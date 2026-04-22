from __future__ import annotations

from typing import Any

import frappe
from frappe.utils import flt

from ashan_cn_procurement.constants.restrictions import (
    FIELD_RESTRICTION_NOTE,
    REMARK_MAX_LENGTH,
)
from ashan_cn_procurement.services.restriction_service import (
    build_restriction_context,
    collect_procurement_source_refs,
    sync_restriction_fields,
)
from ashan_cn_procurement.utils.biz_mode import normalize_biz_mode
from ashan_cn_procurement.utils.line_math import CalculationMode, calculate_line_values, infer_calculation_mode
from ashan_cn_procurement.utils.purchase_tax_bridge import sync_purchase_tax_bridge
from ashan_cn_procurement.utils.text_normalization import normalize_multiline_text, normalize_single_line_text

MODE_TO_FIELD = {
    CalculationMode.NET_RATE: "rate",
    CalculationMode.GROSS_RATE: "custom_gross_rate",
    CalculationMode.NET_AMOUNT: "amount",
    CalculationMode.GROSS_AMOUNT: "custom_gross_amount",
}

FALLBACK_MODE_ORDER = [
    CalculationMode.NET_RATE,
    CalculationMode.GROSS_RATE,
    CalculationMode.NET_AMOUNT,
    CalculationMode.GROSS_AMOUNT,
]

RESTRICTION_CONTEXT_FIELDS = [
    "custom_is_restricted_doc",
    "custom_restriction_group",
    "custom_restriction_root_doctype",
    "custom_restriction_root_name",
    "custom_restriction_note",
]

PURCHASE_INVOICE_ALLOWED_TYPES = {
    "专用发票",
    "普通发票",
    "无发票",
}
PURCHASE_INVOICE_BILL_NO_REQUIRED_TYPES = {
    "专用发票",
    "普通发票",
}
PURCHASE_INVOICE_NO_INVOICE_TYPE = "无发票"


def has_input_value(value: Any) -> bool:
    return value not in (None, "")


def validate_procurement_doc(doc: Any, method: str | None = None) -> None:
    current_biz_mode = getattr(doc, "custom_biz_mode", None)
    if hasattr(doc, "custom_biz_mode") and current_biz_mode not in (None, ""):
        normalized_biz_mode = normalize_biz_mode(current_biz_mode)
        if not normalized_biz_mode:
            frappe.throw(f"不支持的业务模式：{current_biz_mode}")
        doc.custom_biz_mode = normalized_biz_mode

    try:
        normalize_purchase_invoice_bill_no(doc)
    except ValueError as exc:
        frappe.throw(str(exc))

    try:
        sync_restriction_fields(
            doc,
            source_contexts=get_procurement_source_contexts(doc),
            current_doctype=getattr(doc, "doctype", None),
            current_name=get_current_doc_name(doc),
        )
    except ValueError as exc:
        frappe.throw(str(exc))

    if hasattr(doc, FIELD_RESTRICTION_NOTE):
        doc.custom_restriction_note = normalize_multiline_text(getattr(doc, FIELD_RESTRICTION_NOTE, ""))

    for row in getattr(doc, "items", []) or []:
        normalize_procurement_row_text(row)
        recalculate_procurement_row(row)

    sync_purchase_tax_bridge(doc, frappe_module=frappe)



def normalize_purchase_invoice_bill_no(doc: Any) -> None:
    if getattr(doc, "doctype", None) != "Purchase Invoice":
        return

    invoice_type = normalize_single_line_text(getattr(doc, "custom_invoice_type", ""), max_length=REMARK_MAX_LENGTH)
    bill_no = normalize_single_line_text(getattr(doc, "bill_no", ""), max_length=REMARK_MAX_LENGTH)

    if not invoice_type:
        if bill_no == "0":
            doc.custom_invoice_type = PURCHASE_INVOICE_NO_INVOICE_TYPE
            doc.bill_no = ""
            return
        raise ValueError("采购发票必须选择发票类型")

    if invoice_type not in PURCHASE_INVOICE_ALLOWED_TYPES:
        raise ValueError(f"不支持的发票类型：{invoice_type}")

    if bill_no == "0":
        bill_no = ""

    doc.custom_invoice_type = invoice_type

    if invoice_type == PURCHASE_INVOICE_NO_INVOICE_TYPE:
        if bill_no:
            raise ValueError("无发票时发票号必须留空")
        doc.bill_no = ""
        return

    if invoice_type in PURCHASE_INVOICE_BILL_NO_REQUIRED_TYPES and not bill_no:
        raise ValueError(f"{invoice_type}时发票号必填")

    doc.bill_no = bill_no



def get_current_doc_name(doc: Any) -> str | None:
    name = getattr(doc, "name", None)
    if not name:
        return None
    name = str(name)
    return None if name.startswith("new-") else name


def get_procurement_source_contexts(doc: Any) -> list[dict[str, Any]]:
    contexts: list[dict[str, Any]] = []
    if not hasattr(frappe, "get_cached_value"):
        return contexts

    for source_doctype, source_name in collect_procurement_source_refs(doc):
        cached_values = frappe.get_cached_value(source_doctype, source_name, RESTRICTION_CONTEXT_FIELDS)
        if not cached_values:
            continue
        if isinstance(cached_values, dict):
            values_map = cached_values
        else:
            values_map = dict(zip(RESTRICTION_CONTEXT_FIELDS, cached_values, strict=False))
        contexts.append(build_restriction_context(values_map))
    return contexts


def normalize_procurement_row_text(row: Any) -> None:
    if hasattr(row, "custom_spec_model"):
        row.custom_spec_model = normalize_single_line_text(getattr(row, "custom_spec_model", ""), max_length=REMARK_MAX_LENGTH)
    if hasattr(row, "custom_line_remark"):
        row.custom_line_remark = normalize_single_line_text(getattr(row, "custom_line_remark", ""), max_length=REMARK_MAX_LENGTH)


def recalculate_procurement_row(row: Any) -> None:
    qty = flt(getattr(row, "qty", 0))
    if qty <= 0:
        return

    row_dict = row.as_dict() if hasattr(row, "as_dict") else dict(row)
    mode = infer_calculation_mode(row_dict)
    mode, basis_value = resolve_mode_and_value(row, mode)
    if basis_value is None:
        return

    tax_rate = flt(getattr(row, "custom_tax_rate", 0) or 0)
    values = calculate_line_values(
        qty=qty,
        tax_rate=tax_rate,
        mode=mode,
        basis_value=basis_value,
    )

    row.custom_tax_basis = values["mode"]
    row.rate = flt(values["net_rate"])
    row.amount = flt(values["net_amount"])
    row.custom_gross_rate = flt(values["gross_rate"])
    row.custom_tax_amount = flt(values["tax_amount"])
    row.custom_gross_amount = flt(values["gross_amount"])


def resolve_mode_and_value(row: Any, preferred_mode: CalculationMode) -> tuple[CalculationMode, float | None]:
    preferred_field = MODE_TO_FIELD[preferred_mode]
    preferred_raw = getattr(row, preferred_field, None)
    if has_input_value(preferred_raw):
        return preferred_mode, flt(preferred_raw)

    for mode in FALLBACK_MODE_ORDER:
        fieldname = MODE_TO_FIELD[mode]
        raw_value = getattr(row, fieldname, None)
        if has_input_value(raw_value):
            return mode, flt(raw_value)

    return preferred_mode, None

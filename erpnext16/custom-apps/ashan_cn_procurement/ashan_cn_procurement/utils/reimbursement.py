from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Iterable

from ashan_cn_procurement.constants.restrictions import (
    FIELD_IS_RESTRICTED_DOC,
    FIELD_RESTRICTION_GROUP,
    FIELD_RESTRICTION_NOTE,
    FIELD_RESTRICTION_ROOT_DOCTYPE,
    FIELD_RESTRICTION_ROOT_NAME,
    REMARK_MAX_LENGTH,
    TITLE_MAX_LENGTH,
)
from ashan_cn_procurement.services.restriction_service import sync_restriction_fields
from ashan_cn_procurement.utils.biz_mode import BIZ_MODE_REIMBURSEMENT_REQUEST, normalize_biz_mode
from ashan_cn_procurement.utils.text_normalization import join_single_line_parts, normalize_multiline_text, normalize_single_line_text

AMOUNT_PLACES = Decimal("0.01")
DEFAULT_REIMBURSEMENT_CODE_PREFIX = "BX"
PAYMENT_STATUS_UNPAID = "未付款"
PAYMENT_STATUS_PARTIAL = "部分付款"
PAYMENT_STATUS_PAID = "已付款"


def to_decimal(value: Any) -> Decimal:
    if value in (None, ""):
        return Decimal("0")
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def quantize_amount(value: Any) -> Decimal:
    return to_decimal(value).quantize(AMOUNT_PLACES, rounding=ROUND_HALF_UP)


def compute_line_amount(row: dict[str, Any]) -> Decimal:
    qty = to_decimal(row.get("qty") or 0)
    if qty <= 0:
        qty = Decimal("1")
        row["qty"] = float(qty)

    explicit_amount = row.get("amount")
    if explicit_amount not in (None, ""):
        amount = quantize_amount(explicit_amount)
    else:
        amount = quantize_amount(qty * to_decimal(row.get("rate") or 0))

    row["amount"] = float(amount)
    if row.get("rate") in (None, "") and qty:
        row["rate"] = float((amount / qty).quantize(AMOUNT_PLACES, rounding=ROUND_HALF_UP))
    return amount


def summarize_reimbursement(rows: Iterable[dict[str, Any]], paid_amount: Any = 0) -> dict[str, Any]:
    total_amount = quantize_amount(sum(compute_line_amount(row) for row in rows))
    paid_amount_decimal = quantize_amount(paid_amount)
    outstanding_amount = quantize_amount(total_amount - paid_amount_decimal)

    if paid_amount_decimal <= 0:
        payment_status = PAYMENT_STATUS_UNPAID
    elif paid_amount_decimal >= total_amount:
        payment_status = PAYMENT_STATUS_PAID
        outstanding_amount = Decimal("0.00")
    else:
        payment_status = PAYMENT_STATUS_PARTIAL

    return {
        "total_amount": float(total_amount),
        "paid_amount": float(paid_amount_decimal),
        "outstanding_amount": float(outstanding_amount),
        "payment_status": payment_status,
    }


def build_reimbursement_items_from_purchase_invoice(purchase_invoice: dict[str, Any]) -> list[dict[str, Any]]:
    bill_no = normalize_single_line_text(purchase_invoice.get("bill_no"), max_length=REMARK_MAX_LENGTH)
    supplier = normalize_single_line_text(purchase_invoice.get("supplier"), max_length=REMARK_MAX_LENGTH)
    items = []

    for row in purchase_invoice.get("items") or []:
        qty = row.get("qty") or 0
        gross_rate = row.get("custom_gross_rate") or row.get("rate") or 0
        gross_amount = row.get("custom_gross_amount") or row.get("amount") or 0
        items.append(
            {
                "item_name": normalize_single_line_text(
                    row.get("item_name") or row.get("description") or row.get("item_code"),
                    max_length=REMARK_MAX_LENGTH,
                ),
                "custom_spec_model": normalize_single_line_text(row.get("custom_spec_model"), max_length=REMARK_MAX_LENGTH),
                "qty": qty,
                "uom": row.get("uom"),
                "rate": gross_rate,
                "amount": gross_amount,
                "custom_line_remark": normalize_single_line_text(row.get("custom_line_remark"), max_length=REMARK_MAX_LENGTH),
                "invoice_no": bill_no,
                "supplier": supplier,
                "source_pi": purchase_invoice.get("name"),
                "source_pi_item": row.get("name"),
            }
        )

    return items


def build_reimbursement_request_from_purchase_invoice(purchase_invoice: dict[str, Any]) -> dict[str, Any]:
    items = build_reimbursement_items_from_purchase_invoice(purchase_invoice)
    summary = summarize_reimbursement(items)
    bill_no = normalize_single_line_text(purchase_invoice.get("bill_no") or purchase_invoice.get("name"), max_length=REMARK_MAX_LENGTH)
    supplier = normalize_single_line_text(purchase_invoice.get("supplier"), max_length=REMARK_MAX_LENGTH)
    title = join_single_line_parts([supplier, bill_no], max_length=TITLE_MAX_LENGTH) or normalize_single_line_text(
        purchase_invoice.get("name") or "报销单",
        max_length=TITLE_MAX_LENGTH,
    )

    restriction_payload = {
        FIELD_IS_RESTRICTED_DOC: purchase_invoice.get(FIELD_IS_RESTRICTED_DOC, 0),
        FIELD_RESTRICTION_GROUP: purchase_invoice.get(FIELD_RESTRICTION_GROUP),
        FIELD_RESTRICTION_ROOT_DOCTYPE: purchase_invoice.get(FIELD_RESTRICTION_ROOT_DOCTYPE),
        FIELD_RESTRICTION_ROOT_NAME: purchase_invoice.get(FIELD_RESTRICTION_ROOT_NAME),
        FIELD_RESTRICTION_NOTE: purchase_invoice.get(FIELD_RESTRICTION_NOTE),
    }
    restriction_context = sync_restriction_fields(
        restriction_payload,
        current_doctype="Purchase Invoice",
        current_name=purchase_invoice.get("name"),
    )

    payload = {
        "doctype": "Reimbursement Request",
        "company": purchase_invoice.get("company"),
        "posting_date": purchase_invoice.get("bill_date") or purchase_invoice.get("posting_date"),
        "custom_biz_mode": normalize_biz_mode(
            purchase_invoice.get("custom_biz_mode"),
            default=BIZ_MODE_REIMBURSEMENT_REQUEST,
        ),
        "employee": purchase_invoice.get("employee"),
        "employee_name": purchase_invoice.get("employee_name"),
        "department": purchase_invoice.get("department"),
        "source_purchase_invoice": purchase_invoice.get("name"),
        "title": title,
        "invoice_items": items,
        **summary,
    }
    if restriction_context["is_restricted"]:
        payload.update(restriction_payload)
    else:
        payload[FIELD_IS_RESTRICTED_DOC] = 0
        payload[FIELD_RESTRICTION_GROUP] = ""
        payload[FIELD_RESTRICTION_ROOT_DOCTYPE] = ""
        payload[FIELD_RESTRICTION_ROOT_NAME] = ""
        payload[FIELD_RESTRICTION_NOTE] = normalize_multiline_text(purchase_invoice.get(FIELD_RESTRICTION_NOTE))
    return payload

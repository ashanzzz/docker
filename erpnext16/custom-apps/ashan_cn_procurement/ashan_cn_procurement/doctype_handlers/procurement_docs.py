from __future__ import annotations

from typing import Any

from frappe.utils import flt

from ashan_cn_procurement.utils.line_math import CalculationMode, calculate_line_values, infer_calculation_mode

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


def has_input_value(value: Any) -> bool:
    return value not in (None, "")


def validate_procurement_doc(doc: Any, method: str | None = None) -> None:
    for row in getattr(doc, "items", []) or []:
        recalculate_procurement_row(row)


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

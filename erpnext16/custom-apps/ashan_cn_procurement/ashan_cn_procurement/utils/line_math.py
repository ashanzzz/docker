from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from enum import StrEnum
from typing import Final

RATE_PLACES: Final[Decimal] = Decimal("0.000001")
AMOUNT_PLACES: Final[Decimal] = Decimal("0.01")
ONE_HUNDRED: Final[Decimal] = Decimal("100")


class CalculationMode(StrEnum):
    NET_RATE = "net_rate"
    GROSS_RATE = "gross_rate"
    NET_AMOUNT = "net_amount"
    GROSS_AMOUNT = "gross_amount"


@dataclass(frozen=True)
class LineComputation:
    qty: Decimal
    tax_rate: Decimal
    mode: CalculationMode
    basis_value: Decimal
    net_rate: Decimal
    gross_rate: Decimal
    net_amount: Decimal
    tax_amount: Decimal
    gross_amount: Decimal

    def as_dict(self) -> dict[str, Decimal | str]:
        return {
            "qty": self.qty,
            "tax_rate": self.tax_rate,
            "mode": self.mode.value,
            "basis_value": self.basis_value,
            "net_rate": self.net_rate,
            "gross_rate": self.gross_rate,
            "net_amount": self.net_amount,
            "tax_amount": self.tax_amount,
            "gross_amount": self.gross_amount,
        }


def quantize_rate(value: Decimal) -> Decimal:
    return Decimal(value).quantize(RATE_PLACES, rounding=ROUND_HALF_UP)


def quantize_amount(value: Decimal) -> Decimal:
    return Decimal(value).quantize(AMOUNT_PLACES, rounding=ROUND_HALF_UP)


def has_meaningful_value(value: object) -> bool:
    if value is None:
        return False
    if isinstance(value, str) and not value.strip():
        return False
    try:
        return to_decimal(value) != 0
    except Exception:
        return False


def infer_calculation_mode(row: dict[str, object]) -> CalculationMode:
    explicit_basis = row.get("custom_tax_basis")
    if explicit_basis:
        return CalculationMode(str(explicit_basis))

    if has_meaningful_value(row.get("custom_gross_amount")) and not has_meaningful_value(row.get("amount")):
        return CalculationMode.GROSS_AMOUNT
    if has_meaningful_value(row.get("custom_gross_rate")) and not has_meaningful_value(row.get("rate")):
        return CalculationMode.GROSS_RATE
    if has_meaningful_value(row.get("amount")) and not has_meaningful_value(row.get("rate")):
        return CalculationMode.NET_AMOUNT
    return CalculationMode.NET_RATE


def to_decimal(value: Decimal | int | float | str) -> Decimal:
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def calculate_line_values(
    *,
    qty: Decimal | int | float | str,
    tax_rate: Decimal | int | float | str,
    mode: CalculationMode | str,
    basis_value: Decimal | int | float | str,
) -> dict[str, Decimal | str]:
    qty_decimal = to_decimal(qty)
    tax_rate_decimal = to_decimal(tax_rate)
    basis_decimal = to_decimal(basis_value)
    mode_enum = CalculationMode(mode)

    if qty_decimal <= 0:
        raise ValueError("qty must be greater than zero")
    if tax_rate_decimal < 0:
        raise ValueError("tax_rate cannot be negative")
    if basis_decimal < 0:
        raise ValueError("basis_value cannot be negative")

    tax_multiplier = Decimal("1") + (tax_rate_decimal / ONE_HUNDRED)

    if mode_enum == CalculationMode.NET_RATE:
        net_rate = quantize_rate(basis_decimal)
        net_amount = quantize_amount(qty_decimal * net_rate)
        tax_amount = quantize_amount(net_amount * (tax_rate_decimal / ONE_HUNDRED))
        gross_amount = quantize_amount(net_amount + tax_amount)
        gross_rate = quantize_rate(gross_amount / qty_decimal)
    elif mode_enum == CalculationMode.GROSS_RATE:
        gross_rate = quantize_rate(basis_decimal)
        gross_amount = quantize_amount(qty_decimal * gross_rate)
        net_amount = quantize_amount(gross_amount / tax_multiplier)
        tax_amount = quantize_amount(gross_amount - net_amount)
        net_rate = quantize_rate(net_amount / qty_decimal)
    elif mode_enum == CalculationMode.NET_AMOUNT:
        net_amount = quantize_amount(basis_decimal)
        net_rate = quantize_rate(net_amount / qty_decimal)
        tax_amount = quantize_amount(net_amount * (tax_rate_decimal / ONE_HUNDRED))
        gross_amount = quantize_amount(net_amount + tax_amount)
        gross_rate = quantize_rate(gross_amount / qty_decimal)
    elif mode_enum == CalculationMode.GROSS_AMOUNT:
        gross_amount = quantize_amount(basis_decimal)
        gross_rate = quantize_rate(gross_amount / qty_decimal)
        net_amount = quantize_amount(gross_amount / tax_multiplier)
        tax_amount = quantize_amount(gross_amount - net_amount)
        net_rate = quantize_rate(net_amount / qty_decimal)
    else:
        raise ValueError(f"unsupported calculation mode: {mode_enum}")

    return LineComputation(
        qty=quantize_rate(qty_decimal),
        tax_rate=quantize_rate(tax_rate_decimal),
        mode=mode_enum,
        basis_value=quantize_amount(basis_decimal) if "amount" in mode_enum.value else quantize_rate(basis_decimal),
        net_rate=net_rate,
        gross_rate=gross_rate,
        net_amount=net_amount,
        tax_amount=tax_amount,
        gross_amount=gross_amount,
    ).as_dict()

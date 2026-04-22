from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Iterable

AMOUNT_PLACES = Decimal("0.01")
RATIO_PLACES = Decimal("0.000001")

INVOICE_STATUS_UNINVOICED = "未开票"
INVOICE_STATUS_PARTIAL = "部分开票"
INVOICE_STATUS_INVOICED = "已开票"


def to_decimal(value: Any) -> Decimal:
    if value in (None, ""):
        return Decimal("0")
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def quantize_amount(value: Any) -> Decimal:
    return to_decimal(value).quantize(AMOUNT_PLACES, rounding=ROUND_HALF_UP)


def quantize_ratio(value: Any) -> Decimal:
    return to_decimal(value).quantize(RATIO_PLACES, rounding=ROUND_HALF_UP)


def mask_card_number(card_no: Any) -> str:
    raw = str(card_no or "").strip()
    if len(raw) <= 4:
        return raw
    return f"{'*' * (len(raw) - 4)}{raw[-4:]}"


def compute_recharge_metrics(recharge_amount: Any, bonus_amount: Any = 0) -> dict[str, float]:
    recharge_amount_decimal = quantize_amount(recharge_amount)
    bonus_amount_decimal = quantize_amount(bonus_amount)
    if recharge_amount_decimal < 0 or bonus_amount_decimal < 0:
        raise ValueError("充值金额和赠送金额不能为负数")

    effective_amount = quantize_amount(recharge_amount_decimal + bonus_amount_decimal)
    if effective_amount <= 0:
        invoiceable_ratio = Decimal("0")
        discount_ratio = Decimal("0")
    else:
        invoiceable_ratio = quantize_ratio(recharge_amount_decimal / effective_amount * Decimal("100"))
        discount_ratio = quantize_ratio(bonus_amount_decimal / effective_amount * Decimal("100"))

    return {
        "recharge_amount": float(recharge_amount_decimal),
        "bonus_amount": float(bonus_amount_decimal),
        "effective_amount": float(effective_amount),
        "invoiceable_ratio": float(invoiceable_ratio),
        "discount_ratio": float(discount_ratio),
    }


def derive_invoice_status(invoiceable_basis_amount: Any, invoiced_amount: Any) -> tuple[Decimal, str]:
    invoiceable_basis_decimal = quantize_amount(invoiceable_basis_amount)
    invoiced_amount_decimal = quantize_amount(invoiced_amount)
    uninvoiced_amount = quantize_amount(max(invoiceable_basis_decimal - invoiced_amount_decimal, Decimal("0")))

    if invoiceable_basis_decimal <= 0 or invoiced_amount_decimal >= invoiceable_basis_decimal:
        return uninvoiced_amount, INVOICE_STATUS_INVOICED
    if invoiced_amount_decimal <= 0:
        return uninvoiced_amount, INVOICE_STATUS_UNINVOICED
    return uninvoiced_amount, INVOICE_STATUS_PARTIAL


def compute_refuel_metrics(
    *,
    amount: Any,
    liters: Any,
    odometer: Any,
    previous_odometer: Any = None,
    invoiceable_ratio: Any = 100,
    invoiced_amount: Any = 0,
) -> dict[str, float | str | int]:
    amount_decimal = quantize_amount(amount)
    liters_decimal = to_decimal(liters)
    odometer_decimal = to_decimal(odometer)
    previous_odometer_decimal = to_decimal(previous_odometer) if previous_odometer not in (None, "") else None
    invoiceable_ratio_decimal = quantize_ratio(invoiceable_ratio)

    if amount_decimal <= 0:
        raise ValueError("金额必须大于 0")
    if liters_decimal <= 0:
        raise ValueError("升数必须大于 0")
    if previous_odometer_decimal is not None and odometer_decimal < previous_odometer_decimal:
        raise ValueError("当前里程不能小于上次里程")

    unit_price = quantize_amount(amount_decimal / liters_decimal)
    invoiceable_basis_amount = quantize_amount(amount_decimal * invoiceable_ratio_decimal / Decimal("100"))
    allocated_discount_amount = quantize_amount(amount_decimal - invoiceable_basis_amount)
    uninvoiced_amount, invoice_status = derive_invoice_status(invoiceable_basis_amount, invoiced_amount)

    distance_since_last = 0
    km_per_liter = Decimal("0")
    liter_per_100km = Decimal("0")
    if previous_odometer_decimal is not None:
        distance_since_last = int(odometer_decimal - previous_odometer_decimal)
        if distance_since_last > 0:
            km_per_liter = quantize_amount(Decimal(distance_since_last) / liters_decimal)
            liter_per_100km = quantize_amount(liters_decimal / Decimal(distance_since_last) * Decimal("100"))

    return {
        "distance_since_last": distance_since_last,
        "unit_price": float(unit_price),
        "invoiceable_basis_amount": float(invoiceable_basis_amount),
        "allocated_discount_amount": float(allocated_discount_amount),
        "uninvoiced_amount": float(uninvoiced_amount),
        "invoice_status": invoice_status,
        "km_per_liter": float(km_per_liter),
        "liter_per_100km": float(liter_per_100km),
    }


def summarize_invoice_batch_items(rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
    normalized_rows: list[dict[str, Any]] = []
    total_amount = Decimal("0")
    discount_total_amount = Decimal("0")

    for row in rows:
        invoiceable_basis_amount = quantize_amount(row.get("invoiceable_basis_amount"))
        already_invoiced_amount = quantize_amount(row.get("already_invoiced_amount"))
        available_amount = quantize_amount(max(invoiceable_basis_amount - already_invoiced_amount, Decimal("0")))
        invoice_amount_this_time = quantize_amount(row.get("invoice_amount_this_time") or available_amount)
        discount_amount_this_time = quantize_amount(row.get("discount_amount_this_time"))

        if invoice_amount_this_time < 0:
            raise ValueError("本次开票金额不能为负数")
        if invoice_amount_this_time > available_amount:
            raise ValueError("本次开票金额不能大于当前剩余未开票金额")

        remaining_uninvoiced_amount = quantize_amount(available_amount - invoice_amount_this_time)
        normalized_row = dict(row)
        normalized_row["invoice_amount_this_time"] = float(invoice_amount_this_time)
        normalized_row["discount_amount_this_time"] = float(discount_amount_this_time)
        normalized_row["remaining_uninvoiced_amount"] = float(remaining_uninvoiced_amount)
        normalized_rows.append(normalized_row)

        total_amount += invoice_amount_this_time
        discount_total_amount += discount_amount_this_time

    return {
        "items": normalized_rows,
        "total_amount": float(quantize_amount(total_amount)),
        "discount_total_amount": float(quantize_amount(discount_total_amount)),
    }


def allocate_invoiceable_amount_by_fifo(
    *,
    amount: Any,
    recharge_batches: Iterable[dict[str, Any]],
    consumed_amount_before: Any = 0,
) -> float:
    remaining_to_skip = quantize_amount(consumed_amount_before)
    current_amount = quantize_amount(amount)
    invoiceable_basis_amount = Decimal("0")

    for batch in recharge_batches:
        batch_effective_amount = quantize_amount(batch.get("effective_amount"))
        if batch_effective_amount <= 0:
            continue

        batch_ratio = quantize_ratio(batch.get("invoiceable_ratio") if batch.get("invoiceable_ratio") not in (None, "") else 100)

        if remaining_to_skip >= batch_effective_amount:
            remaining_to_skip = quantize_amount(remaining_to_skip - batch_effective_amount)
            continue

        available_in_batch = quantize_amount(batch_effective_amount - remaining_to_skip)
        remaining_to_skip = Decimal("0")
        if current_amount <= 0:
            break

        consume_amount = available_in_batch if available_in_batch <= current_amount else current_amount
        invoiceable_basis_amount += quantize_amount(consume_amount * batch_ratio / Decimal("100"))
        current_amount = quantize_amount(current_amount - consume_amount)

    if current_amount > 0:
        invoiceable_basis_amount += quantize_amount(current_amount)

    return float(quantize_amount(invoiceable_basis_amount))


def compute_oil_card_summary(
    *,
    opening_balance: Any,
    recharge_effective_amounts: Iterable[Any],
    refuel_amounts: Iterable[Any],
    refuel_uninvoiced_amounts: Iterable[Any],
) -> dict[str, float]:
    opening_balance_decimal = quantize_amount(opening_balance)
    total_recharge = quantize_amount(sum(quantize_amount(value) for value in recharge_effective_amounts))
    total_refuel = quantize_amount(sum(quantize_amount(value) for value in refuel_amounts))
    total_uninvoiced = quantize_amount(sum(quantize_amount(value) for value in refuel_uninvoiced_amounts))

    current_balance = quantize_amount(opening_balance_decimal + total_recharge - total_refuel)
    return {
        "current_balance": float(current_balance),
        "uninvoiced_amount": float(total_uninvoiced),
    }

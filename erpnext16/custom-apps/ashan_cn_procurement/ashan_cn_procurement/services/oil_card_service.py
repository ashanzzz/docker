from __future__ import annotations

from typing import Any

from ashan_cn_procurement.utils.oil_card import allocate_invoiceable_amount_by_fifo, compute_oil_card_summary


def _get_frappe():
    import frappe

    return frappe


def get_oil_card_context(oil_card_name: str) -> dict[str, Any]:
    frappe = _get_frappe()
    if not oil_card_name:
        return {}

    return frappe.db.get_value(
        "Oil Card",
        oil_card_name,
        ["name", "company", "supplier", "default_vehicle", "status", "current_balance"],
        as_dict=True,
    ) or {}


def get_latest_vehicle_refuel_snapshot(vehicle: str, exclude_name: str | None = None) -> dict[str, Any]:
    frappe = _get_frappe()
    if not vehicle:
        return {}

    filters: dict[str, Any] = {"vehicle": vehicle, "docstatus": 1}
    if exclude_name:
        filters["name"] = ("!=", exclude_name)

    rows = frappe.get_all(
        "Oil Card Refuel Log",
        filters=filters,
        fields=["name", "posting_date", "odometer", "liters", "amount"],
        order_by="posting_date desc, creation desc",
        limit=1,
    )
    return rows[0] if rows else {}


def update_vehicle_last_refuel_fields(vehicle: str, snapshot: dict[str, Any] | None) -> None:
    frappe = _get_frappe()
    if not vehicle:
        return

    values = {
        "custom_last_refuel_date": snapshot.get("posting_date") if snapshot else None,
        "custom_last_refuel_liters": snapshot.get("liters") if snapshot else 0,
        "custom_last_refuel_amount": snapshot.get("amount") if snapshot else 0,
        "custom_last_refuel_odometer": snapshot.get("odometer") if snapshot else 0,
    }
    frappe.db.set_value("Vehicle", vehicle, values, update_modified=False)


def get_recharge_batches(oil_card_name: str) -> list[dict[str, Any]]:
    frappe = _get_frappe()
    if not oil_card_name:
        return []

    return frappe.get_all(
        "Oil Card Recharge",
        filters={"oil_card": oil_card_name, "docstatus": 1},
        fields=["posting_date", "effective_amount", "invoiceable_ratio"],
        order_by="posting_date asc, creation asc",
        limit=0,
    )


def get_consumed_amount_before(oil_card_name: str, posting_date: Any, exclude_name: str | None = None) -> float:
    frappe = _get_frappe()
    if not oil_card_name or not posting_date:
        return 0.0

    rows = frappe.get_all(
        "Oil Card Refuel Log",
        filters={"oil_card": oil_card_name, "docstatus": 1, "posting_date": ("<", posting_date)},
        fields=["name", "amount"],
        order_by="posting_date asc, creation asc",
        limit=0,
    )
    total = 0.0
    for row in rows:
        if exclude_name and row.get("name") == exclude_name:
            continue
        total += float(row.get("amount") or 0)
    return total


def compute_refuel_invoiceable_basis(oil_card_name: str, posting_date: Any, amount: Any, exclude_name: str | None = None) -> float:
    recharge_batches = get_recharge_batches(oil_card_name)
    consumed_amount_before = get_consumed_amount_before(oil_card_name, posting_date, exclude_name=exclude_name)
    return allocate_invoiceable_amount_by_fifo(
        amount=amount,
        recharge_batches=recharge_batches,
        consumed_amount_before=consumed_amount_before,
    )


def refresh_oil_card_summary(oil_card_name: str) -> dict[str, float]:
    frappe = _get_frappe()
    if not oil_card_name:
        return {"current_balance": 0.0, "uninvoiced_amount": 0.0}

    oil_card = frappe.db.get_value(
        "Oil Card",
        oil_card_name,
        ["opening_balance"],
        as_dict=True,
    )
    if not oil_card:
        return {"current_balance": 0.0, "uninvoiced_amount": 0.0}

    recharges = frappe.get_all(
        "Oil Card Recharge",
        filters={"oil_card": oil_card_name, "docstatus": 1},
        fields=["effective_amount"],
        limit=0,
    )
    refuels = frappe.get_all(
        "Oil Card Refuel Log",
        filters={"oil_card": oil_card_name, "docstatus": 1},
        fields=["amount", "uninvoiced_amount"],
        limit=0,
    )

    summary = compute_oil_card_summary(
        opening_balance=oil_card.get("opening_balance"),
        recharge_effective_amounts=[row.get("effective_amount") for row in recharges],
        refuel_amounts=[row.get("amount") for row in refuels],
        refuel_uninvoiced_amounts=[row.get("uninvoiced_amount") for row in refuels],
    )
    frappe.db.set_value(
        "Oil Card",
        oil_card_name,
        {
            "current_balance": summary["current_balance"],
            "uninvoiced_amount": summary["uninvoiced_amount"],
        },
        update_modified=False,
    )
    return summary

from __future__ import annotations

import frappe
from frappe.model.document import Document

from ashan_cn_procurement.services.oil_card_service import (
    compute_refuel_invoiceable_basis,
    get_latest_vehicle_refuel_snapshot,
    get_oil_card_context,
    refresh_oil_card_summary,
    update_vehicle_last_refuel_fields,
)
from ashan_cn_procurement.utils.oil_card import compute_refuel_metrics


class OilCardRefuelLog(Document):
    def validate(self) -> None:
        context = get_oil_card_context(self.oil_card)
        if not context:
            frappe.throw("请选择有效的油卡")

        self.company = context.get("company")
        self.supplier = context.get("supplier")
        if not self.vehicle and context.get("default_vehicle"):
            self.vehicle = context.get("default_vehicle")
        if not self.vehicle:
            frappe.throw("请选择车辆")

        vehicle_context = frappe.db.get_value("Vehicle", self.vehicle, ["company", "employee"], as_dict=True) or {}
        vehicle_company = vehicle_context.get("company")
        if vehicle_company and self.company and vehicle_company != self.company:
            frappe.throw("油卡所属公司与车辆所属公司不一致，不能保存")
        if not self.driver_employee and vehicle_context.get("employee"):
            self.driver_employee = vehicle_context.get("employee")

        previous_snapshot = get_latest_vehicle_refuel_snapshot(self.vehicle, exclude_name=self.name)
        self.previous_odometer = previous_snapshot.get("odometer") if previous_snapshot else None
        self.previous_refuel_date = previous_snapshot.get("posting_date") if previous_snapshot else None
        self.previous_liters = previous_snapshot.get("liters") if previous_snapshot else 0

        invoiceable_basis_amount = compute_refuel_invoiceable_basis(
            self.oil_card,
            self.posting_date,
            self.amount,
            exclude_name=self.name,
        )
        invoiceable_ratio = (invoiceable_basis_amount / float(self.amount) * 100) if float(self.amount or 0) else 100
        metrics = compute_refuel_metrics(
            amount=self.amount,
            liters=self.liters,
            odometer=self.odometer,
            previous_odometer=self.previous_odometer,
            invoiceable_ratio=invoiceable_ratio,
            invoiced_amount=self.invoiced_amount or 0,
        )

        self.distance_since_last = metrics["distance_since_last"]
        self.unit_price = metrics["unit_price"]
        self.invoiceable_basis_amount = metrics["invoiceable_basis_amount"]
        self.allocated_discount_amount = metrics["allocated_discount_amount"]
        self.uninvoiced_amount = metrics["uninvoiced_amount"]
        self.invoice_status = metrics["invoice_status"]
        self.km_per_liter = metrics["km_per_liter"]
        self.liter_per_100km = metrics["liter_per_100km"]

        if float(context.get("current_balance") or 0) < float(self.amount or 0) and self.docstatus != 2:
            frappe.throw("当前油卡余额不足，不能保存本次加油记录")

    def on_submit(self) -> None:
        refresh_oil_card_summary(self.oil_card)
        update_vehicle_last_refuel_fields(
            self.vehicle,
            {
                "posting_date": self.posting_date,
                "liters": self.liters,
                "amount": self.amount,
                "odometer": self.odometer,
            },
        )

    def on_cancel(self) -> None:
        refresh_oil_card_summary(self.oil_card)
        previous_snapshot = get_latest_vehicle_refuel_snapshot(self.vehicle, exclude_name=self.name)
        update_vehicle_last_refuel_fields(self.vehicle, previous_snapshot or None)

from __future__ import annotations

import frappe
from frappe.model.document import Document

from ashan_cn_procurement.services.oil_card_service import get_oil_card_context, refresh_oil_card_summary
from ashan_cn_procurement.utils.oil_card import compute_recharge_metrics


class OilCardRecharge(Document):
    def validate(self) -> None:
        context = get_oil_card_context(self.oil_card)
        if not context:
            frappe.throw("请选择有效的油卡")

        self.company = context.get("company")
        self.supplier = context.get("supplier")

        metrics = compute_recharge_metrics(self.recharge_amount, self.bonus_amount)
        self.recharge_amount = metrics["recharge_amount"]
        self.bonus_amount = metrics["bonus_amount"]
        self.effective_amount = metrics["effective_amount"]
        self.invoiceable_ratio = metrics["invoiceable_ratio"]
        self.discount_ratio = metrics["discount_ratio"]

        if self.recharge_amount <= 0:
            frappe.throw("充值金额必须大于 0")

        self.status = "Submitted" if self.docstatus == 1 else "Draft"

    def on_submit(self) -> None:
        self.db_set("status", "Submitted", update_modified=False)
        refresh_oil_card_summary(self.oil_card)

    def on_cancel(self) -> None:
        self.db_set("status", "Cancelled", update_modified=False)
        refresh_oil_card_summary(self.oil_card)

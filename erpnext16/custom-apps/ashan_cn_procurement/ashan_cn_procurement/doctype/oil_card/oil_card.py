from __future__ import annotations

import frappe
from frappe.model.document import Document

from ashan_cn_procurement.services.oil_card_service import refresh_oil_card_summary
from ashan_cn_procurement.utils.oil_card import mask_card_number


class OilCard(Document):
    def validate(self) -> None:
        self.card_name = (self.card_name or "").strip()
        self.card_no = (self.card_no or "").strip()
        self.card_no_masked = mask_card_number(self.card_no)
        self.opening_balance = float(self.opening_balance or 0)

        if self.valid_from and self.valid_upto and self.valid_from > self.valid_upto:
            frappe.throw("启用日期不能晚于截止日期")

        summary = refresh_oil_card_summary(self.name) if self.name and not str(self.name).startswith("new-") else None
        if summary:
            self.current_balance = summary["current_balance"]
            self.uninvoiced_amount = summary["uninvoiced_amount"]
        else:
            self.current_balance = float(self.opening_balance or 0)
            self.uninvoiced_amount = float(self.uninvoiced_amount or 0)

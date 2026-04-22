from __future__ import annotations

from frappe.model.document import Document

from ashan_cn_procurement.utils.oil_card import summarize_invoice_batch_items


class OilCardInvoiceBatch(Document):
    def validate(self) -> None:
        summary = summarize_invoice_batch_items([row.as_dict() if hasattr(row, "as_dict") else dict(row) for row in (self.items or [])])
        for row, normalized in zip(self.items or [], summary["items"]):
            row.invoice_amount_this_time = normalized["invoice_amount_this_time"]
            row.discount_amount_this_time = normalized["discount_amount_this_time"]
            row.remaining_uninvoiced_amount = normalized["remaining_uninvoiced_amount"]

        self.total_amount = summary["total_amount"]
        self.discount_total_amount = summary["discount_total_amount"]
        self.status = "Invoiced" if self.purchase_invoice else "Draft"

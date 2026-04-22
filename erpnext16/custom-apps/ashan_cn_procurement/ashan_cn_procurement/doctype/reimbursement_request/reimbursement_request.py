from __future__ import annotations

import frappe
from frappe.model.document import Document
from frappe.model.naming import make_autoname

from ashan_cn_procurement.constants.restrictions import FIELD_RESTRICTION_NOTE, REMARK_MAX_LENGTH, TITLE_MAX_LENGTH
from ashan_cn_procurement.services.restriction_service import sync_restriction_fields
from ashan_cn_procurement.utils.biz_mode import BIZ_MODE_REIMBURSEMENT_REQUEST, normalize_biz_mode
from ashan_cn_procurement.utils.reimbursement import summarize_reimbursement
from ashan_cn_procurement.utils.text_normalization import normalize_multiline_text, normalize_single_line_text


class ReimbursementRequest(Document):
    def autoname(self) -> None:
        self.name = make_autoname("BX-.YYYY.-.#####")

    def validate(self) -> None:
        self.custom_biz_mode = normalize_biz_mode(
            getattr(self, "custom_biz_mode", None),
            default=BIZ_MODE_REIMBURSEMENT_REQUEST,
        )
        if getattr(self, "employee", None):
            employee_context = frappe.db.get_value(
                "Employee",
                self.employee,
                ["employee_name", "department"],
                as_dict=True,
            ) or {}
            self.employee_name = employee_context.get("employee_name") or getattr(self, "employee_name", None)
            self.department = employee_context.get("department") or getattr(self, "department", None)
        self.title = normalize_single_line_text(getattr(self, "title", ""), max_length=TITLE_MAX_LENGTH)
        if hasattr(self, FIELD_RESTRICTION_NOTE):
            self.custom_restriction_note = normalize_multiline_text(getattr(self, FIELD_RESTRICTION_NOTE, ""))

        for row in self.invoice_items or []:
            row.item_name = normalize_single_line_text(getattr(row, "item_name", ""), max_length=REMARK_MAX_LENGTH)
            row.custom_spec_model = normalize_single_line_text(getattr(row, "custom_spec_model", ""), max_length=REMARK_MAX_LENGTH)
            row.custom_line_remark = normalize_single_line_text(getattr(row, "custom_line_remark", ""), max_length=REMARK_MAX_LENGTH)

        try:
            sync_restriction_fields(
                self,
                current_doctype=self.doctype,
                current_name=self.name if self.name and not str(self.name).startswith("new-") else None,
            )
        except ValueError as exc:
            frappe.throw(str(exc))

        summary = summarize_reimbursement(
            [row.as_dict() if hasattr(row, "as_dict") else dict(row) for row in (self.invoice_items or [])],
            paid_amount=self.paid_amount or 0,
        )
        self.total_amount = summary["total_amount"]
        self.paid_amount = summary["paid_amount"]
        self.outstanding_amount = summary["outstanding_amount"]
        self.payment_status = summary["payment_status"]

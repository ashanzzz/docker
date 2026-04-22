import sys
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from ashan_cn_procurement.utils.reimbursement import (
    PAYMENT_STATUS_PARTIAL,
    PAYMENT_STATUS_PAID,
    PAYMENT_STATUS_UNPAID,
    build_reimbursement_request_from_purchase_invoice,
    summarize_reimbursement,
)


class ReimbursementLogicTests(unittest.TestCase):
    def test_build_reimbursement_request_from_purchase_invoice_uses_gross_amounts(self):
        purchase_invoice = {
            "name": "ACC-PINV-2026-00001",
            "company": "天津祺富机械加工有限公司",
            "supplier": "供应商A",
            "bill_no": "FP-001",
            "bill_date": "2026-04-22",
            "posting_date": "2026-04-21",
            "custom_biz_mode": "报销申请",
            "custom_is_restricted_doc": 1,
            "custom_restriction_group": "采购核心组",
            "custom_restriction_root_doctype": "Material Request",
            "custom_restriction_root_name": "MAT-MR-2026-00001",
            "items": [
                {
                    "name": "pi-item-1",
                    "item_name": "物料A",
                    "custom_spec_model": "M8",
                    "qty": 2,
                    "uom": "Nos",
                    "rate": 100,
                    "amount": 200,
                    "custom_gross_rate": 113,
                    "custom_gross_amount": 226,
                    "custom_line_remark": "  备注1\n",
                }
            ],
        }

        doc = build_reimbursement_request_from_purchase_invoice(purchase_invoice)

        self.assertEqual(doc["doctype"], "Reimbursement Request")
        self.assertEqual(doc["posting_date"], "2026-04-22")
        self.assertEqual(doc["source_purchase_invoice"], "ACC-PINV-2026-00001")
        self.assertEqual(doc["custom_biz_mode"], "报销申请")
        self.assertEqual(doc["custom_is_restricted_doc"], 1)
        self.assertEqual(doc["custom_restriction_group"], "采购核心组")
        self.assertEqual(doc["custom_restriction_root_doctype"], "Material Request")
        self.assertEqual(doc["custom_restriction_root_name"], "MAT-MR-2026-00001")
        self.assertEqual(doc["title"], "供应商A / FP-001")
        self.assertEqual(doc["invoice_items"][0]["rate"], 113)
        self.assertEqual(doc["invoice_items"][0]["amount"], 226)
        self.assertEqual(doc["invoice_items"][0]["custom_line_remark"], "备注1")
        self.assertEqual(doc["invoice_items"][0]["source_pi_item"], "pi-item-1")
        self.assertEqual(doc["total_amount"], 226.0)
        self.assertEqual(doc["payment_status"], PAYMENT_STATUS_UNPAID)

    def test_build_reimbursement_request_from_purchase_invoice_preserves_employee_context(self):
        purchase_invoice = {
            "name": "ACC-PINV-2026-00002",
            "company": "天津祺富机械加工有限公司",
            "supplier": "供应商B",
            "bill_no": "FP-002",
            "bill_date": "2026-04-23",
            "employee": "EMP-0001",
            "employee_name": "张三",
            "department": "采购部",
            "items": [
                {
                    "name": "pi-item-2",
                    "item_name": "物料B",
                    "qty": 1,
                    "uom": "Nos",
                    "rate": 88,
                    "amount": 88,
                }
            ],
        }

        doc = build_reimbursement_request_from_purchase_invoice(purchase_invoice)

        self.assertEqual(doc["employee"], "EMP-0001")
        self.assertEqual(doc["employee_name"], "张三")
        self.assertEqual(doc["department"], "采购部")

    def test_summarize_reimbursement_calculates_partial_status(self):
        rows = [
            {"qty": 1, "rate": 100},
            {"qty": 2, "rate": 50},
        ]

        summary = summarize_reimbursement(rows, paid_amount=120)

        self.assertEqual(summary["total_amount"], 200.0)
        self.assertEqual(summary["paid_amount"], 120.0)
        self.assertEqual(summary["outstanding_amount"], 80.0)
        self.assertEqual(summary["payment_status"], PAYMENT_STATUS_PARTIAL)

    def test_summarize_reimbursement_marks_paid_when_paid_amount_covers_total(self):
        rows = [{"qty": 1, "rate": 88.8}]

        summary = summarize_reimbursement(rows, paid_amount=100)

        self.assertEqual(summary["payment_status"], PAYMENT_STATUS_PAID)
        self.assertEqual(summary["outstanding_amount"], 0.0)


if __name__ == "__main__":
    unittest.main()

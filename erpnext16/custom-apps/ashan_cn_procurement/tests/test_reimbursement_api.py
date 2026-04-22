import importlib
import sys
import types
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))


class FakePurchaseInvoiceDoc:
    def __init__(self, data):
        self._data = data

    def as_dict(self):
        return dict(self._data)


class FakeInsertedDoc(dict):
    def __init__(self, payload):
        super().__init__(payload)
        self.name = payload.get("name", "BX-2026-00001")

    def insert(self, ignore_permissions=False):
        return self


class ReimbursementApiTests(unittest.TestCase):
    def setUp(self):
        self._original_modules = {name: sys.modules.get(name) for name in ("frappe", "ashan_cn_procurement.api.reimbursement")}
        self.state = {
            "existing": [],
            "purchase_invoice": None,
            "inserted": None,
        }

        frappe_module = types.ModuleType("frappe")
        frappe_module.whitelist = lambda *args, **kwargs: (lambda fn: fn)

        def fake_get_all(doctype, filters=None, pluck=None, limit=None):
            if doctype == "Reimbursement Request":
                if self.state["existing"] and filters.get("source_purchase_invoice"):
                    return self.state["existing"]
                return []
            raise AssertionError(f"Unexpected get_all doctype: {doctype}")

        def fake_get_doc(*args, **kwargs):
            if args[:2] == ("Purchase Invoice", self.state["purchase_invoice"]["name"]):
                return FakePurchaseInvoiceDoc(self.state["purchase_invoice"])
            payload = args[0] if args else kwargs
            inserted = FakeInsertedDoc(payload)
            self.state["inserted"] = inserted
            return inserted

        frappe_module.get_all = fake_get_all
        frappe_module.get_doc = fake_get_doc

        sys.modules["frappe"] = frappe_module
        sys.modules.pop("ashan_cn_procurement.api.reimbursement", None)
        self.module = importlib.import_module("ashan_cn_procurement.api.reimbursement")

    def tearDown(self):
        sys.modules.pop("ashan_cn_procurement.api.reimbursement", None)
        for name, original in self._original_modules.items():
            if original is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = original

    def test_returns_existing_reimbursement_when_already_created(self):
        self.state["existing"] = ["BX-2026-00002"]

        result = self.module.create_reimbursement_from_purchase_invoice("ACC-PINV-2026-00001")

        self.assertEqual(result, {"created": False, "name": "BX-2026-00002", "doctype": "Reimbursement Request"})
        self.assertIsNone(self.state["inserted"])

    def test_creates_reimbursement_from_purchase_invoice(self):
        self.state["purchase_invoice"] = {
            "name": "ACC-PINV-2026-00001",
            "company": "天津祺富机械加工有限公司",
            "supplier": "供应商A",
            "bill_no": "FP-001",
            "bill_date": "2026-04-22",
            "custom_biz_mode": "员工代付",
            "custom_is_restricted_doc": 1,
            "custom_restriction_group": "采购核心组",
            "custom_restriction_root_doctype": "Material Request",
            "custom_restriction_root_name": "MAT-MR-2026-00001",
            "items": [
                {
                    "name": "pi-item-1",
                    "item_name": "物料A",
                    "qty": 1,
                    "uom": "Nos",
                    "custom_gross_rate": 113,
                    "custom_gross_amount": 113,
                }
            ],
        }

        result = self.module.create_reimbursement_from_purchase_invoice("ACC-PINV-2026-00001")

        self.assertTrue(result["created"])
        self.assertEqual(result["doctype"], "Reimbursement Request")
        self.assertEqual(self.state["inserted"]["custom_biz_mode"], "报销申请")
        self.assertEqual(self.state["inserted"]["custom_is_restricted_doc"], 1)
        self.assertEqual(self.state["inserted"]["custom_restriction_group"], "采购核心组")
        self.assertEqual(self.state["inserted"]["custom_restriction_root_doctype"], "Material Request")
        self.assertEqual(self.state["inserted"]["custom_restriction_root_name"], "MAT-MR-2026-00001")
        self.assertEqual(self.state["inserted"]["source_purchase_invoice"], "ACC-PINV-2026-00001")
        self.assertEqual(self.state["inserted"]["invoice_items"][0]["amount"], 113)


if __name__ == "__main__":
    unittest.main()

import importlib
import sys
import types
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))


class OilCardServiceTests(unittest.TestCase):
    def setUp(self):
        self._original_module = sys.modules.get("ashan_cn_procurement.services.oil_card_service")
        sys.modules.pop("ashan_cn_procurement.services.oil_card_service", None)
        self.module = importlib.import_module("ashan_cn_procurement.services.oil_card_service")

    def tearDown(self):
        sys.modules.pop("ashan_cn_procurement.services.oil_card_service", None)
        if self._original_module is not None:
            sys.modules["ashan_cn_procurement.services.oil_card_service"] = self._original_module

    def test_get_oil_card_context_reads_current_balance_for_refuel_validation(self):
        class DummyDB:
            def __init__(self):
                self.calls = []

            def get_value(self, doctype, name, fields, as_dict=False):
                self.calls.append((doctype, name, fields, as_dict))
                return {"name": name, "company": "测试公司", "supplier": "测试供应商", "default_vehicle": "TEST-CAR", "status": "Active", "current_balance": 1050}

        dummy_frappe = types.SimpleNamespace(db=DummyDB())
        self.module._get_frappe = lambda: dummy_frappe

        context = self.module.get_oil_card_context("TEST-OIL-CARD")

        self.assertEqual(context["current_balance"], 1050)
        self.assertIn("current_balance", dummy_frappe.db.calls[0][2])


if __name__ == "__main__":
    unittest.main()

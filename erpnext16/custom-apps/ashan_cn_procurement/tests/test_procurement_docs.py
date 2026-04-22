import sys
import types
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))


class DummyRow:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


class ProcurementDocHandlerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        frappe_module = types.ModuleType("frappe")
        frappe_utils_module = types.ModuleType("frappe.utils")

        def fake_flt(value, *_args, **_kwargs):
            if value in (None, ""):
                return 0.0
            return float(value)

        frappe_utils_module.flt = fake_flt
        frappe_module.utils = frappe_utils_module

        sys.modules.setdefault("frappe", frappe_module)
        sys.modules.setdefault("frappe.utils", frappe_utils_module)

        from ashan_cn_procurement.doctype_handlers.procurement_docs import (  # noqa: PLC0415
            CalculationMode,
            normalize_purchase_invoice_bill_no,
            resolve_mode_and_value,
        )

        cls.CalculationMode = CalculationMode
        cls.resolve_mode_and_value = staticmethod(resolve_mode_and_value)
        cls.normalize_purchase_invoice_bill_no = staticmethod(normalize_purchase_invoice_bill_no)

    def test_zero_value_is_preserved_for_preferred_mode(self):
        row = DummyRow(rate=0, custom_gross_rate=113, amount=None, custom_gross_amount=None)
        mode, value = self.resolve_mode_and_value(row, self.CalculationMode.NET_RATE)
        self.assertEqual(mode, self.CalculationMode.NET_RATE)
        self.assertEqual(value, 0.0)

    def test_purchase_invoice_no_invoice_placeholder_is_migrated_to_blank_bill_no(self):
        doc = DummyRow(doctype="Purchase Invoice", custom_invoice_type="", bill_no="0")

        self.normalize_purchase_invoice_bill_no(doc)

        self.assertEqual(doc.custom_invoice_type, "无发票")
        self.assertEqual(doc.bill_no, "")

    def test_purchase_invoice_regular_types_require_real_bill_no(self):
        doc = DummyRow(doctype="Purchase Invoice", custom_invoice_type="普通发票", bill_no="")

        with self.assertRaises(ValueError):
            self.normalize_purchase_invoice_bill_no(doc)

    def test_purchase_invoice_regular_type_strips_bill_no_whitespace(self):
        doc = DummyRow(doctype="Purchase Invoice", custom_invoice_type="专用发票", bill_no="  FP-001  ")

        self.normalize_purchase_invoice_bill_no(doc)

        self.assertEqual(doc.custom_invoice_type, "专用发票")
        self.assertEqual(doc.bill_no, "FP-001")


if __name__ == "__main__":
    unittest.main()

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
            resolve_mode_and_value,
        )

        cls.CalculationMode = CalculationMode
        cls.resolve_mode_and_value = staticmethod(resolve_mode_and_value)

    def test_zero_value_is_preserved_for_preferred_mode(self):
        row = DummyRow(rate=0, custom_gross_rate=113, amount=None, custom_gross_amount=None)
        mode, value = self.resolve_mode_and_value(row, self.CalculationMode.NET_RATE)
        self.assertEqual(mode, self.CalculationMode.NET_RATE)
        self.assertEqual(value, 0.0)


if __name__ == "__main__":
    unittest.main()

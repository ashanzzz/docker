import importlib
import sys
import types
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))


class WorkDateDefaultsTests(unittest.TestCase):
    def setUp(self):
        self._original_modules = {name: sys.modules.get(name) for name in ("frappe", "frappe.utils")}
        self.calls = []

        frappe_module = types.ModuleType("frappe")
        defaults_namespace = types.SimpleNamespace(
            set_user_default=self.fake_set_user_default,
            clear_user_default=self.fake_clear_user_default,
        )
        frappe_module.defaults = defaults_namespace
        frappe_module.whitelist = lambda *args, **kwargs: (lambda fn: fn)

        frappe_utils_module = types.ModuleType("frappe.utils")

        def fake_getdate(value):
            if value in (None, ""):
                raise ValueError("work_date is required")
            parts = str(value).split("-")
            if len(parts) != 3 or any(not part.isdigit() for part in parts):
                raise ValueError(f"Invalid date: {value}")
            year, month, day = map(int, parts)
            if not (1 <= month <= 12 and 1 <= day <= 31):
                raise ValueError(f"Invalid date: {value}")
            return f"{year:04d}-{month:02d}-{day:02d}"

        frappe_utils_module.getdate = fake_getdate
        frappe_module.utils = frappe_utils_module

        sys.modules["frappe"] = frappe_module
        sys.modules["frappe.utils"] = frappe_utils_module
        sys.modules.pop("ashan_cn_procurement.api.work_date", None)
        self.module = importlib.import_module("ashan_cn_procurement.api.work_date")

    def tearDown(self):
        sys.modules.pop("ashan_cn_procurement.api.work_date", None)
        for name, original in self._original_modules.items():
            if original is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = original

    def fake_set_user_default(self, key, value, *args, **kwargs):
        self.calls.append(("set", key, value))

    def fake_clear_user_default(self, key, *args, **kwargs):
        self.calls.append(("clear", key, None))

    def test_set_work_date_updates_all_supported_default_keys(self):
        result = self.module.set_work_date("2026-04-22")

        self.assertEqual(result["work_date"], "2026-04-22")
        self.assertEqual(result["default_keys"], list(self.module.WORK_DATE_DEFAULT_KEYS))
        self.assertEqual(
            self.calls,
            [("set", key, "2026-04-22") for key in self.module.WORK_DATE_DEFAULT_KEYS],
        )

    def test_clear_work_date_clears_all_supported_default_keys(self):
        result = self.module.clear_work_date()

        self.assertTrue(result["cleared"])
        self.assertEqual(result["default_keys"], list(self.module.WORK_DATE_DEFAULT_KEYS))
        self.assertEqual(
            self.calls,
            [("clear", key, None) for key in self.module.WORK_DATE_DEFAULT_KEYS],
        )

    def test_invalid_work_date_is_rejected(self):
        with self.assertRaises(ValueError):
            self.module.set_work_date("2026-99-99")


if __name__ == "__main__":
    unittest.main()

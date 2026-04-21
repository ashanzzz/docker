import importlib
import sys
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))


class AppLayoutTests(unittest.TestCase):
    def test_frappe_module_package_is_importable(self):
        module = importlib.import_module("ashan_cn_procurement.ashan_cn_procurement")
        self.assertIsNotNone(module)


if __name__ == "__main__":
    unittest.main()

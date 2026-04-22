import sys
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from ashan_cn_procurement.utils.biz_mode import (
    ALLOWED_BIZ_MODES,
    BIZ_MODE_REIMBURSEMENT_REQUEST,
    BIZ_MODE_TELEGRAPHIC_TRANSFER_REQUEST,
    normalize_biz_mode,
)


class BizModeTests(unittest.TestCase):
    def test_normalize_biz_mode_maps_legacy_values(self):
        self.assertEqual(normalize_biz_mode("常规采购"), "采购申请")
        self.assertEqual(normalize_biz_mode("员工代付"), BIZ_MODE_REIMBURSEMENT_REQUEST)
        self.assertEqual(normalize_biz_mode("自办电汇"), BIZ_MODE_TELEGRAPHIC_TRANSFER_REQUEST)

    def test_normalize_biz_mode_rejects_unknown_values(self):
        self.assertIsNone(normalize_biz_mode("神秘模式"))

    def test_allowed_modes_are_stable(self):
        self.assertEqual(ALLOWED_BIZ_MODES, ["采购申请", "报销申请", "电汇申请", "月结补录"])


if __name__ == "__main__":
    unittest.main()

import sys
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from ashan_cn_procurement.utils.text_normalization import (
    join_single_line_parts,
    normalize_multiline_text,
    normalize_single_line_text,
)


class TextNormalizationTests(unittest.TestCase):
    def test_normalize_single_line_text_collapses_whitespace(self):
        self.assertEqual(normalize_single_line_text("  采购   备注\n\t内容  "), "采购 备注 内容")

    def test_normalize_multiline_text_preserves_meaningful_lines(self):
        self.assertEqual(
            normalize_multiline_text("\n 第一行 \n\n\n 第二行\t\n   第三行   \n"),
            "第一行\n\n第二行\n第三行",
        )

    def test_join_single_line_parts_skips_empty_parts(self):
        self.assertEqual(join_single_line_parts([" 供应商A ", "", None, " 发票001 "]), "供应商A / 发票001")


if __name__ == "__main__":
    unittest.main()

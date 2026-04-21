import sys
import unittest
from decimal import Decimal
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from ashan_cn_procurement.utils.line_math import CalculationMode, calculate_line_values


class LineMathTests(unittest.TestCase):
    def test_net_rate_mode(self):
        result = calculate_line_values(
            qty=Decimal("2"),
            tax_rate=Decimal("13"),
            mode=CalculationMode.NET_RATE,
            basis_value=Decimal("100"),
        )

        self.assertEqual(result["net_rate"], Decimal("100.000000"))
        self.assertEqual(result["net_amount"], Decimal("200.00"))
        self.assertEqual(result["tax_amount"], Decimal("26.00"))
        self.assertEqual(result["gross_amount"], Decimal("226.00"))
        self.assertEqual(result["gross_rate"], Decimal("113.000000"))

    def test_gross_rate_mode(self):
        result = calculate_line_values(
            qty=Decimal("2"),
            tax_rate=Decimal("13"),
            mode=CalculationMode.GROSS_RATE,
            basis_value=Decimal("113"),
        )

        self.assertEqual(result["gross_rate"], Decimal("113.000000"))
        self.assertEqual(result["gross_amount"], Decimal("226.00"))
        self.assertEqual(result["net_amount"], Decimal("200.00"))
        self.assertEqual(result["tax_amount"], Decimal("26.00"))
        self.assertEqual(result["net_rate"], Decimal("100.000000"))

    def test_net_amount_mode(self):
        result = calculate_line_values(
            qty=Decimal("3"),
            tax_rate=Decimal("13"),
            mode=CalculationMode.NET_AMOUNT,
            basis_value=Decimal("300"),
        )

        self.assertEqual(result["net_amount"], Decimal("300.00"))
        self.assertEqual(result["net_rate"], Decimal("100.000000"))
        self.assertEqual(result["tax_amount"], Decimal("39.00"))
        self.assertEqual(result["gross_amount"], Decimal("339.00"))
        self.assertEqual(result["gross_rate"], Decimal("113.000000"))

    def test_gross_amount_mode(self):
        result = calculate_line_values(
            qty=Decimal("3"),
            tax_rate=Decimal("13"),
            mode=CalculationMode.GROSS_AMOUNT,
            basis_value=Decimal("339"),
        )

        self.assertEqual(result["gross_amount"], Decimal("339.00"))
        self.assertEqual(result["gross_rate"], Decimal("113.000000"))
        self.assertEqual(result["net_amount"], Decimal("300.00"))
        self.assertEqual(result["tax_amount"], Decimal("39.00"))
        self.assertEqual(result["net_rate"], Decimal("100.000000"))

    def test_infer_mode_prefers_explicit_basis(self):
        from ashan_cn_procurement.utils.line_math import infer_calculation_mode

        self.assertEqual(
            infer_calculation_mode(
                {
                    "custom_tax_basis": "gross_amount",
                    "custom_gross_amount": "339",
                    "amount": "300",
                    "rate": "100",
                }
            ),
            CalculationMode.GROSS_AMOUNT,
        )

    def test_infer_mode_uses_gross_rate_when_only_gross_price_exists(self):
        from ashan_cn_procurement.utils.line_math import infer_calculation_mode

        self.assertEqual(
            infer_calculation_mode(
                {
                    "custom_gross_rate": "113",
                    "custom_gross_amount": None,
                    "amount": None,
                    "rate": None,
                }
            ),
            CalculationMode.GROSS_RATE,
        )

    def test_zero_qty_is_rejected(self):
        with self.assertRaises(ValueError):
            calculate_line_values(
                qty=Decimal("0"),
                tax_rate=Decimal("13"),
                mode=CalculationMode.NET_RATE,
                basis_value=Decimal("100"),
            )


if __name__ == "__main__":
    unittest.main()

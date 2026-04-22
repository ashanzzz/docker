import sys
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from ashan_cn_procurement.utils.oil_card import (
    INVOICE_STATUS_INVOICED,
    INVOICE_STATUS_PARTIAL,
    INVOICE_STATUS_UNINVOICED,
    allocate_invoiceable_amount_by_fifo,
    compute_oil_card_summary,
    compute_recharge_metrics,
    compute_refuel_metrics,
    summarize_invoice_batch_items,
)


class OilCardLogicTests(unittest.TestCase):
    def test_compute_recharge_metrics_splits_recharge_and_bonus(self):
        metrics = compute_recharge_metrics(recharge_amount=4000, bonus_amount=200)

        self.assertEqual(metrics["effective_amount"], 4200.0)
        self.assertAlmostEqual(metrics["invoiceable_ratio"], 95.238095, places=6)
        self.assertAlmostEqual(metrics["discount_ratio"], 4.761905, places=6)

    def test_compute_refuel_metrics_uses_invoiceable_ratio_and_previous_odometer(self):
        metrics = compute_refuel_metrics(
            amount=210,
            liters=30,
            odometer=1300,
            previous_odometer=1000,
            invoiceable_ratio=95.238095,
            invoiced_amount=0,
        )

        self.assertEqual(metrics["distance_since_last"], 300)
        self.assertEqual(metrics["unit_price"], 7.0)
        self.assertEqual(metrics["invoiceable_basis_amount"], 200.0)
        self.assertEqual(metrics["allocated_discount_amount"], 10.0)
        self.assertEqual(metrics["uninvoiced_amount"], 200.0)
        self.assertEqual(metrics["invoice_status"], INVOICE_STATUS_UNINVOICED)
        self.assertEqual(metrics["km_per_liter"], 10.0)
        self.assertEqual(metrics["liter_per_100km"], 10.0)

    def test_compute_refuel_metrics_marks_partial_or_complete_invoice_status(self):
        partial = compute_refuel_metrics(
            amount=210,
            liters=30,
            odometer=1300,
            previous_odometer=1000,
            invoiceable_ratio=95.238095,
            invoiced_amount=120,
        )
        invoiced = compute_refuel_metrics(
            amount=210,
            liters=30,
            odometer=1300,
            previous_odometer=1000,
            invoiceable_ratio=95.238095,
            invoiced_amount=210,
        )

        self.assertEqual(partial["invoice_status"], INVOICE_STATUS_PARTIAL)
        self.assertEqual(partial["uninvoiced_amount"], 80.0)
        self.assertEqual(invoiced["invoice_status"], INVOICE_STATUS_INVOICED)
        self.assertEqual(invoiced["uninvoiced_amount"], 0.0)

    def test_summarize_invoice_batch_items_sums_invoice_and_discount_amounts(self):
        summary = summarize_invoice_batch_items(
            [
                {
                    "invoice_amount_this_time": 100,
                    "discount_amount_this_time": 5,
                    "invoiceable_basis_amount": 100,
                    "already_invoiced_amount": 0,
                    "remaining_uninvoiced_amount": 0,
                },
                {
                    "invoice_amount_this_time": 80,
                    "discount_amount_this_time": 4,
                    "invoiceable_basis_amount": 120,
                    "already_invoiced_amount": 20,
                    "remaining_uninvoiced_amount": 20,
                },
            ]
        )

        self.assertEqual(summary["total_amount"], 180.0)
        self.assertEqual(summary["discount_total_amount"], 9.0)

    def test_allocate_invoiceable_amount_by_fifo_preserves_discount_pool_order(self):
        invoiceable_basis_amount = allocate_invoiceable_amount_by_fifo(
            amount=200,
            recharge_batches=[
                {"effective_amount": 4200, "invoiceable_ratio": 95.238095},
                {"effective_amount": 1000, "invoiceable_ratio": 100},
            ],
            consumed_amount_before=4100,
        )

        self.assertEqual(invoiceable_basis_amount, 195.24)

    def test_compute_oil_card_summary_calculates_balance_and_uninvoiced_totals(self):
        summary = compute_oil_card_summary(
            opening_balance=100,
            recharge_effective_amounts=[4200, 800],
            refuel_amounts=[210, 300],
            refuel_uninvoiced_amounts=[200, 260],
        )

        self.assertEqual(summary["current_balance"], 4590.0)
        self.assertEqual(summary["uninvoiced_amount"], 460.0)


if __name__ == "__main__":
    unittest.main()

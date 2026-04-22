import json
import sys
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))


class FakeRow(dict):
    __getattr__ = dict.get
    __setattr__ = dict.__setitem__


class FakeDoc(FakeRow):
    def append(self, fieldname, value):
        row = FakeRow(value)
        self.setdefault(fieldname, []).append(row)
        return row


class FakeTemplateDoc(FakeRow):
    pass


class FakeInsertedDoc(FakeRow):
    def __init__(self, manager, payload):
        super().__init__(payload)
        self._manager = manager
        self.name = payload.get("title")

    def insert(self, ignore_permissions=False):
        self._manager.inserted_templates[self.name] = self
        return self


class FakeFrappe:
    def __init__(self):
        self.purchase_tax_templates = {}
        self.tax_accounts = []
        self.inserted_templates = {}

    def get_all(self, doctype, filters=None, pluck=None, fields=None, limit=None):
        if doctype == "Item Tax Template":
            matches = [
                name
                for name, doc in self.inserted_templates.items()
                if doc.get("company") == filters.get("company") and doc.get("title") == filters.get("title")
            ]
            return matches if pluck == "name" else [{"name": name} for name in matches]

        if doctype == "Purchase Taxes and Charges Template":
            names = list(self.purchase_tax_templates)
            return names if pluck == "name" else [{"name": name} for name in names]

        if doctype == "Account":
            rows = [row for row in self.tax_accounts if row.get("company") == filters.get("company")]
            if filters.get("account_type"):
                rows = [row for row in rows if row.get("account_type") == filters.get("account_type")]
            if filters.get("root_type"):
                rows = [row for row in rows if row.get("root_type") == filters.get("root_type")]
            return rows if fields else [row.get("name") for row in rows]

        raise AssertionError(f"Unexpected get_all doctype: {doctype}")

    def get_cached_doc(self, doctype, name):
        if doctype == "Purchase Taxes and Charges Template":
            return self.purchase_tax_templates[name]
        if doctype == "Item Tax Template":
            return self.inserted_templates[name]
        raise AssertionError(f"Unexpected get_cached_doc doctype: {doctype}")

    def get_doc(self, payload):
        if payload.get("doctype") != "Item Tax Template":
            raise AssertionError(f"Unexpected get_doc payload: {payload}")
        return FakeInsertedDoc(self, payload)


class PurchaseTaxBridgeTests(unittest.TestCase):
    def setUp(self):
        from ashan_cn_procurement.utils.purchase_tax_bridge import sync_purchase_tax_bridge

        self.sync_purchase_tax_bridge = sync_purchase_tax_bridge
        self.frappe = FakeFrappe()

    def test_sync_purchase_tax_bridge_prefers_existing_tax_row(self):
        doc = FakeDoc(
            doctype="Purchase Invoice",
            company="天津祺富机械加工有限公司",
            custom_invoice_type="专用发票",
            taxes=[
                FakeRow(
                    account_head="VAT - 祺富",
                    charge_type="On Net Total",
                    add_deduct_tax="Add",
                )
            ],
            items=[FakeRow(custom_tax_rate=13), FakeRow(custom_tax_rate=0)],
        )

        account_head = self.sync_purchase_tax_bridge(doc, frappe_module=self.frappe)

        self.assertEqual(account_head, "VAT - 祺富")
        self.assertEqual(json.loads(doc["items"][0].item_tax_rate), {"VAT - 祺富": 13.0})
        self.assertEqual(json.loads(doc["items"][1].item_tax_rate), {"VAT - 祺富": 0.0})
        self.assertEqual(len(self.frappe.inserted_templates), 2)

    def test_sync_purchase_tax_bridge_appends_tax_row_when_needed(self):
        self.frappe.tax_accounts = [
            {
                "name": "VAT - 祺富",
                "account_name": "VAT",
                "account_type": "Tax",
                "company": "天津祺富机械加工有限公司",
            }
        ]
        doc = FakeDoc(
            doctype="Purchase Invoice",
            company="天津祺富机械加工有限公司",
            custom_invoice_type="专用发票",
            taxes=[],
            taxes_and_charges=None,
            items=[FakeRow(custom_tax_rate=13)],
        )

        account_head = self.sync_purchase_tax_bridge(doc, frappe_module=self.frappe)

        self.assertEqual(account_head, "VAT - 祺富")
        self.assertEqual(len(doc.taxes), 1)
        self.assertEqual(doc.taxes[0].account_head, "VAT - 祺富")
        self.assertEqual(doc.taxes[0].set_by_item_tax_template, 1)
        self.assertEqual(doc.taxes[0].category, "Total")
        self.assertEqual(doc.taxes[0].add_deduct_tax, "Add")

    def test_sync_purchase_tax_bridge_uses_selected_master_template_account_head(self):
        self.frappe.purchase_tax_templates["China Tax - 祺富"] = FakeTemplateDoc(
            taxes=[
                FakeRow(
                    account_head="VAT - 祺富",
                    charge_type="On Net Total",
                    add_deduct_tax="Add",
                )
            ]
        )
        doc = FakeDoc(
            doctype="Purchase Invoice",
            company="天津祺富机械加工有限公司",
            custom_invoice_type="专用发票",
            taxes=[],
            taxes_and_charges="China Tax - 祺富",
            items=[FakeRow(custom_tax_rate=13)],
        )

        account_head = self.sync_purchase_tax_bridge(doc, frappe_module=self.frappe)

        self.assertEqual(account_head, "VAT - 祺富")
        self.assertEqual(doc.taxes, [])
        self.assertEqual(json.loads(doc["items"][0].item_tax_rate), {"VAT - 祺富": 13.0})

    def test_sync_purchase_tax_bridge_routes_normal_invoice_tax_to_non_vat_account(self):
        self.frappe.purchase_tax_templates["China Tax - 祺富"] = FakeTemplateDoc(
            taxes=[
                FakeRow(
                    account_head="VAT - 祺富",
                    charge_type="On Net Total",
                    add_deduct_tax="Add",
                )
            ]
        )
        self.frappe.tax_accounts = [
            {
                "name": "VAT - 祺富",
                "account_name": "VAT",
                "account_type": "Tax",
                "company": "天津祺富机械加工有限公司",
                "root_type": "Liability",
            },
            {
                "name": "Tax Expense - 祺富",
                "account_name": "Tax Expense",
                "account_type": "",
                "company": "天津祺富机械加工有限公司",
                "root_type": "Expense",
            },
        ]
        doc = FakeDoc(
            doctype="Purchase Invoice",
            company="天津祺富机械加工有限公司",
            custom_invoice_type="普通发票",
            taxes=[],
            taxes_and_charges="China Tax - 祺富",
            items=[FakeRow(custom_tax_rate=13)],
        )

        account_head = self.sync_purchase_tax_bridge(doc, frappe_module=self.frappe)

        self.assertEqual(account_head, "Tax Expense - 祺富")
        self.assertEqual(json.loads(doc["items"][0].item_tax_rate), {"Tax Expense - 祺富": 13.0})
        self.assertEqual(doc.taxes[0].account_head, "Tax Expense - 祺富")

    def test_sync_purchase_tax_bridge_replaces_auto_vat_row_when_switching_to_normal_invoice(self):
        self.frappe.tax_accounts = [
            {
                "name": "VAT - 祺富",
                "account_name": "VAT",
                "account_type": "Tax",
                "company": "天津祺富机械加工有限公司",
                "root_type": "Liability",
            },
            {
                "name": "Tax Expense - 祺富",
                "account_name": "Tax Expense",
                "account_type": "",
                "company": "天津祺富机械加工有限公司",
                "root_type": "Expense",
            },
        ]
        doc = FakeDoc(
            doctype="Purchase Invoice",
            company="天津祺富机械加工有限公司",
            custom_invoice_type="普通发票",
            taxes=[
                FakeRow(
                    account_head="VAT - 祺富",
                    charge_type="On Net Total",
                    add_deduct_tax="Add",
                    set_by_item_tax_template=1,
                )
            ],
            items=[FakeRow(custom_tax_rate=13)],
        )

        account_head = self.sync_purchase_tax_bridge(doc, frappe_module=self.frappe)

        self.assertEqual(account_head, "Tax Expense - 祺富")
        self.assertEqual([row.account_head for row in doc.taxes], ["Tax Expense - 祺富"])

    def test_sync_purchase_tax_bridge_skips_unsupported_doctype(self):
        doc = FakeDoc(doctype="Material Request", company="天津祺富机械加工有限公司", taxes=[], items=[])

        account_head = self.sync_purchase_tax_bridge(doc, frappe_module=self.frappe)

        self.assertIsNone(account_head)
        self.assertEqual(self.frappe.inserted_templates, {})


if __name__ == "__main__":
    unittest.main()

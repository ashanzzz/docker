import importlib
import json
import sys
import types
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

DOCTYPE_ROOT = APP_ROOT / "ashan_cn_procurement" / "doctype"


def load_doctype_json(name: str) -> dict:
    path = DOCTYPE_ROOT / name / f"{name}.json"
    return json.loads(path.read_text())


class OilCardMetadataTests(unittest.TestCase):
    def setUp(self):
        self._original_modules = {
            name: sys.modules.get(name)
            for name in (
                "frappe",
                "frappe.custom",
                "frappe.custom.doctype",
                "frappe.custom.doctype.custom_field",
                "frappe.custom.doctype.custom_field.custom_field",
            )
        }

        frappe_module = types.ModuleType("frappe")
        frappe_custom_module = types.ModuleType("frappe.custom")
        frappe_custom_doctype_module = types.ModuleType("frappe.custom.doctype")
        frappe_custom_field_pkg = types.ModuleType("frappe.custom.doctype.custom_field")
        frappe_custom_field_module = types.ModuleType("frappe.custom.doctype.custom_field.custom_field")
        frappe_custom_field_module.create_custom_fields = lambda *args, **kwargs: None

        sys.modules["frappe"] = frappe_module
        sys.modules["frappe.custom"] = frappe_custom_module
        sys.modules["frappe.custom.doctype"] = frappe_custom_doctype_module
        sys.modules["frappe.custom.doctype.custom_field"] = frappe_custom_field_pkg
        sys.modules["frappe.custom.doctype.custom_field.custom_field"] = frappe_custom_field_module
        sys.modules.pop("ashan_cn_procurement.setup.custom_fields", None)
        self.custom_fields_module = importlib.import_module("ashan_cn_procurement.setup.custom_fields")

    def tearDown(self):
        sys.modules.pop("ashan_cn_procurement.setup.custom_fields", None)
        for name, original in self._original_modules.items():
            if original is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = original

    def test_vehicle_custom_fields_include_oil_card_block(self):
        fields = {field["fieldname"]: field for field in self.custom_fields_module.get_custom_fields()["Vehicle"]}

        self.assertEqual(fields["custom_oil_card_section"]["fieldtype"], "Section Break")
        self.assertEqual(fields["custom_default_oil_card"]["options"], "Oil Card")
        self.assertEqual(fields["custom_last_refuel_date"]["read_only"], 1)
        self.assertEqual(fields["custom_last_refuel_amount"]["fieldtype"], "Currency")

    def test_oil_card_doctype_uses_standard_layout_naming(self):
        doc = load_doctype_json("oil_card")
        fieldnames = {field["fieldname"]: field for field in doc["fields"]}

        self.assertEqual(doc["name"], "Oil Card")
        self.assertEqual(doc["quick_entry"], 0)
        self.assertEqual(doc["title_field"], "card_name")
        self.assertIn("sb_basic_info", doc["field_order"])
        self.assertEqual(fieldnames["layout_summary_html"]["fieldtype"], "HTML")
        self.assertEqual(fieldnames["current_balance"]["read_only"], 1)
        self.assertEqual(fieldnames["uninvoiced_amount"]["read_only"], 1)

    def test_refuel_log_doctype_exposes_vehicle_history_html_and_invoice_status(self):
        doc = load_doctype_json("oil_card_refuel_log")
        fieldnames = {field["fieldname"]: field for field in doc["fields"]}

        self.assertEqual(doc["name"], "Oil Card Refuel Log")
        self.assertEqual(fieldnames["vehicle_history_html"]["fieldtype"], "HTML")
        self.assertEqual(fieldnames["invoice_status"]["read_only"], 1)
        self.assertEqual(fieldnames["invoice_status"]["in_list_view"], 1)
        self.assertEqual(fieldnames["allocated_discount_amount"]["read_only"], 1)

    def test_invoice_batch_doctype_and_child_table_follow_field_order_spec(self):
        batch = load_doctype_json("oil_card_invoice_batch")
        item = load_doctype_json("oil_card_invoice_batch_item")
        batch_fields = {field["fieldname"]: field for field in batch["fields"]}
        item_fields = {field["fieldname"]: field for field in item["fields"]}

        self.assertEqual(batch["name"], "Oil Card Invoice Batch")
        self.assertIn("sb_items", batch["field_order"])
        self.assertEqual(batch_fields["items"]["options"], "Oil Card Invoice Batch Item")
        self.assertEqual(batch_fields["purchase_invoice"]["read_only"], 1)
        self.assertEqual(item["istable"], 1)
        self.assertEqual(item_fields["invoice_amount_this_time"]["reqd"], 1)
        self.assertEqual(item_fields["remaining_uninvoiced_amount"]["read_only"], 1)

    def test_reimbursement_request_json_includes_employee_fields(self):
        doc = load_doctype_json("reimbursement_request")
        fieldnames = {field["fieldname"]: field for field in doc["fields"]}

        self.assertIn("employee", doc["field_order"])
        self.assertIn("employee_name", doc["field_order"])
        self.assertIn("department", doc["field_order"])
        self.assertEqual(fieldnames["employee"]["options"], "Employee")
        self.assertEqual(fieldnames["employee_name"]["read_only"], 1)
        self.assertEqual(fieldnames["department"]["read_only"], 1)


if __name__ == "__main__":
    unittest.main()

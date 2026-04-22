import importlib
import sys
import types
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from ashan_cn_procurement.utils.biz_mode import ALLOWED_BIZ_MODES


class CustomFieldsTests(unittest.TestCase):
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
        self.module = importlib.import_module("ashan_cn_procurement.setup.custom_fields")

    def tearDown(self):
        sys.modules.pop("ashan_cn_procurement.setup.custom_fields", None)
        for name, original in self._original_modules.items():
            if original is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = original

    def test_purchase_invoice_includes_invoice_type_field(self):
        fields = {field["fieldname"]: field for field in self.module.get_custom_fields()["Purchase Invoice"]}
        invoice_type = fields["custom_invoice_type"]

        self.assertEqual(invoice_type["label"], "发票类型")
        self.assertEqual(invoice_type["fieldtype"], "Select")
        self.assertEqual(invoice_type["reqd"], 1)
        self.assertIn("专用发票", invoice_type["options"])
        self.assertIn("普通发票", invoice_type["options"])
        self.assertIn("无发票", invoice_type["options"])

    def test_procurement_parent_biz_mode_only_keeps_four_allowed_values(self):
        fields = {field["fieldname"]: field for field in self.module.get_custom_fields()["Purchase Invoice"]}
        biz_mode = fields["custom_biz_mode"]

        self.assertEqual(biz_mode["label"], "业务模式")
        self.assertEqual(biz_mode["fieldtype"], "Select")
        self.assertEqual(biz_mode["options"].split("\n"), ALLOWED_BIZ_MODES)

    def test_procurement_parent_includes_restriction_fields(self):
        fields = {field["fieldname"]: field for field in self.module.get_custom_fields()["Purchase Invoice"]}

        self.assertEqual(fields["custom_is_restricted_doc"]["fieldtype"], "Check")
        self.assertEqual(fields["custom_restriction_group"]["fieldtype"], "Link")
        self.assertEqual(fields["custom_restriction_group"]["options"], "Restricted Access Group")
        self.assertEqual(fields["custom_restriction_root_doctype"]["read_only"], 1)
        self.assertEqual(fields["custom_restriction_root_name"]["read_only"], 1)
        self.assertEqual(fields["custom_restriction_note"]["fieldtype"], "Small Text")


if __name__ == "__main__":
    unittest.main()

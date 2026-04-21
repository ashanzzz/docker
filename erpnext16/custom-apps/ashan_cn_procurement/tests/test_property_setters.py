import sys
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from ashan_cn_procurement.setup.property_setters import (
    PROCUREMENT_ROW_LABEL_OVERRIDES,
    ensure_property_setters,
    get_property_setter_specs,
)


class PropertySetterTests(unittest.TestCase):
    def test_rate_label_is_explicitly_untaxed_for_all_procurement_rows(self):
        expected_doctypes = {
            "Material Request Item",
            "Purchase Order Item",
            "Purchase Receipt Item",
            "Purchase Invoice Item",
        }

        self.assertEqual(set(PROCUREMENT_ROW_LABEL_OVERRIDES), expected_doctypes)
        for doctype in expected_doctypes:
            self.assertEqual(PROCUREMENT_ROW_LABEL_OVERRIDES[doctype]["rate"], "不含税单价")

    def test_property_setter_specs_include_rate_label_override(self):
        specs = {(spec.doctype, spec.fieldname, spec.property): spec for spec in get_property_setter_specs()}

        for doctype in PROCUREMENT_ROW_LABEL_OVERRIDES:
            rate_label_spec = specs[(doctype, "rate", "label")]
            self.assertEqual(rate_label_spec.value, "不含税单价")
            self.assertEqual(rate_label_spec.property_type, "Data")

    def test_ensure_property_setters_calls_make_property_setter(self):
        calls = []

        def fake_make_property_setter(*args, **kwargs):
            calls.append((args, kwargs))

        ensure_property_setters(setter=fake_make_property_setter)

        rate_calls = [
            (args, kwargs)
            for args, kwargs in calls
            if args[1] == "rate" and args[2] == "label"
        ]

        self.assertEqual(len(rate_calls), 4)
        for args, kwargs in rate_calls:
            self.assertEqual(args[3], "不含税单价")
            self.assertEqual(args[4], "Data")
            self.assertTrue(kwargs["validate_fields_for_doctype"])
            self.assertTrue(kwargs["is_system_generated"])


if __name__ == "__main__":
    unittest.main()

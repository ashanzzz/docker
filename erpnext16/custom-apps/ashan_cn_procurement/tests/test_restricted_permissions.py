import importlib
import sys
import types
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))


class FakeDB:
    def __init__(self, shared_pairs=None):
        self.shared_pairs = set(shared_pairs or [])

    def escape(self, value):
        return "'" + str(value).replace("'", "''") + "'"

    def exists(self, doctype, filters=None):
        if doctype != "DocShare":
            return False
        key = (filters.get("share_doctype"), filters.get("share_name"), filters.get("user"))
        return key in self.shared_pairs


class RestrictedPermissionsTests(unittest.TestCase):
    def setUp(self):
        self._original_modules = {name: sys.modules.get(name) for name in ("frappe", "ashan_cn_procurement.permissions.restricted_docs")}
        self.state = {
            "roles": {},
            "group_users": {},
            "group_roles": {},
            "shared_pairs": set(),
        }

        frappe_module = types.ModuleType("frappe")
        frappe_module.session = types.SimpleNamespace(user="test@example.com")
        frappe_module.db = FakeDB(self.state["shared_pairs"])

        def fake_get_roles(user):
            return list(self.state["roles"].get(user, []))

        def fake_get_all(doctype, filters=None, pluck=None, limit_page_length=None):
            parent = (filters or {}).get("parent")
            if doctype == "Restricted Access Group User":
                return list(self.state["group_users"].get(parent, []))
            if doctype == "Restricted Access Group Role":
                return list(self.state["group_roles"].get(parent, []))
            raise AssertionError(f"Unexpected doctype: {doctype}")

        frappe_module.get_roles = fake_get_roles
        frappe_module.get_all = fake_get_all

        sys.modules["frappe"] = frappe_module
        sys.modules.pop("ashan_cn_procurement.permissions.restricted_docs", None)
        self.module = importlib.import_module("ashan_cn_procurement.permissions.restricted_docs")

    def tearDown(self):
        sys.modules.pop("ashan_cn_procurement.permissions.restricted_docs", None)
        for name, original in self._original_modules.items():
            if original is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = original

    def test_build_restricted_doc_query_conditions_contains_native_and_custom_checks(self):
        conditions = self.module.build_restricted_doc_query_conditions("Purchase Invoice", user="user@example.com")

        self.assertIn("custom_is_restricted_doc", conditions)
        self.assertIn("tabDocShare", conditions)
        self.assertIn("tabRestricted Access Group User", conditions)
        self.assertIn("tabRestricted Access Group Role", conditions)

    def test_user_can_access_restricted_doc_via_group_role_and_share(self):
        self.state["roles"]["manager@example.com"] = {"Purchase Manager"}
        self.state["group_roles"]["采购核心组"] = ["Purchase Manager"]
        self.state["shared_pairs"].add(("Purchase Invoice", "PI-0002", "shared@example.com"))
        self.module.frappe.db.shared_pairs = self.state["shared_pairs"]

        restricted_doc = types.SimpleNamespace(
            doctype="Purchase Invoice",
            name="PI-0001",
            owner="owner@example.com",
            custom_is_restricted_doc=1,
            custom_restriction_group="采购核心组",
        )
        shared_doc = types.SimpleNamespace(
            doctype="Purchase Invoice",
            name="PI-0002",
            owner="owner@example.com",
            custom_is_restricted_doc=1,
            custom_restriction_group="采购核心组",
        )

        self.assertTrue(self.module.user_can_access_restricted_doc(restricted_doc, user="manager@example.com", permission_type="read"))
        self.assertTrue(self.module.user_can_access_restricted_doc(shared_doc, user="shared@example.com", permission_type="read"))
        self.assertFalse(self.module.user_can_access_restricted_doc(restricted_doc, user="other@example.com", permission_type="read"))


if __name__ == "__main__":
    unittest.main()

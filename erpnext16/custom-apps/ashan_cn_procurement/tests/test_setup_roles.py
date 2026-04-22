import importlib
import sys
import types
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))


class SetupRolesTests(unittest.TestCase):
    def setUp(self):
        self._original_modules = {name: sys.modules.get(name) for name in ("frappe", "ashan_cn_procurement.setup.roles")}
        self.created_roles = []

        frappe_module = types.ModuleType("frappe")
        existing_roles = {"System Manager"}

        class FakeDB:
            @staticmethod
            def exists(doctype, name):
                return doctype == "Role" and name in existing_roles

        def fake_get_doc(payload):
            role_name = payload["role_name"]
            self.created_roles.append(role_name)

            class FakeRoleDoc:
                @staticmethod
                def insert(ignore_permissions=False):
                    existing_roles.add(role_name)
                    return None

            return FakeRoleDoc()

        frappe_module.db = FakeDB()
        frappe_module.get_doc = fake_get_doc
        sys.modules["frappe"] = frappe_module
        sys.modules.pop("ashan_cn_procurement.setup.roles", None)
        self.module = importlib.import_module("ashan_cn_procurement.setup.roles")

    def tearDown(self):
        sys.modules.pop("ashan_cn_procurement.setup.roles", None)
        for name, original in self._original_modules.items():
            if original is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = original

    def test_ensure_roles_creates_missing_restricted_roles(self):
        self.module.ensure_roles()

        self.assertIn("Restricted Document Super Viewer", self.created_roles)


if __name__ == "__main__":
    unittest.main()

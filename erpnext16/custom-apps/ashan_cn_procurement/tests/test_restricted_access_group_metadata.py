import json
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]


def _load_json_copies(doctype_name: str):
    paths = sorted(
        path
        for path in APP_ROOT.rglob(f"{doctype_name}.json")
        if f"/doctype/{doctype_name}/" in path.as_posix()
    )
    if not paths:
        raise AssertionError(f"No JSON files found for {doctype_name}")
    return [(path, json.loads(path.read_text(encoding="utf-8"))) for path in paths]


class RestrictedAccessGroupMetadataTests(unittest.TestCase):
    def test_restricted_access_group_form_metadata_is_operator_friendly(self):
        for path, payload in _load_json_copies("restricted_access_group"):
            with self.subTest(path=path.as_posix()):
                fields = {field["fieldname"]: field for field in payload["fields"]}

                self.assertEqual(payload["quick_entry"], 0)
                self.assertIn("configuration_guide_html", payload["field_order"])
                self.assertEqual(fields["configuration_guide_html"]["fieldtype"], "HTML")
                self.assertEqual(fields["group_name"]["label"], "受限组名称")
                self.assertIn("采购核心组", fields["group_name"]["description"])
                self.assertEqual(fields["is_active"]["label"], "启用该受限组")
                self.assertIn("停用后", fields["is_active"]["description"])
                self.assertEqual(fields["description"]["label"], "适用说明")
                self.assertIn("自动带出", fields["description"]["description"])
                self.assertEqual(fields["user_members"]["label"], "指定用户成员")
                self.assertIn("个别人", fields["user_members"]["description"])
                self.assertEqual(fields["role_members"]["label"], "指定角色成员")
                self.assertIn("优先维护角色", fields["role_members"]["description"])

    def test_child_tables_mark_access_level_as_reserved_guidance(self):
        expected = {
            "restricted_access_group_user": "用户",
            "restricted_access_group_role": "角色",
        }
        for doctype_name, member_label in expected.items():
            for path, payload in _load_json_copies(doctype_name):
                with self.subTest(path=path.as_posix()):
                    fields = {field["fieldname"]: field for field in payload["fields"]}
                    self.assertEqual(fields[next(iter([name for name in fields if name in {"user", "role"}]))]["label"], member_label)
                    self.assertEqual(fields["access_level"]["label"], "访问级别（预留）")
                    self.assertIn("当前版本仅作提示", fields["access_level"]["description"])

    def test_hooks_register_restricted_access_group_form_script(self):
        hooks_path = APP_ROOT / "ashan_cn_procurement" / "hooks.py"
        hooks_text = hooks_path.read_text(encoding="utf-8")

        self.assertIn('"Restricted Access Group": "public/js/restricted_access_group_form.js"', hooks_text)


if __name__ == "__main__":
    unittest.main()

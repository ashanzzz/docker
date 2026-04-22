import sys
import unittest
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from ashan_cn_procurement.constants.restrictions import GLOBAL_RESTRICTED_VIEWER_ROLE
from ashan_cn_procurement.services.restriction_service import (
    evaluate_restricted_access,
    merge_restriction_contexts,
    sync_restriction_fields,
)


class RestrictionServiceTests(unittest.TestCase):
    def test_sync_restriction_fields_requires_group_for_manual_root_doc(self):
        doc = {"doctype": "Purchase Invoice", "custom_is_restricted_doc": 1, "custom_restriction_group": ""}

        with self.assertRaisesRegex(ValueError, "受限单据必须选择受限单据组"):
            sync_restriction_fields(doc, current_doctype="Purchase Invoice", current_name="PI-0001")

    def test_sync_restriction_fields_inherits_group_and_root_from_single_source(self):
        doc = {"doctype": "Purchase Receipt", "custom_is_restricted_doc": 0}
        source_contexts = [
            {
                "is_restricted": True,
                "group": "采购核心组",
                "root_doctype": "Material Request",
                "root_name": "MAT-MR-0001",
            }
        ]

        sync_restriction_fields(doc, source_contexts=source_contexts, current_doctype="Purchase Receipt")

        self.assertEqual(doc["custom_is_restricted_doc"], 1)
        self.assertEqual(doc["custom_restriction_group"], "采购核心组")
        self.assertEqual(doc["custom_restriction_root_doctype"], "Material Request")
        self.assertEqual(doc["custom_restriction_root_name"], "MAT-MR-0001")

    def test_merge_restriction_contexts_clears_root_when_same_group_has_multiple_roots(self):
        merged = merge_restriction_contexts(
            [
                {"is_restricted": True, "group": "采购核心组", "root_doctype": "Material Request", "root_name": "MR-1"},
                {"is_restricted": True, "group": "采购核心组", "root_doctype": "Material Request", "root_name": "MR-2"},
            ]
        )

        self.assertEqual(merged["group"], "采购核心组")
        self.assertEqual(merged["root_doctype"], "")
        self.assertEqual(merged["root_name"], "")

    def test_merge_restriction_contexts_rejects_mixed_groups(self):
        with self.assertRaisesRegex(ValueError, "受限单据组不一致"):
            merge_restriction_contexts(
                [
                    {"is_restricted": True, "group": "采购核心组", "root_doctype": "Material Request", "root_name": "MR-1"},
                    {"is_restricted": True, "group": "财务核心组", "root_doctype": "Material Request", "root_name": "MR-2"},
                ]
            )

    def test_evaluate_restricted_access_respects_global_role_group_role_and_share(self):
        self.assertTrue(
            evaluate_restricted_access(
                is_restricted=True,
                owner="owner@example.com",
                user="gm@example.com",
                user_roles={GLOBAL_RESTRICTED_VIEWER_ROLE},
                group_users=set(),
                group_roles=set(),
                shared_users=set(),
            )
        )
        self.assertTrue(
            evaluate_restricted_access(
                is_restricted=True,
                owner="owner@example.com",
                user="manager@example.com",
                user_roles={"Purchase Manager"},
                group_users=set(),
                group_roles={"Purchase Manager"},
                shared_users=set(),
            )
        )
        self.assertTrue(
            evaluate_restricted_access(
                is_restricted=True,
                owner="owner@example.com",
                user="guest@example.com",
                user_roles=set(),
                group_users=set(),
                group_roles=set(),
                shared_users={"guest@example.com"},
            )
        )
        self.assertFalse(
            evaluate_restricted_access(
                is_restricted=True,
                owner="owner@example.com",
                user="other@example.com",
                user_roles={"Accounts User"},
                group_users=set(),
                group_roles={"Purchase Manager"},
                shared_users=set(),
            )
        )


if __name__ == "__main__":
    unittest.main()

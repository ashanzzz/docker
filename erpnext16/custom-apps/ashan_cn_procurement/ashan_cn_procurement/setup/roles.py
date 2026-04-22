from __future__ import annotations

import frappe

from ashan_cn_procurement.constants.restrictions import GLOBAL_RESTRICTED_VIEWER_ROLE

REQUIRED_ROLES = [
    GLOBAL_RESTRICTED_VIEWER_ROLE,
]


def ensure_roles() -> None:
    for role_name in REQUIRED_ROLES:
        if frappe.db.exists("Role", role_name):
            continue
        frappe.get_doc({"doctype": "Role", "role_name": role_name}).insert(ignore_permissions=True)

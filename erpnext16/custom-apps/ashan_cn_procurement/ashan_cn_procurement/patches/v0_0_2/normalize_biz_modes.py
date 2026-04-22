from __future__ import annotations

import frappe

from ashan_cn_procurement.utils.biz_mode import ALLOWED_BIZ_MODES, LEGACY_BIZ_MODE_MAP

TARGET_DOCTYPES = [
    "Material Request",
    "Purchase Order",
    "Purchase Receipt",
    "Purchase Invoice",
    "Reimbursement Request",
]


def execute() -> None:
    legacy_values = [value for value in LEGACY_BIZ_MODE_MAP if value not in ALLOWED_BIZ_MODES]
    if not legacy_values:
        return

    for doctype in TARGET_DOCTYPES:
        if not frappe.db.exists("DocType", doctype):
            continue

        rows = frappe.get_all(
            doctype,
            filters={"custom_biz_mode": ["in", legacy_values]},
            fields=["name", "custom_biz_mode"],
            limit_page_length=0,
        )
        for row in rows:
            mapped_value = LEGACY_BIZ_MODE_MAP.get(row.get("custom_biz_mode"))
            if not mapped_value or mapped_value == row.get("custom_biz_mode"):
                continue
            frappe.db.set_value(doctype, row["name"], "custom_biz_mode", mapped_value, update_modified=False)

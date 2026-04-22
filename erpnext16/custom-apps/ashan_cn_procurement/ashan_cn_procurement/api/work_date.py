from __future__ import annotations

from typing import Final

import frappe
from frappe.utils import getdate

WORK_DATE_DEFAULT_KEY: Final[str] = "ashan_work_date"
WORK_DATE_FIELD_KEYS: Final[tuple[str, ...]] = (
    "posting_date",
    "transaction_date",
    "schedule_date",
    "bill_date",
)
WORK_DATE_DEFAULT_KEYS: Final[tuple[str, ...]] = (WORK_DATE_DEFAULT_KEY, *WORK_DATE_FIELD_KEYS)


def normalize_work_date(work_date: str) -> str:
    if work_date in (None, ""):
        raise ValueError("work_date is required")
    return str(getdate(work_date))


@frappe.whitelist()
def get_work_date() -> dict[str, object]:
    return {
        "work_date": frappe.defaults.get_user_default(WORK_DATE_DEFAULT_KEY),
        "default_keys": list(WORK_DATE_DEFAULT_KEYS),
    }


@frappe.whitelist()
def set_work_date(work_date: str) -> dict[str, object]:
    normalized = normalize_work_date(work_date)

    for key in WORK_DATE_DEFAULT_KEYS:
        frappe.defaults.set_user_default(key, normalized)

    return {
        "work_date": normalized,
        "default_keys": list(WORK_DATE_DEFAULT_KEYS),
    }


@frappe.whitelist()
def clear_work_date() -> dict[str, object]:
    for key in WORK_DATE_DEFAULT_KEYS:
        frappe.defaults.clear_user_default(key)

    return {
        "cleared": True,
        "default_keys": list(WORK_DATE_DEFAULT_KEYS),
    }

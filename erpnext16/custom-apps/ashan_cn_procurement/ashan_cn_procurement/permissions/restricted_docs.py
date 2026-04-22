"""Permission hooks for restricted procurement/reimbursement docs."""

from __future__ import annotations

from typing import Any

import frappe

from ashan_cn_procurement.constants.restrictions import (
    FIELD_IS_RESTRICTED_DOC,
    FIELD_RESTRICTION_GROUP,
    GLOBAL_RESTRICTED_VIEWER_ROLE,
)
from ashan_cn_procurement.services.restriction_service import evaluate_restricted_access, get_value


SUPPORTED_DOCTYPES = {
    "Material Request",
    "Purchase Order",
    "Purchase Receipt",
    "Purchase Invoice",
    "Reimbursement Request",
}


def user_has_super_restricted_access(user: str | None = None, *, frappe_module: Any = frappe) -> bool:
    user = user or frappe_module.session.user
    roles = set(frappe_module.get_roles(user) or [])
    return "System Manager" in roles or GLOBAL_RESTRICTED_VIEWER_ROLE in roles


def _load_group_users(group: str, *, frappe_module: Any = frappe) -> set[str]:
    if not group:
        return set()
    return set(
        frappe_module.get_all(
            "Restricted Access Group User",
            filters={"parent": group, "parenttype": "Restricted Access Group"},
            pluck="user",
            limit_page_length=0,
        )
        or []
    )


def _load_group_roles(group: str, *, frappe_module: Any = frappe) -> set[str]:
    if not group:
        return set()
    return set(
        frappe_module.get_all(
            "Restricted Access Group Role",
            filters={"parent": group, "parenttype": "Restricted Access Group"},
            pluck="role",
            limit_page_length=0,
        )
        or []
    )


def build_restricted_doc_query_conditions(doctype: str, user: str | None = None, *, frappe_module: Any = frappe) -> str:
    user = user or frappe_module.session.user
    if user_has_super_restricted_access(user, frappe_module=frappe_module):
        return ""

    escaped_user = frappe_module.db.escape(user)
    escaped_doctype = frappe_module.db.escape(doctype)
    table = f"`tab{doctype}`"
    return f"""
(
    IFNULL({table}.{FIELD_IS_RESTRICTED_DOC}, 0) = 0
    OR {table}.owner = {escaped_user}
    OR EXISTS (
        SELECT 1 FROM `tabDocShare` ds
        WHERE ds.share_doctype = {escaped_doctype}
          AND ds.share_name = {table}.name
          AND ds.user = {escaped_user}
          AND IFNULL(ds.read, 0) = 1
    )
    OR EXISTS (
        SELECT 1 FROM `tabRestricted Access Group User` group_user
        WHERE group_user.parent = {table}.{FIELD_RESTRICTION_GROUP}
          AND group_user.parenttype = 'Restricted Access Group'
          AND group_user.user = {escaped_user}
    )
    OR EXISTS (
        SELECT 1
        FROM `tabRestricted Access Group Role` group_role
        INNER JOIN `tabHas Role` user_role
            ON user_role.role = group_role.role
           AND user_role.parent = {escaped_user}
           AND user_role.parenttype = 'User'
        WHERE group_role.parent = {table}.{FIELD_RESTRICTION_GROUP}
          AND group_role.parenttype = 'Restricted Access Group'
    )
)
""".strip()


def user_can_access_restricted_doc(
    doc: Any,
    user: str | None = None,
    permission_type: str | None = None,
    *,
    frappe_module: Any = frappe,
) -> bool | None:
    doctype = get_value(doc, "doctype", "")
    if doctype not in SUPPORTED_DOCTYPES:
        return None
    if permission_type == "create":
        return None

    user = user or frappe_module.session.user
    if not get_value(doc, FIELD_IS_RESTRICTED_DOC, 0):
        return None

    allowed = evaluate_restricted_access(
        is_restricted=True,
        owner=get_value(doc, "owner", ""),
        user=user,
        user_roles=set(frappe_module.get_roles(user) or []),
        group_users=_load_group_users(get_value(doc, FIELD_RESTRICTION_GROUP, ""), frappe_module=frappe_module),
        group_roles=_load_group_roles(get_value(doc, FIELD_RESTRICTION_GROUP, ""), frappe_module=frappe_module),
        shared_users={user}
        if frappe_module.db.exists(
            "DocShare",
            {"share_doctype": doctype, "share_name": get_value(doc, "name", ""), "user": user, "read": 1},
        )
        else set(),
    )
    return True if allowed else False


def _query_for(doctype: str, user: str | None = None) -> str:
    return build_restricted_doc_query_conditions(doctype, user=user)


def _has_permission_for(doc: Any, user: str | None = None, permission_type: str | None = None) -> bool | None:
    return user_can_access_restricted_doc(doc, user=user, permission_type=permission_type)


def material_request_query_conditions(user: str | None = None) -> str:
    return _query_for("Material Request", user=user)


def purchase_order_query_conditions(user: str | None = None) -> str:
    return _query_for("Purchase Order", user=user)


def purchase_receipt_query_conditions(user: str | None = None) -> str:
    return _query_for("Purchase Receipt", user=user)


def purchase_invoice_query_conditions(user: str | None = None) -> str:
    return _query_for("Purchase Invoice", user=user)


def reimbursement_request_query_conditions(user: str | None = None) -> str:
    return _query_for("Reimbursement Request", user=user)


def material_request_has_permission(doc: Any, user: str | None = None, permission_type: str | None = None) -> bool | None:
    return _has_permission_for(doc, user=user, permission_type=permission_type)


def purchase_order_has_permission(doc: Any, user: str | None = None, permission_type: str | None = None) -> bool | None:
    return _has_permission_for(doc, user=user, permission_type=permission_type)


def purchase_receipt_has_permission(doc: Any, user: str | None = None, permission_type: str | None = None) -> bool | None:
    return _has_permission_for(doc, user=user, permission_type=permission_type)


def purchase_invoice_has_permission(doc: Any, user: str | None = None, permission_type: str | None = None) -> bool | None:
    return _has_permission_for(doc, user=user, permission_type=permission_type)


def reimbursement_request_has_permission(doc: Any, user: str | None = None, permission_type: str | None = None) -> bool | None:
    return _has_permission_for(doc, user=user, permission_type=permission_type)

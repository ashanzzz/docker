"""Service-layer helpers for restricted-document behavior."""

from __future__ import annotations

from typing import Any, Iterable

from ashan_cn_procurement.constants.restrictions import (
    FIELD_IS_RESTRICTED_DOC,
    FIELD_RESTRICTION_GROUP,
    FIELD_RESTRICTION_NOTE,
    FIELD_RESTRICTION_ROOT_DOCTYPE,
    FIELD_RESTRICTION_ROOT_NAME,
    GLOBAL_RESTRICTED_VIEWER_ROLE,
)
from ashan_cn_procurement.utils.text_normalization import normalize_multiline_text, normalize_single_line_text

PROCUREMENT_SOURCE_LINK_FIELDS = {
    "Purchase Order": [("material_request", "Material Request")],
    "Purchase Receipt": [("purchase_order", "Purchase Order")],
    "Purchase Invoice": [("purchase_receipt", "Purchase Receipt"), ("purchase_order", "Purchase Order")],
}


def get_value(doc: Any, fieldname: str, default: Any = None) -> Any:
    if isinstance(doc, dict):
        return doc.get(fieldname, default)
    return getattr(doc, fieldname, default)


def set_value(doc: Any, fieldname: str, value: Any) -> None:
    if isinstance(doc, dict):
        doc[fieldname] = value
    else:
        setattr(doc, fieldname, value)


def _is_restricted_flag(value: Any) -> bool:
    return value in (1, "1", True, "true", "True")


def _clean_group(value: Any) -> str:
    return normalize_single_line_text(value)


def build_restriction_context(doc: Any) -> dict[str, Any]:
    return {
        "is_restricted": _is_restricted_flag(get_value(doc, FIELD_IS_RESTRICTED_DOC, 0)),
        "group": _clean_group(get_value(doc, FIELD_RESTRICTION_GROUP, "")),
        "root_doctype": normalize_single_line_text(get_value(doc, FIELD_RESTRICTION_ROOT_DOCTYPE, "")),
        "root_name": normalize_single_line_text(get_value(doc, FIELD_RESTRICTION_ROOT_NAME, "")),
        "note": normalize_multiline_text(get_value(doc, FIELD_RESTRICTION_NOTE, "")),
    }


def merge_restriction_contexts(contexts: Iterable[dict[str, Any]]) -> dict[str, Any] | None:
    restricted_contexts = [context for context in contexts if context and context.get("is_restricted")]
    if not restricted_contexts:
        return None

    groups = {normalize_single_line_text(context.get("group")) for context in restricted_contexts if context.get("group")}
    if len(groups) > 1:
        raise ValueError("来源单据的受限单据组不一致，不能合并")
    if not groups:
        raise ValueError("来源受限单据缺少受限单据组")

    group = groups.pop()
    root_pairs = {
        (
            normalize_single_line_text(context.get("root_doctype")),
            normalize_single_line_text(context.get("root_name")),
        )
        for context in restricted_contexts
        if context.get("root_doctype") or context.get("root_name")
    }
    if len(root_pairs) == 1:
        root_doctype, root_name = next(iter(root_pairs))
    else:
        root_doctype, root_name = "", ""

    return {
        "is_restricted": True,
        "group": group,
        "root_doctype": root_doctype,
        "root_name": root_name,
        "note": "",
    }


def sync_restriction_fields(
    doc: Any,
    *,
    source_contexts: Iterable[dict[str, Any]] | None = None,
    current_doctype: str | None = None,
    current_name: str | None = None,
) -> dict[str, Any]:
    context = build_restriction_context(doc)
    merged_source_context = merge_restriction_contexts(source_contexts or [])

    if merged_source_context:
        if context["is_restricted"] and context["group"] and context["group"] != merged_source_context["group"]:
            raise ValueError("下游单据的受限单据组必须与来源单据一致")
        context.update(merged_source_context)
    elif context["is_restricted"]:
        if not context["group"]:
            raise ValueError("受限单据必须选择受限单据组")
        if current_doctype and not context["root_doctype"]:
            context["root_doctype"] = current_doctype
        if current_name and not context["root_name"]:
            context["root_name"] = current_name
    else:
        context = {
            "is_restricted": False,
            "group": "",
            "root_doctype": "",
            "root_name": "",
            "note": "",
        }

    set_value(doc, FIELD_IS_RESTRICTED_DOC, 1 if context["is_restricted"] else 0)
    set_value(doc, FIELD_RESTRICTION_GROUP, context["group"])
    set_value(doc, FIELD_RESTRICTION_ROOT_DOCTYPE, context["root_doctype"])
    set_value(doc, FIELD_RESTRICTION_ROOT_NAME, context["root_name"])
    set_value(doc, FIELD_RESTRICTION_NOTE, context["note"])
    return context


def evaluate_restricted_access(
    *,
    is_restricted: bool,
    owner: str | None,
    user: str,
    user_roles: set[str] | None = None,
    group_users: set[str] | None = None,
    group_roles: set[str] | None = None,
    shared_users: set[str] | None = None,
) -> bool:
    if not is_restricted:
        return True

    normalized_roles = {normalize_single_line_text(role) for role in (user_roles or set()) if role}
    if user == owner:
        return True
    if "System Manager" in normalized_roles or GLOBAL_RESTRICTED_VIEWER_ROLE in normalized_roles:
        return True
    if user in (group_users or set()):
        return True
    if normalized_roles.intersection(group_roles or set()):
        return True
    if user in (shared_users or set()):
        return True
    return False


def collect_procurement_source_refs(doc: Any) -> list[tuple[str, str]]:
    refs: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    doctype = get_value(doc, "doctype", "")
    for fieldname, source_doctype in PROCUREMENT_SOURCE_LINK_FIELDS.get(doctype, []):
        for row in get_value(doc, "items", []) or []:
            source_name = normalize_single_line_text(get_value(row, fieldname, ""))
            if not source_name:
                continue
            key = (source_doctype, source_name)
            if key in seen:
                continue
            seen.add(key)
            refs.append(key)
    return refs

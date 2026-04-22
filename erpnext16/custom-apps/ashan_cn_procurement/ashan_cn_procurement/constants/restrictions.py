"""Restriction-related constants for Ashan CN Procurement."""

GLOBAL_RESTRICTED_VIEWER_ROLE = "Restricted Document Super Viewer"

RESTRICTED_ACCESS_GROUP_DOCTYPE = "Restricted Access Group"
RESTRICTED_ACCESS_GROUP_USER_DOCTYPE = "Restricted Access Group User"
RESTRICTED_ACCESS_GROUP_ROLE_DOCTYPE = "Restricted Access Group Role"

RESTRICTED_SUPPORTED_DOCTYPES = [
    "Material Request",
    "Purchase Order",
    "Purchase Receipt",
    "Purchase Invoice",
    "Reimbursement Request",
]

FIELD_IS_RESTRICTED_DOC = "custom_is_restricted_doc"
FIELD_RESTRICTION_GROUP = "custom_restriction_group"
FIELD_RESTRICTION_ROOT_DOCTYPE = "custom_restriction_root_doctype"
FIELD_RESTRICTION_ROOT_NAME = "custom_restriction_root_name"
FIELD_RESTRICTION_NOTE = "custom_restriction_note"

TITLE_MAX_LENGTH = 140
REMARK_MAX_LENGTH = 140

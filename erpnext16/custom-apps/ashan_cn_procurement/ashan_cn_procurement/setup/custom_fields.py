from __future__ import annotations

from copy import deepcopy

from frappe.custom.doctype.custom_field.custom_field import create_custom_fields

from ashan_cn_procurement.constants.restrictions import RESTRICTED_ACCESS_GROUP_DOCTYPE
from ashan_cn_procurement.utils.biz_mode import BIZ_MODE_OPTIONS

PROCUREMENT_PARENT_DOCTYPES = {
    "Material Request": "material_request_type",
    "Purchase Order": "supplier",
    "Purchase Receipt": "supplier",
    "Purchase Invoice": "supplier",
}

PROCUREMENT_CHILD_DOCTYPES = [
    "Material Request Item",
    "Purchase Order Item",
    "Purchase Receipt Item",
    "Purchase Invoice Item",
]

VEHICLE_INSERT_AFTER = "last_odometer"

INVOICE_TYPE_OPTIONS = "\n".join(
    [
        "专用发票",
        "普通发票",
        "无发票",
    ]
)

TAX_BASIS_OPTIONS = "\n".join(["net_rate", "gross_rate", "net_amount", "gross_amount"])


def restriction_parent_fields(insert_after: str) -> list[dict[str, object]]:
    return [
        {
            "fieldname": "custom_is_restricted_doc",
            "label": "受限单据",
            "fieldtype": "Check",
            "insert_after": insert_after,
            "allow_on_submit": 1,
        },
        {
            "fieldname": "custom_restriction_group",
            "label": "受限单据组",
            "fieldtype": "Link",
            "options": RESTRICTED_ACCESS_GROUP_DOCTYPE,
            "insert_after": "custom_is_restricted_doc",
            "depends_on": "eval:doc.custom_is_restricted_doc==1",
            "mandatory_depends_on": "eval:doc.custom_is_restricted_doc==1",
            "allow_on_submit": 1,
        },
        {
            "fieldname": "custom_restriction_root_doctype",
            "label": "权限源单据类型",
            "fieldtype": "Data",
            "insert_after": "custom_restriction_group",
            "read_only": 1,
            "allow_on_submit": 1,
        },
        {
            "fieldname": "custom_restriction_root_name",
            "label": "权限源单据",
            "fieldtype": "Data",
            "insert_after": "custom_restriction_root_doctype",
            "read_only": 1,
            "allow_on_submit": 1,
        },
        {
            "fieldname": "custom_restriction_note",
            "label": "受限说明",
            "fieldtype": "Small Text",
            "insert_after": "custom_restriction_root_name",
            "depends_on": "eval:doc.custom_is_restricted_doc==1",
            "allow_on_submit": 1,
        },
    ]


def procurement_parent_fields(doctype: str, insert_after: str) -> list[dict[str, object]]:
    fields = [
        {
            "fieldname": "custom_biz_mode",
            "label": "业务模式",
            "fieldtype": "Select",
            "options": BIZ_MODE_OPTIONS,
            "insert_after": insert_after,
            "allow_on_submit": 1,
        }
    ]

    if doctype == "Purchase Invoice":
        fields.append(
            {
                "fieldname": "custom_invoice_type",
                "label": "发票类型",
                "fieldtype": "Select",
                "options": INVOICE_TYPE_OPTIONS,
                "insert_after": "custom_biz_mode",
                "allow_on_submit": 1,
            }
        )
        fields.extend(restriction_parent_fields("custom_invoice_type"))
    else:
        fields.extend(restriction_parent_fields("custom_biz_mode"))

    return fields


PROCUREMENT_ROW_FIELDS = [
    {
        "fieldname": "custom_spec_model",
        "label": "规格参数",
        "fieldtype": "Data",
        "insert_after": "item_name",
        "allow_on_submit": 1,
    },
    {
        "fieldname": "custom_gross_rate",
        "label": "含税单价",
        "fieldtype": "Currency",
        "insert_after": "rate",
        "allow_on_submit": 1,
    },
    {
        "fieldname": "custom_tax_rate",
        "label": "税率(%)",
        "fieldtype": "Percent",
        "insert_after": "custom_gross_rate",
        "default": "13",
        "allow_on_submit": 1,
    },
    {
        "fieldname": "custom_tax_amount",
        "label": "税额",
        "fieldtype": "Currency",
        "insert_after": "amount",
        "read_only": 1,
        "allow_on_submit": 1,
    },
    {
        "fieldname": "custom_gross_amount",
        "label": "价税合计",
        "fieldtype": "Currency",
        "insert_after": "custom_tax_amount",
        "allow_on_submit": 1,
    },
    {
        "fieldname": "custom_line_remark",
        "label": "备注",
        "fieldtype": "Data",
        "insert_after": "custom_gross_amount",
        "allow_on_submit": 1,
    },
    {
        "fieldname": "custom_tax_basis",
        "label": "税额联动基准",
        "fieldtype": "Select",
        "options": TAX_BASIS_OPTIONS,
        "insert_after": "custom_line_remark",
        "default": "net_rate",
        "hidden": 1,
        "read_only": 1,
        "allow_on_submit": 1,
    },
]

VEHICLE_CUSTOM_FIELDS = [
    {
        "fieldname": "custom_oil_card_section",
        "label": "油卡信息",
        "fieldtype": "Section Break",
        "insert_after": VEHICLE_INSERT_AFTER,
    },
    {
        "fieldname": "custom_vehicle_note",
        "label": "车辆备注",
        "fieldtype": "Small Text",
        "insert_after": "custom_oil_card_section",
    },
    {
        "fieldname": "custom_default_oil_card",
        "label": "默认油卡",
        "fieldtype": "Link",
        "options": "Oil Card",
        "insert_after": "custom_vehicle_note",
        "in_standard_filter": 1,
    },
    {
        "fieldname": "custom_oil_card_cb",
        "fieldtype": "Column Break",
        "insert_after": "custom_default_oil_card",
    },
    {
        "fieldname": "custom_last_refuel_date",
        "label": "上次加油日期",
        "fieldtype": "Date",
        "insert_after": "custom_oil_card_cb",
        "read_only": 1,
    },
    {
        "fieldname": "custom_last_refuel_liters",
        "label": "上次加油升数",
        "fieldtype": "Float",
        "insert_after": "custom_last_refuel_date",
        "read_only": 1,
    },
    {
        "fieldname": "custom_last_refuel_amount",
        "label": "上次加油金额",
        "fieldtype": "Currency",
        "insert_after": "custom_last_refuel_liters",
        "read_only": 1,
    },
    {
        "fieldname": "custom_last_refuel_odometer",
        "label": "上次加油里程",
        "fieldtype": "Int",
        "insert_after": "custom_last_refuel_amount",
        "read_only": 1,
    },
]


def get_custom_fields() -> dict[str, list[dict[str, object]]]:
    custom_fields: dict[str, list[dict[str, object]]] = {}

    for doctype, insert_after in PROCUREMENT_PARENT_DOCTYPES.items():
        custom_fields[doctype] = procurement_parent_fields(doctype, insert_after)

    for doctype in PROCUREMENT_CHILD_DOCTYPES:
        custom_fields[doctype] = [deepcopy(field) for field in PROCUREMENT_ROW_FIELDS]

    custom_fields["Vehicle"] = [deepcopy(field) for field in VEHICLE_CUSTOM_FIELDS]

    return custom_fields


def ensure_custom_fields() -> None:
    create_custom_fields(get_custom_fields(), update=True)

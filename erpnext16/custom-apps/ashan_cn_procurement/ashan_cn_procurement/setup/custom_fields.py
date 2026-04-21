from __future__ import annotations

from copy import deepcopy

from frappe.custom.doctype.custom_field.custom_field import create_custom_fields

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

BIZ_MODE_OPTIONS = "\n".join(
    [
        "常规采购",
        "直接采购",
        "员工代付",
        "无发票现金支付",
        "其他账户支付",
        "自办电汇",
        "月结补录",
    ]
)

TAX_BASIS_OPTIONS = "\n".join(["net_rate", "gross_rate", "net_amount", "gross_amount"])


def procurement_parent_fields(insert_after: str) -> list[dict[str, object]]:
    return [
        {
            "fieldname": "custom_biz_mode",
            "label": "业务模式",
            "fieldtype": "Select",
            "options": BIZ_MODE_OPTIONS,
            "insert_after": insert_after,
            "allow_on_submit": 1,
        }
    ]


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


def get_custom_fields() -> dict[str, list[dict[str, object]]]:
    custom_fields: dict[str, list[dict[str, object]]] = {}

    for doctype, insert_after in PROCUREMENT_PARENT_DOCTYPES.items():
        custom_fields[doctype] = procurement_parent_fields(insert_after)

    for doctype in PROCUREMENT_CHILD_DOCTYPES:
        custom_fields[doctype] = [deepcopy(field) for field in PROCUREMENT_ROW_FIELDS]

    return custom_fields


def ensure_custom_fields() -> None:
    create_custom_fields(get_custom_fields(), update=True)

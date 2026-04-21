from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

PROCUREMENT_ROW_LABEL_OVERRIDES: dict[str, dict[str, str]] = {
    "Material Request Item": {"rate": "不含税单价"},
    "Purchase Order Item": {"rate": "不含税单价"},
    "Purchase Receipt Item": {"rate": "不含税单价"},
    "Purchase Invoice Item": {"rate": "不含税单价"},
}


@dataclass(frozen=True)
class PropertySetterSpec:
    doctype: str
    fieldname: str
    property: str
    value: str
    property_type: str


def get_property_setter_specs() -> list[PropertySetterSpec]:
    specs: list[PropertySetterSpec] = []

    for doctype, field_overrides in PROCUREMENT_ROW_LABEL_OVERRIDES.items():
        for fieldname, label in field_overrides.items():
            specs.append(
                PropertySetterSpec(
                    doctype=doctype,
                    fieldname=fieldname,
                    property="label",
                    value=label,
                    property_type="Data",
                )
            )

    return specs


def ensure_property_setters(
    setter: Callable[..., object] | None = None,
) -> None:
    if setter is None:
        from frappe.custom.doctype.property_setter.property_setter import make_property_setter

        setter = make_property_setter

    for spec in get_property_setter_specs():
        setter(
            spec.doctype,
            spec.fieldname,
            spec.property,
            spec.value,
            spec.property_type,
            validate_fields_for_doctype=True,
            is_system_generated=True,
        )

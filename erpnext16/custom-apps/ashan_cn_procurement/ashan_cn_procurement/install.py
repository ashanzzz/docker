from ashan_cn_procurement.setup.custom_fields import ensure_custom_fields
from ashan_cn_procurement.setup.property_setters import ensure_property_setters


def apply_customizations() -> None:
    ensure_custom_fields()
    ensure_property_setters()


def after_install() -> None:
    apply_customizations()


def after_migrate() -> None:
    apply_customizations()

from ashan_cn_procurement.setup.custom_fields import ensure_custom_fields


def after_install() -> None:
    ensure_custom_fields()


def after_migrate() -> None:
    ensure_custom_fields()

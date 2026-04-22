from __future__ import annotations

import json
from typing import Any

SUPPORTED_PURCHASE_TAX_DOCTYPES = {
    "Purchase Order",
    "Purchase Receipt",
    "Purchase Invoice",
}

VAT_ELIGIBLE_INVOICE_TYPES = {
    "专用发票",
    "增值税专用发票",
}


def _flt(value: Any) -> float:
    if value in (None, ""):
        return 0.0
    return float(value)


def _field_value(obj: Any, fieldname: str) -> Any:
    if isinstance(obj, dict):
        return obj.get(fieldname)

    value = getattr(obj, fieldname, None)
    if callable(value):
        return None
    return value


def _as_list(value: Any) -> list[Any]:
    if not value:
        return []
    return list(value)


def _pick_tax_account_from_rows(rows: list[Any]) -> str | None:
    for row in rows:
        account_head = _field_value(row, "account_head")
        charge_type = _field_value(row, "charge_type")
        add_deduct_tax = _field_value(row, "add_deduct_tax")
        if account_head and charge_type == "On Net Total" and add_deduct_tax != "Deduct":
            return account_head

    for row in rows:
        account_head = _field_value(row, "account_head")
        if account_head:
            return account_head

    return None


def build_item_tax_rate_json(account_head: str, tax_rate: Any) -> str:
    return json.dumps({account_head: _flt(tax_rate)}, ensure_ascii=False, sort_keys=True)


def build_purchase_tax_row(account_head: str) -> dict[str, Any]:
    return {
        "charge_type": "On Net Total",
        "account_head": account_head,
        "rate": 0,
        "description": str(account_head).split(" - ", 1)[0],
        "set_by_item_tax_template": 1,
        "category": "Total",
        "add_deduct_tax": "Add",
    }


def format_item_tax_template_title(company: str, account_head: str, tax_rate: Any) -> str:
    return f"Ashan Auto Tax | {company} | {account_head} | {_flt(tax_rate):g}%"


def resolve_deductible_tax_account_head(doc: Any, frappe_module: Any) -> str | None:
    existing_rows = _as_list(_field_value(doc, "taxes"))
    account_head = _pick_tax_account_from_rows(existing_rows)
    if account_head:
        return account_head

    taxes_and_charges = _field_value(doc, "taxes_and_charges")
    if taxes_and_charges:
        template_doc = frappe_module.get_cached_doc("Purchase Taxes and Charges Template", taxes_and_charges)
        account_head = _pick_tax_account_from_rows(_as_list(_field_value(template_doc, "taxes")))
        if account_head:
            return account_head

    company = _field_value(doc, "company")
    template_names = frappe_module.get_all(
        "Purchase Taxes and Charges Template",
        filters={"company": company},
        pluck="name",
    )
    for template_name in template_names:
        template_doc = frappe_module.get_cached_doc("Purchase Taxes and Charges Template", template_name)
        account_head = _pick_tax_account_from_rows(_as_list(_field_value(template_doc, "taxes")))
        if account_head:
            return account_head

    accounts = frappe_module.get_all(
        "Account",
        filters={"company": company, "account_type": "Tax"},
        fields=["name", "account_name", "account_type", "company", "root_type"],
    )
    if not accounts:
        return None

    for account in accounts:
        account_name = (account.get("account_name") or "").lower()
        account_code = (account.get("name") or "").lower()
        if "vat" in account_name or "vat" in account_code or "税" in account_name or "税" in account_code:
            return account.get("name")

    return accounts[0].get("name")


def resolve_non_deductible_tax_account_head(doc: Any, frappe_module: Any) -> str | None:
    company = _field_value(doc, "company")
    accounts = frappe_module.get_all(
        "Account",
        filters={"company": company, "root_type": "Expense"},
        fields=["name", "account_name", "account_type", "company", "root_type"],
    )
    if not accounts:
        return None

    preference_checks = [
        lambda account: "tax expense" in (account.get("account_name") or "").lower(),
        lambda account: "tax expense" in (account.get("name") or "").lower(),
        lambda account: "税" in (account.get("account_name") or ""),
        lambda account: "税" in (account.get("name") or ""),
    ]
    for check in preference_checks:
        for account in accounts:
            if check(account):
                return account.get("name")

    return accounts[0].get("name")


def resolve_purchase_tax_account_head(doc: Any, frappe_module: Any) -> str | None:
    if _field_value(doc, "doctype") == "Purchase Invoice":
        invoice_type = _field_value(doc, "custom_invoice_type")
        if invoice_type and invoice_type not in VAT_ELIGIBLE_INVOICE_TYPES:
            return resolve_non_deductible_tax_account_head(doc, frappe_module)

    return resolve_deductible_tax_account_head(doc, frappe_module)


def ensure_item_tax_template(company: str, account_head: str, tax_rate: Any, frappe_module: Any) -> str:
    title = format_item_tax_template_title(company, account_head, tax_rate)
    existing = frappe_module.get_all(
        "Item Tax Template",
        filters={"company": company, "title": title},
        pluck="name",
        limit=1,
    )
    if existing:
        return existing[0]

    template_doc = frappe_module.get_doc(
        {
            "doctype": "Item Tax Template",
            "title": title,
            "company": company,
            "taxes": [
                {
                    "tax_type": account_head,
                    "tax_rate": _flt(tax_rate),
                }
            ],
        }
    )
    template_doc.insert(ignore_permissions=True)
    return template_doc.name


def sync_purchase_tax_bridge(doc: Any, *, frappe_module: Any) -> str | None:
    doctype = _field_value(doc, "doctype")
    if doctype not in SUPPORTED_PURCHASE_TAX_DOCTYPES:
        return None

    company = _field_value(doc, "company")
    if not company:
        return None

    account_head = resolve_purchase_tax_account_head(doc, frappe_module)
    if not account_head:
        return None

    taxes = _as_list(_field_value(doc, "taxes"))
    taxes_and_charges = _field_value(doc, "taxes_and_charges")
    invoice_type = _field_value(doc, "custom_invoice_type")

    filtered_taxes = [
        row
        for row in taxes
        if not (_field_value(row, "set_by_item_tax_template") and _field_value(row, "account_head") != account_head)
    ]
    if len(filtered_taxes) != len(taxes):
        if isinstance(doc, dict):
            doc["taxes"] = filtered_taxes
        else:
            doc.taxes = filtered_taxes
        taxes = filtered_taxes

    has_tax_row = any(_field_value(row, "account_head") == account_head for row in taxes)
    should_force_tax_row = _field_value(doc, "doctype") == "Purchase Invoice" and invoice_type not in (None, "", *VAT_ELIGIBLE_INVOICE_TYPES)
    if not has_tax_row and (taxes or not taxes_and_charges or should_force_tax_row):
        doc.append("taxes", build_purchase_tax_row(account_head))

    for row in _as_list(_field_value(doc, "items")):
        tax_rate = _field_value(row, "custom_tax_rate") or 0
        row.item_tax_template = ensure_item_tax_template(company, account_head, tax_rate, frappe_module)
        row.item_tax_rate = build_item_tax_rate_json(account_head, tax_rate)

    return account_head

from __future__ import annotations

from typing import Any

import frappe

from ashan_cn_procurement.utils.purchase_tax_bridge import sync_purchase_tax_bridge


class TaxBridgeRow(frappe._dict):
    pass


class TaxBridgeDoc(frappe._dict):
    def append(self, fieldname: str, value: dict[str, Any]) -> TaxBridgeRow:
        row = TaxBridgeRow(value)
        self.setdefault(fieldname, [])
        self[fieldname].append(row)
        return row


def _to_rows(values: list[dict[str, Any]] | None) -> list[TaxBridgeRow]:
    return [TaxBridgeRow(value) for value in values or []]


@frappe.whitelist()
def resolve_purchase_tax_bridge(doc: str | dict[str, Any], tax_rate: float | str | int) -> dict[str, Any]:
    payload = frappe.parse_json(doc) if isinstance(doc, str) else doc
    bridge_doc = TaxBridgeDoc(
        {
            "doctype": payload.get("doctype"),
            "company": payload.get("company"),
            "taxes_and_charges": payload.get("taxes_and_charges"),
            "taxes": _to_rows(payload.get("taxes")),
            "items": [TaxBridgeRow({"custom_tax_rate": tax_rate})],
        }
    )

    account_head = sync_purchase_tax_bridge(bridge_doc, frappe_module=frappe)
    row = bridge_doc.items[0] if bridge_doc.items else TaxBridgeRow()

    return {
        "account_head": account_head,
        "item_tax_template": row.get("item_tax_template"),
        "item_tax_rate": row.get("item_tax_rate"),
        "tax_rows": [dict(tax_row) for tax_row in bridge_doc.taxes],
    }

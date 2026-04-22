from __future__ import annotations

import frappe

from ashan_cn_procurement.utils.reimbursement import build_reimbursement_request_from_purchase_invoice


@frappe.whitelist()
def create_reimbursement_from_purchase_invoice(purchase_invoice: str) -> dict[str, object]:
    existing = frappe.get_all(
        "Reimbursement Request",
        filters={"source_purchase_invoice": purchase_invoice},
        pluck="name",
        limit=1,
    )
    if existing:
        return {
            "created": False,
            "name": existing[0],
            "doctype": "Reimbursement Request",
        }

    purchase_invoice_doc = frappe.get_doc("Purchase Invoice", purchase_invoice)
    payload = build_reimbursement_request_from_purchase_invoice(purchase_invoice_doc.as_dict())
    reimbursement_doc = frappe.get_doc(payload)
    reimbursement_doc.insert(ignore_permissions=True)

    return {
        "created": True,
        "name": reimbursement_doc.name,
        "doctype": "Reimbursement Request",
    }

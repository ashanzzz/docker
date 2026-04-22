from . import __version__ as app_version

app_name = "ashan_cn_procurement"
app_title = "Ashan CN Procurement"
app_publisher = "Hermes Agent"
app_description = "China-style procurement and reimbursement customization for ERPNext 16"
app_email = "noreply@example.com"
app_license = "MIT"
required_apps = ["erpnext"]

app_include_js = [
    "/assets/ashan_cn_procurement/js/procurement_grid_settings.js",
    "/assets/ashan_cn_procurement/js/work_date_manager.js",
    "/assets/ashan_cn_procurement/js/restricted_doc_actions.js",
]

doctype_js = {
    "Material Request": "public/js/procurement_controller.js",
    "Purchase Order": "public/js/procurement_controller.js",
    "Purchase Receipt": "public/js/procurement_controller.js",
    "Purchase Invoice": "public/js/procurement_controller.js",
    "Restricted Access Group": "public/js/restricted_access_group_form.js",
}

doc_events = {
    "Material Request": {"before_validate": "ashan_cn_procurement.doctype_handlers.procurement_docs.validate_procurement_doc"},
    "Purchase Order": {"before_validate": "ashan_cn_procurement.doctype_handlers.procurement_docs.validate_procurement_doc"},
    "Purchase Receipt": {"before_validate": "ashan_cn_procurement.doctype_handlers.procurement_docs.validate_procurement_doc"},
    "Purchase Invoice": {"before_validate": "ashan_cn_procurement.doctype_handlers.procurement_docs.validate_procurement_doc"},
}

permission_query_conditions = {
    "Material Request": "ashan_cn_procurement.permissions.restricted_docs.material_request_query_conditions",
    "Purchase Order": "ashan_cn_procurement.permissions.restricted_docs.purchase_order_query_conditions",
    "Purchase Receipt": "ashan_cn_procurement.permissions.restricted_docs.purchase_receipt_query_conditions",
    "Purchase Invoice": "ashan_cn_procurement.permissions.restricted_docs.purchase_invoice_query_conditions",
    "Reimbursement Request": "ashan_cn_procurement.permissions.restricted_docs.reimbursement_request_query_conditions",
}

has_permission = {
    "Material Request": "ashan_cn_procurement.permissions.restricted_docs.material_request_has_permission",
    "Purchase Order": "ashan_cn_procurement.permissions.restricted_docs.purchase_order_has_permission",
    "Purchase Receipt": "ashan_cn_procurement.permissions.restricted_docs.purchase_receipt_has_permission",
    "Purchase Invoice": "ashan_cn_procurement.permissions.restricted_docs.purchase_invoice_has_permission",
    "Reimbursement Request": "ashan_cn_procurement.permissions.restricted_docs.reimbursement_request_has_permission",
}

after_install = "ashan_cn_procurement.install.after_install"
after_migrate = "ashan_cn_procurement.install.after_migrate"

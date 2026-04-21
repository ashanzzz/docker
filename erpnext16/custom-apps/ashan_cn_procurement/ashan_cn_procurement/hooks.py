from . import __version__ as app_version

app_name = "ashan_cn_procurement"
app_title = "Ashan CN Procurement"
app_publisher = "Hermes Agent"
app_description = "China-style procurement and reimbursement customization for ERPNext 16"
app_email = "noreply@example.com"
app_license = "MIT"
required_apps = ["erpnext"]

app_include_js = []

doctype_js = {
    "Material Request": "public/js/procurement_controller.js",
    "Purchase Order": "public/js/procurement_controller.js",
    "Purchase Receipt": "public/js/procurement_controller.js",
    "Purchase Invoice": "public/js/procurement_controller.js",
}

doc_events = {
    "Material Request": {"validate": "ashan_cn_procurement.doctype_handlers.procurement_docs.validate_procurement_doc"},
    "Purchase Order": {"validate": "ashan_cn_procurement.doctype_handlers.procurement_docs.validate_procurement_doc"},
    "Purchase Receipt": {"validate": "ashan_cn_procurement.doctype_handlers.procurement_docs.validate_procurement_doc"},
    "Purchase Invoice": {"validate": "ashan_cn_procurement.doctype_handlers.procurement_docs.validate_procurement_doc"},
}

after_install = "ashan_cn_procurement.install.after_install"
after_migrate = "ashan_cn_procurement.install.after_migrate"

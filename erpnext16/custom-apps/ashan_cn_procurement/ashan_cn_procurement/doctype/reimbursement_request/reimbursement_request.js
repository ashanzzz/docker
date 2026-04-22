(() => {
  const restrictionHelper = globalThis.ashanCnRestrictedDocActions || {
    canOpenRestrictionGroup(doc) {
      return Boolean(doc?.custom_is_restricted_doc && doc?.custom_restriction_group);
    },
    canOpenSourceDocument(doc) {
      return Boolean(doc?.custom_restriction_root_doctype && doc?.custom_restriction_root_name);
    },
  };

  function recalculateAmount(cdt, cdn) {
    const row = locals[cdt][cdn];
    if (!row) return;
    const qty = flt(row.qty || 0) || 1;
    frappe.model.set_value(cdt, cdn, "amount", flt(qty * flt(row.rate || 0), 2));
  }

  frappe.ui.form.on("Reimbursement Invoice Item", {
    qty(frm, cdt, cdn) {
      recalculateAmount(cdt, cdn);
    },
    rate(frm, cdt, cdn) {
      recalculateAmount(cdt, cdn);
    },
  });

  frappe.ui.form.on("Reimbursement Request", {
    refresh(frm) {
      frm.add_custom_button(__("管理受限单据组"), () => {
        frappe.set_route("List", "Restricted Access Group");
      }, __("权限"));

      frm.add_custom_button(__("新建受限单据组"), () => {
        frappe.new_doc("Restricted Access Group");
      }, __("权限"));

      if (restrictionHelper.canOpenRestrictionGroup(frm.doc)) {
        frm.add_custom_button(__("查看受限单据组"), () => {
          frappe.set_route("Form", "Restricted Access Group", frm.doc.custom_restriction_group);
        }, __("权限"));
      }

      if (restrictionHelper.canOpenSourceDocument(frm.doc)) {
        frm.add_custom_button(__("查看权限源单据"), () => {
          frappe.set_route("Form", frm.doc.custom_restriction_root_doctype, frm.doc.custom_restriction_root_name);
        }, __("权限"));
      }

      if (frm.doc.source_purchase_invoice) {
        frm.add_custom_button(__("查看来源采购发票"), () => {
          frappe.set_route("Form", "Purchase Invoice", frm.doc.source_purchase_invoice);
        }, __("来源"));
      }
    },
  });
})();

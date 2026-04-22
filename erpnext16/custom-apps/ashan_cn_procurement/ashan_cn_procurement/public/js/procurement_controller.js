(() => {
  const parentToChild = {
    "Material Request": "Material Request Item",
    "Purchase Order": "Purchase Order Item",
    "Purchase Receipt": "Purchase Receipt Item",
    "Purchase Invoice": "Purchase Invoice Item",
  };

  const modeToField = {
    net_rate: "rate",
    gross_rate: "custom_gross_rate",
    net_amount: "amount",
    gross_amount: "custom_gross_amount",
  };

  const fallbackModeOrder = ["net_rate", "gross_rate", "net_amount", "gross_amount"];
  const taxBridgeParents = new Set(["Purchase Order", "Purchase Receipt", "Purchase Invoice"]);
  const gridSettingsHelper = globalThis.ashanCnProcurementGridSettings || {
    normalizeColumnWidth(value, fallback = 2) {
      const parsed = Number.parseInt(value, 10);
      return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
    },
    normalizeSelectedColumns(columns, fallbackWidths = {}) {
      return (columns || []).map((column) => ({
        fieldname: column.fieldname,
        columns: this.normalizeColumnWidth(column.columns, fallbackWidths[column.fieldname] ?? 2),
        sticky: column.sticky ? 1 : 0,
      }));
    },
  };
  const restrictionHelper = globalThis.ashanCnRestrictedDocActions || {
    canOpenRestrictionGroup(doc) {
      return Boolean(doc?.custom_is_restricted_doc && doc?.custom_restriction_group);
    },
    canOpenSourceDocument(doc) {
      return Boolean(doc?.custom_restriction_root_doctype && doc?.custom_restriction_root_name);
    },
  };

  function flt(value, precision) {
    if (typeof globalThis.flt === "function") {
      return globalThis.flt(value || 0, precision);
    }
    return Number.parseFloat(value || 0).toFixed(precision ?? 2) * 1;
  }

  function hasValue(value) {
    return value !== undefined && value !== null && value !== "" && flt(value) !== 0;
  }

  function hasInputValue(value) {
    return value !== undefined && value !== null && value !== "";
  }

  function inferMode(row) {
    if (row.custom_tax_basis) {
      return row.custom_tax_basis;
    }
    if (hasValue(row.custom_gross_amount) && !hasValue(row.amount)) {
      return "gross_amount";
    }
    if (hasValue(row.custom_gross_rate) && !hasValue(row.rate)) {
      return "gross_rate";
    }
    if (hasValue(row.amount) && !hasValue(row.rate)) {
      return "net_amount";
    }
    return "net_rate";
  }

  function calculateValues({ qty, taxRate, mode, basisValue }) {
    if (!qty) {
      return null;
    }

    const taxMultiplier = 1 + taxRate / 100;
    let netRate = 0;
    let grossRate = 0;
    let netAmount = 0;
    let taxAmount = 0;
    let grossAmount = 0;

    if (mode === "net_rate") {
      netRate = flt(basisValue, 6);
      netAmount = flt(qty * netRate, 2);
      taxAmount = flt((netAmount * taxRate) / 100, 2);
      grossAmount = flt(netAmount + taxAmount, 2);
      grossRate = flt(grossAmount / qty, 6);
    } else if (mode === "gross_rate") {
      grossRate = flt(basisValue, 6);
      grossAmount = flt(qty * grossRate, 2);
      netAmount = flt(grossAmount / taxMultiplier, 2);
      taxAmount = flt(grossAmount - netAmount, 2);
      netRate = flt(netAmount / qty, 6);
    } else if (mode === "net_amount") {
      netAmount = flt(basisValue, 2);
      netRate = flt(netAmount / qty, 6);
      taxAmount = flt((netAmount * taxRate) / 100, 2);
      grossAmount = flt(netAmount + taxAmount, 2);
      grossRate = flt(grossAmount / qty, 6);
    } else if (mode === "gross_amount") {
      grossAmount = flt(basisValue, 2);
      grossRate = flt(grossAmount / qty, 6);
      netAmount = flt(grossAmount / taxMultiplier, 2);
      taxAmount = flt(grossAmount - netAmount, 2);
      netRate = flt(netAmount / qty, 6);
    } else {
      return null;
    }

    return {
      mode,
      rate: netRate,
      amount: netAmount,
      custom_gross_rate: grossRate,
      custom_tax_amount: taxAmount,
      custom_gross_amount: grossAmount,
    };
  }

  function resolveModeAndValue(row, preferredMode) {
    const preferredField = modeToField[preferredMode];
    if (hasInputValue(row[preferredField])) {
      return { mode: preferredMode, basisValue: flt(row[preferredField]) };
    }

    for (const mode of fallbackModeOrder) {
      const fieldname = modeToField[mode];
      if (hasInputValue(row[fieldname])) {
        return { mode, basisValue: flt(row[fieldname]) };
      }
    }

    return null;
  }

  function supportsStandardTaxBridge(frm) {
    return taxBridgeParents.has(frm?.doctype);
  }

  function parseItemTaxRate(row) {
    if (!row?.item_tax_rate) {
      return {};
    }

    if (typeof row.item_tax_rate === "object") {
      return row.item_tax_rate;
    }

    try {
      return JSON.parse(row.item_tax_rate);
    } catch (_error) {
      return {};
    }
  }

  function taxBridgeNeedsSync(frm, row) {
    if (!supportsStandardTaxBridge(frm)) {
      return false;
    }

    const taxMap = parseItemTaxRate(row);
    const accountHeads = Object.keys(taxMap || {});
    const mappedRates = Object.values(taxMap || {});
    if (!row?.item_tax_template || !mappedRates.length || !accountHeads.length) {
      return true;
    }

    if (frm?.doc?.taxes_and_charges && !(frm.doc.taxes || []).length) {
      return true;
    }

    if ((frm?.doc?.taxes || []).length) {
      const matchesExistingTaxRow = accountHeads.some((accountHead) =>
        (frm.doc.taxes || []).some((tax) => tax.account_head === accountHead),
      );
      if (!matchesExistingTaxRow) {
        return true;
      }
    }

    return mappedRates.some((value) => flt(value) !== flt(row.custom_tax_rate));
  }

  function ensureClientTaxRows(frm, taxRows, activeAccountHead = null) {
    if (!frm?.fields_dict?.taxes) {
      return false;
    }

    if (activeAccountHead) {
      frm.doc.taxes = (frm.doc.taxes || []).filter((taxRow) => {
        if (!taxRow?.set_by_item_tax_template) {
          return true;
        }
        return taxRow.account_head === activeAccountHead;
      });
      frm.refresh_field("taxes");
    }

    if (!Array.isArray(taxRows) || !taxRows.length) {
      return false;
    }

    const existingHeads = new Set((frm.doc.taxes || []).map((row) => row.account_head).filter(Boolean));
    let added = false;

    taxRows.forEach((taxRow) => {
      if (!taxRow?.account_head || existingHeads.has(taxRow.account_head)) {
        return;
      }
      frm.add_child("taxes", taxRow);
      existingHeads.add(taxRow.account_head);
      added = true;
    });

    if (added) {
      frm.refresh_field("taxes");
    }

    return added;
  }

  async function recalculateStandardTaxes(frm) {
    if (!supportsStandardTaxBridge(frm) || frm.__ashan_cn_standard_tax_guard) {
      return;
    }

    frm.__ashan_cn_standard_tax_guard = true;
    try {
      if (frm.cscript && typeof frm.cscript.calculate_taxes_and_totals === "function") {
        await frm.cscript.calculate_taxes_and_totals();
      } else {
        await frm.trigger("calculate_taxes_and_totals");
      }
      frm.refresh_field("taxes");
      frm.refresh_fields(["total_taxes_and_charges", "grand_total", "net_total"]);
    } finally {
      frm.__ashan_cn_standard_tax_guard = false;
    }
  }

  async function syncStandardTaxBridge(frm, row) {
    if (!supportsStandardTaxBridge(frm)) {
      return;
    }

    if (!taxBridgeNeedsSync(frm, row)) {
      await recalculateStandardTaxes(frm);
      return;
    }

    if (frm.__ashan_cn_tax_bridge_guard) {
      return;
    }

    frm.__ashan_cn_tax_bridge_guard = true;
    try {
      const response = await frappe.call({
        method: "ashan_cn_procurement.api.tax_bridge.resolve_purchase_tax_bridge",
        args: {
          doc: frm.doc,
          tax_rate: flt(row.custom_tax_rate),
        },
        freeze: false,
      });
      const message = response?.message;
      if (!message?.account_head) {
        return;
      }

      row.item_tax_template = message.item_tax_template;
      row.item_tax_rate = message.item_tax_rate;
      ensureClientTaxRows(frm, message.tax_rows || [], message.account_head);
      frm.refresh_field(row.parentfield || "items");
      await recalculateStandardTaxes(frm);
    } finally {
      frm.__ashan_cn_tax_bridge_guard = false;
    }
  }

  async function recalculateRow(frm, cdt, cdn, forcedMode = null) {
    if (frm.__ashan_cn_recalc_guard) {
      return;
    }

    const row = locals[cdt][cdn];
    if (!row) {
      return;
    }

    const qty = flt(row.qty);
    if (!qty) {
      return;
    }

    const preferredMode = forcedMode || inferMode(row);
    const resolved = resolveModeAndValue(row, preferredMode);
    if (!resolved) {
      return;
    }

    const values = calculateValues({
      qty,
      taxRate: flt(row.custom_tax_rate),
      mode: resolved.mode,
      basisValue: resolved.basisValue,
    });
    if (!values) {
      return;
    }

    frm.__ashan_cn_recalc_guard = true;
    Object.assign(row, values, { custom_tax_basis: values.mode });
    frm.refresh_field(row.parentfield || "items");
    frm.__ashan_cn_recalc_guard = false;

    await syncStandardTaxBridge(frm, row);
  }

  function getItemsGrid(frm) {
    return frm?.fields_dict?.items?.grid || null;
  }

  function getVisibleGridColumns(frm) {
    const grid = getItemsGrid(frm);
    if (!grid) {
      return [];
    }

    grid.visible_columns = null;
    if (typeof grid.setup_visible_columns === "function") {
      grid.setup_visible_columns();
    }

    return (grid.visible_columns || []).map(([df, colsize]) => ({
      fieldname: df.fieldname,
      label: __(df.label, null, grid.doctype),
      columns: gridSettingsHelper.normalizeColumnWidth(df.columns || colsize || df.colsize || 2, 2),
      sticky: df.sticky ? 1 : 0,
    }));
  }

  function renderGridColumnRows(columns) {
    return columns
      .map(
        (column) => `
          <div class="grid-width-row row" style="margin-bottom: 8px; align-items: center;" data-fieldname="${column.fieldname}">
            <div class="col-sm-7" style="padding-top: 6px;">${frappe.utils.escape_html(column.label)}</div>
            <div class="col-sm-5">
              <input
                class="form-control column-width text-right"
                data-fieldname="${column.fieldname}"
                type="number"
                min="1"
                step="1"
                value="${column.columns}"
              />
            </div>
          </div>
        `,
      )
      .join("");
  }

  function bindGridColumnInputs(dialog, selectedColumns, fallbackWidths) {
    const wrapper = dialog.get_field("columns_html").$wrapper;
    wrapper.off("change", ".column-width");
    wrapper.on("change", ".column-width", (event) => {
      const fieldname = event.currentTarget.dataset.fieldname;
      const nextWidth = gridSettingsHelper.normalizeColumnWidth(
        event.currentTarget.value,
        fallbackWidths[fieldname] ?? 2,
      );
      event.currentTarget.value = nextWidth;

      selectedColumns.forEach((column) => {
        if (column.fieldname === fieldname) {
          column.columns = nextWidth;
        }
      });
    });
  }

  function saveGridColumnSettings(frm, dialog, selectedColumns, fallbackWidths) {
    const grid = getItemsGrid(frm);
    if (!grid) {
      return;
    }

    const payload = {};
    payload[grid.doctype] = gridSettingsHelper.normalizeSelectedColumns(selectedColumns, fallbackWidths);

    frappe.model.user_settings.save(frm.doctype, "GridView", payload).then((response) => {
      frappe.model.user_settings[frm.doctype] = response.message || response;
      grid.reset_grid();
      dialog.hide();
      frappe.show_alert({
        message: __("明细列宽已保存，可填写大于 10 的宽度值"),
        indicator: "green",
      });
    });
  }

  function resetGridColumnSettings(frm, dialog) {
    const grid = getItemsGrid(frm);
    if (!grid) {
      return;
    }

    frappe.model.user_settings.save(frm.doctype, "GridView", null).then((response) => {
      frappe.model.user_settings[frm.doctype] = response.message || response;
      grid.reset_grid();
      dialog.hide();
      frappe.show_alert({
        message: __("已恢复默认明细列宽"),
        indicator: "green",
      });
    });
  }

  function openGridWidthDialog(frm) {
    const visibleColumns = getVisibleGridColumns(frm);
    if (!visibleColumns.length) {
      frappe.msgprint(__("当前明细没有可配置的可见列。"));
      return;
    }

    const selectedColumns = visibleColumns.map((column) => ({ ...column }));
    const fallbackWidths = Object.fromEntries(
      visibleColumns.map((column) => [column.fieldname, column.columns]),
    );

    const dialog = new frappe.ui.Dialog({
      title: __("配置明细列宽"),
      fields: [
        {
          fieldtype: "HTML",
          fieldname: "columns_html",
        },
      ],
      primary_action_label: __("保存"),
      primary_action() {
        saveGridColumnSettings(frm, dialog, selectedColumns, fallbackWidths);
      },
      secondary_action_label: __("重置"),
      secondary_action() {
        resetGridColumnSettings(frm, dialog);
      },
    });

    dialog.get_field("columns_html").$wrapper.html(`
      <div class="grid-width-configurator">
        <p class="text-muted small" style="margin-bottom: 12px;">
          ${__("这里保存的是当前用户的明细列宽。宽度值支持任意正整数，不受 Customize Form 里 1-10 的静态限制。")}
        </p>
        ${renderGridColumnRows(selectedColumns)}
      </div>
    `);
    bindGridColumnInputs(dialog, selectedColumns, fallbackWidths);
    dialog.show();
  }

  function addGridWidthButton(frm) {
    if (!getItemsGrid(frm)) {
      return;
    }

    frm.add_custom_button(__("配置明细列宽"), () => openGridWidthDialog(frm), __("明细"));
  }

  function addRestrictionButtons(frm) {
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
  }

  function addPurchaseInvoiceButtons(frm) {
    if (frm?.doctype !== "Purchase Invoice" || !frm.doc?.name || frm.is_new()) {
      return;
    }

    frm.add_custom_button(__("创建报销单"), async () => {
      const response = await frappe.call({
        method: "ashan_cn_procurement.api.reimbursement.create_reimbursement_from_purchase_invoice",
        args: { purchase_invoice: frm.doc.name },
        freeze: true,
      });
      const message = response?.message;
      if (!message?.name) {
        return;
      }
      frappe.show_alert({
        message: message.created ? __("已创建报销单 {0}", [message.name]) : __("已打开已存在报销单 {0}", [message.name]),
        indicator: "green",
      });
      frappe.set_route("Form", message.doctype || "Reimbursement Request", message.name);
    }, __("报销"));
  }

  function isPurchaseInvoiceTypeRequiringBillNo(invoiceType) {
    return invoiceType === "专用发票" || invoiceType === "普通发票";
  }

  async function syncPurchaseInvoiceBillNoState(frm) {
    if (frm?.doctype !== "Purchase Invoice") {
      return;
    }

    const invoiceType = frm.doc.custom_invoice_type;
    const billNoRequired = isPurchaseInvoiceTypeRequiringBillNo(invoiceType);
    frm.set_df_property("bill_no", "reqd", billNoRequired);
    frm.set_df_property(
      "bill_no",
      "description",
      invoiceType === "无发票"
        ? __("无发票时发票号留空")
        : billNoRequired
          ? __("请填写真实发票号")
          : __("请选择发票类型后再决定是否需要填写发票号"),
    );

    if (frm.doc.bill_no === "0" || (invoiceType === "无发票" && frm.doc.bill_no)) {
      await frm.set_value("bill_no", "");
    }
  }

  async function handlePurchaseInvoiceTypeChange(frm) {
    if (frm?.doctype !== "Purchase Invoice") {
      return;
    }

    await syncPurchaseInvoiceBillNoState(frm);

    frm.doc.taxes = (frm.doc.taxes || []).filter((taxRow) => !taxRow?.set_by_item_tax_template);
    frm.refresh_field("taxes");

    for (const row of frm.doc.items || []) {
      row.item_tax_template = null;
      row.item_tax_rate = null;
      await recalculateRow(frm, row.doctype, row.name);
    }
  }

  function registerChildHandlers(childDoctype) {
    frappe.ui.form.on(childDoctype, {
      qty(frm, cdt, cdn) {
        recalculateRow(frm, cdt, cdn);
      },
      custom_tax_rate(frm, cdt, cdn) {
        recalculateRow(frm, cdt, cdn);
      },
      rate(frm, cdt, cdn) {
        recalculateRow(frm, cdt, cdn, "net_rate");
      },
      custom_gross_rate(frm, cdt, cdn) {
        recalculateRow(frm, cdt, cdn, "gross_rate");
      },
      amount(frm, cdt, cdn) {
        recalculateRow(frm, cdt, cdn, "net_amount");
      },
      custom_gross_amount(frm, cdt, cdn) {
        recalculateRow(frm, cdt, cdn, "gross_amount");
      },
    });
  }

  Object.entries(parentToChild).forEach(([parentDoctype, childDoctype]) => {
    registerChildHandlers(childDoctype);
    frappe.ui.form.on(parentDoctype, {
      refresh(frm) {
        addGridWidthButton(frm);
        addRestrictionButtons(frm);
        addPurchaseInvoiceButtons(frm);
        if (frm?.doctype === "Purchase Invoice") {
          void syncPurchaseInvoiceBillNoState(frm);
        }
      },
      custom_invoice_type(frm) {
        void handlePurchaseInvoiceTypeChange(frm);
      },
      taxes_and_charges(frm) {
        (frm.doc.items || []).forEach((row) => {
          row.item_tax_template = null;
          row.item_tax_rate = null;
          void recalculateRow(frm, row.doctype, row.name);
        });
      },
      validate(frm) {
        (frm.doc.items || []).forEach((row) => {
          recalculateRow(frm, row.doctype, row.name);
        });
      },
    });
  });
})();

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
      taxAmount = flt(netAmount * taxRate / 100, 2);
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
      taxAmount = flt(netAmount * taxRate / 100, 2);
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

  function recalculateRow(frm, cdt, cdn, forcedMode = null) {
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
      validate(frm) {
        (frm.doc.items || []).forEach((row) => {
          recalculateRow(frm, row.doctype, row.name);
        });
      },
    });
  });
})();

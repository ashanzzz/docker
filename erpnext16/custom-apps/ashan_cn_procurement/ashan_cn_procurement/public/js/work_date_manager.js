(() => {
  const WORK_DATE_DEFAULT_KEY = "ashan_work_date";
  const DATE_FIELD_KEYS = ["posting_date", "transaction_date", "schedule_date", "bill_date"];
  const DEFAULT_KEYS = [WORK_DATE_DEFAULT_KEY, ...DATE_FIELD_KEYS];

  function getCurrentWorkDate() {
    return frappe.defaults.get_user_default(WORK_DATE_DEFAULT_KEY) || null;
  }

  function syncLocalDefaults(workDate) {
    frappe.boot.user.defaults = frappe.boot.user.defaults || {};

    DEFAULT_KEYS.forEach((key) => {
      if (workDate) {
        frappe.boot.user.defaults[key] = workDate;
        frappe.defaults.set_user_default_local(key, workDate);
      } else {
        delete frappe.boot.user.defaults[key];
      }
    });
  }

  function getBlankDateUpdates(frm, workDate) {
    const updates = {};

    DATE_FIELD_KEYS.forEach((fieldname) => {
      if (frm.fields_dict?.[fieldname] && !frm.doc?.[fieldname]) {
        updates[fieldname] = workDate;
      }
    });

    if (frm.fields_dict?.set_posting_time && !frm.doc?.set_posting_time) {
      updates.set_posting_time = 1;
    }

    return updates;
  }

  async function applyWorkDateToForm(frm, options = {}) {
    const { force = false } = options;
    if (!frm || typeof frm.is_new !== "function" || !frm.is_new()) {
      return;
    }

    const workDate = getCurrentWorkDate();
    if (!workDate || frm.__ashan_work_date_applying) {
      return;
    }

    const updates = getBlankDateUpdates(frm, workDate);
    if (!Object.keys(updates).length && !force) {
      return;
    }

    frm.__ashan_work_date_applying = true;
    try {
      if (Object.keys(updates).length) {
        await frm.set_value(updates);
      }
      frm.__ashan_last_applied_work_date = workDate;
    } finally {
      frm.__ashan_work_date_applying = false;
    }
  }

  function openWorkDateDialog(frm) {
    const dialog = new frappe.ui.Dialog({
      title: __("设定业务日期"),
      fields: [
        {
          fieldtype: "Date",
          fieldname: "work_date",
          label: __("业务日期"),
          default: getCurrentWorkDate() || frappe.datetime.get_today(),
          reqd: 1,
        },
        {
          fieldtype: "Check",
          fieldname: "apply_open_form",
          label: __("立即回填当前新单据的空日期字段"),
          default: 1,
        },
      ],
      primary_action_label: __("保存"),
      primary_action(values) {
        frappe.call({
          method: "ashan_cn_procurement.api.work_date.set_work_date",
          args: { work_date: values.work_date },
          freeze: true,
          callback: async ({ message }) => {
            if (!message?.work_date) {
              return;
            }

            syncLocalDefaults(message.work_date);
            dialog.hide();
            if (values.apply_open_form) {
              await applyWorkDateToForm(frm, { force: true });
              frm.refresh();
            }
            frappe.show_alert({
              message: __("业务日期已设为 {0}", [message.work_date]),
              indicator: "green",
            });
          },
        });
      },
    });

    dialog.show();
  }

  function clearWorkDate(frm) {
    frappe.call({
      method: "ashan_cn_procurement.api.work_date.clear_work_date",
      freeze: true,
      callback: ({ message }) => {
        if (!message?.cleared) {
          return;
        }

        syncLocalDefaults(null);
        frm.refresh();
        frappe.show_alert({
          message: __("业务日期默认值已清除"),
          indicator: "green",
        });
      },
    });
  }

  function addWorkDateButtons(frm) {
    if (!frm || !frm.page || typeof frm.add_custom_button !== "function") {
      return;
    }

    const currentWorkDate = getCurrentWorkDate();
    const group = __("业务日期");
    const label = currentWorkDate ? __("当前：{0}", [currentWorkDate]) : __("设定业务日期");

    frm.add_custom_button(label, () => openWorkDateDialog(frm), group);

    if (currentWorkDate) {
      frm.add_custom_button(__("清除业务日期"), () => clearWorkDate(frm), group);
    }
  }

  if (!frappe.ui?.form?.Form || frappe.ui.form.Form.__ashan_work_date_patched) {
    return;
  }

  const originalRefresh = frappe.ui.form.Form.prototype.refresh;
  frappe.ui.form.Form.prototype.refresh = function (...args) {
    const result = originalRefresh.apply(this, args);
    Promise.resolve(result)
      .then(() => applyWorkDateToForm(this))
      .then(() => addWorkDateButtons(this))
      .catch((error) => {
        console.error("ashan work date manager failed", error);
      });
    return result;
  };
  frappe.ui.form.Form.__ashan_work_date_patched = true;
})();

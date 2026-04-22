(function (root, factory) {
  const exports = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = exports;
  }
  root.ashanCnRestrictedAccessGroupForm = exports;
  if (root.frappe?.ui?.form?.on) {
    exports.register(root.frappe);
  }
})(typeof globalThis !== "undefined" ? globalThis : window, function () {
  const BASE_TIP = "配置建议：优先维护角色成员；只有个别人需要额外可见时再放到用户成员。总经理等全局查看者请通过 Restricted Document Super Viewer 配置；临时例外请在具体单据上使用共享（Share）。";

  function normalizeText(value) {
    if (value === undefined || value === null) {
      return "";
    }
    return String(value).trim();
  }

  function normalizeRows(rows) {
    return Array.isArray(rows) ? rows.filter(Boolean) : [];
  }

  function isActive(doc) {
    return [1, "1", true, "true", "True"].includes(doc?.is_active);
  }

  function hasAnyMembers(doc) {
    return normalizeRows(doc?.user_members).length > 0 || normalizeRows(doc?.role_members).length > 0;
  }

  function usesReservedAccessLevels(doc) {
    return [...normalizeRows(doc?.user_members), ...normalizeRows(doc?.role_members)].some((row) => {
      const accessLevel = normalizeText(row?.access_level).toLowerCase();
      return accessLevel && accessLevel !== "viewer";
    });
  }

  function buildDefaultDescription(doc) {
    const groupName = normalizeText(doc?.group_name) || "本受限组";
    return [
      `${groupName}用于控制受限单据的默认可见范围。`,
      "优先维护角色成员；仅对个别人单独加入用户成员。",
      "总经理等全局查看者请通过 Restricted Document Super Viewer 配置。",
      "临时例外请在具体单据上使用共享（Share）。",
    ].join("\n");
  }

  function getConfigurationWarnings(doc) {
    const warnings = [];
    if (isActive(doc) && !hasAnyMembers(doc)) {
      warnings.push("当前受限组已启用，但没有任何用户或角色成员。除 Restricted Document Super Viewer 和单据共享外，其他人都看不到挂到本组的受限单据。");
    }
    if (usesReservedAccessLevels(doc)) {
      warnings.push("“访问级别（预留）”当前版本仅作提示，不单独控制查看、编辑或管理权限；真正生效的是是否在组内、是否拥有 Restricted Document Super Viewer，以及是否被单据共享。");
    }
    return warnings;
  }

  function getConfigurationTips(doc) {
    const tips = [];
    if (normalizeRows(doc?.user_members).length > 0 && normalizeRows(doc?.role_members).length === 0) {
      tips.push("当前仅配置了指定用户。若同岗位多人都需要可见，建议优先维护角色成员，后续换人时不用回头改单据。");
    }
    if (!tips.length) {
      tips.push(BASE_TIP);
    }
    return tips;
  }

  function buildGuideHtml(doc) {
    const tips = getConfigurationTips(doc);
    const warnings = getConfigurationWarnings(doc);

    const tipItems = tips.map((tip) => `<li>${tip}</li>`).join("");
    const warningItems = warnings.map((warning) => `<li>${warning}</li>`).join("");

    return `
      <div class="small text-muted" style="line-height: 1.7;">
        <div><strong>配置原则</strong></div>
        <ul style="margin: 8px 0 0 18px; padding: 0;">
          ${tipItems}
        </ul>
        ${warnings.length ? `
          <div style="margin-top: 10px; color: #c05621;"><strong>防误配提醒</strong></div>
          <ul style="margin: 8px 0 0 18px; padding: 0; color: #c05621;">
            ${warningItems}
          </ul>
        ` : ""}
      </div>
    `;
  }

  function maybeApplyDefaultDescription(frm) {
    if (!frm?.is_new || !frm.is_new()) {
      return;
    }
    if (normalizeText(frm.doc?.description)) {
      return;
    }
    frm.set_value("description", buildDefaultDescription(frm.doc));
  }

  function refreshConfigurationGuidance(frm) {
    const guideField = frm.get_field?.("configuration_guide_html");
    if (guideField?.$wrapper) {
      guideField.$wrapper.html(buildGuideHtml(frm.doc));
    }

    if (typeof frm.set_intro === "function") {
      const warnings = getConfigurationWarnings(frm.doc);
      if (warnings.length) {
        frm.set_intro("存在防误配提醒，请先看上方配置说明后再保存。", "orange");
      } else {
        frm.set_intro("配置建议已显示在上方：优先按角色维护，个别人再单独加用户。", "blue");
      }
    }
  }

  function showActivationWarning(frappe, doc) {
    if (!isActive(doc) || hasAnyMembers(doc) || typeof frappe?.show_alert !== "function") {
      return;
    }
    frappe.show_alert(
      {
        message: "当前受限组已启用但还没有配置成员，挂到本组的受限单据会几乎没人可见。",
        indicator: "orange",
      },
      7,
    );
  }

  function showReservedAccessLevelAlert(frappe, doc) {
    if (!usesReservedAccessLevels(doc) || typeof frappe?.show_alert !== "function") {
      return;
    }
    frappe.show_alert(
      {
        message: "“访问级别（预留）”当前只作提示，不单独控制查看/编辑/管理权限。",
        indicator: "blue",
      },
      7,
    );
  }

  function register(frappe) {
    const refreshGuide = (frm) => refreshConfigurationGuidance(frm);

    frappe.ui.form.on("Restricted Access Group", {
      onload(frm) {
        maybeApplyDefaultDescription(frm);
        refreshGuide(frm);
      },
      refresh(frm) {
        maybeApplyDefaultDescription(frm);
        refreshGuide(frm);
      },
      group_name(frm) {
        maybeApplyDefaultDescription(frm);
        refreshGuide(frm);
      },
      is_active(frm) {
        refreshGuide(frm);
        showActivationWarning(frappe, frm.doc);
      },
      user_members_add(frm) {
        refreshGuide(frm);
      },
      user_members_remove(frm) {
        refreshGuide(frm);
      },
      role_members_add(frm) {
        refreshGuide(frm);
      },
      role_members_remove(frm) {
        refreshGuide(frm);
      },
    });

    frappe.ui.form.on("Restricted Access Group User", {
      user: refreshGuide,
      access_level(frm) {
        refreshGuide(frm);
        showReservedAccessLevelAlert(frappe, frm.doc);
      },
    });

    frappe.ui.form.on("Restricted Access Group Role", {
      role: refreshGuide,
      access_level(frm) {
        refreshGuide(frm);
        showReservedAccessLevelAlert(frappe, frm.doc);
      },
    });
  }

  return {
    BASE_TIP,
    buildDefaultDescription,
    buildGuideHtml,
    getConfigurationTips,
    getConfigurationWarnings,
    hasAnyMembers,
    isActive,
    normalizeText,
    register,
    usesReservedAccessLevels,
  };
});

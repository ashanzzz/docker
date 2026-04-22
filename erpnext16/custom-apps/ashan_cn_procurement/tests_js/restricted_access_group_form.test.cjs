const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildDefaultDescription,
  getConfigurationWarnings,
  getConfigurationTips,
} = require("../ashan_cn_procurement/public/js/restricted_access_group_form.js");

test("buildDefaultDescription includes group name and operator guidance", () => {
  const description = buildDefaultDescription({ group_name: "采购核心组" });

  assert.match(description, /采购核心组/);
  assert.match(description, /优先维护角色成员/);
  assert.match(description, /Restricted Document Super Viewer/);
  assert.match(description, /Share/);
});

test("getConfigurationWarnings warns when active group has no members", () => {
  const warnings = getConfigurationWarnings({
    is_active: 1,
    user_members: [],
    role_members: [],
  });

  assert.equal(warnings.length > 0, true);
  assert.match(warnings.join("\n"), /已启用/);
  assert.match(warnings.join("\n"), /没有任何用户或角色成员/);
});

test("getConfigurationWarnings explains reserved access level semantics", () => {
  const warnings = getConfigurationWarnings({
    is_active: 1,
    user_members: [{ user: "demo@example.com", access_level: "manager" }],
    role_members: [],
  });

  assert.match(warnings.join("\n"), /访问级别.*预留/);
  assert.match(warnings.join("\n"), /不单独控制查看/);
});

test("getConfigurationTips nudges operators toward role-based maintenance", () => {
  const tips = getConfigurationTips({
    is_active: 1,
    user_members: [{ user: "buyer@example.com", access_level: "viewer" }],
    role_members: [],
  });

  assert.equal(tips.length > 0, true);
  assert.match(tips.join("\n"), /优先维护角色成员/);
});

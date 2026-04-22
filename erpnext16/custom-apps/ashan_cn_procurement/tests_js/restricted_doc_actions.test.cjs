const test = require("node:test");
const assert = require("node:assert/strict");

const {
  canOpenRestrictionGroup,
  canOpenSourceDocument,
} = require("../ashan_cn_procurement/public/js/restricted_doc_actions.js");

test("canOpenRestrictionGroup requires restricted flag and group name", () => {
  assert.equal(canOpenRestrictionGroup({ custom_is_restricted_doc: 1, custom_restriction_group: "采购核心组" }), true);
  assert.equal(canOpenRestrictionGroup({ custom_is_restricted_doc: 0, custom_restriction_group: "采购核心组" }), false);
  assert.equal(canOpenRestrictionGroup({ custom_is_restricted_doc: 1, custom_restriction_group: "" }), false);
});

test("canOpenSourceDocument requires source doctype and name", () => {
  assert.equal(canOpenSourceDocument({ custom_restriction_root_doctype: "Material Request", custom_restriction_root_name: "MR-0001" }), true);
  assert.equal(canOpenSourceDocument({ custom_restriction_root_doctype: "", custom_restriction_root_name: "MR-0001" }), false);
  assert.equal(canOpenSourceDocument({ custom_restriction_root_doctype: "Material Request", custom_restriction_root_name: "" }), false);
});

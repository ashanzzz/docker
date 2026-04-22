(function (root, factory) {
  const exports = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = exports;
  }
  root.ashanCnRestrictedDocActions = exports;
})(typeof globalThis !== "undefined" ? globalThis : window, function () {
  function isRestricted(doc) {
    return [1, "1", true, "true", "True"].includes(doc?.custom_is_restricted_doc);
  }

  function normalizeText(value) {
    if (value === undefined || value === null) {
      return "";
    }
    return String(value).trim();
  }

  function canOpenRestrictionGroup(doc) {
    return isRestricted(doc) && Boolean(normalizeText(doc?.custom_restriction_group));
  }

  function canOpenSourceDocument(doc) {
    return Boolean(normalizeText(doc?.custom_restriction_root_doctype) && normalizeText(doc?.custom_restriction_root_name));
  }

  return {
    canOpenRestrictionGroup,
    canOpenSourceDocument,
    isRestricted,
    normalizeText,
  };
});

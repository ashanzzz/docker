(function (root, factory) {
  const exports = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = exports;
  }
  root.ashanCnProcurementGridSettings = exports;
})(typeof globalThis !== "undefined" ? globalThis : window, function () {
  function normalizeColumnWidth(value, fallback = 2) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed) && parsed > 0) {
      return parsed;
    }
    return Number.parseInt(fallback, 10) > 0 ? Number.parseInt(fallback, 10) : 2;
  }

  function normalizeSelectedColumns(columns, fallbackWidths = {}) {
    return (columns || []).map((column) => ({
      fieldname: column.fieldname,
      columns: normalizeColumnWidth(column.columns, fallbackWidths[column.fieldname] ?? 2),
      sticky: column.sticky ? 1 : 0,
    }));
  }

  return {
    normalizeColumnWidth,
    normalizeSelectedColumns,
  };
});

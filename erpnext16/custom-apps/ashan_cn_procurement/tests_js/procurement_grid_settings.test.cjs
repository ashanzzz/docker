const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeColumnWidth,
  normalizeSelectedColumns,
} = require('../ashan_cn_procurement/public/js/procurement_grid_settings.js');

test('normalizeColumnWidth keeps positive integers', () => {
  assert.equal(normalizeColumnWidth('12', 3), 12);
  assert.equal(normalizeColumnWidth(7, 3), 7);
});

test('normalizeColumnWidth falls back for blank or invalid widths', () => {
  assert.equal(normalizeColumnWidth('', 4), 4);
  assert.equal(normalizeColumnWidth(0, 4), 4);
  assert.equal(normalizeColumnWidth('-2', 4), 4);
  assert.equal(normalizeColumnWidth('abc', 4), 4);
});

test('normalizeSelectedColumns preserves order and sanitizes widths', () => {
  assert.deepEqual(
    normalizeSelectedColumns(
      [
        { fieldname: 'item_code', columns: '8', sticky: 1 },
        { fieldname: 'custom_line_remark', columns: '0', sticky: 0 },
      ],
      { item_code: 3, custom_line_remark: 5 },
    ),
    [
      { fieldname: 'item_code', columns: 8, sticky: 1 },
      { fieldname: 'custom_line_remark', columns: 5, sticky: 0 },
    ],
  );
});

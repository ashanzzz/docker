# ERPNext16 油卡管理 DocType JSON 顺序稿（拟建 JSON / field_order / insert_after / depends_on）

> **Status:** 拟建 JSON 顺序稿，目标是把 `phase5c` 的字段清单和 `phase5d` 的布局稿继续收敛到“后续可以直接照着写 DocType JSON / Custom Field”的粒度。
>
> **Related:**
> - `docs/plans/2026-04-22-phase5-oil-card-management.md`：业务研究稿
> - `docs/plans/2026-04-22-phase5b-oil-card-implementation-plan.md`：实施计划、报表、工作台
> - `docs/plans/2026-04-22-phase5c-oil-card-field-checklist.md`：字段清单版
> - `docs/plans/2026-04-22-phase5d-oil-card-form-layout-draft.md`：表单布局稿
> - `docs/plans/2026-04-22-phase3-invoice-type-vat-and-reimbursement.md`：报销单与报销人设计

**Goal:** 明确每个油卡相关对象在 Frappe/ERPNext 里的拟建 JSON 顺序，包括 `field_order`、`Section Break` / `Column Break` 的具体 fieldname、HTML 字段名、关键 `depends_on` / `mandatory_depends_on` / `fetch_from` 建议，以及标准 DocType 扩展时的 `insert_after` 思路，避免后续进入代码阶段时再反复讨论“这个字段到底插哪儿”。

**Architecture:** 延续前序文档的总体边界：标准 `Vehicle` 继续做车辆主数据，正式发票继续使用标准 `Purchase Invoice`，付款继续走标准 `Payment Entry`，油卡领域新增 `Oil Card`、`Oil Card Recharge`、`Oil Card Refuel Log`、`Oil Card Invoice Batch`、`Oil Card Invoice Batch Item`。本文件只解决“DocType / Custom Field JSON 怎么排”，不替代业务规则、报表矩阵与工作台设计。

**Tech Stack:** ERPNext 16, Frappe 16 Desk metadata, custom app `ashan_cn_procurement`, DocType JSON, `setup/custom_fields.py`, form JS, standard Link / Table / HTML / Section Break / Column Break.

---

## 变更记录 / 为什么这么写

| 版本 | 日期 | 改了什么 | 为什么这么改 |
|---|---|---|---|
| v1.0 | 2026-04-22 | 新增拟建 JSON 顺序稿，补齐各 DocType 的 `field_order`、布局字段 fieldname、标准表扩展插入顺序、关键属性建议 | 有了字段清单和表单布局稿后，下一步最容易反复的就是 DocType JSON 实际顺序；这份文档就是为了把“怎么排 JSON”提前定稿 |

### 后续修改规范
如果后续要改：
- `field_order`
- `Section Break / Column Break / HTML` 的 fieldname
- `insert_after`
- `depends_on / mandatory_depends_on / fetch_from`
- `quick_entry / title_field / search_fields`

都要补 3 条：
1. 改了哪个 DocType / 哪个布局字段
2. 为什么原顺序或原属性不够用
3. 这次变更会影响哪些 JS、报表、数据迁移或用户操作习惯

---

## 一、统一 JSON 落地约定

## 1. 布局字段命名约定
统一使用：
- `sb_` 前缀：`Section Break`
- `cb_` 前缀：`Column Break`
- `tb_` 前缀：`Tab Break`（本期原则上先不用）
- `*_html`：HTML 提示区

不要使用：
- `section_break_1`
- `column_break_2`
- `html_1`

原因：后续维护、前端脚本查找、文档对照都会更清楚。

## 2. 优先在 JSON 定死的属性
优先直接写在 JSON / custom field 定义里：
- `read_only`
- `reqd`
- `in_list_view`
- `in_standard_filter`
- `fetch_from`
- `depends_on`
- `mandatory_depends_on`
- `quick_entry`
- `title_field`
- `search_fields`

不要把这些基础属性都留给前端 JS 去补救。

## 3. `depends_on` 使用原则
只对真正需要联动的字段使用。

v1 明确建议：
- `Oil Card.layout_summary_html`：常显
- `Oil Card Refuel Log.vehicle_history_html`：仅在选择车辆后有内容
- `Oil Card Recharge` 的优惠辅助字段：只在有赠送/优惠信息时强调显示

不要把整张表做成大量字段闪烁显示/隐藏。

## 4. 标准 DocType 的扩展方式
### `Vehicle`
使用 `setup/custom_fields.py` 维护一整块连续 custom fields。

原则：
- 用一个 `Section Break` 把整块油卡信息包起来
- 整块连续插入，不要把只读历史字段散插到标准字段中间
- 如果未来 ERPNext v16.x.y 的标准字段顺序有轻微变化，优先保持“整块连续”，而不是死守某个锚点字段

### `Reimbursement Request`
建议直接更新现有 DocType JSON 的 `field_order` 和新增字段布局元素，保持：
- 报销人字段靠前
- 受限单据字段单独成段
- 金额与子表继续在后面

## 5. 对应文件位置（实施时）
- `Oil Card`：`erpnext16/custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/oil_card/oil_card.json`
- `Oil Card Recharge`：`.../doctype/oil_card_recharge/oil_card_recharge.json`
- `Oil Card Refuel Log`：`.../doctype/oil_card_refuel_log/oil_card_refuel_log.json`
- `Oil Card Invoice Batch`：`.../doctype/oil_card_invoice_batch/oil_card_invoice_batch.json`
- `Oil Card Invoice Batch Item`：`.../doctype/oil_card_invoice_batch_item/oil_card_invoice_batch_item.json`
- `Vehicle` custom fields：`erpnext16/custom-apps/ashan_cn_procurement/ashan_cn_procurement/setup/custom_fields.py`
- `Reimbursement Request`：`erpnext16/custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.json`

---

## 二、`Vehicle` Custom Field 顺序稿

> 说明：`Vehicle` 是标准 DocType，这里不写整张标准表的 `field_order`，只定义新增 custom block 的顺序与 `insert_after` 策略。

### 推荐插入策略
首选把整块插在标准里程/车辆状态摘要区之后。

如果当前标准 `Vehicle` 仍存在 `last_odometer` 之类里程锚点字段，可优先：
- `insert_after = last_odometer`

如果未来上游版本字段名有变：
- 保持“油卡信息”整块仍插在标准车辆摘要区后面
- 不要把这几个 custom fields 拆散

### 拟建 custom field 顺序
```python
vehicle_custom_fields = [
    {
        "fieldname": "custom_oil_card_section",
        "label": "油卡信息",
        "fieldtype": "Section Break",
        "insert_after": "last_odometer",
    },
    {
        "fieldname": "custom_vehicle_note",
        "label": "车辆备注",
        "fieldtype": "Small Text",
        "insert_after": "custom_oil_card_section",
    },
    {
        "fieldname": "custom_default_oil_card",
        "label": "默认油卡",
        "fieldtype": "Link",
        "options": "Oil Card",
        "insert_after": "custom_vehicle_note",
        "in_standard_filter": 1,
    },
    {
        "fieldname": "custom_oil_card_cb",
        "fieldtype": "Column Break",
        "insert_after": "custom_default_oil_card",
    },
    {
        "fieldname": "custom_last_refuel_date",
        "label": "上次加油日期",
        "fieldtype": "Date",
        "read_only": 1,
        "insert_after": "custom_oil_card_cb",
    },
    {
        "fieldname": "custom_last_refuel_liters",
        "label": "上次加油升数",
        "fieldtype": "Float",
        "read_only": 1,
        "insert_after": "custom_last_refuel_date",
    },
    {
        "fieldname": "custom_last_refuel_amount",
        "label": "上次加油金额",
        "fieldtype": "Currency",
        "read_only": 1,
        "insert_after": "custom_last_refuel_liters",
    },
    {
        "fieldname": "custom_last_refuel_odometer",
        "label": "上次加油里程",
        "fieldtype": "Int",
        "read_only": 1,
        "insert_after": "custom_last_refuel_amount",
    },
]
```

### 额外说明
- `custom_default_oil_card` 建议加到标准筛选中
- 4 个“上次加油”字段全部只读，不允许人工改
- 如果后面需要按钮组（新增加油记录 / 查看加油流水 / 查看油耗分析），放 JS，不写进 Custom Field JSON

---

## 三、`Oil Card` DocType JSON 顺序稿

### 建议元数据
- `module = Ashan CN Procurement`
- `document_type = Setup`
- `autoname = field:card_name`
- `title_field = card_name`
- `search_fields = card_name,card_no,supplier`
- `quick_entry = 0`
- `track_changes = 1`

### 推荐 `field_order`
```python
field_order = [
    "sb_basic_info",
    "card_name",
    "card_no",
    "cb_basic_info_right",
    "card_no_masked",
    "fuel_type",
    "sb_ownership",
    "company",
    "supplier",
    "cb_ownership_right",
    "default_vehicle",
    "status",
    "sb_balance",
    "opening_balance",
    "current_balance",
    "cb_balance_right",
    "uninvoiced_amount",
    "valid_from",
    "valid_upto",
    "sb_summary",
    "layout_summary_html",
    "sb_note",
    "note",
]
```

### 布局字段定义
| fieldname | fieldtype | label | 说明 |
|---|---|---|---|
| `sb_basic_info` | Section Break | 基本信息 | 第一屏左/右列起点 |
| `cb_basic_info_right` | Column Break |  | 基本信息右列 |
| `sb_ownership` | Section Break | 归属信息 | 公司 / 供应商 / 默认车辆 / 状态 |
| `cb_ownership_right` | Column Break |  | 归属信息右列 |
| `sb_balance` | Section Break | 余额与开票 | 余额与待开票指标 |
| `cb_balance_right` | Column Break |  | 余额与开票右列 |
| `sb_summary` | Section Break | 指标说明 | 放 HTML 提示区 |
| `layout_summary_html` | HTML | 指标说明 | 当前余额、待开票金额口径说明 |
| `sb_note` | Section Break | 备注 | 备注区 |

### 关键字段属性建议
| fieldname | 关键属性 |
|---|---|
| `card_name` | `reqd=1`, `in_list_view=1` |
| `card_no` | `reqd=1` |
| `card_no_masked` | `read_only=1` |
| `company` | `reqd=1`, `in_list_view=1`, `in_standard_filter=1` |
| `supplier` | `reqd=1`, `in_list_view=1`, `in_standard_filter=1` |
| `default_vehicle` | `in_standard_filter=1` |
| `opening_balance` | `reqd=1`, `default=0` |
| `current_balance` | `read_only=1`, `in_list_view=1` |
| `uninvoiced_amount` | `read_only=1`, `in_list_view=1` |
| `status` | `reqd=1`, `default=Active`, `in_list_view=1` |
| `valid_from` | 常显 |
| `valid_upto` | 常显 |
| `layout_summary_html` | 常显，不做 `depends_on` |

### 说明
- `current_balance`、`uninvoiced_amount`、`status` 必须在第一屏可见
- 不建议把充值/加油流水做成主表子表；这些通过按钮和报表进入
- JS 里再补按钮：`新建充值记录`、`新增加油记录`、`查看待开票记录`、`发起开票批次`

---

## 四、`Oil Card Recharge` DocType JSON 顺序稿

### 建议元数据
- `module = Ashan CN Procurement`
- `document_type = Transaction`
- `autoname = naming_series:`
- `title_field = oil_card`
- `search_fields = oil_card,supplier,reference_no,discount_code`
- `quick_entry = 0`
- `track_changes = 1`

### 推荐 `field_order`
```python
field_order = [
    "sb_basic_info",
    "naming_series",
    "company",
    "oil_card",
    "cb_basic_info_right",
    "supplier",
    "posting_date",
    "status",
    "sb_amount_info",
    "recharge_amount",
    "bonus_amount",
    "cb_amount_info_right",
    "effective_amount",
    "invoiceable_ratio",
    "discount_ratio",
    "sb_discount_info",
    "discount_code",
    "discount_rate_display",
    "cb_discount_info_right",
    "discount_note",
    "sb_payment_info",
    "mode_of_payment",
    "payment_entry",
    "cb_payment_info_right",
    "reference_no",
    "sb_remark",
    "remark",
]
```

### 布局字段定义
| fieldname | fieldtype | label | 说明 |
|---|---|---|---|
| `sb_basic_info` | Section Break | 基本信息 | 编号、公司、油卡 |
| `cb_basic_info_right` | Column Break |  | 供应商、日期、状态 |
| `sb_amount_info` | Section Break | 金额信息 | 充值与实际入卡金额 |
| `cb_amount_info_right` | Column Break |  | 自动计算指标 |
| `sb_discount_info` | Section Break | 优惠信息 | 优惠辅助字段 |
| `cb_discount_info_right` | Column Break |  | 优惠说明右列 |
| `sb_payment_info` | Section Break | 付款信息 | 付款方式、付款单、流水号 |
| `cb_payment_info_right` | Column Break |  | 付款信息右列 |
| `sb_remark` | Section Break | 备注 | 备注区 |

### 关键字段属性建议
| fieldname | 关键属性 |
|---|---|
| `naming_series` | `reqd=1`, `default=OCR-.YYYY.-.#####` |
| `company` | `reqd=1`, 建议 JS 选卡后自动带出；可保留可编辑但必须校验与油卡一致 |
| `oil_card` | `reqd=1`, `in_list_view=1`, `in_standard_filter=1` |
| `supplier` | `reqd=1`, 建议 JS 选卡后自动带出；可保留可编辑但必须校验与油卡一致 |
| `posting_date` | `reqd=1`, `in_list_view=1`，默认业务日期/当天 |
| `status` | `default=Draft`, `in_list_view=1` |
| `recharge_amount` | `reqd=1`, `default=0` |
| `bonus_amount` | `default=0` |
| `effective_amount` | `read_only=1` |
| `invoiceable_ratio` | `read_only=1` |
| `discount_ratio` | `read_only=1` |
| `payment_entry` | `options=Payment Entry` |

### `depends_on` 建议
```python
depends_on = {
    "discount_code": "eval:(doc.bonus_amount || 0) > 0 || !!doc.discount_code || !!doc.discount_note",
    "discount_rate_display": "eval:(doc.bonus_amount || 0) > 0 || !!doc.discount_code || !!doc.discount_note",
    "discount_note": "eval:(doc.bonus_amount || 0) > 0 || !!doc.discount_code || !!doc.discount_note",
}
```

### 联动说明
- 选择 `oil_card` 后：自动带出 `company`、`supplier`
- `effective_amount = recharge_amount + bonus_amount`
- `invoiceable_ratio = recharge_amount / effective_amount`
- `discount_ratio = bonus_amount / effective_amount`
- 表单布局上把“金额”和“优惠”拆开，避免录入人混淆

---

## 五、`Oil Card Refuel Log` DocType JSON 顺序稿

### 建议元数据
- `module = Ashan CN Procurement`
- `document_type = Transaction`
- `autoname = naming_series:`
- `title_field = vehicle`
- `search_fields = vehicle,oil_card,receipt_no,station_name`
- `quick_entry = 0`
- `track_changes = 1`

### 推荐 `field_order`
```python
field_order = [
    "sb_basic_info",
    "naming_series",
    "company",
    "oil_card",
    "vehicle",
    "cb_basic_info_right",
    "posting_date",
    "supplier",
    "station_name",
    "fuel_grade",
    "sb_vehicle_meter",
    "odometer",
    "previous_odometer",
    "distance_since_last",
    "cb_vehicle_meter_right",
    "previous_refuel_date",
    "previous_liters",
    "vehicle_history_html",
    "sb_amount_info",
    "liters",
    "amount",
    "unit_price",
    "cb_amount_info_right",
    "km_per_liter",
    "liter_per_100km",
    "sb_invoice_info",
    "invoiceable_basis_amount",
    "allocated_discount_amount",
    "cb_invoice_info_right",
    "invoiced_amount",
    "uninvoiced_amount",
    "invoice_status",
    "sb_business_info",
    "driver_employee",
    "route_or_purpose",
    "cb_business_info_right",
    "receipt_no",
    "attachment",
    "remark",
]
```

### 布局字段定义
| fieldname | fieldtype | label | 说明 |
|---|---|---|---|
| `sb_basic_info` | Section Break | 基本信息 | 油卡、车辆、日期、油号 |
| `cb_basic_info_right` | Column Break |  | 基本信息右列 |
| `sb_vehicle_meter` | Section Break | 车辆与里程 | 当前/上次里程与历史提示 |
| `cb_vehicle_meter_right` | Column Break |  | 右侧历史提示区 |
| `vehicle_history_html` | HTML | 车辆历史提示 | 上次加油日期、里程、最近 3 次摘要 |
| `sb_amount_info` | Section Break | 油量与金额 | 升数 / 金额 / 单价 / 油耗 |
| `cb_amount_info_right` | Column Break |  | 右列只读分析指标 |
| `sb_invoice_info` | Section Break | 开票与优惠分摊 | 可开票、优惠、已开票、未开票 |
| `cb_invoice_info_right` | Column Break |  | 开票区右列 |
| `sb_business_info` | Section Break | 业务补充信息 | 司机、用途、附件、小票 |
| `cb_business_info_right` | Column Break |  | 业务补充信息右列 |

### 关键字段属性建议
| fieldname | 关键属性 |
|---|---|
| `naming_series` | `reqd=1`, `default=OCRL-.YYYY.-.#####` |
| `company` | `reqd=1`, 选油卡后自动带出；提交前必须校验与车辆公司一致 |
| `oil_card` | `reqd=1`, `in_list_view=1`, `in_standard_filter=1` |
| `vehicle` | `reqd=1`, `in_list_view=1`, `in_standard_filter=1` |
| `posting_date` | `reqd=1`, `in_list_view=1` |
| `supplier` | `reqd=1`, 建议选卡后自动带出 |
| `fuel_grade` | `reqd=1`, `in_list_view=1` |
| `odometer` | `reqd=1`, `in_list_view=1` |
| `previous_odometer` | `read_only=1` |
| `distance_since_last` | `read_only=1`, `in_list_view=1` |
| `previous_refuel_date` | `read_only=1` |
| `previous_liters` | `read_only=1` |
| `liters` | `reqd=1` |
| `amount` | `reqd=1`, `in_list_view=1` |
| `unit_price` | `read_only=1` |
| `km_per_liter` | `read_only=1` |
| `liter_per_100km` | `read_only=1` |
| `invoiceable_basis_amount` | `read_only=1`, `in_list_view=1` |
| `allocated_discount_amount` | `read_only=1` |
| `invoiced_amount` | `read_only=1` |
| `uninvoiced_amount` | `read_only=1` |
| `invoice_status` | `read_only=1`, `default=未开票`, `in_list_view=1`, `in_standard_filter=1` |
| `driver_employee` | `options=Employee` |
| `attachment` | `fieldtype=Attach` |

### `depends_on` 建议
```python
depends_on = {
    "vehicle_history_html": "eval:!!doc.vehicle",
}
```

### 必须保留的业务校验
- `odometer >= previous_odometer`
- `liters > 0`
- `amount > 0`
- 油卡公司与车辆公司不一致时默认阻塞
- 余额不足时阻塞或至少强提醒

### 说明
- `vehicle_history_html` 负责显示“最近一次 / 最近三次摘要”，完整历史仍然通过报表查看
- 录入主流程要集中在第一屏：`oil_card`、`vehicle`、`posting_date`、`fuel_grade`、`odometer`、`liters`、`amount`

---

## 六、`Oil Card Invoice Batch` DocType JSON 顺序稿

### 建议元数据
- `module = Ashan CN Procurement`
- `document_type = Transaction`
- `autoname = naming_series:`
- `title_field = supplier`
- `search_fields = supplier,oil_card,purchase_invoice,discount_code`
- `quick_entry = 0`
- `track_changes = 1`

### 推荐 `field_order`
```python
field_order = [
    "sb_scope_info",
    "naming_series",
    "company",
    "supplier",
    "oil_card",
    "from_date",
    "to_date",
    "cb_scope_info_right",
    "status",
    "purchase_invoice",
    "total_amount",
    "discount_total_amount",
    "sb_invoice_meta",
    "invoice_type",
    "custom_biz_mode",
    "cb_invoice_meta_right",
    "discount_code",
    "discount_rate_display",
    "discount_note",
    "sb_items",
    "items",
    "sb_remark",
    "remark",
]
```

### 布局字段定义
| fieldname | fieldtype | label | 说明 |
|---|---|---|---|
| `sb_scope_info` | Section Break | 基本信息 | 公司、供应商、油卡、日期范围 |
| `cb_scope_info_right` | Column Break |  | 状态、采购发票、汇总金额 |
| `sb_invoice_meta` | Section Break | 发票信息 | 发票类型、业务模式 |
| `cb_invoice_meta_right` | Column Break |  | 优惠展示信息 |
| `sb_items` | Section Break | 开票记录 | 子表区域 |
| `sb_remark` | Section Break | 备注 | 备注区 |

### 关键字段属性建议
| fieldname | 关键属性 |
|---|---|
| `naming_series` | `reqd=1`, `default=OCIB-.YYYY.-.#####` |
| `company` | `reqd=1`, `in_list_view=1`, `in_standard_filter=1` |
| `supplier` | `reqd=1`, `in_list_view=1`, `in_standard_filter=1` |
| `oil_card` | `in_list_view=1`, `in_standard_filter=1`，v1 可选但建议单卡 |
| `from_date` | `in_standard_filter=1` |
| `to_date` | `in_standard_filter=1` |
| `status` | `default=Draft`, `in_list_view=1` |
| `purchase_invoice` | `read_only=1`, `in_list_view=1` |
| `total_amount` | `read_only=1`, `in_list_view=1` |
| `discount_total_amount` | `read_only=1`, `in_list_view=1` |
| `invoice_type` | `reqd=1`, `in_list_view=1` |
| `custom_biz_mode` | `reqd=1`, `default=月结补录` |
| `items` | `fieldtype=Table`, `options=Oil Card Invoice Batch Item` |

### 说明
- `purchase_invoice` 生成前允许为空，生成后只读
- `discount_code / discount_rate_display / discount_note` 可以常显放右侧，不抢主视觉
- 子表是这张单的主体，不建议把 `remark` 插到子表前面打断视线

---

## 七、`Oil Card Invoice Batch Item` Child Table JSON 顺序稿

### 建议元数据
- `istable = 1`
- `editable_grid = 1`
- 不启用 `quick_entry`

### 推荐 `field_order`
```python
field_order = [
    "refuel_log",
    "vehicle",
    "posting_date",
    "amount",
    "invoiceable_basis_amount",
    "discount_amount_this_time",
    "already_invoiced_amount",
    "invoice_amount_this_time",
    "remaining_uninvoiced_amount",
    "remark",
]
```

### 子表字段属性建议
| fieldname | 关键属性 |
|---|---|
| `refuel_log` | `reqd=1`, `in_list_view=1` |
| `vehicle` | `read_only=1`, `in_list_view=1` |
| `posting_date` | `read_only=1`, `in_list_view=1` |
| `amount` | `read_only=1`, `in_list_view=1` |
| `invoiceable_basis_amount` | `read_only=1`, `in_list_view=1` |
| `discount_amount_this_time` | `read_only=1`, `in_list_view=1` |
| `already_invoiced_amount` | `read_only=1`, `in_list_view=1` |
| `invoice_amount_this_time` | `reqd=1`, `in_list_view=1` |
| `remaining_uninvoiced_amount` | `read_only=1`, `in_list_view=1` |
| `remark` | 可选，是否 `in_list_view=1` 视实际列宽再定 |

### 子表规则
- `invoice_amount_this_time <= 当前 refuel_log 的 uninvoiced_amount`
- 默认整额开票，但允许部分开票
- `discount_amount_this_time` 只做展示 / 汇总，不替代主金额字段
- `remaining_uninvoiced_amount` 必须只读

---

## 八、`Reimbursement Request` JSON Patch 顺序稿（补“报销人”）

> 说明：这是对现有 `Reimbursement Request` 的布局增强，不是另起一张新表。

### 建议同步元数据调整
- `quick_entry = 0`（建议）
- `title_field` 保持 `title`
- `track_changes = 1` 保持不变

### 推荐 `field_order`
```python
field_order = [
    "sb_header_info",
    "company",
    "custom_biz_mode",
    "employee",
    "employee_name",
    "cb_header_info_right",
    "posting_date",
    "title",
    "source_purchase_invoice",
    "department",
    "sb_restricted_info",
    "custom_is_restricted_doc",
    "custom_restriction_group",
    "custom_restriction_root_doctype",
    "cb_restricted_info_right",
    "custom_restriction_root_name",
    "custom_restriction_note",
    "sb_amount_info",
    "payment_status",
    "paid_amount",
    "outstanding_amount",
    "total_amount",
    "sb_invoice_items",
    "invoice_items",
]
```

### 新增布局字段定义
| fieldname | fieldtype | label | 说明 |
|---|---|---|---|
| `sb_header_info` | Section Break | 基本信息 | 报销身份信息区 |
| `cb_header_info_right` | Column Break |  | 右列放日期、标题、来源单据、部门 |
| `sb_restricted_info` | Section Break | 受限单据信息 | 保持现有权限字段集中 |
| `cb_restricted_info_right` | Column Break |  | 受限字段右列 |
| `sb_amount_info` | Section Break | 金额信息 | 付款与汇总金额 |
| `sb_invoice_items` | Section Break | 报销明细 | 子表区 |

### 新增字段属性建议
| fieldname | 关键属性 |
|---|---|
| `employee` | `options=Employee`；建议 `mandatory_depends_on=eval:doc.custom_biz_mode=='报销申请'` |
| `employee_name` | `read_only=1`, `fetch_from=employee.employee_name`, `in_list_view=1` |
| `department` | `read_only=1`, `fetch_from=employee.department`, `in_list_view=1` |

### 现有字段保留规则
- `custom_restriction_group` 继续保留现有：`depends_on` + `mandatory_depends_on`
- `source_purchase_invoice` 保持只读
- `payment_status / paid_amount / outstanding_amount / total_amount` 保持只读
- `invoice_items` 继续作为主子表，不做隐藏

### 说明
- 这次 patch 的核心不是改业务逻辑，而是让“报销人”成为表单头部身份字段
- 报销人字段如果继续埋在金额区或子表后面，后续统计和录入体验都会差
- 如果后面业务确认所有 `Reimbursement Request` 都必须指定报销人，可把 `employee` 从 `mandatory_depends_on` 提升到直接 `reqd=1`

---

## 九、进入代码前的冻结点建议

进入 v1 实施前，建议把下面这些作为“冻结点”统一确认：
- `field_order` 是否就按本稿执行
- 布局字段 fieldname 是否直接采用本稿命名
- `Vehicle` custom block 是否接受“整块连续插入”的方式
- `Reimbursement Request` 是否顺手关闭 `quick_entry`
- `Oil Card Recharge` 的优惠字段是否就按当前轻度 `depends_on` 方案

一旦开始写 JSON，尽量不要再边做边改命名，否则会同步影响：
- DocType JSON
- form JS
- tests
- 文档引用
- 未来 patch / migrate 脚本

---

## 十、开发时必须同步维护的地方

如果后面代码落地时和本稿不一致，记得同步更新：
- `docs/plans/2026-04-22-phase5b-oil-card-implementation-plan.md`
- `docs/plans/2026-04-22-phase5c-oil-card-field-checklist.md`
- `docs/plans/2026-04-22-phase5d-oil-card-form-layout-draft.md`
- 本文件顶部“变更记录 / 为什么这么写”
- README 文档入口

否则很快又会回到“实现已经改了，文档还是旧的”状态。

---

## 一句话结论

**这份 `phase5e` 的作用，就是把前面的研究稿、实施计划、字段清单、表单布局稿，再推进到“后续可以直接照着写 DocType JSON / Custom Field”的阶段。到这一步，油卡管理已经不仅是概念清晰，而是连 `field_order`、布局字段名、`depends_on` 和标准表扩展位置都已经基本定稿。**

# ERPNext16 油卡管理字段清单（开发字段清单版）

> **Status:** 字段清单版，已达到“可以直接照着建 DocType / Custom Field / Report”的粒度。
>
> **Related:**
> - `docs/plans/2026-04-22-phase5-oil-card-management.md`：业务研究稿
> - `docs/plans/2026-04-22-phase5b-oil-card-implementation-plan.md`：实施计划与报表/工作台设计
> - `docs/plans/2026-04-22-phase5d-oil-card-form-layout-draft.md`：表单布局稿
> - `docs/plans/2026-04-22-phase3-invoice-type-vat-and-reimbursement.md`：报销单与采购发票主线设计

**Goal:** 把油卡管理与报销人扩展进一步细化到字段级别，明确每个 DocType 的字段名、标签、类型、是否必填、默认值/联动规则、只读逻辑、表单分区和列表展示建议，方便后续直接进入开发实施。

**Architecture:** 沿用上一版实施计划：标准 `Vehicle` 作为车辆主数据，新增 `Oil Card`、`Oil Card Recharge`、`Oil Card Refuel Log`、`Oil Card Invoice Batch`、`Oil Card Invoice Batch Item`；充值付款走标准 `Payment Entry`，正式发票走标准 `Purchase Invoice`。本文件只收敛“字段清单”，不替代前两份文档的架构和报表说明。

**Tech Stack:** ERPNext 16, Frappe 16, custom app `ashan_cn_procurement`, standard `Vehicle`, `Employee`, `Supplier`, `Purchase Invoice`, `Payment Entry`.

---

## 变更记录 / 为什么这么写

| 版本 | 日期 | 改了什么 | 为什么这么改 |
|---|---|---|---|
| v1.0 | 2026-04-22 | 初版字段清单，补齐油卡 5 个核心对象与报销人字段扩展 | 让后续开发不再停留在“概念规划”，直接进入字段级实现 |

### 后续修改规范
以后如果改：
- 字段名
- 字段类型
- 必填规则
- 默认值/联动规则
- 只读逻辑
- 列表视图/搜索字段

都要补 3 条：
1. 改了哪个字段/哪张表
2. 为什么原字段设计不够用
3. 这次修改影响哪些报表、流程或历史数据迁移

---

## 一、统一字段设计约定

## 1. 命名约定
- 自定义主表字段尽量语义直白，不做过度缩写
- 与标准表联动的字段，优先直接 Link 标准 DocType
- 只读的辅助展示字段可以保留 Data 快照
- 汇总/系统计算字段统一只读

## 2. 口径约定
必须区分：
- `amount`：真实发生金额 / 真实卡消耗金额
- `invoiceable_basis_amount`：可开票金额
- `allocated_discount_amount`：优惠分摊金额
- `current_balance`：卡余额
- `uninvoiced_amount`：未开票金额

## 3. v1 默认业务模式
油卡生成采购发票时：
- `custom_biz_mode = 月结补录`

## 4. v1 默认发票口径
- 标准发票还是 `Purchase Invoice`
- 优惠码/优惠率只做展示辅助，不作为主金额计算依据

---

## 二、`Vehicle` 追加字段清单

> 说明：`Vehicle` 为标准 DocType，本节只定义新增 custom fields。

### 表单位置建议
- 放在标准车辆主信息之后，单独新增一个区块：`油卡信息`

### 字段清单
| 分区 | fieldname | 标签 | 类型 | 必填 | 只读 | 默认/联动 | 说明 |
|---|---|---|---|---|---|---|---|
| 油卡信息 | `custom_vehicle_note` | 车辆备注 | Small Text | 否 | 否 | 无 | 人工备注 |
| 油卡信息 | `custom_default_oil_card` | 默认油卡 | Link -> Oil Card | 否 | 否 | 无 | 常用默认油卡 |
| 油卡信息 | `custom_last_refuel_date` | 上次加油日期 | Date | 否 | 是 | 系统回写 | 最近一次加油日期 |
| 油卡信息 | `custom_last_refuel_liters` | 上次加油升数 | Float | 否 | 是 | 系统回写 | 最近一次加油升数 |
| 油卡信息 | `custom_last_refuel_amount` | 上次加油金额 | Currency | 否 | 是 | 系统回写 | 最近一次加油金额 |
| 油卡信息 | `custom_last_refuel_odometer` | 上次加油里程 | Int | 否 | 是 | 系统回写 | 最近一次加油里程 |

### 列表页建议列
- license_plate
- company
- last_odometer
- custom_last_refuel_date
- custom_last_refuel_amount
- custom_default_oil_card

### 搜索建议
- `license_plate`
- `custom_vehicle_note`

---

## 三、`Oil Card` 字段清单

### DocType 建议元数据
- **DocType 名称**：`Oil Card`
- **document_type**：`Setup`
- **autoname**：`field:card_name`
- **title_field**：`card_name`
- **search_fields**：`card_name,card_no,supplier`
- **quick_entry**：0

### 表单分区建议
1. 基本信息
2. 归属信息
3. 余额与开票
4. 状态与有效期
5. 备注

### 字段清单
| 分区 | fieldname | 标签 | 类型 | 必填 | 只读 | 默认/联动 | 说明 |
|---|---|---|---|---|---|---|---|
| 基本信息 | `card_name` | 油卡名称 | Data | 是 | 否 | 无 | 如“祺富-中石化主卡-01” |
| 基本信息 | `card_no` | 油卡号 | Data | 是 | 否 | 无 | 完整卡号 |
| 基本信息 | `card_no_masked` | 油卡号（脱敏） | Data | 否 | 是 | 系统自动生成 | UI 展示用 |
| 归属信息 | `company` | 使用公司 | Link -> Company | 是 | 否 | 无 | 油卡归属公司 |
| 归属信息 | `supplier` | 售油公司 | Link -> Supplier | 是 | 否 | 无 | 中石化/中石油等 |
| 归属信息 | `default_vehicle` | 默认车辆 | Link -> Vehicle | 否 | 否 | 无 | 默认值，不是唯一绑定 |
| 归属信息 | `fuel_type` | 默认油品类型 | Select | 否 | 否 | Petrol / Diesel / 92 / 95 等按最终口径定 | 便于默认带入 |
| 余额与开票 | `opening_balance` | 期初余额 | Currency | 是 | 否 | 默认 0 | 初始化用 |
| 余额与开票 | `current_balance` | 当前余额 | Currency | 否 | 是 | 系统汇总 | 卡余额 |
| 余额与开票 | `uninvoiced_amount` | 待开票金额 | Currency | 否 | 是 | 系统汇总 | 累计未开票金额 |
| 状态与有效期 | `status` | 状态 | Select | 是 | 否 | 默认 `Active` | `Active / Frozen / Lost / Closed` |
| 状态与有效期 | `valid_from` | 启用日期 | Date | 否 | 否 | 无 | 可选 |
| 状态与有效期 | `valid_upto` | 截止日期 | Date | 否 | 否 | 无 | 可选 |
| 备注 | `note` | 备注 | Small Text | 否 | 否 | 无 | 说明 |

### 列表页建议列
- card_name
- company
- supplier
- card_no_masked
- current_balance
- uninvoiced_amount
- status

### 表单按钮建议
- `新建充值记录`
- `新增加油记录`
- `查看待开票记录`
- `发起开票批次`

---

## 四、`Oil Card Recharge` 字段清单

### DocType 建议元数据
- **DocType 名称**：`Oil Card Recharge`
- **document_type**：`Transaction`
- **autoname**：`naming_series:`
- **naming_series 建议**：`OCR-.YYYY.-.#####`
- **title_field**：`oil_card`
- **search_fields**：`oil_card,supplier,reference_no,discount_code`
- **quick_entry**：0

### 表单分区建议
1. 基本信息
2. 金额信息
3. 优惠信息
4. 付款信息
5. 备注

### 字段清单
| 分区 | fieldname | 标签 | 类型 | 必填 | 只读 | 默认/联动 | 说明 |
|---|---|---|---|---|---|---|---|
| 基本信息 | `naming_series` | 编号规则 | Select | 是 | 否 | `OCR-.YYYY.-.#####` | 标准编号 |
| 基本信息 | `company` | 公司 | Link -> Company | 是 | 否 | 从油卡带出 | 公司 |
| 基本信息 | `oil_card` | 油卡 | Link -> Oil Card | 是 | 否 | 无 | 目标油卡 |
| 基本信息 | `supplier` | 售油公司 | Link -> Supplier | 是 | 否 | 从油卡带出 | 供应商 |
| 基本信息 | `posting_date` | 充值日期 | Date | 是 | 否 | 默认业务日期/当天 | 日期 |
| 金额信息 | `recharge_amount` | 充值金额 | Currency | 是 | 否 | 默认 0 | 实付充值额 |
| 金额信息 | `bonus_amount` | 赠送金额 | Currency | 否 | 否 | 默认 0 | 活动赠送 |
| 金额信息 | `effective_amount` | 实际入卡金额 | Currency | 否 | 是 | = recharge_amount + bonus_amount | 实际增加的卡余额 |
| 优惠信息 | `invoiceable_ratio` | 可开票比例 | Percent | 否 | 是 | = recharge_amount / effective_amount | 仅系统计算 |
| 优惠信息 | `discount_ratio` | 优惠比例 | Percent | 否 | 是 | = bonus_amount / effective_amount | 仅系统计算 |
| 优惠信息 | `discount_code` | 优惠码 | Data | 否 | 否 | 无 | 油司活动标识 |
| 优惠信息 | `discount_rate_display` | 发票显示优惠率 | Percent | 否 | 否 | 无 | 票面展示用 |
| 优惠信息 | `discount_note` | 优惠说明 | Small Text | 否 | 否 | 无 | 如“充4000送200” |
| 付款信息 | `mode_of_payment` | 付款方式 | Link -> Mode of Payment | 否 | 否 | 无 | 可选 |
| 付款信息 | `payment_entry` | 付款单 | Link -> Payment Entry | 否 | 否 | 可关联现有付款 | 不重复生成付款 |
| 付款信息 | `reference_no` | 外部流水号 | Data | 否 | 否 | 无 | 付款流水号 |
| 备注 | `status` | 状态 | Select | 是 | 否 | Draft | `Draft / Submitted / Cancelled` |
| 备注 | `remark` | 备注 | Small Text | 否 | 否 | 无 | 说明 |

### 核心联动规则
- 选择 `oil_card` 后自动带出：`company`, `supplier`
- `effective_amount = recharge_amount + bonus_amount`
- `invoiceable_ratio = recharge_amount / effective_amount`
- `discount_ratio = bonus_amount / effective_amount`
- 提交后增加油卡余额

### 列表页建议列
- posting_date
- company
- oil_card
- supplier
- recharge_amount
- bonus_amount
- effective_amount
- payment_entry

---

## 五、`Oil Card Refuel Log` 字段清单

### DocType 建议元数据
- **DocType 名称**：`Oil Card Refuel Log`
- **document_type**：`Transaction`
- **naming_series 建议**：`OCRL-.YYYY.-.#####`
- **title_field**：`vehicle`
- **search_fields**：`vehicle,oil_card,receipt_no,station_name`
- **quick_entry**：0

### 表单分区建议
1. 基本信息
2. 车辆与里程
3. 油量与金额
4. 开票与优惠分摊
5. 业务补充信息

### 字段清单
| 分区 | fieldname | 标签 | 类型 | 必填 | 只读 | 默认/联动 | 说明 |
|---|---|---|---|---|---|---|---|
| 基本信息 | `naming_series` | 编号规则 | Select | 是 | 否 | `OCRL-.YYYY.-.#####` | 编号 |
| 基本信息 | `company` | 公司 | Link -> Company | 是 | 否 | 从油卡/车辆校验 | 公司 |
| 基本信息 | `oil_card` | 油卡 | Link -> Oil Card | 是 | 否 | 无 | 油卡 |
| 基本信息 | `vehicle` | 车辆 | Link -> Vehicle | 是 | 否 | 无 | 车辆 / 车牌 |
| 基本信息 | `posting_date` | 加油日期 | Date | 是 | 否 | 默认业务日期/当天 | 加油日期 |
| 基本信息 | `supplier` | 售油公司 | Link -> Supplier | 是 | 否 | 从油卡带出 | 售油公司 |
| 基本信息 | `station_name` | 加油站点 | Data | 否 | 否 | 无 | 可选 |
| 基本信息 | `fuel_grade` | 油号 | Select | 是 | 否 | 92/95/98/0#/-10# 等 | 油号 |
| 车辆与里程 | `odometer` | 当前里程 | Int | 是 | 否 | 无 | 当前里程 |
| 车辆与里程 | `previous_odometer` | 上次里程 | Int | 否 | 是 | 系统带出 | 最近一笔记录 |
| 车辆与里程 | `distance_since_last` | 本次行驶里程 | Int | 否 | 是 | = odometer - previous_odometer | 自动计算 |
| 车辆与里程 | `previous_refuel_date` | 上次加油日期 | Date | 否 | 是 | 系统带出 | 最近一笔记录 |
| 车辆与里程 | `previous_liters` | 上次加油升数 | Float | 否 | 是 | 系统带出 | 最近一笔记录 |
| 油量与金额 | `liters` | 升数 | Float | 是 | 否 | > 0 | 升数 |
| 油量与金额 | `amount` | 金额 | Currency | 是 | 否 | > 0 | 本次实际消耗金额 |
| 油量与金额 | `unit_price` | 单价 | Currency | 否 | 是 | = amount / liters | 自动计算 |
| 油量与金额 | `km_per_liter` | 每升行驶公里 | Float | 否 | 是 | 自动算 | 可选分析 |
| 油量与金额 | `liter_per_100km` | 百公里油耗 | Float | 否 | 是 | 自动算 | 可选分析 |
| 开票与优惠分摊 | `invoiceable_basis_amount` | 可开票金额 | Currency | 否 | 是 | 由充值池 FIFO 自动分摊 | 核心开票金额 |
| 开票与优惠分摊 | `allocated_discount_amount` | 分摊优惠金额 | Currency | 否 | 是 | = amount - invoiceable_basis_amount | 优惠分摊 |
| 开票与优惠分摊 | `invoiced_amount` | 已开票金额 | Currency | 否 | 是 | 系统汇总 | 已开票部分 |
| 开票与优惠分摊 | `uninvoiced_amount` | 未开票金额 | Currency | 否 | 是 | = invoiceable_basis_amount - invoiced_amount | 未开票部分 |
| 开票与优惠分摊 | `invoice_status` | 开票状态 | Select | 否 | 是 | 自动判定 | `未开票 / 部分开票 / 已开票` |
| 业务补充信息 | `driver_employee` | 司机/员工 | Link -> Employee | 否 | 否 | 可从车辆 employee 带出 | 可改 |
| 业务补充信息 | `route_or_purpose` | 用途/路线 | Small Text | 否 | 否 | 无 | 可选 |
| 业务补充信息 | `receipt_no` | 小票号 | Data | 否 | 否 | 无 | 可选 |
| 业务补充信息 | `attachment` | 附件 | Attach | 否 | 否 | 无 | 小票截图 |
| 业务补充信息 | `remark` | 备注 | Small Text | 否 | 否 | 无 | 可选 |

### 必须校验
- `odometer >= previous_odometer`
- `liters > 0`
- `amount > 0`
- 油卡公司与车辆公司不一致时默认阻塞
- 余额不足时阻塞或强提醒

### 列表页建议列
- posting_date
- vehicle
- oil_card
- fuel_grade
- odometer
- distance_since_last
- liters
- amount
- invoiceable_basis_amount
- invoice_status

### 表单顶部提示区建议展示
当选择车辆后显示：
- 上次加油日期
- 上次里程
- 上次加油升数
- 上次加油金额
- 最近 3 次摘要（可选）

---

## 六、`Oil Card Invoice Batch` 字段清单

### DocType 建议元数据
- **DocType 名称**：`Oil Card Invoice Batch`
- **document_type**：`Transaction`
- **naming_series 建议**：`OCIB-.YYYY.-.#####`
- **title_field**：`supplier`
- **search_fields**：`supplier,oil_card,purchase_invoice,discount_code`
- **quick_entry**：0

### 表单分区建议
1. 基本信息
2. 发票信息
3. 优惠展示信息
4. 汇总与状态
5. 子表

### 字段清单
| 分区 | fieldname | 标签 | 类型 | 必填 | 只读 | 默认/联动 | 说明 |
|---|---|---|---|---|---|---|---|
| 基本信息 | `naming_series` | 编号规则 | Select | 是 | 否 | `OCIB-.YYYY.-.#####` | 编号 |
| 基本信息 | `company` | 公司 | Link -> Company | 是 | 否 | 无 | 公司 |
| 基本信息 | `supplier` | 售油公司 | Link -> Supplier | 是 | 否 | 无 | 发票供应商 |
| 基本信息 | `oil_card` | 油卡 | Link -> Oil Card | 否 | 否 | v1 可选但建议单卡 | 批次范围 |
| 基本信息 | `from_date` | 开票起始日期 | Date | 否 | 否 | 无 | 过滤用 |
| 基本信息 | `to_date` | 开票截止日期 | Date | 否 | 否 | 无 | 过滤用 |
| 发票信息 | `invoice_type` | 发票类型 | Select | 是 | 否 | `专用发票 / 普通发票 / 无发票` | 采购发票类型 |
| 发票信息 | `custom_biz_mode` | 业务模式 | Select | 是 | 否 | 默认 `月结补录` | 沿用现有规则 |
| 优惠展示信息 | `discount_code` | 优惠码 | Data | 否 | 否 | 无 | 发票票面辅助 |
| 优惠展示信息 | `discount_rate_display` | 发票显示优惠率 | Percent | 否 | 否 | 无 | 发票票面辅助 |
| 优惠展示信息 | `discount_note` | 优惠说明 | Small Text | 否 | 否 | 无 | 发票票面辅助 |
| 汇总与状态 | `total_amount` | 本次开票金额 | Currency | 否 | 是 | 汇总子表 | 发票金额 |
| 汇总与状态 | `discount_total_amount` | 本次优惠金额 | Currency | 否 | 是 | 汇总子表 | 优惠金额 |
| 汇总与状态 | `purchase_invoice` | 采购发票 | Link -> Purchase Invoice | 否 | 是 | 生成后回写 | 标准发票 |
| 汇总与状态 | `status` | 状态 | Select | 是 | 否 | Draft | `Draft / Invoiced / Cancelled` |
| 汇总与状态 | `remark` | 备注 | Small Text | 否 | 否 | 无 | 说明 |
| 子表 | `items` | 开票记录 | Table -> Oil Card Invoice Batch Item | 否 | 否 | 无 | 子表 |

### 列表页建议列
- company
- supplier
- oil_card
- invoice_type
- total_amount
- discount_total_amount
- purchase_invoice
- status

### 表单按钮建议
- `拉取待开票记录`
- `生成采购发票`
- `打开采购发票`

---

## 七、`Oil Card Invoice Batch Item` 字段清单

### DocType 建议元数据
- **DocType 名称**：`Oil Card Invoice Batch Item`
- **类型**：Child Table

### 字段清单
| fieldname | 标签 | 类型 | 必填 | 只读 | 默认/联动 | 说明 |
|---|---|---|---|---|---|---|
| `refuel_log` | 加油记录 | Link -> Oil Card Refuel Log | 是 | 否 | 无 | 来源流水 |
| `vehicle` | 车辆 | Link -> Vehicle | 否 | 是 | 从 refuel_log 带出 | 冗余快照 |
| `posting_date` | 加油日期 | Date | 否 | 是 | 从 refuel_log 带出 | 快照 |
| `amount` | 原始金额 | Currency | 否 | 是 | 从 refuel_log 带出 | 原始金额 |
| `invoiceable_basis_amount` | 可开票金额 | Currency | 否 | 是 | 从 refuel_log 带出 | 快照 |
| `discount_amount_this_time` | 本次优惠金额 | Currency | 否 | 是 | 自动汇总 | 本次优惠 |
| `already_invoiced_amount` | 已开票金额 | Currency | 否 | 是 | 从 refuel_log 带出 | 快照 |
| `invoice_amount_this_time` | 本次开票金额 | Currency | 是 | 否 | 默认取未开票 | 可部分开票 |
| `remaining_uninvoiced_amount` | 本次后剩余未开票 | Currency | 否 | 是 | 自动计算 | 开票后剩余 |
| `remark` | 备注 | Small Text | 否 | 否 | 无 | 可选 |

### 子表规则
- `invoice_amount_this_time <= 当前 refuel_log 的 uninvoiced_amount`
- 默认整额开票，但允许部分开票
- `discount_amount_this_time` 只做汇总/展示，不替代主金额字段

---

## 八、`Reimbursement Request` 追加字段清单（报销人）

> 说明：这是对现有 `Reimbursement Request` 的扩展，不重写整张表，只补报销人维度。

### 建议表单位置
放在：
- `company`
- `custom_biz_mode`
之后，`posting_date` 之前

### 字段清单
| fieldname | 标签 | 类型 | 必填 | 只读 | 默认/联动 | 说明 |
|---|---|---|---|---|---|---|
| `employee` | 报销人 | Link -> Employee | 是（报销申请类建议必填） | 否 | 无 | 主字段 |
| `employee_name` | 报销人姓名 | Data | 否 | 是 | fetch_from employee.employee_name 或 employee_name | 展示快照 |
| `department` | 所属部门 | Link -> Department | 否 | 是 | fetch_from employee.department | 统计与展示 |

### 为什么这样设计
- `employee` 才适合做主键语义字段
- `employee_name` 只用于快照和列表展示
- 不建议只用一个手填姓名字段，否则后续按人统计会失真

### 列表页建议列
- posting_date
- employee
- employee_name
- department
- title
- total_amount
- payment_status

---

## 九、字段实现顺序建议

### 第一批先落
1. `Oil Card`
2. `Oil Card Recharge`
3. `Oil Card Refuel Log`
4. `Vehicle` custom fields
5. `Reimbursement Request` 报销人字段

### 第二批再落
1. `Oil Card Invoice Batch`
2. `Oil Card Invoice Batch Item`
3. 开票回写字段
4. 报表与 Workspace 绑定字段

### 原因
这样可以先让：
- 充值
- 加油
- 车辆历史展示
- 报销人维度

先跑起来，再去接开票批次和报表。

---

## 十、开发时必须同步维护的地方

如果字段落地时有任何变化，记得同步更新：
- `docs/plans/2026-04-22-phase5b-oil-card-implementation-plan.md`
- 本文件顶部“变更记录 / 为什么这么写”
- 报表列清单
- Workspace 指标卡口径

否则后面文档和实现会再次脱节。

---

## 一句话结论

**这份字段清单的作用，就是把“油卡管理怎么做”进一步压缩到“开发可以照着建字段和表单”的粒度。接下来如果进入实现，优先按这里的字段名、分区、只读规则和联动规则落地，就不会再反复讨论‘这个字段要不要有、叫啥、放哪儿’。**

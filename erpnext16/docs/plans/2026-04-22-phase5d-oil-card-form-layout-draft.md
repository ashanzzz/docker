# ERPNext16 油卡管理表单布局稿（字段顺序 / Section Break / Column Break / 交互布局）

> **Status:** 表单布局稿，目标是让后续开发直接按这个稿子搭 UI，而不是边开发边猜布局。
>
> **Related:**
> - `docs/plans/2026-04-22-phase5-oil-card-management.md`：业务研究稿
> - `docs/plans/2026-04-22-phase5b-oil-card-implementation-plan.md`：实施计划、报表、工作台
> - `docs/plans/2026-04-22-phase5c-oil-card-field-checklist.md`：字段清单版
> - `docs/plans/2026-04-22-phase3-invoice-type-vat-and-reimbursement.md`：报销单设计与报销人字段

**Goal:** 把油卡管理相关表单的字段顺序、分区方式、两栏布局、只读提示区、快捷按钮、默认隐藏/显示规则写成“接近最终 UI”的稿子，方便后续直接在 Frappe/ERPNext 中按结构实现。

**Architecture:** 表单布局遵循“录入字段前置、结果字段只读靠右、历史信息不塞满主表、详细分析跳报表”的原则。也就是：主表单负责录入当前业务，右侧/下方负责显示最近信息、只读汇总、状态提示；完整历史通过按钮跳到报表。这样既能看起来清楚，也不会把表单做得又长又乱。

**Tech Stack:** Frappe 16 Desk Form, DocType JSON (`Section Break`, `Column Break`, `Tab Break`, `HTML`, `Small Text`, `Attach`, `Table`), custom JS form scripts, standard reports/workspace links.

---

## 变更记录 / 为什么这么写

| 版本 | 日期 | 改了什么 | 为什么这么改 |
|---|---|---|---|
| v1.0 | 2026-04-22 | 初版表单布局稿，明确每张表单第一行放什么、哪些做两栏、哪些字段应只读、哪些历史信息跳报表 | 避免后续开发虽然有字段清单，但表单仍然东一块西一块、体验不统一 |

### 后续修改规范
如果后续要改：
- 字段顺序
- 表单分区
- Section Break / Column Break
- 右侧提示区内容
- 快捷按钮
- 默认显示/隐藏规则

都要补：
1. 改了哪张表单
2. 为什么原布局不好用
3. 这次改动主要是为了解决谁的使用问题（录入员/财务/车队/管理层）

---

## 一、统一布局原则

## 1. 一屏优先看“当前要填什么”
表单上半区只放当前业务录入必须字段。

不要一打开就先看到一堆：
- 历史流水
- 统计图
- 复杂汇总

这些应放：
- 右侧只读区
- HTML 提示区
- 快捷按钮跳报表

## 2. 两栏布局优先用于“录入 + 对照”
推荐用法：
- 左列：当前录入字段
- 右列：系统带出的历史/只读/状态

## 3. 表单中的“好看”不是堆信息
“好看” =
- 主字段集中
- 只读结果稳定
- 状态一眼能看懂
- 按钮名字直白
- 不需要滚半天才录完一张单

## 4. 完整历史跳报表，不塞在表单里
例如：
- 最近一次加油信息可显示在表单
- 最近三次摘要也可显示
- 但完整加油流水一定跳报表看

## 5. 动态显示规则要克制
只对真正有必要的字段做显示联动。

例如：
- `bonus_amount > 0` 时才显示优惠码/优惠说明
- 受限/开票状态区只在有值时高亮

不要把整个表单做成到处闪来闪去。

---

## 二、`Vehicle` 表单布局稿（扩展区）

> 说明：这是标准 `Vehicle` 上新增“油卡信息”区块的布局，不重画整个标准表单。

### 布局目标
- 车辆主表仍以标准字段为主
- 油卡信息只做一个紧凑区块
- 让用户一进车辆页就能看到最近加油情况

### 推荐插入位置
插在标准车辆核心信息后面，新增：
- `Section Break: 油卡信息`

### 布局草图
```text
[标准车辆信息区域……]

[油卡信息 Section Break]
左列：                           右列：
- custom_vehicle_note            - custom_last_refuel_date (只读)
- custom_default_oil_card        - custom_last_refuel_liters (只读)
                                 - custom_last_refuel_amount (只读)
                                 - custom_last_refuel_odometer (只读)
```

### 字段顺序建议
1. `custom_vehicle_note`
2. `custom_default_oil_card`
3. `custom_last_refuel_date`
4. `custom_last_refuel_liters`
5. `custom_last_refuel_amount`
6. `custom_last_refuel_odometer`

### Section / Column 建议
- `Section Break: 油卡信息`
- `Column Break` 放在 `custom_default_oil_card` 后面

### 表单按钮建议
放在按钮组：`油卡`
- `新增加油记录`
- `查看加油流水`
- `查看油耗分析`

### 交互说明
- 最近一次加油信息不允许人工修改，全只读
- `custom_default_oil_card` 只作为默认值，不强绑定

---

## 三、`Oil Card` 表单布局稿

### 布局目标
- 主表像“卡档案 + 当前状态面板”
- 一眼看到：归属、当前余额、待开票金额、状态
- 不在主表里堆流水子表

### 推荐布局结构
```text
第一屏：
[基本信息 | 归属信息]
[余额与开票 | 状态与有效期]
[说明提示 HTML]
[备注]
```

### 第一屏布局稿
#### Section 1：基本信息
左列：
- `card_name`
- `card_no`

右列：
- `card_no_masked`（只读）
- `fuel_type`

#### Section 2：归属信息
左列：
- `company`
- `supplier`

右列：
- `default_vehicle`
- `status`

#### Section 3：余额与开票（建议高亮）
左列：
- `opening_balance`
- `current_balance`（只读）

右列：
- `uninvoiced_amount`（只读）
- `valid_from`
- `valid_upto`

#### Section 4：操作说明 / 风险提示
- `HTML` 字段：`layout_summary_html`
- 展示：
  - 当前余额说明
  - 待开票金额说明
  - 最近充值/最近加油摘要（可后续加）

#### Section 5：备注
- `note`

### 字段顺序建议
1. `card_name`
2. `card_no`
3. `card_no_masked`
4. `fuel_type`
5. `company`
6. `supplier`
7. `default_vehicle`
8. `status`
9. `opening_balance`
10. `current_balance`
11. `uninvoiced_amount`
12. `valid_from`
13. `valid_upto`
14. `layout_summary_html`
15. `note`

### 按钮建议
按钮组：`油卡`
- `新建充值记录`
- `新增加油记录`
- `查看待开票记录`
- `发起开票批次`
- `查看分卡汇总报表`

### 默认显示/隐藏建议
- `card_no_masked`：一直显示，只读
- `valid_from / valid_upto`：始终显示，不隐藏
- `layout_summary_html`：始终显示，用于解释指标口径

### 视觉重点建议
- `current_balance`
- `uninvoiced_amount`
- `status`

这 3 个字段应该在第一屏就能看到，不要折叠。

---

## 四、`Oil Card Recharge` 表单布局稿

### 布局目标
- 录充值时，用户首先录“充了多少”
- 如果有赠送，再自然展开优惠区域
- 付款信息与优惠信息分离，避免混乱

### 推荐布局结构
```text
[基本信息]
[金额信息 | 优惠信息]
[付款信息]
[备注]
```

### Section 1：基本信息
左列：
- `naming_series`
- `company`
- `oil_card`

右列：
- `supplier`
- `posting_date`
- `status`

### Section 2：金额信息
左列：
- `recharge_amount`
- `bonus_amount`

右列：
- `effective_amount`（只读）
- `invoiceable_ratio`（只读）
- `discount_ratio`（只读）

### Section 3：优惠信息
> 建议单独一个 Section，但仅在 `bonus_amount > 0` 时重点展示

左列：
- `discount_code`
- `discount_rate_display`

右列：
- `discount_note`

### Section 4：付款信息
左列：
- `mode_of_payment`
- `payment_entry`

右列：
- `reference_no`

### Section 5：备注
- `remark`

### 字段顺序建议
1. `naming_series`
2. `company`
3. `oil_card`
4. `supplier`
5. `posting_date`
6. `status`
7. `recharge_amount`
8. `bonus_amount`
9. `effective_amount`
10. `invoiceable_ratio`
11. `discount_ratio`
12. `discount_code`
13. `discount_rate_display`
14. `discount_note`
15. `mode_of_payment`
16. `payment_entry`
17. `reference_no`
18. `remark`

### 默认显示/隐藏建议
- `bonus_amount` 默认显示
- `discount_code / discount_rate_display / discount_note`
  - 建议 `depends_on: eval:doc.bonus_amount>0`
- `effective_amount / invoiceable_ratio / discount_ratio` 永远只读显示

### 按钮建议
按钮组：`充值`
- `查看关联付款单`
- `查看油卡`
- `查看分卡汇总报表`

### UI 说明建议
在金额区底部加一个 `HTML` 小提示：
- “充值金额用于可开票基数”
- “赠送金额进入余额，但不直接进入发票金额”

---

## 五、`Oil Card Refuel Log` 表单布局稿

### 布局目标
这是最关键的录入页，要求：
- 第一屏就能录完一条加油记录
- 选车后立刻能看到上次加油历史
- 可开票金额/优惠分摊只读展示，不能干扰录入主流程

### 推荐布局结构
```text
[基本信息]
[车辆与里程 | 最近加油提示区]
[油量与金额 | 开票与优惠分摊]
[业务补充信息]
```

### Section 1：基本信息
左列：
- `naming_series`
- `company`
- `oil_card`
- `vehicle`

右列：
- `posting_date`
- `supplier`
- `station_name`
- `fuel_grade`

### Section 2：车辆与里程
左列：
- `odometer`
- `previous_odometer`（只读）
- `distance_since_last`（只读）

右列：
- `previous_refuel_date`（只读）
- `previous_liters`（只读）
- `vehicle_history_html`（HTML 提示区）

### `vehicle_history_html` 建议展示
当选择车辆后显示：
- 上次加油日期
- 上次里程
- 上次加油升数
- 上次加油金额
- 最近 3 次加油摘要（可选）

### Section 3：油量与金额
左列：
- `liters`
- `amount`
- `unit_price`（只读）

右列：
- `km_per_liter`（只读）
- `liter_per_100km`（只读）

### Section 4：开票与优惠分摊
左列：
- `invoiceable_basis_amount`（只读）
- `allocated_discount_amount`（只读）

右列：
- `invoiced_amount`（只读）
- `uninvoiced_amount`（只读）
- `invoice_status`（只读）

### Section 5：业务补充信息
左列：
- `driver_employee`
- `route_or_purpose`

右列：
- `receipt_no`
- `attachment`
- `remark`

### 字段顺序建议
1. `naming_series`
2. `company`
3. `oil_card`
4. `vehicle`
5. `posting_date`
6. `supplier`
7. `station_name`
8. `fuel_grade`
9. `odometer`
10. `previous_odometer`
11. `distance_since_last`
12. `previous_refuel_date`
13. `previous_liters`
14. `vehicle_history_html`
15. `liters`
16. `amount`
17. `unit_price`
18. `km_per_liter`
19. `liter_per_100km`
20. `invoiceable_basis_amount`
21. `allocated_discount_amount`
22. `invoiced_amount`
23. `uninvoiced_amount`
24. `invoice_status`
25. `driver_employee`
26. `route_or_purpose`
27. `receipt_no`
28. `attachment`
29. `remark`

### 默认显示/隐藏建议
- 只读结果区永远显示，但不可编辑
- `vehicle_history_html` 仅在选择 vehicle 后显示内容
- `invoice_status` 可用颜色 badge 表现：
  - 未开票：橙色
  - 部分开票：蓝色
  - 已开票：绿色

### 按钮建议
按钮组：`加油`
- `查看本车历史加油`
- `查看关联开票情况`
- `加入开票批次`
- `打开车辆油耗报表`

### 录入体验优先级
最常用的录入动作应该集中在第一屏前两段：
- 油卡
- 车辆
- 日期
- 油号
- 里程
- 升数
- 金额

也就是说用户不应该滚到很下面才填到最核心信息。

---

## 六、`Oil Card Invoice Batch` 表单布局稿

### 布局目标
- 左边做批次范围与发票参数
- 右边做汇总结果
- 子表放在下半区
- 生成发票按钮明确可见

### 推荐布局结构
```text
[基本信息 | 汇总与状态]
[发票信息 | 优惠展示信息]
[子表 items]
```

### Section 1：基本信息
左列：
- `naming_series`
- `company`
- `supplier`
- `oil_card`
- `from_date`
- `to_date`

右列：
- `status`
- `purchase_invoice`
- `total_amount`（只读）
- `discount_total_amount`（只读）

### Section 2：发票信息
左列：
- `invoice_type`
- `custom_biz_mode`

右列：
- `discount_code`
- `discount_rate_display`
- `discount_note`

### Section 3：子表 `items`
子表列建议顺序：
1. `refuel_log`
2. `vehicle`
3. `posting_date`
4. `amount`
5. `invoiceable_basis_amount`
6. `discount_amount_this_time`
7. `already_invoiced_amount`
8. `invoice_amount_this_time`
9. `remaining_uninvoiced_amount`
10. `remark`

### 子表显示重点
- `invoice_amount_this_time` 要明显可编辑
- `remaining_uninvoiced_amount` 要只读
- `discount_amount_this_time` 要可见但不抢主视觉

### 按钮建议
按钮组：`开票`
- `拉取待开票记录`
- `生成采购发票`
- `打开采购发票`
- `查看售油公司开票汇总`

### 默认显示/隐藏建议
- `discount_code / discount_rate_display / discount_note` 默认显示，但可放右侧
- `purchase_invoice` 生成前可空，生成后只读

### UI 重点
这张表最重要的是让用户一眼确认：
- 本次开哪些记录
- 一共多少钱
- 对应哪家售油公司
- 发票已经生成没有

---

## 七、`Reimbursement Request` 表单布局稿（补“报销人”）

> 说明：这是现有报销表单的小幅结构优化，不重做整张报销表。

### 报销人建议放置位置
放在：
- `company`
- `custom_biz_mode`
之后
- `posting_date`
之前

### 推荐布局草图
```text
左列：                         右列：
- company                      - posting_date
- custom_biz_mode              - title
- employee（报销人）            - source_purchase_invoice
- employee_name（只读）         - department（只读）
```

### 字段顺序建议
1. `company`
2. `custom_biz_mode`
3. `employee`
4. `employee_name`
5. `department`
6. `posting_date`
7. `title`
8. `source_purchase_invoice`
9. `payment_status`
10. `paid_amount`
11. `outstanding_amount`
12. `total_amount`
13. `invoice_items`

### 默认显示/隐藏建议
- `employee`：常显
- `employee_name`：只读常显
- `department`：只读常显，可选

### 为什么这样放
因为“报销人”是这张单的重要身份字段，应该靠前，不能埋在金额区或子表后面。

---

## 八、建议实现方式（DocType JSON 角度）

## 1. 真正需要 Section Break 的地方
建议直接在 DocType JSON 里明确加：
- `Section Break`
- `Column Break`
- `HTML`

不要想着只靠前端 JS 动态排版把所有布局救回来。

## 2. 真正适合用 HTML 区块的地方
建议只在这几处使用 HTML：
- `Oil Card.layout_summary_html`
- `Oil Card Refuel Log.vehicle_history_html`

不要把 HTML 用成半个自定义页面。

## 3. 只读字段最好在 JSON 就定义只读
例如：
- `current_balance`
- `uninvoiced_amount`
- `effective_amount`
- `invoiceable_basis_amount`
- `allocated_discount_amount`

不要只靠 JS 禁用。

---

## 九、后续如果继续推进，我建议的下一步

在这个布局稿之后，最自然的下一步是：

### Step 1：把每个 DocType 写成“拟建 JSON 顺序稿”
即：
- field_order 数组
- 每个 Section Break / Column Break 具体放在哪里

### Step 2：再进入代码实现
这样能避免边写 JSON 边反复改顺序。

---

## 一句话结论

**这份布局稿的作用，是把上一版“字段清单”进一步推进到“表单应该长什么样”的程度。后续如果按这个稿子落地，油卡录入页会更像一个真正能日常使用的业务表单，而不是一堆字段简单堆在一起。**

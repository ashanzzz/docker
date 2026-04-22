# ERPNext16 油卡管理可实施计划（字段设计 / 单据设计 / 视图设计）

> **Status:** 可实施计划稿，下一步可直接按任务拆解进入开发。
>
> **Related:** `docs/plans/2026-04-22-phase5-oil-card-management.md` 是业务研究稿；本文是更偏实施落地的版本。
>
> **For Hermes:** 后续如果要开始实现，优先按本文的“主数据 / 交易单据 / 批次开票 / 报表工作台”分层推进，不要为了省事把充值、加油、开票都塞进同一个 DocType。

**Goal:** 为 ERPNext16 的“油卡管理”设计一套可以直接实施的 v1 方案，明确字段、表结构、表单交互、列表视图、统计报表、工作台布局，以及与标准 `Vehicle` / `Purchase Invoice` / `Payment Entry` 的衔接方式。

**Architecture:** 复用 ERPNext 标准 `Vehicle` 作为车辆主数据；新增 `Oil Card`、`Oil Card Recharge`、`Oil Card Refuel Log`、`Oil Card Invoice Batch` 四类核心对象；标准 `Payment Entry` 负责充值付款，标准 `Purchase Invoice` 负责正式发票与税务/应付。面向日常使用的“好看视图”不依赖把所有信息堆进单个表单，而是通过 **Workspace + Number Card + Dashboard Chart + Query/Script Report + 表单快捷按钮** 组成完整操作与分析界面。

**Tech Stack:** ERPNext 16, Frappe 16, custom app `ashan_cn_procurement`, standard `Vehicle`, standard `Supplier`, standard `Purchase Invoice`, standard `Payment Entry`, custom reports/workspace/buttons/tests.

---

## 变更记录 / 设计修改说明

> 后续在实际使用中继续优化时，**必须先更新本节**，写清楚“改了什么”和“为什么这么改”。

| 版本 | 日期 | 改了什么 | 为什么这么改 |
|---|---|---|---|
| v1.0 | 2026-04-22 | 初版实施计划，明确 `Oil Card / Oil Card Recharge / Oil Card Refuel Log / Oil Card Invoice Batch` 四层结构 | 避免把充值、加油、开票塞进一个大单据，保证后续可维护 |
| v1.1 | 2026-04-22 | 增加“充4000送200”类优惠/赠送处理：引入 `invoiceable_ratio`、`discount_ratio`、`invoiceable_basis_amount`、`allocated_discount_amount` 等口径 | 解决“卡余额按 4200 走，但发票不能按 4200 直接开”的问题，避免用户手算 |
| v1.2 | 2026-04-22 | 明确报表必须分为：总报表、分油卡报表、分车辆报表，并补充展示特性和报表矩阵 | 让后续开发优先满足管理层/财务/车队三种视角，避免只做流水表而没有管理视图 |

### 后续修改的记录规范
后面每次如果改：
- 字段
- 报表
- 汇总口径
- 优惠/开票规则
- UI 布局

都要在本节补 3 句话：
1. **改了什么**
2. **为什么原方案不够用了**
3. **这次修改影响哪些报表/字段/流程**

## 一、实施原则

## 1. 复用标准对象，不重复造轮子
直接复用：
- `Vehicle`
- `Supplier`
- `Purchase Invoice`
- `Payment Entry`
- `Company`

### 原因
- `Vehicle` 已天然适合承接车牌、所属公司、上次里程、燃料类型
- `Purchase Invoice` 已经是采购发票 / 税务 / 应付的事实单据
- `Payment Entry` 已经是付款流水事实单据

## 2. 高流水记录不要做成子表
`Oil Card Recharge` 和 `Oil Card Refuel Log` **都不建议挂在 `Oil Card` 下面做 child table**。

### 原因
- 加油流水会越积越多
- 子表不利于筛选、报表、权限、独立单号、性能
- 日后开票/对账都更难做

所以：
- 主数据是主数据
- 交易流水是独立 DocType
- 查询通过 Link + Report + Dashboard 完成

## 3. 余额线和开票线必须分开
系统里至少同时维护两套结果：

### A. 油卡余额线
- 充值增加
- 加油减少
- 退款/冲正调整

### B. 待开票线
- 加油记录先形成待开票金额
- 开票后回写已开票 / 未开票金额

**不要用一个字段同时表达“余额”和“待开票”。**

## 4. 先做 v1 可落地，不一开始追求过重中台
v1 先实现：
- 主数据
- 流水
- 批次开票
- 核心报表
- 核心看板

先不做：
- 多卡复杂合并结算规则
- 复杂审批流
- 自动异常预警引擎
- 复杂退款冲正中心

---

## 二、v1 最终对象清单

## 1. 复用标准 DocType
- `Vehicle`
- `Supplier`
- `Purchase Invoice`
- `Payment Entry`
- `Company`

## 2. 新增自定义 DocType
- `Oil Card`
- `Oil Card Recharge`
- `Oil Card Refuel Log`
- `Oil Card Invoice Batch`
- `Oil Card Invoice Batch Item`（child table）

## 3. 追加到标准 `Vehicle` 的 custom fields
建议只补少量字段：
- `custom_vehicle_note`
- `custom_default_oil_card`
- `custom_last_refuel_date`
- `custom_last_refuel_liters`
- `custom_last_refuel_amount`
- `custom_last_refuel_odometer`

其中：
- `custom_vehicle_note`：人工备注
- 其余 4 个：系统回写/汇总用，便于车辆表单快速查看

---

## 三、字段与表设计

## A. `Vehicle`（标准复用 + 轻量补字段）

### 标准已存在的重要字段
- `license_plate`
- `company`
- `employee`
- `last_odometer`
- `fuel_type`
- `uom`

### 建议新增字段
| 字段名 | 标签 | 类型 | 用途 |
|---|---|---|---|
| `custom_vehicle_note` | 车辆备注 | Small Text | 如“长期跑天津港”“司机需手工拍小票” |
| `custom_default_oil_card` | 默认油卡 | Link -> Oil Card | 常用默认卡 |
| `custom_last_refuel_date` | 上次加油日期 | Date (Read Only) | 自动回写 |
| `custom_last_refuel_liters` | 上次加油升数 | Float (Read Only) | 自动回写 |
| `custom_last_refuel_amount` | 上次加油金额 | Currency (Read Only) | 自动回写 |
| `custom_last_refuel_odometer` | 上次加油里程 | Int (Read Only) | 自动回写 |

### 为什么要回写这些字段
因为用户在车辆页面希望“一眼看到最近情况”，不必先打开报表。

---

## B. `Oil Card`

### 角色定位
一张物理油卡 = 一条主数据。

### 推荐字段表
| 字段名 | 标签 | 类型 | 说明 |
|---|---|---|---|
| `card_name` | 油卡名称 | Data | 如“祺富-中石化主卡-01” |
| `company` | 使用公司 | Link -> Company | 油卡归属公司 |
| `supplier` | 售油公司 | Link -> Supplier | 如中石化 / 中石油 |
| `card_no` | 油卡号 | Data | 完整卡号 |
| `card_no_masked` | 油卡号（脱敏） | Data (Read Only) | UI 展示用 |
| `default_vehicle` | 默认车辆 | Link -> Vehicle | 可空，不强制绑定 |
| `fuel_type` | 默认油品类型 | Select | 汽油 / 柴油 等 |
| `opening_balance` | 期初余额 | Currency | 初始化用 |
| `current_balance` | 当前余额 | Currency (Read Only) | 系统汇总 |
| `uninvoiced_amount` | 待开票金额 | Currency (Read Only) | 系统汇总 |
| `status` | 状态 | Select | Active / Frozen / Lost / Closed |
| `valid_from` | 启用日期 | Date | 可选 |
| `valid_upto` | 截止日期 | Date | 可选 |
| `note` | 备注 | Small Text | 说明 |

### List View 建议列
- 油卡名称
- 公司
- 售油公司
- 脱敏卡号
- 当前余额
- 待开票金额
- 状态

### 表单按钮建议
- `新建充值记录`
- `新增加油记录`
- `查看待开票记录`
- `发起开票批次`
- `查看余额流水`

---

## C. `Oil Card Recharge`

### 角色定位
记录每次充值/预付款，不直接等于发票。

### 推荐字段表
| 字段名 | 标签 | 类型 | 说明 |
|---|---|---|---|
| `naming_series` | 编号规则 | Select | 如 `OCR-.YYYY.-.#####` |
| `company` | 公司 | Link -> Company | 必填 |
| `oil_card` | 油卡 | Link -> Oil Card | 必填 |
| `supplier` | 售油公司 | Link -> Supplier | 默认从油卡带出 |
| `posting_date` | 充值日期 | Date | 默认业务日期/当天 |
| `recharge_amount` | 充值金额 | Currency | 必填 |
| `bonus_amount` | 赠送金额 | Currency | 可选 |
| `effective_amount` | 实际入卡金额 | Currency (Read Only) | = 充值 + 赠送 |
| `invoiceable_ratio` | 可开票比例 | Percent (Read Only) | = recharge_amount / effective_amount |
| `discount_ratio` | 优惠比例 | Percent (Read Only) | = bonus_amount / effective_amount |
| `discount_code` | 优惠码 | Data | 可选，记录油司给出的优惠标识 |
| `discount_rate_display` | 发票显示优惠率 | Percent | 可选，抄录实际发票显示值 |
| `discount_note` | 优惠说明 | Small Text | 可选，记录“充4000送200”等规则 |
| `mode_of_payment` | 付款方式 | Link -> Mode of Payment | 可选 |
| `payment_entry` | 付款单 | Link -> Payment Entry | 可选 |
| `reference_no` | 外部流水号 | Data | 可选 |
| `status` | 状态 | Select | Draft / Submitted / Cancelled |
| `remark` | 备注 | Small Text | 说明 |

### 核心规则
- `supplier` 默认取油卡售油公司
- `effective_amount = recharge_amount + bonus_amount`
- `invoiceable_ratio = recharge_amount / effective_amount`
- `discount_ratio = bonus_amount / effective_amount`
- 提交后增加 `Oil Card.current_balance`
- 若已关联 `Payment Entry`，则不重复生成付款

### 针对“充 4000 送 200，发票不能按 4200 直接开”的最省事处理
这类场景最怕用户每次自己手算。

**推荐最省事、也最不容易错的方式：系统自动按充值池比例分摊。**

也就是：
- 用户只录：
  - `recharge_amount = 4000`
  - `bonus_amount = 200`
- 系统自动得到：
  - `effective_amount = 4200`
  - `invoiceable_ratio = 4000 / 4200`
  - `discount_ratio = 200 / 4200`

之后每次加油时：
- 卡里真实扣减仍按 `amount`
- 但系统在后台自动拆出：
  - 其中多少属于“可开票金额”
  - 其中多少属于“优惠分摊金额”

这样用户不用自己算“这次 3000 里到底有多少能开票”。

### 为什么不建议人工每次填优惠比例
因为一张卡可能有：
- 多次充值
- 不同充值活动
- 不同优惠比例

如果人工在开票时再算：
- 容易错
- 对账麻烦
- 后面很难解释为什么某张发票是这个金额

所以最简单的用户操作，其实是：
**前台少填，后台自动分摊。**

### v1 建议的后台规则
- 每次充值形成一个“充值池”
- 每次加油按 **FIFO** 依次消耗最早未用完的充值池
- 系统自动把本次加油金额拆成：
  - `invoiceable_basis_amount`（本次可开票金额）
  - `allocated_discount_amount`（本次分摊优惠金额）

这样以后开票时：
- 开票金额按 `invoiceable_basis_amount` 汇总
- 优惠金额按 `allocated_discount_amount` 汇总
- 如果实际发票上有“优惠码 / 优惠率”，只需要补录显示信息，不需要重算业务金额

### List View 建议列
- 日期
- 公司
- 油卡
- 售油公司
- 充值金额
- 赠送金额
- 实际入卡金额
- 付款单

---

## D. `Oil Card Refuel Log`

### 角色定位
日常业务核心流水单据。

### 推荐字段表
| 字段名 | 标签 | 类型 | 说明 |
|---|---|---|---|
| `naming_series` | 编号规则 | Select | 如 `OCRL-.YYYY.-.#####` |
| `company` | 公司 | Link -> Company | 默认从油卡/车辆校验 |
| `oil_card` | 油卡 | Link -> Oil Card | 必填 |
| `vehicle` | 车辆 | Link -> Vehicle | 必填 |
| `posting_date` | 加油日期 | Date | 默认业务日期/当天 |
| `supplier` | 售油公司 | Link -> Supplier | 默认从油卡带出 |
| `station_name` | 加油站点 | Data | 可选 |
| `fuel_grade` | 油号 | Select | 92 / 95 / 98 / 0# / -10# 等 |
| `odometer` | 当前里程 | Int | 必填 |
| `previous_odometer` | 上次里程 | Int (Read Only) | 自动带出 |
| `distance_since_last` | 本次行驶里程 | Int (Read Only) | 自动计算 |
| `liters` | 升数 | Float | 必填 |
| `amount` | 金额 | Currency | 必填 |
| `unit_price` | 单价 | Currency (Read Only) | 自动计算 |
| `invoiceable_basis_amount` | 可开票金额 | Currency (Read Only) | 系统按充值池自动分摊 |
| `allocated_discount_amount` | 分摊优惠金额 | Currency (Read Only) | = amount - invoiceable_basis_amount |
| `previous_liters` | 上次加油升数 | Float (Read Only) | 自动带出 |
| `previous_refuel_date` | 上次加油日期 | Date (Read Only) | 自动带出 |
| `km_per_liter` | 每升行驶公里 | Float (Read Only) | 可选计算 |
| `liter_per_100km` | 百公里油耗 | Float (Read Only) | 可选计算 |
| `driver_employee` | 司机/员工 | Link -> Employee | 默认从车辆带出，可修改 |
| `route_or_purpose` | 用途/路线 | Small Text | 可选 |
| `receipt_no` | 小票号 | Data | 可选 |
| `attachment` | 附件 | Attach | 小票/截图 |
| `invoiced_amount` | 已开票金额 | Currency (Read Only) | 系统汇总 |
| `uninvoiced_amount` | 未开票金额 | Currency (Read Only) | = amount - invoiced_amount |
| `invoice_status` | 开票状态 | Select (Read Only) | 未开票 / 部分开票 / 已开票 |
| `remark` | 备注 | Small Text | 可选 |

### 提交时自动行为
1. 读取该车辆上一次加油记录
2. 自动带出：
   - `previous_odometer`
   - `previous_liters`
   - `previous_refuel_date`
3. 计算：
   - `distance_since_last = odometer - previous_odometer`
   - `unit_price = amount / liters`
   - `km_per_liter`
   - `liter_per_100km`
4. 扣减油卡余额
5. 更新车辆最近加油信息字段
6. 更新油卡待开票金额
7. 若命中带赠送金额的充值池，自动回写：
   - `invoiceable_basis_amount`
   - `allocated_discount_amount`

### 必须做的校验
- 当前里程不能小于上次里程
- 加油金额、升数必须 > 0
- 车辆公司与油卡公司不一致时：
  - 默认阻塞，除非你明确要支持跨公司卡
- 当油卡余额不足时：
  - v1 建议给阻塞或至少强提醒

### List View 建议列
- 加油日期
- 车辆
- 油卡
- 油号
- 里程
- 本次里程差
- 升数
- 金额
- 单价
- 开票状态

---

## E. `Oil Card Invoice Batch`

### 角色定位
承接“待开票池”到“标准采购发票”的桥梁。

### 主表字段
| 字段名 | 标签 | 类型 | 说明 |
|---|---|---|---|
| `naming_series` | 编号规则 | Select | 如 `OCIB-.YYYY.-.#####` |
| `company` | 公司 | Link -> Company | 必填 |
| `supplier` | 售油公司 | Link -> Supplier | 必填 |
| `oil_card` | 油卡 | Link -> Oil Card | v1 可选但建议单卡 |
| `from_date` | 开票起始日期 | Date | 过滤用 |
| `to_date` | 开票截止日期 | Date | 过滤用 |
| `invoice_type` | 发票类型 | Select | 复用 `专用发票 / 普通发票 / 无发票` |
| `custom_biz_mode` | 业务模式 | Select | v1 建议默认 `月结补录` |
| `total_amount` | 本次开票金额 | Currency (Read Only) | 汇总子表 |
| `discount_total_amount` | 本次优惠金额 | Currency (Read Only) | 汇总子表分摊优惠 |
| `discount_code` | 优惠码 | Data | 可选，抄录实际发票/油司信息 |
| `discount_rate_display` | 发票显示优惠率 | Percent | 可选，抄录实际发票显示值 |
| `discount_note` | 优惠说明 | Small Text | 可选 |
| `purchase_invoice` | 采购发票 | Link -> Purchase Invoice | 生成后回写 |
| `status` | 状态 | Select | Draft / Invoiced / Cancelled |
| `remark` | 备注 | Small Text | 说明 |
| `items` | 开票记录 | Table | 子表 |

### 子表 `Oil Card Invoice Batch Item`
| 字段名 | 标签 | 类型 | 说明 |
|---|---|---|---|
| `refuel_log` | 加油记录 | Link -> Oil Card Refuel Log | 必填 |
| `vehicle` | 车辆 | Link -> Vehicle | 冗余快照，便于看 |
| `posting_date` | 加油日期 | Date | 快照 |
| `amount` | 原始金额 | Currency | 快照 |
| `invoiceable_basis_amount` | 可开票金额 | Currency | 快照 |
| `discount_amount_this_time` | 本次优惠金额 | Currency | 快照/自动汇总 |
| `already_invoiced_amount` | 已开票金额 | Currency | 快照 |
| `invoice_amount_this_time` | 本次开票金额 | Currency | 用户可改，默认取未开票 |
| `remaining_uninvoiced_amount` | 本次后剩余未开票 | Currency (Read Only) | 自动算 |
| `remark` | 备注 | Small Text | 可选 |

### 按钮
- `拉取待开票记录`
- `按条件筛选`
- `生成采购发票`
- `打开采购发票`

### 生成采购发票建议
生成标准 `Purchase Invoice` 时：
- `supplier = 售油公司`
- `company = 批次公司`
- `posting_date = 用户选择日期`
- `custom_invoice_type = 批次发票类型`
- `custom_biz_mode = 月结补录`（v1）
- 发票明细建议先按“车辆 + 日期范围”聚合或按批次一行；具体打印颗粒度可后续再优化

### 为什么批次子表允许 `invoice_amount_this_time` 可改
因为未来会出现：
- 一条使用记录只开一部分
- 发票金额与实际记录金额暂不完全一致

v1 即使默认整额开票，也建议结构先支持部分金额开票。

### 有优惠码 / 优惠率时怎么处理最省事
我建议分两层：

#### 第一层：系统计算层
真正影响金额的，只认：
- `invoiceable_basis_amount`
- `allocated_discount_amount`

#### 第二层：票面展示层
发票上如果出现：
- 优惠码
- 优惠百分比
- 其他营销说明

这些字段只作为：
- 追溯
- 对账
- 打印/备注参考

不作为系统主金额计算的唯一依据。

这样最省事，因为：
- 算账靠系统结构字段
- 票面文字只做补充说明
- 不会因为不同油司打印格式不同，把核心逻辑搞乱

---

## 四、页面与表格怎么设计才“好看”和“实用”

## 1. 不追求把所有统计塞到单据表单顶部
“好看”并不等于单个表单信息越多越好。

更好的做法是：
- 表单负责录入与查看当前记录
- Workspace 负责总览
- Report 负责分析
- 按钮负责快速跳转

## 2. 建一个独立 Workspace：`油卡管理`

### Workspace 分四个区块
#### A. 主数据
- Vehicle
- Oil Card

#### B. 日常录入
- 新建充值记录
- 新增加油记录
- 未开票加油记录

#### C. 开票结算
- 新建开票批次
- 已开票批次
- 打开采购发票

#### D. 查询分析
- 车辆用油汇总
- 车辆加油流水
- 油卡余额与待开票
- 售油公司开票汇总

---

## 3. Workspace 顶部 Number Cards 建议
建议做 5 个数字卡片：

1. `当前卡余额总额`
2. `待开票金额总额`
3. `本月加油总金额`
4. `本月加油总升数`
5. `本月加油车辆数`

如果后面要做异常分析，再加：
- `异常里程记录数`
- `余额不足记录数`

---

## 4. Dashboard Charts 建议
建议至少做 4 张图：

### 图 1：按车辆统计月度加油金额
- X 轴：月份
- 维度：车辆
- 指标：金额

### 图 2：按车辆统计月度加油升数
- X 轴：月份
- 维度：车辆
- 指标：升数

### 图 3：百公里油耗趋势
- X 轴：日期 / 月份
- 维度：车辆
- 指标：`liter_per_100km`

### 图 4：待开票金额按售油公司分布
- 维度：Supplier
- 指标：未开票金额

---

## 5. Query / Script Reports 建议

### v1 必做报表矩阵

| 报表类型 | 报表名称 | 主要使用者 | 主要解决的问题 |
|---|---|---|---|
| 总报表 | `油卡经营总报表` | 管理层 / 财务 / 车队负责人 | 全局看本月/本期加油、余额、待开票、已开票、优惠分摊 |
| 分油卡报表 | `油卡分卡汇总报表` | 财务 / 油卡管理员 | 每张卡的余额、充值、使用、待开票、优惠、状态 |
| 分车辆报表 | `车辆油耗与费用报表` | 车队 / 用车管理 | 每辆车的用油金额、油耗、里程、平均单价 |
| 明细报表 | `车辆加油流水` | 运营 / 财务 / 车队 | 看某车或某卡的逐笔加油记录 |
| 对账报表 | `售油公司开票汇总` | 财务 | 对供应商开票金额、待开票金额、优惠分摊做核对 |

### 报表展现特性要求
这些报表不能只是“把数据库字段列出来”，还要能展现特性：

#### 总报表必须展现
- 本期充值总额
- 本期赠送/优惠总额
- 本期实际加油总金额
- 本期可开票金额
- 本期已开票金额
- 本期未开票金额
- 当前卡余额总额
- 活跃车辆数
- 活跃油卡数

#### 分油卡报表必须展现
- 每张卡当前余额
- 每张卡累计充值金额
- 每张卡累计赠送金额
- 每张卡累计使用金额
- 每张卡累计可开票金额
- 每张卡累计未开票金额
- 最近充值日期
- 最近加油日期
- 卡状态

#### 分车辆报表必须展现
- 每辆车加油次数
- 总行驶里程
- 总加油升数
- 总加油金额
- 平均单价
- 百公里油耗
- 每公里油费
- 最近一次加油日期
- 最近一次里程

### 报表 1：`油卡经营总报表`
#### 用途
给老板、财务、车队负责人一眼看整体经营情况。

#### 推荐做 Script Report
因为它不是简单 list，而是多口径汇总。

#### 建议列
- 公司
- 日期范围
- 充值总额
- 赠送总额
- 实际入卡总额
- 加油总金额
- 可开票金额
- 已开票金额
- 未开票金额
- 当前余额总额
- 活跃油卡数
- 活跃车辆数

#### 建议顶部指标卡同步展示
- 本月加油总金额
- 本月未开票金额
- 当前余额总额
- 平均百公里油耗

### 报表 2：`油卡分卡汇总报表`
#### 用途
看每张油卡的经营与开票情况。

#### 过滤条件
- 公司
- 油卡
- 售油公司
- 状态
- 日期范围

#### 建议列
- 油卡
- 公司
- 售油公司
- 当前余额
- 累计充值金额
- 累计赠送金额
- 累计使用金额
- 累计可开票金额
- 累计已开票金额
- 累计未开票金额
- 最近充值日期
- 最近加油日期
- 状态

### 报表 3：`车辆油耗与费用报表`
#### 用途
看不同车的用油效率、总金额、总里程。

#### 推荐做 Script Report
因为要计算：
- 总里程差
- 总升数
- 总金额
- 平均单价
- 平均每公里成本
- 百公里油耗

#### 建议列
- 车辆
- 公司
- 默认油卡/最近使用油卡
- 加油次数
- 总行驶里程
- 总加油升数
- 总加油金额
- 平均单价
- 百公里油耗
- 每公里油费
- 最近一次加油日期
- 最近一次里程

### 报表 4：`车辆加油流水`
#### 用途
看某车所有加油记录，作为明细追溯基础。

#### 过滤条件
- 公司
- 车辆
- 油卡
- 售油公司
- 日期范围
- 开票状态

#### 建议列
- 日期
- 车辆
- 油卡
- 油号
- 当前里程
- 上次里程
- 本次里程差
- 升数
- 金额
- 可开票金额
- 分摊优惠金额
- 单价
- 开票状态
- 售油公司

### 报表 5：`售油公司开票汇总`
#### 用途
看每家售油公司：
- 已用多少
- 已开票多少
- 未开票多少
- 优惠分摊多少

#### 建议列
- 售油公司
- 公司
- 加油总金额
- 可开票金额
- 已开票金额
- 未开票金额
- 优惠分摊金额
- 发票数

### 后续改报表时的记录要求
如果后续使用中觉得：
- 报表列不够
- 指标口径不对
- 图表不好看
- 管理层看不懂

那么每次修改时都必须在本文顶部“变更记录 / 设计修改说明”中补：
- 改了哪张报表
- 多了/少了哪些列或指标
- 为什么这么改
- 改完后主要给谁看

---

## 6. 表单快捷按钮建议

## `Vehicle` 表单
增加：
- `新增加油记录`
- `查看加油流水`
- `查看油耗分析`

### 跳转逻辑
点击 `查看加油流水`：
- 跳转 `车辆加油流水`
- 自动带过滤条件：当前 Vehicle

点击 `查看油耗分析`：
- 跳转 `车辆油耗分析`
- 自动带过滤条件：当前 Vehicle

## `Oil Card` 表单
增加：
- `新建充值记录`
- `新增加油记录`
- `查看待开票记录`
- `发起开票批次`

## `Oil Card Refuel Log` 表单
增加：
- `查看本车历史加油`
- `查看关联开票情况`
- `加入开票批次`

## `Oil Card Invoice Batch` 表单
增加：
- `拉取待开票记录`
- `生成采购发票`
- `打开采购发票`

---

## 五、关键计算与回写策略

## 1. `Oil Card.current_balance`
建议按以下汇总：

`opening_balance + 已提交充值 effective_amount - 已提交加油金额 ± 后续调整`

v1 可采用：
- 系统实时汇总
- 提交/取消时回写缓存字段

## 2. `Oil Card.uninvoiced_amount`
建议按以下汇总：

`所有已提交加油记录的 uninvoiced_amount 之和`

## 2.1 如果存在充值赠送，未开票金额按什么口径走
### 建议拆成两个口径
- `consumed_amount`：真实加油消耗金额（卡资金消耗）
- `invoiceable_basis_amount`：可用于开票的金额

在有“充 4000 送 200”这类活动时：
- `consumed_amount` 仍按 4200 体系使用
- `invoiceable_basis_amount` 只按 4000 对应比例累计

这样：
- 卡余额对得上
- 发票金额也对得上
- 优惠部分不会误进可开票金额

## 3. `Oil Card Refuel Log.invoice_status`
规则：
- `uninvoiced_amount = amount` → `未开票`
- `0 < uninvoiced_amount < amount` → `部分开票`
- `uninvoiced_amount = 0` → `已开票`

## 4. `Vehicle` 最近信息回写
每次提交加油记录后，更新车辆：
- `last_odometer`
- `custom_last_refuel_date`
- `custom_last_refuel_liters`
- `custom_last_refuel_amount`
- `custom_last_refuel_odometer`

这能让车辆页面非常直观。

---

## 六、你特别关心的“选择车牌就看到历史”怎么做

用户体验上，建议这样实现：

## 在 `Oil Card Refuel Log` 表单中
当选择 `vehicle = 津CB5959` 时，右侧或顶部提示区立即展示：
- 上次加油日期
- 上次里程
- 上次加油升数
- 上次加油金额
- 最近 3 次加油摘要（可选）

### 实现方式建议
- 前端调用轻量 API
- 返回该车辆最近一条 / 最近三条记录
- 不要把完整历史塞在表单里
- 完整历史通过按钮跳转报表查看

### 原因
这样既“看起来直观”，又不会把表单变成很长很乱的详情页。

---

## 七、v1 不要忽略的边界情况

## 1. 部分开票
必须在设计里预留。

## 2. 余额不足
建议默认阻塞或至少强提示。

## 3. 里程倒退
必须阻塞。

## 4. 卡与车非一一绑定
不能把卡和车设计成唯一关系。

## 5. 小票附件
建议 v1 就支持。

## 6. 发票类型沿用现有逻辑
油卡发票应继续复用：
- `custom_invoice_type`
- 现有 VAT 桥接规则

## 7. `custom_biz_mode`
v1 建议仍用：
- `月结补录`

不要立刻新增第 5 个值，避免破坏当前已经收敛好的业务模式体系。

---

## 八、建议的文件结构（实施时）

### DocTypes
- `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/oil_card/`
- `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/oil_card_recharge/`
- `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/oil_card_refuel_log/`
- `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/oil_card_invoice_batch/`
- `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/oil_card_invoice_batch_item/`

### Services / Utils
- `services/oil_card_service.py`
- `services/oil_card_invoice_service.py`
- `utils/oil_card_metrics.py`

### APIs
- `api/oil_card.py`

### Frontend JS
- `public/js/oil_card_refuel_log.js`
- `public/js/oil_card_invoice_batch.js`
- `public/js/vehicle_oil_card_actions.js`

### Reports
- `report/vehicle_refuel_history/`
- `report/vehicle_fuel_efficiency/`
- `report/oil_card_balance_summary/`
- `report/oil_supplier_invoice_summary/`

### Tests
- `tests/test_oil_card_service.py`
- `tests/test_oil_card_invoice_service.py`
- `tests/test_oil_card_metrics.py`
- `tests/test_vehicle_oil_card_custom_fields.py`
- `tests_js/oil_card_refuel_log.test.cjs`

---

## 九、推荐实施顺序

### Task 1：先落主数据与交易单据结构
**Objective:** 把 4 个新对象和 Vehicle 补字段落下来。

**Files:**
- Create: `doctype/oil_card/*`
- Create: `doctype/oil_card_recharge/*`
- Create: `doctype/oil_card_refuel_log/*`
- Create: `doctype/oil_card_invoice_batch/*`
- Create: `doctype/oil_card_invoice_batch_item/*`
- Modify: `setup/custom_fields.py`
- Add tests for metadata

**验收：**
- 可以创建油卡
- 可以创建充值记录
- 可以创建加油记录
- 可以创建开票批次
- Vehicle 上能看到新增轻量字段

### Task 2：实现余额 / 里程 / 最近信息计算
**Objective:** 先让核心数据能自动算对。

**Files:**
- Create: `services/oil_card_service.py`
- Create: `utils/oil_card_metrics.py`
- Create tests

**验收：**
- 充值后卡余额增加
- 加油后卡余额减少
- 里程差自动计算
- Vehicle 最近信息正确回写

### Task 3：实现“选择车牌后显示最近历史”表单交互
**Objective:** 提升录入体验。

**Files:**
- Create: `api/oil_card.py`
- Create: `public/js/oil_card_refuel_log.js`
- Add JS tests if possible

**验收：**
- 选车后能看到上次加油日期 / 里程 / 升数 / 金额
- 表单无额外 JS 报错

### Task 4：实现开票批次 + 标准采购发票生成
**Objective:** 打通“待开票 -> 发票”。

**Files:**
- Create: `services/oil_card_invoice_service.py`
- Create: `public/js/oil_card_invoice_batch.js`
- Reuse: existing Purchase Invoice custom logic
- Add tests

**验收：**
- 批次能拉未开票记录
- 能生成标准 `Purchase Invoice`
- 能回写已开票/未开票金额

### Task 5：实现 Workspace + 报表 + 图表
**Objective:** 把“好看的管理视图”补齐。

**Files:**
- Create workspace fixtures / records
- Create reports
- Create number cards
- Create dashboard charts

**验收：**
- 能看不同车的使用记录
- 能看油耗、里程、加油总额
- 能看每张卡的余额和待开票
- 能看售油公司维度汇总

### Task 6：live 部署与真实验收
**Objective:** 在 ERPNext16 测试实例里真实点通。

**验收场景：**
1. 建一辆车
2. 建一张油卡
3. 录一次充值
4. 录 2-3 次加油
5. 选车查看历史
6. 发起开票批次
7. 生成采购发票
8. 回查待开票金额是否正确下降

---

## 十、一句话结论

**如果要把“油卡管理”做成一个既实用又好看的 ERPNext16 功能，最佳做法不是把所有内容塞进一个单据，而是用“标准 Vehicle + 独立油卡主数据 + 充值流水 + 加油流水 + 开票批次 + Workspace/报表/图表”的组合。这样字段清晰、交易清晰、查询清晰、发票清晰，后面扩展油耗分析、公司对账、售油公司汇总都会顺很多。**

# ERPNext16 油卡管理设计研究（预付充值 / 使用 / 待开票 / 车辆联动）

> **Status:** 研究与架构建议稿，尚未开始实现。
>
> **For Hermes:** 如果后续进入实施阶段，优先沿用本文的“主数据 + 交易单据 + 发票生成批次”结构，不要把所有逻辑硬塞进一个大 DocType。

**Goal:** 在 ERPNext16 中补齐“油卡预付、加油使用、待开票追踪、车辆里程联动、采购发票生成”这一整套业务能力，并尽量贴近 ERPNext 标准单据与会计逻辑。

**Architecture:** 油卡不建议只做成一个单独大表单，而应拆成：`Vehicle` 车辆主数据（复用标准）、`Oil Card` 油卡主数据、`Oil Card Recharge` 充值记录、`Oil Card Refuel Log` 加油记录、`Oil Card Invoice Batch` 开票批次。采购发票仍以标准 `Purchase Invoice` 为会计与发票事实单据，油卡系统负责维护“充值余额”和“待开票使用额”，再通过批次一键生成采购发票。

**Tech Stack:** ERPNext 16, Frappe 16, custom app `ashan_cn_procurement`, standard `Vehicle`, standard `Purchase Invoice`, standard `Payment Entry`, custom permission/reporting layer.

---

## 一、先说结论

你现在说的“油卡管理”，**从 ERPNext 的特征来看，不适合只做成一个单据**。

更合适的方式是：

### 1. “油卡管理”应该是一个业务域 / Workspace 名称
而不是唯一一个 DocType。

也就是说，用户界面上可以叫：
- `油卡管理`

但底层最好拆成几张单据：
- `Oil Card` 油卡
- `Oil Card Recharge` 油卡充值
- `Oil Card Refuel Log` 加油记录
- `Oil Card Invoice Batch` 油卡开票批次

### 2. 会计与发票事实单据仍然用标准 `Purchase Invoice`
不要再造一套自定义“发票单”替代 ERPNext 标准采购发票。

原因：
- 标准发票后面要接税、总账、付款、供应商往来
- 你现在已经把采购发票做了中国式增强
- 油卡发票最终也应该回到 `Purchase Invoice`

### 3. 充值余额和待开票金额是两条不同的线
这是这个功能最容易做乱的地方。

必须分开理解：

#### A. 充值余额
- 5000 充值进去
- 加油用了 3000
- 余额还剩 2000

这是**卡资金余额**问题。

#### B. 待开票金额
- 已经加油使用 3000
- 如果只开了 1000 发票
- 那么待开票还有 2000

这是**使用记录是否已被发票覆盖**的问题。

### 关键点
**充值余额 ≠ 待开票金额**

它们经常会接近，但业务语义完全不同。

ERPNext 里如果不拆这两条线，后面会很难对账。

---

## 二、结合 ERPNext 现状后的最佳放置方式

我已经核实过当前 live ERPNext16：

- 标准 `Vehicle` DocType 存在
- `Vehicle` 的 `name/autoname` 就是 `license_plate`
- `Vehicle` 已有：
  - `company`
  - `license_plate`
  - `last_odometer`
  - `employee`
  - `fuel_type`
  - `uom`
- 标准 `Purchase Invoice` 存在
- 标准 `Payment Entry` 存在

所以最合理的放置方式是：

### 1. 车辆主数据直接复用标准 `Vehicle`
不要再额外建一个“车牌管理”主表。

因为标准 `Vehicle` 已经能承接：
- 车牌号
- 所属公司
- 司机/员工
- 上次里程
- 燃料类型

如果你还需要“车牌备注”，建议只给 `Vehicle` 补一个轻量自定义字段，例如：
- `custom_vehicle_note`

这样你选 `津CB5959` 时，本质上就是选标准 `Vehicle`。

### 2. 油卡本身单独做主数据 `Oil Card`
油卡不是车辆，也不是供应商，更不是采购发票。

它是一个独立主数据，应该有自己的生命周期。

### 3. 加油与充值分成两类交易单据
因为：
- 充值是“往卡里预付钱”
- 加油是“实际发生消耗”

它们的校验、报表、开票逻辑都不同。

### 4. 开票再单独做一个“批次/结算单”
这是为了优雅解决：
- 哪些加油记录已经开票
- 哪些没开票
- 一张发票对应哪些加油记录
- 一次开票是否只开部分金额

如果直接在加油记录上做一个“生成发票”按钮，早期看起来简单，后面很容易乱。

因此推荐：
- 加油记录先形成“待开票池”
- 用户勾选需要开票的记录
- 生成 `Oil Card Invoice Batch`
- 再从批次生成标准 `Purchase Invoice`

---

## 三、推荐数据模型

## A. `Vehicle`（复用标准主数据）

### 继续复用的原因
- 车牌号天然就是车辆主键
- 标准已经有 company / last_odometer / fuel_type
- 后续做车辆视角报表更自然

### 建议追加的轻量字段
如果你要更贴近实际使用，建议只补少量自定义字段：
- `custom_vehicle_note`：车辆备注
- `custom_department`：所属部门（可选）
- `custom_default_oil_card`：默认油卡（可选）

---

## B. `Oil Card`（油卡主数据）

### 作用
一张物理油卡对应一条主数据。

### 建议字段
- `card_name` / `card_label`
- `company`（使用公司）
- `supplier`（售油公司，Link -> Supplier）
- `card_no`
- `card_no_masked`（可选，显示用）
- `default_vehicle`（默认车辆，可空）
- `status`（Active / Frozen / Lost / Closed）
- `opening_balance`
- `current_balance`（只读，系统汇总）
- `uninvoiced_amount`（只读，系统汇总）
- `valid_from`
- `valid_upto`
- `note`

### 设计说明
#### 为什么 `supplier` 放在油卡主数据里
因为同一张卡通常属于某一家售油公司，例如：
- 中石化
- 中石油

后续生成采购发票时，需要明确供应商是谁。

#### 为什么 `company` 放在油卡主数据里
因为你已经明确说了：
- 不同公司油卡不同

所以一张卡应该清楚归属哪个公司，后续：
- 充值
- 加油
- 开票
- 付款

都用这个公司做默认值和校验。

---

## C. `Oil Card Recharge`（油卡充值记录）

### 作用
记录每次预付款充值，不直接等于采购发票。

### 建议字段
- `company`
- `oil_card`
- `supplier`
- `posting_date`
- `recharge_amount`
- `bonus_amount`（可选，活动赠送金额）
- `effective_amount`（只读 = recharge_amount + bonus_amount）
- `mode_of_payment`
- `bank_account` / `cash_account`
- `payment_entry`（Link -> Payment Entry，可选）
- `remark`
- `status`

### 设计说明
#### 为什么充值不建议直接生成 `Purchase Invoice`
因为你描述的业务本质是：
- 先预付
- 后按使用情况开发票

如果充值时直接生成采购发票，会和“按使用开发票”的业务口径冲突。

更贴近 ERPNext 的做法是：
- 充值对应 `Payment Entry` 或 `Journal Entry`
- 记到“预付油卡/预付款”类账户
- 真正开票时再生成 `Purchase Invoice`

### 会计建议
充值建议走：
- `Payment Entry` → 预付油卡科目

而不是直接走费用科目。

---

## D. `Oil Card Refuel Log`（加油记录）

### 作用
这是日常最常用的业务单据。

它记录：
- 哪辆车
- 哪张卡
- 什么时间
- 加了多少油
- 花了多少钱
- 当前里程是多少
- 有没有开票

### 你当前已经想到的字段
你提到的一般录入信息包括：
- 当前日期
- 里程
- 油号
- 金额
- 升数
- 或充值记录

这些都应该保留。

### 推荐字段
- `company`
- `oil_card`
- `vehicle`（Link -> Vehicle）
- `license_plate_snapshot`（可选快照）
- `posting_date`
- `supplier`
- `station_name`（加油站点）
- `fuel_grade`（92/95/98/0# 等）
- `odometer`
- `previous_odometer`（只读，自动带出）
- `distance_since_last`（只读，自动计算）
- `liters`
- `amount`
- `unit_price`（只读或自动算）
- `previous_liters`（只读，自动带出）
- `driver_employee`（可选）
- `route_or_purpose`（用途/路线，可选）
- `receipt_no`（小票号，可选）
- `attachment`（票据图片，可选）
- `invoiced_amount`（只读）
- `uninvoiced_amount`（只读）
- `invoice_status`（未开票 / 部分开票 / 已开票）
- `purchase_invoice`（若一对一时可回填；若批次式则通过子表追踪）
- `remark`

### 核心自动行为
#### 1. 选车辆后显示历史信息
当用户选择：
- `津CB5959`

应自动显示：
- 上次加油日期
- 上次里程
- 上次加油升数
- 上次百公里油耗（可选）

#### 2. 里程校验
- 当前 `odometer` 不能小于上次里程
- 如果跳变过大，可以给 warning，不一定直接阻塞

#### 3. 自动计算
- `unit_price = amount / liters`
- `distance_since_last = odometer - previous_odometer`
- 可继续算：
  - `km_per_liter`
  - `liter_per_100km`

#### 4. 自动扣减卡余额
提交加油记录后：
- 油卡余额减少

### 设计说明
这里的加油记录，是整个系统的“消耗事实来源”。

后续：
- 待开票统计
- 车辆油耗分析
- 单卡余额变化
- 某车全部加油记录

都靠它。

---

## E. `Oil Card Invoice Batch`（油卡开票批次）

### 作用
把“待开票的加油记录”整理成一批，然后生成标准 `Purchase Invoice`。

### 为什么需要这个批次单
因为你举的例子本质上已经说明了：

- 充值 5000
- 已用 3000
- 要一键开发票
- 剩余 2000 没开票

真正要追的不是“卡还有多少余额”而已，而是：
- 哪些使用记录已经被发票覆盖
- 哪些还没被发票覆盖

最稳妥的做法，就是做一个“开票批次”。

### 建议字段
- `company`
- `supplier`
- `oil_card`（可选，支持单卡）
- `from_date`
- `to_date`
- `total_amount`
- `purchase_invoice`
- `status`（Draft / Invoiced / Cancelled）
- 子表：`Oil Card Invoice Batch Item`

### 子表字段
- `refuel_log`
- `vehicle`
- `posting_date`
- `amount`
- `already_invoiced_amount`
- `invoice_amount_this_time`
- `remaining_uninvoiced_amount`
- `remark`

### 按钮
- `拉取待开票记录`
- `生成采购发票`
- `打开采购发票`

### 发票生成逻辑
点击 `生成采购发票` 后：
- 自动创建标准 `Purchase Invoice`
- `supplier` = 油卡对应售油公司
- `company` = 批次公司
- `posting_date` = 批次日期或用户选择日期
- 自定义字段中可回填：
  - `custom_biz_mode = 月结补录` 或专门新增油卡业务模式（见后文建议）
  - `custom_invoice_type`
- 通过自定义明细/关联子表，记录本次发票覆盖了哪些加油记录

### 为什么不建议“直接从 Oil Card 一键生成发票，不经过批次”
因为后续会遇到这些问题：
- 只想开本月，不想开上月
- 只想开某一辆车的记录
- 同一张卡下部分记录暂不开发票
- 发票金额与使用金额不是 100% 一致

批次单能把这些复杂度接住。

---

## 四、业务流程建议

## 流程 1：充值
1. 新建 `Oil Card Recharge`
2. 记录充值金额
3. 如已付款，可同步生成/关联 `Payment Entry`
4. 油卡余额增加

## 流程 2：加油
1. 新建 `Oil Card Refuel Log`
2. 选择：
   - 公司
   - 油卡
   - 车辆（车牌）
3. 系统自动显示：
   - 上次里程
   - 上次加油信息
4. 录入：
   - 日期
   - 里程
   - 油号
   - 金额
   - 升数
5. 系统自动：
   - 算单价
   - 算里程差
   - 扣减油卡余额
   - 增加待开票金额

## 流程 3：开票
1. 新建 `Oil Card Invoice Batch`
2. 拉取待开票加油记录
3. 确认本次要开票的金额/记录
4. 一键生成 `Purchase Invoice`
5. 系统回写：
   - 对应加油记录的已开票金额
   - 待开票余额
   - 批次与采购发票的关联

## 流程 4：查询
### 从油卡看
看：
- 当前余额
- 已充值总额
- 已使用总额
- 待开票金额

### 从车辆看
看：
- 某车全部加油记录
- 上次加油日期
- 上次里程
- 平均油耗

### 从发票看
看：
- 某张采购发票对应哪些加油记录
- 哪些记录尚未开票

---

## 五、和 ERPNext 标准单据怎么衔接最合适

## 1. `Vehicle`
直接复用标准 `Vehicle`。

这是当前 live 环境已经存在并可复用的最合适主数据。

## 2. `Purchase Invoice`
标准采购发票继续作为：
- 正式供应商发票
- 税务单据
- 应付单据
- 后续付款依据

## 3. `Payment Entry`
充值付款最好走标准 `Payment Entry`。

这样：
- 付款流水不需要另造
- 银行/现金账户也继续走 ERPNext 标准逻辑

## 4. `Supplier`
售油公司直接用标准 `Supplier`。

不建议再做“油站公司”自定义主表。

如果确实要记录站点级别信息，可以在加油记录里写：
- `station_name`

而供应商主体仍然是 `Supplier`。

---

## 六、业务模式怎么放更合适

你现在系统里 `custom_biz_mode` 已经被收敛到 4 个值：
- `采购申请`
- `报销申请`
- `电汇申请`
- `月结补录`

### 对油卡发票，我的建议
**v1 先归到 `月结补录`，不要立即新增第 5 个值。**

原因：
- 油卡开票本质上很像按期间汇总补录进采购发票
- 你刚把 biz_mode 收敛成 4 个值，现在马上再放大值域，会破坏刚完成的简化

### 什么时候再考虑新增“油卡管理”业务模式
只有当后续出现这些情况时，再考虑：
- 统计报表必须单独按油卡区分
- 审批流、权限、单号规则都和其他月结补录完全不同
- 油卡发票量已经足够大，单独分类比维持统一更值

在 v1 阶段，我建议：
- 业务领域叫“油卡管理”
- 发票业务模式先仍归 `月结补录`

---

## 七、你目前没提但我认为应该补进去的点

这是我认为你**很可能后面会需要，但当前口述里还没完全展开**的部分。

## 1. 部分开票
一条加油记录不一定总是整条一次性开票。

所以最好不要只存：
- `是否已开票`

而要存：
- `invoiced_amount`
- `uninvoiced_amount`
- `invoice_status`

这样以后更稳。

## 2. 余额调整 / 退款 / 退卡
现实里会遇到：
- 卡作废
- 退余额
- 充值冲正
- 人工调账

所以后续最好预留一种：
- `Oil Card Adjustment`

但 **v1 可以先不做独立 DocType**，先用 `status + Journal Entry/备注` 兜住；如果以后频繁出现，再单独做。

## 3. 卡和车不是永远一一绑定
有的卡固定一辆车，有的卡是车队共用。

所以：
- `Oil Card.default_vehicle` 只能是默认值，不能当唯一关系
- 真正的使用关系，还是以 `Oil Card Refuel Log.vehicle` 为准

## 4. 异常油耗提醒
这个不是 v1 必须，但很有价值。

如果你录了：
- 里程
- 升数

系统就能算：
- 百公里油耗

这样以后可以发现：
- 漏录里程
- 里程跳错
- 异常用油

## 5. 票据附件
建议加：
- 小票照片 / 发票照片 / 备注附件

因为加油业务后面经常会回头核对。

## 6. 发票并不一定按单卡开
有些售油公司可能按：
- 公司 + 时间段
- 公司 + 站点
- 多卡合并

所以 `Oil Card Invoice Batch` 最好：
- 支持单卡
- 但不要强制只能单卡

v1 可以先做单卡；架构上别把未来多卡合并彻底堵死。

## 7. 税率 / 发票类型
油卡发票也会碰到：
- 专票
- 普票
- 无票

所以生成采购发票时，应该沿用你现在已经做好的：
- `custom_invoice_type`
- VAT 桥接规则

不要再单独搞一套油卡发票税务逻辑。

---

## 八、推荐的 v1 范围

如果现在就要做，我建议 v1 先做这 5 块：

### 1. 复用 `Vehicle`
- 补车辆备注字段（如需要）

### 2. 新建 `Oil Card`
- 卡主数据
- 余额只读汇总
- 待开票金额只读汇总

### 3. 新建 `Oil Card Recharge`
- 充值记录
- 可关联 `Payment Entry`

### 4. 新建 `Oil Card Refuel Log`
- 车辆联动
- 上次里程提示
- 自动计算单价/里程差
- 余额与待开票额联动

### 5. 新建 `Oil Card Invoice Batch`
- 拉取未开票使用记录
- 一键生成 `Purchase Invoice`
- 回写已开票/未开票金额

### v1 先不做的
- 多卡合并开票
- 异常油耗自动预警
- 退款/冲正的独立复杂单据
- 很复杂的审批流

这样范围可控，而且很快就能实际用起来。

---

## 九、如果让我给你一个最终建议

### 功能命名
前台功能域可以叫：
- `油卡管理`

### 但底层不要只做一个 DocType
而应该拆成：
- `Oil Card`
- `Oil Card Recharge`
- `Oil Card Refuel Log`
- `Oil Card Invoice Batch`

### 放置位置
我建议放在当前 custom app `ashan_cn_procurement` 里，作为同一业务域继续扩展。

### 在界面上的呈现方式
建议在自定义模块 / Workspace 里放一个分组：
- `车辆与油卡`
  - Vehicle
  - Oil Card
  - Oil Card Recharge
  - Oil Card Refuel Log
  - Oil Card Invoice Batch

### 会计边界
- 充值：走 `Payment Entry` / 预付类账户
- 发票：走标准 `Purchase Invoice`
- 付款与税：继续沿用现有 ERPNext + custom app 规则

---

## 十、一句话结论

**从 ERPNext 的特征看，“油卡管理”最合适的落地方式不是单独一个大单据，而是“标准 Vehicle + 自定义油卡主数据 + 充值记录 + 加油记录 + 开票批次 + 标准 Purchase Invoice / Payment Entry”这套组合。这样既能追卡余额，也能追待开票，还能自然接入车牌、里程、发票、公司、售油公司和后续报表。**

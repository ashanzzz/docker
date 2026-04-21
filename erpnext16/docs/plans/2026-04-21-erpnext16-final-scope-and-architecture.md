# ERPNext16 最终范围与架构计划（采购 / 发票 / 支付 / 报销）

> **For Hermes:** This is the current recommended plan to execute. Prefer this document as the decision baseline when earlier plan files overlap.

**Goal:** 在 ERPNext16 中，以最稳、最可维护的方式落地一套适合中国企业的采购与支出系统，范围只覆盖：

1. 物料需求（购买申请）
2. 采购订单
3. 采购入库
4. 采购发票
5. 支付
   - 现金
   - 电汇
   - 其他账户支付
   - 无发票现金支付
6. 报销系统

**Core Decision:**
- `Material Request` / `Purchase Order` / `Purchase Receipt` / `Purchase Invoice` / `Payment Entry` **全部继续使用 ERPNext16 原有单据**
- **只新增一个 custom app** 来扩展这些原有单据
- **只在确实需要时保留自定义 DocType：`Reimbursement Request`（报销申请）及其子表**

**Why this is the final recommendation:** 这是当前最接近你实际意图、升级风险最低、后续最可维护、同时最容易和 ERPNext16 标准能力兼容的方案。

---

## 1. 这次最终决定：哪些用原有单据，哪些自定义

## 1.1 继续用 ERPNext16 原有单据

### A. 物料需求（购买申请）
使用：`Material Request`

说明：
- 不新造“购买申请”DocType
- 直接把 `Material Request` 作为中国语义下的“物料需求 / 购买申请”
- 其中 `Purpose=Purchase` 即采购申请主线

### B. 采购订单
使用：`Purchase Order`

### C. 采购入库
使用：`Purchase Receipt`

### D. 采购发票
使用：`Purchase Invoice`

### E. 支付
使用：`Payment Entry`

说明：
- 现金支付：用 `Payment Entry + Mode of Payment=现金`
- 电汇：用 `Payment Entry + Mode of Payment=电汇`
- 其他账户支付：用 `Payment Entry + 选定 paid_from_account`
- 无发票现金支付：仍可进入 Payment Entry，但其来源可能不是标准采购发票，而是报销申请或特殊支出流程

---

## 1.2 保留自定义单据

### F. 报销系统
保留 / 重构：`Reimbursement Request`

原因：
- ERPNext15 里这个单据已经不是“临时表单”，而是成熟业务入口
- 它已经承担：
  - 非标准采购 / 直接支出 / 员工代付
  - 发票导入
  - 生成报销标题
  - 快捷付款
- 如果强行把报销场景塞回标准采购单据，会丢失你已经形成的业务语言

所以推荐：
- ERPNext16 中继续保留 `Reimbursement Request`
- 但不照抄 15 的碎片脚本形态
- 改成 custom app 中可维护的正式代码

---

## 2. 最终业务范围（按你刚刚确认的范围）

## 2.1 标准采购主线

1. **Material Request（物料需求 / 购买申请）**
2. **Purchase Order（采购订单）**
3. **Purchase Receipt（采购入库）**
4. **Purchase Invoice（采购发票）**
5. **Payment Entry（支付）**

适合：
- 正常采购
- 有供应商
- 有请购 / 下单 / 入库 / 发票 / 付款闭环

## 2.2 非标准支出 / 报销主线

1. **Reimbursement Request（报销申请）**
2. 关联：`Purchase Invoice` / `Purchase Invoice Item`
3. 付款：`Payment Entry`

适合：
- 现金报销
- 内部报销
- 自办电汇
- 月结补录
- 无发票现金支付
- 员工代付 / 事后补录支出

---

## 3. 为什么这个方案最合理

## 3.1 不新造采购申请 / 采购订单 / 采购入库 / 发票单据
原因：
- ERPNext16 标准采购链本来就有成熟闭环
- 新造主单据会破坏：
  - 标准来源关系
  - 标准按钮流程
  - 标准报表
  - 标准付款 / 对账逻辑
- 你真正要改的是：
  - 表单语言
  - 行项目结构
  - 税率录入方式
  - 支付和报销联动

所以最优做法是：
> **保留主单据，重构它们的交互层、显示层、计算层。**

## 3.2 报销系统必须保留
原因：
- 你的 15 已经证明：报销是独立业务主线
- 它不是采购发票的附属按钮而已
- 它承接了大量“非标准采购 / 非 PO 驱动”的支出场景

所以：
> **采购单据用标准，报销系统保留自定义。**

## 3.3 支付统一收口到 Payment Entry
这是最稳的设计。

不应该再造：
- 现金支付单
- 电汇支付单
- 其他账户支付单

因为这些都是**支付方式**，不是不同的主业务对象。

正确做法：
- 统一使用 `Payment Entry`
- 用 Mode of Payment + paid_from_account + 来源单据 来区分

---

## 4. 中国式单据列：统一设计

以下列风格，统一应用到：
- Material Request Item
- Purchase Order Item
- Purchase Receipt Item
- Purchase Invoice Item
- Reimbursement Invoice Item（尽量同一语言）

## 4.1 统一目标列

1. 物料号
2. 物料名
3. 规格参数
4. 单价不含税
5. 单价含税
6. 税率
7. 数量
8. 单位
9. 总金额不含税
10. 总金额
11. 备注

## 4.2 建议字段映射

| 显示列 | 字段 |
|---|---|
| 物料号 | `item_code` |
| 物料名 | `item_name` |
| 规格参数 | `custom_spec_model` |
| 单价不含税 | `rate` |
| 单价含税 | `custom_gross_rate` |
| 税率 | `custom_tax_rate` |
| 数量 | `qty` |
| 单位 | `uom` |
| 总金额不含税 | `amount` |
| 总金额 | `custom_gross_amount` |
| 备注 | `custom_line_remark` |

### 辅助字段
- `custom_tax_amount`
- 如有必要，继续维护：
  - `item_tax_rate`
  - `item_tax_template`

---

## 5. 行级税率：最终设计结论

## 5.1 可以做，而且建议做
你的关键需求是：

> 一个发票中，不同物料可以不同税率，税率应存在于每个明细行，并且可以联动计算。

这在 ERPNext16 中**可以实现**。

## 5.2 但实现方式必须分层

### 用户录入层
让用户直接操作：
- `custom_tax_rate`
- `rate`
- `custom_gross_rate`
- `qty`
- `amount`
- `custom_gross_amount`

### 联动计算层
必须支持这些录入模式：

#### 模式 A
输入：
- 税率
- 不含税单价
- 数量

自动算：
- 不含税总金额
- 税额
- 含税单价
- 含税总金额

#### 模式 B
输入：
- 税率
- 含税单价
- 数量

自动反算：
- 不含税单价
- 不含税总金额
- 税额
- 含税总金额

#### 模式 C
输入：
- 税率
- 不含税总金额
- 数量

自动算：
- 不含税单价
- 含税单价
- 含税总金额

#### 模式 D
输入：
- 税率
- 含税总金额
- 数量

自动反算：
- 含税单价
- 不含税单价
- 不含税总金额

## 5.3 和 ERPNext 标准税务结构的关系
最关键的结论：

### **不要只做自定义显示字段，不接标准税务结构。**

否则会出现：
- 界面能看
- 但采购发票 / 税额 / 付款 / GL / 报表可能不一致

### 推荐做法
- 用户填 `custom_tax_rate`
- 服务端自动生成 / 更新标准 `item_tax_rate`
- 必要时再映射到默认税模板或默认税科目

这样：
- 用户体验是中国式的
- 系统底层仍然尽量兼容 ERPNext 标准税务逻辑

---

## 6. 是否必须 custom app？

## 6.1 严格结论：正式上生产，建议必须有 custom app

### 原因
因为你的需求已经不再是：
- 改个字段
- 调个列表列顺序
- 写一个小提示

而是包含：
- 原有单据整体中国化
- 行级税率
- 含税 / 不含税双向联动
- 服务端强制重算
- 发票与报销联动
- 付款入口统一
- 非标准支出流程保留
- 打印格式
- 升级兼容

这些如果继续只堆在：
- Client Script
- Server Script
- Property Setter
- Custom Field

短期能跑，长期一定碎。

所以：
> **原有单据可以继续用，但业务代码必须进入 custom app。**

## 6.2 不是因为原有单据不够用，才需要 custom app
而是因为：
- 你的需求已经足够复杂
- 必须工程化
- 必须版本化
- 必须可测试
- 必须未来可升级

---

## 7. 最终技术方案

## 7.1 保留原有标准单据
- `Material Request`
- `Purchase Order`
- `Purchase Receipt`
- `Purchase Invoice`
- `Payment Entry`

## 7.2 保留 / 重构报销申请单据
- `Reimbursement Request`
- `Reimbursement Invoice Item`

## 7.3 新建一个 custom app
建议 app 名：
- `ashan_cn_procurement`

它负责：
- 字段 fixtures
- Property Setter fixtures
- Print Format
- doctype_js
- doc_events
- Python API
- 行税率桥接逻辑
- 报销申请迁移逻辑

---

## 8. custom app 模块边界（最终推荐）

## 8.1 `purchase_layout`
负责：
- 采购三单 + 发票的中国式列
- 规格参数、备注、明细摘要
- Grid 列顺序
- 中文标签

## 8.2 `purchase_tax`
负责：
- 行级税率
- 含税 / 不含税计算
- 同步到标准 `item_tax_rate`
- 校验金额一致性

## 8.3 `purchase_flow`
负责：
- 业务模式 `custom_biz_mode`
- Purchase Receipt 无 PO 时的分流逻辑
- 发票类型联动
- 从采购发票进入报销流程

## 8.4 `payment_flow`
负责：
- Payment Entry 统一收口
- 快捷付款
- 现金 / 电汇 / 其他账户支付的入口封装
- 无发票现金支付的处理逻辑

## 8.5 `reimbursement`
负责：
- Reimbursement Request 结构迁移
- 发票导入
- 发票明细导入
- 标题辅助
- 报销付款

---

## 9. Payment（支付）最终建议

## 9.1 统一用 `Payment Entry`
支付类型不要做多个主单据，而要通过配置和入口区分：

### 支付方式
- 现金
- 电汇
- 其他账户支付
- 无发票现金支付

### 区分手段
- `Mode of Payment`
- `paid_from_account`
- 来源单据（Purchase Invoice / Reimbursement Request）
- 业务模式（必要时）

## 9.2 “无发票现金支付”怎么处理
这个不建议做成一个新的采购单据。

更合理的是：
- 作为 `Reimbursement Request` 或特定支出场景的一种业务模式
- 最终仍然创建 `Payment Entry`

这样：
- 财务动作统一
- 支付层不会裂成多套系统

---

## 10. 实施顺序（最终版）

## 第一阶段：采购主线基础重构
1. Material Request 子表中国式列
2. Purchase Order 子表中国式列
3. Purchase Receipt 子表中国式列
4. Purchase Invoice 子表中国式列
5. Print Format 中国化

## 第二阶段：行级税率落地
1. 增加 `custom_tax_rate` / `custom_gross_rate` / `custom_tax_amount` / `custom_gross_amount`
2. 做前端双向联动
3. 服务端强制重算
4. 同步到 `item_tax_rate`

## 第三阶段：支付体系统一
1. `Payment Entry` 快捷入口封装
2. 现金 / 电汇 / 其他账户支付入口统一
3. 无发票现金支付路径纳入报销或特殊支出流

## 第四阶段：报销系统迁移
1. 迁结构
2. 迁 API
3. 迁前端脚本
4. 迁快捷付款
5. 迁发票导入能力

---

## 11. 最终一句话决策

### 我认为最合理的最终方案是：

> **采购申请、采购订单、采购入库、采购发票、支付全部继续使用 ERPNext16 原有单据；**
> **报销系统继续保留自定义单据；**
> **所有中国式列、行级税率、支付联动、报销联动全部通过一个 custom app 来实现。**

这条路线最稳、最符合你现有业务意图，也最适合后续持续演进。

---

## 12. 与其他计划文档的关系

### 这份文档是“最终决策版”
建议优先参考本文件。

### 其他相关文档
- `erpnext16/docs/plans/2026-04-21-cn-procurement-and-reimbursement-plan.md`
  - 更偏实施任务拆解
- `erpnext16/docs/plans/2026-04-21-erpnext15-reverse-engineering-and-v16-tax-redesign.md`
  - 更偏 ERPNext15 逆向分析、意图还原、税率重构论证

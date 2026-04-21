# ERPNext15 现有定制逆向分析 + ERPNext16 重构设计（中国采购 / 报销 / 行级税率）

**Goal:** 基于 ERPNext15 当前已经跑起来的 Python / Client Script / Server Script / 自定义字段，反推出真实业务意图，并据此在 ERPNext16 中重新设计，而不是照搬 ERPNext15 的实现细节。

**Scope:**
- 逆向分析 ERPNext15 当前采购 / 报销相关定制
- 判断你为什么会这样做
- 设计 ERPNext16 中的新方案
- 重点回答：**“中国样式税率是否可以做到一张单据里每个明细行单独填税率？”**
- 给出成功概率、风险点、推荐路径

---

## 1. 先说结论

### 1.1 可以做，而且技术上是可落地的
你要的“**每个明细行可以直接填不同税率**”在 ERPNext16 里**可以实现**，而且不需要违背 ERPNext 的底层结构。

但正确做法不是“只加几个显示字段”，而是要把它设计成三层：

1. **显示层（中国式单据列）**
   - 规格参数
   - 单价不含税
   - 单价含税
   - 税率
   - 总金额不含税
   - 总金额
   - 备注

2. **计算层（前端 + 服务端重算）**
   - 行金额联动
   - 税额联动
   - 含税 / 不含税互算
   - 校验行数据一致性

3. **标准 ERPNext 兼容层（关键）**
   - 不直接绕开 ERPNext 税务结构
   - 把“行税率”同步到标准字段：
     - `item_tax_template`
     - `item_tax_rate`
   - 保持标准采购 / 发票 / 付款 / GL 逻辑还可以继续工作

### 1.2 成功概率判断

#### 高成功率部分
- 采购申请 / 采购订单 / 采购入库三张单据改成中国式列风格：**高概率成功**
- 报销申请迁到 ERPNext16：**高概率成功**
- 每行直接录税率、自动算含税价 / 不含税价：**高概率成功**
- 打印格式改造成中国风格：**高概率成功**

#### 中高风险但仍可落地的部分
- 行级税率与 ERPNext 标准税务引擎、采购发票、付款、总账严格对齐：**中高概率成功**
- 前提是必须采用“**兼容标准税务结构**”的方案，而不是完全自造一套税务计算引擎

#### 不推荐做法
- 直接改容器里的标准 `erpnext` / `frappe` 源码：**风险高，不建议**
- 继续把大量核心逻辑堆在 DB Server Script：**短期能跑，长期难维护**

---

## 2. ERPNext15 当前到底做了什么

这部分不是猜的，是对 live ERPNext15 只读检查后的结果。

## 2.1 代码层面：你现在的业务定制主要不在自定义 app 里
ERPNext15 当前 bench 中的 apps 有：
- `erpnext`
- `erpnext_chinese`
- `frappe`
- `hrms`
- `payments`
- `print_designer`

### 关键发现
`erpnext_chinese` 基本上只是：
- 中文翻译
- workspace/sidebar 小范围 override

**没有看到你采购 / 报销业务逻辑真正写在 custom app Python 里。**

也就是说，你现在真正的业务定制主要来自：
- `Custom Field`
- `Property Setter`
- `Client Script`
- `Server Script`

这很关键，因为它说明：

> 你现在这套 ERPNext15 的定制，本质上是“围绕标准单据的轻量重塑 + 少量 API 扩展”，而不是深度改核心框架。

这也解释了为什么 16 可以重构，而不必照搬 15 的脚本碎片。

---

## 2.2 ERPNext15 的采购 / 报销字段改造

### Material Request（采购申请）
新增：
- `custom_明细摘要`

### Material Request Item
新增：
- `custom_guige_xinghao`（规格型号）
- `custom_备注`
- `custom_总金额`

### Purchase Order
新增：
- `custom_明细摘要`

### Purchase Order Item
新增：
- `custom_guige_xinghao`
- `custom_备注`

### Purchase Receipt
新增：
- `custom_biz_mode`
- `custom_明细摘要`

### Purchase Receipt Item
新增：
- `custom_guige_xinghao`
- `custom_备注`

### Purchase Invoice
新增：
- `custom_biz_mode`
- `custom_发票类型`
- `custom_明细摘要`

### Purchase Invoice Item
新增：
- `custom_guige_xinghao`
- `custom_备注`

### Reimbursement Request（报销申请，自定义 DocType）
主字段：
- `custom_biz_mode`
- `company`
- `posting_date`
- `title`
- `payment_status`
- `paid_amount`
- `outstanding_amount`
- `total_amount`
- `invoice_items`

### Reimbursement Invoice Item
子字段：
- `item_name`
- `custom_guige_xinghao`
- `qty`
- `uom`
- `rate`
- `amount`
- `custom_备注`
- `invoice_no`
- `supplier`
- `source_pi`
- `source_pi_item`

---

## 2.3 ERPNext15 的 Client Script 清单（反映你的真实意图）

当前关键 Client Script 包括：

### Material Request
- `物料需求日期`

**意图：**
- 不让采购申请的 `schedule_date` 留空
- 按不同类型自动填默认日期
- 降低一线使用者出错概率

这说明你在意：
- 表单不要太 ERP 原教旨主义
- 要有符合实际操作习惯的默认值
- 用户“少填、少错、少卡住”比系统原生逻辑更重要

### Purchase Order
- `物料需求-采购订单`

**意图：**
- 从采购需求生成采购订单时，子表日期继续自动补齐
- 说明你想让采购链路前后行为一致

### Purchase Receipt
- `物料需求-采购入库`
- `采购入库-零金额提交提醒`

**意图：**
- 入库时继续沿用日期补齐逻辑
- 对“零金额提交”进行提醒，而不是一味阻断

这说明你想要的是：
- 系统能提醒风险
- 但仍然允许业务继续推进
- 不是纯技术性拦截

### Purchase Invoice
- `采购发票-发票类型联动`
- `采购发票列表-批量创建报销单`
- `采购发票按钮`

**意图：**
- 发票是财务和报销的中枢
- 发票类型（例如“无发票”）会影响 bill_no 行为
- 采购发票可以直接生成报销单
- 说明你在把“采购发票”和“报销流程”打通

### Reimbursement Request
- `Reimbursement Request`
- `Reimbursement Request列表`
- `报销申请-ai标题辅助`
- `报销申请-快捷付款`

**意图：**
- 报销单不是简单录入页，而是一个“发票导入 / 汇总 / 标题 / 快捷付款”的业务门户
- 你希望报销单具备：
  - 导入未付发票
  - 按发票明细导入
  - AI 辅助生成标题
  - 直接付款
  - 状态同步

这说明报销申请在你的系统中不是边缘单据，而是重要入口。

---

## 2.4 ERPNext15 的 Server Script 清单（反映你的业务边界）

### `PR Auto Biz Mode`
作用：`Purchase Receipt` / `Before Validate`

逻辑：
- 有采购订单 → `常规采购`
- 无采购订单 → 必须人工选：
  - 自办电汇
  - 月结补录
  - 现金报销
  - 内部报销

**反映的业务意图：**
你已经明确把业务分成两种：

1. **标准采购闭环**
   - 请购
   - 下单
   - 入库
   - 对账付款

2. **非标准采购 / 直接支出**
   - 没有采购订单
   - 但仍然要在财务上被分类

这是你整个系统的关键思想之一。

### `物料需求_明细摘要` / `采购订单_明细摘要` / `采购入库_明细摘要` / `采购发票_明细摘要`
作用：给单据生成 `custom_明细摘要`

**反映的业务意图：**
- 你希望列表页和单据概览能够快速看懂单据内容
- 不想每次都点开子表才能知道买了什么

也就是说：
> 你非常在意“列表可读性”和“管理层一眼看懂”。

### `采购发票-发票类型联动`
作用：发票类型 = 无发票 时，`bill_no = 0`

**反映的业务意图：**
- 中国实际业务里存在“无票”场景
- 系统必须显式表达这类情况，而不是假装所有支出都有合规票据

### `采购发票-创建报销申请`
作用：从采购发票直接创建报销申请

**反映的业务意图：**
- 采购发票不是采购流程的终点
- 对于现金报销 / 内部报销场景，采购发票是报销单的来源
- 你想避免重复录入

### `reimbursement_helper`
作用：报销单的后端中枢 API

根据脚本注释与行为，可以确认它做了这些事：
- 获取未付发票
- 获取发票明细
- 支持 company 过滤
- 支持 bill_date
- 支持锁定模式 / 排除已导入
- 读取 `custom_备注`
- 与 `Purchase Invoice` / `Purchase Invoice Item` 深度关联

**反映的业务意图：**
- 报销单要以“采购发票明细”为来源
- 同时要避免重复导入、跨公司误导入
- 你已经把“发票明细”作为真正的业务颗粒度

### `rr_quick_pay_accounts` / `rr_quick_pay_cash_submit`
作用：报销单快捷付款

**反映的业务意图：**
- 报销不只是审批单
- 它还要连到实际付款执行
- 用户不应该再跳好多层手工做 Payment Entry

### `发票单据-自办电汇自动付款`
作用：Purchase Invoice 提交后自动生成并提交付款凭证

**反映的业务意图：**
- 对“自办电汇”这种模式，你希望发票提交后自动进入付款
- 这是把“业务模式”直接驱动财务动作

---

## 3. 从这些脚本里反推出：你真正想要的系统是什么

如果把你 ERPNext15 的定制抽象一下，你并不是只想“汉化 ERPNext”。

你真正想做的是：

## 3.1 用中国企业常见表格语言重塑标准单据
你持续在做这些事：
- 增加规格型号列
- 增加备注列
- 增加明细摘要
- 调整列表显示
- 调整命名规则
- 调整打印格式

这说明你要的是：
> 单据要像中国企业在看，而不是像框架开发者在看。

## 3.2 把“采购”和“报销”统一到一套业务语言里
从 `custom_biz_mode`、`采购发票创建报销单`、`PR Auto Biz Mode` 可以明确看到：

你在做的是：
- 用标准采购处理“常规采购”
- 用报销申请处理“现金报销 / 内部报销 / 月结补录 / 自办电汇”等非标准支出
- 但两者共享发票、付款、金额、物料明细语言

也就是说：
> 你不想要两套彼此割裂的系统，而是想要“一个采购 / 支出操作系统”。

## 3.3 发票明细是核心颗粒度，不只是单据头
你不是只关心“这张单据多少钱”，而是关心：
- 每个物料是什么
- 规格是什么
- 数量是多少
- 备注是什么
- 哪张发票来的
- 对应哪个采购发票明细

这就是为什么你需要：
- 行级字段
- 行级备注
- 行级规格
- 现在继续进一步要：**行级税率**

---

## 4. ERPNext16 中“行级税率直接写在明细里”能不能实现？

## 4.1 结论：可以，而且 ERPNext 标准结构本身已经留了接口
我确认 ERPNext16 的这些标准子表都已经有内建字段：

### `Purchase Order Item`
- `item_tax_template`
- `item_tax_rate`
- `rate`
- `amount`
- `base_rate`
- `base_amount`
- `net_rate`
- `net_amount`

### `Purchase Receipt Item`
- `item_tax_template`
- `item_tax_rate`
- `rate`
- `amount`
- `base_rate`
- `base_amount`
- `net_rate`
- `net_amount`

### `Purchase Invoice Item`
- `item_tax_template`
- `item_tax_rate`
- `rate`
- `amount`
- `base_rate`
- `base_amount`
- `net_rate`
- `net_amount`

这意味着：

> ERPNext 底层不是完全不能按行处理税率，
> 只是标准 UI 不适合中国用户直接这么录。

也就是说，**你想要的是“重构交互方式”，不是推翻底层。**

---

## 4.2 关键设计判断：不要自造一套完全脱离 ERPNext 的税引擎

### 不推荐方案
- 自己完全维护 `custom_tax_rate` / `custom_tax_amount` / `custom_gross_amount`
- 然后不和 ERPNext 标准税结构同步

问题：
- GL / 应付 / 发票税额容易不一致
- 后续退款 / 红字 / 采购发票 / 报表会乱
- 你等于自己再造一个采购税务系统

### 推荐方案
保留中国式显示列，但**同步到标准字段**：

#### 给每个子表行保留这些可见字段
- `custom_spec_model`
- `custom_tax_rate`
- `custom_gross_rate`
- `custom_tax_amount`
- `custom_gross_amount`
- `custom_line_remark`

#### 同时把税率结果映射到标准字段
- `item_tax_rate`
- 视情况自动指定 / 维护 `item_tax_template`

也就是说：
- **用户录的是中国式列**
- **系统存的是中国式列 + ERPNext 标准兼容字段**

这样才稳。

---

## 4.3 行级税率方案的正确分层

### A. 对 Material Request（采购申请）
这是“计划单”，不是财务入账单。

所以这里的税率主要是：
- 预算税率
- 参考含税价
- 参考不含税价

这里可以直接用自定义字段，不必强求走 ERPNext 标准税引擎。

### B. 对 Purchase Order / Purchase Receipt
这两张是采购执行单据。

这里应该：
- 保留中国式列
- 行级录税率
- 服务端把行税率同步到 `item_tax_rate`
- 单据头保留标准 `Purchase Taxes and Charges`

### C. 对 Purchase Invoice
这是**真正的财务税务来源单据**。

这一层必须最严格：
- 行级税率是事实来源
- 标准税引擎要能理解它
- 报销申请如果引用发票明细，应以这里为准

### D. 对 Reimbursement Request
报销申请不是税务核算主单据，而是业务归集与付款入口。

所以推荐：
- 报销子表继承采购发票明细的税率与金额
- 不重新发明税率来源
- 如果后面要做纯报销无采购发票场景，再补一套轻量税字段

---

## 5. 推荐的 ERPNext16 重构方向

## 5.1 不要“照搬 ERPNext15”，而是提炼成 16 的正式架构

ERPNext15 的问题不是功能不行，而是：
- 大量逻辑散在 DB Client Script / Server Script
- 维护成本高
- 不利于版本管理
- 不利于测试
- 不利于未来扩展行级税率

### 在 16 中应改成：

#### 第一层：字段与显示层
通过：
- `Custom Field`
- `Property Setter`
- `Print Format`

完成：
- 中国式列
- 列顺序
- 中文标签
- 列表可读性

#### 第二层：前端行为层
通过：
- `doctype_js`
- app 内的 `public/js/*.js`

完成：
- 自动带出规格参数
- 行税率 / 含税价 / 不含税价联动
- bill_no / 发票类型联动
- 按钮与快捷操作

#### 第三层：服务端行为层
通过：
- 自定义 app Python
- hooks / doc_events / whitelisted methods

完成：
- 校验
- 行税率标准化同步
- 创建报销申请
- 快捷付款
- 发票导入
- 明细摘要生成

---

## 5.2 在 16 中建议统一的采购明细列

| 目标列 | 建议字段 |
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

### 公式建议
- `amount = qty * rate`
- `custom_tax_amount = amount * custom_tax_rate / 100`
- `custom_gross_amount = amount + custom_tax_amount`
- `custom_gross_rate = custom_gross_amount / qty`

### 双向编辑建议
建议支持两种输入习惯：

#### 方式 A：输入不含税价
用户填：
- 数量
- 单价不含税
- 税率

系统自动算：
- 税额
- 含税单价
- 含税总金额

#### 方式 B：输入含税价
用户填：
- 数量
- 单价含税
- 税率

系统反算：
- 单价不含税
- 不含税金额
- 税额

这正是中国企业常见录单方式。

---

## 5.3 行级税率如何和 ERPNext 标准字段桥接

### 推荐桥接方式
当每一行保存时：

- `custom_tax_rate` 是用户可见输入
- 服务端生成 / 更新该行 `item_tax_rate`

例如概念上可以变成：

```python
row.item_tax_rate = json.dumps({
    tax_account_head: row.custom_tax_rate
}, ensure_ascii=False)
```

### 优点
- ERPNext 标准税逻辑还能读懂
- 采购发票与税额报表不至于完全脱节
- 后续如果要做按税率分组统计，也有标准基础

### 第一阶段建议约束
第一阶段不要支持“每行不同税科目”。

只支持：
- 每行不同税率
- 但统一映射到一个标准进项税科目 / 或按公司配置的默认进项税科目

原因：
- 大大降低复杂度
- 已经能满足绝大多数中国采购录单习惯

### 第二阶段再考虑
若你后面要做更强版本，可支持：
- 税率 → 税模板 / 税科目映射
- 例如 13% / 9% / 6% 分别映射不同逻辑

但这不必一开始就做。

---

## 6. 我现在理解到的“你为什么这么做”

综合 ERPNext15 的脚本与字段，我认为你的核心意图是：

## 6.1 不是为了炫技，而是为了减少重复劳动
你已经做了很多“自动补日期 / 自动摘要 / 自动创建 / 自动付款 / 自动联动”的逻辑。

这说明你在意的是：
- 减少重复录入
- 减少用户判断成本
- 降低录错概率

## 6.2 你不接受“ERPNext 原生字段看不懂”的体验
你把很多单据改成：
- 中文列
- 明细摘要
- 规格型号独立列
- 发票类型联动
- 零金额提醒

这说明你要的是：
- 单据给业务看得懂
- 列表给管理层看得懂
- 而不是技术上“字段都在就行”

## 6.3 你已经在用“业务模式”统一采购与支出
`custom_biz_mode` 是你整个系统的中枢思想之一。

它把原来 ERPNext 里容易割裂的东西连接了：
- 常规采购
- 月结补录
- 自办电汇
- 现金报销
- 内部报销

这意味着在 ERPNext16 重构时，不应该只做“单据美化”，而应该继续保留这套业务模式体系。

---

## 7. 对 ERPNext16 的推荐重构方案

## 7.1 总体原则

### 原则 1
**ERPNext16 不直接复制 ERPNext15 的 DB 脚本形态。**

### 原则 2
**ERPNext15 的业务意图全部保留。**

### 原则 3
**采购单据与报销申请的语言统一。**

### 原则 4
**税务逻辑不脱离 ERPNext 标准结构。**

---

## 7.2 建议的新架构

### 主体：自定义 app
建议 app 名：
- `ashan_cn_procurement`

### 模块分层

#### 模块 A：采购三单中国式重构
- Material Request
- Purchase Order
- Purchase Receipt

#### 模块 B：采购发票与税务桥接
- Purchase Invoice
- 行级税率桥接到标准 `item_tax_rate`
- 发票类型联动

#### 模块 C：报销申请迁移
- Reimbursement Request
- Reimbursement Invoice Item
- 从 15 迁结构与逻辑

#### 模块 D：支付与自动化
- 快捷付款
- 自办电汇自动付款
- 批量创建报销单

---

## 7.3 重构优先级

### 第一阶段（必须）
- 采购三单中国式列重构
- 行级税率 UI 与计算
- Purchase Invoice 行税率桥接
- 报销申请基础结构迁移

### 第二阶段（推荐）
- 采购发票创建报销申请
- 快捷付款
- 明细摘要
- AI 标题辅助

### 第三阶段（增强）
- 多税科目映射
- 更复杂税务规则
- 更复杂报销分类
- 历史数据迁移工具

---

## 8. 成功概率与风险评估

## 8.1 我认为可以成功，前提是采用正确路线

### 成功前提
1. **不用直接改标准 ERPNext 源码**
2. **把 15 的 DB 脚本迁成 custom app 里的正式代码**
3. **行税率与标准字段桥接，不做野路子税引擎**
4. **先做采购 / 税，再接报销，而不是一次全摊开**

## 8.2 最大风险点

### 风险 1：直接把 DB 脚本原样搬到 16
问题：
- 越搬越乱
- 难测试
- 难演进

### 风险 2：行税率只做显示，不接 ERPNext 标准结构
问题：
- 金额能显示
- 但财务不一定认
- 后续 GL / 发票 / 付款容易错位

### 风险 3：一开始就做过度复杂税务映射
问题：
- 很容易做成一个巨复杂项目
- 第一阶段不一定需要

---

## 9. 最终建议（给未来实施者）

### 方案判断

#### 该做
- 在 ERPNext16 中**重构**采购 / 报销体系
- 保留 15 的真实业务思想
- 增加中国式行税率输入能力
- 让每一行能直接填税率
- 用 custom app 工程化落地

#### 不该做
- 继续堆更多 DB Client Script / Server Script
- 直接魔改容器内标准代码
- 用完全脱离 ERPNext 的方式重新发明税务逻辑

### 一句话判断

> **这件事不是“能不能做”的问题，而是“要不要按正确方式做”。**
>
> 如果按 custom app + 行税率桥接标准字段 + 采购/报销两条线统一语言 的方式推进，
> 我判断这套 ERPNext16 重构是**可以成功的**，而且比 ERPNext15 更稳、更可维护。

---

## 10. 与上一份计划的关系

本文件是：
- **逆向分析与设计说明**

上一份计划文件是：
- `erpnext16/docs/plans/2026-04-21-cn-procurement-and-reimbursement-plan.md`
- 它更偏：**实施任务分解**

建议后续：
- 先按本文件确认方向
- 再按上一份文件推进实施

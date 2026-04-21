# ERPNext16 中国式采购单据 + 报销申请迁移 Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** 在 ERPNext16 中，把采购申请、采购订单、采购入库改造成更符合中国用户习惯的单据风格，并把 ERPNext15 里已经跑起来的“报销申请”能力迁移到 16，形成一套统一的采购 / 报销业务流程。

**Architecture:** `ashanzzz/docker` 继续作为 ERPNext16 AIO 镜像与集成仓库，**不直接在镜像里魔改标准 ERPNext 源码**。真正的业务定制放进一个新的自定义 Frappe App（下文暂定名 `ashan_cn_procurement`），通过 fixtures、hooks、Client Script、Python API 与 Print Format 落地；本仓库负责保存方案文档，并在后续把自定义 app 加进 `erpnext16/image/apps.json` 参与镜像构建。

**Tech Stack:** ERPNext 16 / Frappe 16、Custom Field、Property Setter、Client Script、whitelisted Python methods、fixtures、Print Format、AIO Docker build。

---

## 1. 为什么要这样改

这次需求本质上不是“多加几个字段”，而是要把 ERPNext 的标准采购单据，调整成更贴近中国企业实际使用习惯的视图和流程。

### 1.1 你想要的采购明细风格
你明确要的是每个物料都按下面的列来理解和展示：

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

这和 ERPNext 标准英文化字段相比，更强调：
- **中文使用习惯**
- **含税 / 不含税并列展示**
- **规格参数单独成列**
- **备注明确独立，不混进 description**
- **采购申请 / 采购订单 / 采购入库三种单据尽量长得像同一套语言**

### 1.2 为什么还要把“报销申请”迁过来
当前 ERPNext15 里已经有一个自定义单据：`Reimbursement Request`（报销申请）。

从 live 系统只读检查可确认：
- 主单据：`Reimbursement Request`
- 子表：`Reimbursement Invoice Item`
- 它已经不是空壳，而是被真实在用的业务单据
- 最近单号形如：`BX-2026-04-00130`
- 子表里已经出现很多中国式报销场景：
  - 快递费
  - 员工餐费
  - 临时工工资
  - 货车维修保养
  - 微波炉采购
- 它已经有完整的客户端脚本与后端 API 配套：
  - `reimbursement_helper`
  - `n8n_proxy`
  - `rr_quick_pay_accounts`
  - `rr_quick_pay_cash_submit`

所以你真正想保留的不是“一个单据名字”，而是一种业务能力：

### 1.3 你想保留的业务能力
- **标准采购**：采购申请 → 采购订单 → 采购入库 → 采购发票 → 付款
- **非标准采购 / 直接支出 / 员工代付**：报销申请 → 发票导入 / 对应采购发票 → 付款 / 核销

这两条线都要保留，而且要在 ERPNext16 里讲得通。

---

## 2. 当前 live 系统调研结论

## 2.1 ERPNext16 当前现状（已验证）

### 标准采购单据
ERPNext16 live metadata 已验证以下标准 DocType：
- `Material Request`（采购申请对应：Purpose=Purchase）
- `Purchase Order`
- `Purchase Receipt`

对应子表：
- `Material Request Item`
- `Purchase Order Item`
- `Purchase Receipt Item`

### ERPNext16 已存在的相关自定义字段
在 16 的 live 系统里，已经存在这些采购相关自定义字段：

#### `Purchase Order Item`
- `custom_tax_rate`
- `custom_gross_rate`
- `custom_tax_amount`
- `custom_gross_amount`

#### `Purchase Receipt Item`
- `custom_tax_rate`
- `custom_gross_rate`
- `custom_tax_amount`
- `custom_gross_amount`

#### 但 `Material Request Item` 目前还没有同一套税额字段
这意味着：
- 采购订单 / 采购入库已经有了“含税/税率”方向的基础
- 采购申请还没统一到同一风格

## 2.2 ERPNext15 当前“报销申请”现状（已验证）

### 主单据字段
`Reimbursement Request` 当前主单据核心字段包括：
- `custom_biz_mode`：业务模式
  - 现金报销
  - 内部报销
  - 常规采购
  - 自办电汇
  - 月结补录
- `company`
- `posting_date`（报销日期）
- `title`（报销标题）
- `payment_status`
- `paid_amount`
- `outstanding_amount`
- `total_amount`
- `invoice_items`（子表）

### 子表字段
`Reimbursement Invoice Item` 当前子表核心字段包括：
- `item_name`（物料名称）
- `custom_guige_xinghao`（规格型号）
- `qty`
- `uom`
- `rate`（单价）
- `amount`（发票金额）
- `custom_备注`
- `invoice_no`
- `supplier`
- `source_pi`
- `source_pi_item`

### 报销申请当前的前端 / 后端能力
当前 15 里已经有以下能力：
- 报销单主表 Client Script
- 列表页 Client Script
- AI 标题辅助
- 快捷付款入口
- 发票导入 / 明细导入 / 未付发票筛选
- 按供应商拆分付款
- 与 `Purchase Invoice` / `Purchase Invoice Item` 的引用关系

**结论：** ERPNext16 不应该只“重新做一个长得像的单据”，而应该**接过 15 里已经被验证过的业务模式**。

---

## 3. 目标业务流程（交接版）

这是你现在想要的大概流程，我把它明确成两条主线。

## 3.1 标准采购主线

### 场景
适合：
- 正常采购
- 有明确请购
- 有供应商
- 后续需要采购订单、入库、发票、付款的完整闭环

### 流程
1. **采购申请（Material Request, Purpose=Purchase）**
   - 申请人提出需求
   - 填写物料号、物料名、规格参数、数量、单位、预计不含税单价、预计税率、预计含税单价、备注
   - 这里的价格允许是“预算价 / 参考价”

2. **采购订单（Purchase Order）**
   - 采购确认供应商与成交价
   - 继承采购申请行项目
   - 固化：不含税价、税率、含税价、不含税金额、含税金额、备注

3. **采购入库（Purchase Receipt）**
   - 仓库或采购确认实收
   - 继承采购订单行项目
   - 允许对数量、收货状态、拒收数量做调整
   - 保持中国式列显示风格不变

4. **采购发票（Purchase Invoice）**
   - 对账、进项发票、应付确认

5. **付款（Payment Entry）**
   - 正常对供应商付款

## 3.2 非标准支出 / 员工代付主线

### 场景
适合：
- 没走请购 / 采购订单
- 员工先垫付
- 快递费、维修费、餐费、临时工工资、补助等
- 事后补录

### 流程
1. **报销申请（Reimbursement Request）**
   - 按“业务模式”区分：现金报销 / 内部报销 / 自办电汇 / 月结补录 / 常规采购
   - 导入未付发票或直接选发票明细
   - 子表行风格尽量与采购单据统一

2. **关联采购发票 / 明细**
   - 保留当前 15 里已经存在的 `source_pi`、`source_pi_item` 逻辑

3. **提交后付款 / 快捷付款**
   - 沿用当前 15 里已经跑起来的“快捷付款”思路
   - 最终形成财务付款闭环

## 3.3 两条主线之间的关系

### 原则
- **常规采购**优先走采购申请 → 采购订单 → 采购入库
- **报销申请**主要处理非标准支出、员工代付、事后补录
- 报销申请里的 `custom_biz_mode = 常规采购` 应作为兼容字段保留，但不鼓励作为主要入口

### 你真正想要的是
- 用户看单据时，列风格统一
- 财务看金额时，含税 / 不含税统一
- 业务看流程时，标准采购和报销申请都能解释清楚

---

## 4. 设计决策

## 4.1 物料号不新增字段，直接用标准 `item_code`
目标列“物料号”直接映射：
- `item_code`

## 4.2 物料名直接用标准 `item_name`
目标列“物料名”直接映射：
- `item_name`

## 4.3 规格参数需要单独字段，不继续混用 description
推荐做法：
- 在 `Item` 主数据上新增：`custom_spec_model`
- 在交易子表上新增快照字段：`custom_spec_model`

原因：
- `description` 太长、太自由
- 打印 / 列表 / 子表联动时很难稳定展示
- 规格参数应成为明确一列，而不是附带文本

## 4.4 不含税金额仍以标准字段为主
推荐标准：
- `rate` = 单价不含税
- `amount` = 总金额不含税

原因：
- ERPNext 标准采购逻辑本来就围绕 `rate` / `amount`
- 避免和库存估值、后续标准逻辑脱节

## 4.5 含税相关使用自定义字段
推荐标准：
- `custom_tax_rate` = 税率
- `custom_gross_rate` = 单价含税
- `custom_tax_amount` = 税额
- `custom_gross_amount` = 总金额（含税）

## 4.6 备注单独成列
推荐字段：
- `custom_line_remark`

不建议继续把备注混进 `description`，否则：
- 规格参数和备注容易混
- 打印格式难以统一
- 列表展示不稳定

## 4.7 报销申请沿用 15 的成熟结构，但字段名要适当规范化
ERPNext15 里已有：
- `custom_guige_xinghao`
- `custom_备注`

迁到 16 时建议：
- 可以先兼容保留旧字段名
- 但新开发的长期方向建议统一成英文可维护命名，例如：
  - `custom_spec_model`
  - `custom_line_remark`

如果要避免一次性迁移过大，也可以先 **兼容旧字段名 + 新字段名双读写**，第二阶段再清理。

---

## 5. 目标字段映射

## 5.1 采购申请 / 采购订单 / 采购入库统一列映射

| 目标显示列 | 推荐字段 |
|---|---|
| 物料号 | `item_code` |
| 物料名 | `item_name` |
| 规格参数 | `custom_spec_model` |
| 单价不含税 | `rate` |
| 单价含税 | `custom_gross_rate` |
| 税率 | `custom_tax_rate` |
| 数量 | `qty`（采购入库可另保留 `received_qty` / `rejected_qty`） |
| 单位 | `uom` |
| 总金额不含税 | `amount` |
| 总金额 | `custom_gross_amount` |
| 备注 | `custom_line_remark` |

## 5.2 报销申请子表目标列映射

| 目标显示列 | 当前 15 字段 | 推荐 16 方向 |
|---|---|---|
| 物料号 | 无 | 可选新增 `item_code` 或继续不强制 |
| 物料名 | `item_name` | `item_name` |
| 规格参数 | `custom_guige_xinghao` | `custom_spec_model`（兼容旧字段） |
| 单价不含税 | `rate` | `rate` |
| 单价含税 | 当前无 | 视场景决定是否补 `custom_gross_rate` |
| 税率 | 当前无 | 视场景决定是否补 `custom_tax_rate` |
| 数量 | `qty` | `qty` |
| 单位 | `uom` | `uom` |
| 总金额不含税 | `amount` | `amount` |
| 总金额 | 当前等同 `amount` | 若启用税率则补 `custom_gross_amount` |
| 备注 | `custom_备注` | `custom_line_remark`（兼容旧字段） |

---

## 6. 仓库与代码放置策略

## 6.1 当前仓库的角色
本仓库：`ashanzzz/docker`

它当前是：
- ERPNext16 AIO 镜像仓库
- 不是业务 custom app 仓库

所以：
- **方案文档可以放这里**
- **真正业务代码不建议直接写在这里的标准 ERPNext 源码目录里**

## 6.2 推荐新增的 custom app 仓库
建议新增一个独立仓库（仓库名可后续再定，这里先给一个建议名）：

- `ashanzzz/ashan-cn-procurement`

App 名建议：
- `ashan_cn_procurement`

## 6.3 两个仓库如何分工

### `ashanzzz/docker`
负责：
- `erpnext16/` 镜像构建
- `erpnext16/image/apps.json` 里引入自定义 app
- 保存部署与集成方案文档

### `ashan-cn-procurement`
负责：
- Custom Field fixtures
- Property Setter fixtures
- Client Script（转 Python hooks + public js 的可维护版本）
- Python hooks / doc_events / whitelisted methods
- Print Format
- 报销申请 DocType 迁移

---

## 7. 文件路径约定（后续实施时按这个来）

## 7.1 当前仓库中要改的文件
- `erpnext16/image/apps.json`
- `erpnext16/README.md`
- `erpnext16/single-aio/README.md`
- `erpnext16/docs/plans/2026-04-21-cn-procurement-and-reimbursement-plan.md`

## 7.2 未来 custom app 仓库中的关键路径
假设 app repo 根目录就是 `ashan_cn_procurement/`：

- `ashan_cn_procurement/hooks.py`
- `ashan_cn_procurement/modules.txt`
- `ashan_cn_procurement/fixtures/custom_field.json`
- `ashan_cn_procurement/fixtures/property_setter.json`
- `ashan_cn_procurement/fixtures/client_script.json`（如仍要 fixture 化）
- `ashan_cn_procurement/public/js/material_request.js`
- `ashan_cn_procurement/public/js/purchase_order.js`
- `ashan_cn_procurement/public/js/purchase_receipt.js`
- `ashan_cn_procurement/api/purchase_doc.py`
- `ashan_cn_procurement/api/reimbursement.py`
- `ashan_cn_procurement/patches.txt`
- `ashan_cn_procurement/patches/v1_0/add_procurement_fields.py`
- `ashan_cn_procurement/fixtures/print_format.json`

若要把报销申请做成正式 DocType：
- `ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.json`
- `ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.py`
- `ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.js`
- `ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_invoice_item/reimbursement_invoice_item.json`

---

## 8. 实施任务

### Task 1: 建立 custom app 仓库与骨架

**Objective:** 建立一个长期可维护的 ERPNext16 自定义 app，而不是直接改镜像里的标准源码。

**Files:**
- Create: `ashan_cn_procurement/hooks.py`
- Create: `ashan_cn_procurement/modules.txt`
- Create: `ashan_cn_procurement/patches.txt`
- Create: `ashan_cn_procurement/fixtures/`
- Create: `ashan_cn_procurement/public/js/`
- Create: `ashan_cn_procurement/api/`

**Step 1: 初始化 app**

在 ERPNext16 开发环境执行：

```bash
bench new-app ashan_cn_procurement
```

**Step 2: 初始化 hooks.py 的 fixtures 与 doctype_js 声明**

```python
app_name = "ashan_cn_procurement"
app_title = "Ashan CN Procurement"
app_publisher = "a shan"
app_email = "ashanzzz1213@gmail.com"
app_license = "MIT"

fixtures = [
    "Custom Field",
    "Property Setter",
    "Print Format",
]

doctype_js = {
    "Material Request": "public/js/material_request.js",
    "Purchase Order": "public/js/purchase_order.js",
    "Purchase Receipt": "public/js/purchase_receipt.js",
}

doc_events = {
    "Material Request": {
        "validate": "ashan_cn_procurement.api.purchase_doc.validate_material_request",
    },
    "Purchase Order": {
        "validate": "ashan_cn_procurement.api.purchase_doc.validate_purchase_order",
    },
    "Purchase Receipt": {
        "validate": "ashan_cn_procurement.api.purchase_doc.validate_purchase_receipt",
    },
}
```

**Step 3: 提交骨架**

```bash
git add .
git commit -m "feat: scaffold ashan_cn_procurement app"
```

---

### Task 2: 给 Item 主数据增加“规格参数”字段

**Objective:** 把规格参数从自由文本里剥离出来，成为稳定可继承字段。

**Files:**
- Modify: `ashan_cn_procurement/fixtures/custom_field.json`

**Step 1: 新增 Item 字段 fixture**

```json
{
  "doctype": "Custom Field",
  "dt": "Item",
  "fieldname": "custom_spec_model",
  "label": "规格参数",
  "fieldtype": "Data",
  "insert_after": "item_name"
}
```

**Step 2: 导出 fixtures**

```bash
bench --site site1.local export-fixtures
```

**Step 3: 验证**

进入 Item 表单，确认：
- 可以看到 `规格参数`
- 新建 Item 时可填写
- 保存后值稳定保留

---

### Task 3: 给 Material Request Item 补齐中国式列字段

**Objective:** 让采购申请明细也支持含税/不含税统一风格，不再只有标准 qty/rate/amount。

**Files:**
- Modify: `ashan_cn_procurement/fixtures/custom_field.json`
- Modify: `ashan_cn_procurement/fixtures/property_setter.json`

**Step 1: 新增字段**

为 `Material Request Item` 增加：
- `custom_spec_model`
- `custom_tax_rate`
- `custom_gross_rate`
- `custom_tax_amount`
- `custom_gross_amount`
- `custom_line_remark`

推荐定义示例：

```json
{
  "doctype": "Custom Field",
  "dt": "Material Request Item",
  "fieldname": "custom_gross_rate",
  "label": "单价含税",
  "fieldtype": "Currency",
  "insert_after": "rate"
}
```

```json
{
  "doctype": "Custom Field",
  "dt": "Material Request Item",
  "fieldname": "custom_tax_rate",
  "label": "税率",
  "fieldtype": "Percent",
  "insert_after": "custom_gross_rate"
}
```

```json
{
  "doctype": "Custom Field",
  "dt": "Material Request Item",
  "fieldname": "custom_line_remark",
  "label": "备注",
  "fieldtype": "Small Text",
  "insert_after": "amount"
}
```

**Step 2: 用 Property Setter 调整列表列顺序**

目标顺序：
1. `item_code`
2. `item_name`
3. `custom_spec_model`
4. `rate`
5. `custom_gross_rate`
6. `custom_tax_rate`
7. `qty`
8. `uom`
9. `amount`
10. `custom_gross_amount`
11. `custom_line_remark`

**Step 3: 导出 fixtures 并验证**

```bash
bench --site site1.local export-fixtures
```

验证：
- Material Request 子表能看到新列
- 列顺序符合中国式单据习惯

---

### Task 4: 标准化 Purchase Order Item 与 Purchase Receipt Item

**Objective:** 把 16 里已存在的含税字段整理成统一规则，并补齐规格参数与备注列。

**Files:**
- Modify: `ashan_cn_procurement/fixtures/custom_field.json`
- Modify: `ashan_cn_procurement/fixtures/property_setter.json`

**Step 1: 复用已有字段，不重复造轮子**

当前 live 16 已存在：
- `custom_tax_rate`
- `custom_gross_rate`
- `custom_tax_amount`
- `custom_gross_amount`

因此：
- **不要重复新增这 4 个字段**
- 只补缺失字段：
  - `custom_spec_model`
  - `custom_line_remark`

**Step 2: 统一中文标签**

例如：
- `rate` → 单价不含税
- `amount` → 总金额不含税
- `custom_gross_rate` → 单价含税
- `custom_gross_amount` → 总金额
- `custom_tax_rate` → 税率
- `custom_line_remark` → 备注

**Step 3: 调整 grid 列顺序**

目标与 Material Request Item 一致。

**Step 4: 验证**

分别打开：
- Purchase Order
- Purchase Receipt

确认子表列顺序、标签和展示逻辑一致。

---

### Task 5: 编写采购单据前端联动脚本

**Objective:** 实现规格自动带出、含税/不含税自动换算、数量变化时金额自动刷新。

**Files:**
- Create: `ashan_cn_procurement/public/js/material_request.js`
- Create: `ashan_cn_procurement/public/js/purchase_order.js`
- Create: `ashan_cn_procurement/public/js/purchase_receipt.js`

**Step 1: 先抽共用计算函数**

建议每个文件都引用相同思路：

```javascript
function round2(v) {
  return flt(v, 2);
}

function sync_tax_fields(row) {
  const qty = flt(row.qty || 0);
  const rate = flt(row.rate || 0);
  const tax_rate = flt(row.custom_tax_rate || 0);

  row.amount = round2(qty * rate);
  row.custom_tax_amount = round2(row.amount * tax_rate / 100);
  row.custom_gross_amount = round2(row.amount + row.custom_tax_amount);

  if (qty) {
    row.custom_gross_rate = round2(row.custom_gross_amount / qty);
  }
}
```

**Step 2: item_code 变化时带出规格参数**

```javascript
frappe.db.get_value("Item", row.item_code, ["item_name", "custom_spec_model"])
  .then(r => {
    if (r.message) {
      frappe.model.set_value(cdt, cdn, "item_name", r.message.item_name || "");
      frappe.model.set_value(cdt, cdn, "custom_spec_model", r.message.custom_spec_model || "");
    }
  });
```

**Step 3: 绑定子表事件**

```javascript
frappe.ui.form.on("Purchase Order Item", {
  item_code(frm, cdt, cdn) {
    // fetch item master fields
  },
  qty(frm, cdt, cdn) {
    // recompute amounts
  },
  rate(frm, cdt, cdn) {
    // recompute amounts
  },
  custom_tax_rate(frm, cdt, cdn) {
    // recompute amounts
  },
  custom_gross_rate(frm, cdt, cdn) {
    // reverse compute if user edits gross price directly
  }
});
```

**Step 4: 验证**

逐行测试：
- 选 Item 后自动带出规格参数
- 改 `qty` 时总金额自动变化
- 改 `rate` / `custom_tax_rate` 时含税金额自动变化
- 改 `custom_gross_rate` 时能反推出税额或净价（按最终设计决定单向还是双向）

---

### Task 6: 服务端做权威校验与重算

**Objective:** 防止只靠前端脚本，保证导入、API、批量操作时金额逻辑也正确。

**Files:**
- Create: `ashan_cn_procurement/api/purchase_doc.py`
- Modify: `ashan_cn_procurement/hooks.py`

**Step 1: 编写通用行计算函数**

```python
def recompute_line(row):
    qty = float(row.qty or 0)
    rate = float(row.rate or 0)
    tax_rate = float(row.custom_tax_rate or 0)

    row.amount = qty * rate
    row.custom_tax_amount = row.amount * tax_rate / 100
    row.custom_gross_amount = row.amount + row.custom_tax_amount
    row.custom_gross_rate = row.custom_gross_amount / qty if qty else 0
```

**Step 2: 在 validate 中重算**

```python
def validate_purchase_order(doc, method=None):
    for row in doc.items:
        recompute_line(row)
```

**Step 3: 增加数据一致性校验**

例如：
- 若 `custom_gross_amount < amount` 则报错
- 若 `custom_tax_rate < 0` 则报错
- 若 `qty <= 0` 则报错

**Step 4: 验证**

通过以下方式都要一致：
- 界面新建单据
- 复制单据
- API 插入
- 批量导入

---

### Task 7: 增加打印格式 / 中文呈现

**Objective:** 不只是 grid 看着像中国单据，打印出来也要像。

**Files:**
- Modify: `ashan_cn_procurement/fixtures/print_format.json`

**Step 1: 为 3 张单据新增 Print Format**

建议至少增加：
- `采购申请-中国风格`
- `采购订单-中国风格`
- `采购入库-中国风格`

**Step 2: 打印列顺序必须与用户要求一致**

打印列按：
- 物料号
- 物料名
- 规格参数
- 单价不含税
- 单价含税
- 税率
- 数量
- 单位
- 总金额不含税
- 总金额
- 备注

**Step 3: 验证**

- 浏览器打印预览
- PDF 导出
- 金额显示是否为中文环境习惯

---

### Task 8: 迁移 ERPNext15 的报销申请 DocType

**Objective:** 把 15 里已验证过的报销申请迁到 16，而不是重新拍脑袋造一个新流程。

**Files:**
- Create: `ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.json`
- Create: `ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.py`
- Create: `ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.js`
- Create: `ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_invoice_item/reimbursement_invoice_item.json`

**Step 1: 先迁结构，不先迁复杂逻辑**

先把 15 当前结构迁进 16：

主单据至少保留：
- `custom_biz_mode`
- `company`
- `posting_date`
- `title`
- `payment_status`
- `paid_amount`
- `outstanding_amount`
- `total_amount`
- `invoice_items`

子表至少保留：
- `item_name`
- `custom_guige_xinghao` / `custom_spec_model`
- `qty`
- `uom`
- `rate`
- `amount`
- `custom_备注` / `custom_line_remark`
- `invoice_no`
- `supplier`
- `source_pi`
- `source_pi_item`

**Step 2: 保留旧命名兼容层**

如果 15 里已有大量数据与脚本依赖：
- 第一阶段允许保留 `custom_guige_xinghao`、`custom_备注`
- 第二阶段再逐步标准化为 `custom_spec_model`、`custom_line_remark`

**Step 3: 验证**

- 新建一张 Reimbursement Request
- 子表可录入和保存
- total_amount 正常汇总

---

### Task 9: 迁移报销申请的前端与 API 能力

**Objective:** 把 15 的实际使用体验迁进 16，尤其是发票导入、AI 标题、快捷付款。

**Files:**
- Create: `ashan_cn_procurement/public/js/reimbursement_request.js`
- Create: `ashan_cn_procurement/api/reimbursement.py`
- Modify: `ashan_cn_procurement/hooks.py`

**Step 1: 把 DB Server Script 迁成 Python API**

把 15 里这些 API 逻辑迁成 Python：
- `reimbursement_helper`
- `n8n_proxy`
- `rr_quick_pay_accounts`
- `rr_quick_pay_cash_submit`

**不要继续把核心业务逻辑只放在 Server Script 里。**

原因：
- Git 难管
- 版本难回滚
- 长脚本维护痛苦
- 不利于自动化测试

**Step 2: 把 15 的 4 个 Client Script 收敛整合**

当前 15 已存在：
- `Reimbursement Request`
- `Reimbursement Request列表`
- `报销申请-ai标题辅助`
- `报销申请-快捷付款`

迁到 16 时建议：
- 合并成 1~2 个可维护 JS 文件
- 不继续散落为多条 DB Client Script

**Step 3: 验证**

- 导入未付发票
- AI 标题生成
- 快捷付款
- 列表状态同步

---

### Task 10: 将 custom app 纳入 ERPNext16 AIO 镜像构建

**Objective:** 让 16 的定制真正跟着镜像发布，而不是只在某次手工改过的容器里存在。

**Files:**
- Modify: `erpnext16/image/apps.json`
- Modify: `erpnext16/README.md`
- Modify: `erpnext16/single-aio/README.md`

**Step 1: 在 apps.json 增加自定义 app**

示例：

```json
[
  {
    "url": "https://github.com/frappe/erpnext",
    "branch": "version-16"
  },
  {
    "url": "https://github.com/ashanzzz/ashan-cn-procurement",
    "branch": "main"
  }
]
```

**Step 2: 构建验证**

```bash
cd erpnext16/image
bash build.sh
```

或走当前 workflow。

**Step 3: 文档补齐**

README 必须解释：
- 这个 app 是做什么的
- 采购单据中国式布局做了哪些字段
- 报销申请为什么也在 16 里保留

---

### Task 11: 数据迁移与验收

**Objective:** 不只迁结构，还要确认真实业务能从 15 平滑交接到 16。

**Files:**
- Create: `erpnext16/docs/plans/reimbursement-migration-checklist.md`
- Create: `ashan_cn_procurement/patches/v1_0/migrate_reimbursement_schema.py`

**Step 1: 先迁结构，再决定是否迁历史数据**

优先级建议：
1. 先在 16 跑通单据结构与流程
2. 再决定是否迁历史 `Reimbursement Request` 数据
3. 若迁，优先迁近 3~6 个月活跃数据

**Step 2: 验收清单**

必须逐项确认：
- Material Request（采购申请）风格符合要求
- Purchase Order 风格符合要求
- Purchase Receipt 风格符合要求
- Print Format 正常
- 报销申请可创建
- 报销申请可导入未付发票
- 报销申请可快捷付款
- 财务金额逻辑一致

**Step 3: 提交**

```bash
git add .
git commit -m "docs: add ERPNext16 CN procurement and reimbursement migration plan"
```

---

## 9. 验收标准

满足以下几点，才算这套方案真的达标：

1. 采购申请 / 采购订单 / 采购入库三张单据的子表列风格统一
2. 用户肉眼能直接看懂：不含税 / 含税 / 税率 / 规格参数 / 备注
3. ERPNext16 中保留报销申请能力，不丢失 15 里的业务经验
4. 自定义逻辑可进 Git，可回滚，可跟镜像构建集成
5. 后续升级 ERPNext16 时，不需要重新手工在容器里打一遍补丁

---

## 10. 最后的工程判断

### 该怎么做
**正确路线：**
- 本仓库保存方案文档与 AIO 集成
- 新建 custom app 仓库存业务代码
- 通过 `erpnext16/image/apps.json` 把 app 纳入构建

### 不该怎么做
**不要：**
- 直接进 `erpnext16` 容器改 `apps/frappe` / `apps/erpnext`
- 继续把核心长逻辑只堆在 DB Server Script 里
- 把规格参数和备注继续全塞进 `description`

### 你想要的大概效果
最终你要的是：
- **采购单据看起来更像中国企业在用的单据**
- **报销申请保留，而且和采购流程讲得通**
- **ERPNext16 以后可持续迭代，不是一锤子买卖**

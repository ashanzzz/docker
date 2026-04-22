# ERPNext16 发票类型 VAT 规则 + 报销单迁移实施计划

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** 在 ERPNext16 中补齐采购发票“发票类型”规则，让 `VAT - 祺富` 只承接可抵扣税额，并把 ERPNext15 的报销单主流程迁进 `ashan_cn_procurement` custom app。

**Architecture:** 采购发票按文档级 `custom_invoice_type` 区分专用/普通/无发票，行税率继续由中国式字段驱动，但标准税桥接将根据发票类型把税额路由到不同标准税费科目。报销系统继续保留为自定义 DocType：先落结构、金额汇总、从采购发票创建入口，再逐步把 15 的导入/快捷付款能力迁入 Python API。报销主单建议明确加入“报销人”维度，优先使用标准 `Employee` Link 并自动带出姓名/部门，而不是只存一段自由文本。

**Tech Stack:** Frappe/ERPNext 16, custom fields, DocType JSON/Python/JS, whitelisted API, unittest, browser/live validation.

---

### Task 1: 为发票类型税桥接写 failing tests
**Objective:** 先锁定“专票进 VAT、普通票不进 VAT”的行为。

**Files:**
- Modify: `custom-apps/ashan_cn_procurement/tests/test_purchase_tax_bridge.py`
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/utils/purchase_tax_bridge.py`

**Checks:**
- `专用发票` → 税桥接到 `VAT - 祺富`
- `普通发票` → 不桥接到 `VAT - 祺富`
- `无发票` → 不桥接到 `VAT - 祺富`

### Task 2: 给 Purchase Invoice 增加 `custom_invoice_type`
**Objective:** 在采购发票上补 ERPNext15 里的“发票类型”字段。

**Files:**
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/setup/custom_fields.py`
- Modify: `custom-apps/ashan_cn_procurement/tests/test_app_layout.py` or add a focused metadata test

**Checks:**
- `Purchase Invoice` 存在 `custom_invoice_type`
- 选项至少包含：`专用发票`、`普通发票`、`无发票`

### Task 3: 前端补发票类型联动
**Objective:** 采购发票前端切换发票类型后，税桥接与 bill_no 行为同步更新。

**Files:**
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/public/js/procurement_controller.js`

**Checks:**
- 发票类型切换会重新桥接税费
- `无发票` 时 `bill_no = 0`
- 税费总额刷新正常

### Task 4: 落 Reimbursement Request / Reimbursement Invoice Item 结构
**Objective:** 先把 ERPNext15 的报销单结构迁进 16。

**Files:**
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/__init__.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.json`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.js`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_invoice_item/__init__.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_invoice_item/reimbursement_invoice_item.json`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_invoice_item/reimbursement_invoice_item.py`

**Checks:**
- 可以新建报销单
- 报销单存在 `employee`（报销人）并可自动带出 `employee_name` / `department`
- 子表可保存
- `total_amount / paid_amount / outstanding_amount / payment_status` 正常

### 补充设计：报销人字段怎么放更合适
为了后续：
- 查询“某个人的全部报销”
- 做部门维度统计
- 关联员工/司机/责任人

建议 `Reimbursement Request` 主表至少增加：
- `employee`：Link -> Employee，标签“报销人”
- `employee_name`：Data（Read Only / fetch）
- `department`：Link -> Department（Read Only / fetch，可选）

其中：
- `employee` 才是主键语义字段
- `employee_name` 只做展示快照
- 不建议只放一个手输的“报销人姓名”Data 字段，否则后续统计、筛选、关联都会变脏

### Task 5: 从采购发票创建报销单
**Objective:** 先把 ERPNext15 最核心的“采购发票 -> 报销单”主路径迁过来。

**Files:**
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/api/reimbursement.py`
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/hooks.py`
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/public/js/procurement_controller.js`
- Add tests for API mapping

**Checks:**
- 在采购发票上可直接创建报销单
- 报销子表能带入发票明细、供应商、source_pi、source_pi_item
- 避免重复录入

### Task 6: 部署到 live 测试实例并验收
**Objective:** 不只跑单测，要在正在运行的 ERPNext16 测试实例里实际点通。

**Files:**
- Sync changed files into running `erpnext16` container
- Run `bench build --app ashan_cn_procurement`
- Run `bench --site site1.local migrate`
- Restart services

**Checks:**
- 采购发票页面能选发票类型
- 专票税进 `VAT - 祺富`
- 普票税不进 `VAT - 祺富`
- 报销单可创建并从采购发票生成

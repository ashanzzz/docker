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

### 补充设计：`无发票` 的 `bill_no` 应该怎么设计

当前 v1 已实现：
- `custom_invoice_type = 无发票` 时，前端联动 `bill_no = 0`
- 目的主要是快速区分“真正无票”和“只是没填发票号”

这个做法在 **v1 过渡阶段可用**，因为：
- 很容易识别
- 前端联动简单
- 旧报表能立刻区分无票单据

但从长期维护角度，我建议后续收口为下面这套规则：

#### 推荐最终设计

### 1. `bill_no` 回到“真实外部发票号”语义
也就是：
- `专用发票`：`bill_no` 必填，且必须是真实票号
- `普通发票`：`bill_no` 必填，且必须是真实票号
- `无发票`：`bill_no` **留空**，不要再塞假的 `0`

原因：
- `bill_no` 本质是外部票据编号，不应该承载“无票状态”语义
- 大量单据都写成 `0`，后续筛选、搜索、打印、对账、接口同步都会变脏
- 如果未来接电子发票、OCR、票据导入或外部财务接口，`0` 会成为假数据噪音

### 2. “无票”状态由 `custom_invoice_type` 明确表达
真正决定语义的应该是：
- `custom_invoice_type = 无发票`

而不是靠 `bill_no = 0` 去反推。

### 3. 无票单据单独增加业务字段
建议至少补：
- `custom_no_invoice_reason`：无票原因
- `custom_no_invoice_note`：补充说明
- `custom_no_invoice_attachment`：佐证附件（截图/收据/审批依据）
- `custom_expected_invoice_date`：预计补票日期（可选）
- `custom_invoice_followup_status`：补票跟进状态（可选）

### 4. 如果界面上一定要显示“编号”，用只读展示字段，不污染 `bill_no`
例如增加：
- `custom_invoice_reference_display`

显示规则：
- 专票/普票：显示真实 `bill_no`
- 无票：显示类似 `无票 / <supplier> / <posting_date>` 的只读展示串

这样既方便列表页看，又不破坏标准字段语义。

#### 推荐过渡方案（兼容当前已落地实现）
- 已有旧数据里 `bill_no = 0` 的无票单据，可以暂时继续兼容识别
- 新版规则开始后：
  - 新建无票单据不再写 `0`
  - 后续可做一次数据清洗，把旧的 `bill_no = 0` 且 `custom_invoice_type = 无发票` 统一迁成空值

---

### 补充设计：发票类型整体规则建议

#### A. `专用发票`
- `bill_no`：必填
- `bill_date`：必填
- `VAT - 祺富`：允许桥接
- 附件：建议必传
- 校验重点：
  - 发票号不能为空
  - 发票日期不能为空
  - 税额/税率/金额应自洽

#### B. `普通发票`
- `bill_no`：必填
- `bill_date`：建议必填
- `VAT - 祺富`：不桥接
- 附件：建议必传
- 校验重点：
  - 不能误走可抵扣 VAT
  - 仍保留票据管理能力

#### C. `无发票`
- `bill_no`：留空
- `bill_date`：可空，或默认采用业务日期但不视为正式票据日期
- `VAT - 祺富`：不桥接
- `custom_no_invoice_reason`：必填
- `custom_no_invoice_attachment` / `custom_no_invoice_note`：至少满足其一，最好附件必填
- 校验重点：
  - 无票必须说明原因
  - 无票必须有佐证或审批依据
  - 后续如果补票，应允许把类型改回专票/普票并补真实 `bill_no`

---

### 当前这块还没完全考虑到的点

#### 1. “无票”和“暂未拿到票”其实不是一回事
建议后续明确区分：
- 真无票：本次业务本身就无票
- 暂未收票：后续预计补票

否则所有无票都会混在一起，后续财务追票很难做。

#### 2. 没有补票闭环
如果一张采购发票先按无票入账，后续拿到票：
- 怎么改类型
- 怎么补 `bill_no`
- 怎么记录原来是无票后补
- 是否需要补票日期 / 跟进状态

这条链建议后续补起来。

#### 3. 无票缺少管理口径字段
至少应能回答：
- 为什么无票
- 谁审批的
- 是否允许无票入账
- 后续是否要补票

#### 4. 报表口径还不够完整
后续建议加一张按发票类型汇总的采购发票报表，至少能看：
- 专票金额
- 普票金额
- 无票金额
- 可抵扣税额
- 不可抵扣税额
- 无票待跟进金额
- 按供应商/月度汇总

#### 5. 打印与对外接口语义
如果打印模板、导出、接口同步直接取 `bill_no`，`0` 会让外部误解为真实票号。
这也是我建议后续把无票的 `bill_no=0` 收回到“空值 + 单独无票字段”的重要原因。

---

### 一句话结论
我建议把现在的 `无发票 -> bill_no = 0` 定义为 **v1 过渡做法**；长期正式设计应改成：
- `bill_no` 只存真实票号
- `无发票` 时 `bill_no` 留空
- 用 `custom_invoice_type` 表示无票状态
- 再补 `无票原因 / 佐证附件 / 预计补票日期 / 跟进状态`

这样语义最干净，也最适合后续报表、审计、补票闭环和外部接口。

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

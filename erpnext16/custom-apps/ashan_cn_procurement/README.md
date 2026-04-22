# ashan_cn_procurement

`ashan_cn_procurement` 是 ERPNext16 的中国式采购 / 报销改造 custom app。

## 文档入口

- **用户 / 管理员操作说明**：[`erpnext16/docs/guides/erpnext16-cn-procurement-user-guide.md`](../../docs/guides/erpnext16-cn-procurement-user-guide.md)
- 默认业务日期与明细列宽实施计划：[`erpnext16/docs/plans/2026-04-22-phase2-default-date-and-grid-width.md`](../../docs/plans/2026-04-22-phase2-default-date-and-grid-width.md)
- 发票类型 VAT 规则 + 报销单实施计划：[`erpnext16/docs/plans/2026-04-22-phase3-invoice-type-vat-and-reimbursement.md`](../../docs/plans/2026-04-22-phase3-invoice-type-vat-and-reimbursement.md)
- 受限单据最终架构：[`erpnext16/docs/plans/2026-04-22-phase4c-restricted-doc-final-architecture.md`](../../docs/plans/2026-04-22-phase4c-restricted-doc-final-architecture.md)
- 油卡管理研究稿：[`erpnext16/docs/plans/2026-04-22-phase5-oil-card-management.md`](../../docs/plans/2026-04-22-phase5-oil-card-management.md)
- 油卡管理可实施计划：[`erpnext16/docs/plans/2026-04-22-phase5b-oil-card-implementation-plan.md`](../../docs/plans/2026-04-22-phase5b-oil-card-implementation-plan.md)
- 油卡管理字段清单：[`erpnext16/docs/plans/2026-04-22-phase5c-oil-card-field-checklist.md`](../../docs/plans/2026-04-22-phase5c-oil-card-field-checklist.md)
- 油卡管理表单布局稿：[`erpnext16/docs/plans/2026-04-22-phase5d-oil-card-form-layout-draft.md`](../../docs/plans/2026-04-22-phase5d-oil-card-form-layout-draft.md)
- 油卡管理 DocType JSON 顺序稿：[`erpnext16/docs/plans/2026-04-22-phase5e-oil-card-doctype-json-order-draft.md`](../../docs/plans/2026-04-22-phase5e-oil-card-doctype-json-order-draft.md)

## 当前已落地能力

### 采购四单增强
- 标准采购主链仍保留：
  - `Material Request`
  - `Purchase Order`
  - `Purchase Receipt`
  - `Purchase Invoice`
- 增加中国式明细录入字段与统一计算逻辑
- 业务模式统一为：
  - `采购申请`
  - `报销申请`
  - `电汇申请`
  - `月结补录`

### 全局业务日期
- 在 Desk 表单里可直接 `设定业务日期 / 清除业务日期`
- 设定后，新单据默认带入：
  - `posting_date`
  - `transaction_date`
  - `schedule_date`
  - `bill_date`
- 若单据存在 `set_posting_time`，会自动勾选

### 明细列宽配置
- 采购四单表单里可直接 `配置明细列宽`
- 列宽保存到当前用户的 `GridView` 设置
- 宽度支持任意正整数，不受 Customize Form 常见 1-10 限制

### 采购发票发票类型 + VAT 规则
- `Purchase Invoice` 增加 `custom_invoice_type`
- 支持：
  - `专用发票`
  - `普通发票`
  - `无发票`
- `专用发票` 税额桥接到可抵扣 VAT
- `普通发票 / 无发票` 不进入可抵扣 VAT
- `无发票` 前端联动 `bill_no = 0`

### 报销单体系
- 新增：
  - `Reimbursement Request`
  - `Reimbursement Invoice Item`
- 已支持 `Purchase Invoice -> Reimbursement Request` 主路径
- 已支持报销金额汇总与付款状态：
  - `未付款`
  - `部分付款`
  - `已付款`

### 受限单据体系
- 新增：
  - `Restricted Access Group`
  - `Restricted Access Group User`
  - `Restricted Access Group Role`
- 新增全局覆盖角色：`Restricted Document Super Viewer`
- 已在以下单据接入受限字段与权限判断：
  - `Material Request`
  - `Purchase Order`
  - `Purchase Receipt`
  - `Purchase Invoice`
  - `Reimbursement Request`
- 已支持 root 继承、标准 `Share` 例外授权、WebUI 配置闭环

### Restricted Access Group 表单优化
- 中文标签
- 默认说明文案
- 帮助文本
- 防误配提醒
- 完整表单模式（关闭 Quick Entry）

## 设计边界

### 放在 WebUI 的内容
- 受限组
- 组成员 / 角色成员
- 单据受限组归属
- 超级查看角色分配
- 临时 Share
- 业务日期使用
- 列宽偏好

### 放在代码的内容
- 发票类型 VAT 规则
- 业务模式标准值
- 报销生成逻辑
- 受限继承逻辑
- 权限判定顺序
- 文本清洗规范

一句话：

**配置在 UI，规则在代码。**

# ERPNext16 中国式采购 / 报销改造说明

> 适用仓库：`erpnext16/`
>
> 适用 custom app：`custom-apps/ashan_cn_procurement`
>
> 本文档同时面向两类读者：
> - **业务 / 管理员**：想知道系统现在怎么用、哪里配置、改完后有什么特性
> - **开发 / 运维**：想知道这次主要是怎么改的、边界在哪里、关键模块有哪些

---

## 1. 这次改造的目标

这次不是简单给 ERPNext 16 加几个字段，而是把它改造成更适合中国企业采购 / 报销场景的版本，同时尽量保持：

- 继续沿用 ERPNext 标准采购主链路
- 会计 / 总账 / 标准单据关系不被推翻
- 日常业务配置尽量放到 **WebUI**
- 稳定规则放到 **custom app 代码**
- 后续维护尽量干净、清晰、可扩展

一句话概括：

**配置放在 UI，规则放在代码；尽量保留 ERPNext 标准骨架，在上面做中国式采购 / 报销增强。**

---

## 2. 总体改造思路

### 2.1 保留 ERPNext 标准采购主链

仍然以 ERPNext 标准单据为主：

- `Material Request` 采购申请
- `Purchase Order` 采购订单
- `Purchase Receipt` 采购收货/入库
- `Purchase Invoice` 采购发票

没有把采购主链整体推倒重做，而是在这些标准单据上做中国式增强。

### 2.2 报销单作为单独的 custom DocType 保留

为了兼容 ERPNext15 里已经在用的报销逻辑，保留并重构了：

- `Reimbursement Request`
- `Reimbursement Invoice Item`

这样可以兼顾：

- 标准采购流程
- 员工代付 / 报销申请 / 直接支出类流程

### 2.3 受限单据采用方案 C

最终采用的权限方案是：

**`Restricted Access Group + 标准 Role/Profile 覆盖 + 标准 Share + Root 继承，无 bundle`**

原因是这个方案在以下几项之间最平衡：

- 维护成本
- 代码清晰度
- 与 ERPNext 原生逻辑的贴合度
- 后续扩展空间

---

## 3. 这次具体改了什么

## 3.1 全局“业务日期”功能

新增了一个全局业务日期能力。

### 改造前
ERPNext 默认按系统当前日期带入，遇到补录、回填历史单据时会非常不方便。

### 改造后
用户可以先设定一个“业务日期”，之后新建单据时会自动带入这个日期。

### 自动带入的字段
会同步影响以下标准日期字段（空值时自动带入）：

- `posting_date`
- `transaction_date`
- `schedule_date`
- `bill_date`

如果单据有 `set_posting_time`，系统还会自动勾上。

### 实现方式
- 服务端：通过 Frappe 用户默认值保存
- 前端：通过 app 级 JS 在 Desk 表单里统一提供入口

---

## 3.2 采购四单支持中国式明细录入

在采购四单的明细行上，补齐了中国式采购录入常见字段和计算逻辑。

### 重点增强方向
- 规格型号 / 规格参数
- 税率
- 含税单价
- 税额
- 价税合计
- 行备注

### 设计原则
不是另起一套完全脱离 ERPNext 的税务系统，而是：

- 前端给用户中国式录入体验
- 服务端把关键结果桥接回 ERPNext 标准字段/税逻辑

这样兼顾：

- 用户体验
- 与 ERPNext 标准数据结构兼容
- 后续维护可控

---

## 3.3 明细列宽可自定义，不再受 1-10 限制

你特别提出的需求之一是：

> 采购申请明细、发票明细这些明细列，希望能自定义宽度，而不是只能填 1-10

这个已经落地。

### 改造后
在采购四单表单里，可以直接配置当前用户的明细列宽。

### 特点
- 在表单里直接操作
- 保存的是当前用户自己的 GridView 设置
- 支持 **任意正整数宽度**
- 不再受 Customize Form 里常见的 1-10 静态思维限制

### 作用范围
- `Material Request`
- `Purchase Order`
- `Purchase Receipt`
- `Purchase Invoice`

---

## 3.4 `custom_biz_mode` 统一为 4 个标准值

业务模式字段已经被统一和收敛。

### 当前只保留 4 个值
- `采购申请`
- `报销申请`
- `电汇申请`
- `月结补录`

### 为什么要统一
以前历史值较多，例如：
- 常规采购
- 直接采购
- 员工代付
- 无发票现金支付
- 其他账户支付
- 自办电汇

这些值虽然来自历史业务，但长期会带来：

- 统计口径混乱
- 代码判断复杂
- 用户理解困难

所以现在统一成 4 个标准值，并做了历史值归并迁移。

---

## 3.5 采购发票增加“发票类型”并接入 VAT 规则

在 `Purchase Invoice` 上增加了：

- `custom_invoice_type`

### 当前可选值
- `专用发票`
- `普通发票`
- `无发票`

### 实际规则
#### 专用发票
- 税额桥接到可抵扣 VAT 科目
- 当前规则：`VAT - 祺富`

#### 普通发票
- 不进入可抵扣 VAT
- 走非抵扣税费逻辑

#### 无发票
- 不进入可抵扣 VAT
- 前端联动时会把 `bill_no = 0`

### 为什么这样设计
这是为了贴合中国企业真实财务逻辑：

- 不是所有税额都能进进项 VAT
- 发票类型决定是否可抵扣

### 额外处理
切换发票类型时，会清理并重建自动生成的税桥接行，避免旧 VAT 行残留。

---

## 3.6 补齐了“采购发票 -> 报销单”的主路径

已经实现从采购发票直接创建报销单的主路径。

### 新增 DocType
- `Reimbursement Request`
- `Reimbursement Invoice Item`

### 当前主路径
`Purchase Invoice -> Reimbursement Request`

### 自动带入的内容
会从采购发票带入：
- 公司
- 业务模式
- 来源采购发票
- 明细行
- 供应商
- 源明细引用
- 金额信息

### 金额口径
报销侧使用的是更贴近真实报销金额的 **含税 / gross** 口径，而不是只用不含税金额。

### 当前状态字段
报销单支持：
- `未付款`
- `部分付款`
- `已付款`

---

## 3.7 新增“受限单据”体系

为了实现敏感采购 / 报销单据的可见范围控制，新增了受限单据能力。

### 受控对象
当前已经接入：
- `Material Request`
- `Purchase Order`
- `Purchase Receipt`
- `Purchase Invoice`
- `Reimbursement Request`

### 父单字段
这些单据上新增了最小必要字段：
- `custom_is_restricted_doc`
- `custom_restriction_group`
- `custom_restriction_root_doctype`
- `custom_restriction_root_name`
- `custom_restriction_note`

### 权限主数据
新增了 3 个核心 DocType：
- `Restricted Access Group`
- `Restricted Access Group User`
- `Restricted Access Group Role`

### 全局覆盖角色
新增了：
- `Restricted Document Super Viewer`

适合总经理等默认可看所有受限单据的账号。

### 例外授权
临时给某一张单据放权，不另造系统，直接用 ERPNext 标准：
- `Share`

### 下游继承
如果上游单据是受限单据，下游单据会继承：
- 是否受限
- 受限组
- 权限源单据（root）

这样采购链和报销链可以保持同一可见范围。

---

## 3.8 Restricted Access Group 表单做了中文化和防误配优化

这部分已经不是“后台能配”而已，而是已经做成了更易用的 WebUI 表单。

### 已优化内容
- 中文字段标签
- 默认说明文案
- 更直观的帮助文本
- 顶部“配置原则”说明
- 防误配提醒
- 关闭 Quick Entry，强制走完整表单

### 重点提醒
子表里的：
- `访问级别（预留）`

当前版本只是预留说明，**不单独控制查看/编辑/管理权限**。

真正生效的是：
- 用户是否在组内
- 用户角色是否匹配组内角色成员
- 是否拥有 `Restricted Document Super Viewer`
- 是否被 `Share`

---

## 4. 用户应该怎么操作

## 4.1 设定业务日期

在任意 Desk 表单顶部找到：
- `业务日期`

可以执行：
- `设定业务日期`
- `清除业务日期`

### 典型使用场景
比如今天在补录 4 月 10 日的历史单据：

1. 先设定业务日期 = `2026-04-10`
2. 再新建采购申请 / 采购订单 / 入库 / 发票
3. 新单据会默认带入该日期

这样就不用每张单据手工改日期。

---

## 4.2 配置采购明细列宽

在采购四单表单里，找到：
- `明细 -> 配置明细列宽`

然后：
1. 打开配置对话框
2. 按需修改列宽
3. 保存
4. 刷新后仍会保留

### 注意
- 这是当前用户自己的界面配置
- 支持任意正整数宽度
- 不是全局字段定义修改

---

## 4.3 使用业务模式

在相关父单上，`custom_biz_mode` 现在统一使用以下 4 个值：

- `采购申请`
- `报销申请`
- `电汇申请`
- `月结补录`

建议后续业务培训、报表统计、流程判断，都统一按这 4 个值理解。

---

## 4.4 使用采购发票的“发票类型”

在 `Purchase Invoice` 上选择：

- `专用发票`
- `普通发票`
- `无发票`

### 业务含义
- **专用发票**：可抵扣税额进入 VAT
- **普通发票**：税额不进入可抵扣 VAT
- **无发票**：不进 VAT，且 `bill_no` 自动处理为 `0`

### 什么时候选什么
- 有进项专票：选 `专用发票`
- 只有普票：选 `普通发票`
- 没发票：选 `无发票`

---

## 4.5 从采购发票创建报销单

在 `Purchase Invoice` 页面，可以直接点击：
- `创建报销单`

系统会：
- 创建新的报销单，或打开已存在的来源报销单
- 自动带入来源采购发票信息
- 自动带入报销明细

### 使用建议
如果这张采购发票本质上要进入报销流程，就不要再重复录一张报销单，直接从采购发票创建即可。

---

## 4.6 配置受限单据组

在 ERPNext 搜索：
- `Restricted Access Group`

然后新建，例如：
- `采购核心组`
- `财务核心组`
- `总经办组`

### 在组里可以维护什么
- 是否启用
- 适用说明
- 指定用户成员
- 指定角色成员

### 推荐配置原则
- 一类岗位都要可见：优先放 **角色成员**
- 只有个别人要额外可见：再放 **用户成员**

---

## 4.7 给总经理默认可见所有受限单据

在 WebUI 里配置：
- `Role`
- `Role Profile`
- `User`

给对应账号加上：
- `Restricted Document Super Viewer`

这样该账号默认可看所有受限单据，不需要加入每一个组。

---

## 4.8 给某张单据标记为受限单据

在业务单据上：
1. 勾选 `受限单据`
2. 选择 `受限单据组`
3. 按需填写 `受限说明`

之后下游链路会自动继承对应限制信息。

---

## 4.9 使用表单上的权限辅助按钮

在采购单 / 报销单上，已经补了方便 WebUI 管理的按钮，例如：

- `管理受限单据组`
- `新建受限单据组`
- `查看受限单据组`
- `查看权限源单据`
- `查看来源采购发票`（报销单）

这意味着日常配置不需要再靠命令行。

---

## 4.10 临时例外授权

如果只是某一张单据临时给某个用户看，不需要改代码，也不建议为了单次例外新建一个组。

直接使用 ERPNext 原生：
- `Share`

即可。

---

## 5. 改造后系统具备哪些特性

当前已经具备的核心特性：

- ERPNext16 标准采购链仍保留
- 采购四单具备中国式明细录入体验
- 新单据可统一跟随业务日期
- 明细列宽可以按用户自定义
- 业务模式统一为 4 个标准值
- 采购发票支持发票类型并影响 VAT 规则
- 无发票自动联动 `bill_no = 0`
- 可从采购发票一键创建报销单
- 报销单已具备基本金额汇总与付款状态能力
- 受限单据能力已落地
- 受限权限可通过 WebUI 配置
- 受限组表单已经中文化并带防误配提示

---

## 6. 这次主要是怎么改的（技术视角）

本次改造主要落在 custom app：
- `custom-apps/ashan_cn_procurement`

### 关键模块
- `setup/custom_fields.py`
  - 创建采购/报销/受限相关 custom fields
- `api/work_date.py`
  - 业务日期设置与清理 API
- `api/reimbursement.py`
  - 从采购发票创建报销单 API
- `utils/purchase_tax_bridge.py`
  - 发票类型 + VAT 税桥接逻辑
- `utils/reimbursement.py`
  - 报销金额汇总、付款状态、来源映射
- `utils/text_normalization.py`
  - 备注 / 标题 / 文本清洗规则集中管理
- `utils/biz_mode.py`
  - 业务模式标准值与历史值归并
- `permissions/restricted_docs.py`
  - 受限单据的 `permission_query_conditions` / `has_permission`
- `services/restriction_service.py`
  - 受限访问的服务层逻辑
- `setup/roles.py`
  - 全局覆盖角色初始化
- `doctype_handlers/procurement_docs.py`
  - 采购四单保存前校验、继承、规范化胶水层

### 关键前端文件
- `public/js/work_date_manager.js`
- `public/js/procurement_grid_settings.js`
- `public/js/procurement_controller.js`
- `public/js/restricted_doc_actions.js`
- `public/js/restricted_access_group_form.js`

### 新增 / 重构的核心 DocType
- `Reimbursement Request`
- `Reimbursement Invoice Item`
- `Restricted Access Group`
- `Restricted Access Group User`
- `Restricted Access Group Role`

---

## 7. 配置边界：哪些通过 WebUI，哪些通过代码

## 应该通过 WebUI 配置的内容
- Restricted Access Group
- 组内用户 / 角色成员
- 哪张单据属于哪个受限组
- 哪些用户拥有 `Restricted Document Super Viewer`
- 临时 Share
- 日常业务日期使用
- 明细列宽偏好

## 应该通过代码维护的内容
- 业务模式标准值
- 发票类型与 VAT 桥接规则
- 报销生成逻辑
- 下游受限继承规则
- 权限判定顺序
- 文本清洗 / 统一规范

也就是：

**组织和配置在 UI，稳定规则在代码。**

---

## 8. 当前范围与未完成项

当前已经完成的是 v1 主体能力，但仍有一些后续可继续增强的点。

### 已完成
- 默认业务日期
- 明细列宽自定义
- 业务模式统一
- 发票类型 + VAT 基本规则
- 报销单基础主路径
- 受限单据方案 C
- Restricted Access Group 中文友好表单

### 后续可继续增强
- 报销更多辅助动作（如历史导入 / 更完整付款联动）
- 与 `Payment Entry` 的更深层联动
- 更多报表与分析视图
- 更多单据类型接入受限体系

---

## 9. 推荐阅读顺序

如果你是：

### 业务负责人 / 管理员
建议先看：
1. 本文第 4 节：用户应该怎么操作
2. 本文第 5 节：改造后系统具备哪些特性
3. 本文第 7 节：配置边界

### 开发 / 运维
建议再继续看：
1. 本文第 6 节：技术实现
2. `docs/plans/2026-04-22-phase2-default-date-and-grid-width.md`
3. `docs/plans/2026-04-22-phase3-invoice-type-vat-and-reimbursement.md`
4. `docs/plans/2026-04-22-phase4c-restricted-doc-final-architecture.md`

---

## 10. 一句话总结

这次 ERPNext16 改造的核心成果是：

**在保留 ERPNext 标准采购骨架的前提下，把中国式采购录入、业务日期、发票类型 VAT 规则、报销主路径、受限单据权限体系，以及日常 WebUI 配置体验，整体补齐到了可实际落地使用的程度。**

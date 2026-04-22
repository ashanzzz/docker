# ERPNext16 定制开发统一规范（Ashan / Hermes 标准）

> **Status:** 生效中的统一规范。后续本仓库内 ERPNext16 的 custom app 设计、文档、字段、DocType JSON、JS、权限和测试，都应优先参照本规范。
>
> **Applies to:**
> - `erpnext16/custom-apps/ashan_cn_procurement/`
> - `erpnext16/docs/guides/`
> - `erpnext16/docs/plans/`
> - 后续同仓库中的 ERPNext16 中国式业务定制

**Goal:** 把 ERPNext16 的定制开发方式统一下来，避免后续每做一个功能就重新发明结构、重新争论字段命名、布局命名、权限写法、测试方式和文档组织方式。以后只要属于这套 ERPNext16 定制，都默认先看这份规范，再写实现。

**Core Principle:** **配置在 UI，规则在代码；标准能力优先，定制边界清晰；字段、布局、权限、测试、文档必须同一套口径。**

---

## 一、适用边界

本规范主要约束以下类型的工作：
- 中国式采购 / 报销 / 月结补录 / 电汇申请
- 受限单据可见性
- 油卡 / 车辆 / 充值 / 加油 / 开票类业务域
- ERPNext16 标准单据上的扩展字段
- 自定义 DocType / Child Table / 表单 JS / 服务层逻辑 / 报表设计

不属于本规范直接覆盖的部分：
- Docker 镜像构建细节
- Unraid 部署参数
- CI/CD 工作流本身
- 与 ERPNext16 无关的通用脚本

---

## 二、总设计原则

### 1. 标准能力优先，定制能力补缝
优先复用 ERPNext / Frappe 标准对象：
- 采购主链：`Material Request` / `Purchase Order` / `Purchase Receipt` / `Purchase Invoice`
- 付款：`Payment Entry`
- 车辆：`Vehicle`
- 员工：`Employee`
- 供应商：`Supplier`

只有当标准对象不能清晰表达业务入口时，才新增 custom DocType。

### 2. 配置在 UI，规则在代码
放在 WebUI 的内容：
- 组、成员、角色归属
- 单据字段值
- 业务日期
- 列宽偏好
- 日常维护型主数据

放在代码的内容：
- 校验规则
- 计算逻辑
- 权限继承逻辑
- 单据间同步逻辑
- 文本清洗规范
- 状态机 / 汇总逻辑

### 3. 稳定规则归服务层，界面交互归表单层
- `DocType JSON`：字段结构、只读、必填、布局骨架
- `Python DocType class`：服务端 validate / submit / cancel 生命周期
- `utils/`：纯计算、纯文本、纯口径函数
- `services/`：跨 DocType、跨查询、同步、权限归集逻辑
- `public/js/` 或 doctype JS：表单体验、按钮、提醒、前端联动

### 4. 一切都必须可维护
禁止：
- 把核心规则散在 JS、Server Script、手工改 DB、临时补丁里
- 让同一业务规则在 3 个地方重复实现
- 为了快而直接改 ERPNext 标准源码

---

## 三、目录与文件组织规范

## 1. 推荐目录职责
- `ashan_cn_procurement/doctype/`：主业务 DocType / Child Table
- `ashan_cn_procurement/utils/`：纯函数，不依赖业务上下文副作用
- `ashan_cn_procurement/services/`：跨单据同步、权限汇总、聚合计算
- `ashan_cn_procurement/api/`：明确暴露给前端或外部调用的接口
- `ashan_cn_procurement/setup/`：custom fields / roles / property setters
- `ashan_cn_procurement/permissions/`：权限查询与 has_permission
- `ashan_cn_procurement/public/js/`：跨标准 DocType 复用 JS
- `tests/`：Python 单元测试
- `tests_js/`：Node 原生测试（`node --test`）

## 2. 什么时候新增 DocType
满足以下任一情况才新增：
- 它是清晰的业务入口
- 它有独立生命周期和状态
- 它不能自然塞进标准单据而不变得混乱
- 它未来需要独立报表 / 权限 / 工作台入口

### 典型例子
应该独立建 DocType：
- `Reimbursement Request`
- `Restricted Access Group`
- `Oil Card`
- `Oil Card Recharge`
- `Oil Card Refuel Log`
- `Oil Card Invoice Batch`

不应该为了“方便”独立建新主档：
- 已有标准 `Vehicle` 时再建一套车辆档案
- 已有标准 `Purchase Invoice` 时再建一套油票发票主档

---

## 四、字段规范

## 1. 字段命名
### 主规则
- 语义直白，不做过度缩写
- 主表字段优先用完整业务名
- 标准 DocType 上的扩展字段统一 `custom_` 前缀
- 自定义 DocType 自己的字段不加 `custom_`

### 示例
- 标准表扩展：`custom_biz_mode`, `custom_invoice_type`, `custom_default_oil_card`
- 自定义表字段：`oil_card`, `posting_date`, `invoiceable_basis_amount`

## 2. 标签语言
- 面向用户的标签统一中文
- 内部 fieldname 统一英文 snake_case
- 备注 / 提示 / 帮助文本优先中文，直白可操作

## 3. 计算字段口径必须分清
金额字段至少区分：
- `amount`：真实发生金额
- `effective_amount`：实际入卡金额
- `invoiceable_basis_amount`：可开票金额
- `allocated_discount_amount`：优惠分摊金额
- `current_balance`：当前余额
- `uninvoiced_amount`：未开票金额

禁止把“余额”“未开票金额”“实际发生金额”混成一个字段解释。

## 4. `fetch_from` / 快照字段
- 需要长期展示、列表显示、历史留痕时，可保留快照字段
- `Link` 是主语义字段，`Data` 快照只是辅助展示

### 示例
- `employee` 是主字段
- `employee_name` 是快照
- `department` 是统计辅助字段

---

## 五、DocType JSON 规范

## 1. 元数据默认要求
大多数自定义 DocType 应明确设置：
- `module`
- `document_type`
- `autoname`
- `title_field`
- `search_fields`
- `quick_entry`
- `track_changes`

默认建议：
- 交易类 DocType：`quick_entry = 0`
- 有明显标题语义的主表：必须设 `title_field`
- 重要业务单据：`track_changes = 1`

## 2. 布局字段命名统一
- `sb_*` → `Section Break`
- `cb_*` → `Column Break`
- `tb_*` → `Tab Break`
- `*_html` → `HTML`

禁止使用：
- `section_break_1`
- `column_break_2`
- `html_1`

## 3. 布局原则
- 一屏优先录当前业务
- 两栏用于“录入 + 对照”
- 只读结果靠右
- 完整历史跳报表，不塞主表
- HTML 只用于提示与摘要，不做半个页面

## 4. 只读 / 必填 / 显示逻辑优先写进 JSON
优先放进 JSON / custom field 定义：
- `read_only`
- `reqd`
- `in_list_view`
- `in_standard_filter`
- `fetch_from`
- `depends_on`
- `mandatory_depends_on`

不要把这些本可结构化声明的东西全部交给 JS 临时处理。

---

## 六、标准 DocType 扩展规范

## 1. `custom_fields.py` 是标准表扩展唯一入口
所有标准 DocType 的 custom fields，统一通过：
- `ashan_cn_procurement/setup/custom_fields.py`

不要：
- 手工在站点 Customize Form 里配完就算了
- 同一批字段一半写代码、一半靠人工点 UI

## 2. 标准表扩展必须“整块插入”
对于一组强相关字段：
- 用 `Section Break` 包起来
- 连续插入
- 不要把一组字段打散到标准字段各处

### 示例
`Vehicle` 的油卡信息区：
- `custom_oil_card_section`
- `custom_vehicle_note`
- `custom_default_oil_card`
- `custom_oil_card_cb`
- `custom_last_refuel_date`
- `custom_last_refuel_liters`
- `custom_last_refuel_amount`
- `custom_last_refuel_odometer`

## 3. 标准单据上的规则要尽量少而稳
- 标准表上只放真正必要字段
- 重计算、聚合、复杂状态不要全部压到标准单据上
- 复杂业务域优先单独建 custom DocType

---

## 七、Python 逻辑分层规范

## 1. `utils/` 只写纯函数
适合放到 `utils/` 的内容：
- 金额计算
- 状态推导
- 文本清洗
- 比例换算
- 命名常量

要求：
- 尽量无副作用
- 不直接依赖 UI
- 尽量不直接依赖 `frappe.db`
- 单元测试优先覆盖这里

## 2. `services/` 处理跨单据同步
适合放到 `services/` 的内容：
- 汇总某张油卡余额
- 同步限制字段
- 更新车辆最近加油信息
- 处理跨单据聚合与回写

要求：
- 允许依赖 `frappe`
- 要保持职责边界清晰
- 不把展示层逻辑塞进服务层

## 3. DocType class 只承接生命周期
DocType class 负责：
- `validate`
- `before_save`
- `on_submit`
- `on_cancel`

DocType class 不负责：
- 大段业务计算实现细节
- 到处拷贝粘贴的文本处理
- 重复查询逻辑

正确做法：
- DocType class 调用 `utils/` 和 `services/`

---

## 八、JS 规范

## 1. 哪些逻辑适合 JS
适合前端 JS 的内容：
- 自定义按钮
- 表单提示
- 即时联动
- 只影响录入体验的非关键显示逻辑

不适合只放前端的内容：
- 关键金额计算
- 关键权限控制
- 核心状态判断
- 提交后必须一致的数据同步

## 2. JS 模块化要求
- 可复用逻辑优先抽到 `public/js/*.js`
- 单 DocType 的专用交互可放 doctype 同目录 JS
- 能被 Node 测试的函数尽量导出

## 3. JS 文案要求
按钮和提示语必须：
- 中文
- 动词直白
- 一看就知道点击后去哪儿

例如：
- `查看来源采购发票`
- `发起开票批次`
- `查看本车历史加油`

---

## 九、权限规范

## 1. 受限单据架构固定
当前固定采用：
**`Restricted Access Group + 标准 Role/Profile 覆盖 + 标准 Share + root 继承，无 bundle`**

除非用户明确改架构，否则后续相关实现全部沿用这一套。

## 2. 权限校验必须双层
对于受限单据：
- `permission_query_conditions`
- `has_permission`

两者都要有。

## 3. 权限字段命名统一
- `custom_is_restricted_doc`
- `custom_restriction_group`
- `custom_restriction_root_doctype`
- `custom_restriction_root_name`
- `custom_restriction_note`

禁止今后又发明一套同义字段名。

---

## 十、测试规范

## 1. 默认测试命令
Python：
```bash
python3 -m unittest discover -s tests -q
```

JavaScript：
```bash
node --test tests_js/*.test.cjs
```

## 2. 新功能必须至少满足一类测试
### 纯逻辑功能
必须有 Python 单测：
- 金额计算
- 状态计算
- 文本清洗
- 规则函数

### 元数据/字段结构变更
至少有一类测试：
- custom field 生成测试
- DocType JSON 元数据测试
- 字段顺序 / 字段属性测试

### JS 交互逻辑
能抽纯函数的必须做 Node 测试。

## 3. TDD 默认生效
对于功能实现：
- 先写失败测试
- 看它失败
- 再写实现
- 再跑全量回归

如果只是纯文档改动，可不要求 TDD。

---

## 十一、文档规范

## 1. 文档分层固定
后续优先沿用这 5 层：
1. 研究稿：为什么这么设计
2. 实施计划：对象、流程、报表、工作台
3. 字段清单：字段级定义
4. 表单布局稿：UI 布局与交互
5. JSON 顺序稿：`field_order` / `insert_after` / `depends_on`

## 2. 规范文档是第 0 层约束
像本文件这种“统一规范”，优先级高于单个功能文档。
如果某个功能文档与本规范冲突：
- 要么修改功能文档
- 要么明确修订本规范并记录原因

## 3. 每次设计演进必须写变更记录
至少说明：
1. 改了什么
2. 为什么原设计不够用
3. 影响哪些字段 / 流程 / 报表 / 权限 / 迁移

---

## 十二、提交与落地规范

## 1. 提交粒度
优先按以下粒度提交：
- 规范文档
- 字段 / DocType 元数据
- 纯逻辑层
- 表单 JS
- 权限 / 服务层
- 部署 / migrate / 验证

## 2. 提交信息
统一用 Conventional Commit 风格：
- `docs(erpnext16): ...`
- `feat(ashan_cn_procurement): ...`
- `test(ashan_cn_procurement): ...`
- `refactor(ashan_cn_procurement): ...`

## 3. 落地顺序
用户已明确偏好：
1. 先在 custom app 中实现
2. 先在当前运行中的 ERPNext16 测试实例验证
3. 证明可行后，再进入镜像固化

---

## 十三、后续默认执行规则

从现在开始，凡是我继续写这套 ERPNext16 定制，默认采用：
- 本规范做总约束
- 本仓库中的功能计划文档做具体业务边界
- `custom_fields.py + DocType JSON + utils + services + tests` 作为标准落地骨架

如果没有特别说明，后续不再重新发明：
- 字段命名规则
- 布局命名规则
- 权限字段规则
- 目录职责
- 测试方式
- 文档分层

---

## 一句话结论

**以后这套 ERPNext16 的定制开发，不再是“想到哪写到哪”，而是统一按这份规范来：标准优先、边界清晰、字段统一、JSON 统一、逻辑分层、权限固定、测试先行、文档同步。后面的油卡、报销、采购、受限单据，都默认在这个规范下继续落地。**

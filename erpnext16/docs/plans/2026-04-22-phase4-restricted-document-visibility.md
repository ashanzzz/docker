# 受限单据可见性 Implementation Plan

> **Superseded for v1 by:** `docs/plans/2026-04-22-phase4b-restricted-document-minimal-erpnext-native.md`
> 
> 当前这个文档保留为“较重的扩展版思路”。如果目标是**尽量贴合 ERPNext 原生逻辑、尽量少改东西**，应优先采用 phase4b 的轻量方案。

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** 将业务模式收敛为 4 个标准值，并为采购/报销链路增加“受限单据”能力，使被标记的单据及其关联单据只能被授权用户看到。

**Architecture:** 业务模式采用统一枚举 + 旧值映射迁移。单据权限不直接靠“私密”语义，而采用“受限单据”语义：在根单据上选择一个“受限单据组”，系统生成一个权限 bundle，所有下游关联单据继承同一个 bundle；访问权限由 `bundle + 受限单据组 + ERPNext 角色覆盖 + 显式例外用户` 共同决定，列表过滤、直接打开、Link 搜索都按同一套校验逻辑执行。

**Tech Stack:** ERPNext 16, Frappe 16, custom app `ashan_cn_procurement`

---

## 一、已确认的业务决定

### 1) `custom_biz_mode` 只保留 4 个值
- `采购申请`
- `报销申请`
- `电汇申请`
- `月结补录`

### 2) 旧值兼容映射
为避免历史单据失效，旧值在 migrate / validate 时统一映射：

- `常规采购` → `采购申请`
- `直接采购` → `采购申请`
- `员工代付` → `报销申请`
- `无发票现金支付` → `报销申请`
- `其他账户支付` → `报销申请`
- `自办电汇` → `电汇申请`

### 3) 名称建议
不建议叫“私密单据”，因为这会让人误解成加密或绝对不可见。

**推荐名称：`受限单据`**

含义更准确：
- 不是“谁都不能看”
- 而是“只有被授权的人能看”

### 4) 分层授权建议
这一块建议直接做成三层，不要只做“单个用户名单”：

1. **受限单据组**：业务上谁是一组，谁能看这一类受限单据
2. **ERPNext 角色 / Role Profile**：如 `总经理`、`采购经理`、`财务经理`
3. **例外授权用户**：个别不在组里但需要额外查看的人

其中：
- `总经理` 这种高权限岗位，不建议每次手工加到每个组里
- 推荐作为 **全局覆盖角色**，默认可查看所有受限单据
- `经理` 这类角色，则按具体受限单据组决定是否能看

### 5) ERPNext“职位”怎么用
如果你系统里已经有人事主数据（例如 Employee 里的职位/岗位）：
- **职位/岗位字段可以作为分配角色的来源**
- **真正用于权限判断的，仍然应该是 ERPNext Role / Role Profile**

原因：
- `职位` 更像 HR 信息
- `Role` / `Role Profile` 才是 Frappe/ERPNext 原生权限机制
- 这样权限实现更稳，也更容易和 `has_permission` / `permission_query_conditions` 打通

---

## 二、范围定义

### 受限能力第一批覆盖的单据
1. `Material Request`（采购申请）
2. `Purchase Order`
3. `Purchase Receipt`
4. `Purchase Invoice`
5. `Reimbursement Request`
6. `Payment Entry`（如果后续报销/付款打通，这个也要纳入）

### 关联传播原则
如果根单据是受限单据，则它创建出来的关联单据默认也必须受限，并继承同一套授权名单。

例如：
- 采购申请受限 → 采购订单受限 → 入库单受限 → 发票受限
- 报销申请受限 → 相关发票/付款单也受限
- 采购发票受限 → 由其创建的报销单也受限

---

## 三、推荐的数据模型

## 方案结论
**不要只在每张单据上各自存一份授权名单。**

推荐用“权限 bundle（权限包）”做中心模型。

原因：
- 一个采购链路会生成多张关联单据
- 如果每张单据各管各的，后续很容易授权不一致
- bundle 可以保证整条链路权限统一

### A. 每张业务单据上的字段
以下字段加到受控范围内的父单据上：

- `custom_is_restricted_doc`（Check）
  - 标签：`受限单据`
- `custom_restriction_bundle`（Link / Data）
  - 标签：`权限包`
  - 存 bundle id 或 link 到权限包 DocType
- `custom_restriction_group`（Link）
  - 标签：`受限单据组`
  - 指向 `Restricted Document Group`
- `custom_restriction_root_doctype`（Data）
  - 标签：`权限源单据类型`
- `custom_restriction_root_name`（Dynamic Link / Data）
  - 标签：`权限源单据`
- `custom_restriction_note`（Small Text，可选）
  - 标签：`受限说明`

其中：
- 根单据：可以选择 `受限单据组`，并维护例外授权
- 下游单据：这些字段只读，由系统继承

### B. 新建中心权限 DocType
#### 1) `Restricted Document Group`
这是“谁是一组”的业务权限对象，建议字段：
- `group_name`
- `is_active`
- `description`
- `allow_global_manager_roles`（Check）
- `members`（子表，显式用户）
- `roles`（子表，ERPNext 角色）

#### 2) 子表：`Restricted Document Group User`
建议字段：
- `user`（Link -> User）
- `group_access_level`（Select: `viewer`, `editor`, `manager`）

#### 3) 子表：`Restricted Document Group Role`
建议字段：
- `role`（Link -> Role）
- `group_access_level`（Select: `viewer`, `editor`, `manager`）

#### 4) `Restricted Document Bundle`
bundle 仍然保留，但它不再只存用户名单，而是负责绑定“这条业务链属于哪个受限单据组”。建议字段：
- `bundle_id`
- `root_doctype`
- `root_docname`
- `restriction_group`
- `is_active`
- `note`
- `authorized_users`（子表，例外授权用户）

#### 5) 子表：`Restricted Document Bundle User`
建议字段：
- `user`（Link -> User）
- `access_level`（Select: `viewer`, `editor`, `manager`）
- `allow_print`（Check，可后加）
- `allow_export`（Check，可后加）

### C. 为什么要“组 + 角色 + 例外用户”三层
推荐的访问判定顺序：
1. 用户是否命中全局覆盖角色（如 `System Manager`、`Restricted Document Manager`、`总经理`）
2. 用户是否在 `Restricted Document Group.members` 里
3. 用户是否拥有 `Restricted Document Group.roles` 中任一角色
4. 用户是否在 bundle 的 `authorized_users` 例外名单里
5. 否则拒绝访问

这样设计的好处：
- 受限单据组满足“组内谁能看”
- ERPNext 角色满足“总经理/经理等岗位自动带权限”
- 例外授权用户满足个别临时查看需求
- bundle 继续负责整条业务链继承，不会权限漂移

### D. 为什么不用 DocShare 直接做主模型
DocShare 可以辅助，但不适合做唯一真源：
- 它是“单张单据级”分享，不天然适合整条链路
- 关联单据继承会很麻烦
- 多单据同步撤销授权不方便

**推荐做法：**
- `Restricted Document Group + Bundle` 是真源
- `Role` / `Role Profile` 是标准权限补充来源
- 如有需要，DocShare 只是从 bundle 同步出来的派生结果，不作为主判断依据

---

## 四、权限规则

### 1) 谁默认有权限
默认拥有查看权限的用户：
- `System Manager`
- 新增角色：`Restricted Document Manager`（建议增加）
- 全局覆盖角色：如 `总经理`
- 受限单据组里的显式成员用户
- 命中受限单据组角色表的用户（例如 `采购经理`、`财务经理`）
- 根单据 owner / creator
- bundle 子表里显式列出的例外用户

### 2) 谁没有权限
不在上述名单里的用户：
- 列表页看不到
- 全局搜索搜不到
- Link 字段搜索不到
- 即使拿到 URL / 单号，直接打开也报无权限
- 看不到关联单据计数和跳转入口

### 3) 关于“职位 / 岗位”的建议
- 如果你的人事体系里有 `总经理`、`经理` 等岗位，**不要直接拿 Employee.designation 当最终权限判断**
- 推荐做法是：
  - `职位/岗位` → 同步到 `Role Profile`
  - `Role Profile` → 赋予 ERPNext `Role`
  - 权限引擎最终读取 `Role`

例如：
- `总经理` Role Profile -> 含 `General Manager` / `Restricted Document Super Viewer`
- `采购经理` Role Profile -> 含 `Purchase Manager`
- `财务经理` Role Profile -> 含 `Accounts Manager`

这样职位管理和权限管理可以关联，但不会耦死在 HR 字段上。

### 4) 权限判断必须做两层
#### 第一层：列表/报表过滤
用 `permission_query_conditions`。

作用：
- 列表页直接过滤
- 报表/Link 搜索时减少泄露

#### 第二层：单据打开校验
用 `has_permission(doc, user, permission_type)`。

作用：
- 防止用户通过直接 URL、REST API、手填单号绕过列表过滤

**两层都要做，缺一不可。**

---

## 五、继承与传播规则

### 1) 根单据创建时
如果用户勾选 `受限单据`：
- 必须选择一个 `受限单据组`
- 创建一个 `Restricted Document Bundle`
- bundle 自动记录所选 `restriction_group`
- 自动把 owner/creator 加入 bundle 的例外名单（避免新建人把自己锁在外面）
- 如果该组启用了“全局管理角色可见”，则 `总经理` / `Restricted Document Manager` 这类角色自动生效，不需要逐个加用户
- 自动写回：
  - `custom_is_restricted_doc = 1`
  - `custom_restriction_bundle = bundle_id`
  - `custom_restriction_group = restriction_group`
  - `custom_restriction_root_doctype = 当前doctype`
  - `custom_restriction_root_name = 当前name`

### 2) 从根单据生成下游单据时
如果来源单据已有 bundle：
- 新单据自动继承：
  - `custom_is_restricted_doc = 1`
  - 相同 `custom_restriction_bundle`
  - 相同 `custom_restriction_group`
  - 相同 root 信息

### 3) 多来源合并规则
如果一个目标单据来自多个来源单据：
- 若多个来源都未受限：允许
- 若多个来源都受限且 bundle 相同：允许
- 若多个来源 bundle 不同：**禁止合并创建**，提示用户先统一权限范围

这个规则必须明确，否则权限边界会混乱。

### 4) 取消受限的规则
v1 建议保守：
- 如果根单据还没有生成任何下游单据，可以解除受限
- 一旦已经生成下游单据，普通用户不可直接取消
- 只能由 `Restricted Document Manager` 执行“整链解除/重建权限”动作

这样可以避免“上游不受限、下游还受限”或相反的脏状态。

---

## 六、界面设计

### 根单据界面
在采购申请 / 报销申请等入口单据上增加区域：
- `受限单据` 复选框
- `受限单据组`
- `例外授权用户` 子表
- `受限说明`
- `查看权限包` 按钮
- `查看受限单据组` 按钮

### 下游单据界面
显示但只读：
- `受限单据`
- `受限单据组`
- `权限源单据`
- `权限包`
- `查看权限源` 按钮

### 操作体验
- 用户在根单据上优先选择 `受限单据组`
- 例外授权用户只处理少数临时情况，不作为主授权方式
- 下游单据不允许自行改授权名单
- 所有权限改动都回到根单据 / 受限单据组 / 权限包去改

这能保证“谁是权限源头、谁是默认可见人群、谁是例外授权”都很清楚。

---

## 七、实现文件建议

### Task 1: 业务模式统一枚举与旧值迁移

**Objective:** 统一 `custom_biz_mode` 的值域，并把历史值迁移到新标准值。

**Files:**
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/utils/biz_mode.py`
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/setup/custom_fields.py`
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/utils/reimbursement.py`
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype_handlers/procurement_docs.py`
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/patches/v0_0_2/normalize_biz_modes.py`
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/patches.txt`
- Test: `custom-apps/ashan_cn_procurement/tests/test_biz_mode.py`

### Task 2: 新建受限单据组与权限包 DocType

**Objective:** 建立“受限单据组 + 权限包”的双层权限源头。

**Files:**
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_group/restricted_document_group.json`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_group/restricted_document_group.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_group_user/restricted_document_group_user.json`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_group_user/restricted_document_group_user.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_group_role/restricted_document_group_role.json`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_group_role/restricted_document_group_role.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_bundle/restricted_document_bundle.json`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_bundle/restricted_document_bundle.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_bundle_user/restricted_document_bundle_user.json`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/restricted_document_bundle_user/restricted_document_bundle_user.py`

### Task 3: 给受控业务单据加受限字段

**Objective:** 让采购/报销链路上的业务单据都能挂到权限包上。

**Files:**
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/setup/custom_fields.py`
- Test: `custom-apps/ashan_cn_procurement/tests/test_custom_fields.py`

建议新增字段：
- `custom_is_restricted_doc`
- `custom_restriction_bundle`
- `custom_restriction_group`
- `custom_restriction_root_doctype`
- `custom_restriction_root_name`
- `custom_restriction_note`

### Task 4: 写权限核心服务

**Objective:** 统一创建 bundle、继承 bundle、校验 bundle。

**Files:**
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/utils/restricted_docs.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/api/restricted_docs.py`
- Test: `custom-apps/ashan_cn_procurement/tests/test_restricted_docs.py`

核心函数建议：
- `ensure_restriction_bundle(doc)`
- `resolve_restriction_group_access(doc, user)`
- `user_has_global_restricted_access(user)`
- `inherit_restriction_from_source(target_doc, source_doc)`
- `validate_restriction_merge(source_docs)`
- `user_can_read_restricted_doc(doc, user)`

### Task 5: 接入 Frappe 权限钩子

**Objective:** 让列表、Link 搜索、直接打开全部按 bundle 限制。

**Files:**
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/hooks.py`
- Create/Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/permissions.py`
- Test: `custom-apps/ashan_cn_procurement/tests/test_restricted_permissions.py`

需要接入：
- `permission_query_conditions`
- `has_permission`
- 必要时补 `doc_events` 做继承/同步

### Task 6: 在单据创建链路里自动继承权限

**Objective:** 上游受限，下游自动受限。

**Files:**
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/api/reimbursement.py`
- Modify: 采购申请 → 采购订单 → 入库 → 发票 的相关创建入口（按当前实际入口逐个接）
- Test: `custom-apps/ashan_cn_procurement/tests/test_restricted_inheritance.py`

### Task 7: 前端界面与用户体验

**Objective:** 让用户能在根单据选择受限单据组、维护例外授权用户，并在下游单据看见权限来源。

**Files:**
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/public/js/procurement_controller.js`
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/doctype/reimbursement_request/reimbursement_request.js`
- Test: `custom-apps/ashan_cn_procurement/tests_js/restricted_docs.test.cjs`

---

## 八、验收标准

### 业务模式
- 所有新单据 `custom_biz_mode` 只能选择 4 个值
- 历史旧值 migrate 后被自动归一化
- 旧逻辑创建出的报销单不会再带入旧值

### 受限单据
- 未授权用户在列表页看不到受限单据
- 未授权用户不能通过 URL 直接打开受限单据
- 未授权用户不能在 Link 搜索里搜到受限单据
- 受限根单据创建的下游单据自动继承同一个权限包和受限单据组
- 多来源 bundle 或受限单据组不一致时禁止合并建单
- 受限单据组内成员可以正常查看整条链路
- 命中组内角色的用户（如经理类角色）可以按组规则查看
- `总经理` 这类全局覆盖角色默认可以查看所有受限单据

---

## 九、v1 / v2 边界建议

### v1 必做
- 4 个业务模式统一
- 根单据受限开关
- 受限单据组
- 权限包 + 例外授权用户
- 总经理类全局覆盖角色
- 列表过滤 + 打开校验
- 采购/报销主链路自动继承

### v2 再做
- 部门维度授权
- 自动从职位同步 Role Profile
- 自动同步 DocShare
- 报表级脱敏
- 批量重建/解除整链权限

---

## 十、最终建议

这件事不要做成“单张单据的私密开关”，要做成：

**“受限单据组 + 权限包 + 角色覆盖”的整链权限体系。**

这样你后面不管是：
- 采购申请 → 订单 → 入库 → 发票
- 报销申请 → 发票 → 付款
- 发票 → 报销单

都能满足：
- 组内用户可见
- 经理类角色按组授权可见
- `总经理` 这类全局角色默认可见
- 整条链路权限不乱，维护成本也最低。

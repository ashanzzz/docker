# 受限单据最小改动方案（贴合 ERPNext 原生逻辑）

> **Superseded when maintainability is the top priority by:** `docs/plans/2026-04-22-phase4c-restricted-doc-final-architecture.md`
> 
> 当前文档是“最少改动优先”的轻量方案。如果目标升级为**长期维护优先、代码语义更干净、业务组与系统角色明确分离**，应优先采用 phase4c。

> **For Hermes:** 优先按这个版本实施；只有当标准 Role/Role Profile 无法满足业务时，才升级到更重的自定义权限模型。

**Goal:** 在尽量不偏离 ERPNext/Frappe 原生权限模型的前提下，实现“受限单据”能力，使指定单据及其关联单据只对特定角色/用户可见。

**Architecture:** 复用 ERPNext 原生 `Role`、`Role Profile`、`Owner`、`DocShare(Share)` 逻辑；仅补极少量自定义字段与权限钩子。`受限单据组` 在 v1 中直接用 **标准 Role** 承担，不额外新造复杂的权限包/bundle 模型。

**Tech Stack:** ERPNext 16, Frappe 16, custom app `ashan_cn_procurement`

---

## 一、核心原则

这次按你的要求，**尽量贴合 ERPNext 逻辑，尽量少改东西**。

所以 v1 我建议：

1. **不用复杂 bundle 模型**
2. **不新造一套独立权限系统**
3. **直接复用 ERPNext 的 Role / Role Profile / Share**
4. 只在标准单据上加几个字段 + 权限钩子

一句话：

**受限单据 = 标准单据 + 一个“受限角色”字段 + 原生角色权限判断。**

---

## 二、把“受限单据组”直接映射成 ERPNext Role

### 推荐做法
你说的“受限单据组”，在 v1 里直接用 ERPNext `Role` 表示。

例如新增这些 Role：

- `Restricted Procurement Group`
- `Restricted Finance Group`
- `Restricted Executive Group`
- `Restricted Project A Group`

然后每张受限单据只需要指定：

- 这张单据属于哪个 `Role`

这样这个 Role 下的用户，就都能看。

### 为什么这样最贴合 ERPNext
因为 ERPNext/Frappe 原生就认：
- `Role`
- `Role Profile`
- `User`
- `Share`

如果我们自己再造一个“受限单据组 DocType”，其实已经比 ERPNext 原生多走了一层。

而直接复用 `Role`：
- 最少改动
- 最贴原生
- 管理后台也更统一
- 后续和岗位/职位映射最顺

---

## 三、总经理 / 经理 / 职位 怎么处理

### 1) 总经理
总经理不要每次手工加入每个受限组。

推荐单独新增一个全局 Role：

- `Restricted Document Super Viewer`

然后把总经理的 `Role Profile` 里带上这个角色。

效果就是：
- 总经理默认可看所有受限单据
- 不需要逐组配置

### 2) 经理
经理不要默认全看，而是按职责分组。

例如：
- `采购经理` → `Purchase Manager` + `Restricted Procurement Group`
- `财务经理` → `Accounts Manager` + `Restricted Finance Group`

这样：
- 采购经理只看采购受限组
- 财务经理只看财务受限组
- 不会权限过大

### 3) 职位 / 岗位
如果你系统里有人事岗位，例如：
- 总经理
- 采购经理
- 财务经理

**不要直接拿 Employee.designation 做最终权限判断。**

推荐链路是：

`职位/岗位` → `Role Profile` → `Role`

原因：
- `职位` 是 HR 信息
- `Role` 才是 ERPNext 原生权限对象
- 这样最符合 Frappe 权限体系

---

## 四、v1 不新增复杂 Doctype，只补最少字段

建议在这些单据上增加最少字段：

1. `Material Request`
2. `Purchase Order`
3. `Purchase Receipt`
4. `Purchase Invoice`
5. `Reimbursement Request`
6. （后续可扩）`Payment Entry`

### 字段建议
- `custom_is_restricted_doc`（Check）
  - 标签：`受限单据`
- `custom_restricted_role`（Link -> Role）
  - 标签：`受限单据组`
  - 实际上选的是一个 ERPNext Role
- `custom_restriction_root_doctype`（Data）
  - 标签：`权限源单据类型`
- `custom_restriction_root_name`（Dynamic Link / Data）
  - 标签：`权限源单据`
- `custom_restriction_note`（Small Text，可选）
  - 标签：`受限说明`

### 说明
这里最关键的是：

**`custom_restricted_role` 直接指向标准 `Role`**

这样就不需要：
- 自己做 group 表
- 自己做 group-user 子表
- 自己做 group-role 子表
- 自己做 bundle-user 表

---

## 五、权限判断逻辑（尽量复用原生）

如果单据 **不是受限单据**：
- 完全走 ERPNext 原生权限

如果单据 **是受限单据**：
- 在原生权限通过的前提下，再加一层限制判断

### 允许查看的人
以下任一满足即可查看：

1. `System Manager`
2. 单据 owner / 创建人
3. 拥有 `Restricted Document Super Viewer` 的用户
4. 拥有该单据 `custom_restricted_role` 的用户
5. 通过 ERPNext 原生 `Share` 显式分享过的用户

### 不允许查看的人
不满足上述条件的人：
- 列表页看不到
- Link 搜索搜不到
- 即使知道 URL，也打不开

---

## 六、例外授权尽量用 ERPNext 原生 Share

如果只是偶尔要让某个人临时看：

**不要再额外做一套“例外授权用户表”。**

直接用 ERPNext 原生：
- `Share`
- 底层就是 `DocShare`

这样更贴近原生逻辑。

### 适用场景
比如：
- 某张采购发票临时给出纳看
- 某张报销单临时给法务看
- 某张采购申请临时给老板助理看

这种情况直接 share 给 конкретный用户即可。

---

## 七、关联单据怎么继承

虽然不做 bundle，但整条链路还是要保持一致。

### 规则
如果根单据是受限单据：
- 下游单据自动继承 `custom_is_restricted_doc = 1`
- 自动继承同一个 `custom_restricted_role`
- 自动继承同一个 root 信息

### 例如
- 采购申请受限（角色 = `Restricted Procurement Group`）
  - 采购订单继承
  - 入库单继承
  - 发票继承
- 采购发票受限
  - 从它生成的报销单也继承同一个 `custom_restricted_role`

---

## 八、多来源合并规则

如果一个目标单据来自多个来源：

- 都不受限 → 允许
- 都受限且 `custom_restricted_role` 相同 → 允许
- `custom_restricted_role` 不同 → **禁止合并**

这已经足够，不需要引入额外 bundle id。

---

## 九、实现上需要的最少改动

### 1) Custom Field
在受控单据上加：
- `custom_is_restricted_doc`
- `custom_restricted_role`
- `custom_restriction_root_doctype`
- `custom_restriction_root_name`
- `custom_restriction_note`

### 2) hooks.py
增加：
- `permission_query_conditions`
- `has_permission`
- 必要的 `doc_events`

### 3) permissions.py
统一实现：
- `user_can_read_restricted_doc(doc, user)`
- `get_restricted_doc_query_conditions(user)`
- `user_has_role(user, role)`
- `user_has_super_restricted_access(user)`

### 4) 单据生成链路自动复制字段
在这些入口补最小继承逻辑：
- 采购申请 → 采购订单
- 采购订单 → 入库
- 入库 / 采购发票
- 采购发票 → 报销单

---

## 十、为什么这个方案比之前更适合你

因为你刚才强调的是：

- **尽量贴合 ERPNext 逻辑**
- **尽量少改东西**

那就应该优先：
- 用 `Role`
- 用 `Role Profile`
- 用 `Share`
- 用标准单据本身的 source/target 链路

而不是一上来就自造：
- group 表
- bundle 表
- 例外授权表
- 自定义权限中台

那样会更重，也更偏离 ERPNext。

---

## 十一、v1 / v2 边界

### v1 推荐
- 受限单据开关
- 受限角色字段（Link Role）
- 总经理全局可看角色
- 经理按分组角色可看
- Share 作为例外授权
- 主链路自动继承

### v2 才考虑
只有当后面发现 Role 数量太多、管理太痛苦，再升级为：
- 自定义 `Restricted Document Group` Doctype
- 更复杂的组成员管理
- 更复杂的批量授权/解除授权

也就是说：

**先按 ERPNext 原生做轻版，实在不够，再升级。**

---

## 十二、最终建议

我完全明白你的意思。

所以现在我推荐的最终方向不是“复杂权限包模型”，而是：

**`Role / Role Profile / Share + 少量自定义字段 + 权限钩子`**

这是当前最贴合 ERPNext、改动最少、也最容易长期维护的做法。

如果后面你确认就按这个逻辑走，我下一步就按这个最小改动版本开始落地。
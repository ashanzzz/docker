# 受限单据最终推荐架构（为“方便维护 + 代码干净精准可维护”而设计）

> **Status:** 用户已确认采用方案 C，作为当前 v1 实施基线。
>
> **For Hermes:** 如果用户要的是长期可维护性优先，这个文档应作为 v1 最终推荐基线。

**Goal:** 在 ERPNext 16 中实现受限单据能力，同时把维护成本、代码复杂度、权限模型混乱风险压到最低。

**Architecture:** 保留 ERPNext 标准采购/发票/付款链路；不把业务组直接硬塞进标准 Role，也不一上来做过重的 bundle 平台。采用 **一个轻量自定义主数据 + 标准 Role/Profile 覆盖 + 标准 Share 例外授权 + 根单据继承** 的折中方案。

**Tech Stack:** ERPNext 16, Frappe 16, custom app `ashan_cn_procurement`

---

## 一、先说结论

如果你的目标是：
- 方便维护
- 代码干净
- 逻辑精准
- 后面不容易越改越乱

那我认为：

### 1) “受限单据组直接等于 ERPNext Role” 不是最优解
虽然它最省事，但长期会把：
- 功能权限 Role
- 组织岗位 Role
- 单据可见性组

三种东西混在一起。

结果通常是：
- Role 越加越多
- Role Profile 越来越脏
- 很难看出某个 Role 到底是“能操作模块”，还是“能看某类受限单据”
- 后面维护者不敢动

所以：

**我认为“直接用 Role 代表每个受限单据组”这个思路，虽然省改动，但不够干净。**

### 2) “复杂 bundle 平台” 也不是 v1 最优解
如果一开始就上：
- 组
- bundle
- 组成员
- 组角色
- 例外用户
- 多张中心权限表

虽然表达力强，但 v1 会偏重：
- 代码量大
- 心智负担重
- 调试成本高
- 很容易出现“功能还没用起来，系统先复杂了”

所以：

**重型权限中台也不适合当前阶段。**

### 3) 最优解：轻量自定义组 + 标准角色覆盖 + 标准 Share 例外
这是我现在最推荐的方案。

---

## 二、推荐架构：三层，但只做一层自定义

### 第 1 层：自定义 `Restricted Access Group`
这是唯一建议新增的权限主数据。

它表达的不是系统功能权限，而是：

**“哪些人/哪些角色能看这一类受限业务单据。”**

这和 ERPNext 标准 Role 不同：
- Role 更偏系统能力
- Restricted Access Group 更偏业务可见范围

### 第 2 层：标准 `Role / Role Profile`
Role 继续做它最擅长的事：
- 总经理
- 采购经理
- 财务经理
- System Manager

它们不直接等于业务组，而是：
- 作为**全局覆盖**
- 或作为**组内允许角色**

### 第 3 层：标准 `Share`
如果只是临时例外：
- 某一张单据临时给某个用户看

直接用 ERPNext 原生 Share，**不要再造一套例外用户系统**。

---

## 三、为什么这个方案最适合“长期维护”

### 1) 业务语义和系统权限语义分离
这是最关键的一点。

#### 不推荐
- `Restricted Procurement Group` 这种直接做成 Role

因为它其实不是“系统权限”，而是“业务可见范围”。

#### 推荐
- `Restricted Access Group` 表达业务范围
- `Role` 表达岗位/系统能力

这样看代码、看后台配置、看权限问题时都更清楚。

---

### 2) 只新增一个核心自定义对象，复杂度可控
不是完全原生，但也不重。

新增：
- `Restricted Access Group`
- 最多两个很薄的子表

不新增：
- bundle 中台
- group/bundle 双中台联动
- 复杂同步系统
- 自定义 docshare 替代品

这会让代码体量和认知负担都保持在合理范围内。

---

### 3) 以后扩展不会推倒重来
现在做轻量组模型，后面如果要扩展：
- 部门自动带权限
- 按岗位自动入组
- 受限报表
- 更多单据类型接入

都能在这个模型上继续长。

如果今天直接把 Role 当组，后面通常会变成：
- 再造一层映射
- 再迁一次数据
- 再解释一次“为什么同一个 Role 不只是 Role”

不划算。

---

## 四、最终推荐数据模型

## A. 新增一个 DocType：`Restricted Access Group`
建议字段：
- `group_name`
- `is_active`
- `description`
- `allow_super_viewer`（Check）
- `user_members`（子表）
- `role_members`（子表）

### 子表 1：`Restricted Access Group User`
字段：
- `user`
- `access_level`（viewer / editor / manager）

### 子表 2：`Restricted Access Group Role`
字段：
- `role`
- `access_level`（viewer / editor / manager）

### 为什么保留 role_members
因为你明确有这类诉求：
- 总经理
- 经理

那么组里允许：
- 明确用户
- 明确角色

是最自然的。

---

## B. 业务单据只加最少字段
在这些单据上加字段：
- `Material Request`
- `Purchase Order`
- `Purchase Receipt`
- `Purchase Invoice`
- `Reimbursement Request`
- 后续可扩到 `Payment Entry`

### 字段
- `custom_is_restricted_doc`（Check）
- `custom_restriction_group`（Link -> Restricted Access Group）
- `custom_restriction_root_doctype`（Data）
- `custom_restriction_root_name`（Dynamic Link / Data）
- `custom_restriction_note`（Small Text）

### 刻意不加的字段
- 不加 `custom_restricted_role`
- 不加 bundle id
- 不加例外授权用户表

原因：
- `Role` 不应该成为业务组主键
- root 字段已经足够表达链路来源
- 例外授权用标准 Share 即可

---

## 五、权限规则怎么定最干净

如果单据 **不是受限单据**：
- 完全走 ERPNext 原生权限

如果单据 **是受限单据**：
- 在原生权限通过后，再做一层受限校验

### 允许访问的顺序
1. `System Manager`
2. 单据 owner / creator
3. 拥有全局覆盖 Role 的用户
   - 例如：`Restricted Document Super Viewer`
   - 对应总经理等全局查看者
4. 单据 `custom_restriction_group` 的显式用户成员
5. 用户拥有该组配置的任一 Role
   - 例如 `Purchase Manager`
   - 例如 `Accounts Manager`
6. 单据通过 ERPNext 原生 Share 分享给该用户
7. 其余拒绝

### 这里最重要的设计点
#### 总经理
- 不要加入每个组
- 给全局 Role：`Restricted Document Super Viewer`
- 永远默认可看所有受限单据

#### 经理
- 不默认全看
- 通过 `Restricted Access Group.role_members` 进入对应组

例如：
- 采购受限组允许 `Purchase Manager`
- 财务受限组允许 `Accounts Manager`

---

## 六、为什么不建议直接把“职位”作为最终判断条件

你的岗位体系当然很重要，但：

**岗位/职位不是最终权限检查对象。**

推荐链路：

`Employee.designation` → `Role Profile` → `Role` → 权限判断

原因：
- ERPNext/Frappe 原生权限就是围绕 Role 工作
- 用 designation 直接做最终判断，会把 HR 数据和权限逻辑绑死
- 后面调试“为什么他能看/不能看”会非常痛苦

所以岗位保留，但用来**派生角色**，不要直接做权限判定。

---

## 七、为什么不需要 bundle
我认真想过这个点。

### 结论
**当前阶段不需要单独 bundle。**

### 原因
你真正要解决的是：
- 一张根单据受限
- 它的下游单据继承同一套受限范围

这个目标只靠下面两个字段就够了：
- `custom_restriction_root_doctype`
- `custom_restriction_root_name`

再加：
- `custom_restriction_group`

已经能稳定表达：
- 这条链从哪张根单据来
- 这条链属于哪个受限组

### 什么时候才需要 bundle
只有当你后面出现这种需求：
- 一条业务链要脱离根单据单独改权限
- 根单据删了但权限链要保留
- 一条链可能跨多个 root 重组

那才值得上 bundle。

当前没必要。

---

## 八、链路继承怎么设计才干净

### 根单据创建时
如果勾选 `受限单据`：
- 必须选择 `custom_restriction_group`
- 自动写 root 为自己

### 下游创建时
如果来源单据已受限：
- 自动继承 `custom_is_restricted_doc = 1`
- 自动继承 `custom_restriction_group`
- 自动继承 root 信息

### 多来源合并规则
如果多个来源单据：
- 都不受限 → 允许
- 都受限且 group 相同 → 允许
- group 不同 → 禁止合并

这个规则简单、清晰、足够稳定。

---

## 九、代码怎么组织，才能真正“干净精准可维护”

这是我最想强调的部分。

## 1) 权限逻辑绝对不要散在 JS / Server Script / 多个 DocType 里
必须集中到一个服务模块。

### 推荐结构
- `ashan_cn_procurement/permissions/restricted_docs.py`
- `ashan_cn_procurement/services/restriction_service.py`
- `ashan_cn_procurement/setup/custom_fields.py`
- `ashan_cn_procurement/doctype_handlers/...` 只做 very thin glue

### 分工
#### `restriction_service.py`
只放纯业务逻辑：
- `is_restricted(doc)`
- `resolve_restriction_group(doc)`
- `user_can_access_restricted_doc(doc, user)`
- `inherit_restriction(target_doc, source_doc)`
- `validate_same_restriction_group(source_docs)`

#### `permissions/restricted_docs.py`
只放 Frappe 接口层：
- `has_permission`
- `permission_query_conditions`

#### `doctype_handlers`
只放调用，不放复杂判断。

---

## 2) 备注清洗 / 标题摘要 / 文本标准化必须单独模块化
你提到“备注清洗代码清晰”，这一点我非常赞同。

### 不要这样做
- 在 JS 里顺手清洗一点
- 在保存前 Python 再清洗一点
- 在报销生成时又拼接一点
- 最后 nobody knows 哪层才是真规则

### 推荐这样做
单独一个纯函数模块：
- `ashan_cn_procurement/utils/text_normalization.py`
  或
- `ashan_cn_procurement/utils/remark_normalizer.py`

只做：
- 去首尾空白
- 合并多余空格
- 统一换行
- 去掉纯噪音字符
- 限制长度
- 摘要标题生成

### 原则
- **文本清洗规则只有一份真源**
- 前端只做体验优化，不做最终规则
- 最终写库前统一走服务端 normalizer

这样以后你改备注规则，只改一个文件。

---

## 3) 常量集中，不要魔法字符串满天飞
例如：
- `Restricted Document Super Viewer`
- `custom_is_restricted_doc`
- `custom_restriction_group`
- `Purchase Manager`

这些都应该集中到：
- `ashan_cn_procurement/constants/restrictions.py`

避免以后改名字要全仓 grep。

---

## 4) 所有权限判断都必须可单测
至少要有：
- `test_restriction_service.py`
- `test_restricted_permissions.py`
- `test_restriction_inheritance.py`
- `test_text_normalization.py`

重点测：
- 总经理能看所有受限单据
- 采购经理只能看采购受限组
- 无组无角色无 share 的用户不能看
- 下游单据继承 group 成功
- 多来源 group 冲突时报错
- 备注清洗输出稳定

---

## 十、三种方案对比，我的最终判断

### 方案 A：Role 直接等于组
**优点：** 最省代码
**缺点：** 长期会脏
**结论：** 不推荐作为最终设计

### 方案 B：Group + Bundle + Exception 平台
**优点：** 最强表达力
**缺点：** v1 太重
**结论：** 现在不推荐

### 方案 C：Restricted Access Group + Role 覆盖 + Share 例外 + Root 继承
**优点：**
- 业务语义清楚
- 改动不大
- 代码容易收敛
- 后续好扩展
- 不污染 Role 体系

**结论：**
**这是我认为最适合你当前目标的方案。**

---

## 十一、最终建议

如果目标排序是：
1. 好维护
2. 代码干净
3. 逻辑精准
4. 尽量贴 ERPNext
5. 但不要为了“太原生”把未来搞乱

那我建议最终选：

**`Restricted Access Group + 标准 Role/Profile 覆盖 + 标准 Share + Root 继承，无 bundle。`**

这是我现在认为最平衡、最靠谱、最适合长期维护的架构。

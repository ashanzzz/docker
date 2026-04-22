# ERPNext16 默认业务日期与明细列宽配置实施计划

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** 让 ERPNext16 测试实例支持“设定业务日期后新单据默认带入该日期”，并让采购四单的明细表支持用户自定义列宽且不受 1-10 的静态表单配置限制。

**Architecture:** 业务日期采用 Frappe 用户默认值（`DefaultValue`）作为持久层，前端通过 app 级 JS 在所有表单上提供“设定/清除业务日期”入口，并在新单据空白日期字段上回填。明细列宽采用 Frappe 现有 `GridView` 用户设置机制，custom app 只补一个更直接的配置入口，并允许保存任意正整数宽度。

**Tech Stack:** Frappe/ERPNext 16, custom app hooks, whitelisted Python API, desk-side JavaScript, unittest, node syntax check.

---

### Task 1: 为业务日期默认值写 failing tests
**Objective:** 先锁定 server 侧默认值同步/清理规则。

**Files:**
- Create: `custom-apps/ashan_cn_procurement/tests/test_work_date_defaults.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/api/work_date.py`

**Checks:**
- `set_work_date()` 会同步写入 `ashan_work_date`、`posting_date`、`transaction_date`、`schedule_date`、`bill_date`
- `clear_work_date()` 会清理同一组 keys
- 非法日期会被拒绝

### Task 2: 实现业务日期 API + 全局表单入口
**Objective:** 在所有 Desk 表单上可设/清业务日期，并在新单据上回填空日期字段。

**Files:**
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/hooks.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/api/__init__.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/api/work_date.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/public/js/work_date_manager.js`

**Checks:**
- 表单操作菜单可见“设定业务日期/清除业务日期”
- 设置后新建单据的 `posting_date / transaction_date / bill_date / schedule_date` 空值自动带入
- 若存在 `set_posting_time` 字段，则自动勾上

### Task 3: 为采购四单的明细列宽配置写 failing coverage
**Objective:** 锁定列宽配置所依赖的纯逻辑，避免 JS 里出现 0/空值等坏输入。

**Files:**
- Create: `custom-apps/ashan_cn_procurement/tests/test_grid_column_settings.py`
- Create: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/utils/grid_columns.py`

**Checks:**
- 列宽必须为正整数
- 空值/非法值回退到默认宽度
- 字段顺序/字段名不会被意外破坏

### Task 4: 实现采购四单的“配置明细列宽”入口
**Objective:** 在采购申请/订单/收货/发票表单里，给 items 子表增加显式列宽配置按钮。

**Files:**
- Modify: `custom-apps/ashan_cn_procurement/ashan_cn_procurement/public/js/procurement_controller.js`
- Modify: `custom-apps/ashan_cn_procurement/README.md`

**Checks:**
- 可打开列宽配置对话框
- 保存后写入 `GridView` 用户设置
- 刷新后列宽保持
- 允许大于 10 的宽度值

### Task 5: 部署到运行中的测试实例并做 live 验证
**Objective:** 不只在本地代码通过，还要在正在运行的 ERPNext16 测试实例直接验证。

**Files:**
- Sync changed files into running `erpnext16` container
- Run `bench build --app ashan_cn_procurement`
- Run `bench --site site1.local migrate`
- Restart supervisor processes if needed

**Checks:**
- 单测通过
- JS 语法检查通过
- live UI 可设定业务日期
- 新建采购四单默认日期正确
- 采购申请/采购发票明细支持自定义列宽并持久化

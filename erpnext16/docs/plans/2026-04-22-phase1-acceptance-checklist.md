# ERPNext16 中国式采购 Custom App 第一阶段验收清单

> 目标：在**当前运行中的 ERPNext16 测试实例**上，把 `ashan_cn_procurement` 的第一阶段能力验收到“我自己满意、再交给用户点验”的程度。

## 范围

本轮只验这四个标准采购单据：

- Material Request
- Purchase Order
- Purchase Receipt
- Purchase Invoice

本轮不包含：

- 报销主单/子单正式迁移
- Payment Entry 与报销流联动
- 税率到 ERPNext 标准税务分录的完整映射

## 代码层验收

### A. 包结构与安装能力
- [ ] app Python 包可导入
- [ ] Frappe module package 可导入
- [ ] `after_install` / `after_migrate` 会执行自定义字段与属性设置

### B. 计算核心
- [ ] `net_rate` 模式计算正确
- [ ] `gross_rate` 模式计算正确
- [ ] `net_amount` 模式计算正确
- [ ] `gross_amount` 模式计算正确
- [ ] `0` 值不会被误判为空
- [ ] 非法输入（如 `qty <= 0`）能被拒绝

### C. UI/字段定义
- [ ] 四个子表都存在以下字段：
  - `custom_spec_model`
  - `custom_gross_rate`
  - `custom_tax_rate`
  - `custom_tax_amount`
  - `custom_gross_amount`
  - `custom_line_remark`
  - `custom_tax_basis`
- [ ] 四个父单都存在 `custom_biz_mode`
- [ ] 四个子表标准 `rate` 字段标签被显式改成 **不含税单价**

## Live 环境验收

### D. 当前测试站点安装状态
- [ ] 当前运行中的 `erpnext16` 已安装 `ashan_cn_procurement`
- [ ] `bench --site site1.local list-apps` 可见该 app
- [ ] `sites/apps.txt` 包含该 app

### E. Metadata 与显示
- [ ] 四个父单 metadata 可见 `custom_biz_mode`
- [ ] 四个子表 metadata 可见全部中国式字段
- [ ] Purchase Order 新建页面可见：
  - 不含税单价
  - 含税单价
  - 税率(%)
  - 税额
  - 价税合计

### F. 前端联动
- [ ] 录入：数量 + 不含税单价 + 税率，可自动推出含税侧
- [ ] 录入：数量 + 价税合计 + 税率，可自动反算不含税侧
- [ ] 浏览器控制台无新增 JS 错误

### G. 保存与服务端重算
- [ ] 至少能在 live 环境中创建并保存 1 张测试采购单据
- [ ] 保存后行项目字段与前端计算一致
- [ ] 刷新后字段值不丢失

## 当前已知前置条件

- 当前测试站点已确认存在 Company 与 Warehouse
- 上一轮 API 探测时：`Supplier=0`、`Item=0`
- 因此若要执行保存级验收，需要先补临时测试 Supplier / Item，或导入最小主数据

## 执行原则

1. 先跑代码层验收。
2. 再跑 live 验收。
3. 任一条不通过：
   - 先补 failing test（能写测试的先写测试）
   - 再修实现
   - 再重跑对应验收
4. 循环，直到整份清单达到“可交给用户点验”的状态。

## 本轮执行结果（2026-04-22）

### 已通过
- 代码层：
  - `test_line_math.py`
  - `test_procurement_docs.py`
  - `test_app_layout.py`
  - `test_property_setters.py`
  - 合计 `12` 个单测通过
- 语法层：
  - `python3 -m compileall -q .../ashan_cn_procurement`
  - `node --check .../procurement_controller.js`
- live 安装层：
  - 当前运行中的 `erpnext16` 已完成 app 同步、`migrate`、supervisor 进程重启
  - `bench --site site1.local list-apps` 已确认存在 `ashan_cn_procurement 0.1.0`
- live metadata：
  - 四个父单都存在 `custom_biz_mode`
  - 四个子表都存在中国式字段集合
  - 四个子表标准 `rate` 标签均已改为 **不含税单价**
- live 保存级验证：
  - 已成功通过 API 创建并保存：
    - `Material Request`：`MAT-MR-2026-00001`
    - `Purchase Order`：`PUR-ORD-2026-00001`
    - `Purchase Receipt`：`MAT-PRE-2026-00001`
    - `Purchase Invoice`：`ACC-PINV-2026-00001`
  - 保存时故意传入错误的 `custom_gross_amount=999`，服务端已自动重算为正确结果，说明保存前重算逻辑生效

### 验收过程中发现并确认的业务规则
- `Purchase Receipt` 在 `custom_biz_mode=常规采购` 且**无关联采购订单**时，会被站点现有 Server Script 拒绝保存：
  - `❌ 错误：无关联订单，不能选择【常规采购】。`
- 这不是本 custom app 新引入的 bug，而是当前站点既有业务规则。
- 因此 standalone 验收时，`Purchase Receipt` / `Purchase Invoice` 采用 `直接采购` 路径完成保存测试。

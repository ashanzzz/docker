# ashan_cn_procurement

`ashan_cn_procurement` 是 ERPNext16 的中国式采购 / 报销改造 custom app。

当前实现范围：

- 采购四单基础扩展：
  - Material Request
  - Purchase Order
  - Purchase Receipt
  - Purchase Invoice
- 行项目中国式字段：
  - 规格参数
  - 税率
  - 含税单价
  - 税额
  - 价税合计
  - 备注
- 含税 / 不含税四种录入模式的统一计算核心
- 前端联动脚本 + 服务端保存前重算
- 作为 ERPNext16 AIO 镜像内置 app 打包

暂未在这个提交里完成的内容：

- 报销主单 / 子单 DocType 正式迁移
- 行税率到 ERPNext 标准税务科目的完整映射
- Payment Entry 与报销流的完整联动

这些会在后续提交继续落地，但当前结构已经把长期路线固定下来了。

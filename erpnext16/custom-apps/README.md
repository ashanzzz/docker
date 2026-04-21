# ERPNext16 local custom apps

这个目录放 **和 erpnext16 镜像一起构建** 的本地 custom app 源码。

当前第一个 app：

- `ashan_cn_procurement` — 中国式采购 / 报销改造基础层

设计原则：

1. 业务代码放 app，不直接魔改标准 ERPNext 源码。
2. AIO 镜像构建时把这里的 app 一起打进去。
3. 先做稳定的采购明细税额联动基础层，再继续补报销单据与支付联动。

# ERPNext 16（Unraid / AIO-only）

这个目录现在**锁定为单容器 AIO 方案**。

也就是说：
- 保留目录名 `erpnext16`
- 只支持单容器 AIO 运行方式
- GitHub Actions 只构建并发布 AIO 镜像
- Unraid 侧只需要 `docker run`
- 容器内端口固定为 `8080`

多容器运行方案已经移除，不再作为本仓库维护目标。

---

## 官方参考

如果你要对照官方做法，看这些就够：

- Frappe Docker 官方文档入口：<https://frappe.github.io/frappe_docker/>
- 官方构建说明（Build Setup）：<https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/02-build-setup.md>
- 官方部署方式说明（Choosing a Deployment Method）：<https://github.com/frappe/frappe_docker/blob/main/docs/01-getting-started/01-choosing-a-deployment-method.md>
- ERPNext v16 项目地址：<https://github.com/frappe/erpnext/tree/version-16>
- Frappe Framework v16 项目地址：<https://github.com/frappe/frappe/tree/version-16>

说明：
- 官方默认更偏多服务拓扑。
- 这个仓库明确收口成单容器 AIO，只为降低 Unraid 单机部署复杂度。

---

## 我们现在要的方案

文档：`erpnext16/single-aio/README.md`

镜像：
- `ghcr.io/ashanzzz/erpnext16:aio`
- `ghcr.io/ashanzzz/erpnext16:v16.x.y-aio`

这就是现在唯一支持的部署入口。

---

## 业务功能改造文档

如果你要看这套 ERPNext16 在业务层面做了哪些中国式采购 / 报销增强、用户应该怎么操作、管理员应该如何配置，请直接看：

- [ERPNext16 中国式采购 / 报销改造说明](docs/guides/erpnext16-cn-procurement-user-guide.md)

如果你要看更细的实施与架构拆解，再继续看：

- `docs/plans/2026-04-22-phase2-default-date-and-grid-width.md`
- `docs/plans/2026-04-22-phase3-invoice-type-vat-and-reimbursement.md`
- `docs/plans/2026-04-22-phase4c-restricted-doc-final-architecture.md`

---

## `image/` 目录还保留着什么

`image/` 现在**不是独立部署方案**。

它保留的原因只有一个：
- 作为 AIO 构建时的输入目录

当前 AIO workflow 会继续使用：
- `erpnext16/image/apps.json`
- `erpnext16/image/apps.json.example`
- `erpnext16/custom-apps/`（本地 custom app 源码）

也就是说：
- 你可以把它理解为 AIO 镜像的 app 清单来源
- `custom-apps/` 是跟镜像一起打进去的业务代码
- 不是给用户单独拉一个“标准镜像”去部署的

文档：`erpnext16/image/README.md`

---

## 当前版本策略

当前 AIO 构建策略是：

- `FRAPPE_IMAGE_TAG=version-16`
- `FRAPPE_BRANCH=<优先使用与 ERPNext 相同的精确 v16.x.y tag；找不到时回退到 version-16 分支>`
- ERPNext app 也 pin 到同一个 `v16.x.y`

如果 workflow 找到了 ERPNext 的 `v16.x.y`，并且官方 `frappe/frappe` 也有同名 tag，就优先用同名 tag。

如果官方没有同名 Frappe tag，就回退到 `version-16` 分支，保证 AIO 镜像还能继续构建。

这意味着：
- 能精确对齐时就精确对齐
- 对不齐时，至少仍然锁在官方 `version-16` 主版本线上

---

## 额外官方 apps

如果后面要加官方 apps（如 `hrms` / `print_designer` / `helpdesk`），做法也还是 AIO 路线：

- 改 `erpnext16/image/apps.json`
- 或从 `erpnext16/image/apps.json.example` 复制一份再裁剪
- 然后继续走 AIO workflow 构建

不再保留额外的“标准镜像 / 多容器”发布路线。

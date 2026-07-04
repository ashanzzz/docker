# ERPNext 16 AIO infrastructure (Unraid / AIO-only)

这个目录现在只保留 **ERPNext16 的 AIO 基础设施**：

- AIO Containerfile
- image build inputs
- GitHub Actions workflow
- 单容器 `docker run` 说明
- 本地 `custom-apps/` 暂存目录

## 这套 AIO 的定位

它不是官方 `frappe_docker` 的原样复刻，而是一个 **面向 Unraid / 单容器部署** 的收敛版：

- 默认走 **内置 MariaDB + 内置 Redis**
- 运行时可以切到 **外部数据库 / 外部 Redis** 模式
- 核心目标是让同一个镜像既能单机开箱即用，也能接外部服务

## 业务定制代码在哪里

需要打进镜像的业务 custom app，直接放在：

- `erpnext16/custom-apps/`

构建流程**不会自动拉取任何外部仓库**，也**不需要 GitHub secret**。你要打包什么 custom app，就把源码放进这个目录，再重新构建镜像。

## 当前目录保留内容

- `single-aio/` — 单容器 AIO 镜像与运行说明
- `image/` — AIO 构建输入（官方 apps 清单等）
- `custom-apps/` — 本地 custom app 暂存目录

## 官方参考

- Frappe Docker 官方文档入口：<https://frappe.github.io/frappe_docker/>
- ERPNext v16：<https://github.com/frappe/erpnext/tree/version-16>
- Frappe v16：<https://github.com/frappe/frappe/tree/version-16>

## 说明

- 这里不再作为业务 custom app 的源码主仓库
- 业务改动先放到 `custom-apps/`，然后在镜像里验证
- AIO 侧只负责本地构建、部署、验收
- 运行模式通过环境变量切换；不会再维护两套完全独立的镜像实现

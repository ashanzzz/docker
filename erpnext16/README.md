# ERPNext 16 AIO infrastructure (Unraid / AIO-only)

这个目录现在只保留 **ERPNext16 的 AIO 基础设施**：

- AIO Containerfile
- image build inputs
- GitHub Actions workflow
- Unraid / `docker run` 说明

## 业务定制代码在哪里

ERPNext16 的个人业务 custom app 与业务说明文档，已经拆到独立私有仓库：

- `ashanzzz/erpnext-private-customizations`

这个仓库里的 AIO 构建流程会在构建前拉取私有仓库中的：

- `erpnext16/custom-apps/`

然后再把 custom app 打进 AIO 镜像。

当前策略：
- **不要求**私有仓库 push 后自动触发 AIO 构建
- AIO 仓库按 **每月一次** 的 GitHub Actions 定时构建（以及手动 workflow_dispatch）来拉取私有仓库最新 custom app
- GitHub Actions 侧需要配置私有仓库读取令牌：`PRIVATE_CUSTOM_REPO_PAT`

## 当前目录保留内容

- `single-aio/` — 单容器 AIO 镜像与运行说明
- `image/` — AIO 构建输入（官方 apps 清单等）
- `scripts/fetch-private-customizations.sh` — 构建前同步私有定制仓库

## 官方参考

- Frappe Docker 官方文档入口：<https://frappe.github.io/frappe_docker/>
- ERPNext v16：<https://github.com/frappe/erpnext/tree/version-16>
- Frappe v16：<https://github.com/frappe/frappe/tree/version-16>

## 说明

- 这里不再作为业务 custom app 的源码主仓库
- 业务改动先进入私有定制仓库
- AIO 侧只负责拉取、构建、部署、验收

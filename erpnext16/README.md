# ERPNext 16（Unraid）

你要求的最终形态：
- **名字保持 `erpnext16` 不变**
- **单容器 AIO**：一个容器内包含 **MariaDB + Redis + ERPNext 全套进程 + Nginx**
- **GitHub Actions 从官方代码自动构建并推送 GHCR**
- Unraid 侧只需要 `docker run`（或 Unraid Docker UI 模板）
- 容器内端口：**8080**（对外端口由 `-p <HOST_PORT>:8080` 决定；你想映射成 6XXX 或其它端口都可以，只要不冲突）

---

## 官方参考

这个目录里的方案是面向 Unraid 做的收敛版，便于单机落地；如果你要对照官方做法，建议先看下面这些地址：

- Frappe Docker 官方文档入口：<https://frappe.github.io/frappe_docker/>
- 官方构建说明（Build Setup）：<https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/02-build-setup.md>
- 官方部署方式说明（Choosing a Deployment Method）：<https://github.com/frappe/frappe_docker/blob/main/docs/01-getting-started/01-choosing-a-deployment-method.md>
- ERPNext v16 项目地址：<https://github.com/frappe/erpnext/tree/version-16>
- Frappe Framework v16 项目地址：<https://github.com/frappe/frappe/tree/version-16>

说明：
- 官方 Docker 方案默认是 `frappe_docker` 的多服务拓扑。
- 本目录保留 `erpnext16` 名称，并额外提供更适合 Unraid 的单容器 AIO 变体，主要是为了降低部署复杂度。

---

## ✅ 推荐：单容器 AIO（你现在要的方案）

文档：`erpnext16/single-aio/README.md`

镜像：
- `ghcr.io/ashanzzz/erpnext16:aio`（滚动最新）
- `ghcr.io/ashanzzz/erpnext16:v16.x.y-aio`（固定版本）

> 这是目前最符合你“Unraid 只用 docker run”的方式。

---

## 镜像类型说明

这里有三条线，别混：

### 1) `single-aio/`

- 真正的单容器 AIO
- 一个容器里带 MariaDB、Redis、ERPNext 相关进程和 Nginx
- 对外 tag：
  - `ghcr.io/ashanzzz/erpnext16:aio`
  - `ghcr.io/ashanzzz/erpnext16:v16.x.y-aio`

### 2) `image/`

- 标准 ERPNext 16 镜像
- 主要给多容器部署、自定义官方 apps、或后续衍生方案使用
- 不是单容器 AIO
- 对外 tag：
  - `ghcr.io/ashanzzz/erpnext16:latest`
  - `ghcr.io/ashanzzz/erpnext16:v16.x.y`
  - 自定义镜像示例：`ghcr.io/ashanzzz/erpnext16:v16-custom`

文档：`erpnext16/image/README.md`

### 3) `compose.yaml` / `docker-compose.unraid.yml` / `DOCKER_RUN.md`

- 仍然是官方多服务拓扑思路
- 只是镜像来源和 Unraid 运行方式做了收敛
- 适合你以后想从 AIO 回到更清晰的多容器拆分

---

## 当前版本策略

当前仓库默认采用的是：

- `FRAPPE_IMAGE_TAG=version-16`
- `FRAPPE_BRANCH=<与 ERPNext 相同的精确 v16.x.y tag>`
- ERPNext app 在 workflow 里按上游发现结果 pin 到 `v16.x.y`

也就是：
- Frappe 基础镜像仍走 `version-16` 版本线
- Frappe 源码和 ERPNext app 都要求对齐到同一个明确的 `v16.x.y` tag

如果 workflow 发现 ERPNext 的 `v16.x.y`，但官方 `frappe/frappe` 没有同名 tag，构建会直接失败，不再回退到 `version-16` 分支。

这套策略比之前更严格：
- 基础镜像 tag 仍然保持 `version-16`
- 但源码 ref 不再放任漂移
- 固定镜像 tag 对应固定源码 ref，重建时可重复性更好

---

## 可选：多容器（同一镜像，不用 compose 也能跑）

如果你未来想回到官方推荐的多容器拓扑（可更易升级/迁移），仍然保留：
- `erpnext16/DOCKER_RUN.md`（多容器 docker run，no compose）
- `erpnext16/docker-compose.unraid.yml`（如果你未来允许用 compose）

---

## 需要额外官方 Apps（未来再做）

当前你明确要求：**暂时不烘焙任何额外官方 Apps**。

当你决定要加官方 Apps（如 `hrms` / `print_designer` / `helpdesk`）时，可以使用：
- `.github/workflows/erpnext16-custom-image.yml`（手动触发构建自定义镜像）

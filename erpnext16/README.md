# ERPNext 16（Unraid）

你要求的最终形态：
- **名字保持 `erpnext16` 不变**
- **单容器 AIO**：一个容器内包含 **MariaDB + Redis + ERPNext 全套进程 + Nginx**
- **GitHub Actions 从官方代码自动构建并推送 GHCR**
- Unraid 侧只需要 `docker run`（或 Unraid Docker UI 模板）
- 对外端口：**8080**

---

## ✅ 推荐：单容器 AIO（你现在要的方案）

文档：`erpnext16/single-aio/README.md`

镜像：
- `ghcr.io/<你的GitHub用户名>/erpnext16:aio`（滚动最新）
- `ghcr.io/<你的GitHub用户名>/erpnext16:v16.x.y-aio`（固定版本）

> 这是目前最符合你“Unraid 只用 docker run”的方式。

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

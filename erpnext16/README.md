# ERPNext 16（Unraid AIO 体验版）

你要求：
- **名字保持 `erpnext16` 不变**
- **AIO**（一键起全栈）
- 可 **自定义官方 Apps**（例如 `hrms` / `print_designer` / `helpdesk` 等）

本目录实现方式：
- 运行层采用官方推荐的 **多容器 full-stack**（但通过 `run.sh` 做到 AIO 体验：一个目录、一条命令）
- 镜像层支持两种：
  1) 直接用官方 `frappe/erpnext` 或你自己镜像 `ghcr.io/ashanzzz/erpnext16`
  2) 需要额外官方 App 时：走 `apps.json` + build pipeline 生成**自定义镜像**，再在站点里 `install-app`

> 为什么不做“单容器真 AIO”？
> ERPNext/Frappe 官方长期维护的是多容器形态（backend/frontend/queue/scheduler/websocket + db/redis）。单容器能做但升级与稳定性成本高。

---

## 快速开始

```bash
cp .env.example .env
# 编辑 .env：改 DB_PASSWORD / ADMIN_PASSWORD / SITE_NAME / 端口

./run.sh up
./run.sh create-site

# 打开（默认）
# http://<Unraid-IP>:8080
```

## 安装额外官方 App（前提：镜像里已经包含该 App 源码）

```bash
./run.sh install-app hrms
```

> 关键点：**install-app 只安装到站点**；如果镜像里没有 app 代码，会失败。
> 所以额外官方 App 建议通过 `apps.json` 烘焙进自定义镜像。

---

## 文件说明

- `compose.yaml`：上游 `frappe_docker` 基础 compose（已 vendor）
- `overrides/`：MariaDB / Redis / NoProxy（端口暴露）等上游 override（已 vendor）
- `.env.example`：你的环境变量模板
- `run.sh`：一键脚本（up/down/logs/create-site/install-app）
- `legacy-aio/`：旧版单容器 AIO（已归档保留，便于回滚对照）

---

## 下一步（我需要你确认/补充的唯一信息）

1) 你希望默认端口仍然是 `80` 吗？（现在按官方样例走 `8080`，更安全不撞车）
2) 你要自定义的官方 Apps 清单是哪些？（例如：`hrms,print_designer,helpdesk`）

我确认后，就把 **自定义镜像的 build pipeline**（按 apps.json 自动构建推送 GHCR）补齐到“完美可用”。

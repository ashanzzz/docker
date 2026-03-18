# ERPNext 16（Unraid AIO 体验版）

你要求：
- **名字保持 `erpnext16` 不变**
- **AIO**（一键起全栈）
- **GitHub 构建 1 个镜像**，Unraid 直接运行（不需要在 Unraid 上跑构建脚本）
- 可 **自定义官方 Apps**（例如 `hrms` / `print_designer` / `helpdesk` 等；你当前要求：暂时不加额外 Apps）

本目录实现方式：
- 运行层采用官方推荐的 **多容器 full-stack**（在 Unraid 上可直接用 compose 部署；`run.sh` 仅作为可选便捷封装）
- 镜像层支持两种：
  1) 直接用官方 `frappe/erpnext` 或你自己镜像 `ghcr.io/ashanzzz/erpnext16`
  2) 需要额外官方 App 时：走 `apps.json` + build pipeline 生成**自定义镜像**，再在站点里 `install-app`

> 为什么不做“单容器真 AIO”？
> ERPNext/Frappe 官方长期维护的是多容器形态（backend/frontend/queue/scheduler/websocket + db/redis）。单容器能做但升级与稳定性成本高。

---

## 快速开始（Unraid 不跑自定义 sh；只用 compose）

1) 复制 env：

```bash
cp .env.example .env
```

2) 用 Unraid Compose Manager 部署：
- Compose 文件：`erpnext16/docker-compose.unraid.yml`
- Env 文件：`erpnext16/.env`（你刚复制的）

3) 访问：
- `http://<Unraid-IP>:8080`

> 说明：`create-site` 是一个一次性 job（会检查 site 是否已存在）；第一次 up 会自动建站。

## 安装额外官方 App（前提：镜像里已经包含该 App 源码）

（你当前要求：暂时不加额外 Apps）

如果未来需要额外官方 App（前提：镜像里已经包含该 App 源码）：

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

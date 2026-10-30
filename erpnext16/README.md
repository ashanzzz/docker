# ERPNext 16 单容器 AIO 镜像构建工程 (ashanzzz/docker/erpnext16)

本项目是 `ashanzzz/docker` 仓库下的 ERPNext 16 镜像构建子工程，用于构建包含 **Frappe Framework**、**ERPNext 16** 以及 **`ashan_cn_procurement` 自定义业务扩展应用** 的生产级单容器 AIO (All-In-One) 镜像。

---

## 一、 部署架构与设计规范

本工程采用**纯外部数据库与缓存（External-Only Services）**的现代化容器架构：

```text
+----------------------------------------------------+
|               ERPNext16 运行时容器                   |
|                                                    |
|  - Nginx (反向代理与静态资源托管)                     |
|  - Gunicorn (Frappe Python 后端 WSGI 服务)         |
|  - Socket.IO (实时 WebSocket 通信服务)              |
|  - Celery/Frappe Worker (后台异步任务工作进程)       |
|  - Celery/Frappe Scheduler (定时调度器进程)         |
+----------------------------------------------------+
                          | (网络通信)
                          v
+----------------------------------------------------+
|               外部依赖基础设施服务                    |
|                                                    |
|  - MariaDB 11.x+ (业务持久化数据库)                  |
|  - Redis Cache (内存缓存服务)                       |
|  - Redis Queue (后台任务队列服务)                    |
|  - Redis SocketIO (长连接状态服务)                  |
+----------------------------------------------------+
```

- **容器内部无捆绑数据库/缓存**：容器内彻底移除了 MariaDB 和 Redis，消除单点臃肿，确保数据持久性与集群伸缩能力。
- **确定性启动时序**：容器启动时依次执行环境校验 -> DB/Redis 连通探测 -> 站点自动初始化/迁移 (`bench migrate`) -> Nginx 配置验证 -> 启动 Supervisor 进程树。

---

## 二、 完整项目目录结构

```text
erpnext16/
├── .dockerignore                            # Docker 构建忽略规则配置
├── ERPNEXT_VERSION                          # 当前跟踪的上游 ERPNext 官方版本 (如 v16.37.0)
├── apps.json                                # Frappe 官方依赖 App 清单 (ERPNext version-16)
├── README.md                                # 本构建与目录说明文档
├── custom-apps/                             # 自定义业务 App 构建暂存目录
│   └── README.md                            # 仅用于构建期拉取暂存，严禁在此维护业务源码
├── docs/                                    # 技术方案与架构说明
│   └── external-only-aio.md                 # 纯外部数据库/Redis 架构技术路线详解
├── scripts/                                 # 构建与应用拉取自动化脚本
│   ├── build-local.sh                       # 本地 Docker 镜像构建调试脚本
│   └── fetch-ashan-custom-app.sh            # 从私有定制仓库自动拉取 ashan_cn_procurement 脚本
└── single-aio/                              # AIO 单容器构建核心规范
    ├── Containerfile                        # Multi-stage 多阶段构建定义 (Builder -> Final)
    ├── README.md                            # 启动生命周期、环境变量与健康检查说明
    └── rootfs/                              # 容器内文件系统模板与启动入口
        ├── etc/
        │   └── supervisor/
        │       ├── supervisord.conf         # Supervisor 主进程管理配置
        │       └── conf.d/
        │           └── 20-erpnext.conf      # ERPNext 进程树托管 (Nginx, Gunicorn, Worker, Scheduler, Socketio)
        └── usr/local/bin/
            ├── entrypoint.sh                # 容器确定性启动、配置注入与自动迁移脚本
            └── aio-healthcheck.sh           # Docker 原生健康检查探测脚本
```

---

## 三、 自定义业务应用 (`ashan_cn_procurement`) 集成机制

- **源码权威来源 (Source of Truth)**：
  `https://github.com/ashanzzz/erpnext-private-customizations`
- **构建注入机制**：
  在 GitHub Actions 构建或本地执行 `./scripts/build-local.sh` 时，脚本会自动拉取 `ashanzzz/erpnext-private-customizations` 仓库 `main` 分支的最新代码至 `custom-apps/ashan_cn_procurement`，并通过 `--build-arg` 与多阶段编译将其固化打包至镜像内的 Python 环境与 `sites/apps.txt` 中。

---

## 四、 镜像构建与发布

### 1. GitHub Actions 自动化构建
- **工作流文件**：`.github/workflows/erpnext16-single-container-aio.yml`
- **发布产物**：`ghcr.io/ashanzzz/erpnext16:latest` (以及按 commit sha 标记的版本镜像)

### 2. 本地构建调试
```bash
cd erpnext16
./scripts/build-local.sh
```

---

## 五、 生产运行与持久化挂载

生产环境运行时，**仅需挂载 sites 目录即可保持全部运行时状态**：

```text
/home/frappe/frappe-bench/sites
```

业务数据全部存储于外部 MariaDB，队列与缓存存储于外部 Redis。

### 核心环境变量清单

| 变量名 | 说明 | 示例值 |
| :--- | :--- | :--- |
| `SITE_NAME` | ERPNext 站点名称 | `erpnext16.local` |
| `FRAPPE_DB_TYPE` | 数据库类型 | `mariadb` |
| `FRAPPE_DB_HOST` | 外部数据库主机地址 | `192.168.8.11` |
| `FRAPPE_DB_PORT` | 外部数据库端口 | `3306` |
| `FRAPPE_DB_NAME` | 业务数据库名 | `erpnext16` |
| `FRAPPE_DB_USER` | 数据库用户名 | `frappe` |
| `FRAPPE_DB_PASSWORD`| 数据库密码 | `[REDACTED]` |
| `FRAPPE_REDIS_CACHE`| 外部 Redis 缓存服务连接串 | `redis://192.168.8.11:6379/1` |
| `FRAPPE_REDIS_QUEUE`| 外部 Redis 任务队列连接串 | `redis://192.168.8.11:6379/2` |
| `FRAPPE_REDIS_SOCKETIO` | 外部 Redis 长连接服务串 | `redis://192.168.8.11:6379/3` |
| `ADMIN_PASSWORD` | 首次建站管理员密码（非初次建站无需设置） | `[REDACTED]` |

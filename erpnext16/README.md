# ERPNext 16 AIO Docker

此目录包含构建和运行 **ERPNext 16 全栈镜像**（All‑in‑One）所需的文件。  
镜像默认使用内置的 MariaDB，也可以选择连接外部数据库。

## 文件结构

```
erpnext16/
├── Dockerfile                     # 构建镜像
├── run-aio.sh                     # 一键运行脚本（支持内部/外部 DB）
├── README.md                      # 本文档
└── installdata/
    └── install-erpnext16.sh       # 在镜像构建时执行的完整安装脚本
```

## 快速开始

### 1. 运行内部数据库（默认）

```bash
cd erpnext16
./run-aio.sh
```

容器将以后台模式启动，默认映射到宿主机的 80 端口。  
管理员密码默认为 `admin`，站点名称为 `site1.local`。

#### 持久化策略（默认目录映射）

脚本默认使用 **目录映射（bind‑mount）** 持久化数据到：

* `erpnext16/data/sites` → `/home/frappe/frappe-bench/sites`
* `erpnext16/data/mysql` → `/var/lib/mysql`

并在启动前尝试自动修复权限（`FIX_PERMS=yes`，默认开启）。

> 如果你的宿主机目录所在文件系统不支持 `chown`（如某些 NAS/NFS/NTFS 场景），权限修复会失败；此时建议切换到命名卷：
>
> ```bash
> USE_NAMED_VOLUMES=yes ./run-aio.sh
> ```

### 2. 外部数据库（说明）

本仓库的 AIO 镜像当前按“一体化”思路构建（容器内含 MariaDB 并由 supervisor 管理）。  
如果你更希望 **业务容器 + 独立数据库** 的标准架构，我建议直接采用官方推荐的 `frappe/frappe_docker`（维护成本更低、升级路径更清晰）。

后续如果你确认要我把本 AIO 镜像改造成“可切换外部 DB”的模式（不启动容器内 MariaDB、通过环境变量连接外部 DB），我可以再做一轮结构性改造。
## 官方插件策略（默认不装，脚本里保留注释模板）

当前安装脚本遵循：

- **必装（官方核心）**：`frappe + payments + erpnext`
- **可选（官方插件）**：默认不安装，但在脚本中已预留注释模板，随时手动打开

已预留的官方插件模板：

- `hrms`
- `print_designer`

你可以直接编辑 `installdata/install-erpnext16.sh`，取消对应 `bench get-app` / `bench --site ... install-app` 的注释后重建镜像。这样保持默认镜像干净，同时可按需快速扩展。
## 构建镜像

```bash
docker build -t ghcr.io/ashanzzz/erpnext16-aio:latest .
```

构建完成后，您可以推送到 GitHub Container Registry（需要提前登录）：

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u ashanzzz --password-stdin
docker push ghcr.io/ashanzzz/erpnext16-aio:latest
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `IMAGE` | `ghcr.io/ashanzzz/erpnext16-aio:latest` | 要运行的镜像 |
| `NAME` | `erpnext16-aio` | 容器名称 |
| `HTTP_PORT` | `80` | 宿主机映射的 HTTP 端口 |
| `MARIADB_ROOT_PASSWORD` | `Pass1234` | 内部 MariaDB root 密码 |
| `ADMIN_PASSWORD` | `admin` | ERPNext 管理员密码 |
| `SITE_NAME` | `site1.local` | 默认站点名称 |
| `FIX_PERMS` | `yes` | 目录映射时，启动前是否自动尝试修复权限（bind-mount 场景） |
| `USE_NAMED_VOLUMES` | `no` | 是否改用 Docker 命名卷（当 bind-mount 的文件系统不支持 chown 时） |
| `DATA_DIR` | `erpnext16/data` | bind-mount 数据根目录（可覆盖） |
| `SITES_DIR` | `DATA_DIR/sites` | bind-mount 的 sites 目录（可覆盖） |
| `MYSQL_DIR` | `DATA_DIR/mysql` | bind-mount 的 mysql 目录（可覆盖） |

构建时可选环境变量：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `INSTALL_APPS` | 空 | 构建时额外安装的 app（逗号或空格分隔，如 `hrms,payments`） |
| `INSTALL_ERPNEXT_CHINESE` | `no` | 构建时是否安装非官方中文本地化 app |

## 常见问题

1. **目录映射保存失败**  
   默认脚本会尝试 `chown` 修复权限；如果仍失败（常见于不支持 chown 的文件系统），再切换 `USE_NAMED_VOLUMES=yes`。

2. **如何修改站点名称或管理员密码**  
   可通过环境变量 `SITE_NAME` 与 `ADMIN_PASSWORD` 覆盖。

3. **能否在运行时安装额外的应用**  
   可以。进入容器后使用 `bench get‑app <repo>` 并在站点上执行 `bench --site <site> install‑app <app>`。

## 贡献

请在此仓库根目录使用 Pull Request（PR）提交对 `erpnext16` 目录的修改。

## 许可

遵循上游 Frappe / ERPNext 的 MIT 许可。
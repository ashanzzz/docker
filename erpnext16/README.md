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
数据将持久化到两个 Docker 命名卷：

* `erpnext16-sites` → `/home/frappe/frappe-bench/sites`
* `erpnext16-mysql` → `/var/lib/mysql`

> **为什么推荐命名卷而不是目录映射？**  
> 在目录映射（bind‑mount）时，宿主机目录的所有者和容器内部用户（frappe、mysql）的 UID 不匹配，导致写入失败或权限错误。  
> 使用命名卷可以让 Docker 自动处理所有权，避免此类问题。

### 2. 使用外部数据库

如果您已有独立的 MariaDB（10.11 或更高）实例，可设置以下环境变量并运行脚本：

```bash
export EXTERNAL_DB=1
export DB_HOST=192.168.1.100
export DB_PORT=3306
export DB_ROOT_USER=root
export DB_ROOT_PASSWORD=myrootpass

./run-aio.sh
```

容器将不启动内部的 MariaDB，而是尝试连接您提供的数据库。

## 可选的官方插件

安装脚本默认只安装 **ERPNext 核心**。如果您想一次性获取并安装以下官方插件，可在构建镜像前设置环境变量：

```bash
export INSTALL_OPTIONAL_APPS=yes
```

* payments
* hrms
* print_designer

> **注意**：这些插件仅在构建时获取并安装。如需后续增删，请在容器内使用 `bench get-app` 或自行修改 `install-erpnext16.sh`。

## 构建镜像

```bash
docker build -t ghcr.io/ashanzzz/erpnext16-aio:latest .
```

构建完成后，您可以推送到 GitHub Container Registry（需要提前登录）：

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u ash anzzz --password-stdin
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
| `INSTALL_OPTIONAL_APPS` | `no` | 是否在构建时安装可选插件 |

## 使用外部数据库（docker‑compose 示例）

```yaml
version: '3.8'

services:
  db:
    image: mariadb:10.11
    environment:
      MYSQL_ROOT_PASSWORD: myrootpass
    volumes:
      - db-data:/var/lib/mysql
    ports:
      - "3306:3306"

  erpnext:
    image: ghcr.io/ashanzzz/erpnext16-aio:latest
    ports:
      - "80:80"
    environment:
      DB_HOST: db
      DB_PORT: 3306
      DB_ROOT_USER: root
      DB_ROOT_PASSWORD: myrootpass
      ADMIN_PASSWORD: admin
      SITE_NAME: site1.local
    volumes:
      - erpnext-sites:/home/frappe/frappe-bench/sites

volumes:
  db-data:
  erpnext-sites:
```

## 常见问题

1. **目录映射保存失败**  
   如上文所述，推荐使用 Docker 命名卷（named volume）来持久化数据，避免权限问题。

2. **如何修改站点名称或管理员密码**  
   可通过环境变量 `SITE_NAME` 与 `ADMIN_PASSWORD` 覆盖。

3. **能否在运行时安装额外的应用**  
   可以。进入容器后使用 `bench get‑app <repo>` 并在站点上执行 `bench --site <site> install‑app <app>`。

## 贡献

请在此仓库根目录使用 Pull Request（PR）提交对 `erpnext16` 目录的修改。

## 许可

遵循上游 Frappe / ERPNext 的 MIT 许可。
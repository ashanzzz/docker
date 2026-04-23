# ERPNext16 single-container AIO (docker run)

你明确要求：**单容器**、Unraid 侧只用 `docker run`。

本目录会构建并推送镜像：
- `ghcr.io/ashanzzz/erpnext16:aio`
- `ghcr.io/ashanzzz/erpnext16:latest`
- `ghcr.io/ashanzzz/erpnext16:v16.x.y-aio`

## 默认登录信息

- **站点地址**：`http://<容器IP>:6888/login`
- **用户名**：`Administrator`
- **密码**：`adminpassword`
- **数据库 root 密码**：`mysqlpassword`

> 建议首次登录后立即修改密码。

## 运行示例（Unraid）

> 镜像容器内固定监听 **8080**。
> 你对外暴露的端口完全由 `-p <HOST_PORT>:8080` 决定（例如 6888/6001/8888 都可以，只要不冲突）。

### Unraid 模板里最容易配错的两项

1. **WebUI / 端口映射必须指向容器 `8080`，不是 `8000`**
   - `8000` 是 gunicorn 后端端口
   - `8080` 才是 nginx 对外入口
   - 正确示例：宿主机 `6888` -> 容器 `8080`

2. **不要挂载 `/etc/supervisor/supervisord.conf`**
   - 镜像里已经带了配好的 supervisor 配置
   - 如果你用宿主机文件覆盖它，常见结果就是 nginx / worker / scheduler 启动链不一致
   - 这个 AIO 方案只需要挂载：
     - `/home/frappe/frappe-bench/sites`
     - `/var/lib/mysql`
     - `/var/lib/redis`

### 最简启动（推荐）

```bash
docker run -d --name erpnext16 \
  --restart unless-stopped \
  -p 6888:8080 \
  -e SITE_NAME=site1.local \
  -e ADMIN_PASSWORD=adminpassword \
  -e MARIADB_ROOT_PASSWORD=mysqlpassword \
  -v /mnt/user/appdata/erpnext16/sites:/home/frappe/frappe-bench/sites \
  -v /mnt/user/appdata/erpnext16/mysql:/var/lib/mysql \
  -v /mnt/user/appdata/erpnext16/redis:/var/lib/redis \
  ghcr.io/ashanzzz/erpnext16:aio
```

访问：`http://<unraid-ip>:6888/login`

### 默认初始化值

如果你不传环境变量，镜像会用下面这些默认值初始化：

- 站点名：`site1.local`
- ERPNext 登录用户名：`Administrator`
- ERPNext 默认管理员密码：`adminpassword`
- MariaDB root 密码：`mysqlpassword`
- 默认安装 app：如果镜像中已同步私有定制 app，则为 `erpnext,ashan_cn_procurement`；否则仅 `erpnext`

建议：
- 这套默认值只是为了第一次起容器更省事
- 正式用的时候，第一次登录后就改密码
- 如果你不想用默认值，直接在 Unraid 模板里覆盖环境变量即可

### 一键重置为全新系统

容器里现在带了一个重置脚本：

```bash
docker exec -it erpnext16 aio-reset.sh --yes
```

它会做这些事：

1. 把当前数据备份到：
   - `/home/frappe/frappe-bench/sites/.aio-reset-backups/<时间戳>/`
2. 备份内容包括：
   - `sites.tar.gz`
   - `mysql.tar.gz`
   - `redis.tar.gz`
   - `metadata.txt`
3. 清空运行中的 `sites/mysql/redis`
4. 终止容器主进程，让 Docker 按重启策略重新拉起一个“全新初始化”的系统

说明：
- 备份放在挂载卷里，不放在镜像内部
- 这样容器重建后，备份还在
- 如果你只是想回看旧数据，去 `.aio-reset-backups/` 里找对应时间戳目录就行

### 可选参数（一般不需要）

- `SITE_INSTALL_APPS`：默认会根据镜像里是否带有 `ashan_cn_procurement` 自动决定（带 app 时为 `erpnext,ashan_cn_procurement`，否则为 `erpnext`）。如果你后续还要把别的 app 一起装到站点，可以在这里追加。
- `MARIADB_USER_HOST_LOGIN_SCOPE`：默认已是 `localhost`，通常无需再传。
- `GUNICORN_WORKERS`：默认 `1`。如果宿主机资源充足，可再调大。
- `GUNICORN_THREADS`：默认 `2`。
- `GUNICORN_TIMEOUT`：默认 `300` 秒，用于降低首次重负载页面/接口被过早杀掉的概率。
- `BENCH_WORKER_QUEUES`：默认 `long,default,short`。
- `REDIS_CACHE_DB` / `REDIS_QUEUE_DB` / `REDIS_SOCKETIO_DB`：默认分别是 `0/1/2`，单 Redis 实例下也会按逻辑库拆分，避免全部挤在同一个 DB。

### 多 site 说明

- 默认只会自动创建一个站点：`site1.local`
- `sites/` 目录本身可以放多个 site
- 如果你后面要加第二个 site，可以在容器里用 bench 手动创建
- 也就是说：单容器 AIO 默认是“单 site 开箱即用”，不是“自动多 site 初始化”

### 重要提示

- **不要**额外挂载覆盖 `/etc/supervisor/supervisord.conf`（否则会覆盖镜像内的修复，导致行为不一致）。
- 当前 AIO 默认已偏向 **低资源 / Unraid 稳定优先**：web gunicorn 默认更轻、timeout 更宽，Redis 逻辑库也已拆分；如果你后面要追求吞吐，再手动往上调。
- 这个仓库现在已经锁定成 AIO-only。`erpnext16/` 下不再维护多容器运行入口。
- `erpnext16/image/` 仍然保留，但它只是 AIO 构建时使用的 app 清单和构建辅助目录，不是独立部署入口。
- 如果首次初始化 MariaDB 失败，最省事的恢复方式是：删掉容器，清空 `sites/mysql/redis` 三个目录后重新创建。
- `MARIADB_ROOT_PASSWORD` 建议先用普通强密码（字母、数字、下划线、短横线），先不要带单引号。

### 改错后的访问方式

如果你把 Unraid 模板改成：
- Host Port: `6888`
- Container Port: `8080`

那访问地址就是：

```text
http://<你的Unraid-IP>:6888/login
```

## 升级

### 升级前

先备份这三个目录：
- `sites`
- `mysql`
- `redis`

如果你现在跑的是固定版本，建议先记下旧 tag，方便回滚。

### 升级步骤

1. `docker pull` 新镜像
2. 停掉旧容器
3. 用新镜像重新 `docker run`
4. 容器起来后，先确认：
   - 登录页正常
   - 站点能打开
   - 基本页面无 502 / 500

### 关于 migrate

如果这次升级跨了 ERPNext/Frappe 发布点，建议在站点数据备份完成后，额外执行一次站点升级检查。

最稳妥的做法是：
- 先在测试环境验证
- 再升级正式环境

### 回滚

如果升级后异常：

1. 停掉新容器
2. 改回旧镜像 tag
3. 重新启动旧容器
4. 如果数据已经被新版本写入并出现不兼容，再恢复你升级前备份的 `sites/mysql/redis`

不要把 `latest` 当成唯一回滚依据。真要长期跑，最好保留一个固定 tag。

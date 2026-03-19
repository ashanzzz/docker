# ERPNext16 single-container AIO (docker run)

你明确要求：**单容器**、Unraid 侧只用 `docker run`。

本目录会构建并推送镜像：
- `ghcr.io/ashanzzz/erpnext16:aio`
- `ghcr.io/ashanzzz/erpnext16:v16.x.y-aio`

## 运行示例（Unraid）

> 镜像容器内固定监听 **8080**。
> 你对外暴露的端口完全由 `-p <HOST_PORT>:8080` 决定（例如 6888/6001/8888 都可以，只要不冲突）。

### 最简启动（推荐）

```bash
docker run -d --name erpnext16 \
  --restart unless-stopped \
  -p 6888:8080 \
  -e SITE_NAME=site1.local \
  -e ADMIN_PASSWORD=ChangeMe_Admin \
  -e MARIADB_ROOT_PASSWORD=ChangeMe_Strong_DB \
  -v /mnt/user/appdata/erpnext16/sites:/home/frappe/frappe-bench/sites \
  -v /mnt/user/appdata/erpnext16/mysql:/var/lib/mysql \
  -v /mnt/user/appdata/erpnext16/redis:/var/lib/redis \
  ghcr.io/ashanzzz/erpnext16:aio
```

访问：`http://<unraid-ip>:6888/login`

### 可选参数（一般不需要）

- `MARIADB_USER_HOST_LOGIN_SCOPE`：默认已是 `localhost`，通常无需再传。

### 重要提示

- **不要**额外挂载覆盖 `/etc/supervisor/supervisord.conf`（否则会覆盖镜像内的修复，导致行为不一致）。

## 升级

- 先备份三个目录（sites/mysql/redis）
- `docker pull` 新镜像
- 停旧容器，重新 run 新镜像（容器会复用你的 volume 数据）

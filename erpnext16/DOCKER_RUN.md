# ERPNext16 on Unraid — 多容器 `docker run`（no compose）

> 你当前主方案是 **单容器 AIO**（更符合“Unraid 只用一个 docker run”）：
> - 先看：`erpnext16/single-aio/README.md`

本文件是 **可选方案**：不用 compose，但仍按官方多进程拓扑拆成多个容器来跑。

目标：
- 镜像由 GitHub Actions 构建并推送：`ghcr.io/<你的GitHub用户名>/erpnext16:<tag>`
- Unraid 侧不使用 compose，不跑自定义脚本；只用 `docker run`

重要澄清：**一个镜像 ≠ 一个容器**。
- 官方推荐是多服务（backend/frontend/websocket/worker/scheduler + db + redis）
- 这里做到的是：**ERPNext 相关服务全部使用同一个镜像**，但仍然需要多个容器来跑不同进程

---

## 0) 先准备（一次性）

### 0.1 选择镜像 tag

建议先用 rolling tag：

```bash
export ERP_IMAGE="ghcr.io/ashanzzz/erpnext16:latest"
```

生产更建议 pin 版本：

```bash
export ERP_IMAGE="ghcr.io/ashanzzz/erpnext16:v16.x.y"
```

说明：
- `latest` 是标准镜像的滚动 tag
- 如果你要单容器 AIO，不要用这里的多容器命令，直接看 `erpnext16/single-aio/README.md`

### 0.2 站点与密码

```bash
export SITE_NAME="site1.local"
export DB_PASSWORD="ChangeMe_Strong_DB_Password"
export ADMIN_PASSWORD="ChangeMe_Strong_Admin_Password"

# 访问端口（你要求 8080）
export HTTP_PUBLISH_PORT=8080
```

### 0.3 创建网络与 volumes（一次性）

```bash
docker network create erpnext16-net || true

docker volume create erpnext16_sites || true
docker volume create erpnext16_db || true
docker volume create erpnext16_redis_queue || true
```

---

## 1) 启动 DB/Redis（先起）

### MariaDB 11.8

```bash
docker run -d --name erpnext16-db \
  --network erpnext16-net \
  --restart unless-stopped \
  -e MYSQL_ROOT_PASSWORD="$DB_PASSWORD" \
  -e MARIADB_AUTO_UPGRADE=1 \
  -v erpnext16_db:/var/lib/mysql \
  mariadb:11.8 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --skip-character-set-client-handshake
```

> Unraid 里如果你更喜欢 bind-mount 到 `/mnt/user/appdata/...`，也可以把 volume 换成 `-v /mnt/user/appdata/erpnext16/db:/var/lib/mysql`。

### Redis cache / queue

```bash
docker run -d --name erpnext16-redis-cache \
  --network erpnext16-net \
  --restart unless-stopped \
  redis:6.2-alpine

docker run -d --name erpnext16-redis-queue \
  --network erpnext16-net \
  --restart unless-stopped \
  -v erpnext16_redis_queue:/data \
  redis:6.2-alpine
```

---

## 2) 运行 configurator（一次性，写 common_site_config）

```bash
docker run --rm --name erpnext16-configurator \
  --network erpnext16-net \
  -v erpnext16_sites:/home/frappe/frappe-bench/sites \
  -e DB_HOST=erpnext16-db \
  -e DB_PORT=3306 \
  -e REDIS_CACHE=erpnext16-redis-cache:6379 \
  -e REDIS_QUEUE=erpnext16-redis-queue:6379 \
  -e SOCKETIO_PORT=9000 \
  "$ERP_IMAGE" \
  bash -lc 'ls -1 apps > sites/apps.txt; \
    bench set-config -g db_host "$DB_HOST"; \
    bench set-config -gp db_port "$DB_PORT"; \
    bench set-config -g redis_cache "redis://$REDIS_CACHE"; \
    bench set-config -g redis_queue "redis://$REDIS_QUEUE"; \
    bench set-config -g redis_socketio "redis://$REDIS_QUEUE"; \
    bench set-config -gp socketio_port "$SOCKETIO_PORT"; \
    bench set-config -g chromium_path /usr/bin/chromium-headless-shell;'
```

---

## 3) 创建站点（第一次需要；可重复执行，已存在就跳过）

```bash
docker run --rm --name erpnext16-create-site \
  --network erpnext16-net \
  -v erpnext16_sites:/home/frappe/frappe-bench/sites \
  -e SITE_NAME="$SITE_NAME" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  "$ERP_IMAGE" \
  bash -lc 'if [ -d "sites/$SITE_NAME" ]; then echo "Site exists: $SITE_NAME"; exit 0; fi; \
    bench new-site --mariadb-user-host-login-scope="%" \
      --db-root-password "$DB_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --install-app erpnext \
      --set-default frontend \
      "$SITE_NAME"'
```

---

## 4) 启动 ERPNext 服务容器（全部用同一镜像）

### backend

```bash
docker run -d --name erpnext16-backend \
  --network erpnext16-net \
  --restart unless-stopped \
  -v erpnext16_sites:/home/frappe/frappe-bench/sites \
  "$ERP_IMAGE"
```

### websocket

```bash
docker run -d --name erpnext16-websocket \
  --network erpnext16-net \
  --restart unless-stopped \
  -v erpnext16_sites:/home/frappe/frappe-bench/sites \
  "$ERP_IMAGE" node /home/frappe/frappe-bench/apps/frappe/socketio.js
```

### worker（先用一个 worker 覆盖所有队列，容器更少）

```bash
docker run -d --name erpnext16-worker \
  --network erpnext16-net \
  --restart unless-stopped \
  -v erpnext16_sites:/home/frappe/frappe-bench/sites \
  "$ERP_IMAGE" bench worker --queue long,default,short
```

### scheduler

```bash
docker run -d --name erpnext16-scheduler \
  --network erpnext16-net \
  --restart unless-stopped \
  -v erpnext16_sites:/home/frappe/frappe-bench/sites \
  "$ERP_IMAGE" bench schedule
```

### frontend（对外 8080）

```bash
docker run -d --name erpnext16-frontend \
  --network erpnext16-net \
  --restart unless-stopped \
  -p ${HTTP_PUBLISH_PORT}:8080 \
  -e BACKEND=erpnext16-backend:8000 \
  -e SOCKETIO=erpnext16-websocket:9000 \
  -e FRAPPE_SITE_NAME_HEADER="$SITE_NAME" \
  "$ERP_IMAGE" nginx-entrypoint.sh
```

访问：
- `http://<Unraid-IP>:8080`

---

## 5) 升级

### 升级前

- 先备份 `erpnext16_sites`、`erpnext16_db`、`erpnext16_redis_queue`
- 如果你用的是 bind mount，就备份对应宿主机目录
- 记录当前镜像 tag，方便回滚

### 升级步骤

```bash
docker pull "$ERP_IMAGE"
# 逐个 restart ERPNext 相关容器即可（不涉及删除权限）
docker restart erpnext16-backend erpnext16-websocket erpnext16-worker erpnext16-scheduler erpnext16-frontend
```

如果这次升级跨了明确发布版本，建议在升级后检查一次站点迁移状态，不要只看容器有没有起来。

### 回滚

如果升级后有异常：

1. 把 `ERP_IMAGE` 改回旧 tag
2. 重启 ERPNext 相关容器
3. 如果站点数据已经被新版本写入并不兼容，再恢复升级前备份的数据卷

不建议长期只依赖 `latest` 做生产升级。

---

## FAQ

### 为什么 frontend 需要 FRAPPE_SITE_NAME_HEADER？
因为默认按 Host 头匹配站点名。Unraid 上常用 IP:8080 访问，Host 可能是 IP。
设置 `FRAPPE_SITE_NAME_HEADER=$SITE_NAME` 可以强制映射到你的站点名，省心。

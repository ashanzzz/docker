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
- 这个镜像是 AIO 变体，不是官方默认多服务生产拓扑。要回到标准多容器路线，请看 `erpnext16/README.md` 和 `erpnext16/DOCKER_RUN.md`。

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

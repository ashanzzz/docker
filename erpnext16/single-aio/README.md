# ERPNext16 single-container AIO (docker run)

你明确要求：**单容器**、Unraid 侧只用 `docker run`。

本目录会构建并推送镜像：
- `ghcr.io/ashanzzz/erpnext16:single-aio`
- `ghcr.io/ashanzzz/erpnext16:v16.x.y-single-aio`

## 运行示例（Unraid）

```bash
docker run -d --name erpnext16 \
  --restart unless-stopped \
  -p 8080:8080 \
  -e SITE_NAME=site1.local \
  -e ADMIN_PASSWORD=ChangeMe_Admin \
  -e MARIADB_ROOT_PASSWORD=ChangeMe_Strong_DB \
  -v /mnt/user/appdata/erpnext16/sites:/home/frappe/frappe-bench/sites \
  -v /mnt/user/appdata/erpnext16/mysql:/var/lib/mysql \
  -v /mnt/user/appdata/erpnext16/redis:/var/lib/redis \
  ghcr.io/ashanzzz/erpnext16:single-aio
```

访问：`http://<unraid-ip>:8080`

## 升级

- 先备份三个目录（sites/mysql/redis）
- `docker pull` 新镜像
- 停旧容器，重新 run 新镜像（容器会复用你的 volume 数据）

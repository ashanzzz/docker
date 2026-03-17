# Nextcloud (full stack) — docker-compose + one-shot automation

目标：在 **Unraid / Linux** 上用一条脚本完成“可用且偏生产”的 Nextcloud 部署，并尽量把易踩坑的配置（反代、Redis 文件锁、Cron、预览、Office）自动化。

> 说明：本目录提供 **部署脚本 + docker-compose**（不是自建 Nextcloud 镜像）。

## Features（默认启用）

- Nextcloud（Apache 版，便于单容器直接反代）
- MariaDB（持久化）
- Redis（内存缓存 + file locking）
- Cron（独立容器跑后台任务，避免 AJAX/请求触发）
- Collabora CODE（可选：Office 在线预览/编辑）
- 反代友好：可配置 `trusted_domains / overwrite* / trusted_proxies`
- 常用性能/稳定性设置：OPcache、PHP 上传大小、预览 provider（可选）

## Quick start

```bash
cd nextcloud
cp .env.example .env
# 按需修改：域名、端口、数据盘路径、密码等

bash run.sh up
bash run.sh post-config
bash run.sh status
```

如果你已经有旧的 Nextcloud 数据目录：先把 `DATA_DIR/DB_DIR/REDIS_DIR` 指到旧目录，再执行 `up`。

## Important vars

- `TRUSTED_DOMAINS`：**空格分隔**（Nextcloud 官方 docker 入口的格式）
- `TRUSTED_PROXIES`：空格分隔（可留空）

## Important dirs（建议 Unraid）

- `DATA_DIR`：Nextcloud 程序数据（config/custom_apps/themes）
- `FILES_DIR`：用户文件 data（建议单独盘/共享）
- `DB_DIR`：MariaDB 数据
- `REDIS_DIR`：Redis 数据（可选）

> 不建议把 `/var/www/html` 整目录映射出来（会干扰升级/权限）。本方案只映射：
> - `/var/www/html/config`
> - `/var/www/html/custom_apps`
> - `/var/www/html/themes`（可选）
> - `/var/www/html/data`

## Script commands

- `bash run.sh up`：启动/更新
- `bash run.sh down`：停止
- `bash run.sh post-config`：安装后自动配置（反代/Redis/Cron/外部存储相关开关等）
- `bash run.sh enable-collabora`：安装/启用 richdocuments，并指向 collabora 容器
- `bash run.sh enable-fulltextsearch`：启动 Elasticsearch profile + 安装全文检索 apps + 跑一次 index（耗时）
- `bash run.sh occ <...>`：执行 occ
- `bash run.sh logs`：看日志

## Reverse proxy notes (1Panel / nginx / caddy)

反代后建议至少配置：
- `trusted_domains`（域名 + 内网 IP）
- `trusted_proxies`（反代 IP/网段）
- `overwriteprotocol=https`
- `overwrite.cli.url=https://<your-domain>`

脚本会按 `.env` 中的变量写入上述配置。

## Security

- `.env` 含数据库/管理员密码：不要提交到 Git。
- 本目录提供 `.env.example` 作为模板。

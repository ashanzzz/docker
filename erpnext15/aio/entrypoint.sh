#!/usr/bin/env bash
# erpnext15/aio/entrypoint.sh
# 单容器 AIO 启动脚本（外接数据库/Redis；不会内置 MariaDB/Redis）
set -euo pipefail

export BENCH_HOME="/home/frappe/frappe-bench"
cd "$BENCH_HOME"

# ===== 必填/可选环境变量（外部注入）=====
DB_HOST="${DB_HOST:-}"     # 必填：数据库主机
DB_PORT="${DB_PORT:-3306}" # 可选：默认 3306

# Redis 支持两种写法：
#  1) 片段：REDIS_CACHE=":pass@host:6379"（脚本会自动补全为 redis://）
#  2) 完整：REDIS_CACHE="redis://:pass@host:6379"
REDIS_CACHE="${REDIS_CACHE:-}"  # 必填
REDIS_QUEUE="${REDIS_QUEUE:-}"  # 必填

# 端口可覆盖
SOCKETIO_PORT="${SOCKETIO_PORT:-9000}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
NGINX_PORT="${NGINX_PORT:-8080}"

# 自动迁移（对已有站点执行 bench migrate）
AUTO_MIGRATE="${AUTO_MIGRATE:-true}"

echo "== ERPNext AIO 启动 =="
echo "DB_HOST=${DB_HOST}  DB_PORT=${DB_PORT}"
echo "REDIS_CACHE=${REDIS_CACHE}  REDIS_QUEUE=${REDIS_QUEUE}"
echo "BACKEND_PORT=${BACKEND_PORT}  SOCKETIO_PORT=${SOCKETIO_PORT}  NGINX_PORT=${NGINX_PORT}"

if [[ -z "$DB_HOST" ]]; then
  echo "❌ 缺少 DB_HOST；本镜像只支持外部数据库"
  exit 1
fi

# 让 bench 认识到镜像内已有 app
ls -1 apps > sites/apps.txt || true

# 标准化 Redis URL
norm_redis () {
  local v="$1"
  if [[ -z "$v" ]]; then echo ""; return; fi
  if [[ "$v" == redis://* ]]; then echo "$v"; else echo "redis://$v"; fi
}
RC="$(norm_redis "$REDIS_CACHE")"
RQ="$(norm_redis "$REDIS_QUEUE")"
[[ -z "$RC" || -z "$RQ" ]] && { echo "❌ 缺少 REDIS_CACHE / REDIS_QUEUE"; exit 1; }

# 写 common_site_config.json
bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g  redis_cache    "$RC"
bench set-config -g  redis_queue    "$RQ"
bench set-config -g  redis_socketio "$RQ"
bench set-config -gp socketio_port "$SOCKETIO_PORT"

# 可选：对现有站点做迁移
if [[ "$AUTO_MIGRATE" == "true" ]]; then
  echo "== bench --sites all migrate =="
  bench --sites all migrate || true
fi

# 生成 nginx 配置（官方脚本存在于基础镜像）
export BACKEND="127.0.0.1:${BACKEND_PORT}"
export SOCKETIO="127.0.0.1:${SOCKETIO_PORT}"
export FRAPPE_SITE_NAME_HEADER="${FRAPPE_SITE_NAME_HEADER:-\$host}"
export PROXY_READ_TIMEOUT="${PROXY_READ_TIMEOUT:-120}"
export CLIENT_MAX_BODY_SIZE="${CLIENT_MAX_BODY_SIZE:-50m}"
nginx-entrypoint.sh >/dev/null 2>&1 || true

# 替换 nginx 监听端口（默认 8080）
if [[ "$NGINX_PORT" != "8080" ]]; then
  sed -i "s/listen 8080;/listen ${NGINX_PORT};/"  config/nginx.conf || true
  sed -i "s/listen \[::\]:8080;/listen \[::\]:${NGINX_PORT};/" config/nginx.conf || true
fi

# 使用 supervisord 拉起各进程
exec /usr/bin/supervisord -c /opt/aio/supervisord.conf

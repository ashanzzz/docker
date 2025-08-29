#!/usr/bin/env bash
# erpnext15/aio/entrypoint.sh
# 单容器 AIO 启动脚本（仅外接数据库/Redis；不会内置 MariaDB/Redis）
# 特性：
# 1) 首次启动若不存在任何站点且 AUTO_SETUP=true，则自动创建站点并安装指定 apps
# 2) 后续启动可自动 migrate（MIGRATE_ON_START=true）
# 3) 所有 DB / Redis 只走“外接”，不在容器内启动

set -euo pipefail

BENCH_HOME="/home/frappe/frappe-bench"
cd "$BENCH_HOME"

# ===== 必填/可选环境变量 =====
# 数据库（外部）：
DB_HOST="${DB_HOST:-}"        # 必填：数据库主机，例如 192.168.8.19
DB_PORT="${DB_PORT:-3306}"    # 可选：默认 3306
DB_ROOT_USER="${DB_ROOT_USER:-root}"          # 自动建站时需要
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"      # 自动建站时需要

# Redis（外部）：支持两种写法
#  1) 片段：":password@host:6379"
#  2) 完整："redis://:password@host:6379"
REDIS_CACHE="${REDIS_CACHE:-}"  # 必填
REDIS_QUEUE="${REDIS_QUEUE:-}"  # 必填

# 站点与应用（用于首启自动建站）
AUTO_SETUP="${AUTO_SETUP:-true}"               # true=无站点时自动创建
SITE_NAME="${SITE_NAME:-}"                     # 例：mysite.example
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"           # 管理员密码
INSTALL_APPS_RAW="${INSTALL_APPS:-erpnext,payments,hrms,print_designer}" # 逗号或空格分隔
SET_DEFAULT_SITE="${SET_DEFAULT_SITE:-true}"   # 建站后设为默认站点

# 运行端口（容器内）
SOCKETIO_PORT="${SOCKETIO_PORT:-9000}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
NGINX_PORT="${NGINX_PORT:-8080}"

# 启动时迁移（对所有站点）
MIGRATE_ON_START="${MIGRATE_ON_START:-true}"

echo "== ERPNext AIO 启动 =="
echo "DB_HOST=${DB_HOST}  DB_PORT=${DB_PORT}"
echo "REDIS_CACHE=${REDIS_CACHE}  REDIS_QUEUE=${REDIS_QUEUE}"
echo "BACKEND_PORT=${BACKEND_PORT}  SOCKETIO_PORT=${SOCKETIO_PORT}  NGINX_PORT=${NGINX_PORT}"
echo "AUTO_SETUP=${AUTO_SETUP}  SITE_NAME=${SITE_NAME}  INSTALL_APPS=${INSTALL_APPS_RAW}"

if [[ -z "$DB_HOST" ]]; then
  echo "❌ 缺少 DB_HOST；本镜像只支持外部数据库"
  exit 1
fi
if [[ -z "$REDIS_CACHE" || -z "$REDIS_QUEUE" ]]; then
  echo "❌ 缺少 REDIS_CACHE / REDIS_QUEUE；示例：:123456@192.168.8.19:6379 或 redis://:123456@192.168.8.19:6379"
  exit 1
fi

# 让 bench 认识到镜像内已有 apps
ls -1 apps > sites/apps.txt || true

# 标准化 Redis URL
norm_redis () {
  local v="$1"
  if [[ -z "$v" ]]; then echo ""; return; fi
  if [[ "$v" == redis://* ]]; then echo "$v"; else echo "redis://$v"; fi
}
RC="$(norm_redis "$REDIS_CACHE")"
RQ="$(norm_redis "$REDIS_QUEUE")"

# 写 common_site_config.json（全局）
bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g  redis_cache    "$RC"
bench set-config -g  redis_queue    "$RQ"
bench set-config -g  redis_socketio "$RQ"
bench set-config -gp socketio_port "$SOCKETIO_PORT"

# 获取现有站点（排除 assets 目录）
find_first_site () {
  find sites -mindepth 1 -maxdepth 1 -type d \
    ! -name "assets" ! -name "logs" -printf "%f\n" | head -n1 || true
}
EXISTING_SITE="$(find_first_site || true)"

# ===== 首次启动：自动建站 + 安装 Apps =====
if [[ -z "$EXISTING_SITE" && "$AUTO_SETUP" == "true" ]]; then
  if [[ -z "$SITE_NAME" || -z "$ADMIN_PASSWORD" || -z "$DB_ROOT_PASSWORD" ]]; then
    echo "❌ AUTO_SETUP 启用但缺少 SITE_NAME / ADMIN_PASSWORD / DB_ROOT_PASSWORD"
    exit 1
  fi
  echo "== 未检测到站点，开始自动创建：$SITE_NAME =="

  # bench new-site
  bench new-site "$SITE_NAME" \
    --db-host "$DB_HOST" --db-port "$DB_PORT" \
    --mariadb-root-username "$DB_ROOT_USER" \
    --mariadb-root-password "$DB_ROOT_PASSWORD" \
    --admin-password "$ADMIN_PASSWORD" \
    --no-mariadb-socket

  # 解析 apps 列表（逗号或空格转空格）
  INSTALL_APPS="$(echo "$INSTALL_APPS_RAW" | tr ',' ' ')"
  for app in $INSTALL_APPS; do
    echo "== 安装应用：$app =="
    bench --site "$SITE_NAME" install-app "$app" || {
      echo "⚠️ 安装 $app 失败（可能 app 与当前 v15 不兼容或已安装），继续……"
    }
  done

  # 设为默认站点
  if [[ "$SET_DEFAULT_SITE" == "true" ]]; then
    bench config serve_default_site on
    bench use "$SITE_NAME"
  fi

  # 站点级缓存清理（可选）
  bench --site "$SITE_NAME" clear-cache || true
  bench --site "$SITE_NAME" clear-website-cache || true
else
  if [[ -n "$EXISTING_SITE" ]]; then
    echo "== 检测到已存在站点：$EXISTING_SITE，跳过自动建站 =="
  else
    echo "== 未检测到站点且 AUTO_SETUP=false，保持空站点目录 =="
  fi
fi

# 可选：对所有站点做迁移
if [[ "$MIGRATE_ON_START" == "true" ]]; then
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

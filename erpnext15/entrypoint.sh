#!/usr/bin/env bash
# 目的：
# 1) 在容器启动时，根据环境变量(DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD、SITE_NAME等)
#    动态写入 frappe 的 site_config.json / common_site_config.json，
#    从而连接外部数据库（无需容器内 MariaDB 卷）。
# 2) 如果检测到使用外部数据库，则禁用/移除 supervisord 对容器内 MariaDB 的管理配置，
#    避免“内部 MariaDB 启动失败导致循环重启”的问题。
# 3) 最后以和原镜像一致的方式启动 supervisord（保持原作者风格）。

set -Eeuo pipefail

# ---- 路径与默认值（尽量与原作者布局保持一致） ----
FRAPPE_HOME="/home/frappe/frappe-bench"
SITES_DIR="${FRAPPE_HOME}/sites"
DEFAULT_SITE="site1.local"

SITE_NAME="${SITE_NAME:-$DEFAULT_SITE}"     # 允许通过 env 指定站点名，默认 site1.local
SITE_DIR="${SITES_DIR}/${SITE_NAME}"
SITE_CFG="${SITE_DIR}/site_config.json"
COMMON_CFG="${SITES_DIR}/common_site_config.json"

# ---- 数据库相关环境变量（供 Unraid 的 Container Variable 配）----
# 你说希望使用以下5个变量；我也兼容 DB_USERNAME -> DB_USER
DB_HOST="${DB_HOST:-}"                       # 为空则认为使用容器内数据库（与原版一致）
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-${DB_USERNAME:-}}"
DB_PASSWORD="${DB_PASSWORD:-}"

# 行为控制：是否强制覆盖 site_config 已有的同名字段
FORCE_OVERWRITE_DB_CONFIG="${FORCE_OVERWRITE_DB_CONFIG:-false}"

# 行为控制：是否禁用容器内 MariaDB（默认：只要 DB_HOST 非本机/非空，就禁用）
DISABLE_INTERNAL_DB="${DISABLE_INTERNAL_DB:-}"
if [[ -z "${DISABLE_INTERNAL_DB}" ]]; then
  if [[ -n "${DB_HOST}" && "${DB_HOST}" != "127.0.0.1" && "${DB_HOST}" != "localhost" ]]; then
    DISABLE_INTERNAL_DB="true"
  else
    DISABLE_INTERNAL_DB="false"
  fi
fi

log() { echo "[entrypoint] $*"; }

# ---- 如果使用外部数据库，禁用容器内 MariaDB 的 supervisor 配置 ----
if [[ "${DISABLE_INTERNAL_DB}" == "true" ]]; then
  # 原作者脚本在 inDocker=yes 时会把 MariaDB/NGINX 的 conf 链接到 /etc/supervisor/conf.d/
  # 这里仅移除 MariaDB 的，保留 NGINX/FRAPPE 等其他程序不变，尊重原版。
  if [[ -f /etc/supervisor/conf.d/mariadb.conf ]]; then
    log "Detected external DB (DB_HOST=${DB_HOST}). Disabling internal MariaDB supervisor config..."
    sudo rm -f /etc/supervisor/conf.d/mariadb.conf || true
  fi
fi

# ---- 选定要写入的 site_config.json ----
if [[ ! -f "${SITE_CFG}" ]]; then
  log "WARN: ${SITE_CFG} not found. Will try to locate any site_config.json under ${SITES_DIR} ..."
  FIRST=$(find "${SITES_DIR}" -maxdepth 2 -name site_config.json 2>/dev/null | head -n1 || true)
  if [[ -n "${FIRST}" ]]; then
    SITE_CFG="${FIRST}"
    log "Using ${SITE_CFG}"
  else
    log "WARN: No site_config.json found. Skipping DB config injection."
  fi
fi

# ---- 写入 JSON（使用 Python，镜像里一定有 python3；避免依赖 jq）----
update_json_if_needed() {
python3 - <<'PY'
import json, os, sys

cfg = os.environ.get("CFG","")
force = os.environ.get("FORCE","false").lower()=="true"

# 仅把有值的变量写入（没提供的就不动）
env_map = {
  "db_host": os.environ.get("DB_HOST") or None,
  "db_port": os.environ.get("DB_PORT") or None,
  "db_name": os.environ.get("DB_NAME") or None,
  "db_password": os.environ.get("DB_PASSWORD") or None,
  # 注意：Frappe 传统上不依赖 db_user（它内部会用 site 派生用户名）。
  # 但你明确希望可写 DB_USER，这里保留为扩展字段，供外部自定义模块使用。
  "db_user": os.environ.get("DB_USER") or None,
}

if not cfg or not os.path.exists(cfg):
  print(f"[entrypoint] skip json update; site_config not found: {cfg}", file=sys.stderr)
  sys.exit(0)

with open(cfg, "r", encoding="utf-8") as f:
  try:
    data = json.load(f)
  except Exception:
    data = {}

changed = False
for k, v in env_map.items():
  if v is None: 
    continue
  # db_port 转成 int
  if k == "db_port":
    try:
      v = int(v)
    except Exception:
      pass
  if k in data and not force:
    # 已存在且未开启强制覆盖：跳过
    continue
  data[k] = v
  changed = True

if changed:
  with open(cfg, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
  print(f"[entrypoint] Updated {cfg}")
else:
  print("[entrypoint] No changes written.")
PY
}

if [[ -f "${SITE_CFG}" ]]; then
  export CFG="${SITE_CFG}" FORCE="${FORCE_OVERWRITE_DB_CONFIG}"
  export DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD
  update_json_if_needed
  # 保险起见保权限
  sudo chown -R frappe:frappe "${SITES_DIR}" || true
fi

# ---- 启动 supervisord（保持原镜像风格：sudo + supervisord 前台）----
# 原 Dockerfile 里是：ENTRYPOINT ["/bin/bash","-c"] + CMD ["sudo /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf"]
# 我们直接 exec，确保 PID 1 正确，信号转发正常。
exec sudo /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf

#!/usr/bin/env bash
set -euo pipefail

# ERPNext16 single-container AIO entrypoint
#
# Modes:
#   internal - run bundled MariaDB + Redis + ERPNext services
#   external - use externally provided DB/Redis and skip bundled DB/Redis supervisors

get_default_site_install_apps() {
  local apps="erpnext"
  if [ -d /home/frappe/frappe-bench/apps/ashan_cn_procurement ] || [ -e /opt/sites-skel/assets/ashan_cn_procurement ]; then
    apps="${apps},ashan_cn_procurement"
  fi
  printf '%s' "$apps"
}

require_non_empty() {
  local value="$1"
  local name="$2"
  if [ -z "$value" ]; then
    echo "[aio] Missing required variable: ${name}" >&2
    exit 1
  fi
}

normalize_mode() {
  local mode
  mode="$(printf '%s' "${AIO_MODE:-internal}" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    internal|external) printf '%s' "$mode" ;;
    *)
      echo "[aio] Unsupported AIO_MODE=${AIO_MODE:-}; expected internal or external" >&2
      exit 1
      ;;
  esac
}

write_common_site_config() {
  local mode="$1"
  local config_path=/home/frappe/frappe-bench/sites/common_site_config.json

  python3 - "$mode" "$config_path" <<'PY'
import json
import os
import pathlib
import sys

mode = sys.argv[1]
config_path = pathlib.Path(sys.argv[2])

def env(name, default=""):
    return os.environ.get(name, default)

if config_path.exists():
    try:
        data = json.loads(config_path.read_text())
    except Exception:
        data = {}
else:
    data = {}

if mode == "internal":
    data.update({
        "db_host": "127.0.0.1",
        "db_port": 3306,
        "redis_cache": f"redis://127.0.0.1:6379/{env('REDIS_CACHE_DB', '0')}",
        "redis_queue": f"redis://127.0.0.1:6379/{env('REDIS_QUEUE_DB', '1')}",
        "redis_socketio": f"redis://127.0.0.1:6379/{env('REDIS_SOCKETIO_DB', '2')}",
        "socketio_port": 9000,
    })
    data.pop('db_type', None)
    data.pop('db_name', None)
    data.pop('db_socket', None)
    data.pop('db_user', None)
    data.pop('db_password', None)
else:
    db_name = env('FRAPPE_DB_NAME') or env('SITE_NAME') or env('FRAPPE_DB_USER')
    data.update({
        "db_type": env('FRAPPE_DB_TYPE', 'mariadb'),
        "db_name": db_name,
        "db_host": env('FRAPPE_DB_HOST'),
        "db_port": int(env('FRAPPE_DB_PORT') or ('5432' if env('FRAPPE_DB_TYPE', 'mariadb') == 'postgres' else '3306')),
        "db_user": env('FRAPPE_DB_USER') or db_name,
        "db_password": env('FRAPPE_DB_PASSWORD'),
        "redis_cache": env('FRAPPE_REDIS_CACHE'),
        "redis_queue": env('FRAPPE_REDIS_QUEUE'),
        "redis_socketio": env('FRAPPE_REDIS_SOCKETIO'),
        "socketio_port": 9000,
    })
    db_socket = env('FRAPPE_DB_SOCKET')
    if db_socket:
        data['db_socket'] = db_socket
    else:
        data.pop('db_socket', None)

config_path.write_text(json.dumps(data, indent=1, sort_keys=True))
PY
}

site_install_apps_resolve() {
  local raw="${SITE_INSTALL_APPS:-}"
  if [ -z "$raw" ]; then
    get_default_site_install_apps
    return 0
  fi
  printf '%s' "$raw"
}

setup_nginx_config() {
  if [ -f /templates/nginx/frappe.conf.template ]; then
    echo "[aio] Generating nginx config..."
    : "${UPSTREAM_REAL_IP_ADDRESS:=127.0.0.1}"
    : "${UPSTREAM_REAL_IP_HEADER:=X-Forwarded-For}"
    : "${UPSTREAM_REAL_IP_RECURSIVE:=off}"
    : "${PROXY_READ_TIMEOUT:=120}"
    : "${CLIENT_MAX_BODY_SIZE:=50m}"

    export UPSTREAM_REAL_IP_ADDRESS UPSTREAM_REAL_IP_HEADER UPSTREAM_REAL_IP_RECURSIVE PROXY_READ_TIMEOUT CLIENT_MAX_BODY_SIZE

    mkdir -p /etc/nginx/conf.d
    envsubst '${BACKEND}
${SOCKETIO}
${UPSTREAM_REAL_IP_ADDRESS}
${UPSTREAM_REAL_IP_HEADER}
${UPSTREAM_REAL_IP_RECURSIVE}
${FRAPPE_SITE_NAME_HEADER}
${PROXY_READ_TIMEOUT}
${CLIENT_MAX_BODY_SIZE}'       </templates/nginx/frappe.conf.template >/etc/nginx/conf.d/frappe.conf

    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  fi
}

bootstrap_sites_volume() {
  local dst=/home/frappe/frappe-bench/sites
  local src=/opt/sites-skel
  local asset_build_id_file=.asset-build-id

  mkdir -p "$dst"

  for file in apps.txt apps.json common_site_config.json "$asset_build_id_file"; do
    if [ -f "$src/$file" ] && [ ! -f "$dst/$file" ]; then
      echo "[aio] Bootstrapping sites/$file"
      cp -a "$src/$file" "$dst/$file"
    fi
  done

  if [ -d "$src/assets" ] && [ ! -d "$dst/assets" ]; then
    echo "[aio] Bootstrapping sites/assets/"
    cp -a "$src/assets" "$dst/assets"
  fi

  chown -R frappe:frappe "$dst" || true
}

ensure_sites_dir_permissions() {
  local sites_dir=/home/frappe/frappe-bench/sites
  if ! su - frappe -c "test -w '${sites_dir}'" >/dev/null 2>&1; then
    echo "[aio] Fixing permissions for sites volume..."
    chown -R frappe:frappe "$sites_dir" || true
    chmod 775 "$sites_dir" || true
  fi
}

write_default_sites_metadata() {
  local sites_dir=/home/frappe/frappe-bench/sites

  if [ ! -f "${sites_dir}/apps.txt" ]; then
    echo "[aio] Bootstrapping sites/apps.txt..."
    {
      printf 'frappe
'
      printf 'erpnext
'
      if [ -d /home/frappe/frappe-bench/apps/ashan_cn_procurement ] || [ -e /opt/sites-skel/assets/ashan_cn_procurement ]; then
        printf 'ashan_cn_procurement
'
      fi
    } >"${sites_dir}/apps.txt"
    chown frappe:frappe "${sites_dir}/apps.txt" || true
  fi

  if [ ! -f "${sites_dir}/apps.json" ]; then
    echo "[aio] Bootstrapping sites/apps.json..."
    cat >"${sites_dir}/apps.json" <<'EOF'
[
  {"url":"https://github.com/frappe/frappe","branch":"version-16"},
  {"url":"https://github.com/frappe/erpnext","branch":"version-16"}
]
EOF
    chown frappe:frappe "${sites_dir}/apps.json" || true
  fi

  if [ ! -f "${sites_dir}/common_site_config.json" ]; then
    echo "[aio] Bootstrapping sites/common_site_config.json..."
    echo '{}' >"${sites_dir}/common_site_config.json"
    chown frappe:frappe "${sites_dir}/common_site_config.json" || true
  fi
}

refresh_bundled_assets_if_needed() {
  local dst=/home/frappe/frappe-bench/sites
  local src=/opt/sites-skel
  local asset_build_id_file=.asset-build-id
  local src_id="$src/$asset_build_id_file"
  local dst_id="$dst/$asset_build_id_file"

  if [ ! -f "$src_id" ]; then
    echo "[aio] No bundled asset build id found in image; skipping asset refresh"
    return 0
  fi

  if [ ! -f "$dst_id" ] || ! cmp -s "$src_id" "$dst_id" || [ ! -d "$dst/assets" ]; then
    if [ -f "$dst_id" ]; then
      echo "[aio] Bundled asset build id changed or assets missing; refreshing assets"
    else
      echo "[aio] Bootstrapping bundled assets from image"
    fi

    rm -rf "$dst/assets"
    if [ -d "$src/assets" ]; then
      cp -a "$src/assets" "$dst/assets"
    fi

    for file in apps.txt apps.json common_site_config.json "$asset_build_id_file"; do
      if [ -e "$src/$file" ]; then
        cp -a "$src/$file" "$dst/$file"
      fi
    done

    ASSET_BUNDLE_REFRESHED=1
  fi

  chown -R frappe:frappe "$dst" || true
}

clear_site_cache_after_asset_refresh() {
  local site_name="$1"
  if [ "${ASSET_BUNDLE_REFRESHED:-0}" != "1" ]; then
    return 0
  fi

  echo "[aio] Clearing site cache after asset refresh..."
  su - frappe -c "cd /home/frappe/frappe-bench && bench --site '${site_name}' clear-cache" || true
  su - frappe -c "cd /home/frappe/frappe-bench && bench --site '${site_name}' clear-website-cache" || true
}

wait_for_mariadb_ready() {
  local label="${1:-MariaDB}"
  local timeout_seconds="${2:-900}"
  local sleep_seconds=2
  local attempts=$(( timeout_seconds / sleep_seconds ))
  if [ "$attempts" -lt 1 ]; then attempts=1; fi

  echo "[aio] Waiting for ${label} to be ready (timeout=${timeout_seconds}s)..."
  for i in $(seq 1 "$attempts"); do
    if mariadb-admin --socket=/run/mysqld/mysqld.sock ping >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
  done

  echo "[aio] ${label} did not become ready within ${timeout_seconds}s" >&2
  return 1
}

wait_for_redis_ready() {
  local timeout_seconds="${1:-120}"
  local sleep_seconds=2
  local attempts=$(( timeout_seconds / sleep_seconds ))
  if [ "$attempts" -lt 1 ]; then attempts=1; fi

  echo "[aio] Waiting for Redis to be ready (timeout=${timeout_seconds}s)..."
  for i in $(seq 1 "$attempts"); do
    if redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
  done

  echo "[aio] Redis did not become ready within ${timeout_seconds}s" >&2
  return 1
}

ensure_site_apps() {
  local site_name="$1"
  local raw_apps="${SITE_INSTALL_APPS}"
  local installed_apps

  installed_apps=$(su - frappe -c "cd /home/frappe/frappe-bench && bench --site '${site_name}' list-apps" | tr -d '
' || true)

  IFS=',' read -r -a requested_apps <<< "$raw_apps"
  for app in "${requested_apps[@]}"; do
    app="${app// /}"
    [ -z "$app" ] && continue

    if printf '%s
' "$installed_apps" | grep -qx "$app"; then
      echo "[aio] Site ${site_name} already has app: ${app}"
      continue
    fi

    echo "[aio] Installing missing app on ${site_name}: ${app}"
    su - frappe -c "cd /home/frappe/frappe-bench && bench --site '${site_name}' install-app '${app}'"
    installed_apps=$(printf '%s
%s
' "$installed_apps" "$app")
  done
}

run_site_migrate() {
  local site_name="$1"

  if [ "${SITE_AUTO_MIGRATE}" != "1" ]; then
    echo "[aio] SITE_AUTO_MIGRATE=${SITE_AUTO_MIGRATE}; skipping bench migrate"
    return
  fi

  echo "[aio] Running bench migrate for ${site_name}"
  su - frappe -c "cd /home/frappe/frappe-bench && bench --site '${site_name}' migrate"
}

start_supervisor() {
  /usr/bin/supervisord -c /etc/supervisor/supervisord.conf &
  SUP_PID=$!
}

cleanup() {
  echo "[aio] Caught signal, stopping supervisord..."
  kill -TERM "$SUP_PID" 2>/dev/null || true
}

main() {
  : "${SITE_NAME:=site1.local}"
  : "${ADMIN_PASSWORD:=adminpassword}"
  : "${MARIADB_ROOT_PASSWORD:=mysqlpassword}"
  : "${MARIADB_USER_HOST_LOGIN_SCOPE:=localhost}"
  : "${SITE_INSTALL_APPS:=$(get_default_site_install_apps)}"
  : "${SITE_AUTO_MIGRATE:=1}"
  : "${AIO_MODE:=internal}"
  : "${MARIADB_READY_TIMEOUT_SECONDS:=900}"
  : "${REDIS_CACHE_DB:=0}"
  : "${REDIS_QUEUE_DB:=1}"
  : "${REDIS_SOCKETIO_DB:=2}"
  : "${FRAPPE_DB_TYPE:=mariadb}"
  : "${FRAPPE_DB_HOST:=}"
  : "${FRAPPE_DB_PORT:=}"
  : "${FRAPPE_DB_NAME:=}"
  : "${FRAPPE_DB_USER:=}"
  : "${FRAPPE_DB_PASSWORD:=}"
  : "${FRAPPE_REDIS_CACHE:=}"
  : "${FRAPPE_REDIS_QUEUE:=}"
  : "${FRAPPE_REDIS_SOCKETIO:=}"
  : "${FRAPPE_DB_SOCKET:=}"
  : "${FRAPPE_DB_ROOT_PASSWORD:=}"
  : "${FRAPPE_SITE_NAME_HEADER:=$SITE_NAME}"
  : "${BACKEND:=127.0.0.1:8000}"
  : "${SOCKETIO:=127.0.0.1:9000}"

  AIO_MODE="$(normalize_mode)"
  SITE_INSTALL_APPS="$(site_install_apps_resolve)"
  export SITE_NAME ADMIN_PASSWORD MARIADB_ROOT_PASSWORD MARIADB_USER_HOST_LOGIN_SCOPE
  export SITE_INSTALL_APPS SITE_AUTO_MIGRATE AIO_MODE MARIADB_READY_TIMEOUT_SECONDS
  export REDIS_CACHE_DB REDIS_QUEUE_DB REDIS_SOCKETIO_DB
  export FRAPPE_DB_TYPE FRAPPE_DB_HOST FRAPPE_DB_PORT FRAPPE_DB_NAME FRAPPE_DB_USER FRAPPE_DB_PASSWORD
  export FRAPPE_REDIS_CACHE FRAPPE_REDIS_QUEUE FRAPPE_REDIS_SOCKETIO FRAPPE_DB_SOCKET FRAPPE_DB_ROOT_PASSWORD
  export FRAPPE_SITE_NAME_HEADER BACKEND SOCKETIO

  mkdir -p /run/mysqld /var/lib/redis /var/log/supervisor
  chown -R mysql:mysql /run/mysqld /var/lib/mysql || true
  chown -R redis:redis /var/lib/redis || true

  bootstrap_sites_volume
  refresh_bundled_assets_if_needed
  ensure_sites_dir_permissions
  write_default_sites_metadata

  setup_nginx_config
  start_supervisor

  trap cleanup SIGTERM SIGINT

  if [ "$AIO_MODE" = "external" ]; then
    echo "[aio] Running in EXTERNAL mode: bundled MariaDB/Redis will stay disabled"
    require_non_empty "${FRAPPE_DB_HOST:-}" "FRAPPE_DB_HOST"
    require_non_empty "${FRAPPE_REDIS_CACHE:-}" "FRAPPE_REDIS_CACHE"
    require_non_empty "${FRAPPE_REDIS_QUEUE:-}" "FRAPPE_REDIS_QUEUE"
    require_non_empty "${FRAPPE_REDIS_SOCKETIO:-}" "FRAPPE_REDIS_SOCKETIO"
    echo "[aio] External mode expects the target database and user to already exist; bench will not create them."
    if [ -z "${FRAPPE_DB_PORT:-}" ]; then
      case "${FRAPPE_DB_TYPE:-mariadb}" in
        mariadb) FRAPPE_DB_PORT=3306 ;;
        postgres) FRAPPE_DB_PORT=5432 ;;
        *) echo "[aio] Unsupported FRAPPE_DB_TYPE=${FRAPPE_DB_TYPE:-}" >&2; exit 1 ;;
      esac
      export FRAPPE_DB_PORT
    fi
    if [ -z "${FRAPPE_DB_NAME:-}" ]; then
      FRAPPE_DB_NAME="${SITE_NAME}"
      export FRAPPE_DB_NAME
    fi
    if [ -z "${FRAPPE_DB_USER:-}" ]; then
      FRAPPE_DB_USER="${FRAPPE_DB_NAME}"
      export FRAPPE_DB_USER
    fi
    require_non_empty "${FRAPPE_DB_NAME:-}" "FRAPPE_DB_NAME or SITE_NAME"
    require_non_empty "${FRAPPE_DB_USER:-}" "FRAPPE_DB_USER"
    write_common_site_config external
  else
    if [ ! -d /var/lib/mysql/mysql ]; then
      echo "[aio] Initializing MariaDB data directory..."
      if mariadb-install-db --help 2>/dev/null | grep -q -- '--auth-root-authentication-method'; then
        mariadb-install-db --user=mysql --datadir=/var/lib/mysql --auth-root-authentication-method=normal >/dev/null
      else
        mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null
      fi
    fi
    write_common_site_config internal
  fi

  if [ "$AIO_MODE" = "internal" ]; then
    rm -f /run/mysqld/mysqld.sock /run/mysqld/mysqld.pid /run/mysqld/skip-grants.pid 2>/dev/null || true
    supervisorctl start mariadb redis || true
    wait_for_mariadb_ready "MariaDB" "$MARIADB_READY_TIMEOUT_SECONDS"
    wait_for_redis_ready 120 || true
  else
    supervisorctl stop mariadb redis >/dev/null 2>&1 || true
  fi

  if [ ! -d "/home/frappe/frappe-bench/sites/${SITE_NAME}" ]; then
    echo "[aio] Creating site: ${SITE_NAME}"
    if [ "$AIO_MODE" = "internal" ]; then
      su - frappe -c "cd /home/frappe/frappe-bench && bench new-site --mariadb-user-host-login-scope='${MARIADB_USER_HOST_LOGIN_SCOPE}' --db-root-password '${MARIADB_ROOT_PASSWORD}' --admin-password '${ADMIN_PASSWORD}' --install-app erpnext '${SITE_NAME}'"
    else
      require_non_empty "${FRAPPE_DB_USER:-}" "FRAPPE_DB_USER"
      require_non_empty "${FRAPPE_DB_PASSWORD:-}" "FRAPPE_DB_PASSWORD"
      su - frappe -c "cd /home/frappe/frappe-bench && bench new-site '${SITE_NAME}' --db-type '${FRAPPE_DB_TYPE}' --db-name '${FRAPPE_DB_NAME}' --db-host '${FRAPPE_DB_HOST}' --db-port '${FRAPPE_DB_PORT}' --db-user '${FRAPPE_DB_USER}' --db-password '${FRAPPE_DB_PASSWORD}' --no-setup-db --admin-password '${ADMIN_PASSWORD}' --install-app erpnext"
    fi
  else
    echo "[aio] Site exists: ${SITE_NAME}"
  fi

  ensure_site_apps "${SITE_NAME}"
  run_site_migrate "${SITE_NAME}"
  clear_site_cache_after_asset_refresh "${SITE_NAME}"

  supervisorctl start backend websocket worker scheduler nginx

  echo "[aio] Ready. ERPNext is reachable on :8080 in ${AIO_MODE} mode"

  wait "$SUP_PID"
}

main "$@"

#!/usr/bin/env bash
set -Eeuo pipefail

BENCH="/home/frappe/frappe-bench"
SITES="${BENCH}/sites"
SKEL="/opt/sites-skel"

log() {
  printf '[aio] %s\n' "$*"
}

die() {
  printf '[aio] ERROR: %s\n' "$*" >&2
  exit 1
}

required_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Missing required environment variable: ${name}"
}

normalize_settings() {
  : "${SITE_NAME:=site1.local}"
  : "${ADMIN_PASSWORD:=adminpassword}"
  : "${FRAPPE_DB_TYPE:=mariadb}"
  : "${FRAPPE_DB_PORT:=3306}"
  : "${FRAPPE_DB_NAME:=${SITE_NAME}}"
  : "${FRAPPE_DB_USER:=${FRAPPE_DB_NAME}}"
  : "${FRAPPE_SITE_NAME_HEADER:=${SITE_NAME}}"
  : "${BACKEND:=127.0.0.1:8000}"
  : "${SOCKETIO:=127.0.0.1:9000}"

  export \
    SITE_NAME \
    ADMIN_PASSWORD \
    FRAPPE_DB_TYPE \
    FRAPPE_DB_HOST \
    FRAPPE_DB_PORT \
    FRAPPE_DB_NAME \
    FRAPPE_DB_USER \
    FRAPPE_DB_PASSWORD \
    FRAPPE_REDIS_CACHE \
    FRAPPE_REDIS_QUEUE \
    FRAPPE_REDIS_SOCKETIO \
    FRAPPE_SITE_NAME_HEADER \
    BACKEND \
    SOCKETIO
}

validate_settings() {
  [[ "$FRAPPE_DB_TYPE" == "mariadb" ]] || \
    die "External-only image currently supports FRAPPE_DB_TYPE=mariadb."

  required_env FRAPPE_DB_HOST
  required_env FRAPPE_DB_PORT
  required_env FRAPPE_DB_NAME
  required_env FRAPPE_DB_USER
  required_env FRAPPE_DB_PASSWORD
  required_env FRAPPE_REDIS_CACHE
  required_env FRAPPE_REDIS_QUEUE
  required_env FRAPPE_REDIS_SOCKETIO
}

wait_for_tcp() {
  local label="$1"
  local host="$2"
  local port="$3"
  local timeout="${4:-120}"

  log "Waiting for ${label}: ${host}:${port}"

  python3 - "$label" "$host" "$port" "$timeout" <<'PY'
import socket
import sys
import time

label, host, port, timeout = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
deadline = time.time() + timeout
last_error = None

while time.time() < deadline:
    try:
        with socket.create_connection((host, port), timeout=3):
            print(f"[aio] {label} reachable")
            raise SystemExit(0)
    except OSError as exc:
        last_error = exc
        time.sleep(2)

print(f"[aio] ERROR: {label} not reachable: {last_error}", file=sys.stderr)
raise SystemExit(1)
PY
}

wait_for_redis_url() {
  local label="$1"
  local url="$2"

  python3 - "$label" "$url" <<'PY'
import socket
import sys
import time
from urllib.parse import urlparse

label, url = sys.argv[1], sys.argv[2]
parsed = urlparse(url)

if parsed.scheme not in {"redis", "rediss"}:
    raise SystemExit(f"[aio] ERROR: invalid {label} URL: {url}")

host = parsed.hostname
port = parsed.port or 6379

if not host:
    raise SystemExit(f"[aio] ERROR: missing host in {label} URL")

deadline = time.time() + 120
last_error = None

while time.time() < deadline:
    try:
        with socket.create_connection((host, port), timeout=3):
            print(f"[aio] {label} reachable: {host}:{port}")
            raise SystemExit(0)
    except OSError as exc:
        last_error = exc
        time.sleep(2)

print(f"[aio] ERROR: {label} not reachable: {last_error}", file=sys.stderr)
raise SystemExit(1)
PY
}

bootstrap_sites() {
  mkdir -p "$SITES"

  if [[ ! -f "$SITES/common_site_config.json" && -f "$SKEL/common_site_config.json" ]]; then
    cp -a "$SKEL/common_site_config.json" "$SITES/common_site_config.json"
  fi

  if [[ ! -d "$SITES/assets" && -d "$SKEL/assets" ]]; then
    cp -a "$SKEL/assets" "$SITES/assets"
  fi

  chown -R frappe:frappe "$SITES" || true
}

normalize_apps_txt() {
  # This is intentionally deterministic. The image contains exactly these apps.
  # It also repairs the historical malformed value:
  # erpnextashan_cn_procurement
  printf 'frappe\nerpnext\nashan_cn_procurement\n' > "$SITES/apps.txt"
  chown frappe:frappe "$SITES/apps.txt"
}

write_runtime_config() {
  python3 - "$SITES/common_site_config.json" <<'PY'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])

try:
    data = json.loads(path.read_text()) if path.exists() else {}
except Exception:
    data = {}

data.update(
    {
        "db_type": os.environ["FRAPPE_DB_TYPE"],
        "db_host": os.environ["FRAPPE_DB_HOST"],
        "db_port": int(os.environ["FRAPPE_DB_PORT"]),
        "db_name": os.environ["FRAPPE_DB_NAME"],
        "db_user": os.environ["FRAPPE_DB_USER"],
        "db_password": os.environ["FRAPPE_DB_PASSWORD"],
        "redis_cache": os.environ["FRAPPE_REDIS_CACHE"],
        "redis_queue": os.environ["FRAPPE_REDIS_QUEUE"],
        "redis_socketio": os.environ["FRAPPE_REDIS_SOCKETIO"],
        "socketio_port": 9000,
    }
)

path.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n")
PY

  chown frappe:frappe "$SITES/common_site_config.json"
}

refresh_image_assets() {
  local image_id="$SKEL/.image-build-id"
  local live_id="$SITES/.image-build-id"

  [[ -f "$image_id" ]] || return 0

  if [[ ! -f "$live_id" ]] || ! cmp -s "$image_id" "$live_id"; then
    log "Image assets changed; refreshing generated assets."

    rm -rf "$SITES/assets"

    if [[ -d "$SKEL/assets" ]]; then
      cp -a "$SKEL/assets" "$SITES/assets"
    else
      mkdir -p "$SITES/assets"
    fi

    cp -a "$image_id" "$live_id"
    chown -R frappe:frappe "$SITES/assets" "$live_id" || true
  fi
}

ensure_ashan_asset_link() {
  local source="$BENCH/apps/ashan_cn_procurement/ashan_cn_procurement/public"
  local target="$SITES/assets/ashan_cn_procurement"

  [[ -d "$source" ]] || return 0

  mkdir -p "$SITES/assets"

  if [[ -e "$target" || -L "$target" ]]; then
    rm -rf "$target"
  fi

  ln -s "$source" "$target"
  chown -h frappe:frappe "$target" || true
}

site_exists() {
  [[ -d "$SITES/$SITE_NAME" ]]
}

create_site() {
  log "Creating site ${SITE_NAME} using pre-created external MariaDB database."

  su - frappe -c "
    cd '$BENCH' &&
    bench new-site '$SITE_NAME' \
      --db-type '$FRAPPE_DB_TYPE' \
      --db-name '$FRAPPE_DB_NAME' \
      --db-host '$FRAPPE_DB_HOST' \
      --db-port '$FRAPPE_DB_PORT' \
      --db-user '$FRAPPE_DB_USER' \
      --db-password '$FRAPPE_DB_PASSWORD' \
      --no-setup-db \
      --admin-password '$ADMIN_PASSWORD' \
      --install-app erpnext
  "
}

installed_apps() {
  su - frappe -c "
    cd '$BENCH' &&
    bench --site '$SITE_NAME' list-apps
  "
}

site_has_app() {
  local app="$1"
  installed_apps | awk '{print $1}' | grep -qxF "$app"
}

ensure_site_apps() {
  if ! site_has_app erpnext; then
    log "Installing ERPNext on ${SITE_NAME}"
    su - frappe -c "cd '$BENCH' && bench --site '$SITE_NAME' install-app erpnext"
  else
    log "ERPNext already installed on ${SITE_NAME}"
  fi

  if ! site_has_app ashan_cn_procurement; then
    log "Installing ashan_cn_procurement on ${SITE_NAME}"
    su - frappe -c "cd '$BENCH' && bench --site '$SITE_NAME' install-app ashan_cn_procurement"
  else
    log "ashan_cn_procurement already installed on ${SITE_NAME}"
  fi
}

migrate_site() {
  log "Migrating ${SITE_NAME}"
  su - frappe -c "cd '$BENCH' && bench --site '$SITE_NAME' migrate"

  su - frappe -c "cd '$BENCH' && bench --site '$SITE_NAME' clear-cache" || true
  su - frappe -c "cd '$BENCH' && bench --site '$SITE_NAME' clear-website-cache" || true
}

setup_nginx() {
  local template="/templates/nginx/frappe.conf.template"

  [[ -f "$template" ]] || die "Missing nginx template: $template"

  : "${UPSTREAM_REAL_IP_ADDRESS:=127.0.0.1}"
  : "${UPSTREAM_REAL_IP_HEADER:=X-Forwarded-For}"
  : "${UPSTREAM_REAL_IP_RECURSIVE:=off}"
  : "${PROXY_READ_TIMEOUT:=120}"
  : "${CLIENT_MAX_BODY_SIZE:=50m}"

  export \
    UPSTREAM_REAL_IP_ADDRESS \
    UPSTREAM_REAL_IP_HEADER \
    UPSTREAM_REAL_IP_RECURSIVE \
    PROXY_READ_TIMEOUT \
    CLIENT_MAX_BODY_SIZE

  mkdir -p /etc/nginx/conf.d

  envsubst '${BACKEND}
${SOCKETIO}
${UPSTREAM_REAL_IP_ADDRESS}
${UPSTREAM_REAL_IP_HEADER}
${UPSTREAM_REAL_IP_RECURSIVE}
${FRAPPE_SITE_NAME_HEADER}
${PROXY_READ_TIMEOUT}
${CLIENT_MAX_BODY_SIZE}' \
    < "$template" \
    > /etc/nginx/conf.d/frappe.conf

  rm -f /etc/nginx/sites-enabled/default
  nginx -t
}

main() {
  normalize_settings
  validate_settings

  log "Architecture: external MariaDB + external Redis only."
  log "Site: ${SITE_NAME}"

  bootstrap_sites
  normalize_apps_txt
  write_runtime_config
  refresh_image_assets
  normalize_apps_txt
  ensure_ashan_asset_link

  wait_for_tcp "MariaDB" "$FRAPPE_DB_HOST" "$FRAPPE_DB_PORT"
  wait_for_redis_url "Redis cache" "$FRAPPE_REDIS_CACHE"
  wait_for_redis_url "Redis queue" "$FRAPPE_REDIS_QUEUE"
  wait_for_redis_url "Redis socketio" "$FRAPPE_REDIS_SOCKETIO"

  setup_nginx

  if site_exists; then
    log "Site exists: ${SITE_NAME}"
  else
    create_site
  fi

  ensure_site_apps
  migrate_site

  # migrate may touch assets/apps metadata; enforce the immutable-image contract.
  normalize_apps_txt
  ensure_ashan_asset_link

  log "Startup preparation completed. Starting application services."

  exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
}

main "$@"

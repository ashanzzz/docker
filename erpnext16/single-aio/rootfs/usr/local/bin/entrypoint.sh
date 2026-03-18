#!/usr/bin/env bash
set -euo pipefail

# ERPNext16 single-container AIO entrypoint

: "${SITE_NAME:=site1.local}"
: "${ADMIN_PASSWORD:=admin}"
: "${MARIADB_ROOT_PASSWORD:=ChangeMe_Strong_DB_Password}"
: "${MARIADB_USER_HOST_LOGIN_SCOPE:=localhost}"  # Fix auth when client connects as 'localhost'

# nginx-entrypoint.sh expects these; we use local ports
: "${FRAPPE_SITE_NAME_HEADER:=$SITE_NAME}"
: "${BACKEND:=127.0.0.1:8000}"
: "${SOCKETIO:=127.0.0.1:9000}"

mkdir -p /run/mysqld /var/lib/redis /var/log/supervisor
chown -R mysql:mysql /run/mysqld /var/lib/mysql || true
chown -R redis:redis /var/lib/redis || true

# If /home/frappe/frappe-bench/sites is mounted as an empty volume, it will hide the
# default apps.txt + assets/ shipped in the image. Bootstrap missing files from /opt/sites-skel.
bootstrap_sites_volume() {
  local dst=/home/frappe/frappe-bench/sites
  local src=/opt/sites-skel

  mkdir -p "$dst"

  if [ -f "$src/apps.txt" ] && [ ! -f "$dst/apps.txt" ]; then
    echo "[aio] Bootstrapping sites/apps.txt"
    cp -a "$src/apps.txt" "$dst/apps.txt"
  fi

  if [ -f "$src/apps.json" ] && [ ! -f "$dst/apps.json" ]; then
    echo "[aio] Bootstrapping sites/apps.json"
    cp -a "$src/apps.json" "$dst/apps.json"
  fi

  if [ -f "$src/common_site_config.json" ] && [ ! -f "$dst/common_site_config.json" ]; then
    echo "[aio] Bootstrapping sites/common_site_config.json"
    cp -a "$src/common_site_config.json" "$dst/common_site_config.json"
  fi

  if [ -d "$src/assets" ] && [ ! -d "$dst/assets" ]; then
    echo "[aio] Bootstrapping sites/assets/"
    cp -a "$src/assets" "$dst/assets"
  fi

  chown -R frappe:frappe "$dst" || true
}
bootstrap_sites_volume

# Initialize MariaDB datadir if empty
if [ ! -d /var/lib/mysql/mysql ]; then
  echo "[aio] Initializing MariaDB data directory..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null
fi

# Generate nginx config for Frappe (listen 8080; route to local backend/socketio)
# We intentionally DO NOT call upstream nginx-entrypoint.sh because it would start nginx and block.
if [ -f /templates/nginx/frappe.conf.template ]; then
  echo "[aio] Generating nginx config..."
  : "${UPSTREAM_REAL_IP_ADDRESS:=127.0.0.1}"
  : "${UPSTREAM_REAL_IP_HEADER:=X-Forwarded-For}"
  : "${UPSTREAM_REAL_IP_RECURSIVE:=off}"
  : "${PROXY_READ_TIMEOUT:=120}"
  : "${CLIENT_MAX_BODY_SIZE:=50m}"

  mkdir -p /etc/nginx/conf.d
  envsubst '${BACKEND}
  ${SOCKETIO}
  ${UPSTREAM_REAL_IP_ADDRESS}
  ${UPSTREAM_REAL_IP_HEADER}
  ${UPSTREAM_REAL_IP_RECURSIVE}
  ${FRAPPE_SITE_NAME_HEADER}
  ${PROXY_READ_TIMEOUT}
  ${CLIENT_MAX_BODY_SIZE}' \
    </templates/nginx/frappe.conf.template >/etc/nginx/conf.d/frappe.conf

  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
fi

# Start supervisor (only mariadb+redis autostart)
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf &
SUP_PID=$!

SITES_DIR=/home/frappe/frappe-bench/sites

# Ensure frappe can write to the mounted sites volume (Unraid often creates root-owned dirs)
if ! su - frappe -c "test -w '${SITES_DIR}'" >/dev/null 2>&1; then
  echo "[aio] Fixing permissions for sites volume..."
  chown -R frappe:frappe "${SITES_DIR}" || true
  chmod 775 "${SITES_DIR}" || true
fi

# When users mount an empty volume to /home/frappe/frappe-bench/sites,
# the image-provided metadata files (apps.txt/apps.json/common_site_config.json)
# are hidden and bench will crash. Bootstrap minimal required files.
if [ ! -f "${SITES_DIR}/apps.txt" ]; then
  echo "[aio] Bootstrapping sites/apps.txt..."
  cat >"${SITES_DIR}/apps.txt" <<'EOF'
frappe
erpnext
EOF
  chown frappe:frappe "${SITES_DIR}/apps.txt" || true
fi

if [ ! -f "${SITES_DIR}/apps.json" ]; then
  echo "[aio] Bootstrapping sites/apps.json..."
  cat >"${SITES_DIR}/apps.json" <<'EOF'
[
  {"url":"https://github.com/frappe/frappe","branch":"version-16"},
  {"url":"https://github.com/frappe/erpnext","branch":"version-16"}
]
EOF
  chown frappe:frappe "${SITES_DIR}/apps.json" || true
fi

if [ ! -f "${SITES_DIR}/common_site_config.json" ]; then
  echo "[aio] Bootstrapping sites/common_site_config.json..."
  echo '{}' >"${SITES_DIR}/common_site_config.json"
  chown frappe:frappe "${SITES_DIR}/common_site_config.json" || true
fi

cleanup() {
  echo "[aio] Caught signal, stopping supervisord..."
  kill -TERM "$SUP_PID" 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT

# Wait for MariaDB socket
echo "[aio] Waiting for MariaDB to be ready..."
for i in $(seq 1 60); do
  if mariadb-admin --socket=/run/mysqld/mysqld.sock ping >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [ "$i" = "60" ]; then
    echo "[aio] MariaDB did not become ready" >&2
    exit 1
  fi
done

# Ensure root password / remote root exists (best-effort)
# We connect via unix socket as root.
echo "[aio] Ensuring MariaDB root password..."
# Try socket auth (fresh install), then try with password (when reusing volumes)
if mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot -e 'SELECT 1' >/dev/null 2>&1; then
  ROOT_AUTH=(mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot)
elif mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot -p"${MARIADB_ROOT_PASSWORD}" -e 'SELECT 1' >/dev/null 2>&1; then
  ROOT_AUTH=(mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot -p"${MARIADB_ROOT_PASSWORD}")
else
  echo "[aio] ERROR: cannot connect to MariaDB as root (socket)" >&2
  exit 1
fi

"${ROOT_AUTH[@]}" <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# Configure common_site_config to use local services
su - frappe -c "cd /home/frappe/frappe-bench && \
  bench set-config -g db_host 127.0.0.1 && \
  bench set-config -gp db_port 3306 && \
  bench set-config -g redis_cache 'redis://127.0.0.1:6379' && \
  bench set-config -g redis_queue 'redis://127.0.0.1:6379' && \
  bench set-config -g redis_socketio 'redis://127.0.0.1:6379' && \
  bench set-config -gp socketio_port 9000" || true

# Create site if missing
if [ ! -d "/home/frappe/frappe-bench/sites/${SITE_NAME}" ]; then
  echo "[aio] Creating site: ${SITE_NAME}"
  su - frappe -c "cd /home/frappe/frappe-bench && \
    bench new-site --mariadb-user-host-login-scope='${MARIADB_USER_HOST_LOGIN_SCOPE}' \
      --db-root-password '${MARIADB_ROOT_PASSWORD}' \
      --admin-password '${ADMIN_PASSWORD}' \
      --install-app erpnext \
      '${SITE_NAME}'"
else
  echo "[aio] Site exists: ${SITE_NAME}"
fi

# Start ERPNext processes
supervisorctl start backend websocket worker scheduler nginx

echo "[aio] Ready. ERPNext should be reachable on :8080"

wait "$SUP_PID"

#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--yes" ]]; then
  cat <<'EOF'
Usage:
  aio-reset.sh --yes

What it does:
  1. Backs up current sites/mysql/redis data
  2. Clears runtime data
  3. Terminates PID 1 so Docker restart policy recreates a fresh system

Backups are stored in:
  /home/frappe/frappe-bench/sites/.aio-reset-backups/<timestamp>/
EOF
  exit 1
fi

: "${SITE_NAME:=site1.local}"
SITES_DIR=/home/frappe/frappe-bench/sites
MYSQL_DIR=/var/lib/mysql
REDIS_DIR=/var/lib/redis
BACKUP_ROOT="${SITES_DIR}/.aio-reset-backups"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"

mkdir -p "$BACKUP_DIR"

cat >"${BACKUP_DIR}/metadata.txt" <<EOF
timestamp=${STAMP}
site_name=${SITE_NAME}
backup_root=${BACKUP_DIR}
EOF

echo "[aio-reset] Stopping services..."
supervisorctl stop nginx scheduler worker websocket backend >/dev/null 2>&1 || true
supervisorctl stop redis mariadb >/dev/null 2>&1 || true
sleep 5

echo "[aio-reset] Backing up current data to ${BACKUP_DIR} ..."
tar --exclude='.aio-reset-backups' -czf "${BACKUP_DIR}/sites.tar.gz" -C "$SITES_DIR" .
tar -czf "${BACKUP_DIR}/mysql.tar.gz" -C "$MYSQL_DIR" .
tar -czf "${BACKUP_DIR}/redis.tar.gz" -C "$REDIS_DIR" .

echo "[aio-reset] Clearing runtime data..."
find "$SITES_DIR" -mindepth 1 -maxdepth 1 ! -name '.aio-reset-backups' -exec rm -rf {} +
find "$MYSQL_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
find "$REDIS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
sync

echo "[aio-reset] Reset complete. Backup saved to ${BACKUP_DIR}"
echo "[aio-reset] Restarting container so entrypoint can provision a fresh system..."
kill -TERM 1

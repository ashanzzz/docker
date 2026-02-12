#!/bin/bash
set -euo pipefail

# ERPNext 16 AIO runner
# Default: bind-mount persistence under ./data/ (works if permissions are fixed).
# Fallback: set USE_NAMED_VOLUMES=yes to use Docker named volumes.

: ${IMAGE:=ghcr.io/ashanzzz/erpnext16-aio:latest}
: ${NAME:=erpnext16-aio}
: ${HTTP_PORT:=80}
: ${MARIADB_ROOT_PASSWORD:=Pass1234}
: ${ADMIN_PASSWORD:=admin}
: ${SITE_NAME:=site1.local}
: ${FIX_PERMS:=yes}
: ${USE_NAMED_VOLUMES:=no}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd docker

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-${SCRIPT_DIR}/data}"
SITES_DIR="${SITES_DIR:-${DATA_DIR}/sites}"
MYSQL_DIR="${MYSQL_DIR:-${DATA_DIR}/mysql}"

if [[ "$USE_NAMED_VOLUMES" == "yes" ]]; then
  SITES_MOUNT=( -v erpnext16-sites:/home/frappe/frappe-bench/sites )
  MYSQL_MOUNT=( -v erpnext16-mysql:/var/lib/mysql )
else
  mkdir -p "$SITES_DIR" "$MYSQL_DIR"
  SITES_MOUNT=( -v "${SITES_DIR}:/home/frappe/frappe-bench/sites" )
  MYSQL_MOUNT=( -v "${MYSQL_DIR}:/var/lib/mysql" )

  if [[ "$FIX_PERMS" == "yes" ]]; then
    echo "Fixing bind-mount permissions..."
    # We chown to container users (frappe uid=1000, mysql uid from distro package).
    # This may fail on filesystems that don't support chown (then use named volumes).
    docker run --rm --user 0:0 \
      "${SITES_MOUNT[@]}" "${MYSQL_MOUNT[@]}" \
      --entrypoint bash "$IMAGE" -lc \
      'set -e; mkdir -p /home/frappe/frappe-bench/sites /var/lib/mysql; chown -R frappe:frappe /home/frappe/frappe-bench/sites; chown -R mysql:mysql /var/lib/mysql || true'
  fi
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container '$NAME' already exists. Remove it first: docker rm -f $NAME" >&2
  exit 1
fi

echo "Starting $NAME from $IMAGE ..."
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  -p "$HTTP_PORT":80 \
  -e MARIADB_ROOT_PASSWORD="$MARIADB_ROOT_PASSWORD" \
  -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  -e SITE_NAME="$SITE_NAME" \
  "${SITES_MOUNT[@]}" \
  "${MYSQL_MOUNT[@]}" \
  "$IMAGE"

echo "OK. Open: http://localhost:${HTTP_PORT}"
echo "Admin password: ${ADMIN_PASSWORD}"

#!/bin/sh
set -e
PUID=${ONEDRIVE_UID:-99}
PGID=${ONEDRIVE_GID:-100}

mkdir -p "${CONFIG_DIR:-/config}" "${DATA_DIR:-/data}"
chown -R "${PUID}:${PGID}" "${CONFIG_DIR:-/config}" 2>/dev/null || true

if [ "$(id -u)" = "0" ] && command -v su-exec >/dev/null 2>&1; then
    exec su-exec "${PUID}:${PGID}" "$@"
else
    exec "$@"
fi

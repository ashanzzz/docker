#!/usr/bin/env bash
set -euo pipefail

: "${GUNICORN_THREADS:=2}"
: "${GUNICORN_WORKERS:=1}"
: "${GUNICORN_TIMEOUT:=300}"
: "${GUNICORN_BIND:=127.0.0.1:8000}"
: "${GUNICORN_PRELOAD:=true}"

cmd=(
  /home/frappe/frappe-bench/env/bin/gunicorn
  --chdir=/home/frappe/frappe-bench/sites
  --bind="${GUNICORN_BIND}"
  --threads="${GUNICORN_THREADS}"
  --workers="${GUNICORN_WORKERS}"
  --worker-class=gthread
  --worker-tmp-dir=/dev/shm
  --timeout="${GUNICORN_TIMEOUT}"
)

if [[ "${GUNICORN_PRELOAD}" == "true" ]]; then
  cmd+=(--preload)
fi

cmd+=(frappe.app:application)
exec "${cmd[@]}"

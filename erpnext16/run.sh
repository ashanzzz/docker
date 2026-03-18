#!/usr/bin/env bash
set -euo pipefail

# ERPNext 16 stack runner (Unraid-friendly)
# - Uses upstream-compatible compose.yaml + official overrides
# - Provides AIO experience: one folder, one script

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

ENV_FILE="${ENV_FILE:-.env}"
PROJECT="${PROJECT:-erpnext16}"

compose_cmd() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return
  fi
  echo "ERROR: docker compose not found. On Unraid install docker-compose plugin or use docker compose v2." >&2
  exit 2
}

C="$(compose_cmd)"

FILES=(
  -f "$DIR/compose.yaml"
  -f "$DIR/overrides/compose.mariadb.yaml"
  -f "$DIR/overrides/compose.redis.yaml"
  -f "$DIR/overrides/compose.noproxy.yaml"
)

# shellcheck disable=SC2086
c() { $C --env-file "$ENV_FILE" -p "$PROJECT" "${FILES[@]}" "$@"; }

need_env() {
  local k="$1"
  if ! grep -qE "^${k}=" "$ENV_FILE"; then
    echo "ERROR: missing ${k} in ${ENV_FILE}" >&2
    exit 2
  fi
}

wait_configurator_done() {
  echo "Waiting configurator to complete..."
  # configurator is a one-shot job; we wait until it exits with code 0.
  local id
  id="$(c ps -q configurator || true)"
  if [[ -z "$id" ]]; then
    echo "WARN: configurator container not found yet (maybe not started)." >&2
    return 0
  fi

  local start="$(date +%s)"
  while true; do
    local status
    status="$(docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null || echo unknown)"
    if [[ "$status" == "exited" ]]; then
      local code
      code="$(docker inspect -f '{{.State.ExitCode}}' "$id" 2>/dev/null || echo 1)"
      if [[ "$code" == "0" ]]; then
        echo "OK: configurator exited 0"
        return 0
      fi
      echo "ERROR: configurator exited code=$code" >&2
      c logs configurator --tail=200 >&2 || true
      exit 1
    fi

    if (( $(date +%s) - start > 120 )); then
      echo "ERROR: configurator did not finish within 120s" >&2
      c logs configurator --tail=200 >&2 || true
      exit 1
    fi
    sleep 3
  done
}

create_site() {
  need_env DB_PASSWORD
  need_env SITE_NAME
  need_env ADMIN_PASSWORD

  # Load vars from env file (safe-ish; file is local)
  # shellcheck disable=SC1090
  source "$ENV_FILE"

  wait_configurator_done

  echo "Creating site: ${SITE_NAME}"
  # Note: --mariadb-user-host-login-scope='%' is simplest for docker networks.
  c exec -T backend bash -lc \
    "bench new-site '${SITE_NAME}' \
      --mariadb-user-host-login-scope='%' \
      --db-root-password '${DB_PASSWORD}' \
      --admin-password '${ADMIN_PASSWORD}' \
      --install-app erpnext \
      --set-default frontend"

  echo "OK: site created. If you need extra official apps (hrms/print_designer/helpdesk...), ensure they exist in the image first, then run:"
  echo "  ./run.sh install-app hrms"
}

install_app() {
  need_env SITE_NAME
  # shellcheck disable=SC1090
  source "$ENV_FILE"

  local app="$1"
  echo "Installing app '${app}' on site '${SITE_NAME}'"
  c exec -T backend bash -lc "bench --site '${SITE_NAME}' install-app '${app}'"
}

case "${1:-}" in
  up)
    c up -d
    ;;
  down)
    c down
    ;;
  restart)
    c down
    c up -d
    ;;
  ps|status)
    c ps
    ;;
  logs)
    shift || true
    c logs -f --tail=200 "$@"
    ;;
  config)
    # Render merged compose for debugging
    c config
    ;;
  create-site)
    create_site
    ;;
  install-app)
    install_app "${2:?app name required (e.g. hrms)}"
    ;;
  *)
    cat <<'USAGE'
Usage:
  ./run.sh up
  ./run.sh status
  ./run.sh logs [service]
  ./run.sh create-site
  ./run.sh install-app <app>
  ./run.sh down

Notes:
- Copy .env.example -> .env and set strong passwords.
- Custom apps (hrms/helpdesk/print_designer/...) should be baked into the image via apps.json + build pipeline.
USAGE
    ;;
esac

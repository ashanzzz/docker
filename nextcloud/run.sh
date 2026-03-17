#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "[nextcloud] .env missing. Copy .env.example -> .env and edit it first." >&2
  exit 2
fi

# shellcheck disable=SC1091
source .env

compose() {
  # Prefer docker compose v2; fallback to docker-compose.
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "[nextcloud] ERROR: docker compose not found" >&2
    exit 3
  fi
}

profiles=()
if [[ "${ENABLE_COLLABORA:-0}" == "1" ]]; then
  profiles+=(--profile collabora)
fi
if [[ "${ENABLE_ELASTICSEARCH:-0}" == "1" ]]; then
  profiles+=(--profile elasticsearch)
fi

cmd="${1:-}" || true
shift || true

wait_occ() {
  # Wait until Nextcloud container can run occ.
  echo "[nextcloud] waiting for Nextcloud to become ready..."
  for i in {1..60}; do
    if compose exec -u www-data nextcloud php occ status >/dev/null 2>&1; then
      echo "[nextcloud] ready"
      return 0
    fi
    sleep 2
  done
  echo "[nextcloud] ERROR: Nextcloud not ready (timeout)" >&2
  return 1
}

case "$cmd" in
  up)
    echo "[nextcloud] starting stack..."
    compose "${profiles[@]}" up -d
    ;;
  down)
    compose "${profiles[@]}" down
    ;;
  restart)
    compose "${profiles[@]}" restart
    ;;
  status)
    compose ps
    ;;
  logs)
    compose logs -f --tail=200
    ;;
  occ)
    # Usage: bash run.sh occ config:system:get trusted_domains
    compose exec -u www-data nextcloud php occ "$@"
    ;;
  post-config)
    wait_occ
    echo "[nextcloud] post-config: reverse proxy, redis, cron, preview, misc"

    # 0) Ensure required apps
    # APCu is used for local cache; if missing, Nextcloud will ignore or warn.

    # 1) Set trusted_domains
    # Nextcloud expects array; easiest is add one-by-one.
    domains_str="${TRUSTED_DOMAINS:-}"
    domains_str="${domains_str//,/ }"
    read -ra domains <<<"${domains_str}"
    i=0
    for d in "${domains[@]}"; do
      d="$(echo "$d" | xargs)"
      [[ -z "$d" ]] && continue
      compose exec -u www-data nextcloud php occ config:system:set trusted_domains "$i" --value="$d" || true
      i=$((i+1))
    done

    # 2) Trusted proxies (optional)
    if [[ -n "${TRUSTED_PROXIES:-}" ]]; then
      proxies_str="${TRUSTED_PROXIES}"
      proxies_str="${proxies_str//,/ }"
      read -ra proxies <<<"${proxies_str}"
      j=0
      for p in "${proxies[@]}"; do
        p="$(echo "$p" | xargs)"
        [[ -z "$p" ]] && continue
        compose exec -u www-data nextcloud php occ config:system:set trusted_proxies "$j" --value="$p" || true
        j=$((j+1))
      done
    fi

    # 3) Overwrite settings (for reverse proxy)
    if [[ -n "${PUBLIC_URL:-}" ]]; then
      compose exec -u www-data nextcloud php occ config:system:set overwrite.cli.url --value="${PUBLIC_URL}" || true
    fi
    if [[ -n "${PUBLIC_PROTO:-}" ]]; then
      compose exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="${PUBLIC_PROTO}" || true
    fi

    # 4) Redis: memcache + file locking
    compose exec -u www-data nextcloud php occ config:system:set memcache.local --value='\\OC\\Memcache\\APCu' || true
    compose exec -u www-data nextcloud php occ config:system:set memcache.locking --value='\\OC\\Memcache\\Redis' || true
    compose exec -u www-data nextcloud php occ config:system:set redis host --value="${REDIS_HOST:-redis}" || true

    # 5) Cron background jobs
    compose exec -u www-data nextcloud php occ background:cron || true

    # 6) allow_local_remote_servers (for external storage/WebDAV use-cases)
    if [[ "${ALLOW_LOCAL_REMOTE_SERVERS:-0}" == "1" ]]; then
      compose exec -u www-data nextcloud php occ config:system:set allow_local_remote_servers --type=boolean --value=true || true
    fi

    # 7) Region
    if [[ -n "${DEFAULT_PHONE_REGION:-}" ]]; then
      compose exec -u www-data nextcloud php occ config:system:set default_phone_region --value="${DEFAULT_PHONE_REGION}" || true
    fi

    echo "[nextcloud] post-config done"
    ;;

  enable-collabora)
    # Start collabora if profile enabled, then install/configure richdocuments.
    echo "[nextcloud] enabling Collabora (CODE) integration..."
    compose --profile collabora up -d collabora
    wait_occ

    # Install app (may fail if no internet / appstore blocked)
    compose exec -u www-data nextcloud php occ app:install richdocuments || true
    compose exec -u www-data nextcloud php occ app:enable richdocuments || true

    # Point Nextcloud to internal collabora service
    compose exec -u www-data nextcloud php occ config:app:set richdocuments wopi_url --value="http://collabora:9980" || true

    echo "[nextcloud] collabora done"
    ;;

  enable-fulltextsearch)
    echo "[nextcloud] enabling Full Text Search (Elasticsearch)..."
    compose --profile elasticsearch up -d elasticsearch
    wait_occ

    compose exec -u www-data nextcloud php occ app:install fulltextsearch || true
    compose exec -u www-data nextcloud php occ app:install fulltextsearch_elasticsearch || true
    compose exec -u www-data nextcloud php occ app:install files_fulltextsearch || true

    # Basic config (may need adjust for your Nextcloud/app versions)
    compose exec -u www-data nextcloud php occ fulltextsearch:configure '{"search_platform":"OCA\\FullTextSearch_Elasticsearch\\Platform\\ElasticSearchPlatform"}' || true
    compose exec -u www-data nextcloud php occ fulltextsearch_elasticsearch:configure '{"elastic_host":"http://elasticsearch:9200"}' || true

    echo "[nextcloud] running initial index (can take long)..."
    compose exec -u www-data nextcloud php occ fulltextsearch:index || true

    echo "[nextcloud] fulltextsearch done"
    ;;

  *)
    cat <<'USAGE'
Usage:
  bash run.sh up
  bash run.sh down
  bash run.sh status
  bash run.sh logs
  bash run.sh occ <occ args>
  bash run.sh post-config
  bash run.sh enable-collabora
  bash run.sh enable-fulltextsearch

Notes:
- First run requires .env (copy from .env.example).
- This script does NOT write secrets. Keep .env private.
USAGE
    exit 1
    ;;
esac

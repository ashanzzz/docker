#!/bin/bash
set -Eeuo pipefail

SITES=/home/frappe/frappe-bench/sites
BENCH_DIR=/home/frappe/frappe-bench
STAMP="$SITES/assets/.last-build.ver"

# ---------- tiny progress helper ---------- #
STEP_TOTAL=6
STEP_DONE=0
: "${PROGRESS:=1}"
: "${QUIET:=0}"

p_log() { [ "${QUIET}" = "1" ] && return 0; echo "$@"; }
p_step() {
  STEP_DONE=$((STEP_DONE+1))
  local pct=$(( STEP_DONE*100/STEP_TOTAL ))
  if [ "${PROGRESS}" = "1" ]; then
    local bars=$(( pct/5 ))
    printf "[%3d%%] " "${pct}"
    printf "%0.s#" $(seq 1 ${bars})
    printf "%0.s-" $(seq $((bars+1)) 20)
    echo "  $1"
  else
    echo "[${pct}%] $1"
  fi
}

# ---------- make node/yarn available ---------- #
p_step "prepare PATH"
if [ -d /usr/local/lib/nodejs ]; then
  V="$(ls -1 /usr/local/lib/nodejs | head -n1 || true)"
  if [ -n "${V}" ] && [ -d "/usr/local/lib/nodejs/${V}/bin" ]; then
    export PATH="/usr/local/lib/nodejs/${V}/bin:$PATH"
  fi
fi

# fallback（容器里没 node 时）
if ! command -v node >/dev/null 2>&1; then
  p_log "node not found → installing Node 20 (first run)"
  apt-get update
  apt-get install -y curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
command -v yarn >/dev/null 2>&1 || npm i -g yarn

# ---------- compute current app version fingerprint ---------- #
p_step "compute version fingerprint"
pushd "$BENCH_DIR" >/dev/null 2>&1 || true
VER_NOW="$(bench version 2>/dev/null | sha1sum | awk '{print $1}')"
popd >/dev/null 2>&1 || true
[ -z "${VER_NOW}" ] && VER_NOW="unknown"

# ---------- decide whether to (re)build ---------- #
p_step "check assets state"
need_build="no"

# v15: 产物在 apps 的 public/dist 下，通过 sites/assets/<app>/dist/** 暴露
COUNT_DIST="$(find -L "$SITES/assets" -type f \( -path "*/dist/js/*.js" -o -path "*/dist/css/*.css" \) 2>/dev/null | wc -l || true)"
if [ "${COUNT_DIST}" = "0" ]; then
  p_log "[entrypoint] No dist assets under sites/assets → need build"
  need_build="yes"
fi

if [ -f "$STAMP" ]; then
  VER_OLD="$(cat "$STAMP" || true)"
  if [ "$VER_OLD" != "$VER_NOW" ]; then
    p_log "[entrypoint] App versions changed: ${VER_OLD} → ${VER_NOW} → need build"
    need_build="yes"
  fi
else
  p_log "[entrypoint] First build (no stamp)"
  need_build="yes"
fi

if [ "${FORCE_REBUILD:-0}" = "1" ]; then
  p_log "[entrypoint] FORCE_REBUILD=1 → need build"
  need_build="yes"
fi

# ---------- build (if needed) ---------- #
p_step "maybe build assets"
if [ "$need_build" = "yes" ]; then
  pushd "$BENCH_DIR" >/dev/null 2>&1 || true
  p_log "[entrypoint] bench build --production (first run/after upgrade is normal)"
  bench build --production || bench build
  bench clear-website-cache || true
  bench clear-cache || true
  echo "$VER_NOW" > "$STAMP"
  popd >/dev/null 2>&1 || true
else
  p_log "[entrypoint] assets ready; skip build"
fi

# ---------- light self-check (HEAD a few URLs) ---------- #
p_step "self-check"
for u in \
  /assets/frappe/dist/js/desk.bundle.*.js \
  /assets/frappe/dist/css/desk.bundle.*.css
do
  # 只挑前两个探测，避免刷屏
  test -e "$u" && break || true
done
# 不强制 HEAD 检查：Nginx 可能还在热加载
# curl -sI "http://127.0.0.1:80${u}" | sed -n "1,3p" || true

# ---------- ready to exec CMD (supervisord) ---------- #
p_step "start supervisord"
exec "$@"

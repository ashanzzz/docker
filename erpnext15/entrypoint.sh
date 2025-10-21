#!/bin/bash
set -Eeuo pipefail

SITES=/home/frappe/frappe-bench/sites
BENCH_DIR=/home/frappe/frappe-bench
STAMP="$SITES/assets/.last-build.ver"

# ---------- tiny progress helper ---------- #
STEP_TOTAL=5
STEP_DONE=0
: "${PROGRESS:=1}"
: "${QUIET:=0}"

p_log() { [ "${QUIET}" = "1" ] && return 0; echo "$@"; }
p_step() {
  STEP_DONE=$((STEP_DONE+1))
  local pct=$(( STEP_DONE * 100 / STEP_TOTAL ))
  if [ "${PROGRESS}" = "1" ]; then
    local bars=$(( pct / 5 ))
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

# Fallback: 安装 Node.js 20 和 Yarn（首次运行容器可能需要）
if ! command -v node >/dev/null 2>&1; then
  p_log "node not found → installing Node 20 (first run)"
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
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
# 检查静态资产是否存在
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
  p_log "[entrypoint] bench build --production (first run/after upgrade)"
  bench build --production || bench build
  bench clear-website-cache || true
  bench clear-cache || true
  echo "$VER_NOW" > "$STAMP"
  popd >/dev/null 2>&1 || true
else
  p_log "[entrypoint] assets ready; skip build"
fi

# ---------- start supervisord and monitor site ---------- #
p_step "start supervisord & monitoring"
sudo /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf &
SUP_PID=$!
p_log "[entrypoint] Supervisord (PID ${SUP_PID}) started, entering health monitor loop..."

# 健康检查循环：每隔 1 分钟检查站点静态资源和 HTTP 状态
WEB_PORT="${WEB_PORT:-80}"
while true; do
  sleep 60
  # 检查 supervisord 进程是否仍在运行
  if ! sudo kill -0 $SUP_PID 2>/dev/null; then
    p_log "[entrypoint] Supervisord not running - exiting monitor."
    break
  fi
  need_build_check="no"
  # 检查静态资源文件是否存在
  COUNT_DIST_NOW="$(find -L "$SITES/assets" -type f \( -path "*/dist/js/*.js" -o -path "*/dist/css/*.css" \) 2>/dev/null | wc -l || true)"
  if [ "$COUNT_DIST_NOW" = "0" ]; then
    need_build_check="yes"
    p_log "[entrypoint] Static assets missing, will rebuild"
  fi
  # 检查 HTTP 服务可用性
  if ! curl -sfI -m 5 "http://127.0.0.1:${WEB_PORT}" >/dev/null; then
    need_build_check="yes"
    p_log "[entrypoint] Site HTTP check failed (port ${WEB_PORT})"
  fi
  # 若需要则重新构建前端资产
  if [ "$need_build_check" = "yes" ]; then
    p_log "[entrypoint] Rebuilding assets..."
    pushd "$BENCH_DIR" >/dev/null 2>&1 || true
    bench build --production || bench build
    bench clear-website-cache || true
    bench clear-cache || true
    popd >/dev/null 2>&1 || true
    p_log "[entrypoint] Asset rebuild complete."
  else
    p_log "[entrypoint] Site check OK."
  fi
done

# 退出（当 supervisord 停止时）
exit 0

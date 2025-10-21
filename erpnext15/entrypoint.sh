#!/bin/bash
# ERPNext v15 entrypoint
# 作用：
# 1) 准备 Node/Yarn 环境（容器第一次运行时兜底安装）
# 2) 计算应用版本指纹，判断是否需要 build 资产
# 3) 若需要就 bench build + 清缓存
# 4) 启动一个“健康守护”后台线程：每 60s 检查一次网站可达性，失败则 bench build + 逐站点 migrate 并在 docker logs 告警
# 5) 最后 exec supervisord（主进程）

set -Eeuo pipefail

SITES=/home/frappe/frappe-bench/sites
BENCH_DIR=/home/frappe/frappe-bench
STAMP="$SITES/assets/.last-build.ver"
: "${PROGRESS:=1}"
: "${QUIET:=0}"

log()  { [ "$QUIET" = "1" ] && return 0; echo "[entrypoint] $*"; }
warn() { echo "[entrypoint][WARN] $*" >&2; }

# 小进度条
STEP_TOTAL=6; STEP_DONE=0
step() {
  STEP_DONE=$((STEP_DONE+1))
  local pct=$(( STEP_DONE*100/STEP_TOTAL ))
  if [ "$PROGRESS" = "1" ]; then
    local bars=$(( pct/5 ))
    printf "[%3d%%] " "$pct"
    printf "%0.s#" $(seq 1 ${bars})
    printf "%0.s-" $(seq $((bars+1)) 20)
    echo "  $1"
  else
    echo "[$pct%%] $1"
  fi
}

step "prepare PATH / Node / Yarn"
if [ -d /usr/local/lib/nodejs ]; then
  V="$(ls -1 /usr/local/lib/nodejs | head -n1 || true)"
  if [ -n "${V}" ] && [ -d "/usr/local/lib/nodejs/${V}/bin" ]; then
    export PATH="/usr/local/lib/nodejs/${V}/bin:$PATH"
  fi
fi
# 容器运行期兜底安装 Node 20
if ! command -v node >/dev/null 2>&1; then
  warn "node not found → installing Node 20 (first run)"
  sudo apt-get update -y
  sudo apt-get install -y curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
  sudo apt-get install -y nodejs
fi
command -v yarn >/dev/null 2>&1 || npm i -g yarn

# 计算 apps 版本指纹
step "compute version fingerprint"
pushd "$BENCH_DIR" >/dev/null 2>&1 || true
VER_NOW="$(bench version 2>/dev/null | sha1sum | awk '{print $1}')"
popd >/dev/null 2>&1 || true
[ -z "${VER_NOW}" ] && VER_NOW="unknown"

# 判断是否需要构建
step "check assets state"
need_build="no"
COUNT_DIST="$(find -L "$SITES/assets" -type f \( -path "*/dist/js/*.js" -o -path "*/dist/css/*.css" \) 2>/dev/null | wc -l || true)"
if [ "${COUNT_DIST}" = "0" ]; then
  log "no dist assets under sites/assets → need build"
  need_build="yes"
fi
if [ -f "$STAMP" ]; then
  VER_OLD="$(cat "$STAMP" || true)"
  if [ "$VER_OLD" != "$VER_NOW" ]; then
    log "app versions changed: ${VER_OLD} → ${VER_NOW} → need build"
    need_build="yes"
  fi
else
  log "first build (no stamp)"
  need_build="yes"
fi
if [ "${FORCE_REBUILD:-0}" = "1" ]; then
  log "FORCE_REBUILD=1 → need build"
  need_build="yes"
fi

# 构建（如需要）
step "maybe build assets"
if [ "$need_build" = "yes" ]; then
  pushd "$BENCH_DIR" >/dev/null 2>&1 || true
  log "bench build --production (first run / after upgrade is normal)"
  bench build --production || bench build
  bench clear-website-cache || true
  bench clear-cache || true
  echo "$VER_NOW" > "$STAMP"
  popd >/dev/null 2>&1 || true
else
  log "assets ready; skip build"
fi

# —— 健康守护后台线程 —— #
# 作用：supervisord 启动后，每 60s 检查一次站点可达性；失败则自动修复，并在 logs 中持续告警
health_guard() {
  # 给各服务一点时间完成热身
  sleep 35
  while true; do
    # 只探测两个关键资源，减少噪音
    if curl -sf -m 5 http://127.0.0.1/api/method/ping >/dev/null 2>&1; then
      # 正常则沉默（避免刷屏）
      :
    else
      warn "网站健康检查失败：/api/method/ping 不可达。尝试自动修复（build + migrate）..."
      pushd "$BENCH_DIR" >/dev/null 2>&1 || true
      # 再做一次轻量 build（若升级后资产缺失）
      bench build --production || bench build || true
      # 逐站点 migrate（防“只升级了 DB、网站没迁移完”的尴尬）
      for s in $(ls -1 "$SITES" 2>/dev/null | grep -v '^assets$'); do
        if [ -f "$SITES/$s/site_config.json" ]; then
          echo "[entrypoint][guard] migrate site: $s"
          bench --site "$s" migrate --skip-search-index || true
        fi
      done
      bench clear-website-cache || true
      bench clear-cache || true
      popd >/dev/null 2>&1 || true

      # 再次探测并给出结果
      if curl -sf -m 8 http://127.0.0.1/api/method/ping >/dev/null 2>&1; then
        log "网站自动修复完成。"
      else
        warn "网站仍不可达，将在 60 秒后继续尝试（请检查 docker logs）。"
      fi
    fi
    sleep 60
  done
}

# 后台启动健康守护（写到容器 stdout，方便 docker logs 观察）
step "spawn health guard"
health_guard &

# 执行 CMD（supervisord 作为主进程）
step "start supervisord"
exec "$@"

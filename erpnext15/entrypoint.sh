#!/bin/bash
set -e

SITES=/home/frappe/frappe-bench/sites
ASSETS_JS="$SITES/assets/js"
ASSETS_CSS="$SITES/assets/css"

# 1) 确保 node/yarn 在 PATH（你的 install 脚本装在 /usr/local/lib/nodejs）
if [ -d /usr/local/lib/nodejs ]; then
  V="$(ls -1 /usr/local/lib/nodejs | head -n1 || true)"
  if [ -n "$V" ] && [ -d "/usr/local/lib/nodejs/$V/bin" ]; then
    export PATH="/usr/local/lib/nodejs/$V/bin:$PATH"
  fi
fi

# 2) 如果卷里 assets 为空：优先用镜像里备好的 /opt/assets-dist 拷贝；没有就 bench build
NEED_BUILD="no"
if [ ! -d "$ASSETS_JS" ] || [ ! -d "$ASSETS_CSS" ] \
   || [ -z "$(ls -A "$ASSETS_JS" 2>/dev/null)" ] \
   || [ -z "$(ls -A "$ASSETS_CSS" 2>/dev/null)" ]; then
  echo "[entrypoint] sites/assets 为空，准备恢复..."
  if [ -d /opt/assets-dist ] && [ -n "$(ls -A /opt/assets-dist 2>/dev/null)" ]; then
    echo "[entrypoint] 使用内置 /opt/assets-dist 进行快速恢复"
    mkdir -p "$SITES/assets"
    cp -a /opt/assets-dist/* "$SITES/assets/"
  else
    NEED_BUILD="yes"
  fi
fi

# 3) 如仍需要，构建一次 assets（首启/升级后）
if [ "$NEED_BUILD" = "yes" ]; then
  echo "[entrypoint] 开始 bench build（首次启动/升级后属正常）"
  cd /home/frappe/frappe-bench
  bench setup assets
  bench build --production || bench build
  bench clear-website-cache
  bench clear-cache
fi

# 4) 进入原来的 CMD（supervisord）
exec "$@"

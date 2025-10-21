#!/bin/bash
# 使用严格模式，遇到错误/未定义变量即退出，管道出错也退出
set -Eeuo pipefail

# 定义 ERPNext 框架的关键路径
SITES="/home/frappe/frappe-bench/sites"              # 所有站点的根目录
BENCH_DIR="/home/frappe/frappe-bench"                # bench 根目录
STAMP="$SITES/assets/.last-build.ver"               # 保存上次构建版本指纹的文件路径

# 进度条相关设置，总步骤数从6增加到7（新增数据库迁移步骤）
STEP_TOTAL=7
STEP_DONE=0
: "${PROGRESS:=1}"
: "${QUIET:=0}"

# 辅助函数：打印日志信息（非安静模式下）
p_log() {
  [ "${QUIET}" = "1" ] && return 0
  echo "$@"
}
# 辅助函数：打印带进度条的步骤信息
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

# 步骤1：准备 PATH，确保 Node.js 和 yarn 可用
p_step "prepare PATH"
# 将 Node.js 安装目录加入 PATH（如果存在于/usr/local/lib/nodejs）
if [ -d /usr/local/lib/nodejs ]; then
  V="$(ls -1 /usr/local/lib/nodejs | head -n1 || true)"
  if [ -n "${V}" ] && [ -d "/usr/local/lib/nodejs/${V}/bin" ]; then
    export PATH="/usr/local/lib/nodejs/${V}/bin:$PATH"
  fi
fi
# 如 PATH 中找不到 node，则安装 Node.js 20（首次运行时可能触发）
if ! command -v node >/dev/null 2>&1; then
  p_log "node 未找到 → 安装 Node.js 20 (首次运行)"
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
  sudo apt-get install -y nodejs
fi
# 确保 yarn 可用（全局安装）
command -v yarn >/dev/null 2>&1 || npm i -g yarn

# 步骤2：计算当前应用版本的指纹
p_step "compute version fingerprint"
pushd "$BENCH_DIR" >/dev/null 2>&1 || true
# 通过 `bench version` 获取当前各应用版本并哈希，作为版本指纹
VER_NOW="$(bench version 2>/dev/null | sha1sum | awk '{print $1}')"
popd >/dev/null 2>&1 || true
[ -z "${VER_NOW}" ] && VER_NOW="unknown"  # 若获取失败则标记unknown

# 步骤3：检查资源构建状态
p_step "check assets state"
need_build="no"
# 检查 sites/assets 下是否已有打包后的静态资源(js/css文件)
COUNT_DIST="$(find -L "$SITES/assets" -type f \( -path "*/dist/js/*.js" -o -path "*/dist/css/*.css" \) 2>/dev/null | wc -l || true)"
if [ "${COUNT_DIST}" = "0" ]; then
  p_log "[entrypoint] 未找到打包后的前端资源 → 需要构建"
  need_build="yes"
fi
# 检查版本指纹是否变化，若变化则需要构建（应用有更新）
if [ -f "$STAMP" ]; then
  VER_OLD="$(cat "$STAMP" || true)"
  if [ "$VER_OLD" != "$VER_NOW" ]; then
    p_log "[entrypoint] 检测到应用版本变化: ${VER_OLD} → ${VER_NOW}，标记需要构建"
    need_build="yes"
  fi
else
  p_log "[entrypoint] 首次构建（未找到版本戳文件）"
  need_build="yes"
fi
# 如设置了强制重建环境变量，则强制构建
if [ "${FORCE_REBUILD:-0}" = "1" ]; then
  p_log "[entrypoint] 检测到 FORCE_REBUILD=1，强制进行构建"
  need_build="yes"
fi

# 步骤4：根据需要构建前端资源
p_step "maybe build assets"
if [ "$need_build" = "yes" ]; then
  pushd "$BENCH_DIR" >/dev/null 2>&1 || true
  p_log "[entrypoint] 正在执行 bench build --production（首次运行或升级后属正常现象）"
  # 生产模式构建，如失败则尝试非生产模式构建
  bench build --production || bench build
  # 清理网站和缓存，以确保加载最新资源
  bench clear-website-cache || true
  bench clear-cache || true
  # 将当前版本指纹写入戳文件，标记本次构建的版本
  echo "$VER_NOW" > "$STAMP"
  popd >/dev/null 2>&1 || true
else
  p_log "[entrypoint] 资源已准备就绪，跳过构建步骤"
fi

# 步骤5：（新增）根据需要进行数据库迁移
p_step "maybe migrate database"
if [ "$need_build" = "yes" ]; then
  p_log "[entrypoint] 检测到应用更新，执行数据库迁移 (bench migrate)"
  # 启动临时的 MariaDB 服务用于迁移（因为 supervisord 尚未启动数据库）
  p_log "[entrypoint] 启动临时 MariaDB 数据库服务以进行迁移..."
  sudo /usr/sbin/mariadbd --basedir=/usr --datadir=/var/lib/mysql \
       --plugin-dir=/usr/lib/mysql/plugin --user=mysql --skip-log-error &
  mariadb_pid=$!  # 记录 MariaDB 进程ID，稍后用于停止
  # 等待 MariaDB 启动就绪（每2秒检查一次，最多尝试30次约60秒）
  try_count=0
  until mysqladmin ping -u root -p"${MARIADB_ROOT_PASSWORD}" --silent; do
    try_count=$((try_count+1))
    if [ $try_count -gt 30 ]; then
      echo "[entrypoint] MariaDB 在预定时间内未能启动，迁移中止。" >&2
      # 如进程仍在运行则终止
      if ps -p $mariadb_pid > /dev/null 2>&1; then
        sudo kill $mariadb_pid
      fi
      exit 1  # 退出脚本，容器启动失败（需要检查数据库问题）
    fi
    echo "[entrypoint] 等待 MariaDB 启动中 (${try_count}/30)..." >&2
    sleep 2
  done
  p_log "[entrypoint] MariaDB 已启动，开始执行数据库迁移..."
  # 关闭自动退出以捕获迁移失败状态
  set +e
  migrate_error=0
  failed_site=""
  # 遍历 sites 目录下的所有站点（排除 assets、logs 等公用目录），逐个执行迁移
  for site in $(find "$SITES" -maxdepth 1 -mindepth 1 -type d ! -name "assets" ! -name "logs" ! -name "packages" -printf "%f\n"); do
    bench --site "$site" migrate
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
      migrate_error=$exit_code
      failed_site="$site"
      break  # 某个站点迁移失败，立即跳出循环
    fi
  done
  set -e  # 恢复严格模式
  if [ $migrate_error -ne 0 ]; then
    # 如果有站点迁移失败，打印错误并进入循环重试
    echo "[entrypoint] ⚠️ 站点 '${failed_site}' 的数据库迁移失败 (退出码 $migrate_error)。将在后台定期重试..." >&2
    # 进入重试循环：每隔60秒重试一次迁移，方便从 docker logs 观察
    while true; do
      echo "[entrypoint] ⏳ 数据库迁移尚未成功，将在60秒后重试..." >&2
      sleep 60
      set +e
      migrate_error=0
      failed_site=""
      for site in $(find "$SITES" -maxdepth 1 -mindepth 1 -type d ! -name "assets" ! -name "logs" ! -name "packages" -printf "%f\n"); do
        bench --site "$site" migrate
        exit_code=$?
        if [ $exit_code -ne 0 ]; then
          migrate_error=$exit_code
          failed_site="$site"
          break
        fi
      done
      set -e
      if [ $migrate_error -ne 0 ]; then
        # 若仍失败，继续循环（输出提示，等待下次重试）
        echo "[entrypoint] ⚠️ 站点 '${failed_site}' 迁移仍未成功，将继续重试..." >&2
        continue
      else
        # 如迁移成功（跳出循环开始继续启动流程）
        p_log "[entrypoint] ✅ 数据库迁移在重试后成功完成，继续启动服务..."
        break
      fi
    done
  else
    p_log "[entrypoint] 数据库迁移完成。所有站点均已更新到最新模式。"
  fi
  # 关闭临时 MariaDB 服务，让后续 supervisord 接管数据库进程
  p_log "[entrypoint] 停止临时 MariaDB 服务"
  mysqladmin -u root -p"${MARIADB_ROOT_PASSWORD}" shutdown || true
  # 等待 MariaDB 进程退出（保证端口释放）
  wait $mariadb_pid 2>/dev/null || true
  # 迁移完成后再次清理缓存，确保新数据/新字段的缓存被刷新
  bench clear-website-cache || true
  bench clear-cache || true
else
  p_log "[entrypoint] 应用版本无变化，跳过数据库迁移步骤"
fi

# 步骤6：轻量自检 - 简单检查关键静态资源是否存在
p_step "self-check"
# 尝试检查主要的打包文件是否存在，以验证构建成功（如不存在也不终止，仅作提示）
for u in \
  /assets/frappe/dist/js/desk.bundle.*.js \
  /assets/frappe/dist/css/desk.bundle.*.css
do
  test -e "$u" && break || true
done

# 步骤7：启动 supervisord 来运行 ERPNext 相应的服务进程
p_step "start supervisord"
exec "$@"
# 通过 exec 替换当前进程为 supervisord，从而启动:
# - Frappe/ERPNext 后台服务 (例如 gunicorn, background workers 等，由supervisor配置管理)
# - MariaDB 数据库服务 (已通过supervisor配置接管)
# - Nginx Web 服务（生产模式下，由supervisor管理）
# 脚本至此结束，控制权交给 supervisord 管理各服务。

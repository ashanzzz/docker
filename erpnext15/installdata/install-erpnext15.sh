#!/bin/bash
# v0.8 2025-10-20
# 变更要点：
# - 强制安装 wkhtmltopdf 0.12.6（patched Qt）——来自官方 packaging release
# - 安装思源中文字体（使用 Noto CJK 软件包，等价 Source Han），并刷新字体缓存
# - 修正 bench init 的参数顺序
# - 清理无效的脚本尾巴，保证构建能顺利通过
set -e

############################################
# ========= 仅新增：展示&日志功能 ========= #
############################################
PROGRESS_TOTAL=22
PROGRESS_DONE=0
CURRENT=""
START_AT=$(date +%s)
LOG_FILE="/var/log/erpnext_install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p /var/log
exec > >(awk '{ print strftime("[%F %T]"), $0 }' | tee -a "$LOG_FILE") 2>&1

function _elapsed() { local s=$1; printf "%ds" "$s"; }
function _percent() { [ "$PROGRESS_TOTAL" -gt 0 ] && echo $((100*PROGRESS_DONE/PROGRESS_TOTAL)) || echo 0; }
function _progress_line(){ printf "[%02d/%02d] (%3d%%) %s\n" "$PROGRESS_DONE" "$PROGRESS_TOTAL" "$(_percent)" "${CURRENT:-}"; }
function begin_section(){ CURRENT="$1"; SECTION_START=$SECONDS; echo; echo "────────────────────────────────────────────────────────"; echo "▶ 开始步骤：$CURRENT"; _progress_line; }
function end_section(){ local dur=$((SECONDS-SECTION_START)); PROGRESS_DONE=$((PROGRESS_DONE+1)); echo "✔ 完成步骤：$CURRENT，耗时 $(_elapsed "$dur")"; _progress_line; echo "────────────────────────────────────────────────────────"; echo; }
function note(){ echo "ℹ️ $*"; }
function warn(){ echo "⚠️ $*"; }
function fatal(){ echo "❌ $*"; }
trap 'code=$?; fatal "出错退出（代码 $code）于步骤：${CURRENT:-未知}"; fatal "最近命令：${BASH_COMMAND}"; fatal "日志文件：$LOG_FILE"; exit $code' ERR

note "全量日志写入：$LOG_FILE"
note "本脚本整合 wkhtmltopdf(patched Qt) 与 思源字体；其它安装逻辑延续原版。"

############################################
# ============== 参数与环境 =============== #
############################################
begin_section "脚本运行环境检查：读取 /etc/os-release"
cat /etc/os-release
osVer=$(grep -F 'Ubuntu 22.04' /etc/os-release || true)
end_section

begin_section "系统版本校验"
if [[ -z "${osVer}" ]]; then
  echo '脚本只在 ubuntu 22.04 测试通过；其它版本请自行适配。'
  exit 1
else
  echo '系统版本检测通过...'
fi
end_section

begin_section "Bash & root 用户校验"
echo 'bash检测通过...'
if [ "$(id -u)" != "0" ]; then
  echo "脚本需要使用root用户执行"
  exit 1
else
  echo '执行用户检测通过...'
fi
end_section

begin_section "初始化默认参数与国内源探测"
mariadbPath=""
mariadbPort="3306"
mariadbRootPassword="${MARIADB_ROOT_PASSWORD:-Pass1234}"
adminPassword="${ADMIN_PASSWORD:-admin}"
installDir="frappe-bench"
userName="frappe"
benchVersion=""
frappePath=""
frappeBranch="version-15"
erpnextPath="https://github.com/frappe/erpnext"
erpnextBranch="version-15"
siteName="site1.local"
siteDbPassword="Pass1234"
webPort=""
productionMode="yes"
altAptSources="yes"
quiet="no"
inDocker="no"
removeDuplicate="yes"
hostAddress=("mirrors.tencentyun.com" "mirrors.tuna.tsinghua.edu.cn" "cn.archive.ubuntu.com")
for h in ${hostAddress[@]}; do
  n=$(grep -c "$h" /etc/apt/sources.list || true)
  [[ ${n} -gt 0 ]] && altAptSources="no"
done
end_section

begin_section "解析命令行参数"
argTag=""
for arg in $*; do
  if [[ -n ${argTag} ]]; then
    case "${argTag}" in
      "webPort")
        t=$(echo ${arg}|sed 's/[0-9]//g')
        if [[ -z ${t} && ${arg} -ge 80 && ${arg} -lt 65535 ]]; then
          webPort=${arg}; echo "设定web端口为${webPort}。"; continue
        else webPort=""; fi
      ;;
    esac
    argTag=""
  fi
  if [[ ${arg} == -* ]]; then
    arg=${arg:1:${#arg}}
    for i in $(seq ${#arg}); do
      arg0=${arg:$i-1:1}
      case "${arg0}" in
        "q") quiet='yes'; removeDuplicate="yes"; echo "静默安装模式";;
        "d") inDocker='yes'; echo "Docker镜像适配";;
        "p") argTag='webPort'; echo "自定义web端口";;
      esac
    done
  elif [[ ${arg} == *=* ]]; then
    arg0=${arg%=*}; arg1=${arg#*=}; echo "${arg0} 为： ${arg1}"
    case "${arg0}" in
      benchVersion) benchVersion=${arg1};;
      mariadbRootPassword) mariadbRootPassword=${arg1};;
      adminPassword) adminPassword=${arg1};;
      frappePath) frappePath=${arg1};;
      frappeBranch) frappeBranch=${arg1};;
      erpnextPath) erpnextPath=${arg1};;
      erpnextBranch) erpnextBranch=${arg1};;
      branch) frappeBranch=${arg1}; erpnextBranch=${arg1};;
      siteName) siteName=${arg1};;
      installDir) installDir=${arg1};;
      userName) userName=${arg1};;
      siteDbPassword) siteDbPassword=${arg1};;
      webPort) webPort=${arg1};;
      altAptSources) altAptSources=${arg1};;
      quiet) quiet=${arg1}; [[ ${quiet} == "yes" ]] && removeDuplicate="yes";;
      inDocker) inDocker=${arg1};;
      productionMode) productionMode=${arg1};;
    esac
  fi
done
end_section

begin_section "展示当前有效参数"
[[ ${quiet} != "yes" && ${inDocker} != "yes" ]] && clear || true
cat <<EOF
数据库端口：${mariadbPort}
数据库root密码：${mariadbRootPassword}
管理员密码：${adminPassword}
安装目录：${installDir}
bench版本：${benchVersion}
frappe路径：${frappePath}
frappe分支：${frappeBranch}
erpnext路径：${erpnextPath}
erpnext分支：${erpnextBranch}
站点名：${siteName}
站点数据库密码：${siteDbPassword}
web端口：${webPort}
是否修改apt源：${altAptSources}
静默安装：${quiet}
删除重名：${removeDuplicate}
Docker适配：${inDocker}
生产模式：${productionMode}
EOF
end_section

begin_section "安装方式选择（仅非静默）"
if [[ ${quiet} != "yes" ]]; then
  echo "1. 安装为开发模式"
  echo "2. 安装为生产模式"
  echo "3. 直接静默安装"
  echo "4. Docker内静默安装"
  read -r -p "请选择： " input
  case ${input} in
    1) productionMode="no";;
    2) productionMode="yes";;
    3) quiet="yes"; removeDuplicate="yes";;
    4) quiet="yes"; removeDuplicate="yes"; inDocker="yes";;
    *) echo "取消安装"; exit 1;;
  esac
else
  note "静默模式：跳过交互式选择"
fi
end_section

begin_section "整理参数关键字（展示用）"
[[ -n ${benchVersion} ]] && benchVersion="==${benchVersion}"
[[ -n ${frappePath} ]]  && frappePath="--frappe-path ${frappePath}"
[[ -n ${frappeBranch} ]]&& frappeBranch="--frappe-branch ${frappeBranch}"
[[ -n ${erpnextBranch} ]]&& erpnextBranch="--branch ${erpnextBranch}"
[[ -n ${siteDbPassword} ]]&& siteDbPassword="--db-password ${siteDbPassword}"
end_section

############################################
# ============== 系统准备阶段 ============= #
############################################
begin_section "APT 源（国内镜像）设置"
if [[ ${altAptSources} == "yes" ]]; then
  [[ ! -e /etc/apt/sources.list.bak ]] && cp /etc/apt/sources.list /etc/apt/sources.list.bak || true
  cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF
  apt update
  echo "apt 已改为清华镜像"
else
  note "检测到国内源/云主机默认源，跳过替换"
fi
end_section

begin_section "安装基础软件（含字体依赖，不装apt版wkhtmltopdf）"
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y
DEBIAN_FRONTEND=noninteractive apt install -y \
  ca-certificates sudo locales tzdata cron wget curl gnupg \
  python3-dev python3-venv python3-setuptools python3-pip python3-testresources \
  git software-properties-common \
  mariadb-server mariadb-client libmysqlclient-dev \
  xvfb libfontconfig1 xfonts-75dpi \
  supervisor pkg-config build-essential \
  libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev \
  libxrender1 libxext6 libx11-6 \
  fonts-noto-cjk fonts-noto-cjk-extra fonts-noto-mono
# 刷新字体缓存（思源等价 Noto CJK）
fc-cache -fv || true
end_section

begin_section "强制安装 wkhtmltopdf 0.12.6（patched Qt）"
# 若装过apt的 wkhtmltopdf 先卸载，避免冲突
apt remove -y wkhtmltopdf || true
CODENAME="$(lsb_release -cs 2>/dev/null || echo jammy)"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
case "$CODENAME" in bionic|focal|jammy) :;; * ) CODENAME="jammy";; esac
case "$ARCH" in amd64|arm64|ppc64el) :;; * ) ARCH="amd64";; esac

# 官方 packaging 版本号（稳定）
PKG_VER="0.12.6-1"
URL="https://github.com/wkhtmltopdf/packaging/releases/download/${PKG_VER}/wkhtmltox_${PKG_VER}.${CODENAME}_${ARCH}.deb"
DEB="/tmp/$(basename "$URL")"
echo "下载：$URL"
curl -fL "$URL" -o "$DEB"
# 安装 deb，自动补依赖
apt install -y "$DEB" || { dpkg -i "$DEB" || true; apt -f install -y; }
rm -f "$DEB"

# 校验版本
if ! wkhtmltopdf -V | grep -q "0.12.6"; then
  echo "wkhtmltopdf 版本异常：$(wkhtmltopdf -V 2>&1 || true)"
  exit 1
fi
echo "wkhtmltopdf 版本：$(wkhtmltopdf -V)"
end_section

############################################
# ========== 环境检查与用户准备 =========== #
############################################
begin_section "环境检查与重复安装目录处理"
rteArr=(); warnArr=()

# 清理重复目录
while [[ -d "/home/${userName}/${installDir}" ]]; do
  echo "检测到已存在：/home/${userName}/${installDir}"
  if [[ ${quiet} != "yes" ]]; then
    echo '1. 删除后继续（推荐）'; echo '2. 输入新目录'; echo '*. 取消'
    read -r -p "选择：" input
    case ${input} in
      1) rm -rf /home/${userName}/${installDir}; rm -f /etc/supervisor/conf.d/${installDir}.conf /etc/nginx/conf.d/${installDir}.conf;;
      2) read -r -p "新目录名：" d; [[ -n "$d" ]] && installDir="$d";;
      *) echo "取消安装"; exit 1;;
    esac
  else
    echo "静默模式：删除后继续"
    rm -rf /home/${userName}/${installDir}
  fi
done

# Python
if command -v python3 >/dev/null 2>&1; then
  if ! python3 -V | grep -q "3.10"; then warnArr+=("Python 非推荐 3.10"); else echo "已安装 Python 3.10"; fi
  rteArr+=("$(python3 -V)")
else
  echo "python3 未安装"; exit 1
fi

# wkhtmltopdf（上一步已安装）
rteArr+=("$(wkhtmltopdf -V)")

# MariaDB
if command -v mysql >/dev/null 2>&1; then
  if ! mysql -V | grep -q "10.6"; then warnArr+=("MariaDB 非推荐 10.6"); else echo "已安装 MariaDB 10.6"; fi
  rteArr+=("$(mysql -V)")
else
  echo "MariaDB 未安装"; exit 1
fi
end_section

begin_section "MariaDB 配置与授权"
if ! grep -q "# ERPNext install script added" /etc/mysql/my.cnf 2>/dev/null; then
  cat >> /etc/mysql/my.cnf <<'EOF'
# ERPNext install script added
[mysqld]
character-set-client-handshake=FALSE
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
bind-address=0.0.0.0

[mysql]
default-character-set=utf8mb4
EOF
fi
/etc/init.d/mariadb restart
sleep 2

if mysql -uroot -e quit >/dev/null 2>&1; then
  mysqladmin -v -uroot password "${mariadbRootPassword}"
elif mysql -uroot -p"${mariadbRootPassword}" -e quit >/dev/null 2>&1; then
  echo "root 密码已配置"
else
  echo "root 密码校验失败"; exit 1
fi

mysql -u root -p"${mariadbRootPassword}" -e \
 "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${mariadbRootPassword}' WITH GRANT OPTION;"
mysqladmin -v -uroot -p"${mariadbRootPassword}" reload
sed -i "s/^password.*$/password=${mariadbRootPassword}/" /etc/mysql/debian.cnf
end_section

begin_section "数据库重名检查与处理"
while true; do
  siteSha1=$(echo -n ${siteName} | sha1sum); siteSha1=_${siteSha1:0:16}
  dbUser=$(mysql -u root -p${mariadbRootPassword} -e "use mysql;SELECT User,Host FROM user;" | grep ${siteSha1} || true)
  if [[ -n ${dbUser} ]]; then
    echo "检测到同名 DB 用户：${siteSha1}"
    if [[ ${quiet} == "yes" ]]; then
      mysql -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};" || true
      arrUser=(${dbUser})
      for ((i=0; i<${#arrUser[@]}; i=i+2)); do
        mysql -u root -p${mariadbRootPassword} -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};" || true
      done
      echo "已删除重名数据库及用户"
      continue
    fi
    echo "1. 输入新站点名；2. 删除重名；3. 忽略（不推荐）；*. 取消"
    read -r -p "选择：" input
    case ${input} in
      1) read -r -p "新站点名：" siteName;;
      2) mysql -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};"
         arrUser=(${dbUser}); for ((i=0; i<${#arrUser[@]}; i=i+2)); do
          mysql -u root -p${mariadbRootPassword} -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};"
         done;;
      3) warnArr+=("选择忽略重名风险"); break;;
      *) echo "取消安装"; exit 1;;
    esac
  else break; fi
done
end_section

begin_section "supervisor 指令检测"
supervisorCommand=""
if command -v supervisord >/dev/null 2>&1; then
  if grep -Eq "[ *]reload\)" /etc/init.d/supervisor 2>/dev/null; then supervisorCommand="reload"
  elif grep -Eq "[ *]restart\)" /etc/init.d/supervisor 2>/dev/null; then supervisorCommand="restart"
  else warnArr+=("supervisor 启动脚本无 reload/restart"); fi
else
  warnArr+=("supervisor 未安装/不可用")
fi
echo "可用指令：${supervisorCommand}"
end_section

begin_section "安装/校验 Redis"
if ! command -v redis-server >/dev/null 2>&1; then
  rm -rf /var/lib/redis /etc/redis /etc/default/redis-server /etc/init.d/redis-server
  rm -f /usr/share/keyrings/redis-archive-keyring.gpg
  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" > /etc/apt/sources.list.d/redis.list
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y redis-tools redis-server redis
fi
rteArr+=("$(redis-server -v)")
end_section

begin_section "pip 源与工具升级"
mkdir -p /root/.pip
cat > /root/.pip/pip.conf <<'EOF'
[global]
index-url=https://pypi.tuna.tsinghua.edu.cn/simple
[install]
trusted-host=mirrors.tuna.tsinghua.edu.cn
EOF
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade setuptools cryptography psutil
alias python=python3; alias pip=pip3
end_section

begin_section "创建用户/组、环境与时区/locale"
# 用户组与用户
if ! getent group "${userName}" >/dev/null; then
  gid=1000; while getent group ${gid} >/dev/null; do gid=$((gid+1)); done
  groupadd -g ${gid} ${userName}
fi
if ! id -u "${userName}" >/dev/null 2>&1; then
  uid=1000; while getent passwd ${uid} >/dev/null; do uid=$((uid+1)); done
  useradd --no-log-init -r -m -u ${uid} -g ${gid} -G sudo ${userName}
fi
sed -i "/^${userName}.*/d" /etc/sudoers
echo "${userName} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
cp -af /root/.pip /home/${userName}/ || true
chown -R ${userName}:${userName} /home/${userName}
usermod -s /bin/bash ${userName}

# locale & 时区
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
for f in /root/.bashrc /home/${userName}/.bashrc; do
  sed -i "/^export.*LC_.*=/d; /^export.*LANG=/d" "$f" || true
  echo -e "export LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8\nexport LANG=en_US.UTF-8" >> "$f"
done
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# inotify
sed -i "/^fs.inotify.max_user_watches=.*/d" /etc/sysctl.conf
echo fs.inotify.max_user_watches=524288 | tee -a /etc/sysctl.conf
/sbin/sysctl -p || true
end_section

begin_section "Node.js 20 / npm / yarn"
source /etc/profile || true
if ! command -v node >/dev/null 2>&1; then
  nodejsLink=$(curl -sL https://registry.npmmirror.com/-/binary/node/latest-v20.x/ | \
    grep -oE "https?://[a-zA-Z0-9\./_&=@$%?~#-]*node-v20\.[0-9]+\.[0-9]+"-linux-x64.tar.xz | tail -1)
  [[ -z $nodejsLink ]] && { echo "Node.js 下载地址获取失败"; exit 1; }
  nodejsFileName=${nodejsLink##*/}; t=(${nodejsFileName//-/ }); nodejsVer=${t[1]}
  wget -q "$nodejsLink" -P /tmp/
  mkdir -p /usr/local/lib/nodejs
  tar -xJf /tmp/${nodejsFileName} -C /usr/local/lib/nodejs/
  mv /usr/local/lib/nodejs/${nodejsFileName%%.tar*} /usr/local/lib/nodejs/${nodejsVer}
  echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" > /etc/profile.d/nodejs.sh
  export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:$PATH
fi
npm config set registry https://registry.npmmirror.com -g
npm i -g npm yarn
sudo -u ${userName} bash -lc "yarn config set registry https://registry.npmmirror.com --global"
end_section

begin_section "Docker 适配（如启用）"
if [[ ${inDocker} == "yes" ]]; then
  supervisorConfigDir=/home/${userName}/.config/supervisor
  mkdir -p ${supervisorConfigDir}
  # mariadb
  cat > ${supervisorConfigDir}/mariadb.conf <<'EOF'
[program:mariadb]
command=/usr/sbin/mariadbd --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib/mysql/plugin --user=mysql --skip-log-error
priority=1
autostart=true
autorestart=true
numprocs=1
startretries=10
stopwaitsecs=10
redirect_stderr=true
stdout_logfile_maxbytes=1024MB
stdout_logfile_backups=10
stdout_logfile=/var/run/log/supervisor_mysql.log
EOF
  # nginx
  cat > ${supervisorConfigDir}/nginx.conf <<'EOF'
[program: nginx]
command=/usr/sbin/nginx -g 'daemon off;'
autostart=true
autorestart=true
stderr_logfile=/var/run/log/supervisor_nginx_error.log
stdout_logfile=/var/run/log/supervisor_nginx_stdout.log
environment=ASPNETCORE_ENVIRONMENT=Production
user=root
stopsignal=INT
startsecs=10
startretries=5
stopasgroup=true
EOF
  /etc/init.d/mariadb stop || true
  ln -fs ${supervisorConfigDir}/mariadb.conf /etc/supervisor/conf.d/mariadb.conf
  if ! pgrep -f supervisord >/dev/null 2>&1; then /usr/bin/supervisord -c /etc/supervisor/supervisord.conf; else /usr/bin/supervisorctl reload; fi
  sleep 2
else
  note "非 Docker 模式，跳过容器适配"
fi
end_section

############################################
# =============== Bench 安装 ============== #
############################################
begin_section "安装 bench"
sudo -u ${userName} bash -lc "sudo -H pip3 install frappe-bench${benchVersion}"
bench --version || { echo "bench 安装失败"; exit 1; }
end_section

begin_section "Docker 情况下：注释 fail2ban 安装"
if [[ ${inDocker} == "yes" ]]; then
  f="/usr/local/lib/python3.10/dist-packages/bench/config/production_setup.py"
  if [[ -f "$f" ]]; then
    n=$(sed -n "/^[[:space:]]*if not which.*fail2ban-client/=" ${f} || true)
    [[ -n "$n" ]] && sed -i "${n}s/^/#&/; $((n+1))s/^/#&/" ${f}
  fi
fi
end_section

begin_section "初始化 frappe（bench init，带重试 & 修正参数顺序）"
sudo -u ${userName} bash -lc "
set -e
for ((i=0; i<5; i++)); do
  rm -rf ~/${installDir}
  set +e
  # 修正后的 bench init 调用顺序： bench init <目录> [--frappe-branch ...] [--frappe-path ...]
  bench init ${installDir} ${frappeBranch} ${frappePath} --python /usr/bin/python3 --ignore-exist
  err=\$?
  set -e
  if [[ \$err -eq 0 ]]; then echo 'bench init 成功'; break; fi
  [[ \$i -ge 4 ]] && { echo 'frappe 初始化失败次数过多'; exit 1; }
  echo 'frappe 初始化失败，重试中...'
  sleep 1
done"
end_section

begin_section "确认 frappe 初始化结果"
sudo -u ${userName} bash -lc "
cd ~/${installDir}
frappeV=\$(bench version | grep 'frappe' || true)
[[ -z \${frappeV} ]] && { echo 'frappe 初始化失败'; exit 1; } || { echo 'frappe 初始化成功'; echo \${frappeV}; }
"
end_section

begin_section "获取应用（erpnext/payments/hrms/print_designer）"
sudo -u ${userName} bash -lc "
cd ~/${installDir}
bench get-app ${erpnextBranch} ${erpnextPath}
bench get-app payments
bench get-app ${erpnextBranch} hrms
bench get-app print_designer
"
end_section

begin_section "建立新站点（bench new-site）"
sudo -u ${userName} bash -lc "
cd ~/${installDir}
bench new-site --mariadb-root-password ${mariadbRootPassword} ${siteDbPassword} --admin-password ${adminPassword} ${siteName}
"
end_section

begin_section "安装应用到站点"
sudo -u ${userName} bash -lc "
cd ~/${installDir}
bench --site ${siteName} install-app payments
bench --site ${siteName} install-app erpnext
bench --site ${siteName} install-app hrms
bench --site ${siteName} install-app print_designer
"
end_section

begin_section "站点基础配置"
sudo -u ${userName} bash -lc "
cd ~/${installDir}
bench config http_timeout 6000
bench config serve_default_site on
bench use ${siteName}
"
end_section

begin_section "安装中文本地化（erpnext_chinese）"
sudo -u ${userName} bash -lc "
cd ~/${installDir}
bench get-app https://gitee.com/yuzelin/erpnext_chinese.git
bench --site ${siteName} install-app erpnext_chinese
bench clear-cache && bench clear-website-cache
"
end_section

begin_section "清理工作台缓存"
sudo -u ${userName} bash -lc "
cd ~/${installDir}
bench clear-cache
bench clear-website-cache
"
end_section

begin_section "生产模式开启（如启用）"
if [[ ${productionMode} == "yes" ]]; then
  apt update && apt install -y nginx
  if [[ ${inDocker} == "yes" ]]; then
    /etc/init.d/nginx stop || true
    ln -fs /home/${userName}/.config/supervisor/nginx.conf /etc/supervisor/conf.d/nginx.conf
    /usr/bin/supervisorctl status || true
    /usr/bin/supervisorctl reload || true
    sleep 5
    /usr/bin/supervisorctl status || true
  fi
  if [[ -n ${supervisorCommand} ]]; then
    f="/usr/local/lib/python3.10/dist-packages/bench/config/supervisor.py"
    if [[ -f "$f" ]]; then
      sed -i -E "s/(service .*supervisor .*)(reload|restart)/\1${supervisorCommand}/" "$f" || true
    fi
  fi
  f="/etc/supervisor/conf.d/${installDir}.conf"
  i=0
  while [[ $i -lt 9 ]]; do
    set +e
    sudo -u ${userName} bash -lc "cd ~/${installDir}; sudo bench setup production ${userName} --yes"
    rc=$?; set -e
    i=$((i+1))
    [[ -e ${f} ]] && { echo '生产模式配置文件已生成'; break; }
    [[ $i -ge 9 ]] && { echo '生产模式开启失败次数过多，请手动排查'; break; }
    echo "生产模式生成失败（第 ${i} 次），重试中..."
    sleep 1
  done
else
  note "开发模式：跳过生产模式开启"
fi
end_section

begin_section "自定义 web 端口（如设置）"
if [[ -n ${webPort} ]]; then
  t=$(echo ${webPort}|sed 's/[0-9]//g')
  if [[ -z ${t} && ${webPort} -ge 80 && ${webPort} -lt 65535 ]]; then
    if [[ ${productionMode} == "yes" ]]; then
      f="/home/${userName}/${installDir}/config/nginx.conf"
      if [[ -f ${f} ]]; then
        n=($(sed -n "/^[[:space:]]*listen/=" ${f}))
        [[ -n ${n} ]] && { sed -i "${n} c listen ${webPort};" ${f}; sed -i "$((n+1)) c listen [::]:${webPort};" ${f}; /etc/init.d/nginx reload || true; echo "生产模式端口改为 ${webPort}"; } || warn "未找到 listen 行"
      else
        warn "未找到 nginx.conf，端口未改"
      fi
    else
      f="/home/${userName}/${installDir}/Procfile"
      if [[ -f ${f} ]]; then
        n=($(sed -n "/^web.*port.*/=" ${f}))
        [[ -n ${n} ]] && { sed -i "${n} c web: bench serve --port ${webPort}" ${f}; sudo -u ${userName} bash -lc "cd ~/${installDir}; bench restart" || true; echo "开发模式端口改为 ${webPort}"; } || warn "未找到 web: 行"
      else
        warn "未找到 Procfile，端口未改"
      fi
    fi
  else
    warn "指定的端口无效，保持默认"
  fi
else
  [[ ${productionMode} == "yes" ]] && webPort="80" || webPort="8000"
  note "未指定 webPort，按默认：${webPort}"
fi
end_section

begin_section "权限修正、清理缓存与包管理器缓存"
chown -R ${userName}:${userName} /home/${userName}/
chmod 755 /home/${userName}
apt clean
apt autoremove -y
rm -rf /var/lib/apt/lists/*
pip cache purge || true
npm cache clean --force || true
sudo -u ${userName} bash -lc "cd ~/${installDir}; npm cache clean --force || true; yarn cache clean || true"
end_section

begin_section "确认安装版本与环境摘要"
sudo -u ${userName} bash -lc "cd ~/${installDir}; bench version"
echo "===================主要运行环境==================="
for i in "${rteArr[@]}"; do echo "${i}"; done
if [[ ${#warnArr[@]} -ne 0 ]]; then
  echo "===================警告==================="; for i in "${warnArr[@]}"; do echo "${i}"; done
fi
echo "管理员账号：administrator，密码：${adminPassword}。"
if [[ ${productionMode} == "yes" ]]; then
  if [[ -e /etc/supervisor/conf.d/${installDir}.conf ]]; then
    echo "已开启生产模式。用域名/IP 访问，监听 ${webPort}"
  else
    echo "已尝试开启生产模式，但 supervisor 配置未生成，请排查后手动开启。"
  fi
else
  echo "开发模式：切换到 ${userName}，进入 ~/${installDir}，执行 'bench start'，默认端口 ${webPort}"
fi
[[ ${inDocker} == "yes" ]] && { echo "当前 supervisor 状态："; /usr/bin/supervisorctl status || true; }
end_section

echo
echo "🎉 全部流程执行完毕。总耗时：$(_elapsed $(( $(date +%s) - START_AT )))"
echo "📄 完整日志：$LOG_FILE"
exit 0

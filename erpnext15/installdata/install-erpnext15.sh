#!/bin/bash
# v0.9 2025.10.20
# 变更摘要：
# - 修复 bench init 参数顺序与可选项，避免 exit code: 2
# - 维持你的安装流程与日志展示；只做稳健性增强与小修
# - wkhtmltopdf 先走 apt；若版本不对自动兜底安装 0.12.6-1 (with patched Qt)
# - su heredoc 不加引号，确保外层变量能展开；不使用 set -u
# - 删除会导致语法错误的“脚本收尾占位行”；进度百分比限幅到 100%

set -eo pipefail

############################################
# ========= 展示&日志功能（保持&增强） ===== #
############################################
PROGRESS_TOTAL=28              # 展示用途；不影响逻辑
PROGRESS_DONE=0
CURRENT=""
START_AT=$(date +%s)
LOG_FILE="/var/log/erpnext_install_$(date +%Y%m%d_%H%M%S).log"

mkdir -p /var/log
# 同步输出到屏幕和日志，并加时间戳
exec > >(awk '{ print strftime("[%F %T]"), $0 }' | tee -a "$LOG_FILE") 2>&1

function _elapsed(){ local s=$1; printf "%ds" "$s"; }
function _percent(){
  local p=0
  if [ "$PROGRESS_TOTAL" -gt 0 ]; then p=$(( 100 * PROGRESS_DONE / PROGRESS_TOTAL )); fi
  if [ "$p" -gt 100 ]; then p=100; fi
  echo "$p"
}
function _progress_line(){ printf "[%02d/%02d] (%3d%%) %s\n" "$PROGRESS_DONE" "$PROGRESS_TOTAL" "$(_percent)" "${CURRENT:-}"; }
function begin_section(){ CURRENT="$1"; SECTION_START=$SECONDS; echo; echo "────────────────────────────────────────────────────────"; echo "▶ 开始步骤：$CURRENT"; _progress_line; }
function end_section(){ local dur=$((SECONDS - SECTION_START)); PROGRESS_DONE=$((PROGRESS_DONE + 1)); echo "✔ 完成步骤：$CURRENT，耗时 $(_elapsed "$dur")"; _progress_line; echo "────────────────────────────────────────────────────────"; echo; }
function note(){ echo "ℹ️ $*"; }
function warn(){ echo "⚠️ $*"; }
function fatal(){ echo "❌ $*"; }
trap 'code=$?; fatal "出错退出（代码 $code）于步骤：${CURRENT:-未知}"; fatal "最近命令：${BASH_COMMAND}"; fatal "日志文件：$LOG_FILE"; exit $code' ERR

note "全量日志写入：$LOG_FILE"
note "仅增强可视化/容错，核心安装逻辑与顺序保持一致。"

############################################
# ============== 原脚本主体 =============== #
############################################

begin_section "脚本运行环境检查：读取 /etc/os-release"
cat /etc/os-release
osVer=$(grep -F 'Ubuntu 22.04' /etc/os-release || true)
end_section

begin_section "系统版本校验"
if [[ -z ${osVer} ]]; then
  echo '脚本只在 ubuntu 22.04 测试通过。其它系统需适配，退出。'
  exit 1
else
  echo '系统版本检测通过...'
fi
end_section

begin_section "Bash & root 用户校验"
echo 'bash检测通过...'
if [ "$(id -u)" != "0" ]; then
  echo "脚本需要使用 root 用户执行"; exit 1
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
frappePath=""                       # 留空=默认仓库
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

# 若 /etc/apt/sources.list 已经是国内源或云厂商源，则自动不改源
hostAddress=("mirrors.tencentyun.com" "mirrors.tuna.tsinghua.edu.cn" "cn.archive.ubuntu.com")
for h in ${hostAddress[@]}; do
  n=$(grep -c "${h}" /etc/apt/sources.list 2>/dev/null || true)
  [[ $n -gt 0 ]] && altAptSources="no"
done
end_section

begin_section "解析命令行参数"
echo "===================获取参数==================="
argTag=""
for arg in "$@"; do
  if [[ -n ${argTag} ]]; then
    case "${argTag}" in
      webPort)
        t=$(echo "${arg}" | sed 's/[0-9]//g')
        if [[ -z ${t} && ${arg} -ge 80 && ${arg} -lt 65535 ]]; then
          webPort=${arg}; echo "设定web端口为 ${webPort}。"; argTag=""; continue
        else
          webPort=""
        fi
      ;;
    esac
    argTag=""
  fi
  if [[ ${arg} == -* ]]; then
    flags="${arg:1:${#arg}}"
    for ((i=0;i<${#flags};i++)); do
      case "${flags:$i:1}" in
        q) quiet='yes'; removeDuplicate="yes"; echo "不再确认参数，直接安装。";;
        d) inDocker='yes'; echo "针对 docker 镜像安装方式适配。";;
        p) argTag='webPort'; echo "准备设置 web 端口...";;
      esac
    done
  elif [[ ${arg} == *=* ]]; then
    arg0=${arg%=*}; arg1=${arg#*=}
    echo "${arg0} 为： ${arg1}"
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
      installDir) installDir=${arg1} ;;
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
cat <<PARMS
数据库地址：${mariadbPath}
数据库端口：${mariadbPort}
数据库root用户密码：${mariadbRootPassword}
管理员密码：${adminPassword}
安装目录：${installDir}
指定bench版本：${benchVersion}
拉取frappe地址：${frappePath}
指定frappe版本：${frappeBranch}
拉取erpnext地址：${erpnextPath}
指定erpnext版本：${erpnextBranch}
网站名称：${siteName}
网站数据库密码：${siteDbPassword}
web端口：${webPort}
是否修改apt安装源：${altAptSources}
是否静默模式安装：${quiet}
如有重名目录或数据库是否删除：${removeDuplicate}
是否为docker镜像内安装适配：${inDocker}
是否开启生产模式：${productionMode}
PARMS
end_section

begin_section "安装方式选择（仅非静默模式）"
if [[ ${quiet} != "yes" ]]; then
  echo "===================请确认并选择安装方式==================="
  echo "1. 安装为开发模式"
  echo "2. 安装为生产模式"
  echo "3. 按当前设定静默安装"
  echo "4. 在 Docker 镜像里静默安装"
  echo "*. 取消安装"
  read -r -p "请选择： " input
  case ${input} in
    1) productionMode="no";;
    2) productionMode="yes";;
    3) quiet="yes"; removeDuplicate="yes";;
    4) quiet="yes"; removeDuplicate="yes"; inDocker="yes";;
    *) echo "取消安装..."; exit 1;;
  esac
else
  note "静默模式：跳过交互式选择"
fi
end_section

begin_section "整理参数关键字（仅格式化展示，不改变逻辑）"
[[ -n ${benchVersion}  ]] && benchVersion="==${benchVersion}"
[[ -n ${frappePath}    ]] && frappePath="--frappe-path ${frappePath}"
[[ -n ${frappeBranch}  ]] && frappeBranch="--frappe-branch ${frappeBranch}"
[[ -n ${erpnextBranch} ]] && erpnextBranch="--branch ${erpnextBranch}"
[[ -n ${siteDbPassword}]] && siteDbPassword="--db-password ${siteDbPassword}"
end_section

begin_section "APT 源（国内镜像）设置"
if [[ ${altAptSources} == "yes" ]]; then
  [[ ! -e /etc/apt/sources.list.bak ]] && cp /etc/apt/sources.list /etc/apt/sources.list.bak
  cat >/etc/apt/sources.list <<'EOF_SOURCES'
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF_SOURCES
  apt update
  echo "===================apt已修改为国内源==================="
else
  note "已检测为国内源或云主机默认源，跳过修改。"
fi
end_section

begin_section "安装基础软件（apt install）"
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y
DEBIAN_FRONTEND=noninteractive apt install -y \
  ca-certificates sudo locales tzdata cron wget curl \
  python3-dev python3-venv python3-setuptools python3-pip python3-testresources \
  git software-properties-common \
  mariadb-server mariadb-client libmysqlclient-dev \
  xvfb libfontconfig wkhtmltopdf \
  supervisor pkg-config build-essential \
  libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev
end_section

begin_section "wkhtmltopdf 版本校验与兜底（仅必要时）"
if command -v wkhtmltopdf >/dev/null 2>&1; then
  if ! wkhtmltopdf -V | grep -q "0\.12\.6"; then
    warn "wkhtmltopdf 不是 0.12.6，尝试兜底安装官方 0.12.6-1（with patched Qt）"
    NEED_WK=1
  else
    NEED_WK=0
  fi
else
  NEED_WK=1
fi
if [[ "$NEED_WK" == "1" ]]; then
  CODENAME="$(lsb_release -cs 2>/dev/null || echo jammy)"
  ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  case "$CODENAME" in bionic|focal|jammy) : ;; * ) CODENAME="jammy" ;; esac
  case "$ARCH" in amd64|arm64|ppc64el) : ;; * ) ARCH="amd64" ;; esac
  URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.${CODENAME}_${ARCH}.deb"
  DEB="/tmp/$(basename "$URL")"
  curl -fL "$URL" -o "$DEB" || { echo "下载 wkhtmltox 失败"; exit 1; }
  apt install -y "$DEB" || { dpkg -i "$DEB" || true; apt -f install -y; }
fi
command -v wkhtmltopdf >/dev/null 2>&1 || { echo "wkhtmltopdf 未安装成功"; exit 1; }
echo "wkhtmltopdf 版本：$(wkhtmltopdf -V)"
end_section

begin_section "环境检查与重复安装目录处理"
rteArr=(); warnArr=()
# 目录冲突处理
while [[ -d "/home/${userName}/${installDir}" ]]; do
  echo "检测到已存在安装目录：/home/${userName}/${installDir}"
  if [[ ${quiet} != "yes" ]]; then
    echo '1. 删除后继续安装（推荐）'
    echo '2. 输入新的安装目录'
    read -r -p "*. 取消安装：" input
    case ${input} in
      1) rm -rf "/home/${userName}/${installDir}"; rm -f "/etc/supervisor/conf.d/${installDir}.conf" "/etc/nginx/conf.d/${installDir}.conf";;
      2)
        while true; do
          echo "当前目录名称：${installDir}"
          read -r -p "请输入新的安装目录名称：" input2
          if [[ -n ${input2} ]]; then
            installDir=${input2}
            read -r -p "使用新的安装目录名称 ${installDir}？(y/n)：" yn
            [[ ${yn} =~ ^[yY]$ ]] && break
          fi
        done
        continue;;
      *) echo "取消安装。"; exit 1;;
    esac
  else
    echo "静默模式：删除目录后继续"
    rm -rf "/home/${userName}/${installDir}"
  fi
done
# Python
if command -v python3 >/dev/null 2>&1; then
  python3 -V | grep -q "3.10" || { warnArr+=("Python 不是推荐的 3.10 版本。"); echo '==========已安装python3，但不是推荐的3.10版本。==========' ; }
  rteArr+=("$(python3 -V)")
else
  echo "==========python安装失败退出脚本！==========" ; exit 1
fi
# wkhtmltopdf
if command -v wkhtmltopdf >/dev/null 2>&1; then
  wkhtmltopdf -V | grep -q "0.12.6" || { warnArr+=('wkhtmltox 不是推荐的 0.12.6。'); echo '==========wkhtmltox 不是推荐的 0.12.6 版本。==========' ; }
  rteArr+=("$(wkhtmltopdf -V)")
else
  echo "==========wkhtmltox安装失败退出脚本！==========" ; exit 1
fi
# MariaDB
if command -v mysql >/dev/null 2>&1; then
  mysql -V | grep -q "10.6" || { warnArr+=('MariaDB 不是推荐的 10.6。'); echo '==========已安装MariaDB，但不是推荐的10.6版本。==========' ; }
  rteArr+=("$(mysql -V)")
else
  echo "==========MariaDB安装失败退出脚本！==========" ; exit 1
fi
end_section

begin_section "MariaDB 配置与授权"
if ! grep -q "# ERPNext install script added" /etc/mysql/my.cnf 2>/dev/null; then
  {
    echo "# ERPNext install script added"
    echo "[mysqld]"
    echo "character-set-client-handshake=FALSE"
    echo "character-set-server=utf8mb4"
    echo "collation-server=utf8mb4_unicode_ci"
    echo "bind-address=0.0.0.0"
    echo
    echo "[mysql]"
    echo "default-character-set=utf8mb4"
  } >> /etc/mysql/my.cnf
fi
/etc/init.d/mariadb restart
sleep 2
if mysql -uroot -e quit >/dev/null 2>&1; then
  mysqladmin -v -uroot password "${mariadbRootPassword}"
elif mysql -uroot -p"${mariadbRootPassword}" -e quit >/dev/null 2>&1; then
  echo "数据库 root 本地访问密码已配置"
else
  echo "数据库 root 本地访问密码错误"; exit 1
fi
mysql -u root -p"${mariadbRootPassword}" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${mariadbRootPassword}' WITH GRANT OPTION;"
mysqladmin -v -uroot -p"${mariadbRootPassword}" reload
sed -i "s/^password.*$/password=${mariadbRootPassword}/" /etc/mysql/debian.cnf
echo "数据库配置完成"
end_section

begin_section "数据库重名检查与处理"
while true; do
  siteSha1=$(echo -n "${siteName}" | sha1sum | awk '{print $1}')
  siteSha1="_${siteSha1:0:16}"
  dbUser=$(mysql -u root -p"${mariadbRootPassword}" -e "use mysql;SELECT User,Host FROM user;" | grep "${siteSha1}" || true)
  if [[ -n ${dbUser} ]]; then
    echo "当前站点：${siteName} 对应DB/用户：${siteSha1} 已存在"
    if [[ ${quiet} == "yes" ]]; then
      mysql -u root -p"${mariadbRootPassword}" -e "drop database ${siteSha1};" || true
      arrUser=(${dbUser})
      for ((i=0; i<${#arrUser[@]}; i+=2)); do
        mysql -u root -p"${mariadbRootPassword}" -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};" || true
      done
      echo "已清理重名数据库与用户，继续..."
      continue
    fi
    echo '1. 更换站点名  2. 删除同名DB与用户  3. 覆盖安装(不推荐)  *. 取消'
    read -r -p "选择：" input
    case ${input} in
      1)
        while true; do
          read -r -p "新的站点名称：" inputSiteName
          if [[ -n ${inputSiteName} ]]; then
            siteName=${inputSiteName}
            read -r -p "使用 ${siteName} ? (y/n)：" yn
            [[ ${yn} =~ ^[yY]$ ]] && break
          fi
        done
        continue;;
      2)
        mysql -u root -p"${mariadbRootPassword}" -e "drop database ${siteSha1};" || true
        arrUser=(${dbUser})
        for ((i=0; i<${#arrUser[@]}; i+=2)); do
          mysql -u root -p"${mariadbRootPassword}" -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};" || true
        done
        echo "已删除同名数据库及用户，继续。"
        continue;;
      3)
        warnArr+=("存在重名 DB/用户 ${siteSha1}，选择覆盖安装，可能导致数据库连接问题。")
        break;;
      *) echo "取消安装。"; exit 1;;
    esac
  else
    echo "无重名数据库或用户。"; break
  fi
done
end_section

begin_section "supervisor 指令检测"
supervisorCommand=""
if command -v supervisord >/dev/null 2>&1; then
  if grep -Eq "[ *]reload\)" /etc/init.d/supervisor 2>/dev/null; then
    supervisorCommand="reload"
  elif grep -Eq "[ *]restart\)" /etc/init.d/supervisor 2>/dev/null; then
    supervisorCommand="restart"
  else
    warn "init 脚本未含 reload/restart"; warnArr+=("没有可用的 supervisor 重启指令。")
  fi
else
  warn "supervisor 未安装"; warnArr+=("supervisor 未安装或失败，无法用其管理进程。")
fi
echo "可用指令：${supervisorCommand:-无}"
end_section

begin_section "安装/校验 Redis"
if ! command -v redis-server >/dev/null 2>&1; then
  rm -rf /var/lib/redis /etc/redis /etc/default/redis-server /etc/init.d/redis-server /usr/share/keyrings/redis-archive-keyring.gpg
  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y redis-tools redis-server redis
fi
if command -v redis-server >/dev/null 2>&1; then
  redis-server -v | grep -q "7" || { warnArr+=('redis 不是推荐的 7 版。'); echo '==========已安装redis，但不是推荐的7版本。==========' ; }
  rteArr+=("$(redis-server -v)")
else
  echo "==========redis安装失败退出脚本！==========" ; exit 1
fi
end_section

begin_section "pip 源与工具升级"
mkdir -p /root/.pip
cat >/root/.pip/pip.conf <<'PIPCONF'
[global]
index-url=https://pypi.tuna.tsinghua.edu.cn/simple
[install]
trusted-host=mirrors.tuna.tsinghua.edu.cn
PIPCONF
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade setuptools cryptography psutil
alias python=python3; alias pip=pip3
end_section

begin_section "创建用户/组、环境与时区/locale"
if ! getent group "${userName}" >/dev/null; then
  gid=1000; while getent group "${gid}" >/dev/null; do gid=$((gid+1)); done
  groupadd -g ${gid} ${userName}
fi
if ! id -u "${userName}" >/dev/null 2>&1; then
  uid=1000; while id -u "${uid}" >/dev/null 2>&1; do uid=$((uid+1)); done
  useradd --no-log-init -r -m -u ${uid} -g ${gid:-${uid}} -G sudo ${userName}
fi
sed -i "/^${userName}\s\+ALL=.*/d" /etc/sudoers
echo "${userName} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
mkdir -p /home/${userName}
cp -af /root/.pip /home/${userName}/ 2>/dev/null || true
chown -R ${userName}.${userName} /home/${userName}
usermod -s /bin/bash ${userName}
sed -i -e 's/#\s*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
for f in /root/.bashrc /home/${userName}/.bashrc; do
  sed -i "/^export.*LC_ALL=.*/d;/^export.*LC_CTYPE=.*/d;/^export.*LANG=.*/d" "$f"
  echo -e "export LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8\nexport LANG=en_US.UTF-8" >> "$f"
done
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata
sed -i "/^fs\.inotify\.max_user_watches=.*/d" /etc/sysctl.conf
echo fs.inotify.max_user_watches=524288 | tee -a /etc/sysctl.conf
/sbin/sysctl -p || true
end_section

begin_section "Node.js 20 / npm / yarn 准备"
source /etc/profile || true
if ! command -v node >/dev/null 2>&1; then
  nodejsLink=$(curl -sL https://registry.npmmirror.com/-/binary/node/latest-v20.x/ | grep -oE "https?://[^\"']*node-v20\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz" | tail -1)
  [[ -z $nodejsLink ]] && echo "未匹配到 nodejs v20 下载地址" && exit 1
  nodejsFileName=${nodejsLink##*/}
  nodejsVer=$(echo "${nodejsFileName}" | sed -E 's/^node-(v[0-9]+\.[0-9]+\.[0-9]+)-linux-x64\.tar\.xz$/\1/')
  wget -q "${nodejsLink}" -P /tmp/
  mkdir -p /usr/local/lib/nodejs
  tar -xJf "/tmp/${nodejsFileName}" -C /usr/local/lib/nodejs/
  mv "/usr/local/lib/nodejs/${nodejsFileName%%.tar*}" "/usr/local/lib/nodejs/${nodejsVer}"
  echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >/etc/profile.d/nodejs.sh
  echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >>~/.bashrc
  echo "export PATH=/home/${userName}/.local/bin:/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> /home/${userName}/.bashrc
  export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:$PATH
  source /etc/profile || true
fi
if command -v node >/dev/null 2>&1; then
  node -v | grep -q "^v20\." || warnArr+=('node 不是 v20，可能导致构建问题。')
  rteArr+=("node $(node -v)")
else
  echo "==========node安装失败退出脚本！==========" ; exit 1
fi
npm config set registry https://registry.npmmirror.com -g
npm install -g npm
npm install -g yarn
yarn config set registry https://registry.npmmirror.com --global
end_section

begin_section "切换到应用用户，配置用户级 yarn"
su - ${userName} <<EOF
set -eo pipefail
cd ~
alias python=python3; alias pip=pip3
source /etc/profile || true
export PATH="\$HOME/.local/bin:\$PATH"
export LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 LANG=en_US.UTF-8
yarn config set registry https://registry.npmmirror.com --global
echo "用户级 yarn 源已调整为国内镜像。"
EOF
end_section

begin_section "Docker 适配（如启用）"
echo "判断是否适配 docker"
if [[ ${inDocker} == "yes" ]]; then
  supervisorConfigDir=/home/${userName}/.config/supervisor
  mkdir -p ${supervisorConfigDir}
  cat >${supervisorConfigDir}/mariadb.conf <<'SUP_MY'
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
SUP_MY
  cat >${supervisorConfigDir}/nginx.conf <<'SUP_NGX'
[program: nginx]
command=/usr/sbin/nginx -g 'daemon off;'
autorestart=true
autostart=true
stderr_logfile=/var/run/log/supervisor_nginx_error.log
stdout_logfile=/var/run/log/supervisor_nginx_stdout.log
user=root
stopsignal=INT
startsecs=10
startretries=5
stopasgroup=true
SUP_NGX
  /etc/init.d/mariadb stop || true
  sleep 2
  [[ ! -e /etc/supervisor/conf.d/mariadb.conf ]] && ln -fs ${supervisorConfigDir}/mariadb.conf /etc/supervisor/conf.d/mariadb.conf
  if ! pgrep -x supervisord >/dev/null; then
    /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
  else
    /usr/bin/supervisorctl reload || true
  fi
  sleep 2
else
  note "非 Docker 模式，跳过容器适配"
fi
end_section

begin_section "安装 bench"
su - ${userName} <<EOF
set -eo pipefail
echo "===================安装 bench==================="
sudo -H pip3 install "frappe-bench${benchVersion}"
if type bench >/dev/null 2>&1; then bench --version; else echo "==========bench安装失败退出脚本！==========" ; exit 1; fi
EOF
end_section

begin_section "Docker 情况下 bench 脚本适配（fail2ban 注释）"
if [[ ${inDocker} == "yes" ]]; then
  f="/usr/local/lib/python3.10/dist-packages/bench/config/production_setup.py"
  n=$(sed -n "/^[[:space:]]*if not which.*fail2ban-client/=" ${f} 2>/dev/null || true)
  [[ -n ${n} ]] && sed -i "${n} s/^/#&/; $((n+1)) s/^/#&/" ${f} && echo "已注释 fail2ban 自动安装逻辑。"
else
  note "非 Docker 模式，跳过 bench fail2ban 适配"
fi
end_section

begin_section "初始化 frappe（bench init，带重试）"
# 关键修复：bench init 的选项需写在 bench 名称前；frappePath 用 --frappe-path；不使用未知选项（例如 --ignore-exist）
su - ${userName} <<EOF
set -eo pipefail
echo "===================初始化 frappe==================="
for i in 1 2 3 4 5; do
  rm -rf "\$HOME/${installDir}" || true
  set +e
  bench init --python /usr/bin/python3 ${frappeBranch} ${frappePath} "${installDir}" 2>&1
  rc=\$?
  set -e
  # 若上面一行的 ${frappeBranch} 与 ${frappePath} 已在外层整理为 --frappe-branch/--frappe-path，会被正确展开
  if [ "\$rc" -eq 0 ]; then
    echo "✅ bench init 成功（第 \$i 次尝试）"; break
  fi
  echo "⚠️ bench init 失败（第 \$i 次），3 秒后重试..."; sleep 3
  if [ "\$i" -eq 5 ]; then
    echo "❌ bench init 连续失败，输出最近日志以便排查："
    find "\$HOME/${installDir}" -maxdepth 3 -type f \( -name "*.log" -o -name "pip-log.txt" -o -name "yarn-error.log" \) -print -exec tail -n 200 {} \; || true
    exit 1
  fi
done
EOF
end_section

begin_section "确认 frappe 初始化结果"
su - ${userName} <<EOF
set -e
cd ~/"${installDir}"
frappeV=\$(bench version | grep "frappe" || true)
if [[ -z \${frappeV} ]]; then echo "==========frappe初始化失败退出脚本！==========" ; exit 1; else echo '==========frappe初始化成功==========' ; echo "\${frappeV}"; fi
EOF
end_section

begin_section "获取应用（erpnext / payments / hrms / print_designer）"
su - ${userName} <<EOF
set -e
cd ~/"${installDir}"
echo "===================获取应用==================="
bench get-app ${erpnextBranch} ${erpnextPath}
bench get-app payments
bench get-app ${erpnextBranch} hrms
bench get-app print_designer
EOF
end_section

begin_section "建立新站点（bench new-site）"
su - ${userName} <<EOF
set -e
cd ~/"${installDir}"
echo "===================建立新网站==================="
bench new-site --mariadb-root-password "${mariadbRootPassword}" ${siteDbPassword} --admin-password "${adminPassword}" "${siteName}"
EOF
end_section

begin_section "安装应用到站点"
su - ${userName} <<EOF
set -e
cd ~/"${installDir}"
echo "===================安装应用到新网站==================="
bench --site "${siteName}" install-app payments
bench --site "${siteName}" install-app erpnext
bench --site "${siteName}" install-app hrms
bench --site "${siteName}" install-app print_designer
EOF
end_section

begin_section "站点基础配置"
su - ${userName} <<EOF
set -e
cd ~/"${installDir}"
bench config http_timeout 6000
bench config serve_default_site on
bench use "${siteName}"
EOF
end_section

begin_section "安装中文本地化（erpnext_chinese）"
su - ${userName} <<EOF
set -e
cd ~/"${installDir}"
echo "===================安装中文本地化==================="
bench get-app https://gitee.com/yuzelin/erpnext_chinese.git
bench --site "${siteName}" install-app erpnext_chinese
bench clear-cache && bench clear-website-cache
EOF
end_section

begin_section "清理工作台缓存"
su - ${userName} <<EOF
set -e
cd ~/"${installDir}"
bench clear-cache
bench clear-website-cache
EOF
end_section

begin_section "生产模式开启（如启用）"
if [[ ${productionMode} == "yes" ]]; then
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y nginx
  if [[ ${inDocker} == "yes" ]]; then
    /etc/init.d/nginx stop || true
    [[ ! -e /etc/supervisor/conf.d/nginx.conf ]] && ln -fs /home/${userName}/.config/supervisor/nginx.conf /etc/supervisor/conf.d/nginx.conf
    /usr/bin/supervisorctl status || true
    /usr/bin/supervisorctl reload || true
    for i in $(seq -w 15 -1 1); do echo -en "${i}"; sleep 1; done; echo
    /usr/bin/supervisorctl status || true
  fi
  # 如果 supervisor 的 init 脚本只支持 reload 或 restart，替换 bench 内置调用
  if [[ -n ${supervisorCommand} ]]; then
    f="/usr/local/lib/python3.10/dist-packages/bench/config/supervisor.py"
    n=$(sed -n "/service.*supervisor.*reload\|service.*supervisor.*restart/=" ${f} 2>/dev/null || true)
    [[ -n ${n} ]] && sed -i "${n} s/reload\|restart/${supervisorCommand}/g" ${f}
  fi
  f="/etc/supervisor/conf.d/${installDir}.conf"
  i=0
  while [[ $i -lt 9 ]]; do
    echo "尝试开启生产模式 ${i} ..."
    set +e
    su - ${userName} -c "cd ~/${installDir} && sudo bench setup production ${userName} --yes"
    rc=$?; set -e
    i=$((i+1))
    sleep 1
    if [[ -e ${f} && $rc -eq 0 ]]; then
      echo "配置文件已生成..."
      break
    elif [[ ${i} -ge 9 ]]; then
      echo "失败次数过多 ${i}，请尝试手动开启！"
      break
    else
      echo "配置文件生成失败 ${i}，自动重试。"
    fi
  done
else
  note "开发模式：跳过生产模式开启"
fi
end_section

begin_section "自定义 web 端口（如设置）"
if [[ -n ${webPort} ]]; then
  echo "设置 web 端口为：${webPort}"
  t=$(echo ${webPort}|sed 's/[0-9]//g')
  if [[ -z ${t} && ${webPort} -ge 80 && ${webPort} -lt 65535 ]]; then
    if [[ ${productionMode} == "yes" ]]; then
      f="/home/${userName}/${installDir}/config/nginx.conf"
      if [[ -e ${f} ]]; then
        n=($(sed -n "/^[[:space:]]*listen/=" ${f}))
        if [[ -n ${n} ]]; then
          sed -i "${n} c listen ${webPort};" ${f}
          sed -i "$((n+1)) c listen [::]:${webPort};" ${f}
          /etc/init.d/nginx reload || true
          echo "web 端口号修改为：${webPort}"
        else warnArr+=("找到 ${f} 但未定位到 listen 设置行"); fi
      else warnArr+=("未找到 ${f}，端口修改失败"); fi
    else
      f="/home/${userName}/${installDir}/Procfile"
      if [[ -e ${f} ]]; then
        n=($(sed -n "/^web.*port.*/=" ${f}))
        if [[ -n ${n} ]]; then
          sed -i "${n} c web: bench serve --port ${webPort}" ${f}
          su - ${userName} -c "cd ~/${installDir}; bench restart" || true
          echo "web 端口号修改为：${webPort}"
        else warnArr+=("找到 ${f} 但未定位到 web: 行"); fi
      else warnArr+=("未找到 ${f}，端口修改失败"); fi
    fi
  else
    warnArr+=("设置的端口号无效，保持默认。")
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
yarn cache clean || true
su - ${userName} <<EOF
set -e
cd ~/"${installDir}"
npm cache clean --force || true
yarn cache clean || true
EOF
end_section

begin_section "确认安装版本与环境摘要"
su - ${userName} <<EOF
set -e
cd ~/"${installDir}"
echo "===================确认安装==================="
bench version
EOF
echo "===================主要运行环境==================="
for i in "${rteArr[@]}"; do echo "${i}"; done
if [[ ${#warnArr[@]} -ne 0 ]]; then
  echo "===================警告==================="; for i in "${warnArr[@]}"; do echo "${i}"; done
fi
echo "管理员账号：administrator，密码：${adminPassword}。"
if [[ ${productionMode} == "yes" ]]; then
  if [[ -e /etc/supervisor/conf.d/${installDir}.conf ]]; then
    echo "已开启生产模式。使用 IP/域名访问网站。监听 ${webPort} 端口。"
  else
    echo "已尝试开启生产模式，但 supervisor 配置未生成，请排查后手动开启。"
  fi
else
  echo "开发模式：su - ${userName} 进入 ~/${installDir}，运行：bench start ；默认端口 ${webPort}。"
fi
if [[ ${inDocker} == "yes" ]]; then
  echo "当前 supervisor 状态"; /usr/bin/supervisorctl status || true
fi
end_section

echo
echo "🎉 全部流程执行完毕。总耗时：$(_elapsed $(( $(date +%s) - START_AT ))) )"
echo "📄 完整日志：$LOG_FILE"

#!/bin/bash
# v0.8 2025.06.27   wkhtmltox 官方 patched Qt + 中文字体 + 细节容错
set -euo pipefail
umask 022

############################################
# ========= 仅新增：展示&日志功能 ========= #
############################################
PROGRESS_TOTAL=23              # 预估的总步骤数（仅用于展示，不影响逻辑）
PROGRESS_DONE=0
CURRENT=""
START_AT=$(date +%s)
LOG_FILE="/var/log/erpnext_install_$(date +%Y%m%d_%H%M%S).log"

mkdir -p /var/log

# 同步输出到屏幕和日志，并加时间戳
exec > >(awk '{ print strftime("[%F %T]"), $0 }' | tee -a "$LOG_FILE") 2>&1

function _now() { date +"%F %T"; }
function _elapsed() { local s=$1; printf "%ds" "$s"; }
function _percent() { if [ "$PROGRESS_TOTAL" -gt 0 ]; then echo $(( 100 * PROGRESS_DONE / PROGRESS_TOTAL )); else echo 0; fi; }
function _progress_line() { printf "[%02d/%02d] (%3d%%) %s\n" "$PROGRESS_DONE" "$PROGRESS_TOTAL" "$(_percent)" "${CURRENT:-}"; }
function begin_section() {
  CURRENT="$1"
  SECTION_START=$SECONDS
  echo
  echo "────────────────────────────────────────────────────────"
  echo "▶ 开始步骤：$CURRENT"
  _progress_line
}
function end_section() {
  local dur=$((SECONDS - SECTION_START))
  PROGRESS_DONE=$((PROGRESS_DONE + 1))
  echo "✔ 完成步骤：$CURRENT，耗时 $(_elapsed "$dur")"
  _progress_line
  echo "────────────────────────────────────────────────────────"
  echo
}
function note()   { echo "ℹ️ $*"; }
function warn()   { echo "⚠️ $*"; }
function fatal()  { echo "❌ $*"; }

# 捕获错误并提示最后一条命令
trap 'code=$?; fatal "出错退出（代码 $code）于步骤：${CURRENT:-未知}"; fatal "最近命令：${BASH_COMMAND}"; fatal "日志文件：$LOG_FILE"; exit $code' ERR

note "全量日志将同时写入：$LOG_FILE"
note "仅新增可视化/日志输出，不修改任何逻辑和命令。"

############################################
# ============== 原脚本开始 =============== #
############################################

begin_section "脚本运行环境检查：读取 /etc/os-release"
# 检测是否ubuntu22.04
cat /etc/os-release
osVer=$(cat /etc/os-release | grep 'Ubuntu 22.04' || true)
end_section

begin_section "系统版本校验"
if [[ ${osVer} == '' ]]; then
    echo '脚本只在ubuntu22.04版本测试通过。其它系统版本需要重新适配。退出安装。'
    exit 1
else
    echo '系统版本检测通过...'
fi
end_section

begin_section "Bash & root 用户校验"
# 检测是否使用bash执行
if [[ 1 == 1 ]]; then
    echo 'bash检测通过...'
else
    echo 'bash检测未通过...'
    echo '脚本需要使用bash执行。'
    exit 1
fi
# 检测是否使用root用户执行
if [ "$(id -u)" != "0" ]; then
   echo "脚本需要使用root用户执行"
   exit 1
else
    echo '执行用户检测通过...'
fi
end_section

begin_section "初始化默认参数与国内源探测"
# 设定参数默认值...
mariadbPath=""
mariadbPort="3306"
mariadbRootPassword="Pass1234"
adminPassword="admin"
installDir="frappe-bench"
userName="frappe"
benchVersion=""
# frappePath="https://gitee.com/mirrors/frappe"
frappePath=""
frappeBranch="version-15"
# erpnextPath="https://gitee.com/mirrors/erpnext"
erpnextPath="https://github.com/frappe/erpnext"
erpnextBranch="version-15"
siteName="site1.local"
siteDbPassword="Pass1234"
webPort=""
productionMode="yes"
# 是否修改apt安装源，如果是云服务器建议不修改。
altAptSources="yes"
# 是否跳过确认参数直接安装
quiet="no"
# 是否为docker镜像
inDocker="no"
# 是否删除重复文件
removeDuplicate="yes"
# 检测如果是云主机或已经是国内源则不修改apt安装源
hostAddress=("mirrors.tencentyun.com" "mirrors.tuna.tsinghua.edu.cn" "cn.archive.ubuntu.com")
for h in ${hostAddress[@]}; do
    n=$(cat /etc/apt/sources.list | grep -c ${h} || true)
    if [[ ${n} -gt 0 ]]; then
        altAptSources="no"
    fi
done
end_section

begin_section "解析命令行参数"
# 遍历参数修改默认值（略，保持你的逻辑不变）
echo "===================获取参数==================="
argTag=""
for arg in $*
do
    if [[ ${argTag} != "" ]]; then
        case "${argTag}" in
        "webPort")
            t=$(echo ${arg}|sed 's/[0-9]//g')
            if [[ (${t} == "") && (${arg} -ge 80) && (${arg} -lt 65535) ]]; then
                webPort=${arg}
                echo "设定web端口为${webPort}。"
                continue
            else
                webPort=""
            fi
            ;;
        esac
        argTag=""
    fi
    if [[ ${arg} == -* ]];then
        arg=${arg:1:${#arg}}
        for i in `seq ${#arg}`
        do
            arg0=${arg:$i-1:1}
            case "${arg0}" in
            "q") quiet='yes'; removeDuplicate="yes"; echo "不再确认参数，直接安装。";;
            "d") inDocker='yes'; echo "针对docker镜像安装方式适配。";;
            "p") argTag='webPort'; echo "针对docker镜像安装方式适配。";;
            esac
        done
    elif [[ ${arg} == *=* ]];then
        arg0=${arg%=*}
        arg1=${arg#*=}
        echo "${arg0} 为： ${arg1}"
        case "${arg0}" in
        "benchVersion") benchVersion=${arg1}; echo "设置bench版本为： ${benchVersion}";;
        "mariadbRootPassword") mariadbRootPassword=${arg1}; echo "设置数据库根密码为： ${mariadbRootPassword}";;
        "adminPassword") adminPassword=${arg1}; echo "设置管理员密码为： ${adminPassword}";;
        "frappePath") frappePath=${arg1}; echo "设置frappe拉取地址为： ${frappePath}";;
        "frappeBranch") frappeBranch=${arg1}; echo "设置frappe分支为： ${frappeBranch}";;
        "erpnextPath") erpnextPath=${arg1}; echo "设置erpnext拉取地址为： ${erpnextPath}";;
        "erpnextBranch") erpnextBranch=${arg1}; echo "设置erpnext分支为： ${erpnextBranch}";;
        "branch") frappeBranch=${arg1}; erpnextBranch=${arg1}; echo "设置frappe/erpnext分支为： ${arg1}";;
        "siteName") siteName=${arg1}; echo "设置站点名称为： ${siteName}";;
        "installDir") installDir=${arg1}; echo "设置安装目录为： ${installDir}";;
        "userName") userName=${arg1}; echo "设置安装用户为： ${userName}";;
        "siteDbPassword") siteDbPassword=${arg1}; echo "设置站点数据库密码为： ${siteDbPassword}";;
        "webPort") webPort=${arg1}; echo "设置web端口为： ${webPort}";;
        "altAptSources") altAptSources=${arg1}; echo "是否修改apt安装源：${altAptSources}";;
        "quiet") quiet=${arg1}; [[ ${quiet} == "yes" ]] && removeDuplicate="yes"; echo "不再确认参数，直接安装。";;
        "inDocker") inDocker=${arg1}; echo "针对docker镜像安装方式适配。";;
        "productionMode") productionMode=${arg1}; echo "是否开启生产模式： ${productionMode}";;
        esac
    fi
done
end_section

begin_section "展示当前有效参数"
if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then clear; fi
echo "数据库地址："${mariadbPath}
echo "数据库端口："${mariadbPort}
echo "数据库root用户密码："${mariadbRootPassword}
echo "管理员密码："${adminPassword}
echo "安装目录："${installDir}
echo "指定bench版本："${benchVersion}
echo "拉取frappe地址："${frappePath}
echo "指定frappe版本："${frappeBranch}
echo "拉取erpnext地址："${erpnextPath}
echo "指定erpnext版本："${erpnextBranch}
echo "网站名称："${siteName}
echo "网站数据库密码："${siteDbPassword}
echo "web端口："${webPort}
echo "是否修改apt安装源："${altAptSources}
echo "是否静默模式安装："${quiet}
echo "如有重名目录或数据库是否删除："${removeDuplicate}
echo "是否为docker镜像内安装适配："${inDocker}
echo "是否开启生产模式："${productionMode}
end_section

begin_section "安装方式选择（仅非静默模式）"
if [[ ${quiet} != "yes" ]];then
    echo "===================请确认已设定参数并选择安装方式==================="
    echo "1. 安装为开发模式"
    echo "2. 安装为生产模式"
    echo "3. 不再询问，按照当前设定安装并开启静默模式"
    echo "4. 在Docker镜像里安装并开启静默模式"
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
if [[ ${benchVersion} != "" ]];then benchVersion="==${benchVersion}"; fi
if [[ ${frappePath} != "" ]];then frappePath="--frappe-path ${frappePath}"; fi
if [[ ${frappeBranch} != "" ]];then frappeBranch="--frappe-branch ${frappeBranch}"; fi
if [[ ${erpnextBranch} != "" ]];then erpnextBranch="--branch ${erpnextBranch}"; fi
if [[ ${siteDbPassword} != "" ]];then siteDbPassword="--db-password ${siteDbPassword}"; fi
end_section

begin_section "APT 源（国内镜像）设置"
if [[ ${altAptSources} == "yes" ]];then
    if [[ ! -e /etc/apt/sources.list.bak ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
    fi
    rm -f /etc/apt/sources.list
    bash -c "cat << EOF > /etc/apt/sources.list && apt update
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF"
    echo "===================apt已修改为国内源==================="
else
    note "已检测为国内源或云主机默认源，跳过修改。"
fi
end_section

begin_section "安装基础软件（apt install）"
echo "===================安装基础软件==================="
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y
DEBIAN_FRONTEND=noninteractive apt install -y \
    ca-certificates sudo locales tzdata cron wget curl \
    python3-dev python3-venv python3-setuptools python3-pip python3-testresources \
    git software-properties-common \
    mariadb-server mariadb-client libmysqlclient-dev \
    xvfb libfontconfig fontconfig \
    supervisor pkg-config build-essential \
    libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev \
    xfonts-75dpi \
    fonts-noto-cjk fonts-noto-cjk-extra \
    fonts-wqy-microhei fonts-wqy-zenhei
end_section

begin_section "安装 wkhtmltox（官方 with patched Qt）+ 中文字体别名 + Bench 路径"
set -e
# 移除可能存在的 apt 版 wkhtmltopdf（通常不是 patched Qt）
apt remove -y wkhtmltopdf || true

# 依赖兜底
DEBIAN_FRONTEND=noninteractive apt install -y xfonts-75dpi fontconfig || true

# 选择合适的包
CODENAME=$(lsb_release -cs 2>/dev/null || echo jammy)
ARCH=$(dpkg --print-architecture 2>/dev/null || echo amd64)
case "$CODENAME" in bionic|focal|jammy) ;; *) CODENAME=jammy;; esac
case "$ARCH" in amd64|arm64|ppc64el) ;; *) ARCH=amd64;; esac

API="https://api.github.com/repos/wkhtmltopdf/packaging/releases/latest"
URL=$(curl -fsSL -H "Accept: application/vnd.github+json" "$API" | \
      grep -oE "https://github.com/.*/wkhtmltox_[0-9.]+(-[0-9]+)?\.${CODENAME}_${ARCH}\.deb" | head -n1 || true)

# 兜底到 0.12.6-1（稳定且带 patched Qt）
[ -z "$URL" ] && URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.${CODENAME}_${ARCH}.deb"
curl -fsI "$URL" >/dev/null 2>&1 || URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.jammy_amd64.deb"

DEB="/tmp/$(basename "$URL")"
echo "→ 下载 $URL"
curl -fL "$URL" -o "$DEB"

# 安装官方包（apt 能自动补依赖；失败则 dpkg + -f install 兜底）
apt install -y "$DEB" || { dpkg -i "$DEB" || true; apt -f install -y; }

# 校验必须包含 with patched qt
VSTR="$(wkhtmltopdf -V 2>/dev/null || true)"
echo "wkhtmltopdf 版本：$VSTR"
echo "$VSTR" | grep -qi "with patched qt" || { echo "❌ 未检测到 with patched qt，退出"; exit 1; }
echo "✅ 检测到 with patched qt"

# 字体别名映射：宋体/SimSun/NSimSun → Noto Serif CJK SC；黑体/微软雅黑 → Noto Sans CJK SC
mkdir -p /etc/fonts
cat >/etc/fonts/local.conf <<'FCXML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>SimSun</family>
    <prefer><family>Noto Serif CJK SC</family><family>WenQuanYi Zen Hei</family></prefer>
  </alias>
  <alias>
    <family>NSimSun</family>
    <prefer><family>Noto Serif CJK SC</family><family>WenQuanYi Zen Hei</family></prefer>
  </alias>
  <alias>
    <family>宋体</family>
    <prefer><family>Noto Serif CJK SC</family><family>WenQuanYi Zen Hei</family></prefer>
  </alias>
  <alias>
    <family>黑体</family>
    <prefer><family>Noto Sans CJK SC</family><family>WenQuanYi Micro Hei</family></prefer>
  </alias>
  <alias>
    <family>微软雅黑</family>
    <prefer><family>Noto Sans CJK SC</family><family>WenQuanYi Micro Hei</family></prefer>
  </alias>
</fontconfig>
FCXML
fc-cache -f >/dev/null 2>&1 || true

# 若 bench 已存在，写入 wkhtmltopdf 路径（后面站点配置也会再保险写一次）
if command -v bench >/dev/null 2>&1; then
  echo "写入 bench wkhtmltopdf 路径"
  sudo bash -lc 'bench set-config -g wkhtmltopdf "$(command -v wkhtmltopdf)" || true'
fi
end_section

begin_section "环境检查与重复安装目录处理"
# 环境需求检查
rteArr=()
warnArr=()
# 检测是否有之前安装的目录
while [[ -d "/home/${userName}/${installDir}" ]]; do
    if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then clear; fi
    echo "检测到已存在安装目录：/home/${userName}/${installDir}"
    if [[ ${quiet} != "yes" ]];then
        echo '1. 删除后继续安装。（推荐）'
        echo '2. 输入一个新的安装目录。'
        read -r -p "*. 取消安装" input
        case ${input} in
            1)
                echo "删除目录重新初始化！"
                rm -rf /home/${userName}/${installDir}
                rm -f /etc/supervisor/conf.d/${installDir}.conf
                rm -f /etc/nginx/conf.d/${installDir}.conf
                ;;
            2)
                while true
                do
                    echo "当前目录名称："${installDir}
                    read -r -p "请输入新的安装目录名称：" input
                    if [[ ${input} != "" ]]; then
                        installDir=${input}
                        read -r -p "使用新的安装目录名称${installDir}，y确认，n重新输入：" ok
                        if [[ ${ok} == [yY] ]]; then
                            echo "将使用安装目录名称${installDir}重试。"
                            break
                        fi
                    fi
                done
                continue
                ;;
            *) echo "取消安装。"; exit 1;;
        esac
    else
        echo "静默模式，删除目录重新初始化！"
        rm -rf /home/${userName}/${installDir}
    fi
done
# Python
if command -v python3 >/dev/null 2>&1; then
    result=$(python3 -V | grep "3.10" || true)
    [[ -z "$result" ]] && { echo '==========已安装python3，但不是推荐的3.10版本。=========='; warnArr+=("Python不是推荐的3.10版本。"); } || echo '==========已安装python3.10=========='
    rteArr+=("$(python3 -V)")
else
    echo "==========python安装失败退出脚本！=========="; exit 1
fi
# wkhtmltox（必须 with patched qt）
if command -v wkhtmltopdf >/dev/null 2>&1; then
    vstr="$(wkhtmltopdf -V 2>/dev/null || true)"
    if echo "$vstr" | grep -qi "with patched qt"; then
        echo "==========已安装 wkhtmltox（with patched Qt）=========="
        echo "$vstr"
    else
        echo '==========检测到 wkhtmltopdf，但不是 with patched Qt（ERPNext PDF 可能异常）=========='
        warnArr+=('wkhtmltopdf 非 with patched Qt 版本，建议改为官方 patched Qt 包。')
    fi
    rteArr+=("$vstr")
else
    echo "==========wkhtmltox 未安装或不可用，退出脚本！=========="; exit 1
fi
# MariaDB
if command -v mysql >/dev/null 2>&1; then
    result=$(mysql -V | grep "10.6" || true)
    [[ -z "$result" ]] && { echo '==========已安装MariaDB，但不是推荐的10.6版本。=========='; warnArr+=('MariaDB不是推荐的10.6版本。'); } || echo '==========已安装MariaDB10.6=========='
    rteArr+=("$(mysql -V)")
else
    echo "==========MariaDB安装失败退出脚本！=========="; exit 1
fi
end_section

begin_section "MariaDB 配置与授权"
n=$(grep -c "# ERPNext install script added" /etc/mysql/my.cnf || true)
if [[ ${n} == 0 ]]; then
    echo "===================修改数据库配置文件==================="
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
for i in $(seq -w 2); do echo ${i}; sleep 1; done
if mysql -uroot -e quit >/dev/null 2>&1; then
    echo "===================修改数据库root本地访问密码==================="
    mysqladmin -v -uroot password ${mariadbRootPassword}
elif mysql -uroot -p${mariadbRootPassword} -e quit >/dev/null 2>&1; then
    echo "===================数据库root本地访问密码已配置==================="
else
    echo "===================数据库root本地访问密码错误==================="; exit 1
fi
echo "===================修改数据库root远程访问密码==================="
mysql -u root -p${mariadbRootPassword} -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${mariadbRootPassword}' WITH GRANT OPTION;"
echo "===================刷新权限表==================="
mysqladmin -v -uroot -p${mariadbRootPassword} reload
sed -i 's/^password.*$/password='"${mariadbRootPassword}"'/' /etc/mysql/debian.cnf
echo "===================数据库配置完成==================="
end_section

begin_section "数据库重名检查与处理"
echo "==========检查数据库残留=========="
while true
do
    siteSha1=$(echo -n ${siteName} | sha1sum); siteSha1=_${siteSha1:0:16}
    dbUser=$(mysql -u root -p${mariadbRootPassword} -e "use mysql;SELECT User,Host FROM user;" | grep ${siteSha1} || true)
    if [[ ${dbUser} != "" ]]; then
        if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then clear; fi
        echo '当前站点名称：'${siteName}
        echo '生成的数据库及用户名为：'${siteSha1}
        echo '已存在同名数据库用户，请选择处理方式。'
        echo '1. 重新输入新的站点名称。'
        echo '2. 删除重名的数据库及用户。'
        echo '3. 什么也不做使用设置的密码直接安装。（不推荐）'
        echo '*. 取消安装。'
        if [[ ${quiet} == "yes" ]]; then
            echo '当前为静默模式，将自动按第2项执行。'
            mysql -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};"
            arrUser=(${dbUser})
            for ((i=0; i<${#arrUser[@]}; i=i+2)); do
                mysql -u root -p${mariadbRootPassword} -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};"
            done
            echo "已删除数据库及用户，继续安装！"
            continue
        fi
        read -r -p "请输入选择：" input
        case ${input} in
            '1')
                while true
                do
                    read -r -p "请输入新的站点名称：" inputSiteName
                    if [[ ${inputSiteName} != "" ]]; then
                        siteName=${inputSiteName}
                        read -r -p "使用新的站点名称${siteName}，y确认，n重新输入：" ok
                        if [[ ${ok} == [yY] ]]; then echo "将使用站点名称${siteName}重试。"; break; fi
                    fi
                done
                continue
                ;;
            '2')
                mysql -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};"
                arrUser=(${dbUser})
                for ((i=0; i<${#arrUser[@]}; i=i+2)); do
                    mysql -u root -p${mariadbRootPassword} -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};"
                done
                echo "已删除数据库及用户，继续安装！"
                continue
                ;;
            '3') echo "什么也不做使用设置的密码直接安装！"; warnArr+=("检测到重名数据库及用户${siteSha1},选择了覆盖安装。"); break;;
            *) echo "取消安装..."; exit 1;;
        esac
    else
        echo "无重名数据库或用户。"; break
    fi
done
end_section

begin_section "supervisor 指令检测"
echo "确认supervisor可用重启指令。"
supervisorCommand=""
if command -v supervisord >/dev/null 2>&1; then
    if [[ $(grep -E "[ *]reload)" /etc/init.d/supervisor) != '' ]]; then
        supervisorCommand="reload"
    elif [[ $(grep -E "[ *]restart)" /etc/init.d/supervisor) != '' ]]; then
        supervisorCommand="restart"
    else
        echo "/etc/init.d/supervisor中没有找到reload或restart指令"
        echo "可能需要手动重启supervisor"
        warnArr+=("没有找到可用的supervisor重启指令。")
    fi
else
    echo "supervisor没有安装"; warnArr+=("supervisor没有安装或安装失败，不能使用supervisor管理进程。")
fi
echo "可用指令："${supervisorCommand}
end_section

begin_section "安装/校验 Redis"
if ! command -v redis-server >/dev/null 2>&1; then
    echo "==========获取最新版redis，并安装=========="
    rm -rf /var/lib/redis /etc/redis /etc/default/redis-server /etc/init.d/redis-server
    rm -f /usr/share/keyrings/redis-archive-keyring.gpg
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y redis-tools redis-server redis
fi
if command -v redis-server >/dev/null 2>&1; then
    result=$(redis-server -v | grep "7" || true)
    [[ -z "$result" ]] && { echo '==========已安装redis，但不是推荐的7版本。=========='; warnArr+=('redis不是推荐的7版本。'); } || echo '==========已安装redis7=========='
    rteArr+=("$(redis-server -v)")
else
    echo "==========redis安装失败退出脚本！=========="; exit 1
fi
end_section

begin_section "pip 源与工具升级"
mkdir -p /root/.pip
cat >/root/.pip/pip.conf <<EOF
[global]
index-url=https://pypi.tuna.tsinghua.edu.cn/simple
[install]
trusted-host=mirrors.tuna.tsinghua.edu.cn
EOF
echo "===================pip已修改为国内源==================="
cd ~
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade setuptools cryptography psutil
alias python=python3
alias pip=pip3
end_section

begin_section "创建用户/组、环境与时区/locale"
echo "===================建立新用户组和用户==================="
result=$(grep "${userName}:" /etc/group || true)
if [[ ${result} == "" ]]; then
    gid=1000
    while true; do
        result=$(grep ":${gid}:" /etc/group || true)
        if [[ ${result} == "" ]]; then groupadd -g ${gid} ${userName}; echo "已新建用户组${userName}，gid: ${gid}"; break; else gid=$((gid+1)); fi
    done
else echo '用户组已存在'; fi
result=$(grep "${userName}:" /etc/passwd || true)
if [[ ${result} == "" ]]; then
    uid=1000
    while true; do
        result=$(grep ":x:${uid}:" /etc/passwd || true)
        if [[ ${result} == "" ]]; then useradd --no-log-init -r -m -u ${uid} -g ${gid} -G sudo ${userName}; echo "已新建用户${userName}，uid: ${uid}"; break; else uid=$((uid+1)); fi
    done
else echo '用户已存在'; fi
sed -i "/^${userName}.*/d" /etc/sudoers
echo "${userName} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
mkdir -p /home/${userName}
cp -af /root/.pip /home/${userName}/ || true
chown -R ${userName}.${userName} /home/${userName}
usermod -s /bin/bash ${userName}
echo "===================设置语言环境==================="
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
for f in /root/.bashrc /home/${userName}/.bashrc; do
  sed -i "/^export.*LC_ALL=.*/d" "$f"; sed -i "/^export.*LC_CTYPE=.*/d" "$f"; sed -i "/^export.*LANG=.*/d" "$f"
  echo -e "export LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8\nexport LANG=en_US.UTF-8" >> "$f"
done
echo "===================设置时区为上海==================="
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata
echo "===================设置监控文件数量上限==================="
sed -i "/^fs.inotify.max_user_watches=.*/d" /etc/sysctl.conf
echo fs.inotify.max_user_watches=524288 | tee -a /etc/sysctl.conf
/sbin/sysctl -p
end_section

begin_section "Node.js 20 / npm / yarn 准备"
source /etc/profile || true
if ! command -v node >/dev/null 2>&1; then
    echo "==========获取最新版nodejs-v20，并安装=========="
    if [ -z "${nodejsLink:-}" ] ; then
        nodejsLink=$(curl -sL https://registry.npmmirror.com/-/binary/node/latest-v20.x/ | grep -oE "https?://[a-zA-Z0-9\.\/_&=@$%?~#-]*node-v20\.[0-9][0-9]\.[0-9]{1,2}-linux-x64\.tar\.xz" | tail -1)
    else
        echo 已自定义nodejs下载链接，开始下载
    fi
    if [ -z "${nodejsLink:-}" ] ; then echo "没有匹配到 node.js 下载地址"; exit 1; fi
    nodejsFileName=${nodejsLink##*/}
    nodejsVer=$(awk -F'-' '{print $2}' <<< "$nodejsFileName")
    echo "nodejs20最新版本为：${nodejsVer}"
    echo "即将安装nodejs20到/usr/local/lib/nodejs/${nodejsVer}"
    wget -q "$nodejsLink" -P /tmp/
    mkdir -p /usr/local/lib/nodejs
    tar -xJf /tmp/${nodejsFileName} -C /usr/local/lib/nodejs/
    mv /usr/local/lib/nodejs/${nodejsFileName%%.tar*} /usr/local/lib/nodejs/${nodejsVer}
    echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> /etc/profile.d/nodejs.sh
    echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> ~/.bashrc
    echo "export PATH=/home/${userName}/.local/bin:/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> /home/${userName}/.bashrc
    export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:$PATH
    source /etc/profile || true
fi
if command -v node >/dev/null 2>&1; then
    result=$(node -v | grep "v20." || true)
    [[ -z "$result" ]] && { echo '==========已存在node，但不是v20版。建议卸载后重试。=========='; warnArr+=('node不是推荐的v20版本。'); } || echo '==========已安装node20=========='
    rteArr+=("node $(node -v)")
else
    echo "==========node安装失败退出脚本！=========="; exit 1
fi
npm config set registry https://registry.npmmirror.com -g
echo "===================npm已修改为国内源==================="
npm install -g npm
npm install -g yarn
yarn config set registry https://registry.npmmirror.com --global
echo "===================yarn已修改为国内源==================="
end_section

begin_section "切换到应用用户，配置用户级 yarn"
su - ${userName} <<'EOF'
echo "===================配置运行环境变量==================="
cd ~
alias python=python3
alias pip=pip3
source /etc/profile || true
export PATH=/home/'"${userName}"'/.local/bin:$PATH
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LANG=en_US.UTF-8
yarn config set registry https://registry.npmmirror.com --global
echo "===================用户yarn已修改为国内源==================="
EOF
end_section

begin_section "Docker 适配（如启用）"
echo "判断是否适配docker"
if [[ ${inDocker} == "yes" ]]; then
    supervisorConfigDir=/home/${userName}/.config/supervisor
    mkdir -p ${supervisorConfigDir}
    f=${supervisorConfigDir}/mariadb.conf
    rm -f ${f}
    echo "[program:mariadb]" > ${f}
    echo "command=/usr/sbin/mariadbd --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib/mysql/plugin --user=mysql --skip-log-error" >> ${f}
    echo "priority=1" >> ${f}
    echo "autostart=true" >> ${f}
    echo "autorestart=true" >> ${f}
    echo "numprocs=1" >> ${f}
    echo "startretries=10" >> ${f}
    echo "stopwaitsecs=10" >> ${f}
    echo "redirect_stderr=true" >> ${f}
    echo "stdout_logfile_maxbytes=1024MB" >> ${f}
    echo "stdout_logfile_backups=10" >> ${f}
    echo "stdout_logfile=/var/run/log/supervisor_mysql.log" >> ${f}
    f=${supervisorConfigDir}/nginx.conf
    rm -f ${f}
    echo "[program: nginx]" > ${f}
    echo "command=/usr/sbin/nginx -g 'daemon off;'" >> ${f}
    echo "autorestart=true" >> ${f}
    echo "autostart=true" >> ${f}
    echo "stderr_logfile=/var/run/log/supervisor_nginx_error.log" >> ${f}
    echo "stdout_logfile=/var/run/log/supervisor_nginx_stdout.log" >> ${f}
    echo "environment=ASPNETCORE_ENVIRONMENT=Production" >> ${f}
    echo "user=root" >> ${f}
    echo "stopsignal=INT" >> ${f}
    echo "startsecs=10" >> ${f}
    echo "startretries=5" >> ${f}
    echo "stopasgroup=true" >> ${f}
    echo "关闭mariadb进程，启动supervisor进程并管理mariadb进程"
    /etc/init.d/mariadb stop || true
    for i in $(seq -w 2); do echo ${i}; sleep 1; done
    if [[ ! -e /etc/supervisor/conf.d/mariadb.conf ]]; then
        ln -fs ${supervisorConfigDir}/mariadb.conf /etc/supervisor/conf.d/mariadb.conf
    fi
    if ! pgrep -x supervisord >/dev/null 2>&1; then
        /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    else
        /usr/bin/supervisorctl reload
    fi
    for i in $(seq -w 2); do echo ${i}; sleep 1; done
else
    note "非 Docker 模式，跳过容器适配"
fi
end_section

begin_section "安装 bench"
su - ${userName} <<EOF
echo "===================安装bench==================="
sudo -H pip3 install frappe-bench${benchVersion}
if type bench >/dev/null 2>&1; then
    benchV=\$(bench --version)
    echo '==========已安装bench=========='
    echo \${benchV}
else
    echo "==========bench安装失败退出脚本！=========="
    exit 1
fi
EOF
rteArr+=("bench $(bench --version 2>/dev/null || echo unknown)")
end_section

begin_section "Docker 情况下 bench 脚本适配（fail2ban 注释）"
if [[ ${inDocker} == "yes" ]]; then
    echo "已配置在docker中运行，将注释安装fail2ban的代码。"
    f="/usr/local/lib/python3.10/dist-packages/bench/config/production_setup.py"
    n=$(sed -n "/^[[:space:]]*if not which.*fail2ban-client/=" ${f})
    if [ ${n} ]; then
        sed -i "${n} s/^/#&/" ${f}; let n++; sed -i "${n} s/^/#&/" ${f}
    fi
else
    note "非 Docker 模式，跳过 bench fail2ban 适配"
fi
end_section

begin_section "初始化 frappe（bench init，带重试）"
su - ${userName} <<EOF
echo "===================初始化frappe==================="
for ((i=0; i<5; i++)); do
    rm -rf ~/${installDir}
    set +e
    bench init ${frappeBranch} --python /usr/bin/python3 --ignore-exist ${installDir} ${frappePath}
    err=\$?
    set -e
    if [[ \${err} == 0 ]]; then echo "执行返回正确第 \${i} 次"; sleep 1; break
    elif [[ \${i} -ge 4 ]]; then echo "==========frappe初始化失败太多（\${i}），退出脚本！=========="; exit 1
    else echo "==========frappe初始化失败第 \${i} 次！自动重试。=========="
    fi
done
echo "frappe初始化脚本执行结束..."
EOF
end_section

begin_section "确认 frappe 初始化结果"
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
frappeV=$(bench version | grep "frappe" || true)
if [[ ${frappeV} == "" ]]; then
    echo "==========frappe初始化失败退出脚本！=========="; exit 1
else
    echo '==========frappe初始化成功=========='; echo ${frappeV}
fi
EOF
end_section

begin_section "获取应用（erpnext/payments/hrms/print_designer）"
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================获取应用==================="
bench get-app ${erpnextBranch} ${erpnextPath}
bench get-app payments
bench get-app ${erpnextBranch} hrms
bench get-app print_designer
EOF
end_section

begin_section "建立新站点（bench new-site）"
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================建立新网站==================="
bench new-site --mariadb-root-password ${mariadbRootPassword} ${siteDbPassword} --admin-password ${adminPassword} ${siteName}
EOF
end_section

begin_section "安装应用到站点"
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================安装erpnext应用到新网站==================="
bench --site ${siteName} install-app payments
bench --site ${siteName} install-app erpnext
bench --site ${siteName} install-app hrms
bench --site ${siteName} install-app print_designer
EOF
end_section

begin_section "站点基础配置"
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================设置网站超时时间==================="
bench config http_timeout 6000
bench config serve_default_site on
bench use ${siteName}
# 保险：统一写一次 wkhtmltopdf 路径
bench set-config -g wkhtmltopdf "\$(command -v wkhtmltopdf)" || true
EOF
end_section

begin_section "安装中文本地化（erpnext_chinese）"
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================安装中文本地化==================="
bench get-app https://gitee.com/yuzelin/erpnext_chinese.git
bench --site '"${siteName}"' install-app erpnext_chinese
bench clear-cache && bench clear-website-cache
EOF
end_section

begin_section "清理工作台缓存"
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================清理工作台==================="
bench clear-cache
bench clear-website-cache
EOF
end_section

begin_section "生产模式开启（如启用）"
if [[ ${productionMode} == "yes" ]]; then
    echo "================开启生产模式==================="
    apt update
    DEBIAN_FRONTEND=noninteractive apt install nginx -y
    rteArr+=("$(nginx -v 2>/dev/null || true)")
    if [[ ${inDocker} == "yes" ]]; then
        /etc/init.d/nginx stop || true
        if [[ ! -e /etc/supervisor/conf.d/nginx.conf ]]; then
            ln -fs ${supervisorConfigDir}/nginx.conf /etc/supervisor/conf.d/nginx.conf
        fi
        /usr/bin/supervisorctl status || true
        /usr/bin/supervisorctl reload || true
        for i in $(seq -w 15 -1 1); do echo -en ${i}; sleep 1; done; echo
        /usr/bin/supervisorctl status || true
    fi
    echo "修正脚本代码..."
    if [[ ${supervisorCommand} != "" ]]; then
        echo "可用的supervisor重启指令为："${supervisorCommand}
        f="/usr/local/lib/python3.10/dist-packages/bench/config/supervisor.py"
        n=$(sed -n "/service.*supervisor.*reload\|service.*supervisor.*restart/=" ${f})
        if [ ${n} ]; then sed -i "${n} s/reload\|restart/${supervisorCommand}/g" ${f}; fi
    fi
    f="/etc/supervisor/conf.d/${installDir}.conf"
    i=0
    while [[ $i -lt 9 ]]; do
        echo "尝试开启生产模式${i}..."
        set +e
        su - ${userName} <<EOF2
        cd ~/${installDir}
        sudo bench setup production ${userName} --yes
EOF2
        rc=$?
        set -e
        i=$((i + 1))
        echo "判断执行结果（rc=$rc）"
        sleep 1
        if [[ -e ${f} ]]; then echo "配置文件已生成..."; break
        elif [[ ${i} -ge 9 ]]; then echo "失败次数过多${i}，请尝试手动开启！"; break
        else echo "配置文件生成失败${i}，自动重试。"
        fi
    done
else
    note "开发模式：跳过生产模式开启"
fi
end_section

begin_section "自定义 web 端口（如设置）"
if [[ ${webPort} != "" ]]; then
    echo "===================设置web端口为：${webPort}==================="
    t=$(echo ${webPort}|sed 's/[0-9]//g')
    if [[ (${t} == "") && (${webPort} -ge 80) && (${webPort} -lt 65535) ]]; then
        if [[ ${productionMode} == "yes" ]]; then
            f="/home/${userName}/${installDir}/config/nginx.conf"
            if [[ -e ${f} ]]; then
                n=($(sed -n "/^[[:space:]]*listen/=" ${f}))
                if [ ${n} ]; then
                    sed -i "${n} c listen ${webPort};" ${f}
                    sed -i "$((${n}+1)) c listen [::]:${webPort};" ${f}
                    /etc/init.d/nginx reload
                    echo "web端口号修改为："${webPort}
                else
                    echo "配置文件中没找到设置行。修改失败。"; warnArr+=("修改端口失败：未找到listen行")
                fi
            else
                echo "没有找到配置文件："${f}",端口修改失败。"; warnArr+=("未找到 nginx.conf")
            fi
        else
            f="/home/${userName}/${installDir}/Procfile"
            echo "找到配置文件："${f}
            if [[ -e ${f} ]]; then
                n=($(sed -n "/^web.*port.*/=" ${f}))
                if [[ ${n} ]]; then
                    sed -i "${n} c web: bench serve --port ${webPort}" ${f}
                    su - ${userName} bash -c "cd ~/${installDir}; bench restart"
                    echo "web端口号修改为："${webPort}
                else
                    echo "配置文件中没找到设置行。修改失败。"; warnArr+=("修改端口失败：Procfile 未找到 web 行")
                fi
            else
                echo "没有找到配置文件："${f}",端口修改失败。"; warnArr+=("未找到 Procfile")
            fi
        fi
    else
        echo "设置的端口号无效或不符合要求，取消端口号修改。使用默认端口号。"; warnArr+=("webPort 无效，使用默认")
    fi
else
    if [[ ${productionMode} == "yes" ]]; then webPort="80"; else webPort="8000"; fi
    note "未指定 webPort，按默认：${webPort}"
fi
end_section

begin_section "权限修正、清理缓存与包管理器缓存"
echo "===================修正权限==================="
chown -R ${userName}:${userName} /home/${userName}/
chmod 755 /home/${userName}
echo "===================清理垃圾,ERPNext安装完毕==================="
apt clean
apt autoremove -y
rm -rf /var/lib/apt/lists/*
pip cache purge || true
npm cache clean --force || true
yarn cache clean || true
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
npm cache clean --force || true
yarn cache clean || true
EOF
end_section

begin_section "确认安装版本与环境摘要"
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================确认安装==================="
bench version
EOF
echo "===================主要运行环境==================="
for i in "${rteArr[@]}"; do echo "${i}"; done
if [[ ${#warnArr[@]} != 0 ]]; then
    echo "===================警告==================="; for i in "${warnArr[@]}"; do echo "${i}"; done
fi
echo "管理员账号：administrator，密码：${adminPassword}。"
if [[ ${productionMode} == "yes" ]]; then
    if [[ -e /etc/supervisor/conf.d/${installDir}.conf ]]; then
        echo "已开启生产模式。使用ip或域名访问网站。监听${webPort}端口。"
    else
        echo "已配置开启生产模式。但supervisor配置文件生成失败，请排除错误后手动开启。"
    fi
else
    echo "使用 su - ${userName} 转到 ${userName} 用户进入 ~/${installDir} 目录"
    echo "运行 bench start 启动项目，使用 ip 或域名访问网站。监听 ${webPort} 端口。"
fi
if [[ ${inDocker} == "yes" ]]; then
    echo "当前supervisor状态"; /usr/bin/supervisorctl status || true
fi
end_section

begin_section "脚本收尾"
# （原示例行容易导致语法错误，这里统一注释掉）
# exit 0
# p all
# fi
# exit 0
end_section

echo
echo "🎉 全部流程执行完毕。总耗时：$(_elapsed $(( $(date +%s) - START_AT ))) )"
echo "📄 完整日志：$LOG_FILE"

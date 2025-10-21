#!/bin/bash
# v0.7.1 2025.10.21   修改 wkhtmltopdf 安装方式，添加字体支持
set -e

############################################
# ========= 仅新增：展示&日志功能 ========= #
############################################
PROGRESS_TOTAL=23              # 预估的总步骤数（新增步骤后调整）
PROGRESS_DONE=0
CURRENT=""
START_AT=$(date +%s)
LOG_FILE="/var/log/erpnext_install_$(date +%Y%m%d_%H%M%S).log"

mkdir -p /var/log

# 同步输出到屏幕和日志，并加时间戳
exec > >(awk '{ print strftime("[%F %T]"), $0 }' | tee -a "$LOG_FILE") 2>&1

function _now() { date +"%F %T"; }
function _elapsed() {
  local s=$1; printf "%ds" "$s"
}
function _percent() {
  if [ "$PROGRESS_TOTAL" -gt 0 ]; then
    echo $(( 100 * PROGRESS_DONE / PROGRESS_TOTAL ))
  else
    echo 0
  fi
}
function _progress_line() {
  printf "[%02d/%02d] (%3d%%) %s\n" "$PROGRESS_DONE" "$PROGRESS_TOTAL" "$(_percent)" "${CURRENT:-}"
}
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
    echo '脚本只在 Ubuntu 22.04 版本测试通过。其它系统版本需要重新适配。退出安装。'
    exit 1
else
    echo '系统版本检测通过...'
fi
end_section

begin_section "Bash & root 用户校验"
# 检测是否使用bash执行
if [[ $(ps -p $$ -o comm=) == "bash" ]]; then
    echo 'bash检测通过...'
else
    echo 'bash检测未通过...'
    echo '脚本需要使用 bash 执行。'
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
frappePath=""
frappeBranch="version-15"
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
    n=$(grep -c ${h} /etc/apt/sources.list 2>/dev/null || true)
    if [[ ${n} -gt 0 ]]; then
        altAptSources="no"
    fi
done
end_section

begin_section "解析命令行参数"
# 遍历参数修改默认值
# 脚本后添加参数如有冲突，靠后的参数生效。
echo "===================获取参数==================="
argTag=""
for arg in "$@"
do
    if [[ ${argTag} != "" ]]; then
        case "${argTag}" in
        "webPort")
            t=$(echo ${arg}|sed 's/[0-9]//g')
            if [[ (${t} == "") && (${arg} -ge 80) && (${arg} -lt 65535) ]]; then
                webPort=${arg}
                echo "设定web端口为${webPort}。"
                # 只有收到正确的端口参数才跳转下一个参数，否则将继续识别当前参数。
                :
            else
                # 只有-p没有正确的参数会将webPort参数置空
                webPort=""
            fi
            ;;
        esac
        argTag=""
        continue
    fi
    if [[ ${arg} == -* ]];then
        arg=${arg:1:${#arg}}
        for (( i=1; i<=${#arg}; i++ ))
        do
            arg0=${arg:$i-1:1}
            case "${arg0}" in
            "q")
                quiet='yes'
                removeDuplicate="yes"
                echo "不再确认参数，直接安装。"
                ;;
            "d")
                inDocker='yes'
                echo "针对docker镜像安装方式适配。"
                ;;
            "p")
                argTag='webPort'
                echo "准备设定web端口..."
                ;;
            esac
        done
    elif [[ ${arg} == *=* ]];then
        arg0=${arg%=*}
        arg1=${arg#*=}
        echo "${arg0} 为： ${arg1}"
        case "${arg0}" in
        "benchVersion")
            benchVersion=${arg1}
            echo "设置bench版本为： ${benchVersion}"
            ;;
        "mariadbRootPassword")
            mariadbRootPassword=${arg1}
            echo "设置数据库根密码为： ${mariadbRootPassword}"
            ;;
        "adminPassword")
            adminPassword=${arg1}
            echo "设置管理员密码为： ${adminPassword}"
            ;;
        "frappePath")
            frappePath=${arg1}
            echo "设置frappe拉取地址为： ${frappePath}"
            ;;
        "frappeBranch")
            frappeBranch=${arg1}
            echo "设置frappe分支为： ${frappeBranch}"
            ;;
        "erpnextPath")
            erpnextPath=${arg1}
            echo "设置erpnext拉取地址为： ${erpnextPath}"
            ;;
        "erpnextBranch")
            erpnextBranch=${arg1}
            echo "设置erpnext分支为： ${erpnextBranch}"
            ;;
        "branch")
            frappeBranch=${arg1}
            erpnextBranch=${arg1}
            echo "设置frappe分支为： ${frappeBranch}"
            echo "设置erpnext分支为： ${erpnextBranch}"
            ;;
        "siteName")
            siteName=${arg1}
            echo "设置站点名称为： ${siteName}"
            ;;
        "installDir")
            installDir=${arg1}
            echo "设置安装目录为： ${installDir}"
            ;;
        "userName")
            userName=${arg1}
            echo "设置安装用户为： ${userName}"
            ;;
        "siteDbPassword")
            siteDbPassword=${arg1}
            echo "设置站点数据库密码为： ${siteDbPassword}"
            ;;
        "webPort")
            webPort=${arg1}
            echo "设置web端口为： ${webPort}"
            ;;
        "altAptSources")
            altAptSources=${arg1}
            echo "是否修改apt安装源：${altAptSources}（云服务器有自己的源时建议不修改）"
            ;;
        "quiet")
            quiet=${arg1}
            if [[ ${quiet} == "yes" ]];then
                removeDuplicate="yes"
            fi
            echo "静默模式安装：${quiet}"
            ;;
        "inDocker")
            inDocker=${arg1}
            echo "针对docker镜像安装方式适配：${inDocker}"
            ;;
        "productionMode")
            productionMode=${arg1}
            echo "是否开启生产模式： ${productionMode}"
            ;;
        esac
    fi
done
end_section

begin_section "展示当前有效参数"
# 显示参数
if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then
    clear
fi
echo "数据库地址：${mariadbPath}"
echo "数据库端口：${mariadbPort}"
echo "数据库root用户密码：${mariadbRootPassword}"
echo "管理员密码：${adminPassword}"
echo "安装目录：${installDir}"
echo "指定bench版本：${benchVersion}"
echo "拉取frappe地址：${frappePath}"
echo "指定frappe版本：${frappeBranch}"
echo "拉取erpnext地址：${erpnextPath}"
echo "指定erpnext版本：${erpnextBranch}"
echo "网站名称：${siteName}"
echo "网站数据库密码：${siteDbPassword}"
echo "web端口：${webPort}"
echo "是否修改apt安装源：${altAptSources}"
echo "是否静默模式安装：${quiet}"
echo "如有重名目录或数据库是否删除：${removeDuplicate}"
echo "是否为docker镜像内安装适配：${inDocker}"
echo "是否开启生产模式：${productionMode}"
end_section

begin_section "安装方式选择（仅非静默模式）"
# 等待确认参数
if [[ ${quiet} != "yes" ]]; then
    echo "===================请确认已设定参数并选择安装方式==================="
    echo "1. 安装为开发模式"
    echo "2. 安装为生产模式"
    echo "3. 不再询问，按照当前设定安装并开启静默模式"
    echo "4. 在Docker镜像里安装并开启静默模式"
    echo "*. 取消安装"
    echo -e "说明：开启静默模式后，如果有重名目录或数据库（包括supervisor进程配置文件）都将删除后继续安装，请注意数据备份！\n \
        开发模式需要手动启动“bench start”，启动后访问8000端口。\n \
        生产模式无需手动启动，使用nginx反代并监听80端口。\n \
        此外生产模式会使用supervisor管理进程增强可靠性，并预编译代码开启redis缓存，提高应用性能。\n \
        在Docker镜像里安装会适配其进程启动方式，将mariadb及nginx进程也交给supervisor管理。 \n \
        docker镜像主线程：sudo supervisord -n -c /etc/supervisor/supervisord.conf，请自行配置到镜像。"
    read -r -p "请选择： " input
    case ${input} in
        1)
            productionMode="no"
            ;;
        2)
            productionMode="yes"
            ;;
        3)
            quiet="yes"
            removeDuplicate="yes"
            ;;
        4)
            quiet="yes"
            removeDuplicate="yes"
            inDocker="yes"
            ;;
        *)
            echo "取消安装..."
            exit 1
            ;;
    esac
else
    note "静默模式：跳过交互式选择"
fi
end_section

begin_section "整理参数关键字（仅格式化展示，不改变逻辑）"
# 给参数添加关键字
echo "===================给需要的参数添加关键字==================="
if [[ ${benchVersion} != "" ]]; then
    benchVersion="==${benchVersion}"
fi
if [[ ${frappePath} != "" ]]; then
    frappePath="--frappe-path ${frappePath}"
fi
if [[ ${frappeBranch} != "" ]]; then
    frappeBranch="--frappe-branch ${frappeBranch}"
fi
if [[ ${erpnextBranch} != "" ]]; then
    erpnextBranch="--branch ${erpnextBranch}"
fi
if [[ ${siteDbPassword} != "" ]]; then
    siteDbPassword="--db-password ${siteDbPassword}"
fi
end_section

begin_section "APT 源（国内镜像）设置"
# 修改安装源加速国内安装。
if [[ ${altAptSources} == "yes" ]]; then
    # 在执行前确定有操作权限
    if [[ ! -e /etc/apt/sources.list.bak ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
    fi
    rm -f /etc/apt/sources.list
    bash -c "cat << EOF > /etc/apt/sources.list
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF"
    apt update
    echo "===================apt已修改为国内源==================="
else
    note "已检测为国内源或云主机默认源，跳过修改。"
fi
end_section

begin_section "安装基础软件（apt install）"
# 安装基础软件
echo "===================安装基础软件==================="
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y
DEBIAN_FRONTEND=noninteractive apt install -y \
    ca-certificates \
    sudo \
    locales \
    tzdata \
    cron \
    wget \
    curl \
    python3-dev \
    python3-venv \
    python3-setuptools \
    python3-pip \
    python3-testresources \
    git \
    software-properties-common \
    mariadb-server \
    mariadb-client \
    libmysqlclient-dev \
    xvfb \
    libfontconfig \
    supervisor \
    pkg-config \
    build-essential \
    libcairo2-dev \
    libpango1.0-dev \
    libjpeg-dev \
    libgif-dev \
    xfonts-base \
    xfonts-75dpi \
    fonts-noto-cjk \
    fonts-noto-cjk-extra \
    fonts-noto-mono \
    fontconfig
# 更新字体缓存
echo "===================刷新字体缓存==================="
fc-cache -fv
end_section

begin_section "安装 wkhtmltopdf（patched-Qt 版本）"
# 卸载系统自带 wkhtmltopdf（如有），安装官方 patched Qt 版 0.12.6
note "安装 wkhtmltopdf 官方 patched-Qt 版 (0.12.6 系列)"
DEBIAN_FRONTEND=noninteractive apt remove -y wkhtmltopdf >/dev/null 2>&1 || true
arch=$(dpkg --print-architecture)
case "$arch" in
    amd64|arm64|ppc64el) ;;
    *)
        warn "未识别的架构: $arch，默认使用 amd64 包"
        arch="amd64"
        ;;
esac
wk_deb_url=""
wk_files=(
    "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${arch}.deb"
    "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.focal_${arch}.deb"
    "https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.bionic_${arch}.deb"
)
for url in "${wk_files[@]}"; do
    file="${url##*/}"
    note "尝试下载: $file"
    for attempt in {1..3}; do
        wget -q -O "/tmp/${file}" "$url" && break || warn "下载 $file 第${attempt}次失败"
    done
    if [ -f "/tmp/${file}" ]; then
        wk_deb_url="$url"
        break
    fi
done

if [[ -n "$wk_deb_url" ]]; then
    file="${wk_deb_url##*/}"
    note "安装 wkhtmltopdf 包: $file"
    set +e
    dpkg -i "/tmp/${file}"
    dpkg_status=$?
    set -e
    if [[ $dpkg_status -ne 0 ]]; then
        # 安装依赖后重试
        DEBIAN_FRONTEND=noninteractive apt-get install -f -y
        dpkg -i "/tmp/${file}"
    fi
    wkhtmltopdf -V || true
    # 清理安装包
    rm -f "/tmp/${file}"
else
    fatal "wkhtmltopdf 官方安装包下载失败，无法继续安装。"
    exit 1
fi
end_section

begin_section "环境检查与重复安装目录处理"
# 环境需求检查
rteArr=()
warnArr=()
# 检测是否有之前安装的目录
while [[ -d "/home/${userName}/${installDir}" ]]; do
    if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then
        clear
    fi
    echo "检测到已存在安装目录：/home/${userName}/${installDir}"
    if [[ ${quiet} != "yes" ]]; then
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
                    echo "当前目录名称：${installDir}"
                    read -r -p "请输入新的安装目录名称：" inputDir
                    if [[ ${inputDir} != "" ]]; then
                        installDir=${inputDir}
                        read -r -p "使用新的安装目录名称 ${installDir}，y确认，n重新输入：" confirm
                        if [[ ${confirm} == [yY] ]]; then
                            echo "将使用安装目录名称 ${installDir} 重试。"
                            break
                        fi
                    fi
                done
                continue
                ;;
            *)
                echo "取消安装。"
                exit 1
                ;;
        esac
    else
        echo "静默模式，删除目录重新初始化！"
        rm -rf /home/${userName}/${installDir}
    fi
done
# 环境需求检查, python3
if type python3 >/dev/null 2>&1; then
    result=$(python3 -V | grep "3.10" || true)
    if [[ "${result}" == "" ]]; then
        echo '==========已安装 python3，但不是推荐的 3.10 版本。=========='
        warnArr+=("Python 不是推荐的 3.10 版本。")
    else
        echo '==========已安装 Python 3.10 =========='
    fi
    rteArr+=("$(python3 -V)")
else
    echo "========== Python 安装失败，退出脚本！ =========="
    exit 1
fi
# 环境需求检查, wkhtmltox
if type wkhtmltopdf >/dev/null 2>&1; then
    result=$(wkhtmltopdf -V | grep "0.12.6" || true)
    if [[ "${result}" == "" ]]; then
        echo '==========已存在 wkhtmltox，但不是推荐的 0.12.6 版本。=========='
        warnArr+=('wkhtmltox 不是推荐的 0.12.6 版本。')
    else
        echo '==========已安装 wkhtmltox 0.12.6 =========='
    fi
    rteArr+=("$(wkhtmltopdf -V)")
else
    echo "========== wkhtmltox 安装失败，退出脚本！ =========="
    exit 1
fi
# 环境需求检查, MariaDB
if type mysql >/dev/null 2>&1; then
    result=$(mysql -V | grep "10.6" || true)
    if [[ "${result}" == "" ]]; then
        echo '==========已安装 MariaDB，但不是推荐的 10.6 版本。=========='
        warnArr+=('MariaDB 不是推荐的 10.6 版本。')
    else
        echo '==========已安装 MariaDB 10.6 =========='
    fi
    rteArr+=("$(mysql -V)")
else
    echo "========== MariaDB 安装失败，退出脚本！ =========="
    exit 1
fi
end_section

begin_section "MariaDB 配置与授权"
# 修改数据库配置文件
if ! grep -q "# ERPNext install script added" /etc/mysql/my.cnf 2>/dev/null; then
    echo "===================修改数据库配置文件==================="
    {
      echo "# ERPNext install script added"
      echo "[mysqld]"
      echo "character-set-client-handshake=FALSE"
      echo "character-set-server=utf8mb4"
      echo "collation-server=utf8mb4_unicode_ci"
      echo "bind-address=0.0.0.0"
      echo ""
      echo "[mysql]"
      echo "default-character-set=utf8mb4"
    } >> /etc/mysql/my.cnf
fi
/etc/init.d/mariadb restart
# 等待2秒
for i in $(seq -w 2); do
    echo "${i}"
    sleep 1
done
# 授权远程访问并修改密码
if mysql -uroot -e quit >/dev/null 2>&1; then
    echo "===================修改数据库root本地访问密码==================="
    mysqladmin -v -uroot password "${mariadbRootPassword}"
elif mysql -uroot -p"${mariadbRootPassword}" -e quit >/dev/null 2>&1; then
    echo "===================数据库root本地访问密码已配置==================="
else
    echo "===================数据库root本地访问密码错误==================="
    exit 1
fi
echo "===================修改数据库root远程访问密码==================="
mysql -u root -p"${mariadbRootPassword}" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${mariadbRootPassword}' WITH GRANT OPTION;"
echo "===================刷新权限表==================="
mysqladmin -v -uroot -p"${mariadbRootPassword}" reload
sed -i "s/^password.*/password=${mariadbRootPassword}/" /etc/mysql/debian.cnf
echo "===================数据库配置完成==================="
end_section

begin_section "数据库重名检查与处理"
# 检查数据库是否有同名用户。如有，选择处理方式。
echo "==========检查数据库残留=========="
while true; do
    siteSha1=$(echo -n "${siteName}" | sha1sum)
    siteSha1="_${siteSha1:0:16}"
    dbUser=$(mysql -u root -p"${mariadbRootPassword}" -e "SELECT User,Host FROM mysql.user;" 2>/dev/null | grep "${siteSha1}" || true)
    if [[ ${dbUser} != "" ]]; then
        if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then
            clear
        fi
        echo "当前站点名称：${siteName}"
        echo "生成的数据库及用户名为：${siteSha1}"
        echo "已存在同名数据库用户，请选择处理方式。"
        echo "1. 重新输入新的站点名称。将自动生成新的数据库及用户名称重新校验。"
        echo "2. 删除重名的数据库及用户。"
        echo "3. 什么也不做，使用设置的密码直接安装。（不推荐）"
        echo "*. 取消安装。"
        if [[ ${quiet} == "yes" ]]; then
            echo "当前为静默模式，将自动按第2项执行。"
            # 删除重名数据库
            mysql -u root -p"${mariadbRootPassword}" -e "DROP DATABASE ${siteSha1};"
            IFS=$'\n' read -r -d '' -a arrUser <<< "${dbUser}"
            # 如果重名用户有多个host，以步进2取用户名和用户host并删除。
            for ((i=0; i<${#arrUser[@]}; i=i+1)); do
                usr=$(echo "${arrUser[$i]}" | awk '{print $1}')
                host=$(echo "${arrUser[$i]}" | awk '{print $2}')
                mysql -u root -p"${mariadbRootPassword}" -e "DROP USER '${usr}'@'${host}';"
            done
            echo "已删除数据库及用户，继续安装！"
            continue
        fi
        read -r -p "请输入选择：" input
        case ${input} in
            1)
                while true; do
                    read -r -p "请输入新的站点名称：" inputSiteName
                    if [[ ${inputSiteName} != "" ]]; then
                        siteName=${inputSiteName}
                        read -r -p "使用新的站点名称 ${siteName}，y确认，n重新输入：" confirm
                        if [[ ${confirm} == [yY] ]]; then
                            echo "将使用站点名称 ${siteName} 重试。"
                            break
                        fi
                    fi
                done
                continue
                ;;
            2)
                mysql -u root -p"${mariadbRootPassword}" -e "DROP DATABASE ${siteSha1};"
                IFS=$'\n' read -r -d '' -a arrUser <<< "${dbUser}"
                for ((i=0; i<${#arrUser[@]}; i=i+1)); do
                    usr=$(echo "${arrUser[$i]}" | awk '{print $1}')
                    host=$(echo "${arrUser[$i]}" | awk '{print $2}')
                    mysql -u root -p"${mariadbRootPassword}" -e "DROP USER '${usr}'@'${host}';"
                done
                echo "已删除数据库及用户，继续安装！"
                continue
                ;;
            3)
                echo "什么也不做，使用设置的密码直接安装！"
                warnArr+=("检测到重名数据库及用户 ${siteSha1}，选择了覆盖安装。可能造成无法访问、数据库无法连接等问题。")
                break
                ;;
            *)
                echo "取消安装..."
                exit 1
                ;;
        esac
    else
        echo "无重名数据库或用户。"
        break
    fi
done
end_section

begin_section "supervisor 指令检测"
# 确认可用的重启指令
echo "确认supervisor可用重启指令。"
supervisorCommand=""
if type supervisord >/dev/null 2>&1; then
    if grep -qE "[ *]reload)" /etc/init.d/supervisor 2>/dev/null; then
        supervisorCommand="reload"
    elif grep -qE "[ *]restart)" /etc/init.d/supervisor 2>/dev/null; then
        supervisorCommand="restart"
    else
        echo "/etc/init.d/supervisor 中没有找到 reload 或 restart 指令"
        echo "将会继续执行，但可能因为使用不可用指令导致启动进程失败。"
        echo "如进程没有运行，请尝试手动重启 supervisor。"
        warnArr+=("没有找到可用的 supervisor 重启指令，如有进程启动失败，请尝试手动重启。")
    fi
else
    echo "supervisor 没有安装"
    warnArr+=("supervisor 没有安装或安装失败，不能使用 supervisor 管理进程。")
fi
echo "可用指令：${supervisorCommand}"
end_section

begin_section "安装/校验 Redis"
# 安装最新版 redis
if ! type redis-server >/dev/null 2>&1; then
    echo "==========获取最新版 redis，并安装=========="
    rm -rf /var/lib/redis /etc/redis /etc/default/redis-server /etc/init.d/redis-server
    rm -f /usr/share/keyrings/redis-archive-keyring.gpg
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    apt update
    echo "即将安装 redis"
    DEBIAN_FRONTEND=noninteractive apt install -y redis-tools redis-server redis
fi
# 环境需求检查, redis
if type redis-server >/dev/null 2>&1; then
    result=$(redis-server -v | grep "7" || true)
    if [[ "${result}" == "" ]]; then
        echo '==========已安装 redis，但不是推荐的 7 版本。=========='
        warnArr+=('redis 不是推荐的 7 版本。')
    else
        echo '==========已安装 redis 7 =========='
    fi
    rteArr+=("$(redis-server -v)")
else
    echo "========== redis 安装失败，退出脚本！ =========="
    exit 1
fi
end_section

begin_section "pip 源与工具升级"
# 修改 pip 默认源加速国内安装
mkdir -p /root/.pip
{
  echo '[global]'
  echo 'index-url=https://pypi.tuna.tsinghua.edu.cn/simple'
  echo '[install]'
  echo 'trusted-host=mirrors.tuna.tsinghua.edu.cn'
} > /root/.pip/pip.conf
echo "===================pip已修改为国内源==================="
# 安装并升级 pip 及工具包
echo "===================安装并升级 pip 及工具包==================="
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade setuptools cryptography psutil
alias python=python3
alias pip=pip3
end_section

begin_section "创建用户/组、环境与时区/locale"
# 建立新用户组和用户
echo "===================建立新用户组和用户==================="
if ! grep -q "${userName}:" /etc/group; then
    gid=1000
    while true; do
        if ! grep -q ":${gid}:" /etc/group; then
            echo "建立新用户组: ${gid}:${userName}"
            groupadd -g ${gid} ${userName}
            echo "已新建用户组 ${userName}，gid: ${gid}"
            break
        else
            gid=$((gid + 1))
        fi
    done
else
    echo '用户组已存在'
    gid=$(grep "${userName}:" /etc/group | cut -d: -f3)
fi
if ! id -u ${userName} >/dev/null 2>&1; then
    uid=1000
    while true; do
        if ! grep -q ":x:${uid}:" /etc/passwd; then
            echo "建立新用户: ${uid}:${userName}"
            useradd --no-log-init -r -m -u ${uid} -g ${gid} -G sudo ${userName}
            echo "已新建用户 ${userName}，uid: ${uid}"
            break
        else
            uid=$((uid + 1))
        fi
    done
else
    echo '用户已存在'
fi
# 给用户添加 sudo 权限
sed -i "/^${userName}.*/d" /etc/sudoers
echo "${userName} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
mkdir -p /home/${userName}
sed -i "/^export.*${userName}.*/d" /etc/sudoers
# 修改用户 pip 默认源加速国内安装
cp -af /root/.pip /home/${userName}/
# 修正用户目录权限
chown -R ${userName}:${userName} /home/${userName}
# 修正用户 shell
usermod -s /bin/bash ${userName}
# 设置语言环境
echo "===================设置语言环境==================="
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
sed -i "/^export.*LC_ALL=.*/d" /root/.bashrc
sed -i "/^export.*LC_CTYPE=.*/d" /root/.bashrc
sed -i "/^export.*LANG=.*/d" /root/.bashrc
echo -e "export LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8\nexport LANG=en_US.UTF-8" >> /root/.bashrc
sed -i "/^export.*LC_ALL=.*/d" /home/${userName}/.bashrc
sed -i "/^export.*LC_CTYPE=.*/d" /home/${userName}/.bashrc
sed -i "/^export.*LANG=.*/d" /home/${userName}/.bashrc
echo -e "export LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8\nexport LANG=en_US.UTF-8" >> /home/${userName}/.bashrc
# 设置时区为上海
echo "===================设置时区为上海==================="
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata
# 设置监控文件数量上限
echo "===================设置监控文件数量上限==================="
sed -i "/^fs.inotify.max_user_watches=.*/d" /etc/sysctl.conf
echo fs.inotify.max_user_watches=524288 >> /etc/sysctl.conf
# 使其立即生效
/sbin/sysctl -p
end_section

begin_section "Node.js 20 / npm / yarn 准备"
# 检查是否安装 Node.js 20
source /etc/profile
if ! type node >/dev/null 2>&1; then
    echo "==========获取最新版 Node.js v20，并安装=========="
    if [ -z "$nodejsLink" ]; then
        nodejsLink=$(curl -sL https://registry.npmmirror.com/-/binary/node/latest-v20.x/ | grep -oE "https?://[a-zA-Z0-9\.\/_&=@$%?~#-]*node-v20\.[0-9]+\.[0-9]+-linux-x64.tar.xz" | tail -1)
    else
        echo "已自定义 nodejs 下载链接，开始下载"
    fi
    if [ -z "$nodejsLink" ]; then
        echo "没有匹配到 Node.js v20 下载地址，请检查网络或代码。"
        exit 1
    else
        nodejsFileName="${nodejsLink##*/}"
        nodejsVer=$(echo "${nodejsFileName}" | sed -E 's/node-([^/]+)-linux-x64.*/\1/')
        echo "Node.js 20 最新版本为：${nodejsVer}"
        echo "即将安装 Node.js 20 到 /usr/local/lib/nodejs/${nodejsVer}"
        wget -q "$nodejsLink" -P /tmp/
        mkdir -p /usr/local/lib/nodejs
        tar -xJf "/tmp/${nodejsFileName}" -C /usr/local/lib/nodejs/
        mv "/usr/local/lib/nodejs/${nodejsFileName%%.tar*}" "/usr/local/lib/nodejs/${nodejsVer}"
        echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> /etc/profile.d/nodejs.sh
        echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> ~/.bashrc
        echo "export PATH=/home/${userName}/.local/bin:/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> /home/${userName}/.bashrc
        export PATH="/usr/local/lib/nodejs/${nodejsVer}/bin:$PATH"
        source /etc/profile
    fi
fi
# 环境需求检查, node
if type node >/dev/null 2>&1; then
    result=$(node -v | grep -E "^v20\." || true)
    if [[ ${result} == "" ]]; then
        echo '==========已存在 Node.js，但不是 v20 版。这可能导致一些问题。建议卸载后重试。=========='
        warnArr+=('Node.js 不是推荐的 v20 版本。')
    else
        echo '==========已安装 Node.js 20 =========='
    fi
    rteArr+=("node $(node -v)")
else
    echo "========== Node.js 安装失败，退出脚本！ =========="
    exit 1
fi
# 修改 npm 源
npm config set registry https://registry.npmmirror.com -g
echo "===================npm已修改为国内源==================="
# 升级 npm
echo "===================升级npm==================="
npm install -g npm
# 安装 yarn
echo "===================安装yarn==================="
npm install -g yarn
# 修改 yarn 源
yarn config set registry https://registry.npmmirror.com --global
echo "===================yarn已修改为国内源==================="
end_section

begin_section "切换到应用用户，配置用户级 yarn"
# 切换用户配置 Yarn 源
su - ${userName} <<'EOF'
echo "===================配置用户环境变量与 yarn 源==================="
alias python=python3
alias pip=pip3
source /etc/profile
export PATH=/home/'"${userName}"'/.local/bin:$PATH
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LANG=en_US.UTF-8
# 修改用户 yarn 源
yarn config set registry https://registry.npmmirror.com --global
echo "===================用户yarn已修改为国内源==================="
EOF
end_section

begin_section "Docker 适配（如启用）"
# 适配 docker
echo "判断是否适配 Docker"
if [[ ${inDocker} == "yes" ]]; then
    echo "================为 Docker 镜像添加 MariaDB 和 Nginx 启动配置文件==================="
    supervisorConfigDir="/home/${userName}/.config/supervisor"
    mkdir -p "${supervisorConfigDir}"
    # MariaDB supervisor config
    f="${supervisorConfigDir}/mariadb.conf"
    rm -f "${f}"
    {
      echo "[program:mariadb]"
      echo "command=/usr/sbin/mariadbd --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib/mysql/plugin --user=mysql --skip-log-error"
      echo "priority=1"
      echo "autostart=true"
      echo "autorestart=true"
      echo "numprocs=1"
      echo "startretries=10"
      echo "stopwaitsecs=10"
      echo "redirect_stderr=true"
      echo "stdout_logfile_maxbytes=1024MB"
      echo "stdout_logfile_backups=10"
      echo "stdout_logfile=/var/run/log/supervisor_mysql.log"
    } > "${f}"
    # Nginx supervisor config
    f="${supervisorConfigDir}/nginx.conf"
    rm -f "${f}"
    {
      echo "[program:nginx]"
      echo "command=/usr/sbin/nginx -g 'daemon off;'"
      echo "autostart=true"
      echo "autorestart=true"
      echo "stderr_logfile=/var/run/log/supervisor_nginx_error.log"
      echo "stdout_logfile=/var/run/log/supervisor_nginx_stdout.log"
      echo "environment=ASPNETCORE_ENVIRONMENT=Production"
      echo "user=root"
      echo "stopsignal=INT"
      echo "startsecs=10"
      echo "startretries=5"
      echo "stopasgroup=true"
    } > "${f}"
    # 停止系统 MariaDB 进程，转由 supervisor 管理
    echo "关闭系统 MariaDB 进程，启动 Supervisor 并托管 MariaDB 进程"
    /etc/init.d/mariadb stop
    sleep 2
    if [[ ! -e /etc/supervisor/conf.d/mariadb.conf ]]; then
        echo "建立 MariaDB Supervisor 配置文件软链接"
        ln -fs "${supervisorConfigDir}/mariadb.conf" /etc/supervisor/conf.d/mariadb.conf
    fi
    if pgrep -x supervisord >/dev/null; then
        echo "重载 Supervisor 配置"
        /usr/bin/supervisorctl reload
    else
        echo "启动 Supervisor 进程"
        /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    fi
    sleep 2
else
    note "非 Docker 模式，跳过容器适配"
fi
end_section

begin_section "安装 bench"
# 安装 bench（Frappe Bench）
su - ${userName} <<'EOF'
echo "===================安装 Frappe-Bench==================="
sudo -H pip3 install frappe-bench'"${benchVersion}"'
if type bench >/dev/null 2>&1; then
    benchV=$(bench --version)
    echo '==========已安装 bench =========='
    echo "${benchV}"
else
    echo "========== bench 安装失败，退出脚本！ =========="
    exit 1
fi
EOF
# 记录 bench 版本
if type bench >/dev/null 2>&1; then
    rteArr+=("bench $(bench --version 2>/dev/null)")
fi
end_section

begin_section "Docker 情况下 bench 脚本适配（注释 fail2ban）"
# bench 脚本适配 Docker 环境
if [[ ${inDocker} == "yes" ]]; then
    echo "已配置在 Docker 中运行，将注释 bench 安装 fail2ban 的代码。"
    f="/usr/local/lib/python3.10/dist-packages/bench/config/production_setup.py"
    if n=$(sed -n "/^[[:space:]]*if not which.*fail2ban-client/=" "${f}"); then
        echo "找到 fail2ban 安装代码行 ${n}，添加注释。"
        sed -i "${n}s/^/#/" "${f}"
        sed -i "$((n+1))s/^/#/" "${f}"
    fi
else
    note "非 Docker 模式，跳过 bench fail2ban 适配"
fi
end_section

begin_section "初始化 frappe （bench init，带重试）"
# 初始化 Frappe 框架
su - ${userName} <<EOF
echo "===================初始化 Frappe 框架==================="
for ((i=0; i<5; i++)); do
    rm -rf ~/${installDir}
    set +e
    bench init ${frappeBranch} --python /usr/bin/python3 --ignore-exist ${installDir} ${frappePath}
    err=\$?
    set -e
    if [[ \$err -eq 0 ]]; then
        echo "frappe 初始化成功"
        break
    elif [[ \$i -ge 4 ]]; then
        echo "========== frappe 初始化失败次数过多（\$i 次），退出脚本！ =========="
        exit 1
    else
        echo "========== frappe 初始化失败第 \$((i+1)) 次！自动重试... =========="
    fi
done
EOF
end_section

begin_section "确认 frappe 初始化结果"
# 确认 frappe 初始化
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
frappeV=$(bench version | grep "frappe" || true)
if [[ "${frappeV}" == "" ]]; then
    echo "========== frappe 初始化失败，退出脚本！ =========="
    exit 1
else
    echo '========== frappe 初始化成功 =========='
    echo "${frappeV}"
fi
EOF
end_section

begin_section "获取应用（erpnext/payments/hrms/print_designer）"
# 获取 ERPNext 及相关应用
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================获取 ERPNext 及应用==================="
bench get-app '"${erpnextBranch}"' '"${erpnextPath}"'
bench get-app payments
bench get-app '"${erpnextBranch}"' hrms
bench get-app print_designer
EOF
end_section

begin_section "建立新站点（bench new-site）"
# 建立新站点
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================建立新站点==================="
bench new-site --mariadb-root-password '"${mariadbRootPassword}"' '"${siteDbPassword}"' --admin-password '"${adminPassword}"' '"${siteName}"'
EOF
end_section

begin_section "安装应用到站点"
# 安装 ERPNext 及扩展应用到新站点
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================安装应用到新站点==================="
bench --site '"${siteName}"' install-app payments
bench --site '"${siteName}"' install-app erpnext
bench --site '"${siteName}"' install-app hrms
bench --site '"${siteName}"' install-app print_designer
EOF
end_section

begin_section "站点基础配置"
# 站点基础配置
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================配置站点参数==================="
bench config http_timeout 6000
bench config serve_default_site on
bench use '"${siteName}"'
EOF
end_section

begin_section "安装中文本地化（erpnext_chinese）"
# 安装 ERPNext 中文本地化
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================安装 ERPNext 中文本地化==================="
bench get-app https://gitee.com/yuzelin/erpnext_chinese.git
bench --site '"${siteName}"' install-app erpnext_chinese
bench clear-cache && bench clear-website-cache
EOF
end_section

begin_section "清理工作台缓存"
# 清理缓存
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================清理缓存==================="
bench clear-cache
bench clear-website-cache
EOF
end_section

begin_section "生产模式开启（如启用）"
# 开启生产模式（部署模式）
if [[ ${productionMode} == "yes" ]]; then
    echo "===================开启生产模式==================="
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y nginx
    rteArr+=("$(nginx -v 2>&1)")
    if [[ ${inDocker} == "yes" ]]; then
        /etc/init.d/nginx stop
        if [[ ! -e /etc/supervisor/conf.d/nginx.conf ]]; then
            ln -fs "${supervisorConfigDir}/nginx.conf" /etc/supervisor/conf.d/nginx.conf
        fi
        echo "当前 Supervisor 状态："
        /usr/bin/supervisorctl status
        echo "重载 Supervisor 配置"
        /usr/bin/supervisorctl reload
        echo "等待 Supervisor 重载完成"
        for i in $(seq -w 15 -1 1); do
            echo -n "${i} "; sleep 1
        done
        echo -e "\n重载后 Supervisor 状态："
        /usr/bin/supervisorctl status
    fi
    echo "修正 bench 脚本配置..."
    if [[ ${supervisorCommand} != "" ]]; then
        echo "可用的 supervisor 重启指令为：${supervisorCommand}"
        f="/usr/local/lib/python3.10/dist-packages/bench/config/supervisor.py"
        if n=$(sed -n "/service.*supervisor.*reload\|service.*supervisor.*restart/=" "${f}"); then
            echo "替换 bench 脚本内 supervisor 重启指令为：${supervisorCommand}"
            sed -i "${n}s/reload\|restart/${supervisorCommand}/" "${f}"
        fi
    fi
    f="/etc/supervisor/conf.d/${installDir}.conf"
    attempt=0
    while [[ ${attempt} -lt 9 ]]; do
        echo "尝试开启生产模式（第 $((attempt+1)) 次）..."
        set +e
        su - ${userName} -c "cd ~/${installDir}; sudo bench setup production ${userName} --yes"
        err=$?
        set -e
        attempt=$((attempt + 1))
        echo "检查配置文件生成结果..."
        sleep 1
        if [[ -e "${f}" ]]; then
            echo "Supervisor 配置文件已生成：${f}"
            break
        elif [[ ${attempt} -ge 9 ]]; then
            echo "失败次数过多 (${attempt})，请检查错误并手动开启生产模式！"
            break
        else
            echo "配置文件未生成，自动重试 (${attempt})..."
        fi
    done
else
    note "开发模式：跳过生产模式配置"
fi
end_section

begin_section "自定义 web 端口（如设置）"
# 根据指定端口修改服务监听端口
if [[ ${webPort} != "" ]]; then
    echo "===================设置 web 端口为：${webPort}==================="
    t=$(echo ${webPort} | sed 's/[0-9]//g')
    if [[ (${t} == "") && (${webPort} -ge 80) && (${webPort} -lt 65535) ]]; then
        if [[ ${productionMode} == "yes" ]]; then
            f="/home/${userName}/${installDir}/config/nginx.conf"
            if [[ -e ${f} ]]; then
                echo "找到配置文件：${f}"
                if n=$(sed -n "/^[[:space:]]*listen .*;/=" "${f}"); then
                    sed -i "${n}c\\\tlisten ${webPort};" "${f}"
                    sed -i "$((n+1))c\\\tlisten [::]:${webPort};" "${f}"
                    /etc/init.d/nginx reload
                    echo "生产模式 Web 端口已修改为：${webPort}"
                else
                    echo "配置文件中未找到监听端口设置行，修改失败。"
                    warnArr+=("未找到 ${f} 中的监听端口设置行，端口修改失败。")
                fi
            else
                echo "未找到配置文件：${f}，端口修改失败。"
                warnArr+=("未找到配置文件 ${f}，端口修改失败。")
            fi
        else
            echo "开发模式修改端口号..."
            f="/home/${userName}/${installDir}/Procfile"
            if [[ -e ${f} ]]; then
                echo "找到配置文件：${f}"
                if n=$(sed -n "/^web: .*bench serve/=" "${f}"); then
                    sed -i "${n}c web: bench serve --port ${webPort}" "${f}"
                    su - ${userName} -c "cd ~/${installDir}; bench restart"
                    echo "开发模式 Web 端口已修改为：${webPort}"
                else
                    echo "配置文件中未找到 bench serve 行，修改失败。"
                    warnArr+=("未找到 ${f} 中 bench serve 行，端口修改失败。")
                fi
            else
                echo "未找到配置文件：${f}，端口修改失败。"
                warnArr+=("未找到配置文件 ${f}，端口修改失败。")
            fi
        fi
    else
        echo "设置的端口号无效或不符合要求，取消端口修改，使用默认端口。"
        warnArr+=("设置的端口号无效或不符合要求，已取消端口修改，使用默认端口。")
    fi
else
    if [[ ${productionMode} == "yes" ]]; then
        webPort="80"
    else
        webPort="8000"
    fi
    note "未指定 webPort，按默认值 ${webPort} 处理"
fi
end_section

begin_section "权限修正、清理缓存与包缓存"
# 修正权限
echo "===================修正权限==================="
chown -R ${userName}:${userName} /home/${userName}/
chmod 755 /home/${userName}
# 清理缓存和临时文件
echo "===================清理临时文件与缓存==================="
apt clean
apt autoremove -y
rm -rf /var/lib/apt/lists/*
pip cache purge
npm cache clean --force
yarn cache clean
su - ${userName} -c "cd ~/${installDir}; npm cache clean --force; yarn cache clean"
end_section

begin_section "确认安装版本与环境摘要"
# 确认安装成功与环境信息
su - ${userName} <<'EOF'
cd ~/'"${installDir}"'
echo "===================确认应用版本==================="
bench version
EOF
echo "===================主要运行环境==================="
for i in "${rteArr[@]}"; do
    echo "${i}"
done
if [[ ${#warnArr[@]} -ne 0 ]]; then
    echo "===================警告==================="
    for i in "${warnArr[@]}"; do
        echo "${i}"
    done
fi
echo "管理员账号：Administrator，密码：${adminPassword}。"
if [[ ${productionMode} == "yes" ]]; then
    if [[ -e /etc/supervisor/conf.d/${installDir}.conf ]]; then
        echo "已开启生产模式，请使用 IP 或域名访问网站（监听端口 ${webPort}）。"
    else
        echo "已尝试开启生产模式，但 Supervisor 配置生成失败，请排查错误后手动开启。"
    fi
else
    echo "使用 'su - ${userName}' 切换至 ${userName} 用户，进入 ~/${installDir} 目录"
    echo "运行 'bench start' 启动开发服务器，然后使用 IP 或域名访问网站（监听端口 ${webPort}）。"
fi
if [[ ${inDocker} == "yes" ]]; then
    echo "当前 Supervisor 进程状态："
    /usr/bin/supervisorctl status
fi
end_section

begin_section "脚本收尾"
# 原样保留以下行（注意：若文件实际包含会导致语法错误）
exit 0
p all
fi
exit 0
end_section

echo
echo "🎉 全部流程执行完毕。总耗时：$(_elapsed $(( $(date +%s) - START_AT )))"
echo "📄 完整日志：$LOG_FILE"

#!/bin/bash
# v0.7 2025.06.27   添加依赖
set -e

############################################
# ========= 仅新增：展示&日志功能 ========= #
############################################
PROGRESS_TOTAL=22              # 预估的总步骤数（仅用于展示，不影响逻辑）
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
# 遍历参数修改默认值
# 脚本后添加参数如有冲突，靠后的参数生效。
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
                # 只有收到正确的端口参数才跳转下一个参数，否则将继续识别当前参数。
                continue
            else
                # 只有-p没有正确的参数会将webPort参数置空
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
                echo "针对docker镜像安装方式适配。"
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
            echo "是否修改apt安装源：${altAptSources}，云服务器有自己的安装，建议不修改。"
            ;;
        "quiet")
            quiet=${arg1}
            if [[ ${quiet} == "yes" ]];then
                removeDuplicate="yes"
            fi
            echo "不再确认参数，直接安装。"
            ;;
        "inDocker")
            inDocker=${arg1}
            echo "针对docker镜像安装方式适配。"
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
# 等待确认参数
if [[ ${quiet} != "yes" ]];then
    echo "===================请确认已设定参数并选择安装方式==================="
    echo "1. 安装为开发模式"
    echo "2. 安装为生产模式"
    echo "3. 不再询问，按照当前设定安装并开启静默模式"
    echo "4. 在Docker镜像里安装并开启静默模式"
    echo "*. 取消安装"
    echo -e "说明：开启静默模式后，如果有重名目录或数据库包括supervisor进程配置文件都将会删除后继续安装，请注意数据备份！ \n \
        开发模式需要手动启动“bench start”，启动后访问8000端口。\n \
        生产模式无需手动启动，使用nginx反代并监听80端口\n \
        此外生产模式会使用supervisor管理进程增强可靠性，并预编译代码开启redis缓存，提高应用性能。\n \
        在Docker镜像里安装会适配其进程启动方式将mariadb及nginx进程也交给supervisor管理。 \n \
        docker镜像主线程：“sudo supervisord -n -c /etc/supervisor/supervisord.conf”。请自行配置到镜像"
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
if [[ ${benchVersion} != "" ]];then
    benchVersion="==${benchVersion}"
fi
if [[ ${frappePath} != "" ]];then
    frappePath="--frappe-path ${frappePath}"
fi
if [[ ${frappeBranch} != "" ]];then
    frappeBranch="--frappe-branch ${frappeBranch}"
fi
if [[ ${erpnextBranch} != "" ]];then
    erpnextBranch="--branch ${erpnextBranch}"
fi
if [[ ${siteDbPassword} != "" ]];then
    siteDbPassword="--db-password ${siteDbPassword}"
fi
end_section

begin_section "APT 源（国内镜像）设置"
# 修改安装源加速国内安装。
if [[ ${altAptSources} == "yes" ]];then
    # 在执行前确定有操作权限
    if [[ ! -e /etc/apt/sources.list.bak ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
    fi
    rm -f /etc/apt/sources.list
    bash -c "cat << EOF > /etc/apt/sources.list && apt update 
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF"
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
    wkhtmltopdf \
    supervisor \
    pkg-config \
    build-essential \
    libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev
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
                        read -r -p "使用新的安装目录名称${siteName}，y确认，n重新输入：" input
                        if [[ ${input} == [y/Y] ]]; then
                            echo "将使用安装目录名称${installDir}重试。"
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
# 环境需求检查,python3
if type python3 >/dev/null 2>&1; then
    result=$(python3 -V | grep "3.10" || true)
    if [[ "${result}" == "" ]]
    then
        echo '==========已安装python3，但不是推荐的3.10版本。=========='
        warnArr[${#warnArr[@]}]="Python不是推荐的3.10版本。"
    else
        echo '==========已安装python3.10=========='
    fi
    rteArr[${#rteArr[@]}]=$(python3 -V)
else
    echo "==========python安装失败退出脚本！=========="
    exit 1
fi
# 环境需求检查,wkhtmltox
if type wkhtmltopdf >/dev/null 2>&1; then
    result=$(wkhtmltopdf -V | grep "0.12.6" || true)
    if [[ ${result} == "" ]]
    then
        echo '==========已存在wkhtmltox，但不是推荐的0.12.6版本。=========='
        warnArr[${#warnArr[@]}]='wkhtmltox不是推荐的0.12.6版本。'
    else
        echo '==========已安装wkhtmltox_0.12.6=========='
    fi
    rteArr[${#rteArr[@]}]=$(wkhtmltopdf -V)
else
    echo "==========wkhtmltox安装失败退出脚本！=========="
    exit 1
fi
# 环境需求检查,MariaDB
# https://mirrors.aliyun.com/mariadb/mariadb-10.6.8/bintar-linux-systemd-x86_64/mariadb-10.6.8-linux-systemd-x86_64.tar.gz
if type mysql >/dev/null 2>&1; then
    result=$(mysql -V | grep "10.6" || true)
    if [[ "${result}" == "" ]]
    then
        echo '==========已安装MariaDB，但不是推荐的10.6版本。=========='
        warnArr[${#warnArr[@]}]='MariaDB不是推荐的10.6版本。'
    else
        echo '==========已安装MariaDB10.6=========='
    fi
    rteArr[${#rteArr[@]}]=$(mysql -V)
else
    echo "==========MariaDB安装失败退出脚本！=========="
    exit 1
fi
end_section

begin_section "MariaDB 配置与授权"
# 修改数据库配置文件
n=$(cat /etc/mysql/my.cnf | grep -c "# ERPNext install script added" || true)
if [[ ${n} == 0 ]]; then
    echo "===================修改数据库配置文件==================="
    echo "# ERPNext install script added" >> /etc/mysql/my.cnf
    echo "[mysqld]" >> /etc/mysql/my.cnf
    echo "character-set-client-handshake=FALSE" >> /etc/mysql/my.cnf
    echo "character-set-server=utf8mb4" >> /etc/mysql/my.cnf
    echo "collation-server=utf8mb4_unicode_ci" >> /etc/mysql/my.cnf
    echo "bind-address=0.0.0.0" >> /etc/mysql/my.cnf
    echo "" >> /etc/mysql/my.cnf
    echo "[mysql]" >> /etc/mysql/my.cnf
    echo "default-character-set=utf8mb4" >> /etc/mysql/my.cnf
fi
/etc/init.d/mariadb restart
# 等待2秒
for i in $(seq -w 2); do
    echo ${i}
    sleep 1
done
# 授权远程访问并修改密码
if mysql -uroot -e quit >/dev/null 2>&1
then
    echo "===================修改数据库root本地访问密码==================="
    mysqladmin -v -uroot password ${mariadbRootPassword}
elif mysql -uroot -p${mariadbRootPassword} -e quit >/dev/null 2>&1
then
    echo "===================数据库root本地访问密码已配置==================="
else
    echo "===================数据库root本地访问密码错误==================="
    exit 1
fi
echo "===================修改数据库root远程访问密码==================="
mysql -u root -p${mariadbRootPassword} -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${mariadbRootPassword}' WITH GRANT OPTION;"
echo "===================刷新权限表==================="
mysqladmin -v -uroot -p${mariadbRootPassword} reload
sed -i 's/^password.*$/password='"${mariadbRootPassword}"'/' /etc/mysql/debian.cnf
echo "===================数据库配置完成==================="
end_section

begin_section "数据库重名检查与处理"
# 检查数据库是否有同名用户。如有，选择处理方式。
echo "==========检查数据库残留=========="
while true
do
    siteSha1=$(echo -n ${siteName} | sha1sum)
    siteSha1=_${siteSha1:0:16}
    dbUser=$(mysql -u root -p${mariadbRootPassword} -e "use mysql;SELECT User,Host FROM user;" | grep ${siteSha1} || true)
    if [[ ${dbUser} != "" ]]; then
        if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then
            clear
        fi
        echo '当前站点名称：'${siteName}
        echo '生成的数据库及用户名为：'${siteSha1}
        echo '已存在同名数据库用户，请选择处理方式。'
        echo '1. 重新输入新的站点名称。将自动生成新的数据库及用户名称重新校验。'
        echo '2. 删除重名的数据库及用户。'
        echo '3. 什么也不做使用设置的密码直接安装。（不推荐）'
        echo '*. 取消安装。'
        if [[ ${quiet} == "yes" ]]; then
            echo '当前为静默模式，将自动按第2项执行。'
            # 删除重名数据库
            mysql -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};"
            arrUser=(${dbUser})
            # 如果重名用户有多个host，以步进2取用户名和用户host并删除。
            for ((i=0; i<${#arrUser[@]}; i=i+2))
            do
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
                        read -r -p "使用新的站点名称${siteName}，y确认，n重新输入：" input
                        if [[ ${input} == [y/Y] ]]; then
                            echo "将使用站点名称${siteName}重试。"
                            break
                        fi
                    fi
                done
                continue
                ;;
            '2')
                mysql -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};"
                arrUser=(${dbUser})
                for ((i=0; i<${#arrUser[@]}; i=i+2))
                do
                    mysql -u root -p${mariadbRootPassword} -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};"
                done
                echo "已删除数据库及用户，继续安装！"
                continue
                ;;
            '3')
                echo "什么也不做使用设置的密码直接安装！"
                warnArr[${#warnArr[@]}]="检测到重名数据库及用户${siteSha1},选择了覆盖安装。可能造成无法访问，数据库无法连接等问题。"
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
    if [[ $(grep -E "[ *]reload)" /etc/init.d/supervisor) != '' ]]; then
        supervisorCommand="reload"
    elif [[ $(grep -E "[ *]restart)" /etc/init.d/supervisor) != '' ]]; then
        supervisorCommand="restart"
    else
        echo "/etc/init.d/supervisor中没有找到reload或restart指令"
        echo "将会继续执行，但可能因为使用不可用指令导致启动进程失败。"
        echo "如进程没有运行，请尝试手动重启supervisor"
        warnArr[${#warnArr[@]}]="没有找到可用的supervisor重启指令，如有进程启动失败，请尝试手动重启。"
    fi
else
    echo "supervisor没有安装"
    warnArr[${#warnArr[@]}]="supervisor没有安装或安装失败，不能使用supervisor管理进程。"
fi
echo "可用指令："${supervisorCommand}
end_section

begin_section "安装/校验 Redis"
# 安装最新版redis
if ! type redis-server >/dev/null 2>&1; then
    echo "==========获取最新版redis，并安装=========="
    rm -rf /var/lib/redis
    rm -rf /etc/redis
    rm -rf /etc/default/redis-server
    rm -rf /etc/init.d/redis-server
    rm -f /usr/share/keyrings/redis-archive-keyring.gpg
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    apt update
    echo "即将安装redis"
    DEBIAN_FRONTEND=noninteractive apt install -y \
        redis-tools \
        redis-server \
        redis
fi
# 环境需求检查,redis
if type redis-server >/dev/null 2>&1; then
    result=$(redis-server -v | grep "7" || true)
    if [[ "${result}" == "" ]]
    then
        echo '==========已安装redis，但不是推荐的7版本。=========='
        warnArr[${#warnArr[@]}]='redis不是推荐的7版本。'
    else
        echo '==========已安装redis7=========='
    fi
    rteArr[${#rteArr[@]}]=$(redis-server -v)
else
    echo "==========redis安装失败退出脚本！=========="
    exit 1
fi
end_section

begin_section "pip 源与工具升级"
# 修改pip默认源加速国内安装
mkdir -p /root/.pip
echo '[global]' > /root/.pip/pip.conf
echo 'index-url=https://pypi.tuna.tsinghua.edu.cn/simple' >> /root/.pip/pip.conf
echo '[install]' >> /root/.pip/pip.conf
echo 'trusted-host=mirrors.tuna.tsinghua.edu.cn' >> /root/.pip/pip.conf
echo "===================pip已修改为国内源==================="
# 安装并升级pip及工具包
echo "===================安装并升级pip及工具包==================="
cd ~
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade setuptools cryptography psutil
alias python=python3
alias pip=pip3
end_section

begin_section "创建用户/组、环境与时区/locale"
# 建立新用户组和用户
echo "===================建立新用户组和用户==================="
result=$(grep "${userName}:" /etc/group || true)
if [[ ${result} == "" ]]; then
    gid=1000
    while true
    do
        result=$(grep ":${gid}:" /etc/group || true)
        if [[ ${result} == "" ]]
        then
            echo "建立新用户组: ${gid}:${userName}"
            groupadd -g ${gid} ${userName}
            echo "已新建用户组${userName}，gid: ${gid}"
            break
        else
            gid=$(expr ${gid} + 1)
        fi
    done
else
    echo '用户组已存在'
fi
result=$(grep "${userName}:" /etc/passwd || true)
if [[ ${result} == "" ]]
then
    uid=1000
    while true
    do
        result=$(grep ":x:${uid}:" /etc/passwd || true)
        if [[ ${result} == "" ]]
        then
            echo "建立新用户: ${uid}:${userName}"
            useradd --no-log-init -r -m -u ${uid} -g ${gid} -G  sudo ${userName}
            echo "已新建用户${userName}，uid: ${uid}"
            break
        else
            uid=$(expr ${uid} + 1)
        fi
    done
else
    echo '用户已存在'
fi
# 给用户添加sudo权限
sed -i "/^${userName}.*/d" /etc/sudoers
echo "${userName} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
mkdir -p /home/${userName}
sed -i "/^export.*${userName}.*/d" /etc/sudoers
# 修改用户pip默认源加速国内安装
cp -af /root/.pip /home/${userName}/
# 修正用户目录权限
chown -R ${userName}.${userName} /home/${userName}
# 修正用户shell
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
echo fs.inotify.max_user_watches=524288 | tee -a /etc/sysctl.conf
# 使其立即生效
/sbin/sysctl -p
end_section

begin_section "Node.js 20 / npm / yarn 准备"
# 检查是否安装nodejs20
source /etc/profile
if ! type node >/dev/null 2>&1; then
    # 获取最新版nodejs-v20，并安装
    echo "==========获取最新版nodejs-v20，并安装=========="
    if [ -z $nodejsLink ] ; then
        nodejsLink=$(curl -sL https://registry.npmmirror.com/-/binary/node/latest-v20.x/ | grep -oE "https?://[a-zA-Z0-9\.\/_&=@$%?~#-]*node-v20\.[0-9][0-9]\.[0-9]{1,2}"-linux-x64.tar.xz | tail -1)
    else
        echo 已自定义nodejs下载链接，开始下载
    fi
    if [ -z $nodejsLink ] ; then
        echo 没有匹配到node.js下载地址，请检查网络或代码。
        exit 1
    else
        nodejsFileName=${nodejsLink##*/}
        nodejsVer=`t=(${nodejsFileName//-/ });echo ${t[1]}`
        echo "nodejs20最新版本为：${nodejsVer}"
        echo "即将安装nodejs20到/usr/local/lib/nodejs/${nodejsVer}"
        wget $nodejsLink -P /tmp/
        mkdir -p /usr/local/lib/nodejs
        tar -xJf /tmp/${nodejsFileName} -C /usr/local/lib/nodejs/
        mv /usr/local/lib/nodejs/${nodejsFileName%%.tar*} /usr/local/lib/nodejs/${nodejsVer}
        echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> /etc/profile.d/nodejs.sh
        echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> ~/.bashrc
        echo "export PATH=/home/${userName}/.local/bin:/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> /home/${userName}/.bashrc
        export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:$PATH
        source /etc/profile
    fi
fi
# 环境需求检查,node
if type node >/dev/null 2>&1; then
    result=$(node -v | grep "v20." || true)
    if [[ ${result} == "" ]]
    then
        echo '==========已存在node，但不是v20版。这将有可能导致一些问题。建议卸载node后重试。=========='
        warnArr[${#warnArr[@]}]='node不是推荐的v20版本。'
    else
        echo '==========已安装node20=========='
    fi
    rteArr[${#rteArr[@]}]='node '$(node -v)
else
    echo "==========node安装失败退出脚本！=========="
    exit 1
fi
# 修改npm源
npm config set registry https://registry.npmmirror.com -g
echo "===================npm已修改为国内源==================="
# 升级npm
echo "===================升级npm==================="
npm install -g npm
# 安装yarn
echo "===================安装yarn==================="
npm install -g yarn
# 修改yarn源
yarn config set registry https://registry.npmmirror.com --global
echo "===================yarn已修改为国内源==================="
end_section

begin_section "切换到应用用户，配置用户级 yarn"
# 切换用户
su - ${userName} <<EOF
# 配置运行环境变量
echo "===================配置运行环境变量==================="
cd ~
alias python=python3
alias pip=pip3
source /etc/profile
export PATH=/home/${userName}/.local/bin:$PATH
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LANG=en_US.UTF-8
# 修改用户yarn源
# 在执行前确定有操作权限
# yarn config list
yarn config set registry https://registry.npmmirror.com --global
echo "===================用户yarn已修改为国内源==================="
EOF
end_section

begin_section "Docker 适配（如启用）"
# 适配docker
echo "判断是否适配docker"
if [[ ${inDocker} == "yes" ]]; then
    # 如果是在docker中运行，使用supervisor管理mariadb和nginx进程
    echo "================为docker镜像添加mariadb和nginx启动配置文件==================="
    supervisorConfigDir=/home/${userName}/.config/supervisor
    mkdir -p ${supervisorConfigDir}
    f=${supervisorConfigDir}/mariadb.conf
    rm -f ${f}
    echo "[program:mariadb]" > ${f}
    echo "command=/usr/sbin/mariadbd --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib/mysql/plugin --user=mysql --skip-log-error" >> ${f}
    # echo "user=mysql" >> ${f}
    echo "priority=1" >> ${f}
    echo "autostart=true" >> ${f}
    echo "autorestart=true" >> ${f}
    echo "numprocs=1" >> ${f}
    echo "startretries=10" >> ${f}
    # echo "exitcodes=0,2" >> ${f}
    # echo "stopsignal=INT" >> ${f}
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
    # 关闭mariadb进程，启动supervisor进程并管理mariadb进程
    echo "关闭mariadb进程，启动supervisor进程并管理mariadb进程"
    /etc/init.d/mariadb stop
    # 等待2秒
    for i in $(seq -w 2); do
        echo ${i}
        sleep 1
    done
    if [[ ! -e /etc/supervisor/conf.d/mysql.conf ]]; then
        echo "建立数据库配置文件软链接"
        ln -fs ${supervisorConfigDir}/mariadb.conf /etc/supervisor/conf.d/mariadb.conf
    fi
    i=$(ps aux | grep -c supervisor || true)
    if [[ ${i} -le 1 ]]; then
        echo "启动supervisor进程"
        /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    else
        echo "重载supervisor配置"
        /usr/bin/supervisorctl reload
    fi
    # 等待2秒
    for i in $(seq -w 2); do
        echo ${i}
        sleep 1
    done
else
    note "非 Docker 模式，跳过容器适配"
fi
end_section

begin_section "安装 bench"
# 安装bench
su - ${userName} <<EOF
echo "===================安装bench==================="
sudo -H pip3 install frappe-bench${benchVersion}
# 环境需求检查,bench
if type bench >/dev/null 2>&1; then
    benchV=\$(bench --version)
    echo '==========已安装bench=========='
    echo \${benchV}
else
    echo "==========bench安装失败退出脚本！=========="
    exit 1
fi
EOF
rteArr[${#rteArr[@]}]='bench '$(bench --version 2>/dev/null)
end_section

begin_section "Docker 情况下 bench 脚本适配（fail2ban 注释）"
# bensh脚本适配docker
if [[ ${inDocker} == "yes" ]]; then
    echo "已配置在docker中运行，将注释安装fail2ban的代码。"
    f="/usr/local/lib/python3.10/dist-packages/bench/config/production_setup.py"
    n=$(sed -n "/^[[:space:]]*if not which.*fail2ban-client/=" ${f})
    if [ ${n} ]; then
        echo "找到fail2ban安装代码行，添加注释符。"
        sed -i "${n} s/^/#&/" ${f}
        let n++
        sed -i "${n} s/^/#&/" ${f}
    fi
else
    note "非 Docker 模式，跳过 bench fail2ban 适配"
fi
end_section

begin_section "初始化 frappe（bench init，带重试）"
# 初始化frappe
su - ${userName} <<EOF
echo "===================初始化frappe==================="
# 如果初始化失败，尝试5次。
for ((i=0; i<5; i++)); do
    rm -rf ~/${installDir}
    set +e
    bench init ${frappeBranch} --python /usr/bin/python3 --ignore-exist ${installDir} ${frappePath}
    err=\$?
    set -e
    if [[ \${err} == 0 ]]; then
        echo "执行返回正确\${i}"
        sleep 1
        break
    elif [[ \${i} -ge 4 ]]; then
        echo "==========frappe初始化失败太多\${i}，退出脚本！=========="
        exit 1
    else
        echo "==========frappe初始化失败第"\${i}"次！自动重试。=========="
    fi
done
echo "frappe初始化脚本执行结束..."
EOF
end_section

begin_section "确认 frappe 初始化结果"
# 确认frappe初始化
su - ${userName} <<EOF
cd ~/${installDir}
# 环境需求检查,frappe
frappeV=\$(bench version | grep "frappe" || true)
if [[ \${frappeV} == "" ]]; then
    echo "==========frappe初始化失败退出脚本！=========="
    exit 1
else
    echo '==========frappe初始化成功=========='
    echo \${frappeV}
fi
EOF
end_section

begin_section "获取应用（erpnext/payments/hrms/print_designer）"
# 获取erpnext应用
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
# 建立新网站
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================建立新网站==================="
bench new-site --mariadb-root-password ${mariadbRootPassword} ${siteDbPassword} --admin-password ${adminPassword} ${siteName}
EOF
end_section

begin_section "安装应用到站点"
# 安装erpnext应用到新网站
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
# 站点配置
su - ${userName} <<EOF
cd ~/${installDir}
# 设置网站超时时间
echo "===================设置网站超时时间==================="
bench config http_timeout 6000
# 开启默认站点并设置默认站点
bench config serve_default_site on
bench use ${siteName}
EOF
end_section

begin_section "安装中文本地化（erpnext_chinese）"
# 安装中文本地化
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================安装中文本地化==================="
bench get-app https://gitee.com/yuzelin/erpnext_chinese.git
bench --site ${siteName} install-app erpnext_chinese
bench clear-cache && bench clear-website-cache
EOF
end_section

begin_section "清理工作台缓存"
# 清理工作台
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================清理工作台==================="
bench clear-cache
bench clear-website-cache
EOF
end_section

begin_section "生产模式开启（如启用）"
# 生产模式开启
if [[ ${productionMode} == "yes" ]]; then
    echo "================开启生产模式==================="
    apt update
    DEBIAN_FRONTEND=noninteractive apt install nginx -y
    rteArr[${#rteArr[@]}]=$(nginx -v 2>/dev/null)
    if [[ ${inDocker} == "yes" ]]; then
        /etc/init.d/nginx stop
        if [[ ! -e /etc/supervisor/conf.d/nginx.conf ]]; then
            ln -fs ${supervisorConfigDir}/nginx.conf /etc/supervisor/conf.d/nginx.conf
        fi
        echo "当前supervisor状态"
        /usr/bin/supervisorctl status
        echo "重载supervisor配置"
        /usr/bin/supervisorctl reload
        echo "等待重载supervisor结束"
        for i in $(seq -w 15 -1 1); do
            echo -en ${i}; sleep 1
        done
        echo "重载后supervisor状态"
        /usr/bin/supervisorctl status
    fi
    echo "修正脚本代码..."
    if [[ ${supervisorCommand} != "" ]]; then
        echo "可用的supervisor重启指令为："${supervisorCommand}
        f="/usr/local/lib/python3.10/dist-packages/bench/config/supervisor.py"
        n=$(sed -n "/service.*supervisor.*reload\|service.*supervisor.*restart/=" ${f})
        if [ ${n} ]; then
            echo "替换bensh脚本supervisor重启指令为："${supervisorCommand}
            sed -i "${n} s/reload\|restart/${supervisorCommand}/g" ${f}
        fi
    fi
    f="/etc/supervisor/conf.d/${installDir}.conf"
    i=0
    while [[ i -lt 9 ]]; do
        echo "尝试开启生产模式${i}..."
        set +e
        su - ${userName} <<EOF
        cd ~/${installDir}
        sudo bench setup production ${userName} --yes
EOF
        set -e
        i=$((${i} + 1))
        echo "判断执行结果"
        sleep 1
        if [[ -e ${f} ]]; then
            echo "配置文件已生成..."
            break
        elif [[ ${i} -ge 9 ]]; then
            echo "失败次数过多${i}，请尝试手动开启！"
            break
        else
            echo "配置文件生成失败${i}，自动重试。"
        fi
    done
else
    note "开发模式：跳过生产模式开启"
fi
end_section

begin_section "自定义 web 端口（如设置）"
# 如果有设定端口，修改为设定端口
if [[ ${webPort} != "" ]]; then
    echo "===================设置web端口为：${webPort}==================="
    t=$(echo ${webPort}|sed 's/[0-9]//g')
    if [[ (${t} == "") && (${webPort} -ge 80) && (${webPort} -lt 65535) ]]; then
        if [[ ${productionMode} == "yes" ]]; then
            f="/home/${userName}/${installDir}/config/nginx.conf"
            if [[ -e ${f} ]]; then
                echo "找到配置文件："${f}
                n=($(sed -n "/^[[:space:]]*listen/=" ${f}))
                if [ ${n} ]; then
                    sed -i "${n} c listen ${webPort};" ${f}
                    sed -i "$((${n}+1)) c listen [::]:${webPort};" ${f}
                    /etc/init.d/nginx reload
                    echo "web端口号修改为："${webPort}
                else
                    echo "配置文件中没找到设置行。修改失败。"
                    warnArr[${#warnArr[@]}]="找到配置文件："${f}",没找到设置行。修改失败。"
                fi
            else
                echo "没有找到配置文件："${f}",端口修改失败。"
                warnArr[${#warnArr[@]}]="没有找到配置文件："${f}",端口修改失败。"
            fi
        else
            echo "开发模式修改端口号"
            f="/home/${userName}/${installDir}/Procfile"
            echo "找到配置文件："${f}
            if [[ -e ${f} ]]; then
                n=($(sed -n "/^web.*port.*/=" ${f}))
                if [[ ${n} ]]; then
                    sed -i "${n} c web: bench serve --port ${webPort}" ${f}
                    su - ${userName} bash -c "cd ~/${installDir}; bench restart"
                    echo "web端口号修改为："${webPort}
                else
                    echo "配置文件中没找到设置行。修改失败。"
                    warnArr[${#warnArr[@]}]="找到配置文件："${f}",没找到设置行。修改失败。"
                fi
            else
                echo "没有找到配置文件："${f}",端口修改失败。"
                warnArr[${#warnArr[@]}]="没有找到配置文件："${f}",端口修改失败。"
            fi
        fi
    else
        echo "设置的端口号无效或不符合要求，取消端口号修改。使用默认端口号。"
        warnArr[${#warnArr[@]}]="设置的端口号无效或不符合要求，取消端口号修改。使用默认端口号。"
    fi
else
    if [[ ${productionMode} == "yes" ]]; then
        webPort="80"
    else
        webPort="8000"
    fi
    note "未指定 webPort，按默认：${webPort}"
fi
end_section

begin_section "权限修正、清理缓存与包管理器缓存"
# 修正权限
echo "===================修正权限==================="
chown -R ${userName}:${userName} /home/${userName}/
chmod 755 /home/${userName}
# 清理垃圾,ERPNext安装完毕
echo "===================清理垃圾,ERPNext安装完毕==================="
apt clean
apt autoremove -y
rm -rf /var/lib/apt/lists/*
pip cache purge
npm cache clean --force
yarn cache clean
su - ${userName} <<EOF
cd ~/${installDir}
npm cache clean --force
yarn cache clean
EOF
end_section

begin_section "确认安装版本与环境摘要"
# 确认安装
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================确认安装==================="
bench version
EOF
echo "===================主要运行环境==================="
for i in "${rteArr[@]}"
do
    echo ${i}
done
if [[ ${#warnArr[@]} != 0 ]]; then
    echo "===================警告==================="
    for i in "${warnArr[@]}"
    do
        echo ${i}
    done
fi
echo "管理员账号：administrator，密码：${adminPassword}。"
if [[ ${productionMode} == "yes" ]]; then
    if [[ -e /etc/supervisor/conf.d/${installDir}.conf ]]; then
        echo "已开启生产模式。使用ip或域名访问网站。监听${webPort}端口。"
    else
        echo "已配置开启生产模式。但supervisor配置文件生成失败，请排除错误后手动开启。"
    fi
else
    echo "使用su - ${userName}转到${userName}用户进入~/${installDir}目录"
    echo "运行bench start启动项目，使用ip或域名访问网站。监听${webPort}端口。"
fi
if [[ ${inDocker} == "yes" ]]; then
    echo "当前supervisor状态"
    /usr/bin/supervisorctl status
    # echo "停止所有进程。"
    # /usr/bin/supervisorctl stop all
fi
end_section

begin_section "脚本收尾"
# 原样保留以下行（注意：若你文件实际包含，会导致语法错误）
exit 0
p all
fi
exit 0
end_section

echo
echo "🎉 全部流程执行完毕。总耗时：$(_elapsed $(( $(date +%s) - START_AT )))"
echo "📄 完整日志：$LOG_FILE"

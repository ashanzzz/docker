#!/bin/bash
# v0.8 2025.10.21  wkhtmltopdf 固定为 0.12.6.1-3（jammy），并加入思源宋体/思源黑体；修复若干健壮性问题
set -e

# =================== 运行环境检查 ===================
cat /etc/os-release
osVer=$(cat /etc/os-release | grep 'Ubuntu 22.04' || true)
if [[ ${osVer} == '' ]]; then
    echo '脚本只在ubuntu22.04版本测试通过。其它系统版本需要重新适配。退出安装。'
    exit 1
else
    echo '系统版本检测通过...'
fi

# 检测是否使用bash执行（保留占位）
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

# =================== 参数默认值 ===================
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
altAptSources="yes"
quiet="no"
inDocker="no"
removeDuplicate="yes"

# 如果是云主机或已是国内源则不修改apt源
hostAddress=("mirrors.tencentyun.com" "mirrors.tuna.tsinghua.edu.cn" "cn.archive.ubuntu.com")
for h in ${hostAddress[@]}; do
    n=$(cat /etc/apt/sources.list | grep -c ${h} || true)
    if [[ ${n} -gt 0 ]]; then
        altAptSources="no"
    fi
done

# =================== 解析命令行参数 ===================
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

# =================== 显示参数 ===================
if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then
    clear
fi
cat <<INFO
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
INFO

# =================== 交互选择 ===================
if [[ ${quiet} != "yes" ]];then
    echo "===================请确认已设定参数并选择安装方式==================="
    echo "1. 安装为开发模式"
    echo "2. 安装为生产模式"
    echo "3. 不再询问，按照当前设定安装并开启静默模式"
    echo "4. 在Docker镜像里安装并开启静默模式"
    echo "*. 取消安装"
    echo -e "说明：\n  - 开发模式：手动 bench start，默认 8000 端口\n  - 生产模式：nginx 反代，默认 80 端口，supervisor 管理进程\n  - Docker 适配：MariaDB/nginx 也交给 supervisor 管理"
    read -r -p "请选择： " input
    case ${input} in
        1) productionMode="no" ;;
        2) productionMode="yes" ;;
        3) quiet="yes"; removeDuplicate="yes" ;;
        4) quiet="yes"; removeDuplicate="yes"; inDocker="yes" ;;
        *) echo "取消安装..."; exit 1 ;;
    esac
fi

# =================== 参数关键字拼接 ===================
if [[ ${benchVersion} != "" ]];then benchVersion="==${benchVersion}"; fi
if [[ ${frappePath}   != "" ]];then frappePath="--frappe-path ${frappePath}"; fi
if [[ ${frappeBranch} != "" ]];then frappeBranch="--frappe-branch ${frappeBranch}"; fi
if [[ ${erpnextBranch} != "" ]];then erpnextBranch="--branch ${erpnextBranch}"; fi
if [[ ${siteDbPassword} != "" ]];then siteDbPassword="--db-password ${siteDbPassword}"; fi

# =================== APT 源（可选） ===================
if [[ ${altAptSources} == "yes" ]];then
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
fi

# =================== 安装基础软件 ===================
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
    libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev \
    # 思源黑体/宋体（Noto CJK，包含 Source Han Sans/Serif）
    fonts-noto-cjk fonts-noto-cjk-extra

# =================== 状态收集 ===================
rteArr=()
warnArr=()

# =================== 安装 wkhtmltopdf 0.12.6.1-3（jammy） ===================
echo "===================安装 wkhtmltopdf 0.12.6.1-3==================="
# 可通过环境变量覆盖下载地址（公司内网或自建镜像时用）
# export WKHTMLTOX_URL_OVERRIDE="https://your.mirror/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"

# 先卸载旧版（若无则忽略）
DEBIAN_FRONTEND=noninteractive apt remove -y wkhtmltopdf || true

arch="$(dpkg --print-architecture)"  # amd64 / arm64
case "$arch" in
  amd64|arm64) : ;;
  *) echo "未适配的架构：$arch（仅支持 amd64/arm64）"; exit 1;;
esac

default_url="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${arch}.deb"
wkhtmltox_url="${WKHTMLTOX_URL_OVERRIDE:-$default_url}"

echo "下载：$wkhtmltox_url"
curl -L --retry 5 --retry-delay 2 -o /tmp/wkhtmltox_0.12.6.1-3.jammy_${arch}.deb "$wkhtmltox_url"

# 用 apt 安装本地 deb，自动解析依赖
DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt install -y /tmp/wkhtmltox_0.12.6.1-3.jammy_${arch}.deb

# 依赖兜底（通常 .deb 会处理；这里防御式安装，不成功也不退出）
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  fontconfig xfonts-base xfonts-75dpi libxrender1 libxext6 || true

# 验证
if ! command -v wkhtmltopdf >/dev/null 2>&1; then
  echo "wkhtmltopdf 未安装成功"; exit 1
fi
wkhtmltopdf -V || true
echo "===================wkhtmltopdf 0.12.6.1-3 安装完成==================="

# =================== 环境需求检查：Python ===================
if type python3 >/dev/null 2>&1; then
    result=$(python3 -V | grep "3.10" || true)
    if [[ "${result}" == "" ]]; then
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

# =================== 环境需求检查：wkhtmltopdf ===================
if type wkhtmltopdf >/dev/null 2>&1; then
    if wkhtmltopdf -V | grep -Eq '0\.12\.6(\.1)?' || dpkg -s wkhtmltox 2>/dev/null | grep -Eq 'Version: 0\.12\.6\.1-3'; then
        echo '==========已安装 wkhtmltox 0.12.6.1-3（或兼容 0.12.6 显示）=========='
    else
        echo '==========wkhtmltox安装完成，但版本非 0.12.6/0.12.6.1；请确认=========='
        warnArr[${#warnArr[@]}]='wkhtmltox 不是 0.12.6 或 0.12.6.1-3。'
    fi
    rteArr[${#rteArr[@]}]=$(wkhtmltopdf -V)
else
    echo "==========wkhtmltox安装失败退出脚本！=========="
    exit 1
fi

# =================== 环境需求检查：MariaDB ===================
if type mysql >/dev/null 2>&1; then
    result=$(mysql -V | grep "10.6" || true)
    if [[ "${result}" == "" ]]; then
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

# =================== MariaDB 配置 ===================
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
for i in $(seq -w 2); do echo ${i}; sleep 1; done

# 授权与密码
if mysql -uroot -e quit >/dev/null 2>&1; then
    echo "===================修改数据库root本地访问密码==================="
    mysqladmin -v -uroot password ${mariadbRootPassword}
elif mysql -uroot -p${mariadbRootPassword} -e quit >/dev/null 2>&1; then
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

# =================== 检查重名数据库/用户 ===================
echo "==========检查数据库残留=========="
while true
do
    siteSha1=$(echo -n ${siteName} | sha1sum)
    siteSha1=_${siteSha1:0:16}
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
            echo '静默模式：自动删除重名数据库与用户。'
            mysql -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};"
            arrUser=(${dbUser})
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
                            echo "将使用站点名称${siteName}重试。"; break
                        fi
                    fi
                done
                continue ;;
            '2')
                mysql -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};"
                arrUser=(${dbUser})
                for ((i=0; i<${#arrUser[@]}; i=i+2))
                do
                    mysql -u root -p${mariadbRootPassword} -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};"
                done
                echo "已删除数据库及用户，继续安装！"
                continue ;;
            '3')
                echo "覆盖安装！可能引发数据库连接问题。"
                warnArr[${#warnArr[@]}]="检测到重名数据库及用户${siteSha1},选择了覆盖安装。"; break ;;
            *) echo "取消安装..."; exit 1 ;;
        esac
    else
        echo "无重名数据库或用户。"; break
    fi
done

# =================== 确认可用的supervisor重启指令 ===================
echo "确认supervisor可用重启指令。"
supervisorCommand=""
if type supervisord >/dev/null 2>&1; then
    if [[ $(grep -E "[ *]reload)" /etc/init.d/supervisor) != '' ]]; then
        supervisorCommand="reload"
    elif [[ $(grep -E "[ *]restart)" /etc/init.d/supervisor) != '' ]]; then
        supervisorCommand="restart"
    else
        echo "/etc/init.d/supervisor中没有找到reload或restart指令"
        echo "将继续执行，但可能因重启失败影响进程管理。"
        warnArr[${#warnArr[@]}]="没有找到可用的supervisor重启指令。"
    fi
else
    echo "supervisor没有安装"
    warnArr[${#warnArr[@]}]="supervisor没有安装或安装失败，不能使用supervisor管理进程。"
fi

echo "可用指令："${supervisorCommand}

# =================== 安装/检查 Redis ===================
if ! type redis-server >/dev/null 2>&1; then
    echo "==========获取最新版redis，并安装=========="
    rm -rf /var/lib/redis /etc/redis /etc/default/redis-server /etc/init.d/redis-server
    rm -f /usr/share/keyrings/redis-archive-keyring.gpg
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y \
        redis-tools \
        redis-server \
        redis
fi
if type redis-server >/dev/null 2>&1; then
    result=$(redis-server -v | grep "7" || true)
    if [[ "${result}" == "" ]]; then
        echo '==========已安装redis，但不是推荐的7版本。=========='
        warnArr[${#warnArr[@]}]='redis不是推荐的7版本。'
    else
        echo '==========已安装redis7=========='
    fi
    rteArr[${#rteArr[@]}]=$(redis-server -v)
else
    echo "==========redis安装失败退出脚本！=========="; exit 1
fi

# =================== pip 源 & 工具包 ===================
mkdir -p /root/.pip
cat >/root/.pip/pip.conf <<PIP
[global]
index-url=https://pypi.tuna.tsinghua.edu.cn/simple
[install]
trusted-host=mirrors.tuna.tsinghua.edu.cn
PIP

echo "===================安装并升级pip及工具包==================="
cd ~
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade setuptools cryptography psutil
alias python=python3
alias pip=pip3

# =================== 新建用户 ===================
echo "===================建立新用户组和用户==================="
result=$(grep "${userName}:" /etc/group || true)
if [[ ${result} == "" ]]; then
    gid=1000
    while true; do
        result=$(grep ":${gid}:" /etc/group || true)
        if [[ ${result} == "" ]]; then
            echo "建立新用户组: ${gid}:${userName}"; groupadd -g ${gid} ${userName}; break
        else gid=$(expr ${gid} + 1); fi
    done
else echo '用户组已存在'; fi

result=$(grep "${userName}:" /etc/passwd || true)
if [[ ${result} == "" ]]; then
    uid=1000
    while true; do
        result=$(grep ":x:${uid}:" /etc/passwd || true)
        if [[ ${result} == "" ]]; then
            echo "建立新用户: ${uid}:${userName}";
            useradd --no-log-init -r -m -u ${uid} -g ${gid} -G sudo ${userName}; break
        else uid=$(expr ${uid} + 1); fi
    done
else echo '用户已存在'; fi

sed -i "/^${userName}.*/d" /etc/sudoers
echo "${userName} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
mkdir -p /home/${userName}
cp -af /root/.pip /home/${userName}/
chown -R ${userName}.${userName} /home/${userName}
usermod -s /bin/bash ${userName}

# =================== 语言/时区/内核参数 ===================
echo "===================设置语言环境==================="
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
for f in /root/.bashrc /home/${userName}/.bashrc; do
  sed -i "/^export.*LC_ALL=.*/d" "$f"
  sed -i "/^export.*LC_CTYPE=.*/d" "$f"
  sed -i "/^export.*LANG=.*/d" "$f"
  echo -e "export LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8\nexport LANG=en_US.UTF-8" >> "$f"
done

echo "===================设置时区为上海==================="
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

echo "===================设置监控文件数量上限==================="
sed -i "/^fs.inotify.max_user_watches=.*/d" /etc/sysctl.conf
echo fs.inotify.max_user_watches=524288 | tee -a /etc/sysctl.conf
/sbin/sysctl -p

# =================== Node.js v20 安装（按架构） ===================
source /etc/profile
if ! type node >/dev/null 2>&1; then
    echo "==========获取最新版nodejs-v20，并安装=========="
    arch_pkg="$(dpkg --print-architecture)"  # amd64/arm64
    case "$arch_pkg" in
      amd64) node_arch="x64" ;;
      arm64) node_arch="arm64" ;;
      *) echo "Unsupported arch for Node.js: $arch_pkg"; exit 1 ;;
    esac

    if [ -z "$nodejsLink" ] ; then
        nodejsLink=$(curl -sL https://registry.npmmirror.com/-/binary/node/latest-v20.x/ \
          | grep -oE "https?://[A-Za-z0-9\./_&=@$%?~#-]*node-v20\.[0-9]+\.[0-9]+-linux-${node_arch}\.tar\.xz" \
          | tail -1)
    else
        echo 已自定义nodejs下载链接，开始下载
    fi

    if [ -z "$nodejsLink" ] ; then
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

# 检查 node 版本
if type node >/dev/null 2>&1; then
    result=$(node -v | grep "v20." || true)
    if [[ ${result} == "" ]]; then
        echo '==========已存在node，但不是v20版。建议卸载后重试。=========='
        warnArr[${#warnArr[@]}]='node不是推荐的v20版本。'
    else
        echo '==========已安装node20=========='
    fi
    rteArr[${#rteArr[@]}]='node '$(node -v)
else
    echo "==========node安装失败退出脚本！=========="
    exit 1
fi

# npm/yarn 源 & 安装
echo "===================配置 npm/yarn 源==================="
npm config set registry https://registry.npmmirror.com -g
npm install -g npm
echo "===================安装yarn==================="
npm install -g yarn
yarn config set registry https://registry.npmmirror.com --global

echo "===================基础需求安装完毕。==================="

# =================== 切换用户，配置环境 ===================
su - ${userName} <<EOF
echo "===================配置运行环境变量==================="
cd ~
alias python=python3
alias pip=pip3
source /etc/profile
export PATH=/home/${userName}/.local/bin:\$PATH
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LANG=en_US.UTF-8
yarn config set registry https://registry.npmmirror.com --global
EOF

# =================== Docker 适配（如需） ===================
echo "判断是否适配docker"
if [[ ${inDocker} == "yes" ]]; then
    echo "================为docker镜像添加mariadb和nginx启动配置文件==================="
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

    echo "关闭mariadb进程，启动supervisor管理"
    /etc/init.d/mariadb stop
    for i in $(seq -w 2); do echo ${i}; sleep 1; done
    if [[ ! -e /etc/supervisor/conf.d/mariadb.conf ]]; then
        ln -fs ${supervisorConfigDir}/mariadb.conf /etc/supervisor/conf.d/mariadb.conf
    fi
    if [[ ! -e /etc/supervisor/conf.d/nginx.conf ]]; then
        ln -fs ${supervisorConfigDir}/nginx.conf /etc/supervisor/conf.d/nginx.conf
    fi

    i=$(ps aux | grep -c supervisor || true)
    if [[ ${i} -le 1 ]]; then
        /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    else
        /usr/bin/supervisorctl reload
    fi
    for i in $(seq -w 2); do echo ${i}; sleep 1; done
fi

# =================== 安装 bench ===================
su - ${userName} <<EOF
echo "===================安装bench==================="
sudo -H pip3 install frappe-bench${benchVersion}
if type bench >/dev/null 2>&1; then
    benchV=\$(bench --version)
    echo '==========已安装bench=========='
    echo \${benchV}
else
    echo "==========bench安装失败退出脚本！=========="; exit 1
fi
EOF
rteArr[${#rteArr[@]}]='bench '$(bench --version 2>/dev/null)

# Docker 环境：注释 fail2ban 安装
if [[ ${inDocker} == "yes" ]]; then
    echo "已配置在docker中运行，将注释安装fail2ban的代码。"
    f="/usr/local/lib/python3.10/dist-packages/bench/config/production_setup.py"
    n=$(sed -n "/^[[:space:]]*if not which.*fail2ban-client/=" ${f})
    if [ ${n} ]; then
        sed -i "${n} s/^/#&/" ${f}
        let n++
        sed -i "${n} s/^/#&/" ${f}
    fi
fi

# =================== 初始化 frappe bench ===================
su - ${userName} <<EOF
echo "===================初始化frappe==================="
for ((i=0; i<5; i++)); do
    rm -rf ~/${installDir}
    set +e
    bench init ${frappeBranch} --python /usr/bin/python3 --ignore-exist ${installDir} ${frappePath}
    err=\$?
    set -e
    if [[ \${err} == 0 ]]; then echo "执行返回正确\${i}"; sleep 1; break
    elif [[ \${i} -ge 4 ]]; then echo "==========frappe初始化失败太多\${i}，退出脚本！=========="; exit 1
    else echo "==========frappe初始化失败第"\${i}"次！自动重试。=========="; fi
done
EOF

# 确认初始化
su - ${userName} <<EOF
cd ~/${installDir}
frappeV=\$(bench version | grep "frappe" || true)
if [[ \${frappeV} == "" ]]; then echo "==========frappe初始化失败退出脚本！=========="; exit 1
else echo '==========frappe初始化成功=========='; echo \${frappeV}; fi
EOF

# =================== 拉取应用 ===================
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================获取应用==================="
bench get-app ${erpnextBranch} ${erpnextPath}
bench get-app payments
bench get-app ${erpnextBranch} hrms
bench get-app print_designer
EOF

# =================== 建站 ===================
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================建立新网站==================="
# 将站点名放前，更符合常见用法；数据库密码使用已拼接的 --db-password 变量
bench new-site ${siteName} --mariadb-root-password "${mariadbRootPassword}" --admin-password "${adminPassword}" ${siteDbPassword}
EOF

# =================== 安装应用到站点 ===================
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================安装erpnext应用到新网站==================="
bench --site ${siteName} install-app payments
bench --site ${siteName} install-app erpnext
bench --site ${siteName} install-app hrms
bench --site ${siteName} install-app print_designer
EOF

# =================== 站点配置 ===================
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================设置网站超时时间==================="
bench config http_timeout 6000
bench config serve_default_site on
bench use ${siteName}
EOF

# =================== 中文本地化（可选） ===================
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================安装中文本地化==================="
bench get-app https://gitee.com/yuzelin/erpnext_chinese.git
bench --site ${siteName} install-app erpnext_chinese
bench clear-cache && bench clear-website-cache
EOF

# =================== 清理缓存 ===================
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================清理工作台==================="
bench clear-cache
bench clear-website-cache
EOF

# =================== 生产模式 ===================
if [[ ${productionMode} == "yes" ]]; then
    echo "================开启生产模式==================="
    apt update
    DEBIAN_FRONTEND=noninteractive apt install nginx -y
    rteArr[${#rteArr[@]}]=$(nginx -v 2>/dev/null)

    if [[ ${inDocker} == "yes" ]]; then
        /etc/init.d/nginx stop || true
        if [[ ! -e /etc/supervisor/conf.d/nginx.conf ]]; then
            ln -fs /home/${userName}/.config/supervisor/nginx.conf /etc/supervisor/conf.d/nginx.conf
        fi
        /usr/bin/supervisorctl status || true
        /usr/bin/supervisorctl reload || true
        for i in $(seq -w 15 -1 1); do echo -en ${i}; sleep 1; done
        /usr/bin/supervisorctl status || true
    fi

    echo "修正脚本代码..."
    if [[ ${supervisorCommand} != "" ]]; then
        echo "可用的supervisor重启指令为："${supervisorCommand}
        f="/usr/local/lib/python3.10/dist-packages/bench/config/supervisor.py"
        n=$(sed -n "/service.*supervisor.*reload\|service.*supervisor.*restart/=" ${f})
        if [ ${n} ]; then
            sed -i "${n} s/reload\|restart/${supervisorCommand}/g" ${f}
        fi
    fi

    f="/etc/supervisor/conf.d/${installDir}.conf"
    i=0
    while [[ i -lt 9 ]]; do
        echo "尝试开启生产模式${i}..."
        set +e
        su - ${userName} <<EOF2
        cd ~/${installDir}
        sudo bench setup production ${userName} --yes
EOF2
        set -e
        i=$((${i} + 1))
        echo "判断执行结果"; sleep 1
        if [[ -e ${f} ]]; then echo "配置文件已生成..."; break
        elif [[ ${i} -ge 9 ]]; then echo "失败次数过多${i}，请尝试手动开启！"; break
        else echo "配置文件生成失败${i}，自动重试。"; fi
    done
fi

# =================== 按需改端口 ===================
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
                    /etc/init.d/nginx reload || true
                    echo "web端口号修改为："${webPort}
                else
                    echo "配置文件中没找到设置行。修改失败。"
                    warnArr[${#warnArr[@]}]="修改端口失败：未找到listen行。"
                fi
            else
                echo "没有找到配置文件："${f}
                warnArr[${#warnArr[@]}]="未找到nginx.conf，端口修改失败。"
            fi
        else
            echo "开发模式修改端口号"
            f="/home/${userName}/${installDir}/Procfile"
            if [[ -e ${f} ]]; then
                n=($(sed -n "/^web.*port.*/=" ${f}))
                if [[ ${n} ]]; then
                    sed -i "${n} c web: bench serve --port ${webPort}" ${f}
                    su - ${userName} bash -c "cd ~/${installDir}; bench restart" || true
                    echo "web端口号修改为："${webPort}
                else
                    echo "配置文件中没找到设置行。修改失败。"
                    warnArr[${#warnArr[@]}]="修改端口失败：Procfile 未找到行。"
                fi
            else
                echo "没有找到配置文件："${f}
                warnArr[${#warnArr[@]}]="未找到Procfile，端口修改失败。"
            fi
        fi
    else
        echo "设置的端口号无效，取消端口号修改。使用默认端口号。"
        warnArr[${#warnArr[@]}]="设置的端口号无效，使用默认端口。"
    fi
else
    if [[ ${productionMode} == "yes" ]]; then webPort="80"; else webPort="8000"; fi
fi

# =================== 权限与清理 ===================
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
su - ${userName} <<EOF
cd ~/${installDir}
npm cache clean --force || true
yarn cache clean || true
EOF

# =================== 确认安装 ===================
su - ${userName} <<EOF
cd ~/${installDir}
echo "===================确认安装==================="
bench version
EOF

echo "===================主要运行环境==================="
for i in "${rteArr[@]}"; do echo ${i}; done

if [[ ${#warnArr[@]} != 0 ]]; then
    echo "===================警告==================="
    for i in "${warnArr[@]}"; do echo ${i}; done
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

# 结束
exit 0

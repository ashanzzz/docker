# ERPNext AIO (MariaDB + Redis + Nginx + Supervisor + Bench)
# 只设置时区为上海；ERPNext 自带中文，不再强制系统中文本地化
FROM ubuntu:22.04

ENV TZ=Asia/Shanghai \
    DEBIAN_FRONTEND=noninteractive

ARG CHINA_MIRRORS=no
ARG FRAPPE_BRANCH=version-15
ARG ERPNEXT_BRANCH=version-15
ARG SITE_NAME=site1.local
ARG ADMIN_PASSWORD=admin
ARG SITE_DB_PASSWORD=Pass1234
ARG MARIADB_ROOT_PASSWORD=Pass1234
ARG WEB_PORT=80

SHELL ["/bin/bash", "-lc"]

# 可选：切换为国内源
RUN set -e; \
  if [[ "$CHINA_MIRRORS" == "yes" ]]; then \
    cp /etc/apt/sources.list /etc/apt/sources.list.bak || true; \
    cat > /etc/apt/sources.list <<'EOF'; \
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF
  fi

# 基础包
RUN set -e; \
  apt-get update; \
  apt-get upgrade -y; \
  apt-get install -y --no-install-recommends \
    ca-certificates sudo locales tzdata cron wget curl git \
    python3 python3-dev python3-venv python3-setuptools python3-pip python3-testresources \
    software-properties-common \
    mariadb-server mariadb-client libmysqlclient-dev \
    xvfb libfontconfig wkhtmltopdf \
    supervisor nginx \
    redis-server \
    pkg-config build-essential \
    libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev \
    gpg lsb-release; \
  rm -rf /var/lib/apt/lists/*

# 生成 en_US.UTF-8（ERPNext 兼容好）；只保留时区为上海
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen

# Node.js 20 + yarn + npm（国内镜像可选）
RUN set -e; \
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; \
  apt-get update && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*; \
  npm install -g npm yarn; \
  if [[ "$CHINA_MIRRORS" == "yes" ]]; then \
    npm config set registry https://registry.npmmirror.com -g; \
    yarn config set registry https://registry.npmmirror.com --global; \
  fi

# pip 国内镜像（可选）
RUN set -e; \
  mkdir -p /root/.pip; \
  if [[ "$CHINA_MIRRORS" == "yes" ]]; then \
    cat > /root/.pip/pip.conf <<'EOF'; \
[global]
index-url=https://pypi.tuna.tsinghua.edu.cn/simple
[install]
trusted-host=mirrors.tuna.tsinghua.edu.cn
EOF
  fi

# 安装 bench
RUN pip3 install --upgrade pip setuptools cryptography psutil && \
    pip3 install frappe-bench

# 新建 frappe 用户
RUN set -e; \
  groupadd -g 1000 -f frappe; \
  id -u frappe &>/dev/null || useradd --no-log-init -m -u 1000 -g 1000 -G sudo -s /bin/bash frappe; \
  echo "frappe ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers; \
  mkdir -p /home/frappe/.pip && cp -a /root/.pip/. /home/frappe/.pip/ 2>/dev/null || true; \
  chown -R frappe:frappe /home/frappe

# MariaDB/Redis/Nginx/Supervisor 基础配置
RUN set -e; \
  mkdir -p /var/run/log /etc/supervisor/conf.d; \
  # 适度调整 inotify（容器内可能不生效，但保留配置以对齐原逻辑）
  sed -i '/^fs.inotify.max_user_watches=.*/d' /etc/sysctl.conf || true; \
  echo fs.inotify.max_user_watches=524288 >> /etc/sysctl.conf || true

# supervisor 管理 MariaDB & Nginx（其余由 bench 生成的 conf 接管）
RUN cat > /etc/supervisor/conf.d/mariadb.conf <<'EOF'
[program:mariadb]
command=/usr/sbin/mariadbd --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib/mysql/plugin --user=mysql --skip-log-error
autostart=true
autorestart=true
startretries=10
redirect_stderr=true
stdout_logfile=/var/run/log/supervisor_mariadb.log
EOF

RUN cat > /etc/supervisor/conf.d/nginx.conf <<'EOF'
[program:nginx]
command=/usr/sbin/nginx -g 'daemon off;'
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/run/log/supervisor_nginx.log
EOF

# 入口脚本：首次启动自动完成 init/new-site/生产模式，之后幂等
RUN cat > /usr/local/bin/entrypoint.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# -------- 参数 --------
: "${FRAPPE_BRANCH:=version-15}"
: "${ERPNEXT_BRANCH:=version-15}"
: "${SITE_NAME:=site1.local}"
: "${ADMIN_PASSWORD:=admin}"
: "${SITE_DB_PASSWORD:=Pass1234}"
: "${MARIADB_ROOT_PASSWORD:=Pass1234}"
: "${WEB_PORT:=80}"

USER_FRAPPE=frappe
BENCH_DIR=/home/${USER_FRAPPE}/frappe-bench

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export PATH=/home/${USER_FRAPPE}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "=================== ERPNext AIO Entry ==================="

# ---- MariaDB 配置（my.cnf）----
if ! grep -q "ERPNext AIO" /etc/mysql/my.cnf 2>/dev/null; then
  cat >> /etc/mysql/my.cnf <<EOCNF
# ERPNext AIO
[mysqld]
character-set-client-handshake=FALSE
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
bind-address=0.0.0.0

[mysql]
default-character-set=utf8mb4
EOCNF
fi

# ---- 初始化 MariaDB 数据目录 ----
if [ ! -d /var/lib/mysql/mysql ]; then
  echo "Initializing MariaDB data directory..."
  install -o mysql -g mysql -d /var/lib/mysql
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql --basedir=/usr >/dev/null
fi

# ---- 启动临时 MariaDB 完成口令与授权 ----
echo "Starting temporary MariaDB for initialization..."
/usr/sbin/mariadbd --user=mysql --skip-networking=0 --bind-address=0.0.0.0 --skip-log-error --daemonize

for i in {1..60}; do
  if mysql -uroot -e 'SELECT 1' >/dev/null 2>&1; then break; fi
  sleep 1
done

if ! mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e 'SELECT 1' >/dev/null 2>&1; then
  echo "Setting MariaDB root password..."
  mysqladmin -uroot password "${MARIADB_ROOT_PASSWORD}" || true
fi

mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}' WITH GRANT OPTION; FLUSH PRIVILEGES;" || true
sed -i "s/^password.*/password=${MARIADB_ROOT_PASSWORD}/" /etc/mysql/debian.cnf || true

# 关闭临时 MariaDB，后面交给 supervisor
mysqladmin -uroot -p"${MARIADB_ROOT_PASSWORD}" shutdown || true

# ---- 准备 frappe 用户主目录 ----
id -u ${USER_FRAPPE} >/dev/null 2>&1 || useradd -m -s /bin/bash ${USER_FRAPPE}
chown -R ${USER_FRAPPE}:${USER_FRAPPE} /home/${USER_FRAPPE}

# ---- 初始化 bench（幂等）----
if [ ! -d "${BENCH_DIR}" ]; then
  echo "bench init (${FRAPPE_BRANCH}) ..."
  su - ${USER_FRAPPE} -c "bench init ${FRAPPE_BRANCH} --python /usr/bin/python3 --ignore-exist '${BENCH_DIR}'"
fi

# ---- 获取应用（幂等）----
echo "bench get-apps ..."
su - ${USER_FRAPPE} -c "cd '${BENCH_DIR}' && bench get-app ${ERPNEXT_BRANCH} https://github.com/frappe/erpnext"
su - ${USER_FRAPPE} -c "cd '${BENCH_DIR}' && bench get-app payments"
su - ${USER_FRAPPE} -c "cd '${BENCH_DIR}' && bench get-app print_designer"

# ---- 建站（幂等）----
if [ ! -d "${BENCH_DIR}/sites/${SITE_NAME}" ]; then
  echo "bench new-site ${SITE_NAME} ..."
  su - ${USER_FRAPPE} -c "cd '${BENCH_DIR}' && bench new-site --mariadb-root-password '${MARIADB_ROOT_PASSWORD}' --db-password '${SITE_DB_PASSWORD}' --admin-password '${ADMIN_PASSWORD}' '${SITE_NAME}'"
  su - ${USER_FRAPPE} -c "cd '${BENCH_DIR}' && bench --site '${SITE_NAME}' install-app payments"
  su - ${USER_FRAPPE} -c "cd '${BENCH_DIR}' && bench --site '${SITE_NAME}' install-app erpnext"
  su - ${USER_FRAPPE} -c "cd '${BENCH_DIR}' && bench --site '${SITE_NAME}' install-app print_designer"
  su - ${USER_FRAPPE} -c "cd '${BENCH_DIR}' && bench config http_timeout 6000 && bench config serve_default_site on && bench use '${SITE_NAME}'"
fi

# ---- 生产模式（生成 supervisor & nginx 配置；忽略重载失败以保持幂等）----
apt-get update && apt-get install -y nginx || true
echo "bench setup production ..."
su - ${USER_FRAPPE} -c "cd '${BENCH_DIR}' && yes | bench setup production ${USER_FRAPPE}" || true

# ---- nginx 端口 ----
if [ -f "${BENCH_DIR}/config/nginx.conf" ]; then
  sed -i -E "0,/listen [0-9]+;/s//listen ${WEB_PORT};/" "${BENCH_DIR}/config/nginx.conf" || true
  sed -i -E "0,/listen \[::\]:[0-9]+;/s//listen [::]:${WEB_PORT};/" "${BENCH_DIR}/config/nginx.conf" || true
  ln -sf "${BENCH_DIR}/config/nginx.conf" /etc/nginx/conf.d/frappe-bench.conf
fi

# ---- 确保 supervisor 程序就绪 ----
mkdir -p /var/run/log
echo "Starting supervisord (PID 1) ..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
EOF
RUN chmod +x /usr/local/bin/entrypoint.sh

# 数据持久化（卷）
VOLUME ["/var/lib/mysql", "/home/frappe/frappe-bench/sites"]

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=10 \
  CMD curl -fsS http://127.0.0.1:${WEB_PORT}/api/method/ping || exit 1

CMD ["/usr/local/bin/entrypoint.sh"]

FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive

# —— 可调参数（可在 workflow 的 build-args 覆盖）——
ARG FRAPPE_BRANCH=version-15
ARG ERPNEXT_BRANCH=version-15
ARG SITE_NAME=site1.local
ARG ADMIN_PASSWORD=admin
ARG SITE_DB_PASSWORD=Pass1234
ARG MARIADB_ROOT_PASSWORD=Pass1234
ARG BENCH_VERSION=
ARG USER_NAME=frappe
ARG INSTALL_DIR=frappe-bench
ARG CHINA_MIRRORS=no

# 只设置时区，按你的要求不改语言环境
ENV TZ=Asia/Shanghai

# 基础环境（可选国内源）
RUN set -eux; \
    if [ "$CHINA_MIRRORS" = "yes" ]; then \
      cp -f /etc/apt/sources.list /etc/apt/sources.list.bak || true; \
      sed -e 's|archive.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' \
          -e 's|security.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' \
          /etc/apt/sources.list.bak > /etc/apt/sources.list; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates sudo tzdata curl wget git \
      python3 python3-dev python3-venv python3-pip python3-setuptools python3-testresources \
      software-properties-common \
      mariadb-server mariadb-client libmysqlclient-dev \
      redis-server \
      xvfb libfontconfig wkhtmltopdf \
      nginx supervisor pkg-config build-essential \
      libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev \
      fonts-noto-cjk fonts-wqy-zenhei fonts-wqy-microhei; \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ >/etc/timezone

# Node.js 20 + Yarn（默认走官方源；国内构建再 CHINA_MIRRORS=yes 切换）
RUN set -eux; \
    if [ "$CHINA_MIRRORS" = "yes" ]; then \
      NODE_URL=$(curl -sL https://registry.npmmirror.com/-/binary/node/latest-v20.x/ | grep -oE "https?://[^\"']*node-v20\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz" | tail -1); \
    else \
      NODE_VER=$(curl -sL https://nodejs.org/dist/latest-v20.x/ | grep -oE "node-v20\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz" | head -1); \
      NODE_URL="https://nodejs.org/dist/latest-v20.x/${NODE_VER}"; \
    fi; \
    echo "Downloading $NODE_URL"; \
    mkdir -p /usr/local/lib/nodejs; cd /tmp; wget -q "$NODE_URL"; \
    tar -xJf node-v20.*-linux-x64.tar.xz -C /usr/local/lib/nodejs/; \
    mv /usr/local/lib/nodejs/node-v20.*-linux-x64 /usr/local/lib/nodejs/node-20; \
    echo 'export PATH=/usr/local/lib/nodejs/node-20/bin:$PATH' >/etc/profile.d/nodejs.sh; \
    export PATH=/usr/local/lib/nodejs/node-20/bin:$PATH; \
    npm -v; node -v; \
    npm install -g npm yarn; \
    if [ "$CHINA_MIRRORS" = "yes" ]; then \
      npm config set registry https://registry.npmmirror.com -g; \
      yarn config set registry https://registry.npmmirror.com --global; \
      mkdir -p /root/.pip && printf '[global]\nindex-url=https://pypi.tuna.tsinghua.edu.cn/simple\n' >/root/.pip/pip.conf; \
    fi

# MariaDB 编码与监听
RUN set -eux; \
    echo fs.inotify.max_user_watches=524288 >> /etc/sysctl.conf; \
    grep -q 'ERPNext install script added' /etc/mysql/my.cnf || { \
      echo '# ERPNext install script added' >> /etc/mysql/my.cnf; \
      echo '[mysqld]' >> /etc/mysql/my.cnf; \
      echo 'character-set-client-handshake=FALSE' >> /etc/mysql/my.cnf; \
      echo 'character-set-server=utf8mb4' >> /etc/mysql/my.cnf; \
      echo 'collation-server=utf8mb4_unicode_ci' >> /etc/mysql/my.cnf; \
      echo 'bind-address=0.0.0.0' >> /etc/mysql/my.cnf; \
      echo '' >> /etc/mysql/my.cnf; \
      echo '[mysql]' >> /etc/mysql/my.cnf; \
      echo 'default-character-set=utf8mb4' >> /etc/mysql/my.cnf; \
    }

# 创建 frappe 用户
RUN set -eux; \
    groupadd -g 1000 ${USER_NAME} || true; \
    useradd  -m -u 1000 -g 1000 -G sudo -s /bin/bash ${USER_NAME} || true; \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers; \
    echo -e "export PATH=/home/${USER_NAME}/.local/bin:/usr/local/lib/nodejs/node-20/bin:\$PATH" \
      >> /home/${USER_NAME}/.bashrc

# —— 构建期完成全部初始化（两文件模式的关键）——
RUN set -eux; export PATH="/usr/local/lib/nodejs/node-20/bin:${PATH}"; \
    python3 -m pip install --upgrade pip setuptools cryptography psutil; \
    if [ -n "$BENCH_VERSION" ]; then pip3 install "frappe-bench==$BENCH_VERSION"; else pip3 install frappe-bench; fi; \
    # init mysql
    chown -R mysql:mysql /var/lib/mysql; mkdir -p /var/run/mysqld; chown -R mysql:mysql /var/run/mysqld; \
    mysqld --user=mysql --daemonize --skip-log-error; \
    for i in $(seq 1 30); do mysqladmin ping && break || sleep 1; done; \
    if mysql -uroot -e 'SELECT 1' >/dev/null 2>&1; then mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}'"; fi; \
    mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}' WITH GRANT OPTION; FLUSH PRIVILEGES;"; \
    # bench init & apps（不装 erpnext_chinese，按你要求）
    su - ${USER_NAME} -c "bench --version || true"; \
    su - ${USER_NAME} -c "cd ~ && bench init ${INSTALL_DIR} --frappe-branch ${FRAPPE_BRANCH} --python /usr/bin/python3"; \
    su - ${USER_NAME} -c "cd ~/${INSTALL_DIR} && bench get-app ${ERPNEXT_BRANCH} https://github.com/frappe/erpnext"; \
    su - ${USER_NAME} -c "cd ~/${INSTALL_DIR} && bench get-app payments && bench get-app print_designer"; \
    # new site & install apps
    su - ${USER_NAME} -c "cd ~/${INSTALL_DIR} && bench new-site --mariadb-root-password ${MARIADB_ROOT_PASSWORD} --db-password ${SITE_DB_PASSWORD} --admin-password ${ADMIN_PASSWORD} ${SITE_NAME}"; \
    su - ${USER_NAME} -c "cd ~/${INSTALL_DIR} && bench --site ${SITE_NAME} install-app payments erpnext print_designer || true"; \
    su - ${USER_NAME} -c "cd ~/${INSTALL_DIR} && bench config http_timeout 6000 && bench config serve_default_site on && bench use ${SITE_NAME}"; \
    su - ${USER_NAME} -c "cd ~/${INSTALL_DIR} && bench build && bench clear-cache && bench clear-website-cache && bench setup nginx"; \
    ln -sf /home/${USER_NAME}/${INSTALL_DIR}/config/nginx.conf /etc/nginx/conf.d/erpnext.conf; \
    # 备份站点用于首次挂卷时回填
    mkdir -p /opt/bootstrap; rsync -a /home/${USER_NAME}/${INSTALL_DIR}/sites/ /opt/bootstrap/sites/; \
    chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}; \
    mysqladmin -uroot -p"${MARIADB_ROOT_PASSWORD}" shutdown || true; \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /var/cache/*

# supervisor（内联）
RUN bash -lc 'cat >/etc/supervisor/supervisord.conf << "EOF"\n[supervisord]\nnodaemon=true\nlogfile=/var/log/supervisor/supervisord.log\npidfile=/var/run/supervisord.pid\nchildlogdir=/var/log/supervisor\n\n[program:mariadb]\ncommand=/usr/sbin/mariadbd --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib/mysql/plugin --user=mysql --skip-log-error --bind-address=0.0.0.0\nautorestart=true\npriority=10\nstdout_logfile=/var/log/supervisor/mariadb.log\nstderr_logfile=/var/log/supervisor/mariadb.err\n\n[program:redis]\ncommand=/usr/bin/redis-server /etc/redis/redis.conf\nautorestart=true\npriority=20\nstdout_logfile=/var/log/supervisor/redis.log\nstderr_logfile=/var/log/supervisor/redis.err\n\n[program:bench-web]\ndirectory=/home/frappe/frappe-bench\ncommand=/bin/bash -lc \"bench web\"\nuser=frappe\nautorestart=true\npriority=30\nstdout_logfile=/var/log/supervisor/bench-web.log\nstderr_logfile=/var/log/supervisor/bench-web.err\nenvironment=HOME=\"/home/frappe\",USER=\"frappe\"\n\n[program:bench-schedule]\ndirectory=/home/frappe/frappe-bench\ncommand=/bin/bash -lc \"bench schedule\"\nuser=frappe\nautorestart=true\npriority=40\nstdout_logfile=/var/log/supervisor/bench-schedule.log\nstderr_logfile=/var/log/supervisor/bench-schedule.err\nenvironment=HOME=\"/home/frappe\",USER=\"frappe\"\n\n[program:bench-worker-short]\ndirectory=/home/frappe/frappe-bench\ncommand=/bin/bash -lc \"bench worker --queue short\"\nuser=frappe\nautorestart=true\npriority=50\n\n[program:bench-worker-default]\ndirectory=/home/frappe/frappe-bench\ncommand=/bin/bash -lc \"bench worker --queue default\"\nuser=frappe\nautorestart=true\npriority=51\n\n[program:bench-worker-long]\ndirectory=/home/frappe/frappe-bench\ncommand=/bin/bash -lc \"bench worker --queue long\"\nuser=frappe\nautorestart=true\npriority=52\n\n[program:nginx]\ncommand=/usr/sbin/nginx -g \"daemon off;\"\nautorestart=true\npriority=60\nstdout_logfile=/var/log/supervisor/nginx.out\nstderr_logfile=/var/log/supervisor/nginx.err\nEOF'

# 入口脚本
COPY erpnext15/aio/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/var/lib/mysql", "/home/frappe/frappe-bench/sites"]
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

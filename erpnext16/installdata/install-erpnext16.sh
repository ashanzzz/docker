#!/usr/bin/env bash
# ERPNext 16 AIO installer (Docker/Ubuntu 22.04)
# Goal:
# - Install official required core apps only: frappe + payments + erpnext
# - Keep optional official apps commented for manual enable (hrms/print_designer/erpnext_chinese)

set -euo pipefail

# ===== args =====
QUIET="no"
IN_DOCKER="no"
for arg in "$@"; do
  case "$arg" in
    -q) QUIET="yes" ;;
    -d) IN_DOCKER="yes" ;;
  esac
done

# ===== configurable env =====
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-Pass1234}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
SITE_NAME="${SITE_NAME:-site1.local}"
SITE_DB_PASSWORD="${SITE_DB_PASSWORD:-Pass1234}"
FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
ERPNEXT_BRANCH="${ERPNEXT_BRANCH:-version-16}"
BENCH_DIR="${BENCH_DIR:-/home/frappe/frappe-bench}"
ALT_APT_SOURCES="${ALT_APT_SOURCES:-yes}"

info(){ echo "[install-erpnext16] $*"; }

require_root() {
  if [[ "$(id -u)" != "0" ]]; then
    echo "Must run as root" >&2
    exit 1
  fi
}

require_ubuntu_2204() {
  if ! grep -q "Ubuntu 22.04" /etc/os-release; then
    echo "This script supports Ubuntu 22.04 only." >&2
    exit 1
  fi
}

set_cn_mirrors() {
  [[ "$ALT_APT_SOURCES" != "yes" ]] && return 0
  if [[ -f /etc/apt/sources.list ]]; then
    sed -i 's|http://archive.ubuntu.com/ubuntu|https://mirrors.tuna.tsinghua.edu.cn/ubuntu|g; s|http://security.ubuntu.com/ubuntu|https://mirrors.tuna.tsinghua.edu.cn/ubuntu|g' /etc/apt/sources.list || true
  fi
}

install_base_packages() {
  info "Installing system dependencies"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl wget git sudo locales tzdata cron supervisor nginx \
    mariadb-server mariadb-client libmysqlclient-dev redis-server redis-tools \
    python3 python3-dev python3-venv python3-pip python3-setuptools \
    build-essential pkg-config \
    libffi-dev libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev liblzma-dev \
    libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev \
    xvfb libfontconfig1 xfonts-75dpi xfonts-base

  # Node.js 24.x (required by ERPNext v16 frontend toolchain)
  if ! command -v node >/dev/null 2>&1 || ! node -v | grep -q '^v24\.'; then
    info "Installing Node.js 24.x"
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
  fi

  npm config set registry https://registry.npmmirror.com -g || true
  npm install -g yarn
  yarn config set registry https://registry.npmmirror.com --global || true

  python3 -m pip install --upgrade pip setuptools wheel frappe-bench

  # wkhtmltopdf patched qt (official recommendation path)
  if ! wkhtmltopdf --version 2>/dev/null | grep -qi 'with patched qt'; then
    info "Installing wkhtmltopdf 0.12.6.1 (patched qt)"
    wget -qO /tmp/wkhtmltox.deb "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
    DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/wkhtmltox.deb
    rm -f /tmp/wkhtmltox.deb
  fi
}

configure_services() {
  info "Configuring MariaDB/Redis"
  # MariaDB charset for frappe
  if ! grep -q 'ERPNext install script added' /etc/mysql/my.cnf 2>/dev/null; then
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

  service mariadb restart || true
  if mysql -uroot -e 'select 1' >/dev/null 2>&1; then
    mysqladmin -uroot password "${MARIADB_ROOT_PASSWORD}" || true
  fi
  mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}' WITH GRANT OPTION; FLUSH PRIVILEGES;" || true

  service redis-server restart || true
}

ensure_frappe_user() {
  if ! id -u frappe >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo frappe
  fi
  echo 'frappe ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/frappe
  chmod 0440 /etc/sudoers.d/frappe
}

init_bench_and_site() {
  info "Initializing bench"
  su - frappe -c "cd ~ && rm -rf frappe-bench && bench init --frappe-branch ${FRAPPE_BRANCH} frappe-bench"

  info "Fetching official apps (required core)"
  su - frappe -c "cd ${BENCH_DIR} && bench get-app --branch ${ERPNEXT_BRANCH} erpnext"
  su - frappe -c "cd ${BENCH_DIR} && bench get-app --branch ${ERPNEXT_BRANCH} payments"

  # Optional official apps (manual enable only):
  # su - frappe -c "cd ${BENCH_DIR} && bench get-app --branch ${ERPNEXT_BRANCH} hrms"
  # su - frappe -c "cd ${BENCH_DIR} && bench get-app --branch ${ERPNEXT_BRANCH} print_designer"

  info "Creating site"
  su - frappe -c "cd ${BENCH_DIR} && bench new-site ${SITE_NAME} --mariadb-root-password ${MARIADB_ROOT_PASSWORD} --db-password ${SITE_DB_PASSWORD} --admin-password ${ADMIN_PASSWORD}"

  info "Installing required core apps"
  su - frappe -c "cd ${BENCH_DIR} && bench --site ${SITE_NAME} install-app payments"
  su - frappe -c "cd ${BENCH_DIR} && bench --site ${SITE_NAME} install-app erpnext"

  # Optional official apps (manual install template):
  # su - frappe -c "cd ${BENCH_DIR} && bench --site ${SITE_NAME} install-app hrms"
  # su - frappe -c "cd ${BENCH_DIR} && bench --site ${SITE_NAME} install-app print_designer"

  # Optional non-official app (disabled):
  # su - frappe -c "cd ${BENCH_DIR} && bench get-app https://gitee.com/yuzelin/erpnext_chinese.git"
  # su - frappe -c "cd ${BENCH_DIR} && bench --site ${SITE_NAME} install-app erpnext_chinese"

  su - frappe -c "cd ${BENCH_DIR} && bench use ${SITE_NAME} && bench clear-cache && bench clear-website-cache"
}

setup_production() {
  info "Setting production mode"
  su - frappe -c "cd ${BENCH_DIR} && sudo bench setup production frappe --yes"
}

setup_docker_supervisor() {
  [[ "$IN_DOCKER" != "yes" ]] && return 0
  info "Configuring supervisord for docker"

  mkdir -p /home/frappe/.config/supervisor /var/run/log

  cat > /home/frappe/.config/supervisor/mariadb.conf <<'EOF'
[program:mariadb]
command=/usr/sbin/mariadbd --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib/mysql/plugin --user=mysql --skip-log-error
priority=1
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/run/log/supervisor_mysql.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=5
EOF

  cat > /home/frappe/.config/supervisor/nginx.conf <<'EOF'
[program:nginx]
command=/usr/sbin/nginx -g 'daemon off;'
autostart=true
autorestart=true
stderr_logfile=/var/run/log/supervisor_nginx_error.log
stdout_logfile=/var/run/log/supervisor_nginx_stdout.log
stopsignal=INT
EOF

  ln -sf /home/frappe/.config/supervisor/mariadb.conf /etc/supervisor/conf.d/mariadb.conf
  ln -sf /home/frappe/.config/supervisor/nginx.conf /etc/supervisor/conf.d/nginx.conf
}

cleanup() {
  apt-get clean
  rm -rf /var/lib/apt/lists/* /tmp/*
}

main() {
  require_root
  require_ubuntu_2204
  set_cn_mirrors
  install_base_packages
  configure_services
  ensure_frappe_user
  init_bench_and_site
  setup_production
  setup_docker_supervisor
  cleanup

  info "Done. site=${SITE_NAME}, admin=Administrator"
  info "For docker entrypoint: supervisord -n -c /etc/supervisor/supervisord.conf"
}

main "$@"

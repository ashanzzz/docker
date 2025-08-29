#!/usr/bin/env bash
set -euo pipefail

FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-15}"
ERPNEXT_BRANCH="${ERPNEXT_BRANCH:-version-15}"
SITE_NAME="${SITE_NAME:-site1.local}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
SITE_DB_PASSWORD="${SITE_DB_PASSWORD:-Pass1234}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-Pass1234}"
USER_NAME="${USER_NAME:-frappe}"
INSTALL_DIR="${INSTALL_DIR:-frappe-bench}"

export PATH="/usr/local/lib/nodejs/node-20/bin:${PATH}"

echo ">>> Upgrade pip & tools"
python3 -m pip install --upgrade pip setuptools cryptography psutil
if [[ -n "${BENCH_VERSION:-}" ]]; then
  pip3 install "frappe-bench==${BENCH_VERSION}"
else
  pip3 install frappe-bench
fi

echo ">>> Prepare MariaDB datadir & start temporary mysqld"
chown -R mysql:mysql /var/lib/mysql
mkdir -p /var/run/mysqld
chown -R mysql:mysql /var/run/mysqld
# init done by postinst usually, but ensure privileges
mysqld --user=mysql --daemonize --skip-log-error
# wait for mysqld
for i in {1..30}; do
  mysqladmin ping && break || sleep 1
done
# root password & grants
if mysql -uroot -e 'SELECT 1' >/dev/null 2>&1; then
  mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';"
fi
mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}' WITH GRANT OPTION; FLUSH PRIVILEGES;"

echo ">>> Create ${USER_NAME} bench, init frappe"
su - "${USER_NAME}" -c "bench --version || true"
su - "${USER_NAME}" -c "cd ~ && bench init ${INSTALL_DIR} --frappe-branch ${FRAPPE_BRANCH} --python /usr/bin/python3 --ignore-exist"

echo ">>> Get apps"
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench get-app ${ERPNEXT_BRANCH} https://github.com/frappe/erpnext"
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench get-app payments"
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench get-app print_designer"
# 中文本地化（gitee）
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench get-app https://gitee.com/yuzelin/erpnext_chinese.git || true"

echo '>>> New site'
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench new-site --mariadb-root-password ${MARIADB_ROOT_PASSWORD} --db-password ${SITE_DB_PASSWORD} --admin-password ${ADMIN_PASSWORD} ${SITE_NAME}"

echo '>>> Install apps to site'
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench --site ${SITE_NAME} install-app payments"
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench --site ${SITE_NAME} install-app erpnext"
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench --site ${SITE_NAME} install-app print_designer || true"
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench --site ${SITE_NAME} install-app erpnext_chinese || true"

echo '>>> Serve default site & build assets'
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench config http_timeout 6000 && bench config serve_default_site on && bench use ${SITE_NAME}"
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench build && bench clear-cache && bench clear-website-cache"

echo '>>> Generate nginx config (no reload here)'
su - "${USER_NAME}" -c "cd ~/${INSTALL_DIR} && bench setup nginx"
# 统一放到 conf.d
ln -sf /home/${USER_NAME}/${INSTALL_DIR}/config/nginx.conf /etc/nginx/conf.d/erpnext.conf

echo '>>> Bootstrap copy for volume seeding'
mkdir -p /opt/bootstrap
rsync -a /home/${USER_NAME}/${INSTALL_DIR}/sites/ /opt/bootstrap/sites/
chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}

echo '>>> Stop temporary mysqld'
mysqladmin -uroot -p"${MARIADB_ROOT_PASSWORD}" shutdown || true

echo '>>> Clean up'
apt-get clean
rm -rf /var/lib/apt/lists/* /root/.cache /var/cache/*

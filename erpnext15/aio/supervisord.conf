#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${USER_NAME:-frappe}"
INSTALL_DIR="${INSTALL_DIR:-frappe-bench}"
SITE_DIR="/home/${USER_NAME}/${INSTALL_DIR}/sites"

# 如果挂载卷是空的，用构建期的 bootstrap 内容填充
if [ ! -f "${SITE_DIR}/common_site_config.json" ]; then
  echo "Seeding sites from /opt/bootstrap..."
  rsync -a /opt/bootstrap/sites/ "${SITE_DIR}/" || true
  chown -R ${USER_NAME}:${USER_NAME} "${SITE_DIR}"
fi

# 确保 nginx 使用 bench 生成的配置
if [ ! -f /etc/nginx/conf.d/erpnext.conf ]; then
  ln -sf "/home/${USER_NAME}/${INSTALL_DIR}/config/nginx.conf" /etc/nginx/conf.d/erpnext.conf
fi

# 权限修正
chown -R mysql:mysql /var/lib/mysql || true
chown -R ${USER_NAME}:${USER_NAME} "/home/${USER_NAME}"

exec "$@"

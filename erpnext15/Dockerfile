FROM ubuntu:22.04
LABEL author=lvxj11

ENV DEBIAN_FRONTEND=noninteractive
ENV MARIADB_ROOT_PASSWORD=Pass1234
ENV ADMIN_PASSWORD=admin

# 把 installdata 目录拷进去（如果里面还有你要用的文件）
COPY installdata/ /installdata/
# 把脚本本身也拷到 /installdata 下（关键修复）
COPY install-erpnext15.sh /installdata/install-erpnext15.sh

# 统一用 bash 做 RUN 的 shell，顺带处理 CRLF 与执行位
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -eux; \
    ls -lah /installdata; \
    sed -i 's/\r$//' /installdata/install-erpnext15.sh; \
    chmod 0755 /installdata/install-erpnext15.sh; \
    /installdata/install-erpnext15.sh -qd

# 脚本已创建 frappe 用户和 bench 环境
USER frappe
WORKDIR /home/frappe/frappe-bench

EXPOSE 3306 80
VOLUME /home/frappe/frappe-bench/sites
VOLUME /var/lib/mysql
STOPSIGNAL SIGTERM

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["sudo /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf"]

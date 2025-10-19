# erpnext
FROM ubuntu:22.04
LABEL author=lvxj11

ENV MARIADB_ROOT_PASSWORD=Pass1234
ENV ADMIN_PASSWORD=admin

# 安装脚本
COPY ./installdata /installdata
RUN /bin/bash -c "chmod -R 777 /installdata/* && /installdata/install-erpnext15.sh -qd"

# 入口脚本（新版，见上）
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 运行用户与目录
USER frappe
WORKDIR /home/frappe/frappe-bench

# 公开端口
EXPOSE 3306 80

# 持久化（Unraid 映射到 ERPNext_db / ERPNext_sites）
VOLUME /home/frappe/frappe-bench/sites
VOLUME /var/lib/mysql

STOPSIGNAL SIGTERM

# 用新版 entrypoint；CMD 仍旧启动 supervisord
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sudo","/usr/bin/supervisord","-n","-c","/etc/supervisor/supervisord.conf"]

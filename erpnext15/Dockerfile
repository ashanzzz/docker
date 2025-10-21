# ERPNext v15 Docker Image
FROM ubuntu:22.04
LABEL maintainer="lvxj11"

ENV MARIADB_ROOT_PASSWORD=Pass1234
ENV ADMIN_PASSWORD=admin

# 复制安装脚本并执行
COPY ./installdata /installdata
RUN /bin/bash -c "chmod -R 777 /installdata && /installdata/install-erpnext15.sh -qd"

# 复制入口脚本并授权执行
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 切换到 frappe 用户，准备运行环境
USER frappe
WORKDIR /home/frappe/frappe-bench

# 暴露端口（数据库 & HTTP）
EXPOSE 3306 80

# 定义持久化目录（数据库和站点数据）
VOLUME /home/frappe/frappe-bench/sites
VOLUME /var/lib/mysql

STOPSIGNAL SIGTERM

# 使用 entrypoint 脚本；CMD 启动 supervisord（通过 entrypoint 间接调用）
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sudo", "/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

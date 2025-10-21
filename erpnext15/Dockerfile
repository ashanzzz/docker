# ERPNext AIO (v15) on Ubuntu 22.04
FROM ubuntu:22.04
LABEL author="lvxj11"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    MARIADB_ROOT_PASSWORD=Pass1234 \
    ADMIN_PASSWORD=admin

# 安装脚本与资源
COPY ./installdata /installdata
RUN /bin/bash -lc "chmod -R 755 /installdata && chmod +x /installdata/install-erpnext15.sh"

# 执行安装（q: 静默, d: Docker 适配）
RUN /bin/bash -lc "/installdata/install-erpnext15.sh -qd"

# 入口脚本（负责资产构建 & 运行期健康自愈）
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 以 frappe 用户运行
USER frappe
WORKDIR /home/frappe/frappe-bench

# 暴露端口
EXPOSE 3306 80

# 数据持久化
VOLUME ["/home/frappe/frappe-bench/sites", "/var/lib/mysql"]

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sudo","/usr/bin/supervisord","-n","-c","/etc/supervisor/supervisord.conf"]

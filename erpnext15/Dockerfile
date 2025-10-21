# erpnext AIO for v15 on Ubuntu 22.04
FROM ubuntu:22.04
LABEL author="lvxj11"

# 这些环境变量用于安装脚本及 entrypoint
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    MARIADB_ROOT_PASSWORD=Pass1234 \
    ADMIN_PASSWORD=admin

# 将安装脚本和资源复制进容器
COPY ./installdata /installdata
RUN /bin/bash -lc "chmod -R 755 /installdata && chmod +x /installdata/install-erpnext15.sh"

# 运行安装脚本（q=静默，d=Docker适配）
# 警告：你提到的密码警告无所谓，这里保持 ENV 方式
RUN /bin/bash -lc "/installdata/install-erpnext15.sh -qd"

# 入口脚本（你已有的新版，会负责资源构建与数据库迁移）
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 切到运行用户与工作目录（install 脚本里已创建 frappe 用户并初始化 bench）
USER frappe
WORKDIR /home/frappe/frappe-bench

# 暴露端口（DB & HTTP）
EXPOSE 3306 80

# 数据卷（持久化 sites 与 mariadb 数据）
VOLUME ["/home/frappe/frappe-bench/sites", "/var/lib/mysql"]

STOPSIGNAL SIGTERM

# 用 entrypoint 启动；CMD 交给 supervisord
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sudo","/usr/bin/supervisord","-n","-c","/etc/supervisor/supervisord.conf"]

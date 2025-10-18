# erpnext
FROM ubuntu:22.04
LABEL author=lvxj11

ENV MARIADB_ROOT_PASSWORD=Pass1234
ENV ADMIN_PASSWORD=admin

# 复制安装脚本
COPY ./installdata /installdata
# 复制启动脚本
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

# 运行安装（你的脚本会装 MariaDB/Redis/Node/Yarn/Bench 并创建站点、生产模式等）
RUN /bin/bash -c "chmod -R 777 /installdata/* && /installdata/install-erpnext15.sh -qd"

# —— 这里仍然是 root 身份 ——
# 预留一个资产备份目录（给首启加速用）
RUN mkdir -p /opt/assets-dist && chown -R 1000:1000 /opt/assets-dist

# 切换到 frappe 用户，预编译一份 assets 存到 /opt/assets-dist（为了冷启动快&作为兜底）
USER frappe
WORKDIR /home/frappe/frappe-bench
RUN bench setup assets && \
    bench build --production || bench build && \
    cp -a /home/frappe/frappe-bench/sites/assets/* /opt/assets-dist/ || true

# 回到 root：给 entrypoint 执行权限
USER root
RUN chmod +x /usr/local/bin/entrypoint.sh

# 再切回 frappe（和你原来一致）
USER frappe
WORKDIR /home/frappe/frappe-bench

EXPOSE 3306 80

VOLUME /home/frappe/frappe-bench/sites
VOLUME /var/lib/mysql

STOPSIGNAL SIGTERM

# ✅ 使用自愈入口；CMD 仍然启动 supervisord（你的 sudoers 已 NOPASSWD）
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sudo","/usr/bin/supervisord","-n","-c","/etc/supervisor/supervisord.conf"]

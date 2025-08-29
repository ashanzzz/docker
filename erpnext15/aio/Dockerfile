# erpnext15/aio/Dockerfile
# 以普通自定义镜像为基础，增加 AIO 启动逻辑（supervisord + 入口脚本）

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER root
# 兜底安装（通常基础镜像已有）
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      supervisor \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /var/log/supervisor /opt/aio && chown -R frappe:frappe /opt/aio /var/log/supervisor

# 拷贝入口脚本与 supervisor 配置
COPY erpnext15/aio/entrypoint.sh /opt/aio/entrypoint.sh
COPY erpnext15/aio/supervisord.conf /opt/aio/supervisord.conf
RUN chmod +x /opt/aio/entrypoint.sh

# 端口说明：Nginx=8080（对外），Backend=8000（被反代），SocketIO=9000
EXPOSE 8080 8000 9000

USER frappe
ENTRYPOINT ["/opt/aio/entrypoint.sh"]

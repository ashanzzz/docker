# docker/erpnext15/Dockerfile
# 说明：
# 1) 基于 Ubuntu 22.04，完全复用你提供的 installdata/install-erpnext15.sh 的安装流程与风格（-q 静默、-d Docker 适配、生产模式）。
# 2) 构建期仍会按原脚本安装 MariaDB/Redis/bench 等（保持“尊重原版”）；运行期是否启用内置 MariaDB 由 EXTERNAL_DB 决定。
# 3) 如果 EXTERNAL_DB=1（默认），容器运行时将“仅连接外部数据库”，不会启动容器内 MariaDB；
#    如果 EXTERNAL_DB=0，则会像原始 all-in-one 那样启动容器内 MariaDB，并且建议映射 /var/lib/mysql。
# 4) 版本锁定/强制覆盖版本的逻辑在 GitHub Actions 工作流里完成；Dockerfile 不做“在线拉最新”之类行为，保证可重现性。

FROM ubuntu:22.04


# 基础环境变量（可在 docker run / Unraid UI 中覆盖）
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    # 外部数据库开关：1=使用外部DB（默认），0=启用容器内 MariaDB
    EXTERNAL_DB=1 \
    # 外部数据库连接信息（EXTERNAL_DB=1 时必须填写）
    DB_HOST="" \
    DB_PORT="3306" \
    DB_NAME="" \
    DB_USER="" \
    DB_PASSWORD="" \
    # 站点名与安装目录（如不改，会使用脚本里默认 site1.local / frappe-bench）
    SITE_NAME="site1.local" \
    INSTALL_DIR="frappe-bench" \
    USER_NAME="frappe"

# 仅拷贝安装脚本。此时不要覆盖 supervisord.conf（否则构建阶段可能因 nodaemon=true 卡住）
COPY ./installdata /installdata

# 执行安装脚本：
# -q 静默（不交互），-d Docker 适配（脚本内部会创建 supervisor 配置等），productionMode=yes（生产模式）
# 这里保持“原版风格”，让脚本完成所有依赖及 bench 初始化、站点创建与生产模式配置。
RUN set -eux; \
    chmod -R 755 /installdata; \
    /bin/bash -c "/installdata/install-erpnext15.sh -qd inDocker=yes productionMode=yes"; \
    # 时区（有些场景需要）
    ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone; \
    # 为 supervisor 准备日志目录（构建期不启动；运行期由 entrypoint 启动）
    mkdir -p /var/log/supervisor

# 现在覆盖我们自己的最小化 supervisor 主配置（nodaemon=true, include conf.d）
# 之所以在安装脚本之后再覆盖，是为了避免构建阶段被 nodaemon=true 阻塞
COPY ./supervisord.conf /etc/supervisor/supervisord.conf

# 复制入口脚本（运行期：按 EXTERNAL_DB=1/0 切换是否启动容器内 MariaDB，并写入站点 DB 连接）
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 与原镜像保持一致的运行用户/工作目录（entrypoint 中需要 sudo，请确保脚本已为 frappe 配置 NOPASSWD）
USER frappe
WORKDIR /home/frappe/frappe-bench

# 端口：80 为 ERPNext/Nginx，3306 仅在 EXTERNAL_DB=0 启容器内 MariaDB 时需要（保留兼容）
EXPOSE 80 3306

# 数据卷：
# - sites：站点文件必须持久化（原作者也建议）
# - mysql：仅当 EXTERNAL_DB=0 使用内置 MariaDB 时建议映射，EXTERNAL_DB=1 不会使用此卷
VOLUME ["/home/frappe/frappe-bench/sites", "/var/lib/mysql"]

# 入口脚本负责：按需切外部DB、修补 site_config、选择性生成/删除 mariadb.conf，然后以前台方式启动 supervisord
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 注：
# 1) 不在 Dockerfile 中执行任何“拉取最新源码”的动作，源码版本与镜像标签的“双重锁定”由 GitHub Actions 工作流实现。
# 2) 运行期通过环境变量（Unraid 容器变量 / docker run -e）控制站点名/数据库连接等；若 EXTERNAL_DB=1 且未提供 DB_*，entrypoint 会提示并退出。

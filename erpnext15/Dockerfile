# 基于 Ubuntu 22.04 LTS 镜像，更新系统并安装基础依赖
FROM ubuntu:22.04

# 设置非交互模式，避免APT等待交互
ENV DEBIAN_FRONTEND=noninteractive

# 安装必要的软件和依赖
# - python3-pip: Python 包管理器
# - git, curl: 用于获取 Frappe 和 ERPNext 源码
# - nodejs, npm: Node.js 和包管理器，用于前端构建和实时通信 (socket.io)
# - yarn: Node.js包管理工具，用于安装前端依赖
# - redis-server: Redis 缓存服务 (内部缓存和队列)
# - nginx: Nginx Web服务器，用于反向代理 Frappe 应用
# - mariadb-client: 用于连接外部MySQL/MariaDB数据库
# - libmysqlclient-dev: MySQL客户端开发库(用于Python MySQL驱动编译)
# - wkhtmltopdf: PDF生成工具 (使用patched Qt版本确保ERPNext报表正常生成PDF)
# - supervisor: 进程管理器，管理多个后台服务
# - sudo: 允许使用sudo命令，以便非root用户执行管理命令
# - fonts-noto-cjk: 思源黑体等中文字体，确保中文显示正常
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip python3-dev python3-setuptools git curl \
    nodejs npm yarn \
    redis-server nginx mariadb-client libmysqlclient-dev \
    supervisor sudo \
    fonts-noto-cjk \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# 安装 wkhtmltopdf 带有 patched QT 版本，用于正确生成PDF (0.12.6-1)
ENV WKHTML_PDF_URL=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.focal_amd64.deb
RUN curl -sSL "$WKHTML_PDF_URL" -o wkhtml.deb && dpkg -i wkhtml.deb || true \
 && apt-get update && apt-get install -y -f --no-install-recommends && apt-get clean && rm -rf /var/lib/apt/lists/* && rm wkhtml.deb

# 创建 frappe 用户，用于运行Bench和ERPNext服务，避免使用root运行应用
RUN useradd -m -s /bin/bash frappe \
 && echo "frappe ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/frappe

# 将工作目录切换到 frappe 用户的 home 目录
USER frappe
WORKDIR /home/frappe

# 使用pip安装 bench 工具 (Frappe Bench CLI)，以便管理Frappe/ERPNext
# 注: 安装bench后会提供`bench`命令
RUN pip3 install --no-cache-dir frappe-bench

# 初始化 Frappe 框架的 Bench 环境
# - 创建一个frappe-bench目录，指定Frappe版本15分支，并使用当前python
# - --skip-redis-config-generation 不使用，Bench会生成默认的Redis配置文件供后续使用
# (过程包括创建 Python 虚拟环境, 克隆 Frappe 框架代码, 安装Frappe依赖等)
RUN bench init --frappe-branch version-15 --python "$(which python3)" frappe-bench

# 切换工作目录到 bench 目录
WORKDIR /home/frappe/frappe-bench

# 获取 ERPNext 应用源码并安装 (版本15分支)
# Bench将通过Git克隆ERPNext仓库并自动使用pip安装应用依赖
RUN bench get-app --branch version-15 erpnext https://github.com/frappe/erpnext.git

# 获取并安装 Print Designer 应用 (用于打印格式设计，可选模块)
# 克隆官方 Print Designer 仓库，并安装到 Bench 环境
RUN bench get-app --branch main print_designer https://github.com/frappe/print_designer.git

# 安装前端依赖并构建前端资源
# - `bench setup requirements` 安装Python和Node.js依赖 (可选)
# - `bench build` 编译前端资源 (JS/CSS) 以生产模式使用
RUN yarn install --production && bench build

# 复制自定义 Supervisor 配置文件和 Entrypoint 脚本到镜像
# supervisord.conf: 定义ERPNext需运行的各服务 (web服务器Gunicorn, 后台worker, scheduler, socketio, redis, nginx 等)
# entrypoint.sh: 容器启动脚本，用于设置站点配置并启动supervisor
COPY supervisord.conf /etc/supervisor/conf.d/erpnext.conf
COPY entrypoint.sh /entrypoint.sh

# 修改 entrypoint.sh 的权限使其可执行
USER root
RUN chmod +x /entrypoint.sh

# 暴露容器的HTTP服务端口 (Nginx监听的端口)
EXPOSE 80

# 指定默认Entrypoint，运行自定义脚本进行初始化后再启动服务
ENTRYPOINT ["/entrypoint.sh"]

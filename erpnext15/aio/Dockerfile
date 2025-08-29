FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# 可调参数（也可由 GitHub Actions 传入）
ARG FRAPPE_BRANCH=version-15
ARG ERPNEXT_BRANCH=version-15
ARG SITE_NAME=site1.local
ARG ADMIN_PASSWORD=admin
ARG SITE_DB_PASSWORD=Pass1234
ARG MARIADB_ROOT_PASSWORD=Pass1234
ARG BENCH_VERSION=
ARG USER_NAME=frappe
ARG INSTALL_DIR=frappe-bench
ARG CHINA_MIRRORS=yes

ENV TZ=Asia/Shanghai \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en

# 基础包与中文源（可选）
RUN set -eux; \
    if [ "$CHINA_MIRRORS" = "yes" ]; then \
      cp -f /etc/apt/sources.list /etc/apt/sources.list.bak || true; \
      sed -e 's|archive.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' \
          -e 's|security.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' \
          /etc/apt/sources.list.bak > /etc/apt/sources.list; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates sudo locales tzdata curl wget git \
      python3 python3-dev python3-venv python3-pip python3-setuptools python3-testresources \
      software-properties-common \
      mariadb-server mariadb-client libmysqlclient-dev \
      redis-server \
      xvfb libfontconfig wkhtmltopdf \
      nginx supervisor pkg-config build-essential \
      libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev; \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen; \
    locale-gen; \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ >/etc/timezone

# Node.js 20 + Yarn（支持国内源）
RUN set -eux; \
    if [ "$CHINA_MIRRORS" = "yes" ]; then \
      NODE_URL=$(curl -sL https://registry.npmmirror.com/-/binary/node/latest-v20.x/ | grep -oE "https?://[^\"']*node-v20\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz" | tail -1); \
    else \
      NODE_URL=$(curl -sL https://nodejs.org/dist/latest-v20.x/ | grep -oE "href=\"node-v20\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz\"" | sed 's/href="//;s/"//;' | head -1); \
      NODE_URL="https://nodejs.org/dist/latest-v20.x/${NODE_URL}"; \
    fi; \
    echo "Downloading $NODE_URL"; \
    mkdir -p /usr/local/lib/nodejs; \
    cd /tmp; wget -q "$NODE_URL"; \
    tar -xJf node-v20.*-linux-x64.tar.xz -C /usr/local/lib/nodejs/; \
    NODE_DIR=$(basename /usr/local/lib/nodejs/node-v20.*-linux-x64); \
    mv /usr/local/lib/nodejs/${NODE_DIR} /usr/local/lib/nodejs/node-20; \
    echo 'export PATH=/usr/local/lib/nodejs/node-20/bin:$PATH' >/etc/profile.d/nodejs.sh; \
    export PATH=/usr/local/lib/nodejs/node-20/bin:$PATH; \
    npm -v; node -v; \
    npm install -g npm; \
    npm install -g yarn; \
    if [ "$CHINA_MIRRORS" = "yes" ]; then \
      npm config set registry https://registry.npmmirror.com -g; \
      yarn config set registry https://registry.npmmirror.c

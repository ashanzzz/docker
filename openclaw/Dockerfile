FROM ghcr.io/openclaw/openclaw:latest

USER root

# Full-featured runtime for OpenClaw in Docker:
# - Chromium browser support
# - Chinese font rendering
# - Common ops/debug tooling
# - UTF-8 locale defaults
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      chromium \
      fonts-noto-cjk \
      fonts-wqy-zenhei \
      locales \
      ca-certificates \
      tzdata \
      curl \
      wget \
      git \
      jq \
      sqlite3 \
      procps \
      net-tools \
      iproute2 \
      lsof \
      psmisc \
      xdg-utils && \
    sed -i 's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen zh_CN.UTF-8 && \
    update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 && \
    fc-cache -f -v >/dev/null && \
    rm -rf /var/lib/apt/lists/*

# Container defaults tuned for OpenClaw browser + Chinese rendering.
ENV LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    LC_ALL=zh_CN.UTF-8 \
    TZ=Asia/Shanghai \
    BROWSER=/usr/bin/chromium

# Simple runtime probe for debugging in Unraid logs.
RUN /usr/bin/chromium --version && sqlite3 --version

USER root

# syntax=docker/dockerfile:1

ARG NEXTCLOUD_VERSION=33.0.0
FROM nextcloud:${NEXTCLOUD_VERSION}-apache

# Install extra system dependencies (edit packages.txt to extend)
COPY packages.txt /tmp/packages.txt

RUN set -eux; \
  apt-get update; \
  # Filter comments/blank lines so packages.txt can be documented.
  grep -vE '^\s*(#|$)' /tmp/packages.txt | xargs -r apt-get install -y --no-install-recommends; \
  rm -rf /var/lib/apt/lists/* /tmp/packages.txt

# Recognize (MoViNet video classifier) requires native TensorFlow backend.
# In some deployments the app's tfjs-node dependency may miss libtensorflow.so.2,
# causing fallback to WASM and "Movinet does not support WASM mode" errors.
# We ship libtensorflow (CPU) in the image so video/audio tagging works after install.
ARG LIBTENSORFLOW_VERSION=2.9.1
RUN set -eux; \
  URL="https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-cpu-linux-x86_64-${LIBTENSORFLOW_VERSION}.tar.gz"; \
  TMPDIR="/tmp/libtensorflow"; \
  mkdir -p "$TMPDIR"; \
  curl -fsSL "$URL" -o "$TMPDIR/libtensorflow.tgz"; \
  tar -xzf "$TMPDIR/libtensorflow.tgz" -C "$TMPDIR"; \
  install -m 0755 -d /usr/local/lib; \
  # The archive provides libtensorflow.so (no version suffix). Create a versioned file + symlinks.
  install -m 0755 "$TMPDIR/lib/libtensorflow.so" "/usr/local/lib/libtensorflow.so.${LIBTENSORFLOW_VERSION}"; \
  ln -sf "libtensorflow.so.${LIBTENSORFLOW_VERSION}" /usr/local/lib/libtensorflow.so.2; \
  ln -sf libtensorflow.so.2 /usr/local/lib/libtensorflow.so; \
  install -m 0755 "$TMPDIR/lib/libtensorflow_framework.so" /usr/local/lib/libtensorflow_framework.so; \
  ldconfig; \
  rm -rf "$TMPDIR"

# Node.js (glibc) for Recognize's local classifiers.
# Recognize downloads its own node build when asked to, but it fetches the **musl** tarball
# (node-vXX-linux-x64-musl). This base image is Debian/glibc, so that binary dies with
#   exec /var/www/html/custom_apps/recognize/bin/node: no such file or directory
# (ELF interpreter /lib/ld-musl-x86_64.so.1 missing) and every classifier — including the
# face recognition people rely on — silently never runs.
# We ship an official glibc build on PATH; the entrypoint hook points `recognize node_binary` at it.
ARG NODE_VERSION=22.23.2
RUN set -eux; \
  ARCH="$(dpkg --print-architecture)"; \
  case "$ARCH" in \
    amd64) NODE_ARCH=x64 ;; \
    arm64) NODE_ARCH=arm64 ;; \
    *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;; \
  esac; \
  URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"; \
  mkdir -p /usr/local/lib/nodejs; \
  curl -fsSL "$URL" -o /tmp/node.tar.xz; \
  tar -xJf /tmp/node.tar.xz -C /usr/local/lib/nodejs --strip-components=1; \
  ln -sf /usr/local/lib/nodejs/bin/node /usr/local/bin/node; \
  ln -sf /usr/local/lib/nodejs/bin/npm /usr/local/bin/npm; \
  ln -sf /usr/local/lib/nodejs/bin/npx /usr/local/bin/npx; \
  rm -f /tmp/node.tar.xz; \
  node --version; \
  npm --version

# Entry-point hooks (for runtime auto-fixes; keep minimal)
COPY docker-entrypoint-hooks.d/ /docker-entrypoint-hooks.d/
RUN chmod +x /docker-entrypoint-hooks.d/before-starting/*.sh

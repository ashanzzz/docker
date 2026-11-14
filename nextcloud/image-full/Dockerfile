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

# Entry-point hooks (for runtime auto-fixes; keep minimal)
COPY docker-entrypoint-hooks.d/ /docker-entrypoint-hooks.d/
RUN chmod +x /docker-entrypoint-hooks.d/before-starting/*.sh

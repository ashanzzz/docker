# ==============================================================================
# Stage 1: Build Ultra-Lightweight Static Rust Supervisor (~4MB stripped binary)
# ==============================================================================
FROM rust:alpine AS builder
RUN apk add --no-cache musl-dev pkgconfig
WORKDIR /build
COPY rust/Cargo.toml ./
COPY rust/src ./src
RUN cargo build --release

# ==============================================================================
# Stage 2: Production Runtime on Official `driveone/onedrive:alpine` (~55MB total)
# ==============================================================================
FROM driveone/onedrive:alpine
LABEL org.opencontainers.image.title="onedrive-multisync" \
      org.opencontainers.image.description="Enterprise Single-Container Multi-Account OneDrive Bidirectional Sync & Self-Healing Gateway" \
      org.opencontainers.image.source="https://github.com/ashanzzz/docker"

RUN apk add --no-cache ca-certificates tzdata curl tini su-exec

COPY --from=builder /build/target/release/onedrive-multisync /usr/local/bin/onedrive-multisync
COPY python/onedrive_multisync/daemon.py /usr/local/bin/onedrive-multisync-py
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/onedrive-multisync-py

ENV CONFIG_DIR=/config \
    DATA_DIR=/data \
    API_PORT=8080 \
    ONEDRIVE_UID=99 \
    ONEDRIVE_GID=100 \
    HTTPS_PROXY=http://192.168.8.11:7890 \
    NO_PROXY=localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8

VOLUME ["/config", "/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/onedrive-multisync"]

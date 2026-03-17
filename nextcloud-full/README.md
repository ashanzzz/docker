# ashanzzz/nextcloud-full

An automated **derived** Nextcloud image that tracks the official Nextcloud **33.x** Docker image and adds extra system dependencies (e.g. `ffmpeg`) needed by certain Nextcloud apps/features.

## Upstream / references

- Official build logic & version source: https://github.com/nextcloud/docker
- Official Nextcloud image (Docker Hub): https://hub.docker.com/_/nextcloud

We follow upstream by reading `https://raw.githubusercontent.com/nextcloud/docker/master/versions.json` and taking `33.version` as the authoritative latest patch version.

## Goals

- Track **Nextcloud 33 patch releases** automatically (daily)
- Publish to GHCR: `ghcr.io/ashanzzz/nextcloud-full`
- Keep it easy to extend: add packages via `packages.txt`

## What this image is / isn't

- ✅ Adds **OS-level dependencies** (e.g. `ffmpeg`) inside the container image.
- ❌ Does **not** bundle Nextcloud apps from the App Store. Apps are installed into your persistent `custom_apps` volume in a running instance.

## Added packages

See `packages.txt`.

- **Video/preview baseline**: `ffmpeg`
- **AI/识别类 apps**：本镜像提供系统依赖；真正的“识别”来自 Nextcloud App（例如 Recognize），需要在 Nextcloud Web 里安装/启用，并确保 cron/后台任务在跑。

## Built-in TensorFlow runtime (for Recognize video tagging)

- 我们在镜像里内置了 **libtensorflow (CPU)**（默认 2.9.1），用于避免 Recognize 的 MoViNet 视频分类在某些环境里因为缺 `libtensorflow.so.2` 而回退到 WASM，进而报错：`Movinet does not support WASM mode`。
- 代价：镜像体积会明显增大（数百 MB 级）。

## Tags

- `ghcr.io/ashanzzz/nextcloud-full:<33.x.y>-apache-full` (immutable, recommended for production pinning)
- `ghcr.io/ashanzzz/nextcloud-full:33-apache-full` (moving, tracks latest 33 patch)
- `ghcr.io/ashanzzz/nextcloud-full:latest` (moving, convenience tag; equivalent to latest built)

## Automation

Workflow: `.github/workflows/nextcloud-full-ci-sync-build.yml` (in this repo)

Daily steps (schedule trigger):
1) Read upstream latest `33.version` from `nextcloud/docker` `versions.json`
2) Verify upstream base image exists: `nextcloud:<version>-apache`
3) Update `NEXTCLOUD_VERSION` if changed and commit
4) Build + push image to GHCR
5) Tag git `v<version>` and create a GitHub Release

PR steps (`pull_request` trigger):
- Build only (no push) to validate Dockerfile + packages changes

## Database + Redis configuration (official Nextcloud env vars)

This derived image keeps the official Nextcloud entrypoint/config behavior.

For DB/Redis, the official image supports configuring via environment variables (recommended for containers). A ready-to-edit example is in `docker-compose.example.yml`.

Authoritative reference: https://github.com/nextcloud/docker/blob/master/README.md

### MySQL/MariaDB env vars (example)

- `MYSQL_HOST`
- `MYSQL_DATABASE`
- `MYSQL_USER`
- `MYSQL_PASSWORD`

The upstream image also supports PostgreSQL:

- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_HOST`

Upstream note (secrets): "As an alternative to passing sensitive information via environment variables, `_FILE` may be appended to the previously listed environment variables".

### Redis session handler env vars (example)

- `REDIS_HOST`
- `REDIS_HOST_PORT` (optional)
- `REDIS_HOST_PASSWORD` / `REDIS_HOST_PASSWORD_FILE` (optional)
- `REDIS_HOST_USER` (optional)

Upstream note (UI vs env): if you configure values via Docker env, you generally should not set the same settings via the Nextcloud Web UI because env values override UI changes.

## Cron / background jobs (important)

For previews, video processing, and AI/识别类任务，必须保证 Nextcloud 的后台任务在跑。

推荐做法：使用单独的 `cron` service（见 `docker-compose.example.yml`，用同一个镜像但 `entrypoint: /cron.sh`）。

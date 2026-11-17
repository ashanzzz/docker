# ashanzzz/nextcloud-full

An automated **derived** Nextcloud image that tracks the official Nextcloud Docker image (currently **35.x**, pinned via `NEXTCLOUD_VERSION`) and adds extra system dependencies (e.g. `ffmpeg`, glibc Node.js) needed by certain Nextcloud apps/features.

## Upstream / references

- Official build logic & version source: https://github.com/nextcloud/docker
- Official Nextcloud image (Docker Hub): https://hub.docker.com/_/nextcloud

We follow upstream by reading `https://raw.githubusercontent.com/nextcloud/docker/master/versions.json` and taking the highest major's `version` field as the authoritative latest patch version.

## Goals

- Track **Nextcloud patch releases** automatically (monthly schedule + manual dispatch)
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

## Node.js runtime (glibc) — required for Recognize's local classifiers

- Recognize 本体不自带可用的 node：让 app 自己去下载时，它拉的是 **musl** 构建（`node-vXX-linux-x64-musl`）。本镜像基于 Debian/glibc，该二进制执行时只报 `exec .../bin/node: no such file or directory`（缺 `/lib/ld-musl-x86_64.so.1`），于是人脸识别/物体识别全部静默空转：`oc_recognize_face_detections = 0`、队列全空，但界面上看不出任何错误。
- 本镜像内置官方 **glibc node（默认 22.23.2，`NODE_VERSION` 可覆盖）** 到 `/usr/local/lib/nodejs`，并在 PATH 暴露 `node` / `npm` / `npx`。
- entrypoint hook `30-recognize-enable-features.sh` 会把 `recognize node_binary` 指向 `/usr/local/bin/node`，并打开 faces/imagenet/landmarks/movinet/musicnn 与温和的 batchSize（只在未设置或为 false 时写入，不覆盖管理员显式选择）。
- 该 hook 早期版本用 `app:list | grep '^\s*recognize\s*$'` 判断启用状态，实际输出是 `  - recognize: 13.2.0`，永远匹配不上，导致 hook 静默不生效；现已改为解析 `app:list --output=json`。
- 全量分类与聚类仍是显式动作：`occ recognize:classify` / `occ recognize:cluster-faces`（会长时间吃 CPU，建议配合维护窗口）。

## Recognize GPU mode (stability hook)

- 识别 GPU 模式在一些安装里会遇到：`tfjs-node-gpu` 缺少 `tfjs_binding.node`，导致报错并中断分类。
- 本镜像包含一个 entrypoint hook：如果检测到 `tfjs-node-gpu` 缺 binding，会自动用 `tfjs-node` 的 CPU binding 做兜底拷贝，避免 GPU 模式直接崩溃。
- 说明：这能保证“功能不报错”，但**不等同于真正 GPU 加速**（真正 GPU 加速还需完整的 tfjs-node-gpu binding + CUDA 依赖链）。

## Tags

- `ghcr.io/ashanzzz/nextcloud-full:<35.x.y>-apache-full` (immutable, recommended for production pinning)
- `ghcr.io/ashanzzz/nextcloud-full:35-apache-full` (moving, tracks latest patch of that major)
- `ghcr.io/ashanzzz/nextcloud-full:latest` (moving, convenience tag; equivalent to latest built)

## Automation

Workflow: `.github/workflows/nextcloud-full-ci-sync-build.yml` (in this repo)

Daily steps (schedule trigger):
1) Read upstream latest major's version from `nextcloud/docker` `versions.json`
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

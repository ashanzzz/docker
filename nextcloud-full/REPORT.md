# Report: ashanzzz/nextcloud-full

## Goal

Build and publish a **single-container Nextcloud (apache) derived image** that:

- Tracks official Nextcloud **33.x patch releases** automatically (daily)
- Adds OS-level dependencies required by some apps/features (e.g. `ffmpeg`)
- Publishes to **GHCR** with predictable tags
- Supports a **separate cron service** (recommended) to run background jobs reliably

## Upstream sources (authoritative)

- Nextcloud official Docker build repo (version tracking & variants): https://github.com/nextcloud/docker
  - Version source used by this repo: `versions.json` (`."33".version`)
- Official Nextcloud image docs (env vars, Redis, DB, SMTP notes):
  - https://github.com/nextcloud/docker/blob/master/README.md

Key upstream excerpts (from README):

- DB env vars are supported (MySQL/MariaDB: `MYSQL_*`, PostgreSQL: `POSTGRES_*`, SQLite: `SQLITE_DATABASE`).
- Secrets note: "`_FILE` may be appended to the previously listed environment variables".
- Redis: `REDIS_HOST`, `REDIS_HOST_PORT`, `REDIS_HOST_USER`, `REDIS_HOST_PASSWORD`.
- UI vs env note (SMTP example): if configured via Docker env, do not set via Web UI because env overrides UI values.

## Design choices & rationale

### Why derived from `nextcloud:<version>-apache`

The official images already include:

- Nextcloud tarball download + signature verification
- Update / upgrade logic in the upstream entrypoint
- Correct PHP/Apache baseline for Nextcloud 33 (currently php:8.4-* on Debian trixie for 33)

This repo only adds **extra packages** via `apt` to solve "missing binaries" problems.

### Why read `nextcloud/docker` `versions.json`

- `nextcloud/docker` maintains `versions.json` via `update.sh` + scheduled workflow.
- Reading `."33".version` provides an authoritative "latest 33 patch" value.
- We gate updates by checking the corresponding upstream image tag exists before building.

### How updates work

Workflow: `.github/workflows/nextcloud-full-ci-sync-build.yml` (in `ashanzzz/docker`)

Daily:
1) Fetch `versions.json` from upstream repo
2) Extract `33.version`
3) Verify `nextcloud:<version>-apache` exists (using `skopeo inspect`)
4) If changed: update `NEXTCLOUD_VERSION`, commit to `main`
5) Build and push to GHCR
6) Create git tag `v<version>` and GitHub Release

## Database + Redis configuration

This repo does not hardcode database or redis settings into the image.

Recommended approach is to configure via **environment variables** (documented by upstream) so that:

- initial install can be automated
- container remains reproducible
- secrets can be provided via `_FILE` variants

Example: see `docker-compose.example.yml`.

## Extending “full” functionality

Edit `packages.txt` to add apt packages (one per line), for example:

- media tooling: `ffmpeg`
- debugging: `procps`

Avoid installing large toolchains unless you need them; bigger images increase attack surface and update cost.

## Risks / limits

- This repo adds binaries; it does not guarantee every third-party app feature works on all CPUs.
- Some ML features depend on CPU instruction sets / native libs; those are outside the scope of `apt install ffmpeg`.
- Using `nextcloud:latest` in production is not recommended; this repo pins to explicit `33.x.y` via `NEXTCLOUD_VERSION`.

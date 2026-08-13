#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERP16_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

: "${ASHAN_REPO_URL:=https://github.com/ashanzzz/erpnext-private-customizations.git}"
: "${ASHAN_REPO_REF:=master}"
: "${ASHAN_REPO_TOKEN:=}"

APP_NAME="ashan_cn_procurement"
TARGET="${ERP16_DIR}/custom-apps/${APP_NAME}"

workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

clone_url="$ASHAN_REPO_URL"

if [[ -n "$ASHAN_REPO_TOKEN" && "$ASHAN_REPO_URL" == https://github.com/* ]]; then
  clone_url="${ASHAN_REPO_URL/https:\/\/github.com\//https:\/\/x-access-token:${ASHAN_REPO_TOKEN}@github.com\/}"
fi

echo "[ashan-sync] Source: ${ASHAN_REPO_URL}"
echo "[ashan-sync] Ref   : ${ASHAN_REPO_REF}"

git clone --depth 1 --branch "$ASHAN_REPO_REF" "$clone_url" "$workdir/repo"

SRC="$workdir/repo"

if [[ ! -f "$SRC/pyproject.toml" && ! -f "$SRC/setup.py" ]]; then
  echo "[ashan-sync] ERROR: app root has no pyproject.toml/setup.py" >&2
  exit 2
fi

if [[ ! -d "$SRC/$APP_NAME" ]]; then
  echo "[ashan-sync] ERROR: Python package missing: $APP_NAME/" >&2
  exit 3
fi

rm -rf "$TARGET"
mkdir -p "$(dirname "$TARGET")"
cp -a "$SRC" "$TARGET"
rm -rf "$TARGET/.git"

SOURCE_SHA="$(git -C "$SRC" rev-parse HEAD)"
printf '%s\n' "$SOURCE_SHA" > "$TARGET/.ashan-source-commit"

echo "[ashan-sync] Synced ${APP_NAME}"
echo "[ashan-sync] Commit: ${SOURCE_SHA}"
echo "[ashan-sync] Target: ${TARGET}"

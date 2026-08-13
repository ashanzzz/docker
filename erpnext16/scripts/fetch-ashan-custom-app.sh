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

REPO_ROOT="$workdir/repo"

# 兼容两种 Ashan 仓库布局：
#
# 1. 仓库本身就是 Frappe App
#    repo/pyproject.toml
#    repo/ashan_cn_procurement/
#
# 2. 仓库是开发工作区，Frappe App 位于子目录
#    repo/ashan_cn_procurement/pyproject.toml
#    repo/ashan_cn_procurement/ashan_cn_procurement/

if [[ -f "$REPO_ROOT/pyproject.toml" || -f "$REPO_ROOT/setup.py" ]]; then
  SRC="$REPO_ROOT"

elif [[ -f "$REPO_ROOT/$APP_NAME/pyproject.toml" || \
        -f "$REPO_ROOT/$APP_NAME/setup.py" ]]; then
  SRC="$REPO_ROOT/$APP_NAME"

else
  echo "[ashan-sync] ERROR: cannot locate Frappe app root for $APP_NAME" >&2
  echo "[ashan-sync] Repository root contents:" >&2
  find "$REPO_ROOT" -maxdepth 2 -type f \
    \( -name pyproject.toml -o -name setup.py \) \
    -print >&2 || true
  exit 2
fi

if [[ ! -d "$SRC/$APP_NAME" ]]; then
  echo "[ashan-sync] ERROR: Python package missing: $SRC/$APP_NAME" >&2
  exit 3
fi

echo "[ashan-sync] App root: $SRC"

SOURCE_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"

rm -rf "$TARGET"
mkdir -p "$TARGET"

cp -a "$SRC/." "$TARGET/"

rm -rf "$TARGET/.git"

printf '%s\n' "$SOURCE_SHA" \
  > "$TARGET/.ashan-source-commit"

echo "[ashan-sync] Synced ${APP_NAME}"
echo "[ashan-sync] Commit: ${SOURCE_SHA}"
echo "[ashan-sync] Target: ${TARGET}"

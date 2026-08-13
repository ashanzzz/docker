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

echo "[ashan-sync] Source: ${ASHAN_REPO_URL}"
echo "[ashan-sync] Ref   : ${ASHAN_REPO_REF}"

if [[ -n "$ASHAN_REPO_TOKEN" && "$ASHAN_REPO_URL" == https://github.com/* ]]; then
  auth="$(printf 'x-access-token:%s' "$ASHAN_REPO_TOKEN" | base64 -w 0 2>/dev/null || printf 'x-access-token:%s' "$ASHAN_REPO_TOKEN" | base64 | tr -d '\n')"
  git -c "http.extraheader=AUTHORIZATION: basic ${auth}" \
    clone --depth 1 --branch "$ASHAN_REPO_REF" "$ASHAN_REPO_URL" "$workdir/repo"
else
  git clone --depth 1 --branch "$ASHAN_REPO_REF" "$ASHAN_REPO_URL" "$workdir/repo"
fi

REPO_ROOT="$workdir/repo"

# Supported layouts:
# 1. Repository root itself is the Frappe app.
# 2. Repository is a workspace and the Frappe app is in /ashan_cn_procurement.
if [[ -f "$REPO_ROOT/pyproject.toml" || -f "$REPO_ROOT/setup.py" ]]; then
  SRC="$REPO_ROOT"
elif [[ -f "$REPO_ROOT/$APP_NAME/pyproject.toml" || -f "$REPO_ROOT/$APP_NAME/setup.py" ]]; then
  SRC="$REPO_ROOT/$APP_NAME"
else
  echo "[ashan-sync] ERROR: cannot locate Frappe app root for $APP_NAME" >&2
  find "$REPO_ROOT" -maxdepth 2 -type f \
    \( -name pyproject.toml -o -name setup.py \) \
    -print >&2 || true
  exit 2
fi

if [[ ! -d "$SRC/$APP_NAME" ]]; then
  echo "[ashan-sync] ERROR: Python package missing: $SRC/$APP_NAME" >&2
  exit 3
fi

if [[ ! -f "$SRC/$APP_NAME/hooks.py" ]]; then
  echo "[ashan-sync] ERROR: hooks.py missing: $SRC/$APP_NAME/hooks.py" >&2
  exit 4
fi

SOURCE_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"

echo "[ashan-sync] App root: $SRC"
echo "[ashan-sync] Commit  : $SOURCE_SHA"

rm -rf "$TARGET"
mkdir -p "$TARGET"
cp -a "$SRC/." "$TARGET/"
rm -rf "$TARGET/.git"

printf '%s\n' "$SOURCE_SHA" > "$TARGET/.ashan-source-commit"

echo "[ashan-sync] Synced ${APP_NAME}"
echo "[ashan-sync] Target: ${TARGET}"

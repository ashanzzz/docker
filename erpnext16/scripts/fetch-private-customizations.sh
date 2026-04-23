#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERP16_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

: "${PRIVATE_CUSTOM_REPO_URL:=https://github.com/ashanzzz/erpnext-private-customizations.git}"
: "${PRIVATE_CUSTOM_REPO_REF:=main}"
: "${PRIVATE_CUSTOM_REPO_TARGET_SUBDIR:=erpnext16/custom-apps}"
: "${PRIVATE_CUSTOM_REPO_TOKEN:=}"

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

clone_url="$PRIVATE_CUSTOM_REPO_URL"
if [[ -n "$PRIVATE_CUSTOM_REPO_TOKEN" && "$PRIVATE_CUSTOM_REPO_URL" == https://github.com/* ]]; then
  clone_url="${PRIVATE_CUSTOM_REPO_URL/https:\/\/github.com\//https:\/\/x-access-token:${PRIVATE_CUSTOM_REPO_TOKEN}@github.com\/}"
fi

echo "[custom-sync] Cloning ${PRIVATE_CUSTOM_REPO_URL} @ ${PRIVATE_CUSTOM_REPO_REF}"
git clone --depth 1 --branch "$PRIVATE_CUSTOM_REPO_REF" "$clone_url" "$workdir/repo" >/dev/null

src="$workdir/repo/$PRIVATE_CUSTOM_REPO_TARGET_SUBDIR"
dst="$ERP16_DIR/custom-apps"

if [[ ! -d "$src" ]]; then
  echo "[custom-sync] Missing source directory: $src" >&2
  exit 2
fi

rm -rf "$dst"
mkdir -p "$dst"
cp -a "$src/." "$dst/"

echo "[custom-sync] Synced custom apps into $dst"
find "$dst" -maxdepth 2 -mindepth 1 -type d | sort

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${IMAGE:=ghcr.io/ashanzzz/erpnext16}"
: "${TAG:=local}"
: "${FRAPPE_IMAGE_TAG:=version-16}"
: "${FRAPPE_BRANCH:=version-16}"
: "${FRAPPE_PATH:=https://github.com/frappe/frappe}"

for cmd in docker jq git base64; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $cmd" >&2
    exit 2
  }
done

"$ROOT/scripts/fetch-ashan-custom-app.sh"

VERSION="$(tr -d '\r\n' < "$ROOT/ERPNEXT_VERSION")"
APPS_JSON_BASE64="$(
  jq --arg ver "$VERSION" \
    'map(if (.url | endswith("/erpnext")) then .branch=$ver else . end)' \
    "$ROOT/apps.json" |
  (base64 -w 0 2>/dev/null || base64 | tr -d '\n')
)"

docker build \
  --pull \
  --build-arg "FRAPPE_IMAGE_TAG=$FRAPPE_IMAGE_TAG" \
  --build-arg "FRAPPE_BRANCH=$FRAPPE_BRANCH" \
  --build-arg "FRAPPE_PATH=$FRAPPE_PATH" \
  --build-arg "APPS_JSON_BASE64=$APPS_JSON_BASE64" \
  -f "$ROOT/single-aio/Containerfile" \
  -t "$IMAGE:$TAG" \
  "$ROOT"

echo "Built: $IMAGE:$TAG"

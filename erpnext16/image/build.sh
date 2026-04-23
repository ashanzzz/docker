#!/usr/bin/env bash
set -euo pipefail

# Build a custom ERPNext16 image (adds official apps from apps.json + bundled local custom apps)
# Based on frappe_docker layered Containerfile.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

: "${FRAPPE_IMAGE_TAG:=version-16}"
: "${FRAPPE_BRANCH:=version-16}"
: "${FRAPPE_PATH:=https://github.com/frappe/frappe}"

: "${IMAGE:=ghcr.io/ashanzzz/erpnext16}"
: "${TAG:=v16-custom}"

APPS_JSON_PATH="${APPS_JSON_PATH:-$DIR/apps.json}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 2; }; }
need docker
need base64

FETCH_SCRIPT="$DIR/../scripts/fetch-private-customizations.sh"
if [[ -f "$FETCH_SCRIPT" ]]; then
  bash "$FETCH_SCRIPT"
fi

if [[ ! -f "$APPS_JSON_PATH" ]]; then
  echo "ERROR: apps.json not found: $APPS_JSON_PATH" >&2
  exit 2
fi

APPS_JSON_BASE64="$(base64 -w 0 "$APPS_JSON_PATH" 2>/dev/null || base64 "$APPS_JSON_PATH" | tr -d '\n')"

echo "Building custom image: ${IMAGE}:${TAG}"
echo "FRAPPE_IMAGE_TAG=${FRAPPE_IMAGE_TAG}"
echo "FRAPPE_BRANCH=${FRAPPE_BRANCH}"
echo "APPS_JSON_PATH=${APPS_JSON_PATH}"

# Note: this builds from source using frappe/build + frappe/base.
# Build time can be significant.

docker build \
  --build-arg FRAPPE_IMAGE_TAG="$FRAPPE_IMAGE_TAG" \
  --build-arg FRAPPE_BRANCH="$FRAPPE_BRANCH" \
  --build-arg FRAPPE_PATH="$FRAPPE_PATH" \
  --build-arg APPS_JSON_BASE64="$APPS_JSON_BASE64" \
  -t "${IMAGE}:${TAG}" \
  -f "$DIR/Containerfile" \
  "$DIR/.."

echo "DONE: ${IMAGE}:${TAG}"

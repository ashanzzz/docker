#!/usr/bin/env sh
set -eu

# Ensure Recognize features are enabled (buildings/scenes/landmarks/etc.)
# This aligns with a "turn it on and forget it" setup.
#
# Safe behavior:
# - If Nextcloud isn't installed yet, do nothing.
# - If Recognize isn't installed/enabled, do nothing.
# - If values are already set, occ prints "Config value were not updated"; ignore.

OCC="/var/www/html/occ"

if [ ! -f "$OCC" ]; then
  exit 0
fi

# Only when NC is installed
if ! php -f "$OCC" status --output=json 2>/dev/null | grep -q '"installed"\s*:\s*true'; then
  exit 0
fi

# Only when Recognize app exists
if [ ! -d /var/www/html/custom_apps/recognize ] && [ ! -d /var/www/html/apps/recognize ]; then
  exit 0
fi

# Only when enabled
if ! php -f "$OCC" app:list --enabled 2>/dev/null | grep -qi '^\s*recognize\s*$'; then
  exit 0
fi

# Enable common classifiers
php -f "$OCC" config:app:set recognize faces.enabled --value=true >/dev/null 2>&1 || true
php -f "$OCC" config:app:set recognize imagenet.enabled --value=true >/dev/null 2>&1 || true
php -f "$OCC" config:app:set recognize landmarks.enabled --value=true >/dev/null 2>&1 || true
php -f "$OCC" config:app:set recognize movinet.enabled --value=true >/dev/null 2>&1 || true
php -f "$OCC" config:app:set recognize musicnn.enabled --value=true >/dev/null 2>&1 || true

# Leave clustering/classification to explicit admin action (can be heavy)

echo "[recognize] ensured classifiers enabled (faces/imagenet/landmarks/movinet/musicnn)" >&2

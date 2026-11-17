#!/usr/bin/env sh
set -eu

# Recognize: make the in-container classifier pipeline actually work.
#
# Why this hook exists:
# 1) Recognize only runs when `recognize node_binary` points at a usable node. The image
#    ships a glibc node at /usr/local/bin/node; Recognize's own download is a musl build
#    that cannot exec on Debian (see Dockerfile).
# 2) Classifier toggles default to false, so a freshly installed app classifies nothing:
#    zero detections, zero faces, empty queues.
#
# The previous revision detected the app with `app:list | grep '^\s*recognize\s*$'`, which
# never matches real output (`  - recognize: 13.2.0`) — the hook silently did nothing.
# It now parses `app:list --output=json`.

OCC="/var/www/html/occ"

[ -f "$OCC" ] || exit 0

# Only when Nextcloud is installed
if ! php -f "$OCC" status --output=json 2>/dev/null | grep -q '"installed"\s*:\s*true'; then
  exit 0
fi

# Only when the recognize app is present on disk
if [ ! -d /var/www/html/custom_apps/recognize ] && [ ! -d /var/www/html/apps/recognize ]; then
  exit 0
fi

# Only when enabled (JSON: {"enabled": {"recognize": "13.2.0", ...}})
if ! php -f "$OCC" app:list --output=json 2>/dev/null \
  | php -r 'exit(isset(json_decode(stream_get_contents(STDIN), true)["enabled"]["recognize"]) ? 0 : 1);'; then
  echo "[recognize] app not enabled; skipping" >&2
  exit 0
fi

occ() { php -f "$OCC" "$@" 2>/dev/null || true; }

# 1) Node runtime — point Recognize at the glibc build shipped in the image.
NODE="/usr/local/bin/node"
if [ -x "$NODE" ]; then
  CUR="$(occ config:app:get recognize node_binary | tr -d '\r\n')"
  if [ -z "$CUR" ] || [ "$CUR" = "node" ] || [ ! -x "$CUR" ]; then
    occ config:app:set recognize node_binary --value="$NODE" >/dev/null || true
    echo "[recognize] node_binary -> $NODE" >&2
  fi
fi

# 2) Classifiers — on by default, but never fight an explicit admin choice.
set_default() {
  key="$1"; value="$2"; cur="$3"
  if [ -z "$cur" ] || [ "$cur" = "false" ]; then
    occ config:app:set recognize "$key" --value="$value" >/dev/null || true
  fi
}
set_default faces.enabled true "$(occ config:app:get recognize faces.enabled | tr -d '\r\n')"
set_default imagenet.enabled true "$(occ config:app:get recognize imagenet.enabled | tr -d '\r\n')"
set_default landmarks.enabled true "$(occ config:app:get recognize landmarks.enabled | tr -d '\r\n')"
set_default movinet.enabled true "$(occ config:app:get recognize movinet.enabled | tr -d '\r\n')"
set_default musicnn.enabled true "$(occ config:app:get recognize musicnn.enabled | tr -d '\r\n')"

# 3) Batch sizes — stay gentle on shared hardware; classification runs via cron.
set_default faces.batchSize 100 "$(occ config:app:get recognize faces.batchSize | tr -d '\r\n')"
set_default imagenet.batchSize 50 "$(occ config:app:get recognize imagenet.batchSize | tr -d '\r\n')"
set_default landmarks.batchSize 50 "$(occ config:app:get recognize landmarks.batchSize | tr -d '\r\n')"
set_default movinet.batchSize 10 "$(occ config:app:get recognize movinet.batchSize | tr -d '\r\n')"
set_default musicnn.batchSize 50 "$(occ config:app:get recognize musicnn.batchSize | tr -d '\r\n')"

# Clustering (Photos "People") and a full sweep stay explicit admin actions:
#   occ recognize:classify   /   occ recognize:cluster-faces
echo "[recognize] node_binary + classifiers ensured" >&2

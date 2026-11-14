#!/usr/bin/env sh
set -eu

# Recognize 11.x protects its DAV collection with a custom header `X-Recognize-Api-Key`.
# In some deployments, Nextcloud Photos does not send this header when requesting
# /remote.php/dav/recognize/<user>/faces/, resulting in 403 and empty faces list.
#
# This hook patches Recognize in-place (when installed) to allow standard DAV auth
# (session/basic) when the header is missing. It keeps the original behavior when
# the header is present.
#
# NOTE: This is a pragmatic compatibility patch. Upgrading the Recognize app may
# overwrite the file; this hook will re-apply at next container start.

F="/var/www/html/custom_apps/recognize/lib/Dav/Faces/PropFindPlugin.php"

if [ ! -f "$F" ]; then
  exit 0
fi

# Skip if already patched
if grep -q "Fallback: allow standard DAV auth" "$F" 2>/dev/null; then
  exit 0
fi

# Only patch if the expected header check exists
if ! grep -q "X-Recognize-Api-Key" "$F" 2>/dev/null; then
  exit 0
fi

TS="$(date +%Y%m%d-%H%M%S)"
cp -a "$F" "${F}.bak.${TS}" 2>/dev/null || true

# Patch: replace the throw in the `$key === null` block with a comment + return.
# We do it with awk to avoid fragile sed multi-line quoting.
awk '
  BEGIN { patched=0; seen_header=0; in_null_if=0 }
  {
    if (!patched && $0 ~ /getHeader/ && $0 ~ /X-Recognize-Api-Key/) {
      seen_header=1
    }

    if (seen_header && !patched && $0 ~ /if \(\$key === null\)/) {
      in_null_if=1
    }

    if (in_null_if && !patched && $0 ~ /throw new Forbidden/ && $0 ~ /X-Recognize-Api-Key/) {
      print "\t\t\t// Fallback: allow standard DAV auth (session/basic) when header is missing"
      print "\t\t\treturn;"
      patched=1
      next
    }

    print

    if (in_null_if && $0 ~ /^\t\t}\s*$/) {
      in_null_if=0
      seen_header=0
    }
  }
  END { }
' "$F" > "${F}.tmp" && mv "${F}.tmp" "$F"

# best-effort: keep file readable by Nextcloud
chown www-data:www-data "$F" 2>/dev/null || true
chmod 0640 "$F" 2>/dev/null || true

echo "[recognize] patched DAV API key requirement for Photos faces compatibility" >&2

#!/usr/bin/env sh
set -eu

# Nextcloud 33 removed QueryBuilder::execute() in favor of executeQuery()/executeStatement().
# Some versions of the Maps app still call $qb->execute(), causing "Call to undefined method ...::execute()"
# and breaking Maps contacts loading.
#
# This hook patches the Maps app in-place to be compatible with NC33.
# It only rewrites lines of the form: $req = $qb->execute();
# based on whether the current builder chain is a SELECT or a statement.

patch_maps_file() {
  f="$1"
  [ -f "$f" ] || return 0

  # Already patched?
  if grep -q "->executeQuery()" "$f" 2>/dev/null || grep -q "->executeStatement()" "$f" 2>/dev/null; then
    # still patch missing ones, but avoid doing work if no legacy execute remains
    if ! grep -q "\$qb->execute()" "$f" 2>/dev/null; then
      return 0
    fi
  fi

  tmp="${f}.tmp"

  awk '
    BEGIN { mode="" }
    {
      line=$0

      # reset mode when a new query builder is created
      if (line ~ /getQueryBuilder\(\)/) { mode="" }

      # detect query type by chained builder calls
      if (line ~ /\$qb->select\b/ || line ~ /->select\(/) { mode="select" }
      if (line ~ /->update\(/ || line ~ /->insert\(/ || line ~ /->delete\(/) { mode="stmt" }

      # rewrite the legacy call
      if (line ~ /\$req[[:space:]]*=[[:space:]]*\$qb->execute\(\);/) {
        if (mode == "select") {
          sub(/\$qb->execute\(\)/, "\$qb->executeQuery()", line)
        } else if (mode == "stmt") {
          sub(/\$qb->execute\(\)/, "\$qb->executeStatement()", line)
        }
      }

      print line
    }
  ' "$f" > "$tmp" && mv "$tmp" "$f"

  chown www-data:www-data "$f" 2>/dev/null || true
  chmod 0640 "$f" 2>/dev/null || true
}

# Only patch if Maps app exists
if [ -d /var/www/html/custom_apps/maps ]; then
  patch_maps_file /var/www/html/custom_apps/maps/lib/Service/AddressService.php
  patch_maps_file /var/www/html/custom_apps/maps/lib/Controller/ContactsController.php
  patch_maps_file /var/www/html/custom_apps/maps/lib/Service/DevicesService.php
  echo "[maps] patched QueryBuilder::execute() calls for NC33 compatibility" >&2
fi

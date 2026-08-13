#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERP16_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

: "${ASHAN_REPO_URL:=https://github.com/ashanzzz/erpnext-private-customizations.git}"
: "${ASHAN_REPO_REF:=main}"
: "${ASHAN_REPO_TOKEN:=}"

APP="ashan_cn_procurement"
TARGET="$ERP16_DIR/custom-apps/$APP"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[ashan-sync] repo: $ASHAN_REPO_URL"
echo "[ashan-sync] ref : $ASHAN_REPO_REF"

if [[ -n "$ASHAN_REPO_TOKEN" && "$ASHAN_REPO_URL" == https://github.com/* ]]; then
  AUTH="$(
    printf 'x-access-token:%s' "$ASHAN_REPO_TOKEN" |
    (base64 -w 0 2>/dev/null || base64 | tr -d '\n')
  )"

  git -c "http.extraheader=AUTHORIZATION: basic ${AUTH}" \
    clone --depth 1 --branch "$ASHAN_REPO_REF" "$ASHAN_REPO_URL" "$TMP/repo"
else
  git clone --depth 1 --branch "$ASHAN_REPO_REF" "$ASHAN_REPO_URL" "$TMP/repo"
fi

REPO="$TMP/repo"

if [[ -f "$REPO/pyproject.toml" && -d "$REPO/$APP" ]]; then
  SRC="$REPO"
elif [[ -f "$REPO/$APP/pyproject.toml" && -d "$REPO/$APP/$APP" ]]; then
  SRC="$REPO/$APP"
else
  echo "[ashan-sync] ERROR: cannot locate Frappe app root." >&2
  find "$REPO" -maxdepth 2 -type f -name pyproject.toml -print >&2 || true
  exit 2
fi

test -f "$SRC/pyproject.toml"
test -f "$SRC/$APP/hooks.py"

SHA="$(git -C "$REPO" rev-parse HEAD)"

rm -rf "$TARGET"
mkdir -p "$TARGET"
cp -a "$SRC/." "$TARGET/"
rm -rf "$TARGET/.git"

printf '%s\n' "$SHA" > "$TARGET/.ashan-source-commit"

echo "[ashan-sync] app root: $SRC"
echo "[ashan-sync] commit  : $SHA"

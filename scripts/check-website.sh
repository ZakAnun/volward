#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/apps/website/dist"
SITE_URL="${SITE_URL:-http://localhost:4321}"

case "$SITE_URL" in
  */) ;;
  *) SITE_URL="$SITE_URL/" ;;
esac

if [ ! -f "$DIST/index.html" ] || [ ! -f "$DIST/zh/index.html" ]; then
  "$ROOT/scripts/website_build.sh"
fi

assert_contains() {
  local file="$1"
  local needle="$2"

  if ! grep -Fq "$needle" "$file"; then
    printf 'Missing expected content in %s: %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

assert_route() {
  local route="$1"
  local lang="$2"
  local canonical="$3"
  local alternate_lang="$4"
  local alternate_href="$5"
  local file="$DIST/$route"

  if [ ! -f "$file" ]; then
    printf 'Missing expected route: %s\n' "$file" >&2
    exit 1
  fi

  assert_contains "$file" '<!DOCTYPE html>'
  assert_contains "$file" "<html lang=\"$lang\">"
  assert_contains "$file" "<link rel=\"canonical\" href=\"$canonical\""
  assert_contains "$file" "<link rel=\"alternate\" hreflang=\"$lang\" href=\"$canonical\""
  assert_contains "$file" "<link rel=\"alternate\" hreflang=\"$alternate_lang\" href=\"$alternate_href\""
  assert_contains "$file" '<meta name="description"'
  assert_contains "$file" '<meta property="og:title"'
  assert_contains "$file" '<meta property="og:description"'
  assert_contains "$file" '<meta property="og:url"'
  assert_contains "$file" '<meta property="og:image"'
  assert_contains "$file" 'image/svg+xml'
  assert_contains "$file" '<meta name="twitter:card" content="summary_large_image"'
  assert_contains "$file" '<meta name="twitter:title"'
  assert_contains "$file" '<meta name="twitter:description"'
  assert_contains "$file" '<meta name="twitter:image"'
  assert_contains "$file" '<meta name="twitter:image:alt"'
  assert_contains "$file" '/og/volward-share.svg'
  assert_contains "$file" '<link rel="alternate" hreflang="x-default"'
}

assert_route "index.html" "en" "${SITE_URL}" "zh" "${SITE_URL}zh/"
assert_route "zh/index.html" "zh" "${SITE_URL}zh/" "en" "${SITE_URL}"

exit 0

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_TEAM_FILE="$ROOT_DIR/Runner/Configs/TeamSettings.local.xcconfig"
EXAMPLE_TEAM_FILE="$ROOT_DIR/Runner/Configs/TeamSettings.local.xcconfig.example"
APP_PATH="${1:-}"

if [[ ! -f "$LOCAL_TEAM_FILE" ]]; then
  echo "error: missing $LOCAL_TEAM_FILE" >&2
  echo "Copy $EXAMPLE_TEAM_FILE to TeamSettings.local.xcconfig and set DEVELOPMENT_TEAM." >&2
  exit 1
fi

if ! grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}[[:space:]]*$' "$LOCAL_TEAM_FILE"; then
  echo "error: DEVELOPMENT_TEAM is missing or invalid in $LOCAL_TEAM_FILE" >&2
  echo "Expected a 10-character Apple Team ID, e.g. DEVELOPMENT_TEAM = ABCD123456" >&2
  exit 1
fi

echo "ok: TeamSettings.local.xcconfig present with DEVELOPMENT_TEAM"

if [[ -z "$APP_PATH" ]]; then
  exit 0
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app not found: $APP_PATH" >&2
  exit 1
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

echo "== codesign -dv --verbose=2 =="
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | tee "$TMP_FILE"

if grep -Eq 'Signature=adhoc|Authority=\(ad hoc\)' "$TMP_FILE"; then
  echo "error: built app is still ad-hoc signed" >&2
  exit 1
fi

if ! grep -q 'Identifier=com.volward.volward' "$TMP_FILE"; then
  echo "error: unexpected bundle identifier on signed app" >&2
  exit 1
fi

echo "ok: Debug signing looks stable (non-adhoc, com.volward.volward)"

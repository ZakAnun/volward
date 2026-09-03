#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/../.." && pwd)"
MACOS_DIR="$APP_DIR/macos"
VERIFY_SCRIPT="$MACOS_DIR/scripts/verify_debug_signing.sh"
APP_PATH="$APP_DIR/build/macos/Build/Products/Debug/volward.app"
SETUP_SCRIPT="$REPO_ROOT/scripts/setup_macos.sh"

# 1) Config gate only — do not require an already-signed .app yet.
if ! "$VERIFY_SCRIPT"; then
  echo "hint: first-time machine? from repo root run: bash scripts/setup_macos.sh" >&2
  echo "      (script path: $SETUP_SCRIPT)" >&2
  exit 1
fi

# 2) Rebuild native dylib (may copy into an existing .app if present).
(
  cd "$MACOS_DIR"
  bash build_rust.sh
)

# 3) Stale ad-hoc Debug apps block progress: they were often built before
#    TeamSettings.local.xcconfig existed. Remove them so Flutter rebuilds
#    with Automatic Apple Development signing.
if [[ -d "$APP_PATH" ]]; then
  SIGN_INFO="$(mktemp)"
  if codesign -dv --verbose=2 "$APP_PATH" >"$SIGN_INFO" 2>&1 \
    && grep -Eq 'Signature=adhoc|Authority=\(ad hoc\)' "$SIGN_INFO"; then
    echo "note: existing Debug app is ad-hoc signed (likely built before DEVELOPMENT_TEAM was set)." >&2
    echo "      Removing it so Flutter can rebuild with Apple Development signing:" >&2
    echo "      $APP_PATH" >&2
    rm -rf "$APP_PATH"
  else
    # Optional soft check; ignore failures here — flutter run will resign.
    "$VERIFY_SCRIPT" "$APP_PATH" || {
      echo "note: pre-existing Debug app signing check failed; continuing to flutter run for a fresh signed build." >&2
    }
  fi
  rm -f "$SIGN_INFO"
else
  echo "note: no Debug app yet; Flutter will create a signed build."
fi

cd "$APP_DIR"

# Inject Aptabase defines when env / local aptabase.json is present.
# Missing config → Analytics stays on Noop (same contract as Linux/Windows debug).
# shellcheck source=resolve_aptabase_defines.sh
source "$SCRIPT_DIR/resolve_aptabase_defines.sh"
resolve_aptabase_defines

VOLWARD_API_BASE="${VOLWARD_API_BASE:-https://api.volwardapp.com/v1}"
PLATFORM_API_DEFINE=(--dart-define="VOLWARD_API_BASE=$VOLWARD_API_BASE")

fvm flutter run -d macos \
  "${APTABASE_DEFINE_ARGS[@]}" \
  "${PLATFORM_API_DEFINE[@]}" \
  "$@"

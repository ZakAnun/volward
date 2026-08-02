#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/../.." && pwd)"
MACOS_DIR="$APP_DIR/macos"
VERIFY_SCRIPT="$MACOS_DIR/scripts/verify_debug_signing.sh"
APP_PATH="$APP_DIR/build/macos/Build/Products/Debug/volward.app"
SETUP_SCRIPT="$REPO_ROOT/scripts/setup_macos.sh"

if ! "$VERIFY_SCRIPT"; then
  echo "hint: first-time machine? from repo root run: bash scripts/setup_macos.sh" >&2
  echo "      (script path: $SETUP_SCRIPT)" >&2
  exit 1
fi

(
  cd "$MACOS_DIR"
  bash build_rust.sh
)

if [[ -d "$APP_PATH" ]]; then
  "$VERIFY_SCRIPT" "$APP_PATH"
else
  echo "note: skipping built app verification because $APP_PATH does not exist yet."
fi

cd "$APP_DIR"
fvm flutter run -d macos "$@"

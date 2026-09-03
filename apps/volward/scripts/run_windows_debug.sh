#!/usr/bin/env bash
# Git Bash / MSYS2 entrypoint for Windows debug runs with Aptabase defines.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/../.." && pwd)"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *)
    echo "❌ run_windows_debug.sh must be run on Windows (Git Bash / MSYS2)" >&2
    exit 1
    ;;
esac

echo "🦀 Building Rust DLL..."
(
  cd "$REPO_ROOT"
  cargo build -p volward-facade
  mkdir -p "$APP_DIR/windows"
  cp -f "$REPO_ROOT/target/debug/volward_facade.dll" "$APP_DIR/windows/volward_facade.dll"
)

# shellcheck source=resolve_aptabase_defines.sh
source "$SCRIPT_DIR/resolve_aptabase_defines.sh"
resolve_aptabase_defines

VOLWARD_API_BASE="${VOLWARD_API_BASE:-https://api.volwardapp.com/v1}"
PLATFORM_API_DEFINE=(--dart-define="VOLWARD_API_BASE=$VOLWARD_API_BASE")

cd "$APP_DIR"
if command -v fvm >/dev/null 2>&1; then
  fvm flutter run -d windows \
    "${APTABASE_DEFINE_ARGS[@]}" \
    "${PLATFORM_API_DEFINE[@]}" \
    "$@"
else
  flutter run -d windows \
    "${APTABASE_DEFINE_ARGS[@]}" \
    "${PLATFORM_API_DEFINE[@]}" \
    "$@"
fi

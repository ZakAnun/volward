#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/../.." && pwd)"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "❌ run_linux_debug.sh must be run on a Linux host" >&2
  exit 1
fi

echo "🦀 Building Rust shared library..."
(
  cd "$REPO_ROOT"
  cargo build -p volward-facade
)

# shellcheck source=resolve_aptabase_defines.sh
source "$SCRIPT_DIR/resolve_aptabase_defines.sh"
resolve_aptabase_defines

cd "$APP_DIR"
if command -v fvm >/dev/null 2>&1; then
  fvm flutter run -d linux "${APTABASE_DEFINE_ARGS[@]}" "$@"
else
  flutter run -d linux "${APTABASE_DEFINE_ARGS[@]}" "$@"
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/apps/website/dist"

if [ ! -f "$DIST/index.html" ]; then
  "$ROOT/scripts/website_build.sh"
fi

python3 -m http.server 8080 --directory "$DIST"

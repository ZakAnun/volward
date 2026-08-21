#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/apps/website"
source "$ROOT/apps/website/scripts/resolve_aptabase_web.sh"
resolve_aptabase_web "${1:-}"
pnpm build

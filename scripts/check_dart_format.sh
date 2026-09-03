#!/usr/bin/env bash
# Same gate as CI: Flutter tests → Verify formatting.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root/apps/volward"

if command -v fvm >/dev/null 2>&1; then
  exec fvm dart format --output=none --set-exit-if-changed .
fi
exec dart format --output=none --set-exit-if-changed .

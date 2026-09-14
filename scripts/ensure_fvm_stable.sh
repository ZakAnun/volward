#!/usr/bin/env bash
# Align apps/volward with FVM Flutter stable (idempotent). No-op when fvm is absent.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$root/apps/volward"

if ! command -v fvm >/dev/null 2>&1; then
  exit 0
fi

(
  cd "$app_dir"
  fvm install stable
  fvm use stable --force --skip-setup
)

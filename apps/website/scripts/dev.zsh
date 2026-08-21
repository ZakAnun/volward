#!/usr/bin/env zsh
set -euo pipefail

incoming_site_url="${SITE_URL:-}"
incoming_aptabase_host="${APTABASE_HOST:-}"
incoming_aptabase_web_key="${APTABASE_WEB_KEY:-}"

if [[ -n "$incoming_site_url" ]]; then
  export SITE_URL="$incoming_site_url"
fi

if [[ -n "$incoming_aptabase_host" ]]; then
  export APTABASE_HOST="$incoming_aptabase_host"
fi

if [[ -n "$incoming_aptabase_web_key" ]]; then
  export APTABASE_WEB_KEY="$incoming_aptabase_web_key"
fi

export SITE_URL="${SITE_URL:-http://localhost:4321}"
export APTABASE_HOST="${APTABASE_HOST:-https://analytics.volwardapp.com}"

# shellcheck source=resolve_aptabase_web.sh
source "$(cd "$(dirname "$0")" && pwd)/resolve_aptabase_web.sh"
resolve_aptabase_web

if [[ "${1:-}" == "--" ]]; then
  shift
fi

exec pnpm exec astro dev "$@"

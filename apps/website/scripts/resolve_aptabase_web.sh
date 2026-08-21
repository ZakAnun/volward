#!/usr/bin/env bash

# Resolve Aptabase config for website builds.
#
# Usage:
#   source "$(dirname "$0")/resolve_aptabase_web.sh"
#   resolve_aptabase_web            # optional for dev/local builds
#   resolve_aptabase_web --require  # fail if missing (release builds)
#
# Priority: env APTABASE_WEB_KEY + APTABASE_HOST -> apps/website/aptabase.json

resolve_aptabase_web() {
  local require=0
  if [[ "${1:-}" == "--require" ]]; then
    require=1
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local app_dir
  app_dir="$(cd "$script_dir/.." && pwd)"

  local key="${APTABASE_WEB_KEY:-}"
  local host="${APTABASE_HOST:-}"
  local json="$app_dir/aptabase.json"

  if [[ -n "$key" || -n "$host" ]]; then
    if [[ -z "$key" || -z "$host" ]]; then
      echo "❌ Aptabase: set both APTABASE_WEB_KEY and APTABASE_HOST (one is missing)" >&2
      return 1
    fi
    export APTABASE_WEB_KEY="$key"
    export APTABASE_HOST="$host"
    echo "📊 Aptabase: using env APTABASE_WEB_KEY / APTABASE_HOST"
    return 0
  fi

  if [[ -f "$json" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      local parsed
      parsed="$(
        python3 - "$json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
key = (data.get("APTABASE_WEB_KEY") or "").strip()
host = (data.get("APTABASE_HOST") or "").strip()
print(f"{key}\t{host}")
PY
      )"
      local file_key
      local file_host
      IFS=$'\t' read -r file_key file_host <<<"$parsed"
      if [[ -z "$file_key" ]]; then
        echo "❌ Aptabase: $json has empty APTABASE_WEB_KEY" >&2
        echo "   Copy from aptabase.json.example and fill the key, or export APTABASE_WEB_KEY/HOST." >&2
        return 1
      fi
      export APTABASE_WEB_KEY="$file_key"
      export APTABASE_HOST="${file_host:-https://analytics.volwardapp.com}"
      echo "📊 Aptabase: using $json"
      return 0
    fi

    echo "❌ Aptabase: python3 is required to read $json" >&2
    return 1
  fi

  if [[ "$require" -eq 1 ]]; then
    echo "❌ Aptabase: required for this build, but neither env nor aptabase.json is configured" >&2
    echo "   Export APTABASE_WEB_KEY + APTABASE_HOST, or create apps/website/aptabase.json" >&2
    echo "   (see apps/website/aptabase.json.example)." >&2
    return 1
  fi

  echo "⚠️  Aptabase: no env defines and no aptabase.json — Analytics stays Noop" >&2
  return 0
}

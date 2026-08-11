#!/usr/bin/env bash
# Resolve Aptabase compile-time defines for flutter run/build.
#
# Usage (from any script):
#   # shellcheck source=resolve_aptabase_defines.sh
#   source "$(dirname "$0")/resolve_aptabase_defines.sh"
#   resolve_aptabase_defines            # optional for debug
#   resolve_aptabase_defines --require  # fail if missing (release)
#
# Sets: APTABASE_DEFINE_ARGS (bash array of --dart-define* flags)
# Priority: env APTABASE_APP_KEY + APTABASE_HOST → apps/volward/aptabase.json

resolve_aptabase_defines() {
  local require=0
  if [[ "${1:-}" == "--require" ]]; then
    require=1
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local app_dir
  app_dir="$(cd "$script_dir/.." && pwd)"

  local key="${APTABASE_APP_KEY:-}"
  local host="${APTABASE_HOST:-}"
  local json="$app_dir/aptabase.json"

  APTABASE_DEFINE_ARGS=()

  if [[ -n "$key" || -n "$host" ]]; then
    if [[ -z "$key" || -z "$host" ]]; then
      echo "❌ Aptabase: set both APTABASE_APP_KEY and APTABASE_HOST (one is missing)" >&2
      return 1
    fi
    APTABASE_DEFINE_ARGS=(
      --dart-define="APTABASE_APP_KEY=$key"
      --dart-define="APTABASE_HOST=$host"
    )
    echo "📊 Aptabase: using env APTABASE_APP_KEY / APTABASE_HOST"
    return 0
  fi

  if [[ -f "$json" ]]; then
    # Reject empty key in the local file so we don't ship a silent Noop by mistake.
    if command -v python3 >/dev/null 2>&1; then
      local file_key
      file_key="$(
        python3 - "$json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print((data.get("APTABASE_APP_KEY") or "").strip())
PY
      )"
      if [[ -z "$file_key" ]]; then
        echo "❌ Aptabase: $json has empty APTABASE_APP_KEY" >&2
        echo "   Copy from aptabase.json.example and fill the key, or export APTABASE_APP_KEY/HOST." >&2
        return 1
      fi
    fi
    APTABASE_DEFINE_ARGS=(--dart-define-from-file="$json")
    echo "📊 Aptabase: using $json"
    return 0
  fi

  if [[ "$require" -eq 1 ]]; then
    echo "❌ Aptabase: required for this build, but neither env nor aptabase.json is configured" >&2
    echo "   Export APTABASE_APP_KEY + APTABASE_HOST, or create apps/volward/aptabase.json" >&2
    echo "   (see apps/volward/aptabase.json.example)." >&2
    return 1
  fi

  echo "⚠️  Aptabase: no env defines and no aptabase.json — Analytics stays Noop" >&2
  return 0
}

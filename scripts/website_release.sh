#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$ROOT/apps/website"
DIST="$WEB_DIR/dist"

source "$WEB_DIR/scripts/resolve_aptabase_web.sh"
resolve_aptabase_web --require

cd "$WEB_DIR"
pnpm install --frozen-lockfile
pnpm build

if [[ -n "${DEPLOY_HOST:-}" || -n "${DEPLOY_USER:-}" || -n "${DEPLOY_PATH:-}" || -n "${DEPLOY_KEY:-}" ]]; then
  if [[ -z "${DEPLOY_HOST:-}" || -z "${DEPLOY_USER:-}" || -z "${DEPLOY_PATH:-}" ]]; then
    echo "❌ Deploy requires DEPLOY_HOST, DEPLOY_USER, and DEPLOY_PATH" >&2
    exit 1
  fi

  ssh_port="${DEPLOY_PORT:-22}"
  ssh_key_file="$(mktemp)"
  cleanup() {
    rm -f "$ssh_key_file"
  }
  trap cleanup EXIT

  if [[ -n "${DEPLOY_KEY:-}" ]]; then
    printf '%s\n' "$DEPLOY_KEY" > "$ssh_key_file"
    chmod 600 "$ssh_key_file"
    ssh_opts=(-i "$ssh_key_file")
  else
    ssh_opts=()
  fi

  rsync -az --delete \
    -e "ssh ${ssh_opts[*]} -p $ssh_port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
    "$DIST/" \
    "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/"

  echo "✅ Website deployed to ${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}"
else
  echo "✅ Website build complete: $DIST"
fi

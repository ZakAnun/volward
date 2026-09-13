#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_DIR="$ROOT/server/deploy"

require_nonempty() {
  local name="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "Missing required platform deploy config: $name" >&2
    exit 1
  fi
}

if [[ -z "${PLATFORM_DEPLOY_HOST:-${DEPLOY_HOST:-}}" ]]; then
  if [[ "${PLATFORM_DEPLOY_REQUIRED:-}" == "1" ]]; then
    echo "error: DEPLOY_HOST is required for this release but is unset." >&2
    exit 1
  fi
  echo "DEPLOY_HOST is unset; skipping platform API deployment."
  exit 0
fi

assert_refresh_smoke_body() {
  local label="$1"
  local status="$2"
  local body="$3"
  if [[ "$status" != "404" ]]; then
    echo "Platform API refresh smoke ($label) expected HTTP 404, got $status: $body" >&2
    return 1
  fi
  if [[ "$body" != *'"error":"not_found"'* && "$body" != *'"error": "not_found"'* ]]; then
    echo "Platform API refresh smoke ($label) missing not_found error: $body" >&2
    return 1
  fi
  if [[ "$body" != *'device_not_found'* ]]; then
    echo "Platform API refresh smoke ($label) missing device_not_found message: $body" >&2
    return 1
  fi
  echo "Platform API refresh smoke passed ($label)."
}

verify_refresh_route() {
  local base_url="$1"
  local label="$2"
  local tmp status body
  tmp="$(mktemp)"
  status="$(
    curl -sS -o "$tmp" -w '%{http_code}' \
      -X POST "${base_url%/}/v1/auth/refresh" \
      -H 'Content-Type: application/json' \
      -d '{"device_uuid":"volward-ci-smoke-unknown-device"}'
  )"
  body="$(cat "$tmp")"
  rm -f "$tmp"
  assert_refresh_smoke_body "$label" "$status" "$body"
}

deploy_host="${PLATFORM_DEPLOY_HOST:-${DEPLOY_HOST}}"
deploy_port="${PLATFORM_DEPLOY_PORT:-${DEPLOY_PORT:-22}}"
deploy_user="${PLATFORM_DEPLOY_USER:-}"
deploy_key="${PLATFORM_DEPLOY_KEY:-}"

require_nonempty PLATFORM_DEPLOY_USER "$deploy_user"
require_nonempty PLATFORM_DEPLOY_KEY "$deploy_key"
require_nonempty PLATFORM_IMAGE "${PLATFORM_IMAGE:-}"
require_nonempty PLATFORM_JWT_SECRET "${PLATFORM_JWT_SECRET:-}"
require_nonempty PLATFORM_DEEPSEEK_API_KEY "${PLATFORM_DEEPSEEK_API_KEY:-}"
require_nonempty PLATFORM_RESEND_API_KEY "${PLATFORM_RESEND_API_KEY:-}"
require_nonempty PLATFORM_RESEND_FROM "${PLATFORM_RESEND_FROM:-}"
require_nonempty PLATFORM_PADDLE_API_KEY "${PLATFORM_PADDLE_API_KEY:-}"
require_nonempty PLATFORM_PADDLE_WEBHOOK_SECRET "${PLATFORM_PADDLE_WEBHOOK_SECRET:-}"

paddle_env="${PLATFORM_PADDLE_ENV:-live}"
case "$paddle_env" in
  sandbox | live) ;;
  *)
    echo "Invalid PLATFORM_PADDLE_ENV: $paddle_env (expected sandbox or live)" >&2
    exit 1
    ;;
esac

platform_image="$(printf '%s' "$PLATFORM_IMAGE" | tr '[:upper:]' '[:lower:]')"

ssh_port="$deploy_port"
ssh_key_file="$(mktemp)"
env_file="$(mktemp)"
cleanup() {
  rm -f "$ssh_key_file" "$env_file"
}
trap cleanup EXIT

printf '%s\n' "$deploy_key" >"$ssh_key_file"
chmod 600 "$ssh_key_file"

ssh_common_opts=(
  -i "$ssh_key_file"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o IdentitiesOnly=yes
)
ssh_cmd=(ssh "${ssh_common_opts[@]}" -p "$ssh_port")
scp_cmd=(scp "${ssh_common_opts[@]}" -P "$ssh_port")

remote="${deploy_user}@${deploy_host}"

cat >"$env_file" <<EOF
VOLWARD_PLATFORM_IMAGE=${platform_image}
JWT_SECRET=${PLATFORM_JWT_SECRET}
DEEPSEEK_API_KEY=${PLATFORM_DEEPSEEK_API_KEY}
RESEND_API_KEY=${PLATFORM_RESEND_API_KEY}
RESEND_FROM=${PLATFORM_RESEND_FROM}
PADDLE_API_KEY=${PLATFORM_PADDLE_API_KEY}
PADDLE_WEBHOOK_SECRET=${PLATFORM_PADDLE_WEBHOOK_SECRET}
PADDLE_ENV=${paddle_env}
EOF

"${scp_cmd[@]}" \
  "$DEPLOY_DIR/docker-compose.extend.yml" \
  "$DEPLOY_DIR/deploy.sh" \
  "$DEPLOY_DIR/backup.sh" \
  "${remote}:/tmp/"
"${scp_cmd[@]}" "$env_file" "${remote}:/tmp/volward-platform.env"

"${ssh_cmd[@]}" "$remote" bash -s <<'REMOTE'
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

$SUDO install -d -m 755 /etc/volward /opt/volward /opt/backups
$SUDO install -m 644 /tmp/docker-compose.extend.yml /etc/volward/docker-compose.extend.yml
$SUDO install -m 755 /tmp/deploy.sh /usr/local/sbin/volward-platform-deploy
$SUDO install -m 755 /tmp/backup.sh /usr/local/sbin/volward-platform-backup
$SUDO install -m 600 /tmp/volward-platform.env /opt/volward/.env
$SUDO chown root:root /opt/volward/.env
rm -f /tmp/docker-compose.extend.yml /tmp/deploy.sh /tmp/backup.sh /tmp/volward-platform.env
REMOTE

if [[ -n "${PLATFORM_GHCR_READ_TOKEN:-}" ]]; then
  ghcr_user="${PLATFORM_GHCR_USER:-${GITHUB_REPOSITORY_OWNER:-}}"
  if [[ -z "$ghcr_user" ]]; then
    echo "PLATFORM_GHCR_READ_TOKEN is set but GHCR username is missing." >&2
    exit 1
  fi
  printf '%s' "$PLATFORM_GHCR_READ_TOKEN" | "${ssh_cmd[@]}" "$remote" \
    docker login ghcr.io -u "$ghcr_user" --password-stdin
fi

"${ssh_cmd[@]}" "$remote" bash -s <<'REMOTE'
set -euo pipefail
if [[ "$(id -u)" -eq 0 ]]; then
  /usr/local/sbin/volward-platform-deploy
else
  sudo /usr/local/sbin/volward-platform-deploy
fi
REMOTE

if [[ -z "${PLATFORM_HEALTHCHECK_URL:-}" && -n "${VOLWARD_API_BASE:-}" ]]; then
  case "$VOLWARD_API_BASE" in
    */v1) PLATFORM_HEALTHCHECK_URL="${VOLWARD_API_BASE%/v1}/health" ;;
  esac
fi

health_body="$("${ssh_cmd[@]}" "$remote" "curl -fsS http://127.0.0.1:8080/health")"
if [[ "$health_body" != *'"ok":true'* ]]; then
  echo "Platform API local health check failed: $health_body" >&2
  exit 1
fi
echo "Platform API local health check passed."

"${ssh_cmd[@]}" "$remote" bash -s <<'REMOTE'
set -euo pipefail
tmp="$(mktemp)"
status="$(
  curl -sS -o "$tmp" -w '%{http_code}' \
    -X POST 'http://127.0.0.1:8080/v1/auth/refresh' \
    -H 'Content-Type: application/json' \
    -d '{"device_uuid":"volward-ci-smoke-unknown-device"}'
)"
body="$(cat "$tmp")"
rm -f "$tmp"
if [[ "$status" != "404" ]]; then
  echo "Platform API refresh smoke (local) expected HTTP 404, got $status: $body" >&2
  exit 1
fi
if [[ "$body" != *'"error":"not_found"'* && "$body" != *'"error": "not_found"'* ]]; then
  echo "Platform API refresh smoke (local) missing not_found error: $body" >&2
  exit 1
fi
if [[ "$body" != *'device_not_found'* ]]; then
  echo "Platform API refresh smoke (local) missing device_not_found message: $body" >&2
  exit 1
fi
echo "Platform API refresh smoke passed (local)."
REMOTE

if [[ -n "${PLATFORM_HEALTHCHECK_URL:-}" ]]; then
  public_body="$(curl -fsS "$PLATFORM_HEALTHCHECK_URL")"
  if [[ "$public_body" != *'"ok":true'* ]]; then
    echo "Platform API public health check failed: $public_body" >&2
    exit 1
  fi
  echo "Platform API public health check passed: $PLATFORM_HEALTHCHECK_URL"
fi

if [[ -n "${VOLWARD_API_BASE:-}" ]]; then
  verify_refresh_route "${VOLWARD_API_BASE%/v1}" "public"
fi

echo "Platform API deployed to ${remote} (${platform_image})"

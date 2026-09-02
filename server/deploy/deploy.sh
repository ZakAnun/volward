#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${VOLWARD_DEPLOY_COMPOSE_FILE:-/etc/volward/docker-compose.extend.yml}"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "error: missing external platform compose file: $COMPOSE_FILE" >&2
  echo "copy the deployment template there, or set VOLWARD_DEPLOY_COMPOSE_FILE to another path" >&2
  exit 1
fi

COMPOSE_DIR="$(cd "$(dirname "$COMPOSE_FILE")" && pwd)"
COMPOSE_FILE="$COMPOSE_DIR/$(basename "$COMPOSE_FILE")"
ENV_FILE="${VOLWARD_ENV_FILE:-/opt/volward/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: missing deployment environment file: $ENV_FILE" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "error: docker compose is required" >&2
  exit 1
fi

if ! docker network inspect volward-net >/dev/null 2>&1; then
  docker network create --driver bridge volward-net >/dev/null
fi

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config >/dev/null
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull platform-api
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --no-deps platform-api

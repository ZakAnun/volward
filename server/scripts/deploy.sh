#!/usr/bin/env bash
set -euo pipefail
cd /opt/volward
docker compose -f docker-compose.yml -f server/docker-compose.extend.yml \
               --env-file .env pull platform-api
docker compose -f docker-compose.yml -f server/docker-compose.extend.yml \
               --env-file .env up -d --no-deps platform-api

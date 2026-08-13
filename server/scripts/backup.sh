#!/usr/bin/env bash
set -euo pipefail
VOLUME_PATH=$(docker volume inspect volward_platform-data --format '{{.Mountpoint}}')
mkdir -p /opt/backups
cp "$VOLUME_PATH/platform.db" "/opt/backups/platform-$(date +%Y%m%d).db"
find /opt/backups -name "platform-*.db" -mtime +14 -delete

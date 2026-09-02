#!/usr/bin/env bash
set -euo pipefail
umask 077
VOLUME_PATH=$(docker volume inspect volward_platform-data --format '{{.Mountpoint}}')
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "error: sqlite3 is required for a consistent online backup" >&2
  exit 1
fi

install -d -m 700 /opt/backups
BACKUP_PATH="/opt/backups/platform-$(date +%Y%m%d).db"
sqlite3 "$VOLUME_PATH/platform.db" ".backup '$BACKUP_PATH'"
chmod 600 "$BACKUP_PATH"
find /opt/backups -name "platform-*.db" -mtime +14 -delete

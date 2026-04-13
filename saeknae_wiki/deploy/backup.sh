#!/bin/bash
# ============================================================
#  사내 Wiki — 백업 스크립트 (crontab 등록용)
#  crontab 예시: 0 2 * * * /opt/wiki/deploy/backup.sh
# ============================================================
BACKUP_DIR="/opt/wiki-backups"
APP_DIR="/opt/wiki"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/wiki_backup_$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"

tar -czf "$BACKUP_FILE" \
    -C "$APP_DIR" wiki.db uploads/ .env

echo "[$(date)] 백업 완료: $BACKUP_FILE"

# 30일 이상 된 백업 자동 삭제
find "$BACKUP_DIR" -name "wiki_backup_*.tar.gz" -mtime +30 -delete
echo "[$(date)] 오래된 백업 정리 완료"

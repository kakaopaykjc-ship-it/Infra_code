#!/bin/bash
# ============================================================
#  VulCheck 업데이트 스크립트
#  실행: sudo bash update.sh
# ============================================================
set -e

APP_DIR="/opt/vulcheck"
APP_USER="vulcheck"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "deploy" ]; then
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
    PROJECT_ROOT="$SCRIPT_DIR"
fi

echo "[*] VulCheck 업데이트 시작..."

# 코드 복사 (.env, DB 제외)
rsync -a --exclude='.env' --exclude='*.db' --exclude='venv/' \
    "$PROJECT_ROOT/" "$APP_DIR/"

# 패키지 업데이트
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt" -q

# 퍼미션 재적용
chown -R "$APP_USER":"$APP_USER" "$APP_DIR"
chmod -R 750 "$APP_DIR"

# 서비스 재시작
systemctl restart vulcheck
echo "[*] 업데이트 완료 — $(systemctl is-active vulcheck)"

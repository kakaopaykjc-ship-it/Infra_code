#!/bin/bash
# ============================================================
#  사내 Wiki — 업데이트 스크립트
#  실행: sudo bash update.sh
# ============================================================
set -e

APP_DIR="/opt/wiki"
APP_USER="wiki"

echo "[1/4] 파일 복사 중..."
# uploads, .env, wiki.db는 덮어쓰지 않음
rsync -av --exclude='uploads/' --exclude='.env' --exclude='wiki.db' \
    ./ "$APP_DIR/"

echo "[2/4] 패키지 업데이트 중..."
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt" -q

echo "[3/4] 퍼미션 재설정..."
chown -R "$APP_USER":"$APP_USER" "$APP_DIR"
chmod -R 750 "$APP_DIR"
chmod 770 "$APP_DIR/uploads"

echo "[4/4] 서비스 재시작..."
systemctl restart wiki
echo ""
echo "✅ 업데이트 완료!"
systemctl status wiki --no-pager

#!/bin/bash
# ============================================================
#  사내 Wiki — Rocky Linux 9 설치 스크립트
#  실행: sudo bash install.sh
# ============================================================
set -e

APP_NAME="wiki"
APP_DIR="/opt/wiki"
APP_USER="wiki"
PYTHON="python3"

# 스크립트 위치 기준으로 프로젝트 루트 자동 탐지
# (deploy/ 안에서 실행해도, 루트에서 실행해도 동작)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "deploy" ]; then
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
    PROJECT_ROOT="$SCRIPT_DIR"
fi
echo "  → 프로젝트 루트: $PROJECT_ROOT"

echo "========================================"
echo "  사내 Wiki 설치 시작 (Rocky Linux 9)"
echo "========================================"

# ── 1. 패키지 설치 ──────────────────────────────────────────
echo "[1/7] 시스템 패키지 설치 중..."
dnf install -y python3 python3-pip nginx curl
# Rocky 9는 venv가 python3에 내장 — 별도 패키지 불필요

# ── 2. 전용 사용자 생성 ─────────────────────────────────────
echo "[2/7] 서비스 계정 생성 중..."
if ! id "$APP_USER" &>/dev/null; then
    useradd -r -s /sbin/nologin -d "$APP_DIR" "$APP_USER"
    echo "  → 계정 '$APP_USER' 생성 완료"
else
    echo "  → 계정 '$APP_USER' 이미 존재"
fi

# ── 3. 앱 디렉터리 구성 ─────────────────────────────────────
echo "[3/7] 앱 디렉터리 구성 중..."
mkdir -p "$APP_DIR"
cp -r "$PROJECT_ROOT"/. "$APP_DIR/"
mkdir -p "$APP_DIR/uploads"

# 가상환경 생성 및 패키지 설치
$PYTHON -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip -q
"$APP_DIR/venv/bin/pip" install gunicorn -q
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt" -q

# .env 없으면 자동 생성 (SECRET_KEY 랜덤)
if [ ! -f "$APP_DIR/.env" ]; then
    SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    echo "SECRET_KEY=$SECRET" > "$APP_DIR/.env"
    echo "  → .env 자동 생성 완료"
fi

# 퍼미션 설정
chown -R "$APP_USER":"$APP_USER" "$APP_DIR"
chmod -R 750 "$APP_DIR"
chmod 770 "$APP_DIR/uploads"

# ── 4. DB 초기화 ────────────────────────────────────────────
echo "[4/7] DB 초기화 중..."
cd "$APP_DIR"
sudo -u "$APP_USER" "$APP_DIR/venv/bin/python" -c "
from app import app, init_db
init_db()
print('  → DB 초기화 완료')
"

# ── 5. systemd 서비스 등록 ──────────────────────────────────
echo "[5/7] systemd 서비스 등록 중..."
cp "$APP_DIR/deploy/wiki.service" /etc/systemd/system/wiki.service
systemctl daemon-reload
systemctl enable wiki
systemctl restart wiki
echo "  → wiki 서비스 시작 완료"

# ── 6. Nginx 설정 ───────────────────────────────────────────
echo "[6/7] Nginx 설정 중..."
cp "$APP_DIR/deploy/wiki.nginx.conf" /etc/nginx/conf.d/wiki.conf
nginx -t && systemctl enable nginx && systemctl restart nginx
echo "  → Nginx 재시작 완료"

# ── 7. 방화벽 ───────────────────────────────────────────────
echo "[7/7] 방화벽 설정 중..."
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
echo "  → 방화벽 규칙 적용 완료"

echo ""
echo "========================================"
echo "  설치 완료!"
echo "  접속 주소: http://$(hostname -I | awk '{print $1}')"
echo "  초기 계정: admin / admin1234"
echo "  ※ 첫 로그인 후 반드시 비밀번호 변경!"
echo "========================================"

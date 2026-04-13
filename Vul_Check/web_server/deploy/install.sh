#!/bin/bash
# ============================================================
#  VulCheck 관리 서버 — Rocky Linux 9 설치 스크립트
#  실행: sudo bash install.sh
# ============================================================
set -e

APP_NAME="vulcheck"
APP_DIR="/opt/vulcheck"
APP_USER="vulcheck"
PYTHON="python3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "deploy" ]; then
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
    PROJECT_ROOT="$SCRIPT_DIR"
fi
echo "  → 프로젝트 루트: $PROJECT_ROOT"

echo "========================================"
echo "  VulCheck 관리 서버 설치 (Rocky Linux 9)"
echo "========================================"

# ── 1. 패키지 설치 ──────────────────────────────────────────
echo "[1/7] 시스템 패키지 설치 중..."
dnf install -y python3 python3-pip nginx curl

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

# 가상환경 생성 및 패키지 설치
$PYTHON -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip -q
"$APP_DIR/venv/bin/pip" install gunicorn -q
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt" -q

# .env 없으면 자동 생성
if [ ! -f "$APP_DIR/.env" ]; then
    API_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    cat > "$APP_DIR/.env" <<EOF
SECRET_KEY=$SECRET_KEY
API_KEY=$API_KEY
EOF
    echo "  → .env 자동 생성 완료"
    echo ""
    echo "  ★ 에이전트에 입력할 API_KEY:"
    echo "    $API_KEY"
    echo ""
fi

# 퍼미션 설정
chown -R "$APP_USER":"$APP_USER" "$APP_DIR"
chmod -R 750 "$APP_DIR"

# ── 4. DB 초기화 ────────────────────────────────────────────
echo "[4/7] DB 초기화 중..."
cd "$APP_DIR"
sudo -u "$APP_USER" "$APP_DIR/venv/bin/python" -c "
from app import app
from models import db
with app.app_context():
    db.create_all()
print('  → DB 초기화 완료')
"

# ── 5. systemd 서비스 등록 ──────────────────────────────────
echo "[5/7] systemd 서비스 등록 중..."
cp "$APP_DIR/deploy/vulcheck.service" /etc/systemd/system/vulcheck.service
systemctl daemon-reload
systemctl enable vulcheck
systemctl restart vulcheck
echo "  → vulcheck 서비스 시작 완료"

# ── 6. Nginx 설정 ───────────────────────────────────────────
echo "[6/7] Nginx 설정 중..."
cp "$APP_DIR/deploy/vulcheck.nginx.conf" /etc/nginx/conf.d/vulcheck.conf
nginx -t && systemctl enable nginx && systemctl restart nginx
echo "  → Nginx 재시작 완료"

# ── 7. 방화벽 ───────────────────────────────────────────────
echo "[7/7] 방화벽 설정 중..."
firewall-cmd --permanent --add-service=http
firewall-cmd --reload
echo "  → 방화벽 규칙 적용 완료"

echo ""
echo "========================================"
echo "  설치 완료!"
echo "  접속 주소: http://$(hostname -I | awk '{print $1}')"
echo "  API_KEY: $(grep API_KEY $APP_DIR/.env | cut -d= -f2)"
echo "========================================"

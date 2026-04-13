import os

# ── 시크릿 (Rocky9: /opt/vulcheck/.env 에서 주입)
SECRET_KEY = os.environ.get("SECRET_KEY", "change-me-please")
API_KEY    = os.environ.get("API_KEY",    "change-me-api-key")

# ── DB (Rocky9: gunicorn WorkingDirectory=/opt/vulcheck 기준)
SQLALCHEMY_DATABASE_URI      = "sqlite:///vul_check.db"
SQLALCHEMY_TRACK_MODIFICATIONS = False

# ── 로컬 테스트용 (Rocky9에서는 gunicorn + nginx 로 서빙)
HOST = "0.0.0.0"
PORT = 5100

import os

# 관리 서버 설정
SECRET_KEY = os.environ.get("SECRET_KEY", "change-me-please")
API_KEY    = os.environ.get("API_KEY",    "change-me-api-key")  # 에이전트 인증 키

SQLALCHEMY_DATABASE_URI      = "sqlite:///vul_check.db"
SQLALCHEMY_TRACK_MODIFICATIONS = False

HOST = "0.0.0.0"
PORT = 5100

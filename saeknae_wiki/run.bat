@echo off
cd /d "%~dp0"
echo [사내 Wiki] 서버 시작 중...
pip install -r requirements.txt >nul 2>&1
python app.py
pause

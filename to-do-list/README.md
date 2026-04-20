# 📅 달력형 투두리스트 + 텔레그램 알림

## 📁 파일 구조
```
todo-calendar/
├── app.py          ← Streamlit 앱 (달력 UI)
├── database.py     ← SQLite DB 관리
├── notifier.py     ← 텔레그램 알림 스케줄러
├── requirements.txt
└── .env.example    ← 환경변수 설정 예시
```

---

## 🚀 시작하기

### 1. 라이브러리 설치
```bash
pip install -r requirements.txt
```

### 2. 환경변수 설정
`.env.example` 파일을 복사해서 `.env` 파일로 만들고 토큰 입력:
```bash
cp .env.example .env
```
`.env` 파일 열어서 수정:
```
TELEGRAM_BOT_TOKEN=1234567890:ABCdef...
TELEGRAM_CHAT_ID=987654321
```

> 💡 채팅 ID 모르면 텔레그램에서 @userinfobot 에게 /start 보내면 알려줘요!

### 3. 앱 실행 (터미널 1)
```bash
streamlit run app.py
```

### 4. 알림 스케줄러 실행 (터미널 2)
```bash
python notifier.py
```

---

## 📱 기능
- 날짜별 할일 추가 / 완료 체크 / 삭제
- 전체 일정 표로 조회
- 매일 아침 08:00 텔레그램 알림 (시간 변경: notifier.py 의 "08:00" 수정)

## ⚡ 알림 즉시 테스트
`notifier.py` 하단 주석 해제 후 실행:
```python
# send_morning_notification()  ← 이 줄 주석 해제
```

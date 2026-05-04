# Weather Bot

매일 정해진 시간에 다중 지역 날씨 정보를 텔레그램으로 전송하는 파이썬 봇.

`wttr.in` 무료 API를 사용하므로 별도 API 키가 필요 없다.

---

## 주요 기능

- **다중 지역 지원**: 여러 도시를 한 번에 조회
- **상세 정보**: 현재 기온, 체감, 날씨 상태, 최저/최고, 습도, 강수확률
- **스마트 알림**: 우산·폭염·한파·일교차 등 조건 기반 자동 경고
- **시간별 예보**: 현재 시각 이후 3시간 단위 예보
- **주간 예보**: 내일·모레 요약 카드
- **재시도 로직**: API 호출 실패 시 자동 재시도 (3회, 5초 간격)

---

## 파일 구조

```
Weather_bot/
├── weather_bot.py             # 메인 봇 스크립트 (운영용)
├── config.py                  # 텔레그램 토큰 + 지역 설정
├── preview_card.py            # (선택) 카드 이미지 시안 생성기
├── weather_card_preview.png   # 카드 이미지 시안 결과물
└── README.md
```

---

## 요구사항

- Python 3.8+
- `requests` 라이브러리 (`pip install requests`)
- 텔레그램 봇 토큰 + 채팅 ID

> `preview_card.py`만 추가로 `Pillow`가 필요하다 (`pip install Pillow`). 운영용 봇 자체는 표준 라이브러리 + requests로 충분.

---

## 설정

`config.py` 편집:

```python
TELEGRAM_TOKEN = "여기에_봇_토큰_입력"
CHAT_ID = "여기에_채팅ID_입력"

LOCATIONS = [
    {"name": "서울", "query": "Seoul,Korea"},
    {"name": "군포", "query": "Gunpo,Korea"},
]
```

`query`는 wttr.in이 인식하는 검색어 (도시명, 공항코드, 좌표 등 가능).

---

## 실행

### 수동 실행

```bash
cd /weather_bot
python3 weather_bot.py
```

### Crontab 등록 (Rocky Linux 기준)

매일 오전 9시 실행 예시:

```bash
crontab -e
```

```cron
0 9 * * * cd /weather_bot && /usr/bin/python3 weather_bot.py >> /var/log/weather_bot.log 2>&1
```

---

## 코드 리뷰

### `get_weather(query, name, retries=3, retry_delay=5)`

wttr.in API 호출 → JSON 파싱 → 필요한 필드 추출.

- **재시도**: 네트워크 오류·일시적 장애 대비 3회 재시도
- **현재 정보**: `current_condition[0]`에서 기온/체감/상태/습도
- **시간별 예보**: 오늘(`weather[0].hourly`)에서 현재 시각 이후만 필터링
- **주간 예보**: `weather[1:]` (내일·모레), 낮 12시(`hourly[4]`) 기준 대표 코드 사용
- **강수확률**: 시간별 예보 기준 max — 이미 지나간 새벽 강수예보 제외 (모순 메시지 방지)

반환값에 `error` 키가 있으면 호출 실패로 간주하고 메시지에서 안내 처리.

### `get_smart_alerts(w)`

날씨 데이터를 입력받아 경고 메시지 리스트를 반환. 조건은 아래 표 참고.

### `format_hourly(hourly)` / `format_weekly(weekly)`

시간별·주간 예보를 텔레그램용 텍스트로 포맷팅. 강수확률이 낮으면(시간별 < 20%, 주간 < 30%) 노이즈를 줄이기 위해 표시 생략.

### `format_message(weather_list)`

도시별 카드를 조합해 최종 메시지 생성. 알림 → 시간별 → 주간 순서.

### `send_telegram(message)`

텔레그램 봇 API의 `sendMessage` 엔드포인트 호출.

### `main()`

설정된 모든 지역을 순회하며 `get_weather` → `format_message` → `send_telegram`.

---

## 스마트 알림 조건

| 조건 | 임계값 | 알림 메시지 |
|---|---|---|
| 우산 챙기기 | 강수확률 ≥ 50% | `🌂 강수확률 X% — 우산 챙기세요` |
| 우산 필수 | 강수확률 ≥ 70% | `☂️ 강수확률 X% — 우산 필수!` |
| 폭염 주의 | 최고 ≥ 33°C | `🔥 폭염 주의 (최고 X°C)` |
| 한파 주의 | 최저 ≤ -5°C | `🥶 한파 주의 (최저 X°C)` |
| 일교차 큼 | 최고 - 최저 ≥ 15°C | `🌡 일교차 큼 (X°C차)` |

---

## 출력 예시

```
☀️ 오늘의 날씨 알림

📍 서울
  🌡 현재: 13°C (체감 12°C)
  🌤 상태: 흐림
  🔻 최저: 12°C  🔺 최고: 23°C
  💧 습도: 62%  🌧 강수확률: 0%
  ⚠️ 🌡 일교차 큼 (11°C차)
  ⏱ 시간별 예보
    15시: ☀️ 22°C
    18시: ⛅ 19°C
    21시: ☁️ 15°C
  📅 향후 예보
    화(5/5): ⛅ 구름 조금 🔻14°C 🔺24°C  🌧10%
    수(5/6): 🌧 비 🔻13°C 🔺19°C  🌧70%
```

---

## 시안: 카드 이미지 알림 (예정)

`preview_card.py`는 텔레그램 메시지를 이미지 카드로 전송하기 위한 디자인 시안 생성기.

다크 테마, 도시별 카드, 시간별 막대 그래프, 주간 미니 카드 등을 포함한 PNG를 생성한다. 결과물은 `weather_card_preview.png` 참고.

운영용 `weather_bot.py`에는 아직 통합되지 않은 상태.

---

## 배포 가이드 (Rocky Linux)

```bash
# 최초 배포
mkdir -p /weather_bot && cd /weather_bot
git clone <repo>
# 또는 weather_bot.py와 config.py 두 파일만 복사

# config.py에 토큰/CHAT_ID 입력 후
python3 weather_bot.py    # 동작 테스트
crontab -e                 # 스케줄 등록

# 코드 업데이트
cd /weather_bot
curl -o weather_bot.py https://raw.githubusercontent.com/kakaopaykjc-ship-it/Infra_code/main/Weather_bot/weather_bot.py
```

---

## 트러블슈팅

- **메시지가 안 옴**: `python3 weather_bot.py` 수동 실행해서 에러 확인. 토큰/CHAT_ID 점검.
- **wttr.in 응답 실패**: 무료 API라 가끔 일시 장애가 있음. 재시도 로직이 있지만 그래도 실패하면 다음 실행 주기까지 대기.
- **한글이 깨짐**: 텔레그램 측 문제는 거의 없음. 서버 로케일이 UTF-8인지 확인 (`locale` 명령).

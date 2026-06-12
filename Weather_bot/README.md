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
- **카드 이미지 알림**: 다크 테마 PNG 카드를 텔레그램 사진으로 전송
- **자동 fallback**: 카드 생성 실패 시 텍스트 메시지로 자동 전환
- **재시도 로직**: API 호출 실패 시 자동 재시도 (3회, 5초 간격)

---

## 파일 구조

```
Weather_bot/
├── weather_bot.py             # 메인 봇 스크립트 (운영용)
├── weather_card.py            # 카드 이미지 렌더러 모듈
├── config.py                  # 텔레그램 토큰 + 지역 설정
├── preview_card.py            # (개발용) 더미 데이터로 카드 시안 PNG 생성
├── weather_card_preview.png   # 카드 시안 결과물
└── README.md
```

---

## 요구사항

- Python 3.8+
- `requests`, `Pillow` (`pip install requests Pillow`)
- 한글 폰트 (Linux 운영 시 필수)
- 텔레그램 봇 토큰 + 채팅 ID

### Rocky Linux 패키지 설치

```bash
# Python 라이브러리
pip3 install requests Pillow

# 한글 폰트 (둘 중 하나)
sudo dnf install -y google-noto-sans-cjk-fonts
# 또는
sudo dnf install -y nhn-nanum-fonts
```

> 폰트가 없으면 카드 생성이 실패하면서 자동으로 텍스트 알림으로 fallback 된다. 이미지로 받고 싶으면 폰트 설치 필수.

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

### `make_caption(weather_list)`

카드 이미지에 첨부할 짧은 캡션 생성 (날짜 + 도시별 한 줄 요약 + 알림).

### `send_telegram(message)` / `send_telegram_photo(photo, caption)`

각각 `sendMessage` / `sendPhoto` 엔드포인트 호출. 텍스트는 fallback용.

### `main()`

흐름: 지역 순회 → 날씨 조회 → 알림 채우기 → **카드 이미지 생성·전송 시도 → 실패 시 텍스트로 fallback**.

### `weather_card.render(data)` (별도 모듈)

도시별 날씨 데이터를 받아 PIL Image를 반환. 폰트 경로는 Windows·Rocky·Ubuntu 등 여러 경로를 자동 탐색.

- **슈퍼샘플링(SS=2)**: 전체를 2배 해상도(1280px)로 그린 뒤 `LANCZOS`로 640px 다운스케일 → 안티앨리어싱. PIL은 기본적으로 안티앨리어싱을 하지 않아 그냥 그리면 텍스트·아이콘·막대에 계단 현상이 생긴다.
- **`_ScaledDraw` 프록시**: 드로잉 코드는 모두 논리 좌표(1배)로 작성하고, 프록시가 좌표·선두께·반지름을 자동으로 SS배 확대해 실제 캔버스에 그린다. 덕분에 레이아웃 로직은 배율을 신경 쓸 필요가 없다.
- **벡터 아이콘**: `_icon_kind(code)`가 wttr.in 날씨코드를 해/구름조금/구름·안개/비/눈/천둥으로 분류하고, 각각 `_icon_sun`·`_icon_cloud`·`_icon_rain`·`_icon_snow`·`_icon_thunder`로 그린다. 컬러 이모지 폰트 없이도 모든 환경에서 동일하게 렌더된다.

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

## 카드 이미지 알림

운영용 `weather_bot.py`가 매 실행마다 `weather_card.render()`로 PNG를 메모리에 생성해 텔레그램 `sendPhoto`로 전송한다.

- **다크 테마**, 도시별 카드, 시간별 막대 그래프, 주간 미니 카드 포함
- **2배 슈퍼샘플링** 렌더 후 다운스케일 → 텍스트·아이콘·막대가 또렷 (계단 현상 제거)
- **벡터 날씨 아이콘**: 해/구름/구름조금/비/눈/천둥을 코드로 분류해 직접 그림 (이모지 폰트 불필요)
- 헤더 구분선·카드 테두리·통계 세로 구분선·알약형 알림 배지로 정돈된 카드뉴스 스타일
- 캡션에는 날짜·도시별 요약·알림만 짧게 들어감 (시각 정보는 이미지가 전달)
- 카드 생성·전송이 실패하면 자동으로 텍스트 메시지로 fallback (안전망)

`preview_card.py`는 더미 데이터로 디자인 시안만 미리 보고 싶을 때 사용:

```bash
python3 preview_card.py    # weather_card_preview.png 생성
```

---

## 배포 가이드 (Rocky Linux)

```bash
# 1. 의존성 설치
pip3 install requests Pillow
sudo dnf install -y google-noto-sans-cjk-fonts   # 또는 nhn-nanum-fonts

# 2. 코드 배치
mkdir -p /weather_bot && cd /weather_bot
# 운영에 필요한 파일은 다음 3개:
#   weather_bot.py, weather_card.py, config.py

# 3. config.py에 토큰/CHAT_ID 입력 후 동작 테스트
python3 weather_bot.py

# 4. 크론 등록
crontab -e
```

### 코드 업데이트 (이미 배포된 서버에서)

```bash
cd /weather_bot
curl -o weather_bot.py  https://raw.githubusercontent.com/kakaopaykjc-ship-it/Infra_code/main/Weather_bot/weather_bot.py
curl -o weather_card.py https://raw.githubusercontent.com/kakaopaykjc-ship-it/Infra_code/main/Weather_bot/weather_card.py
```

---

## 트러블슈팅

- **메시지가 안 옴**: `python3 weather_bot.py` 수동 실행해서 에러 확인. 토큰/CHAT_ID 점검.
- **이미지 대신 텍스트로 옴**: 카드 생성 실패 → fallback 동작. 콘솔 로그에 원인 표시. 주로 폰트 또는 Pillow 미설치.
  - `pip3 install Pillow`
  - `sudo dnf install -y google-noto-sans-cjk-fonts`
- **wttr.in 응답 실패**: 무료 API라 가끔 일시 장애가 있음. 재시도 로직이 있지만 그래도 실패하면 다음 실행 주기까지 대기.
- **한글이 깨짐**: 텔레그램 측 문제는 거의 없음. 서버 로케일이 UTF-8인지 확인 (`locale` 명령).

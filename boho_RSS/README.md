# boho_RSS: 보호나라 RSS → Mattermost 알림

[보호나라(KISA)](https://www.boho.or.kr) RSS 피드를 주기적으로 감시하여 신규 글을 Mattermost 웹훅으로 전송하는 스크립트.

---

## 파일 구조

```
boho_RSS/
├── boho_rss_mattermost.py   # 메인 스크립트 (운영용)
├── test.py                  # 웹훅 연결 단순 확인용
└── test1.py                 # 외부 라이브러리 없이 RSS 파싱 + 전송 테스트용
```

### boho_rss_mattermost.py (메인)

| 항목 | 내용 |
|------|------|
| RSS 대상 | 보안공지 / 취약점 정보 / 경보단계 (3개 피드) |
| 중복 방지 | `/opt/boho-rss/seen.json` 에 전송한 항목의 SHA-256 ID를 저장 |
| 초기 실행 | 기존 글은 전송 없이 seen 처리 → 다음 실행부터 신규 글만 전송 |
| 폭주 방지 | 한 번에 최대 10건까지만 전송 |
| 의존성 | `feedparser`, `requests` |

**주요 함수 흐름**

```
main()
 ├─ BOHO_RSS_FORCE_SEND 환경변수 있으면 → force_test_send() 실행 후 종료
 ├─ load_seen()          seen.json 로드
 ├─ collect_alerts()     3개 RSS 피드 파싱, 미전송 항목 수집
 ├─ save_seen()          seen.json 업데이트
 └─ send_mattermost()    신규 항목 Mattermost 전송 (최대 10건)
```

### test.py

웹훅 URL이 정상 동작하는지 단순 POST 요청으로 확인하는 스크립트.

### test1.py

`feedparser` 없이 표준 라이브러리(`urllib`, `xml.etree`)만으로 RSS 파싱 후 최근 5개를 Mattermost에 전송. 외부 패키지 설치가 어려운 환경에서 사용.

---

## 환경변수

| 변수명 | 필수 | 설명 |
|--------|------|------|
| `MATTERMOST_WEBHOOK_URL` | **필수** | Mattermost Incoming Webhook URL |
| `BOHO_RSS_FORCE_SEND` | 선택 | 숫자 지정 시 seen 무시하고 강제 테스트 전송 (예: `5` → 최대 5건) |

---

## 설치 및 실행

### 1. 의존성 설치

```bash
pip install feedparser requests
```

### 2. 환경변수 설정

```bash
export MATTERMOST_WEBHOOK_URL="https://<your-mattermost>/hooks/<token>"
```

### 3. 실행

**일반 실행 (신규 글만 전송)**
```bash
python3 boho_rss_mattermost.py
```

**강제 테스트 전송 (최근 5건, seen 무시)**
```bash
BOHO_RSS_FORCE_SEND=5 python3 boho_rss_mattermost.py
```

**웹훅 연결 확인만**
```bash
python3 test.py
```

---

## crontab 설정 예시 (매시간 실행)

```cron
0 * * * * MATTERMOST_WEBHOOK_URL="https://<your-mattermost>/hooks/<token>" /usr/bin/python3 /opt/boho-rss/boho_rss_mattermost.py >> /var/log/boho-rss.log 2>&1
```

> `seen.json` 경로 `/opt/boho-rss/seen.json` 는 스크립트 내 `STATE_FILE` 변수에서 변경 가능.

---

## 모니터링 대상 RSS 피드

| 채널명 | URL |
|--------|-----|
| 보안공지 | https://www.boho.or.kr/kr/rss.do?bbsId=B0000133 |
| 취약점 정보 | https://www.boho.or.kr/kr/rss.do?bbsId=B0000302 |
| 경보단계 | https://www.boho.or.kr/kr/rss.do?bbsId=B0000342 |

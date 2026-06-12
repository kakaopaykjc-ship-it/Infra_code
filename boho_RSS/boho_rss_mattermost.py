#!/usr/bin/env python3
import os
import json
import hashlib
from pathlib import Path
from datetime import datetime

import feedparser
import requests


# crontab에서 넘긴 환경변수 이름을 정확히 받아야 함
WEBHOOK_URL = os.environ.get("MATTERMOST_WEBHOOK_URL")

RSS_FEEDS = {
    "보안공지": "https://www.boho.or.kr/kr/rss.do?bbsId=B0000133",
    "취약점 정보": "https://www.boho.or.kr/kr/rss.do?bbsId=B0000302",
    "경보단계": "https://www.boho.or.kr/kr/rss.do?bbsId=B0000342",
}

STATE_FILE = Path("/opt/boho-rss/seen.json")


def log(msg):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{now}] {msg}")


def load_seen():
    if not STATE_FILE.exists():
        return set()

    try:
        return set(json.loads(STATE_FILE.read_text(encoding="utf-8")))
    except Exception as e:
        log(f"seen.json 읽기 실패, 새로 시작합니다: {e}")
        return set()


def save_seen(seen):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(
        json.dumps(sorted(seen), ensure_ascii=False, indent=2),
        encoding="utf-8"
    )


def make_id(feed_name, entry):
    base = entry.get("id") or entry.get("link") or entry.get("title")
    raw = f"{feed_name}|{base}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def send_mattermost(text):
    if not WEBHOOK_URL:
        raise RuntimeError("MATTERMOST_WEBHOOK_URL 환경변수가 없습니다.")

    res = requests.post(
        WEBHOOK_URL,
        json={"text": text},
        timeout=10
    )

    if res.status_code != 200:
        raise RuntimeError(f"Mattermost 전송 실패: {res.status_code} {res.text}")

    return res.text


def build_message(feed_name, entry, test=False):
    title = entry.get("title", "제목 없음")
    link = entry.get("link", "")
    published = entry.get("published", entry.get("updated", ""))

    prefix = "[보호나라 RSS 테스트]" if test else "[보호나라 RSS]"

    return (
        f"### {prefix} {feed_name}\n"
        f"**{title}**\n\n"
        f"- 등록일: {published if published else '확인 필요'}\n"
        f"- 링크: {link}"
    )


def collect_alerts(seen):
    new_seen = set(seen)
    alerts = []
    total_entries = 0

    for feed_name, feed_url in RSS_FEEDS.items():
        parsed = feedparser.parse(feed_url)

        if getattr(parsed, "bozo", False):
            log(f"RSS 파싱 경고: {feed_name} / {getattr(parsed, 'bozo_exception', '')}")

        entries = parsed.entries
        log(f"{feed_name}: RSS 항목 {len(entries)}건 확인")
        total_entries += len(entries)

        for entry in entries:
            item_id = make_id(feed_name, entry)
            new_seen.add(item_id)

            if item_id in seen:
                continue

            alerts.append(build_message(feed_name, entry))

    return alerts, new_seen, total_entries


def force_test_send(limit=5):
    sent = 0

    for feed_name, feed_url in RSS_FEEDS.items():
        parsed = feedparser.parse(feed_url)

        for entry in parsed.entries:
            if sent >= limit:
                return sent

            msg = build_message(feed_name, entry, test=True)
            result = send_mattermost(msg)
            log(f"테스트 전송 완료: {feed_name} / Mattermost 응답: {result}")
            sent += 1

    return sent


def main():
    # 강제 테스트 전송용
    # 예: BOHO_RSS_FORCE_SEND=5 python3 /boho_RSS/boho_rss_mattermost.py
    force_send = os.environ.get("BOHO_RSS_FORCE_SEND")
    if force_send:
        limit = int(force_send)
        sent = force_test_send(limit)
        log(f"강제 테스트 전송 완료: {sent}건")
        return

    first_run = not STATE_FILE.exists()
    seen = load_seen()

    alerts, new_seen, total_entries = collect_alerts(seen)

    save_seen(new_seen)

    if first_run:
        log(f"초기 실행: 기존 RSS {total_entries}건을 seen 처리했습니다. 다음 실행부터 신규 글만 전송합니다.")
        return

    send_count = 0

    # 오래 밀려있던 경우 폭주 방지: 최신 10건까지만 전송
    for msg in alerts[:10]:
        result = send_mattermost(msg)
        log(f"Mattermost 전송 완료: {result}")
        send_count += 1

    log(f"전송 완료: {send_count}건 / 신규 감지: {len(alerts)}건 / 전체 RSS 확인: {total_entries}건")


if __name__ == "__main__":
    main()

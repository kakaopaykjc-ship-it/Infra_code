#!/usr/bin/env python3
import json
import os
import urllib.request
import xml.etree.ElementTree as ET
from html import unescape

# ==================================================
# 여기 2개만 네 값으로 수정
# ==================================================
WEBHOOK_URL = os.environ.get("MATTERMOST_WEBHOOK_URL", "")
RSS_URL = "https://www.boho.or.kr/kr/rss.do?bbsId=B0000133"
# ==================================================


def clean_text(text):
    if text is None:
        return ""
    return unescape(str(text)).strip()


def local_name(tag):
    return tag.split("}")[-1].lower()


def get_text(el, tagname):
    tagname = tagname.lower()

    for child in el.iter():
        if local_name(child.tag) == tagname:
            return clean_text(child.text)

    return ""


def get_link(el):
    # 일반 RSS: <link>URL</link>
    link = get_text(el, "link")
    if link:
        return link

    # Atom: <link href="URL" />
    for child in el.iter():
        if local_name(child.tag) == "link":
            href = child.attrib.get("href")
            if href:
                return href.strip()

    return ""


def fetch_rss():
    req = urllib.request.Request(
        RSS_URL,
        headers={
            "User-Agent": "Mozilla/5.0"
        }
    )

    with urllib.request.urlopen(req, timeout=20) as res:
        return res.read()


def parse_items(xml_data):
    root = ET.fromstring(xml_data)

    # RSS 방식
    items = root.findall(".//item")

    # Atom 방식
    if not items:
        items = root.findall(".//{http://www.w3.org/2005/Atom}entry")

    return items[:5]


def send_mattermost(text):
    payload = {
        "text": text
    }

    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")

    req = urllib.request.Request(
        WEBHOOK_URL,
        data=data,
        headers={
            "Content-Type": "application/json"
        },
        method="POST"
    )

    with urllib.request.urlopen(req, timeout=20) as res:
        body = res.read().decode("utf-8", errors="ignore")
        print("Mattermost response:", res.status, body)


def main():
    if not WEBHOOK_URL.startswith("http"):
        raise Exception("WEBHOOK_URL 값이 잘못됐습니다.")

    if not RSS_URL.startswith("http"):
        raise Exception("RSS_URL 값이 잘못됐습니다.")

    xml_data = fetch_rss()
    items = parse_items(xml_data)

    if not items:
        raise Exception("RSS 항목을 찾지 못했습니다.")

    lines = []
    lines.append("### [TEST] 보호나라 RSS 최근 5개")
    lines.append("Mattermost 수신 테스트용 메시지입니다.")

    for idx, item in enumerate(items, 1):
        title = get_text(item, "title")
        link = get_link(item)

        pubdate = (
            get_text(item, "pubDate")
            or get_text(item, "published")
            or get_text(item, "updated")
            or get_text(item, "date")
        )

        lines.append("")
        lines.append(f"{idx}. **{title}**")

        if pubdate:
            lines.append(f"   - 날짜: {pubdate}")

        if link:
            lines.append(f"   - 링크: {link}")

    message = "\n".join(lines)
    send_mattermost(message)


if __name__ == "__main__":
    main()

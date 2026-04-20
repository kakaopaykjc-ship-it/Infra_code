"""
notifier.py
-----------
매일 아침 08:00 에 오늘의 할일을 텔레그램으로 전송합니다.

실행 방법:
    python notifier.py

앱(app.py)과 별도 터미널에서 동시에 실행하세요.
"""

import os
import time
from datetime import date

import requests
import schedule
from dotenv import load_dotenv

from database import get_today_todos

load_dotenv()  # .env 파일에서 환경변수 로드

BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")


def send_telegram_message(message: str):
    """텔레그램 메시지 전송"""
    if not BOT_TOKEN or not CHAT_ID:
        print("❌ .env 파일에 TELEGRAM_BOT_TOKEN과 TELEGRAM_CHAT_ID를 설정해주세요!")
        return

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": CHAT_ID,
        "text": message,
        "parse_mode": "Markdown",
    }
    response = requests.post(url, json=payload, timeout=10)
    if response.status_code == 200:
        print(f"✅ 알림 전송 성공! ({date.today()})")
    else:
        print(f"❌ 전송 실패: {response.text}")


def send_morning_notification():
    """오늘의 할일 목록을 텔레그램으로 전송"""
    todos = get_today_todos()
    today_str = date.today().strftime("%Y년 %m월 %d일")

    if not todos:
        message = f"🌅 *{today_str}*\n\n오늘 할 일이 없어요! 여유로운 하루 보내세요 😊"
    else:
        message = f"🌅 *{today_str} 할 일 목록*\n\n"
        for i, todo in enumerate(todos, 1):
            # todo = (id, title, description, date, done)
            title = todo[1]
            desc = todo[2]
            message += f"{i}. *{title}*"
            if desc:
                message += f"\n   _{desc}_"
            message += "\n"
        message += f"\n총 *{len(todos)}개* 남았어요. 오늘도 파이팅! 💪"

    send_telegram_message(message)


def run_scheduler():
    """스케줄러 실행 - 매일 08:00에 알림 전송"""
    # 원하는 시간으로 변경 가능 (예: "09:00", "07:30")
    schedule.every().day.at("08:00").do(send_morning_notification)

    print("⏰ 스케줄러 실행 중... (매일 08:00에 텔레그램 알림 전송)")
    print("   종료하려면 Ctrl+C 를 누르세요.\n")

    while True:
        schedule.run_pending()
        time.sleep(60)  # 1분마다 스케줄 체크


if __name__ == "__main__":
    # 바로 테스트하고 싶으면 아래 주석 해제
    # send_morning_notification()

    run_scheduler()

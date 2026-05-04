"""더미 데이터로 weather_card 시안 PNG 생성 (개발/디자인 확인용).

운영용 봇은 weather_bot.py가 weather_card.render()를 직접 호출한다.
"""

import os
from datetime import datetime
from weather_card import render

DUMMY = {
    "date": datetime(2026, 5, 4),
    "cities": [
        {
            "name": "서울",
            "temp": "13", "feels": "12", "status": "흐림", "code": 119,
            "low": "12", "high": "23", "humidity": "62", "rain": 0,
            "alerts": ["일교차 큼 (11°C차)"],
            "hourly": [
                {"time": 9, "temp": "13", "rain": 0, "code": 119},
                {"time": 12, "temp": "18", "rain": 0, "code": 116},
                {"time": 15, "temp": "22", "rain": 0, "code": 113},
                {"time": 18, "temp": "19", "rain": 10, "code": 116},
                {"time": 21, "temp": "15", "rain": 30, "code": 119},
            ],
            "weekly": [
                {"label": "화(5/5)", "low": "14", "high": "24",
                 "rain": 10, "code": 116, "status": "구름 조금"},
                {"label": "수(5/6)", "low": "13", "high": "19",
                 "rain": 70, "code": 296, "status": "비"},
            ],
        },
        {
            "name": "군포",
            "temp": "13", "feels": "13", "status": "흐림", "code": 119,
            "low": "12", "high": "21", "humidity": "40", "rain": 0,
            "alerts": [],
            "hourly": [
                {"time": 9, "temp": "13", "rain": 0, "code": 119},
                {"time": 12, "temp": "17", "rain": 0, "code": 119},
                {"time": 15, "temp": "21", "rain": 0, "code": 116},
                {"time": 18, "temp": "18", "rain": 0, "code": 119},
                {"time": 21, "temp": "14", "rain": 20, "code": 119},
            ],
            "weekly": [
                {"label": "화(5/5)", "low": "13", "high": "22",
                 "rain": 0, "code": 113, "status": "맑음"},
                {"label": "수(5/6)", "low": "12", "high": "18",
                 "rain": 60, "code": 296, "status": "비"},
            ],
        },
    ],
}


if __name__ == "__main__":
    img = render(DUMMY)
    out = os.path.join(os.path.dirname(__file__), "weather_card_preview.png")
    img.save(out)
    print(f"Saved: {out} ({img.size[0]}x{img.size[1]})")

import requests
import time
from datetime import datetime
from config import TELEGRAM_TOKEN, CHAT_ID, LOCATIONS

WEATHER_KO = {
    113: "맑음", 116: "구름 조금", 119: "흐림", 122: "흐림",
    143: "안개", 176: "가끔 비", 179: "가끔 눈", 182: "진눈깨비",
    200: "천둥번개", 227: "눈", 230: "눈", 248: "안개", 260: "안개",
    263: "가끔 비", 266: "이슬비", 281: "진눈깨비", 284: "진눈깨비",
    293: "가끔 비", 296: "비", 299: "비", 302: "비", 305: "비",
    308: "폭우", 311: "진눈깨비", 314: "진눈깨비", 317: "진눈깨비",
    320: "가끔 눈", 323: "가끔 눈", 326: "가끔 눈", 329: "눈",
    332: "눈", 335: "폭설", 338: "폭설", 350: "우박",
    353: "가끔 비", 356: "비", 359: "폭우", 362: "진눈깨비",
    365: "진눈깨비", 368: "가끔 눈", 371: "눈", 374: "우박",
    386: "천둥번개", 389: "뇌우", 392: "천둥번개", 395: "눈",
}

WEATHER_EMOJI = {
    113: "☀️", 116: "⛅", 119: "☁️", 122: "☁️",
    143: "🌫", 176: "🌦", 179: "🌨", 182: "🌧",
    200: "⛈", 227: "❄️", 230: "❄️", 248: "🌫", 260: "🌫",
    263: "🌦", 266: "🌧", 281: "🌧", 284: "🌧",
    293: "🌦", 296: "🌧", 299: "🌧", 302: "🌧", 305: "🌧",
    308: "🌊", 311: "🌧", 314: "🌧", 317: "🌧",
    320: "🌨", 323: "🌨", 326: "🌨", 329: "❄️",
    332: "❄️", 335: "🌨", 338: "🌨", 350: "🌩",
    353: "🌦", 356: "🌧", 359: "🌊", 362: "🌧",
    365: "🌧", 368: "🌨", 371: "❄️", 374: "🌩",
    386: "⛈", 389: "⛈", 392: "⛈", 395: "❄️",
}

DAY_KO = ["월", "화", "수", "목", "금", "토", "일"]


def weather_emoji(code):
    return WEATHER_EMOJI.get(code, "🌡")


def get_smart_alerts(w):
    alerts = []
    rain = w.get("rain", 0)
    high = int(w.get("high", 0))
    low = int(w.get("low", 0))
    temp_diff = high - low

    if rain >= 70:
        alerts.append(f"☂️ 강수확률 {rain}% — 우산 필수!")
    elif rain >= 50:
        alerts.append(f"🌂 강수확률 {rain}% — 우산 챙기세요")

    if high >= 33:
        alerts.append(f"🔥 폭염 주의 (최고 {high}°C)")
    if low <= -5:
        alerts.append(f"🥶 한파 주의 (최저 {low}°C)")
    if temp_diff >= 15:
        alerts.append(f"🌡 일교차 큼 ({temp_diff}°C차)")

    return alerts


def get_weather(query, name, retries=3, retry_delay=5):
    url = f"https://wttr.in/{query}?format=j1&lang=ko"
    headers = {"User-Agent": "WeatherBot/1.0 (curl/7.68.0)"}
    last_error = "알 수 없는 오류"
    for attempt in range(retries):
        try:
            res = requests.get(url, timeout=15, headers=headers)
            res.raise_for_status()
            data = res.json()

            current = data["current_condition"][0]
            today = data["weather"][0]

            temp = current["temp_C"]
            feels = current["FeelsLikeC"]
            code = int(current["weatherCode"])
            status = WEATHER_KO.get(code, current["weatherDesc"][0]["value"])
            low = today["mintempC"]
            high = today["maxtempC"]
            humidity = current["humidity"]

            rain_chances = [int(h["chanceofrain"]) for h in today["hourly"]]
            rain = max(rain_chances)

            # 시간별 예보: 현재 시각 이후 시간대만
            now_hour = datetime.now().hour
            hourly = []
            for h in today["hourly"]:
                t = int(h["time"]) // 100
                if t >= now_hour:
                    hourly.append({
                        "time": t,
                        "temp": h["tempC"],
                        "rain": int(h["chanceofrain"]),
                        "code": int(h["weatherCode"]),
                    })

            # 주간 예보: 내일, 모레
            weekly = []
            for day in data["weather"][1:]:
                day_date = datetime.strptime(day["date"], "%Y-%m-%d")
                day_label = f"{DAY_KO[day_date.weekday()]}({day_date.month}/{day_date.day})"
                day_code = int(day["hourly"][4]["weatherCode"])  # 낮 12시 기준
                day_rain = max(int(h["chanceofrain"]) for h in day["hourly"])
                weekly.append({
                    "label": day_label,
                    "high": day["maxtempC"],
                    "low": day["mintempC"],
                    "rain": day_rain,
                    "code": day_code,
                    "status": WEATHER_KO.get(day_code, ""),
                })

            return {
                "name": name,
                "temp": temp,
                "feels": feels,
                "status": status,
                "code": code,
                "low": low,
                "high": high,
                "humidity": humidity,
                "rain": rain,
                "hourly": hourly,
                "weekly": weekly,
            }
        except Exception as e:
            last_error = str(e)
            if attempt < retries - 1:
                time.sleep(retry_delay)
    return {"name": name, "error": last_error}


def format_hourly(hourly):
    if not hourly:
        return ""
    lines = ["  ⏱ 시간별 예보"]
    for h in hourly:
        emoji = weather_emoji(h["code"])
        rain_txt = f" 🌧{h['rain']}%" if h["rain"] >= 20 else ""
        lines.append(f"    {h['time']:02d}시: {emoji} {h['temp']}°C{rain_txt}")
    return "\n".join(lines)


def format_weekly(weekly):
    if not weekly:
        return ""
    lines = ["  📅 향후 예보"]
    for day in weekly:
        emoji = weather_emoji(day["code"])
        lines.append(
            f"    {day['label']}: {emoji} {day['status']} "
            f"🔻{day['low']}°C 🔺{day['high']}°C  🌧{day['rain']}%"
        )
    return "\n".join(lines)


def format_message(weather_list):
    lines = ["☀️ 오늘의 날씨 알림\n"]
    for w in weather_list:
        if "error" in w:
            lines.append(f"📍 {w['name']}\n⚠️ 날씨 정보를 불러올 수 없어요.\n")
        else:
            block = (
                f"📍 {w['name']}\n"
                f"  🌡 현재: {w['temp']}°C (체감 {w['feels']}°C)\n"
                f"  🌤 상태: {w['status']}\n"
                f"  🔻 최저: {w['low']}°C  🔺 최고: {w['high']}°C\n"
                f"  💧 습도: {w['humidity']}%  🌧 강수확률: {w['rain']}%\n"
            )

            alerts = get_smart_alerts(w)
            if alerts:
                block += "  ⚠️ " + " | ".join(alerts) + "\n"

            hourly_text = format_hourly(w.get("hourly", []))
            if hourly_text:
                block += hourly_text + "\n"

            weekly_text = format_weekly(w.get("weekly", []))
            if weekly_text:
                block += weekly_text + "\n"

            lines.append(block)
    return "\n".join(lines)


def send_telegram(message):
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    payload = {"chat_id": CHAT_ID, "text": message}
    res = requests.post(url, data=payload, timeout=10)
    res.raise_for_status()


def main():
    weather_list = [get_weather(loc["query"], loc["name"]) for loc in LOCATIONS]
    message = format_message(weather_list)
    send_telegram(message)
    print("날씨 알림 전송 완료")


if __name__ == "__main__":
    main()

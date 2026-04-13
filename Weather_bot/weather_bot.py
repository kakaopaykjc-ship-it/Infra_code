import requests
import time
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

            # 오늘 시간별 예보에서 최대 강수확률
            rain_chances = [int(h["chanceofrain"]) for h in today["hourly"]]
            rain = max(rain_chances)

            return {
                "name": name,
                "temp": temp,
                "feels": feels,
                "status": status,
                "low": low,
                "high": high,
                "humidity": humidity,
                "rain": rain,
            }
        except Exception as e:
            last_error = str(e)
            if attempt < retries - 1:
                time.sleep(retry_delay)
    return {"name": name, "error": last_error}


def format_message(weather_list):
    lines = ["☀️ 오늘의 날씨 알림\n"]
    for w in weather_list:
        if "error" in w:
            lines.append(f"📍 {w['name']}\n⚠️ 날씨 정보를 불러올 수 없어요.\n")
        else:
            lines.append(
                f"📍 {w['name']}\n"
                f"  🌡 현재: {w['temp']}°C (체감 {w['feels']}°C)\n"
                f"  🌤 상태: {w['status']}\n"
                f"  🔻 최저: {w['low']}°C  🔺 최고: {w['high']}°C\n"
                f"  💧 습도: {w['humidity']}%  🌧 강수확률: {w['rain']}%\n"
            )
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

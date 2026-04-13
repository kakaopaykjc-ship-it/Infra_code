import requests
from bs4 import BeautifulSoup

url = "https://weather.naver.com/today/1100000000"
headers = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}

res = requests.get(url, headers=headers, timeout=10)
soup = BeautifulSoup(res.text, "html.parser")

def show(label, selector):
    el = soup.select_one(selector)
    print(f"{label}: {el.get_text(strip=True) if el else '없음'}")

def show_all(label, selector):
    els = soup.select(selector)
    print(f"{label} ({len(els)}개):")
    for e in els[:5]:
        print(f"  - {e.get_text(strip=True)[:60]}")

print("=== 기온 ===")
show("i.icon_temperature", "i.icon_temperature")

print("\n=== 날씨 상태 후보 ===")
for cls in ["weather_main", "summary_wrap", "today_weather", "weather_summary",
            "current_weather", "today_info", "status"]:
    el = soup.select_one(f".{cls}")
    if el:
        print(f"  .{cls}: {el.get_text(strip=True)[:60]}")

print("\n=== 최저/최고 기온 후보 ===")
for cls in ["temperature_low", "temperature_high", "lowest", "highest",
            "min_temp", "max_temp", "min", "max"]:
    el = soup.select_one(f".{cls}")
    if el:
        print(f"  .{cls}: {el.get_text(strip=True)[:60]}")

print("\n=== 강수확률 후보 ===")
for cls in ["rainfall", "rain_rate", "precipitation", "rain"]:
    el = soup.select_one(f".{cls}")
    if el:
        print(f"  .{cls}: {el.get_text(strip=True)[:60]}")

print("\n=== is_today 내부 구조 ===")
today = soup.select_one(".is_today")
if today:
    for child in today.find_all(True)[:20]:
        txt = child.get_text(strip=True)
        if txt and len(txt) < 30:
            print(f"  {child.name}.{' '.join(child.get('class', []))}: {txt}")

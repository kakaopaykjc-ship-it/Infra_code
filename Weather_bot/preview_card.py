"""날씨 카드 시안 미리보기 (더미 데이터)"""
from datetime import datetime
from PIL import Image, ImageDraw, ImageFont

# ───────── 색상 팔레트 ─────────
BG = (26, 29, 41)
CARD = (37, 40, 54)
CARD_INNER = (45, 49, 65)
TEXT = (228, 230, 234)
SUB = (142, 144, 153)
ACCENT_WARM = (251, 191, 36)   # 노랑 (맑음/현재기온)
ACCENT_COOL = (96, 165, 250)   # 파랑 (비/물)
ACCENT_HOT = (248, 113, 113)   # 빨강 (폭염/주의)
ACCENT_COLD = (94, 234, 212)   # 청록 (한파)
DIVIDER = (60, 64, 82)

# ───────── 폰트 ─────────
F_REG = "C:/Windows/Fonts/malgun.ttf"
F_BOLD = "C:/Windows/Fonts/malgunbd.ttf"


def font(size, bold=False):
    return ImageFont.truetype(F_BOLD if bold else F_REG, size)


# ───────── 더미 데이터 ─────────
DUMMY = {
    "date": datetime(2026, 5, 4),
    "cities": [
        {
            "name": "서울",
            "temp": 13, "feels": 12, "status": "흐림", "code": 119,
            "low": 12, "high": 23, "humidity": 62, "rain": 0,
            "alerts": ["일교차 큼 (11°C차)"],
            "hourly": [
                {"time": 9, "temp": 13, "rain": 0, "code": 119},
                {"time": 12, "temp": 18, "rain": 0, "code": 116},
                {"time": 15, "temp": 22, "rain": 0, "code": 113},
                {"time": 18, "temp": 19, "rain": 10, "code": 116},
                {"time": 21, "temp": 15, "rain": 30, "code": 119},
            ],
            "weekly": [
                {"label": "화(5/5)", "low": 14, "high": 24, "rain": 10, "code": 116, "status": "구름 조금"},
                {"label": "수(5/6)", "low": 13, "high": 19, "rain": 70, "code": 296, "status": "비"},
            ],
        },
        {
            "name": "군포",
            "temp": 13, "feels": 13, "status": "흐림", "code": 119,
            "low": 12, "high": 21, "humidity": 40, "rain": 0,
            "alerts": [],
            "hourly": [
                {"time": 9, "temp": 13, "rain": 0, "code": 119},
                {"time": 12, "temp": 17, "rain": 0, "code": 119},
                {"time": 15, "temp": 21, "rain": 0, "code": 116},
                {"time": 18, "temp": 18, "rain": 0, "code": 119},
                {"time": 21, "temp": 14, "rain": 20, "code": 119},
            ],
            "weekly": [
                {"label": "화(5/5)", "low": 13, "high": 22, "rain": 0, "code": 113, "status": "맑음"},
                {"label": "수(5/6)", "low": 12, "high": 18, "rain": 60, "code": 296, "status": "비"},
            ],
        },
    ],
}

DAY_KO = ["월", "화", "수", "목", "금", "토", "일"]


# ───────── 날씨 코드별 색상/아이콘 ─────────
def status_color(code):
    if code in (113,):
        return ACCENT_WARM
    if code in (116, 119, 122, 143):
        return SUB
    if code >= 200:  # 비/눈/뇌우
        return ACCENT_COOL
    return TEXT


def draw_weather_icon(draw, x, y, size, code):
    """날씨 코드에 따라 단순한 도형 아이콘을 그린다."""
    cx, cy = x + size // 2, y + size // 2
    r = size // 2 - 2

    if code == 113:  # 맑음 - 태양
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ACCENT_WARM)
        # 햇살
        for i in range(8):
            import math
            ang = i * (math.pi / 4)
            x1 = cx + (r + 3) * math.cos(ang)
            y1 = cy + (r + 3) * math.sin(ang)
            x2 = cx + (r + 7) * math.cos(ang)
            y2 = cy + (r + 7) * math.sin(ang)
            draw.line([x1, y1, x2, y2], fill=ACCENT_WARM, width=2)

    elif code in (116,):  # 구름 조금 - 해+구름
        draw.ellipse([cx - r + 2, cy - r + 2, cx + r - 4, cy + r - 4], fill=ACCENT_WARM)
        draw.ellipse([cx - r + 4, cy - 2, cx + r, cy + r - 2], fill=SUB)

    elif code in (119, 122, 143):  # 흐림 - 구름
        draw.ellipse([cx - r, cy - r // 2, cx + r // 2, cy + r // 2], fill=SUB)
        draw.ellipse([cx - r // 4, cy - r, cx + r, cy + r // 3], fill=(170, 172, 180))

    elif code >= 200:  # 비/눈/뇌우
        draw.ellipse([cx - r, cy - r, cx + r, cy + r // 4], fill=ACCENT_COOL)
        # 빗방울
        for i, dx in enumerate([-r // 2, 0, r // 2]):
            draw.line([cx + dx, cy + r // 3, cx + dx - 3, cy + r],
                      fill=ACCENT_COOL, width=2)
    else:
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=SUB, width=2)


def rounded_rect(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def text_size(draw, text, fnt):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


# ───────── 카드 그리기 ─────────
WIDTH = 640
PAD = 24


def draw_city_card(draw, x, y, w, city):
    """도시 카드 한 개 그리고 차지한 높이를 반환."""
    inner_x = x + 20
    inner_w = w - 40

    # 헤더: 도시명 + 상태 (왼쪽) / 현재기온 + 체감 (오른쪽)
    cy = y + 18
    f_name = font(22, bold=True)
    draw.text((inner_x, cy), city["name"], font=f_name, fill=TEXT)

    # 상태 (도시명 아래)
    f_status = font(14)
    draw_weather_icon(draw, inner_x, cy + 32, 18, city["code"])
    draw.text((inner_x + 26, cy + 30), city["status"], font=f_status, fill=SUB)

    # 현재 기온 (오른쪽 큰 숫자)
    f_temp = font(46, bold=True)
    temp_str = f"{city['temp']}°"
    tw, th = text_size(draw, temp_str, f_temp)
    draw.text((x + w - 24 - tw, cy - 6), temp_str, font=f_temp, fill=ACCENT_WARM)

    # 체감 (큰 기온 아래)
    feels = f"체감 {city['feels']}°"
    f_feels = font(12)
    fw, _ = text_size(draw, feels, f_feels)
    draw.text((x + w - 24 - fw, cy + 44), feels, font=f_feels, fill=SUB)

    cy += 70

    # 통계 4분할: 최저/최고/습도/강수
    stat_y = cy
    stat_w = inner_w // 4
    stats = [
        ("최저", f"{city['low']}°", ACCENT_COOL),
        ("최고", f"{city['high']}°", ACCENT_HOT),
        ("습도", f"{city['humidity']}%", TEXT),
        ("강수", f"{city['rain']}%", ACCENT_COOL if int(city['rain']) >= 30 else SUB),
    ]
    f_label = font(12)
    f_value = font(20, bold=True)
    for i, (label, value, color) in enumerate(stats):
        sx = inner_x + i * stat_w + stat_w // 2
        lw, _ = text_size(draw, label, f_label)
        vw, _ = text_size(draw, value, f_value)
        draw.text((sx - lw // 2, stat_y), label, font=f_label, fill=SUB)
        draw.text((sx - vw // 2, stat_y + 18), value, font=f_value, fill=color)

    cy = stat_y + 50

    # 알림 배지
    if city.get("alerts"):
        f_alert = font(13)
        for alert in city["alerts"]:
            aw, ah = text_size(draw, alert, f_alert)
            badge_h = ah + 10
            rounded_rect(draw, [inner_x, cy, inner_x + aw + 20, cy + badge_h],
                         radius=8, fill=(72, 60, 30))
            draw.text((inner_x + 10, cy + 5), alert, font=f_alert, fill=ACCENT_WARM)
            cy += badge_h + 6
        cy += 4

    # 구분선
    draw.line([inner_x, cy, inner_x + inner_w, cy], fill=DIVIDER, width=1)
    cy += 14

    # 시간별 예보 헤더
    f_h = font(13, bold=True)
    draw.text((inner_x, cy), "시간별", font=f_h, fill=SUB)
    cy += 22

    # 시간별 예보 (가로 배치)
    hourly = city["hourly"]
    col_w = inner_w // len(hourly)
    f_time = font(12)
    f_temp_s = font(15, bold=True)
    f_rain = font(11)

    # 기온 막대 그래프 — min/max 정규화
    temps = [int(h["temp"]) for h in hourly]
    t_min, t_max = min(temps), max(temps)
    t_range = max(t_max - t_min, 1)
    bar_max_h = 28

    for i, h in enumerate(hourly):
        cx = inner_x + i * col_w + col_w // 2

        # 시간
        time_str = f"{h['time']:02d}시"
        tw, _ = text_size(draw, time_str, f_time)
        draw.text((cx - tw // 2, cy), time_str, font=f_time, fill=SUB)

        # 아이콘
        draw_weather_icon(draw, cx - 9, cy + 18, 18, h["code"])

        # 기온
        temp_str = f"{h['temp']}°"
        tw, _ = text_size(draw, temp_str, f_temp_s)
        draw.text((cx - tw // 2, cy + 40), temp_str, font=f_temp_s, fill=TEXT)

        # 막대 (기온 시각화)
        ratio = (int(h["temp"]) - t_min) / t_range
        bh = int(8 + ratio * bar_max_h)
        bx1, bx2 = cx - 12, cx + 12
        by2 = cy + 90
        by1 = by2 - bh
        rounded_rect(draw, [bx1, by1, bx2, by2], radius=4,
                     fill=ACCENT_WARM if int(h["temp"]) >= 20 else ACCENT_COOL)

        # 강수확률
        if h["rain"] >= 20:
            rain_str = f"{h['rain']}%"
            rw, _ = text_size(draw, rain_str, f_rain)
            draw.text((cx - rw // 2, cy + 96), rain_str,
                      font=f_rain, fill=ACCENT_COOL)

    cy += 116

    # 구분선
    draw.line([inner_x, cy, inner_x + inner_w, cy], fill=DIVIDER, width=1)
    cy += 14

    # 주간 예보 헤더
    draw.text((inner_x, cy), "내일·모레", font=f_h, fill=SUB)
    cy += 22

    # 주간 카드 2개
    weekly = city["weekly"]
    wk_w = (inner_w - 12) // len(weekly)
    f_wk_label = font(13, bold=True)
    f_wk_status = font(11)
    f_wk_temp = font(14, bold=True)

    for i, day in enumerate(weekly):
        wx = inner_x + i * (wk_w + 12)
        wy = cy
        rounded_rect(draw, [wx, wy, wx + wk_w, wy + 60], radius=10, fill=CARD_INNER)

        draw.text((wx + 12, wy + 8), day["label"], font=f_wk_label, fill=TEXT)
        draw_weather_icon(draw, wx + wk_w - 32, wy + 8, 22, day["code"])

        draw.text((wx + 12, wy + 28), day["status"], font=f_wk_status, fill=SUB)

        temp_str = f"{day['low']}° / {day['high']}°"
        draw.text((wx + 12, wy + 42), temp_str, font=f_wk_temp, fill=TEXT)

        if day["rain"] >= 30:
            rain_str = f"{day['rain']}%"
            rw, _ = text_size(draw, rain_str, f_wk_status)
            draw.text((wx + wk_w - rw - 12, wy + 44), rain_str,
                      font=f_wk_status, fill=ACCENT_COOL)

    cy += 60 + 20

    return cy - y


def render(data):
    # 임시로 한 번 그려서 전체 높이 계산
    tmp = Image.new("RGB", (WIDTH, 2000), BG)
    d = ImageDraw.Draw(tmp)

    y = 24
    f_title = font(22, bold=True)
    f_date = font(13)
    d.text((PAD, y), "오늘의 날씨", font=f_title, fill=TEXT)
    date_str = f"{data['date'].strftime('%Y.%m.%d')} ({DAY_KO[data['date'].weekday()]})"
    dw, _ = text_size(d, date_str, f_date)
    d.text((WIDTH - PAD - dw, y + 6), date_str, font=f_date, fill=SUB)
    y += 50

    heights = []
    for city in data["cities"]:
        h = draw_city_card(d, PAD, y, WIDTH - PAD * 2, city)
        heights.append(h)
        y += h + 12

    total_h = y + 12

    # 실제 이미지 그리기
    img = Image.new("RGB", (WIDTH, total_h), BG)
    draw = ImageDraw.Draw(img)

    y = 24
    draw.text((PAD, y), "오늘의 날씨", font=f_title, fill=TEXT)
    draw.text((WIDTH - PAD - dw, y + 6), date_str, font=f_date, fill=SUB)
    y += 50

    for city, h in zip(data["cities"], heights):
        # 카드 배경
        rounded_rect(draw, [PAD, y, WIDTH - PAD, y + h - 8], radius=16, fill=CARD)
        draw_city_card(draw, PAD, y, WIDTH - PAD * 2, city)
        y += h + 12

    return img


if __name__ == "__main__":
    img = render(DUMMY)
    img.save("weather_card_preview.png")
    print(f"Saved: weather_card_preview.png ({img.size[0]}x{img.size[1]})")

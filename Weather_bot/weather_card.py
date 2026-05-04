"""날씨 카드 이미지 렌더러.

`render(data)` → PIL.Image 반환.
data 형식:
    {
        "date": datetime,
        "cities": [
            {
                "name": "서울",
                "temp": "13", "feels": "12", "status": "흐림", "code": 119,
                "low": "12", "high": "23",
                "humidity": "62", "rain": 0,
                "alerts": ["일교차 큼 (11°C차)"],
                "hourly": [{"time": 9, "temp": "13", "rain": 0, "code": 119}, ...],
                "weekly": [{"label": "화(5/5)", "low": "14", "high": "24",
                            "rain": 10, "code": 116, "status": "구름 조금"}, ...],
            },
            ...
        ],
    }
"""

import math
import os
from PIL import Image, ImageDraw, ImageFont

# ───────── 색상 팔레트 ─────────
BG = (26, 29, 41)
CARD = (37, 40, 54)
CARD_INNER = (45, 49, 65)
TEXT = (228, 230, 234)
SUB = (142, 144, 153)
ACCENT_WARM = (251, 191, 36)
ACCENT_COOL = (96, 165, 250)
ACCENT_HOT = (248, 113, 113)
ACCENT_COLD = (94, 234, 212)
DIVIDER = (60, 64, 82)

DAY_KO = ["월", "화", "수", "목", "금", "토", "일"]

# ───────── 폰트 자동 탐색 (Windows + Linux) ─────────
_FONT_PATHS = {
    "regular": [
        "C:/Windows/Fonts/malgun.ttf",                                  # Windows
        "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc",     # Rocky/RHEL
        "/usr/share/fonts/google-noto-sans-cjk-vf-fonts/NotoSansCJK-VF.otf.ttc",
        "/usr/share/fonts/nhn-nanum/NanumGothic.ttf",                   # Nanum (Rocky)
        "/usr/share/fonts/nanum/NanumGothic.ttf",
        "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",              # Debian/Ubuntu
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    ],
    "bold": [
        "C:/Windows/Fonts/malgunbd.ttf",
        "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Bold.ttc",
        "/usr/share/fonts/nhn-nanum/NanumGothicBold.ttf",
        "/usr/share/fonts/nanum/NanumGothicBold.ttf",
        "/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    ],
}


def _find_font(kind):
    for p in _FONT_PATHS[kind]:
        if os.path.exists(p):
            return p
    raise FileNotFoundError(
        "한글 폰트를 찾을 수 없습니다. "
        "Rocky: 'sudo dnf install -y google-noto-sans-cjk-fonts' 또는 "
        "'sudo dnf install -y nhn-nanum-fonts'를 설치하세요."
    )


_F_REG = None
_F_BOLD = None


def font(size, bold=False):
    global _F_REG, _F_BOLD
    if bold:
        if _F_BOLD is None:
            _F_BOLD = _find_font("bold")
        return ImageFont.truetype(_F_BOLD, size)
    if _F_REG is None:
        _F_REG = _find_font("regular")
    return ImageFont.truetype(_F_REG, size)


# ───────── 도형 헬퍼 ─────────
def _rounded_rect(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def _text_size(draw, text, fnt):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def _draw_weather_icon(draw, x, y, size, code):
    cx, cy = x + size // 2, y + size // 2
    r = size // 2 - 2

    if code == 113:  # 맑음
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ACCENT_WARM)
        for i in range(8):
            ang = i * (math.pi / 4)
            x1 = cx + (r + 3) * math.cos(ang)
            y1 = cy + (r + 3) * math.sin(ang)
            x2 = cx + (r + 7) * math.cos(ang)
            y2 = cy + (r + 7) * math.sin(ang)
            draw.line([x1, y1, x2, y2], fill=ACCENT_WARM, width=2)

    elif code == 116:  # 구름 조금
        draw.ellipse([cx - r + 2, cy - r + 2, cx + r - 4, cy + r - 4], fill=ACCENT_WARM)
        draw.ellipse([cx - r + 4, cy - 2, cx + r, cy + r - 2], fill=SUB)

    elif code in (119, 122, 143):  # 흐림 / 안개
        draw.ellipse([cx - r, cy - r // 2, cx + r // 2, cy + r // 2], fill=SUB)
        draw.ellipse([cx - r // 4, cy - r, cx + r, cy + r // 3], fill=(170, 172, 180))

    elif code >= 200:  # 비/눈/뇌우
        draw.ellipse([cx - r, cy - r, cx + r, cy + r // 4], fill=ACCENT_COOL)
        for dx in (-r // 2, 0, r // 2):
            draw.line([cx + dx, cy + r // 3, cx + dx - 3, cy + r],
                      fill=ACCENT_COOL, width=2)
    else:
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=SUB, width=2)


# ───────── 카드 그리기 ─────────
WIDTH = 640
PAD = 24


def _draw_city_card(draw, x, y, w, city):
    inner_x = x + 20
    inner_w = w - 40

    # 헤더
    cy = y + 18
    draw.text((inner_x, cy), city["name"], font=font(22, bold=True), fill=TEXT)

    # 상태 (도시명 아래)
    _draw_weather_icon(draw, inner_x, cy + 32, 18, city["code"])
    draw.text((inner_x + 26, cy + 30), city["status"], font=font(14), fill=SUB)

    # 현재 기온 (오른쪽)
    f_temp = font(46, bold=True)
    temp_str = f"{city['temp']}°"
    tw, _ = _text_size(draw, temp_str, f_temp)
    draw.text((x + w - 24 - tw, cy - 6), temp_str, font=f_temp, fill=ACCENT_WARM)

    # 체감
    feels = f"체감 {city['feels']}°"
    fw, _ = _text_size(draw, feels, font(12))
    draw.text((x + w - 24 - fw, cy + 44), feels, font=font(12), fill=SUB)

    cy += 70

    # 4분할 통계
    stat_y = cy
    stat_w = inner_w // 4
    stats = [
        ("최저", f"{city['low']}°", ACCENT_COOL),
        ("최고", f"{city['high']}°", ACCENT_HOT),
        ("습도", f"{city['humidity']}%", TEXT),
        ("강수", f"{city['rain']}%", ACCENT_COOL if int(city['rain']) >= 30 else SUB),
    ]
    for i, (label, value, color) in enumerate(stats):
        sx = inner_x + i * stat_w + stat_w // 2
        lw, _ = _text_size(draw, label, font(12))
        vw, _ = _text_size(draw, value, font(20, bold=True))
        draw.text((sx - lw // 2, stat_y), label, font=font(12), fill=SUB)
        draw.text((sx - vw // 2, stat_y + 18), value,
                  font=font(20, bold=True), fill=color)

    cy = stat_y + 50

    # 알림 배지
    if city.get("alerts"):
        for alert in city["alerts"]:
            aw, ah = _text_size(draw, alert, font(13))
            badge_h = ah + 10
            _rounded_rect(draw, [inner_x, cy, inner_x + aw + 20, cy + badge_h],
                          radius=8, fill=(72, 60, 30))
            draw.text((inner_x + 10, cy + 5), alert, font=font(13), fill=ACCENT_WARM)
            cy += badge_h + 6
        cy += 4

    # 시간별 예보
    if city.get("hourly"):
        draw.line([inner_x, cy, inner_x + inner_w, cy], fill=DIVIDER, width=1)
        cy += 14
        draw.text((inner_x, cy), "시간별", font=font(13, bold=True), fill=SUB)
        cy += 22

        hourly = city["hourly"]
        col_w = inner_w // len(hourly)

        temps = [int(h["temp"]) for h in hourly]
        t_min, t_max = min(temps), max(temps)
        t_range = max(t_max - t_min, 1)
        bar_max_h = 28

        for i, h in enumerate(hourly):
            cx = inner_x + i * col_w + col_w // 2

            # 시간
            time_str = f"{h['time']:02d}시"
            tw, _ = _text_size(draw, time_str, font(12))
            draw.text((cx - tw // 2, cy), time_str, font=font(12), fill=SUB)

            # 아이콘
            _draw_weather_icon(draw, cx - 9, cy + 18, 18, h["code"])

            # 기온
            temp_str = f"{h['temp']}°"
            tw, _ = _text_size(draw, temp_str, font(15, bold=True))
            draw.text((cx - tw // 2, cy + 40), temp_str,
                      font=font(15, bold=True), fill=TEXT)

            # 막대 (기온 시각화)
            ratio = (int(h["temp"]) - t_min) / t_range
            bh = int(8 + ratio * bar_max_h)
            bx1, bx2 = cx - 12, cx + 12
            by2 = cy + 90
            by1 = by2 - bh
            _rounded_rect(draw, [bx1, by1, bx2, by2], radius=4,
                          fill=ACCENT_WARM if int(h["temp"]) >= 20 else ACCENT_COOL)

            # 강수확률
            if h["rain"] >= 20:
                rain_str = f"{h['rain']}%"
                rw, _ = _text_size(draw, rain_str, font(11))
                draw.text((cx - rw // 2, cy + 96), rain_str,
                          font=font(11), fill=ACCENT_COOL)

        cy += 116

    # 주간 예보
    if city.get("weekly"):
        draw.line([inner_x, cy, inner_x + inner_w, cy], fill=DIVIDER, width=1)
        cy += 14
        draw.text((inner_x, cy), "내일·모레", font=font(13, bold=True), fill=SUB)
        cy += 22

        weekly = city["weekly"]
        wk_w = (inner_w - 12) // len(weekly)

        for i, day in enumerate(weekly):
            wx = inner_x + i * (wk_w + 12)
            wy = cy
            _rounded_rect(draw, [wx, wy, wx + wk_w, wy + 60],
                          radius=10, fill=CARD_INNER)
            draw.text((wx + 12, wy + 8), day["label"],
                      font=font(13, bold=True), fill=TEXT)
            _draw_weather_icon(draw, wx + wk_w - 32, wy + 8, 22, day["code"])
            draw.text((wx + 12, wy + 28), day["status"],
                      font=font(11), fill=SUB)
            temp_str = f"{day['low']}° / {day['high']}°"
            draw.text((wx + 12, wy + 42), temp_str,
                      font=font(14, bold=True), fill=TEXT)
            if day["rain"] >= 30:
                rain_str = f"{day['rain']}%"
                rw, _ = _text_size(draw, rain_str, font(11))
                draw.text((wx + wk_w - rw - 12, wy + 44), rain_str,
                          font=font(11), fill=ACCENT_COOL)

        cy += 60 + 20

    return cy - y


def render(data):
    """data dict → PIL.Image"""
    # 1차 패스: 전체 높이 계산
    tmp = Image.new("RGB", (WIDTH, 2000), BG)
    d = ImageDraw.Draw(tmp)

    date_str = (
        f"{data['date'].strftime('%Y.%m.%d')} "
        f"({DAY_KO[data['date'].weekday()]})"
    )

    y = 24 + 50  # 헤더 영역
    heights = []
    for city in data["cities"]:
        h = _draw_city_card(d, PAD, y, WIDTH - PAD * 2, city)
        heights.append(h)
        y += h + 12

    total_h = y + 12

    # 2차 패스: 실제 이미지
    img = Image.new("RGB", (WIDTH, total_h), BG)
    draw = ImageDraw.Draw(img)

    y = 24
    draw.text((PAD, y), "오늘의 날씨", font=font(22, bold=True), fill=TEXT)
    dw, _ = _text_size(draw, date_str, font(13))
    draw.text((WIDTH - PAD - dw, y + 6), date_str, font=font(13), fill=SUB)
    y += 50

    for city, h in zip(data["cities"], heights):
        _rounded_rect(draw, [PAD, y, WIDTH - PAD, y + h - 8],
                      radius=16, fill=CARD)
        _draw_city_card(draw, PAD, y, WIDTH - PAD * 2, city)
        y += h + 12

    return img

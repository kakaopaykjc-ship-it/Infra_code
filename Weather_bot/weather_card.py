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

렌더링은 2배(SS) 슈퍼샘플링 후 LANCZOS 다운스케일로 안티앨리어싱을 적용한다.
드로잉 코드는 모두 '논리 좌표'(1배 기준)로 작성하며, _ScaledDraw 프록시가
좌표·선두께·반지름을 SS배로 확대해 실제 캔버스에 그린다.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFont

# ───────── 슈퍼샘플링 배율 ─────────
SS = 2

# ───────── 색상 팔레트 ─────────
BG = (24, 27, 38)
CARD = (37, 40, 54)
CARD_INNER = (46, 50, 67)
BORDER = (52, 56, 74)
TEXT = (230, 232, 238)
SUB = (140, 144, 156)
ACCENT_WARM = (251, 191, 36)
ACCENT_COOL = (96, 165, 250)
ACCENT_HOT = (248, 113, 113)
ACCENT_COLD = (94, 234, 212)
DIVIDER = (54, 58, 76)
CLOUD = (199, 205, 219)
CLOUD_DARK = (138, 144, 160)
SNOW = (226, 232, 240)

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
    """논리 크기 size의 폰트. 내부적으로 SS배 확대해 슈퍼샘플 캔버스에 맞춘다."""
    global _F_REG, _F_BOLD
    px = int(size * SS)
    if bold:
        if _F_BOLD is None:
            _F_BOLD = _find_font("bold")
        return ImageFont.truetype(_F_BOLD, px)
    if _F_REG is None:
        _F_REG = _find_font("regular")
    return ImageFont.truetype(_F_REG, px)


# ───────── 슈퍼샘플링 프록시 ─────────
class _ScaledDraw:
    """모든 좌표/두께/반지름을 SS배로 확대해 실제 ImageDraw에 위임하는 프록시.

    드로잉 코드는 논리 좌표(1배)로 작성하고, 폰트는 font()가 이미 SS배라
    텍스트는 좌표만 확대하면 된다. _text_size()는 결과를 SS로 나눠 논리 단위로 환산.
    """

    def __init__(self, draw):
        self._d = draw

    @staticmethod
    def _box(xy):
        return [float(v) * SS for v in xy]

    @staticmethod
    def _w(kwargs):
        if "width" in kwargs and kwargs["width"] is not None:
            kwargs["width"] = max(1, int(round(kwargs["width"] * SS)))
        return kwargs

    def text(self, xy, *args, **kwargs):
        self._d.text((xy[0] * SS, xy[1] * SS), *args, **kwargs)

    def line(self, xy, **kwargs):
        self._d.line(self._box(xy), **self._w(kwargs))

    def ellipse(self, xy, **kwargs):
        self._d.ellipse(self._box(xy), **self._w(kwargs))

    def polygon(self, xy, **kwargs):
        self._d.polygon(self._box(xy), **self._w(kwargs))

    def rounded_rectangle(self, xy, radius=0, **kwargs):
        self._d.rounded_rectangle(
            self._box(xy), radius=int(round(radius * SS)), **self._w(kwargs)
        )

    def textbbox(self, xy, *args, **kwargs):
        return self._d.textbbox(xy, *args, **kwargs)


# ───────── 도형/측정 헬퍼 ─────────
def _rounded_rect(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def _text_size(draw, text, fnt):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    return (bbox[2] - bbox[0]) / SS, (bbox[3] - bbox[1]) / SS


# ───────── 날씨 아이콘 ─────────
_SNOW_CODES = {179, 182, 227, 230, 320, 323, 326, 329, 332,
               335, 338, 350, 362, 365, 368, 371, 374, 395}
_THUNDER_CODES = {200, 386, 389, 392}


def _icon_kind(code):
    if code == 113:
        return "sun"
    if code == 116:
        return "partly"
    if code in (119, 122, 143, 248, 260):
        return "cloud"
    if code in _THUNDER_CODES:
        return "thunder"
    if code in _SNOW_CODES:
        return "snow"
    return "rain"  # 나머지 강수 코드


def _icon_sun(draw, cx, cy, r, rays=True, color=ACCENT_WARM):
    if rays:
        wdt = max(1, r * 0.22)
        for i in range(8):
            a = i * math.pi / 4
            draw.line(
                [cx + math.cos(a) * (r + r * 0.40), cy + math.sin(a) * (r + r * 0.40),
                 cx + math.cos(a) * (r + r * 0.95), cy + math.sin(a) * (r + r * 0.95)],
                fill=color, width=wdt,
            )
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def _icon_cloud(draw, cx, cy, s, color=CLOUD):
    draw.ellipse([cx - s * 0.30, cy - s * 0.36, cx + s * 0.30, cy + s * 0.24], fill=color)
    draw.ellipse([cx - s * 0.50, cy - s * 0.16, cx - s * 0.04, cy + s * 0.28], fill=color)
    draw.ellipse([cx + s * 0.08, cy - s * 0.14, cx + s * 0.50, cy + s * 0.28], fill=color)
    draw.rounded_rectangle(
        [cx - s * 0.44, cy + s * 0.02, cx + s * 0.44, cy + s * 0.30],
        radius=s * 0.15, fill=color,
    )


def _icon_partly(draw, cx, cy, s):
    _icon_sun(draw, cx - s * 0.16, cy - s * 0.20, s * 0.24)
    _icon_cloud(draw, cx + s * 0.08, cy + s * 0.12, s * 0.92)


def _icon_rain(draw, cx, cy, s, drop_color=ACCENT_COOL):
    _icon_cloud(draw, cx, cy - s * 0.10, s)
    for dx in (-0.22, 0.0, 0.22):
        x = cx + dx * s
        draw.line([x + s * 0.04, cy + s * 0.30, x - s * 0.04, cy + s * 0.50],
                  fill=drop_color, width=max(1, s * 0.07))


def _icon_snow(draw, cx, cy, s):
    _icon_cloud(draw, cx, cy - s * 0.10, s)
    for dx in (-0.22, 0.0, 0.22):
        x = cx + dx * s
        r = s * 0.055
        draw.ellipse([x - r, cy + s * 0.36 - r, x + r, cy + s * 0.36 + r], fill=SNOW)


def _icon_thunder(draw, cx, cy, s):
    _icon_cloud(draw, cx, cy - s * 0.10, s, color=CLOUD_DARK)
    pts = [
        cx + s * 0.06, cy + s * 0.16,
        cx - s * 0.14, cy + s * 0.40,
        cx + s * 0.00, cy + s * 0.40,
        cx - s * 0.10, cy + s * 0.62,
        cx + s * 0.16, cy + s * 0.32,
        cx + s * 0.02, cy + s * 0.32,
    ]
    draw.polygon(pts, fill=ACCENT_WARM)


def _draw_weather_icon(draw, x, y, size, code):
    cx, cy = x + size / 2, y + size / 2
    kind = _icon_kind(code)
    if kind == "sun":
        _icon_sun(draw, cx, cy, size * 0.32)
    elif kind == "partly":
        _icon_partly(draw, cx, cy, size)
    elif kind == "cloud":
        _icon_cloud(draw, cx, cy, size)
    elif kind == "rain":
        _icon_rain(draw, cx, cy, size)
    elif kind == "snow":
        _icon_snow(draw, cx, cy, size)
    elif kind == "thunder":
        _icon_thunder(draw, cx, cy, size)


# ───────── 카드 그리기 ─────────
WIDTH = 640
PAD = 24


def _draw_city_card(draw, x, y, w, city):
    inner_x = x + 22
    inner_w = w - 44

    # 헤더
    cy = y + 20
    draw.text((inner_x, cy), city["name"], font=font(22, bold=True), fill=TEXT)

    # 상태 (도시명 아래)
    _draw_weather_icon(draw, inner_x, cy + 34, 18, city["code"])
    draw.text((inner_x + 26, cy + 32), city["status"], font=font(14), fill=SUB)

    # 현재 기온 (오른쪽)
    f_temp = font(48, bold=True)
    temp_str = f"{city['temp']}°"
    tw, _ = _text_size(draw, temp_str, f_temp)
    draw.text((x + w - 24 - tw, cy - 8), temp_str, font=f_temp, fill=ACCENT_WARM)

    # 체감
    feels = f"체감 {city['feels']}°"
    fw, _ = _text_size(draw, feels, font(12))
    draw.text((x + w - 24 - fw, cy + 46), feels, font=font(12), fill=SUB)

    cy += 74

    # 4분할 통계
    stat_y = cy
    stat_w = inner_w / 4
    stats = [
        ("최저", f"{city['low']}°", ACCENT_COOL),
        ("최고", f"{city['high']}°", ACCENT_HOT),
        ("습도", f"{city['humidity']}%", TEXT),
        ("강수", f"{city['rain']}%", ACCENT_COOL if int(city['rain']) >= 30 else SUB),
    ]
    for i, (label, value, color) in enumerate(stats):
        sx = inner_x + i * stat_w + stat_w / 2
        if i > 0:  # 칸 구분 세로선
            dx = inner_x + i * stat_w
            draw.line([dx, stat_y + 2, dx, stat_y + 40], fill=DIVIDER, width=1)
        lw, _ = _text_size(draw, label, font(12))
        vw, _ = _text_size(draw, value, font(20, bold=True))
        draw.text((sx - lw / 2, stat_y), label, font=font(12), fill=SUB)
        draw.text((sx - vw / 2, stat_y + 18), value,
                  font=font(20, bold=True), fill=color)

    cy = stat_y + 52

    # 알림 배지
    if city.get("alerts"):
        for alert in city["alerts"]:
            aw, ah = _text_size(draw, alert, font(13))
            badge_h = ah + 12
            _rounded_rect(draw, [inner_x, cy, inner_x + aw + 22, cy + badge_h],
                          radius=badge_h / 2, fill=(66, 55, 28))
            draw.text((inner_x + 11, cy + 6), alert, font=font(13), fill=ACCENT_WARM)
            cy += badge_h + 6
        cy += 4

    # 시간별 예보
    if city.get("hourly"):
        draw.line([inner_x, cy, inner_x + inner_w, cy], fill=DIVIDER, width=1)
        cy += 16
        draw.text((inner_x, cy), "시간별", font=font(13, bold=True), fill=SUB)
        cy += 24

        hourly = city["hourly"]
        col_w = inner_w / len(hourly)

        temps = [int(h["temp"]) for h in hourly]
        t_min, t_max = min(temps), max(temps)
        t_range = max(t_max - t_min, 1)
        bar_max_h = 30

        for i, h in enumerate(hourly):
            cx = inner_x + i * col_w + col_w / 2

            # 시간
            time_str = f"{h['time']:02d}시"
            tw, _ = _text_size(draw, time_str, font(12))
            draw.text((cx - tw / 2, cy), time_str, font=font(12), fill=SUB)

            # 아이콘
            _draw_weather_icon(draw, cx - 11, cy + 18, 22, h["code"])

            # 기온
            temp_str = f"{h['temp']}°"
            tw, _ = _text_size(draw, temp_str, font(15, bold=True))
            draw.text((cx - tw / 2, cy + 44), temp_str,
                      font=font(15, bold=True), fill=TEXT)

            # 막대 (기온 시각화)
            ratio = (int(h["temp"]) - t_min) / t_range
            bh = 8 + ratio * bar_max_h
            bx1, bx2 = cx - 11, cx + 11
            by2 = cy + 96
            by1 = by2 - bh
            _rounded_rect(draw, [bx1, by1, bx2, by2], radius=6,
                          fill=ACCENT_WARM if int(h["temp"]) >= 20 else ACCENT_COOL)

            # 강수확률
            if h["rain"] >= 20:
                rain_str = f"{h['rain']}%"
                rw, _ = _text_size(draw, rain_str, font(11))
                draw.text((cx - rw / 2, cy + 100), rain_str,
                          font=font(11), fill=ACCENT_COOL)

        cy += 122

    # 주간 예보
    if city.get("weekly"):
        draw.line([inner_x, cy, inner_x + inner_w, cy], fill=DIVIDER, width=1)
        cy += 16
        draw.text((inner_x, cy), "내일·모레", font=font(13, bold=True), fill=SUB)
        cy += 24

        weekly = city["weekly"]
        gap = 12
        wk_w = (inner_w - gap * (len(weekly) - 1)) / len(weekly)

        for i, day in enumerate(weekly):
            wx = inner_x + i * (wk_w + gap)
            wy = cy
            _rounded_rect(draw, [wx, wy, wx + wk_w, wy + 62],
                          radius=12, fill=CARD_INNER)
            draw.text((wx + 14, wy + 9), day["label"],
                      font=font(13, bold=True), fill=TEXT)
            _draw_weather_icon(draw, wx + wk_w - 36, wy + 9, 24, day["code"])
            draw.text((wx + 14, wy + 29), day["status"],
                      font=font(11), fill=SUB)
            temp_str = f"{day['low']}° / {day['high']}°"
            draw.text((wx + 14, wy + 43), temp_str,
                      font=font(14, bold=True), fill=TEXT)
            if day["rain"] >= 30:
                rain_str = f"{day['rain']}%"
                rw, _ = _text_size(draw, rain_str, font(11))
                draw.text((wx + wk_w - rw - 14, wy + 45), rain_str,
                          font=font(11), fill=ACCENT_COOL)

        cy += 62 + 20

    return cy - y


def render(data):
    """data dict → PIL.Image (SS배 렌더 후 다운스케일)."""
    date_str = (
        f"{data['date'].strftime('%Y.%m.%d')} "
        f"({DAY_KO[data['date'].weekday()]})"
    )

    # 1차 패스: 전체 높이 계산 (작은 임시 캔버스, 실제 그림은 클리핑되어 버려짐)
    tmp = Image.new("RGB", (8, 8), BG)
    md = _ScaledDraw(ImageDraw.Draw(tmp))

    y = 24 + 56  # 헤더 영역
    heights = []
    for city in data["cities"]:
        h = _draw_city_card(md, PAD, y, WIDTH - PAD * 2, city)
        heights.append(h)
        y += h + 14

    total_h = int(y + 12)

    # 2차 패스: 슈퍼샘플 캔버스에 실제 렌더
    img = Image.new("RGB", (WIDTH * SS, total_h * SS), BG)
    draw = _ScaledDraw(ImageDraw.Draw(img))

    y = 24
    _icon_sun(draw, PAD + 9, y + 13, 9)
    draw.text((PAD + 26, y), "오늘의 날씨", font=font(22, bold=True), fill=TEXT)
    dw, _ = _text_size(draw, date_str, font(13))
    draw.text((WIDTH - PAD - dw, y + 9), date_str, font=font(13), fill=SUB)
    y += 40
    draw.line([PAD, y, WIDTH - PAD, y], fill=DIVIDER, width=1)
    y += 16

    for city, h in zip(data["cities"], heights):
        _rounded_rect(draw, [PAD, y, WIDTH - PAD, y + h - 8],
                      radius=18, fill=CARD, outline=BORDER, width=1)
        _draw_city_card(draw, PAD, y, WIDTH - PAD * 2, city)
        y += h + 14

    # 다운스케일 → 안티앨리어싱
    return img.resize((WIDTH, total_h), Image.LANCZOS)

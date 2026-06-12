"""날씨 카드 이미지 렌더러 (라이트 테마 · 카드뉴스 스타일).

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

디자인 포인트
- 라이트 테마, 흰색 카드 + 부드러운 그림자
- 시간별 기온은 Catmull-Rom 스플라인으로 부드러운 곡선 + 영역 그라데이션
- 2배(SS) 슈퍼샘플링 후 LANCZOS 다운스케일로 안티앨리어싱
"""

import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

# ───────── 슈퍼샘플링 배율 ─────────
SS = 2

# ───────── 색상 팔레트 (라이트) ─────────
BG = (240, 242, 248)
CARD = (255, 255, 255)
INK = (30, 41, 59)        # 진한 네이비 — 제목/기온
INK_SOFT = (71, 85, 105)
SUB = (148, 163, 184)     # 보조 회색
DIVIDER = (230, 234, 240)
COOL = (59, 130, 246)     # 파랑 — 최저
HOT = (239, 68, 68)       # 빨강 — 최고
BADGE_BG = (254, 243, 199)
BADGE_TX = (202, 110, 8)
WEEK_BG = (244, 246, 250)
WEEK_BORDER = (231, 235, 242)
SHADOW = (30, 41, 75)

# 아이콘 색
CLOUD = (189, 199, 216)
CLOUD_DARK = (148, 160, 180)
SUN = (251, 176, 52)
RAIN = (96, 165, 250)
SNOW = (203, 213, 225)

# 곡선 색 (기온 보간)
LINE_COOL = (96, 165, 250)
LINE_WARM = (251, 146, 60)

DAY_KO = ["월", "화", "수", "목", "금", "토", "일"]

# ───────── 레이아웃 상수 (높이 계산 ↔ 그리기 공유) ─────────
WIDTH = 720
PAD = 20
HEADER_BLOCK = 82
BADGE_ROW = 36
BADGE_TRAIL = 4
STATS_BLOCK = 64        # 16(구분선) + 40 + 8
HOURLY_BLOCK = 156      # 26(라벨) + 130(차트)
WEEKLY_BLOCK = 118      # 26(라벨) + 92(카드)
BOTTOM = 22

# ───────── 폰트 자동 탐색 (Windows + Linux) ─────────
_FONT_PATHS = {
    "regular": [
        "C:/Windows/Fonts/malgun.ttf",
        "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/google-noto-sans-cjk-vf-fonts/NotoSansCJK-VF.otf.ttc",
        "/usr/share/fonts/nhn-nanum/NanumGothic.ttf",
        "/usr/share/fonts/nanum/NanumGothic.ttf",
        "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
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
    """논리 크기 size의 폰트 (내부적으로 SS배 확대)."""
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
def _S(v):
    return int(round(v * SS))


class _ScaledDraw:
    """좌표·선두께·반지름을 SS배로 확대해 실제 ImageDraw에 위임."""

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

    def text(self, xy, *a, **k):
        self._d.text((xy[0] * SS, xy[1] * SS), *a, **k)

    def line(self, xy, **k):
        self._d.line(self._box(xy), **self._w(k))

    def ellipse(self, xy, **k):
        self._d.ellipse(self._box(xy), **self._w(k))

    def polygon(self, xy, **k):
        self._d.polygon(self._box(xy), **self._w(k))

    def rounded_rectangle(self, xy, radius=0, **k):
        self._d.rounded_rectangle(self._box(xy), radius=int(round(radius * SS)),
                                  **self._w(k))

    def textbbox(self, xy, *a, **k):
        return self._d.textbbox(xy, *a, **k)


def _text_size(draw, text, fnt):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    return (bbox[2] - bbox[0]) / SS, (bbox[3] - bbox[1]) / SS


def _text_w(draw, text, fnt):
    return _text_size(draw, text, fnt)[0]


# ───────── 이미지 레벨 헬퍼 (그림자·그라데이션) ─────────
def _soft_shadow(img, box, radius, blur=14, color=SHADOW, alpha=40, dy=8):
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([_S(x0), _S(y0 + dy), _S(x1), _S(y1 + dy)],
                        radius=_S(radius), fill=(*color, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(_S(blur)))
    img.alpha_composite(layer)


def _gradient_area(img, curve, baseline_y, color, alpha_top=90):
    """곡선(curve: 논리좌표 점 리스트) 아래 영역을 세로 그라데이션으로 채움."""
    xs = [p[0] for p in curve]
    x0, x1 = min(xs), max(xs)
    top = _S(min(p[1] for p in curve))
    bot = _S(baseline_y)
    if bot <= top:
        return

    grad = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    sx0, sx1 = _S(x0), _S(x1)
    span = bot - top
    for yy in range(top, bot):
        t = (yy - top) / span
        a = int(alpha_top * (1 - t) ** 1.4)
        if a > 0:
            gd.line([(sx0, yy), (sx1, yy)], fill=(*color, a))

    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    poly = [(_S(px), _S(py)) for px, py in curve]
    poly += [(_S(x1), _S(baseline_y)), (_S(x0), _S(baseline_y))]
    md.polygon(poly, fill=255)

    grad.putalpha(ImageChops.multiply(grad.getchannel("A"), mask))
    img.alpha_composite(grad)


# ───────── 곡선 (Catmull-Rom) ─────────
def _catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t +
                  (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                  (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def _smooth(points, samples=18):
    if len(points) < 3:
        return list(points)
    ext = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(len(ext) - 3):
        p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
        for s in range(samples):
            t = s / samples
            out.append((
                _catmull(p0[0], p1[0], p2[0], p3[0], t),
                _catmull(p0[1], p1[1], p2[1], p3[1], t),
            ))
    out.append(points[-1])
    return out


def _temp_color(temp):
    f = max(0.0, min(1.0, (temp - 13) / 8.0))
    return tuple(int(LINE_COOL[i] + (LINE_WARM[i] - LINE_COOL[i]) * f)
                 for i in range(3))


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
    return "rain"


def _icon_sun(draw, cx, cy, r, color=SUN):
    w = max(1, r * 0.24)
    for i in range(8):
        a = i * math.pi / 4
        draw.line([cx + math.cos(a) * (r + r * 0.45), cy + math.sin(a) * (r + r * 0.45),
                   cx + math.cos(a) * (r + r * 1.0), cy + math.sin(a) * (r + r * 1.0)],
                  fill=color, width=w)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def _icon_cloud(draw, cx, cy, s, color=CLOUD):
    draw.ellipse([cx - s * 0.30, cy - s * 0.36, cx + s * 0.30, cy + s * 0.24], fill=color)
    draw.ellipse([cx - s * 0.50, cy - s * 0.16, cx - s * 0.04, cy + s * 0.28], fill=color)
    draw.ellipse([cx + s * 0.08, cy - s * 0.14, cx + s * 0.50, cy + s * 0.28], fill=color)
    draw.rounded_rectangle([cx - s * 0.44, cy + s * 0.02, cx + s * 0.44, cy + s * 0.30],
                           radius=s * 0.15, fill=color)


def _icon_partly(draw, cx, cy, s):
    _icon_sun(draw, cx - s * 0.16, cy - s * 0.20, s * 0.24)
    _icon_cloud(draw, cx + s * 0.08, cy + s * 0.12, s * 0.92)


def _icon_rain(draw, cx, cy, s):
    _icon_cloud(draw, cx, cy - s * 0.10, s, color=CLOUD_DARK)
    for dx in (-0.22, 0.0, 0.22):
        x = cx + dx * s
        draw.line([x + s * 0.04, cy + s * 0.30, x - s * 0.04, cy + s * 0.50],
                  fill=RAIN, width=max(1, s * 0.07))


def _icon_snow(draw, cx, cy, s):
    _icon_cloud(draw, cx, cy - s * 0.10, s, color=CLOUD_DARK)
    for dx in (-0.22, 0.0, 0.22):
        x = cx + dx * s
        r = s * 0.055
        draw.ellipse([x - r, cy + s * 0.36 - r, x + r, cy + s * 0.36 + r], fill=SNOW)


def _icon_thunder(draw, cx, cy, s):
    _icon_cloud(draw, cx, cy - s * 0.10, s, color=CLOUD_DARK)
    pts = [cx + s * 0.06, cy + s * 0.16, cx - s * 0.14, cy + s * 0.40,
           cx + s * 0.00, cy + s * 0.40, cx - s * 0.10, cy + s * 0.62,
           cx + s * 0.16, cy + s * 0.32, cx + s * 0.02, cy + s * 0.32]
    draw.polygon(pts, fill=SUN)


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


# ───────── 높이 계산 ─────────
def _card_height(city):
    h = HEADER_BLOCK
    n = len(city.get("alerts") or [])
    if n:
        h += n * BADGE_ROW + BADGE_TRAIL
    h += STATS_BLOCK
    if city.get("hourly"):
        h += HOURLY_BLOCK
    if city.get("weekly"):
        h += WEEKLY_BLOCK
    h += BOTTOM
    return h


# ───────── 카드 본문 ─────────
def _draw_city_card(draw, img, x, y, w, city):
    inner_x = x + 26
    inner_w = w - 52
    right = x + w - 26

    # ── 헤더 ──
    cy = y + 22
    draw.text((inner_x, cy), city["name"], font=font(22, bold=True), fill=INK)

    _draw_weather_icon(draw, inner_x, cy + 32, 18, city["code"])
    draw.text((inner_x + 25, cy + 31), city["status"], font=font(14), fill=SUB)

    f_temp = font(48, bold=True)
    temp_str = f"{city['temp']}°"
    tw = _text_w(draw, temp_str, f_temp)
    draw.text((right - tw, cy - 6), temp_str, font=f_temp, fill=INK)

    feels = f"체감 {city['feels']}°"
    fw = _text_w(draw, feels, font(12))
    draw.text((right - fw, cy + 46), feels, font=font(12), fill=SUB)

    cy = y + HEADER_BLOCK

    # ── 알림 배지 ──
    for alert in (city.get("alerts") or []):
        aw = _text_w(draw, alert, font(13))
        bh = 26
        draw.rounded_rectangle([inner_x, cy, inner_x + aw + 26, cy + bh],
                               radius=bh / 2, fill=BADGE_BG)
        draw.text((inner_x + 13, cy + 5), alert, font=font(13), fill=BADGE_TX)
        cy += BADGE_ROW
    if city.get("alerts"):
        cy += BADGE_TRAIL

    # ── 4분할 통계 ──
    draw.line([inner_x, cy, inner_x + inner_w, cy], fill=DIVIDER, width=1)
    cy += 16
    stat_w = inner_w / 4
    stats = [
        ("최저", f"{city['low']}°", COOL),
        ("최고", f"{city['high']}°", HOT),
        ("습도", f"{city['humidity']}%", INK),
        ("강수", f"{city['rain']}%", COOL if int(city['rain']) >= 30 else INK),
    ]
    for i, (label, value, color) in enumerate(stats):
        sx = inner_x + i * stat_w + stat_w / 2
        if i > 0:
            dx = inner_x + i * stat_w
            draw.line([dx, cy + 2, dx, cy + 36], fill=DIVIDER, width=1)
        lw = _text_w(draw, label, font(12))
        vw = _text_w(draw, value, font(19, bold=True))
        draw.text((sx - lw / 2, cy), label, font=font(12), fill=SUB)
        draw.text((sx - vw / 2, cy + 18), value, font=font(19, bold=True), fill=color)
    cy = (y + HEADER_BLOCK
          + (len(city.get("alerts") or []) * BADGE_ROW + BADGE_TRAIL
             if city.get("alerts") else 0)
          + STATS_BLOCK)

    # ── 시간별 (곡선 차트) ──
    if city.get("hourly"):
        draw.text((inner_x, cy), "시간별", font=font(13, bold=True), fill=SUB)
        cy += 26

        hourly = city["hourly"]
        n = len(hourly)
        temps = [int(h["temp"]) for h in hourly]
        t_min, t_max = min(temps), max(temps)
        t_range = max(t_max - t_min, 1)

        pad_x = 24
        graph_h = 54
        point_top = cy + 22
        point_bot = point_top + graph_h
        avail = inner_w - pad_x * 2
        xs = [inner_x + pad_x + (avail * i / (n - 1) if n > 1 else avail / 2)
              for i in range(n)]
        ys = [point_bot - (temps[i] - t_min) / t_range * graph_h for i in range(n)]
        pts = list(zip(xs, ys))
        baseline_y = point_bot + 18

        # 영역 그라데이션 (평균 기온 색)
        curve = _smooth(pts)
        avg = sum(temps) / n
        if img is not None:
            _gradient_area(img, curve, baseline_y, _temp_color(avg))

        # 곡선 (구간별 기온 색)
        for i in range(len(curve) - 1):
            x1, y1 = curve[i]
            x2, y2 = curve[i + 1]
            tmid = t_min + (point_bot - (y1 + y2) / 2) / graph_h * t_range
            col = _temp_color(tmid)
            draw.line([x1, y1, x2, y2], fill=col, width=3)
            draw.ellipse([x2 - 1.5, y2 - 1.5, x2 + 1.5, y2 + 1.5], fill=col)

        # 마커 + 라벨
        for i, h in enumerate(hourly):
            px, py = xs[i], ys[i]
            col = _temp_color(temps[i])
            draw.ellipse([px - 5, py - 5, px + 5, py + 5],
                         fill=CARD, outline=col, width=2)
            ts = f"{h['temp']}°"
            tw = _text_w(draw, ts, font(14, bold=True))
            draw.text((px - tw / 2, py - 24), ts, font=font(14, bold=True), fill=INK)

            time_str = f"{h['time']:02d}시"
            tw = _text_w(draw, time_str, font(12))
            draw.text((px - tw / 2, baseline_y + 6), time_str, font=font(12), fill=SUB)
            if h["rain"] >= 20:
                rs = f"{h['rain']}%"
                draw.text((px + tw / 2 + 3, baseline_y + 6), rs,
                          font=font(12, bold=True), fill=COOL)

        cy += 130

    # ── 내일·모레 ──
    if city.get("weekly"):
        draw.text((inner_x, cy), "내일·모레", font=font(13, bold=True), fill=SUB)
        cy += 26

        weekly = city["weekly"]
        gap = 14
        wk_w = (inner_w - gap * (len(weekly) - 1)) / len(weekly)
        for i, day in enumerate(weekly):
            wx = inner_x + i * (wk_w + gap)
            wy = cy
            draw.rounded_rectangle([wx, wy, wx + wk_w, wy + 84], radius=14,
                                   fill=WEEK_BG, outline=WEEK_BORDER, width=1)
            draw.text((wx + 16, wy + 13), day["label"], font=font(13, bold=True), fill=INK)
            draw.text((wx + 16, wy + 33), day["status"], font=font(11), fill=SUB)

            # 최저 / 최고 (색 구분)
            lx = wx + 16
            ly = wy + 51
            seg = [(f"{day['low']}°", COOL), (" / ", SUB), (f"{day['high']}°", HOT)]
            for txt, c in seg:
                draw.text((lx, ly), txt, font=font(14, bold=True), fill=c)
                lx += _text_w(draw, txt, font(14, bold=True))

            if day["rain"] >= 30:
                draw.text((wx + 16, wy + 70), f"강수확률 {day['rain']}%",
                          font=font(11), fill=COOL)

            _draw_weather_icon(draw, wx + wk_w - 46, wy + 28, 30, day["code"])

        cy += 92


# ───────── 진입점 ─────────
def render(data):
    """data dict → PIL.Image."""
    date_str = (f"{data['date'].strftime('%Y.%m.%d')} "
                f"({DAY_KO[data['date'].weekday()]})")

    heights = [_card_height(c) for c in data["cities"]]
    head_h = 24 + 44
    total_h = head_h + sum(h + 20 for h in heights) + 8

    img = Image.new("RGBA", (WIDTH * SS, total_h * SS), (*BG, 255))
    draw = _ScaledDraw(ImageDraw.Draw(img))

    # 헤더
    y = 26
    draw.ellipse([PAD + 4, y + 5, PAD + 14, y + 15], fill=SUN)
    draw.text((PAD + 24, y), "오늘의 날씨", font=font(21, bold=True), fill=INK)
    dw = _text_w(draw, date_str, font(13))
    draw.text((WIDTH - PAD - dw, y + 6), date_str, font=font(13), fill=SUB)
    y = head_h

    for city, h in zip(data["cities"], heights):
        box = [PAD, y, WIDTH - PAD, y + h]
        _soft_shadow(img, box, radius=22)
        draw.rounded_rectangle(box, radius=22, fill=CARD)
        _draw_city_card(draw, img, PAD, y, WIDTH - PAD * 2, city)
        y += h + 20

    return img.convert("RGB").resize((WIDTH, total_h), Image.LANCZOS)

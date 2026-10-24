"""水上機 C-130 のテクスチャを作る（普通の Python：numpy・Pillow。Blender は使わない）。

  python assets/vehicles/floatplane_c130/source/make_textures.py

出力：assets/vehicles/floatplane_c130/textures/
  fp_quilt_*        機内の断熱材（灰緑のキルティング布。1 枚 0.5 m。横の縫い目は形のふくらみの列と同じ 0.5 m ごと）
  fp_floor_*        貨物室の床（アルミの板。1 枚 1.0 m。継ぎ目と皿ねじ、すり傷、汚れ）
  fp_tread_normal   段の縞鋼板（1 枚 0.30 m）
  fp_paint_*        外板のパネルの線とリベット（1 枚 2.0 m。三方向から貼る）
  fp_webbing_normal 座席のベルトの織り目（1 枚 0.10 m）
  fp_fabric_normal  座面の布の織り目（1 枚 0.20 m）
  fp_decals.png / fp_decals.json   ステンシル・表示の文字（RGBA のアトラス。json は UV の領域、左下が原点）
  fp_panel.png / fp_panel.json     操縦席の計器・画面・スイッチの盤面（アトラス）
法線は OpenGL の向き（緑が上）。Godot の StandardMaterial3D／fp_surface.gdshader の normal にそのまま使える。
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "textures"
FONT = "C:/Windows/Fonts/bahnschrift.ttf"
FONT_BOLD = "C:/Windows/Fonts/arialbd.ttf"
RNG = np.random.default_rng(130)


# ---------------------------------------------------------------- 道具

def save_rgb(arr, name):
    OUT.mkdir(parents=True, exist_ok=True)
    img = Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8))
    img.save(OUT / name)


def tile_noise(n, period, octaves=4, seed=0):
    """つなぎ目の出ない値ノイズ（0〜1）。周期 period（画素）から 1/2 ずつ細かく octaves 段。"""
    rng = np.random.default_rng(seed)
    acc = np.zeros((n, n))
    amp, total = 1.0, 0.0
    p = float(period)
    for _ in range(octaves):
        cells = max(2, int(round(n / p)))
        grid = rng.random((cells, cells))
        c = np.arange(n) / n * cells
        i0 = np.floor(c).astype(int)
        f = c - i0
        f = f * f * (3 - 2 * f)
        i1 = (i0 + 1) % cells
        i0 = i0 % cells
        v00, v01 = grid[np.ix_(i0, i0)], grid[np.ix_(i0, i1)]
        v10, v11 = grid[np.ix_(i1, i0)], grid[np.ix_(i1, i1)]
        fx, fy = f[None, :], f[:, None]
        acc += amp * ((v00 * (1 - fx) + v01 * fx) * (1 - fy) + (v10 * (1 - fx) + v11 * fx) * fy)
        total += amp
        amp *= 0.5
        p = max(2.0, p / 2)
    return acc / total


def height_to_normal(h, strength):
    """高さ（0〜1、つなぎ目なし）から法線（0〜1 の RGB、OpenGL の向き）。"""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    nx, ny, nz = -dx, dy, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5


def blur(a, r):
    k = np.exp(-0.5 * (np.arange(-3 * r, 3 * r + 1) / r) ** 2)
    k /= k.sum()
    out = a.copy()
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for i, w in enumerate(k):
            acc += w * np.roll(out, i - 3 * r, axis=axis)
        out = acc
    return out


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


# ---------------------------------------------------------------- 断熱材（キルティング）

def quilt(n=1024):
    y, x = np.mgrid[0:n, 0:n] / n
    # ふくらみ（タイルの縁で 0、真ん中で 1）＋縫い目のくぼみ
    puff = (np.sin(np.pi * x) ** 0.5) * (np.sin(np.pi * y) ** 0.5)
    seam = np.exp(-((np.minimum(y, 1 - y)) / 0.010) ** 2) + np.exp(-((np.minimum(x, 1 - x)) / 0.010) ** 2)
    # 縫い目のミシン目（点線）
    stitch_y = np.exp(-((np.minimum(y, 1 - y) - 0.028) / 0.004) ** 2) * (np.sin(x * n * 0.55) > 0.2)
    stitch_x = np.exp(-((np.minimum(x, 1 - x) - 0.028) / 0.004) ** 2) * (np.sin(y * n * 0.55) > 0.2)
    weave = (np.sin(x * n * 1.9 + y * n * 1.9) * 0.5 + 0.5) * 0.35 + (np.sin(x * n * 1.9 - y * n * 1.9) * 0.5 + 0.5) * 0.35
    wrinkles = tile_noise(n, 96, 4, seed=3)
    h = 0.55 * puff - 0.45 * np.clip(seam, 0, 1) - 0.10 * (stitch_x + stitch_y) + 0.020 * weave + 0.10 * (wrinkles - 0.5)
    base = hexrgb("#9CA38F")
    tint = (tile_noise(n, 256, 3, seed=5) - 0.5) * 0.10
    shade = 0.88 + 0.16 * puff - 0.30 * np.clip(seam, 0, 1) - 0.12 * (stitch_x + stitch_y) + 0.03 * weave
    alb = base[None, None, :] * (shade + tint)[..., None]
    alb[..., 2] *= 0.98
    save_rgb(alb, "fp_quilt_albedo.png")
    save_rgb(height_to_normal(h, 9.0), "fp_quilt_normal.png")


# ---------------------------------------------------------------- 床（アルミの板）

def floor(n=1024):
    y, x = np.mgrid[0:n, 0:n] / n
    seam = np.exp(-((np.minimum(y, 1 - y)) / 0.0025) ** 2) + np.exp(-((np.minimum(x, 1 - x)) / 0.0025) ** 2)
    seam = np.clip(seam, 0, 1)
    h = np.full((n, n), 0.5) - 0.5 * seam
    # 皿ねじ（継ぎ目から 1.5 cm、10 cm ごと）
    screws = np.zeros((n, n))
    for t in np.arange(0.05, 1.0, 0.1):
        for cx, cy in ((t, 0.015), (t, 0.985), (0.015, t), (0.985, t)):
            d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            screws = np.maximum(screws, np.clip(1 - d / 0.0045, 0, 1))
    h -= 0.25 * screws
    # すり傷とへこみ
    img = Image.new("L", (n, n), 0)
    dr = ImageDraw.Draw(img)
    for _ in range(260):
        x0, y0 = RNG.random() * n, RNG.random() * n
        ang = RNG.normal(0.0, 0.25) + (math.pi / 2 if RNG.random() < 0.3 else 0)
        ln = RNG.random() ** 2 * n * 0.25
        dr.line([(x0, y0), (x0 + math.cos(ang) * ln, y0 + math.sin(ang) * ln)], fill=int(60 + RNG.random() * 120), width=1)
    scratch = np.asarray(img, dtype=np.float64) / 255
    h -= 0.06 * scratch
    brushed = blur(RNG.random((n, n)), 1)
    brushed = np.roll(brushed, 0, axis=0)
    dirt = tile_noise(n, 180, 4, seed=11)
    base = hexrgb("#8B9096")
    shade = 0.92 + 0.10 * (brushed - 0.5) - 0.35 * seam - 0.25 * screws + 0.10 * scratch - 0.22 * np.clip(dirt - 0.45, 0, 1)
    alb = base[None, None, :] * shade[..., None]
    rough = 0.48 + 0.25 * np.clip(dirt - 0.4, 0, 1) - 0.20 * scratch + 0.15 * seam
    save_rgb(alb, "fp_floor_albedo.png")
    save_rgb(height_to_normal(h, 5.0), "fp_floor_normal.png")
    save_rgb(np.repeat(np.clip(rough, 0, 1)[..., None], 3, axis=-1), "fp_floor_rough.png")


def tread(n=512):
    """縞鋼板（ダイヤの粒を斜め 2 方向に）。1 枚 0.30 m。"""
    y, x = np.mgrid[0:n, 0:n] / n
    h = np.zeros((n, n))
    k = 8
    for cx in range(k):
        for cy in range(k):
            px, py = (cx + 0.5 * (cy % 2)) / k, (cy + 0.5) / k
            ang = math.radians(45 if (cx + cy) % 2 == 0 else -45)
            dx, dy = (x - px + 0.5) % 1 - 0.5, (y - py + 0.5) % 1 - 0.5
            u = dx * math.cos(ang) + dy * math.sin(ang)
            v = -dx * math.sin(ang) + dy * math.cos(ang)
            h = np.maximum(h, np.clip(1 - (u / 0.045) ** 2 - (v / 0.010) ** 2, 0, 1))
    save_rgb(height_to_normal(h, 8.0), "fp_tread_normal.png")


# ---------------------------------------------------------------- 外板（パネルの線・リベット）

def paint(n=1024):
    """2.0 m 四方。継ぎ目は 0.5〜1.0 m のばらばらの間隔、リベットは継ぎ目にそって 25 mm ごと。"""
    px = n / 2.0   # 1 m の画素
    img_h = Image.new("F", (n, n), 0.0)
    seams = Image.new("L", (n, n), 0)
    dr = ImageDraw.Draw(seams)
    xs = [0.0, 0.62, 1.15, 1.58, 2.0]
    ys = [0.0, 0.48, 1.05, 1.52, 2.0]
    for xv in xs:
        dr.line([(xv * px, 0), (xv * px, n)], fill=255, width=2)
    for yv in ys:
        dr.line([(0, yv * px), (n, yv * px)], fill=255, width=2)
    # 点検ぶた（小さな四角）
    for (ax, ay, aw, ah) in ((0.20, 0.12, 0.28, 0.22), (1.30, 1.18, 0.20, 0.18), (0.80, 1.62, 0.32, 0.20)):
        dr.rectangle([ax * px, ay * px, (ax + aw) * px, (ay + ah) * px], outline=255, width=2)
    seam = np.asarray(seams, dtype=np.float64) / 255
    seam = blur(seam, 1)
    rivet = np.zeros((n, n))
    y, x = np.mgrid[0:n, 0:n] / px
    pitch = 0.025
    for xv in xs:
        for off in (-0.012, 0.012):
            cx = (xv + off) % 2.0
            d = np.abs(((x - cx) + 1.0) % 2.0 - 1.0)
            ring = np.clip(1 - d / 0.0028, 0, 1) * np.clip(1 - np.abs(((y % pitch) - pitch / 2)) / 0.0028, 0, 1)
            rivet = np.maximum(rivet, ring)
    for yv in ys:
        for off in (-0.012, 0.012):
            cy = (yv + off) % 2.0
            d = np.abs(((y - cy) + 1.0) % 2.0 - 1.0)
            ring = np.clip(1 - d / 0.0028, 0, 1) * np.clip(1 - np.abs(((x % pitch) - pitch / 2)) / 0.0028, 0, 1)
            rivet = np.maximum(rivet, ring)
    oil = tile_noise(n, 220, 4, seed=21)
    h = 0.5 - 0.6 * seam + 0.25 * rivet + 0.02 * (oil - 0.5)
    rough = 0.30 + 0.10 * (oil - 0.5) + 0.20 * seam
    save_rgb(height_to_normal(h, 3.5), "fp_paint_normal.png")
    save_rgb(np.repeat(np.clip(rough, 0, 1)[..., None], 3, axis=-1), "fp_paint_rough.png")
    # 2026-10-22：色に掛ける倍率（1 が元の色）。パネルごとの色むら（塗り直した板・ロットの違い）、継ぎ目とリベットのくすみ、
    # 薄い汚れのむら、継ぎ目から下へ垂れるすじ。三方向から貼るので、横の面では絵の縦が上下になる
    rng = np.random.default_rng(2210)
    tone = np.ones((n, n))
    xb = np.searchsorted(np.array(xs[1:-1]) * px, np.arange(n), side="right")
    yb = np.searchsorted(np.array(ys[1:-1]) * px, np.arange(n), side="right")
    cell = rng.uniform(0.955, 1.0, size=(len(ys) - 1, len(xs) - 1))
    tone = cell[yb[:, None], xb[None, :]]
    blot = tile_noise(n, 300, 5, seed=41)
    streak_src = blur(np.clip(seam * 2.0, 0, 1), 2) * (tile_noise(n, 48, 2, seed=43) > 0.55)
    streak = np.zeros((n, n))
    acc = np.zeros(n)
    for row in range(n):                 # 下へ垂れる（画素の y が増える向き）
        acc = np.maximum(acc * 0.985, streak_src[row])
        streak[row] = acc
    streak = blur(streak, 1) * (0.5 + 0.5 * tile_noise(n, 24, 2, seed=44))
    mul = tone * (1 - 0.20 * seam) * (1 - 0.08 * rivet) * (1 - 0.05 * np.clip(blot - 0.45, 0, 1) * 2) * (1 - 0.035 * streak)
    save_rgb(np.repeat(np.clip(mul, 0, 1)[..., None], 3, axis=-1), "fp_paint_albedo.png")


def webbing(n=256):
    y, x = np.mgrid[0:n, 0:n] / n
    h = 0.5 + 0.5 * np.sin(y * 2 * np.pi * 24) * (0.6 + 0.4 * np.sin(x * 2 * np.pi * 6))
    h += 0.25 * np.sin(x * 2 * np.pi * 48 + np.sin(y * 2 * np.pi * 24) * 2)
    save_rgb(height_to_normal(h / 1.5, 2.5), "fp_webbing_normal.png")


def fabric(n=256):
    y, x = np.mgrid[0:n, 0:n] / n
    h = 0.5 + 0.25 * np.sin(x * 2 * np.pi * 40) * np.sin(y * 2 * np.pi * 40) + 0.15 * (tile_noise(n, 32, 3, seed=8) - 0.5)
    save_rgb(height_to_normal(h, 3.0), "fp_fabric_normal.png")


# ---------------------------------------------------------------- 文字のアトラス

DECALS = [
    # 名前, 文字, 文字の色, 下地, 幅（m）, 高さ（m）
    ("ls", None, "#1E1F1C", None, 0.30, 0.12),
    ("exit", "EMERGENCY EXIT", "#1E1F1C", "#F2C230", 0.46, 0.10),
    ("fire", "FIRE EXTINGUISHER", "#C8352B", None, 0.40, 0.06),
    ("firstaid", "FIRST AID KIT", "#F4F4F0", "#3B6B3A", 0.36, 0.08),
    ("oxygen", "OXYGEN", "#2E6B3A", "#F4F4F0", 0.22, 0.07),
    ("jump", "CAUTION  JUMP DOOR", "#1E1F1C", "#F2C230", 0.60, 0.08),
    ("seat", "TROOP SEAT  MAX 4", "#1E1F1C", None, 0.34, 0.05),
    ("nostep", "NO STEP", "#1E1F1C", None, 0.40, 0.10),
    ("walk", "WALKWAY", "#1E1F1C", None, 0.40, 0.10),
    ("rescue", "RESCUE", "#E8E8E2", "#C8352B", 0.40, 0.12),
    ("prop", "DANGER  PROPELLER", "#E8E8E2", "#C8352B", 1.10, 0.10),
    ("reg", "TQ-130", "#F4F5F2", None, 1.20, 0.38),
    ("unit", "TESTOPIA SKY RESCUE", "#F4F5F2", None, 2.40, 0.22),
    ("ramp", "RAMP  -  KEEP CLEAR", "#1E1F1C", "#F2C230", 0.90, 0.08),
    ("door", "PUSH TO OPEN", "#1E1F1C", None, 0.30, 0.05),
]
LS_NUMBERS = list(range(410, 950, 30))


def decals(w=2048, h=2048):
    """RGBA のアトラス。ls は番号ごとに 1 マス。json は名前 → [u0, v0, u1, v1]（左下が原点）。"""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    regions = {}
    cell_h = 96
    x, y = 8, 8
    row_h = 0
    items = []
    for name, text, fg, bg, mw, mh in DECALS:
        if name == "ls":
            for num in LS_NUMBERS:
                items.append((f"ls{num}", f"LS {num}", fg, bg, mw, mh))
        else:
            items.append((name, text, fg, bg, mw, mh))
    for name, text, fg, bg, mw, mh in items:
        ph = cell_h if mh < 0.2 else 200
        pw = int(ph * mw / mh)
        if x + pw > w - 8:
            x = 8
            y += row_h + 12
            row_h = 0
        box = (x, y, x + pw, y + ph)
        if bg:
            dr.rounded_rectangle(box, radius=int(ph * 0.12), fill=bg)
        size = int(ph * (0.62 if bg else 0.80))
        font = ImageFont.truetype(FONT, size)
        room = pw * (0.70 if name == "rescue" else 0.94)
        while font.getlength(text) > room and size > 8:
            size -= 2
            font = ImageFont.truetype(FONT, size)
        tw = font.getlength(text)
        bb = font.getbbox(text)
        th = bb[3] - bb[1]
        tx = x + (pw * (0.80 if name == "rescue" else 1.0) - tw) / 2
        dr.text((tx, y + (ph - th) / 2 - bb[1]), text, font=font, fill=fg)
        if name.startswith("ls"):
            # 番号の左に黄色い矢じり（実機の位置の印）
            dr.polygon([(x + 4, y + ph * 0.8), (x + 4 + ph * 0.25, y + ph * 0.8), (x + 4, y + ph * 0.55)], fill="#E8B21E")
        if name == "rescue":
            dr.polygon([(x + pw - ph * 0.6, y + ph * 0.2), (x + pw - ph * 0.15, y + ph * 0.5), (x + pw - ph * 0.6, y + ph * 0.8)], fill=fg)
        regions[name] = [box[0] / w, 1 - box[3] / h, box[2] / w, 1 - box[1] / h]
        x += pw + 12
        row_h = max(row_h, ph)
    # 少しかすれさせる（ステンシルの吹き付け）
    a = np.asarray(img).astype(np.float64)
    grain = RNG.random((h, w))
    a[..., 3] *= np.clip(0.80 + 0.35 * grain, 0, 1)
    Image.fromarray(a.astype(np.uint8), "RGBA").save(OUT / "fp_decals.png")
    (OUT / "fp_decals.json").write_text(json.dumps({"size": [w, h], "regions": regions, "items": {n: [mw, mh] for n, _, _, _, mw, mh in items}},
                                                   ensure_ascii=False, indent=1), encoding="utf-8")
    return regions


# ---------------------------------------------------------------- 操縦席の盤面

def _dial(dr, cx, cy, r, kind, font):
    dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill="#111316", outline="#5A5F66", width=max(2, r // 18))
    if kind == "adi":
        dr.pieslice([cx - r * 0.86, cy - r * 0.86, cx + r * 0.86, cy + r * 0.86], 180, 360, fill="#2F7FC8")
        dr.pieslice([cx - r * 0.86, cy - r * 0.86, cx + r * 0.86, cy + r * 0.86], 0, 180, fill="#7A5230")
        dr.line([cx - r * 0.86, cy, cx + r * 0.86, cy], fill="#F4F4F0", width=3)
        for k in (-2, -1, 1, 2):
            yy = cy + k * r * 0.16
            dr.line([cx - r * 0.18, yy, cx + r * 0.18, yy], fill="#F4F4F0", width=2)
        dr.line([cx - r * 0.5, cy, cx - r * 0.15, cy], fill="#F2C230", width=5)
        dr.line([cx + r * 0.15, cy, cx + r * 0.5, cy], fill="#F2C230", width=5)
        return
    n_ticks = 36 if kind in ("hsi", "alt") else 24
    for i in range(n_ticks):
        a = 2 * math.pi * i / n_ticks
        big = i % 3 == 0
        r0 = r * (0.74 if big else 0.82)
        dr.line([cx + math.sin(a) * r0, cy - math.cos(a) * r0, cx + math.sin(a) * r * 0.9, cy - math.cos(a) * r * 0.9], fill="#E8E8E2", width=3 if big else 1)
    if kind == "hsi":
        for i, lab in enumerate(["N", "3", "6", "E", "12", "15", "S", "21", "24", "W", "30", "33"]):
            a = 2 * math.pi * i / 12
            dr.text((cx + math.sin(a) * r * 0.58, cy - math.cos(a) * r * 0.58), lab, font=font, fill="#E8E8E2", anchor="mm")
        dr.polygon([(cx, cy - r * 0.5), (cx - r * 0.08, cy + r * 0.3), (cx + r * 0.08, cy + r * 0.3)], fill="#F2A51E")
    else:
        for i in range(0, 10, 1 if kind == "alt" else 2):
            a = 2 * math.pi * i / 10
            dr.text((cx + math.sin(a) * r * 0.58, cy - math.cos(a) * r * 0.58), str(i), font=font, fill="#E8E8E2", anchor="mm")
        a = RNG.random() * 2 * math.pi
        dr.line([cx, cy, cx + math.sin(a) * r * 0.78, cy - math.cos(a) * r * 0.78], fill="#F4F4F0", width=max(3, r // 14))
        dr.ellipse([cx - r * 0.07, cy - r * 0.07, cx + r * 0.07, cy + r * 0.07], fill="#2A2D33")
    if kind == "eng":
        dr.arc([cx - r * 0.86, cy - r * 0.86, cx + r * 0.86, cy + r * 0.86], 200, 280, fill="#3BC45A", width=6)
        dr.arc([cx - r * 0.86, cy - r * 0.86, cx + r * 0.86, cy + r * 0.86], 280, 320, fill="#E8C21E", width=6)
        dr.arc([cx - r * 0.86, cy - r * 0.86, cx + r * 0.86, cy + r * 0.86], 320, 335, fill="#D8352B", width=6)


def panel_v1(w=2048, h=1024):
    """2026-10-18 の版（使っていない。panel() が 2026-10-22 の版）。"""
    img = Image.new("RGB", (w, h), "#2B2F35")
    dr = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, 22)
    small = ImageFont.truetype(FONT, 14)
    regions = {}
    # 1) 計器盤（上の半分の左）：大きな計器 6 + 小さな計器 8 + 画面 2 + 警告灯
    px0, py0, pw, ph = 0, 0, 1536, 512
    dr.rectangle([px0, py0, px0 + pw, py0 + ph], fill="#30343A")
    kinds = ["spd", "adi", "alt", "eng", "hsi", "vsi"]
    for i, k in enumerate(kinds):
        cx = 140 + i * 250 if i < 3 else 140 + (i - 3) * 250 + 780
        _dial(dr, cx, 150, 100, k, font)
    for i in range(8):
        _dial(dr, 120 + i * 110 + (0 if i < 4 else 600), 380, 46, "eng", small)
    for j, sx in enumerate((790, 1010)):
        dr.rectangle([sx - 0, 40, sx + 190, 270], fill="#081215", outline="#5A5F66", width=4)
        for k in range(9):
            yy = 60 + k * 22
            ln = 60 + RNG.random() * 110
            dr.line([sx + 14, yy, sx + 14 + ln, yy], fill="#3EE07A" if j == 0 else "#55D6F2", width=4)
        dr.text((sx + 95, 250), "MFD " + str(j + 1), font=small, fill="#55D6F2", anchor="mm")
    for k in range(10):
        c = ["#D8352B", "#E8C21E", "#3BC45A", "#E8C21E", "#2A2D33"][k % 5]
        dr.rectangle([820 + k * 36, 300, 848 + k * 36, 324], fill=c, outline="#111316")
    regions["dash"] = [px0 / w, 1 - (py0 + ph) / h, (px0 + pw) / w, 1 - py0 / h]
    # 2) 天井の盤（下の半分の左）：スイッチの列と表示
    ox, oy, ow, oh = 0, 512, 1024, 512
    dr.rectangle([ox, oy, ox + ow, oy + oh], fill="#2A2E33")
    for r_ in range(5):
        for c in range(12):
            x0 = ox + 40 + c * 80
            y0 = oy + 40 + r_ * 95
            dr.rectangle([x0 - 22, y0 - 4, x0 + 22, y0 + 50], outline="#6A7078", width=2)
            dr.rectangle([x0 - 5, y0 + 4, x0 + 5, y0 + 40], fill="#C9CDD1")
            dr.text((x0, y0 + 62), ["FUEL", "BLEED", "GEN", "BUS", "PUMP", "ICE"][(r_ + c) % 6], font=small, fill="#E8E8E2", anchor="mm")
    regions["overhead"] = [ox / w, 1 - (oy + oh) / h, (ox + ow) / w, 1 - oy / h]
    # 3) 横の台（スロットルの周り）
    cx_, cy_, cw, ch = 1024, 512, 512, 512
    dr.rectangle([cx_, cy_, cx_ + cw, cy_ + ch], fill="#2B2F35")
    for i in range(4):
        x0 = cx_ + 70 + i * 110
        dr.rectangle([x0 - 14, cy_ + 60, x0 + 14, cy_ + 440], fill="#15171A")
        for t in range(9):
            yy = cy_ + 70 + t * 42
            dr.line([x0 - 30, yy, x0 - 18, yy], fill="#E8E8E2", width=2)
        dr.text((x0, cy_ + 470), f"ENG {i + 1}", font=small, fill="#E8E8E2", anchor="mm")
    regions["console"] = [cx_ / w, 1 - (cy_ + ch) / h, (cx_ + cw) / w, 1 - cy_ / h]
    # 4) 右上：小さな盤（ボタンと画面）
    bx, by, bw, bh = 1536, 0, 512, 512
    dr.rectangle([bx, by, bx + bw, by + bh], fill="#2E3238")
    for r_ in range(6):
        for c in range(6):
            col = ["#2A2D33", "#3BC45A", "#E8C21E", "#2A2D33", "#55D6F2", "#2A2D33"][(r_ * 2 + c) % 6]
            dr.rounded_rectangle([bx + 30 + c * 80, by + 30 + r_ * 78, bx + 90 + c * 80, by + 80 + r_ * 78], radius=6, fill=col, outline="#111316")
    regions["buttons"] = [bx / w, 1 - (by + bh) / h, (bx + bw) / w, 1 - by / h]
    img = img.filter(ImageFilter.SMOOTH)
    img.save(OUT / "fp_panel.png")
    (OUT / "fp_panel.json").write_text(json.dumps({"size": [w, h], "regions": regions}, indent=1), encoding="utf-8")


# ---------------------------------------------------------------- 操縦席の盤面（2026-10-22 の版）
# C-130J のようなグラスコックピット。各領域は実寸（m）で描き、2 倍で描いて縮める（線がなめらか）。
# アルファは光る所（画面・灯）。座標の約束：領域ごとに左下が原点（x 右・y 上、m）。
#   dash       計器盤の面（パイロットから見て左 → 右、下 → 上。幅 1.86・面の長さ 0.671）
#   overhead   天井の盤（左 → 右、上が機首の側）
#   console_r  右の台の上（スロットル。左が内側、上が機首の側）  console_l  左の台の上（無線。左が外側、上が機首の側）
#   mcp        日よけのひさしの後ろの面（自動操縦の盤）  cb  遮断器の盤（壁）  misc  壁の小さな盤（酸素・インターホン）
# fp_panel.json の items に、立体の縁・つまみ・レバーを置く位置（m）を書く（fp_cockpit.py が読む）。
PANEL_W, PANEL_H = 4096, 2048
PANEL_REGIONS = {
    "dash": ((0, 0, 3072, 1024), (1.86, 0.671)),
    "overhead": ((0, 1024, 1024, 2048), (0.80, 0.72)),
    "console_r": ((1024, 1024, 1536, 2048), (0.40, 1.00)),
    "console_l": ((1536, 1024, 2048, 2048), (0.40, 1.00)),
    "mcp": ((2048, 1024, 4096, 1280), (0.90, 0.11)),
    "cb": ((2048, 1280, 4096, 2048), (0.90, 0.34)),
    "misc": ((3072, 0, 4096, 1024), (0.40, 0.40)),
}
SS = 2
PANEL_BG = "#2A2E34"
INK = "#E6E7E1"
AMBER, GREEN, CYAN, MAGENTA, RED = "#F2B21E", "#3EE07A", "#55D6F2", "#E85AE0", "#E8392E"


class Cv:
    """領域のキャンバス（実寸 m、左下が原点）。"""

    def __init__(self, name, bg=PANEL_BG):
        (x0, y0, x1, y1), (wm, hm) = PANEL_REGIONS[name]
        self.box = (x0, y0, x1, y1)
        self.wpx, self.hpx = (x1 - x0) * SS, (y1 - y0) * SS
        self.wm, self.hm = wm, hm
        self.sx, self.sy = self.wpx / wm, self.hpx / hm
        self.img = Image.new("RGB", (self.wpx, self.hpx), bg)
        self.mask = Image.new("L", (self.wpx, self.hpx), 0)
        self.dr = ImageDraw.Draw(self.img)
        self.dm = ImageDraw.Draw(self.mask)

    def p(self, x, y):
        return (x * self.sx, (self.hm - y) * self.sy)

    def r(self, x0, y0, x1, y1):
        (a, b), (c, d) = self.p(x0, y1), self.p(x1, y0)
        return [a, b, c, d]

    def font(self, h_m, bold=False):
        return ImageFont.truetype(FONT_BOLD if bold else FONT, max(6, int(h_m * self.sy)))

    def text(self, x, y, s, h_m, fill=INK, anchor="mm", bold=False, glow=False):
        f = self.font(h_m, bold)
        self.dr.text(self.p(x, y), s, font=f, fill=fill, anchor=anchor)
        if glow:
            self.dm.text(self.p(x, y), s, font=f, fill=255, anchor=anchor)

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, w_m=0.0, rad_m=0.0, glow=False):
        box = self.r(x0, y0, x1, y1)
        wpx = max(1, int(w_m * self.sx)) if outline else 0
        if rad_m > 0:
            self.dr.rounded_rectangle(box, radius=rad_m * self.sx, fill=fill, outline=outline, width=wpx)
            if glow:
                self.dm.rounded_rectangle(box, radius=rad_m * self.sx, fill=255)
        else:
            self.dr.rectangle(box, fill=fill, outline=outline, width=wpx)
            if glow:
                self.dm.rectangle(box, fill=255)

    def ellipse(self, cx, cy, r, fill=None, outline=None, w_m=0.0, glow=False):
        box = self.r(cx - r, cy - r, cx + r, cy + r)
        self.dr.ellipse(box, fill=fill, outline=outline, width=max(1, int(w_m * self.sx)) if outline else 0)
        if glow:
            self.dm.ellipse(box, fill=255)

    def line(self, pts, fill=INK, w_m=0.002):
        self.dr.line([self.p(x, y) for x, y in pts], fill=fill, width=max(1, int(w_m * self.sx)))

    def screw(self, x, y, r=0.004):
        self.ellipse(x, y, r, fill="#4A5058", outline="#1A1C20", w_m=0.0012)
        self.line([(x - r * 0.7, y), (x + r * 0.7, y)], fill="#1A1C20", w_m=0.0012)

    def sub(self, x0, y0, x1, y1, draw_fn, glow=True):
        """(x0, y0)-(x1, y1) の長方形に、画素の絵（draw_fn(img, w, h)）を描いて貼る。"""
        box = [int(round(v)) for v in self.r(x0, y0, x1, y1)]
        w, h = box[2] - box[0], box[3] - box[1]
        im = Image.new("RGB", (w, h), "#05080A")
        draw_fn(im, w, h)
        self.img.paste(im, (box[0], box[1]))
        if glow:
            self.dm.rectangle(box, fill=255)

    def grain(self, amount=0.035, seed=0):
        a = np.asarray(self.img).astype(np.float64)
        n = np.asarray(Image.fromarray((tile_noise(256, 64, 4, seed=seed) * 255).astype(np.uint8)).resize((self.wpx, self.hpx)),
                       dtype=np.float64) / 255
        m = np.asarray(self.mask, dtype=np.float64)[..., None] / 255
        a = a * (1 + amount * (n[..., None] - 0.5) * 2 * (1 - m))
        self.img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
        self.dr = ImageDraw.Draw(self.img)

    def paste_into(self, atlas, amask):
        x0, y0, x1, y1 = self.box
        atlas.paste(self.img.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0))
        amask.paste(self.mask.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0))


def _f(px):
    return ImageFont.truetype(FONT, max(6, int(px)))


def _fb(px):
    return ImageFont.truetype(FONT_BOLD, max(6, int(px)))


def screen_pfd(im, w, h):
    dr = ImageDraw.Draw(im)
    cx, cy = w * 0.5, h * 0.42
    # 姿勢（空と地面。少し右へ傾き、少し機首上げ）
    bank = math.radians(-4.0)
    pitch = h * 0.04
    big = Image.new("RGB", (w * 3, h * 3), "#8A5A2E")
    bd = ImageDraw.Draw(big)
    bd.rectangle([0, 0, w * 3, h * 1.5 + pitch], fill="#2F78D6")
    for k in range(-6, 7):
        if k == 0:
            continue
        yy = h * 1.5 + pitch - k * h * 0.055
        half = w * (0.10 if k % 2 == 0 else 0.05)
        bd.line([w * 1.5 - half, yy, w * 1.5 + half, yy], fill="#F4F4F0", width=max(2, w // 220))
        if k % 2 == 0:
            for sgn in (-1, 1):
                bd.text((w * 1.5 + sgn * (half + w * 0.04), yy), str(abs(k) * 5), font=_f(h * 0.035), fill="#F4F4F0", anchor="mm")
    bd.line([0, h * 1.5 + pitch, w * 3, h * 1.5 + pitch], fill="#F4F4F0", width=max(2, w // 180))
    big = big.rotate(math.degrees(bank), resample=Image.BICUBIC, center=(w * 1.5, h * 1.5))
    att = big.crop((int(w * 1.5 - cx), int(h * 1.5 - cy), int(w * 1.5 - cx + w), int(h * 1.5 - cy + h)))
    im.paste(att, (0, 0))
    dr = ImageDraw.Draw(im)
    # 傾きの目盛り（上の弧）と三角
    r = w * 0.33
    for d in (-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60):
        a = math.radians(d - 90)
        r0 = r * (0.90 if abs(d) in (10, 20, 45) else 0.85)
        dr.line([cx + math.cos(a) * r0, cy + math.sin(a) * r0, cx + math.cos(a) * r, cy + math.sin(a) * r], fill="#F4F4F0", width=max(2, w // 200))
    dr.arc([cx - r, cy - r, cx + r, cy + r], 210, 330, fill="#F4F4F0", width=max(2, w // 220))
    dr.polygon([(cx, cy - r + 2), (cx - w * 0.02, cy - r - h * 0.03), (cx + w * 0.02, cy - r - h * 0.03)], fill="#F4F4F0")
    # 機体の印（黄色）
    t = max(3, w // 90)
    dr.line([cx - w * 0.22, cy, cx - w * 0.08, cy, cx - w * 0.05, cy + h * 0.03], fill="#111", width=t + 4)
    dr.line([cx + w * 0.22, cy, cx + w * 0.08, cy, cx + w * 0.05, cy + h * 0.03], fill="#111", width=t + 4)
    dr.line([cx - w * 0.22, cy, cx - w * 0.08, cy, cx - w * 0.05, cy + h * 0.03], fill="#F2C230", width=t)
    dr.line([cx + w * 0.22, cy, cx + w * 0.08, cy, cx + w * 0.05, cy + h * 0.03], fill="#F2C230", width=t)
    dr.rectangle([cx - t, cy - t, cx + t, cy + t], fill="#F2C230", outline="#111")
    # 速さと高さの帯
    for side, x0, vals, cur in ((-1, 0.03, [150, 160, 170, 180, 190], "165"), (1, 0.80, [4800, 4900, 5000, 5100, 5200], "5000")):
        xa, xb = w * x0, w * (x0 + 0.17)
        ov = Image.new("RGBA", (int(xb - xa), int(h * 0.62)), (20, 24, 28, 170))
        im.paste(ov, (int(xa), int(h * 0.11)), ov)
        dr = ImageDraw.Draw(im)
        for i, val in enumerate(vals):
            yy = h * 0.73 - (i + 0.5) * h * 0.12
            dr.line([xb - w * 0.03 if side < 0 else xa, yy, xb if side < 0 else xa + w * 0.03, yy], fill="#F4F4F0", width=2)
            dr.text(((xa + xb) / 2 - side * w * 0.01, yy), str(val), font=_f(h * 0.04), fill="#F4F4F0", anchor="mm")
        yy = h * 0.42
        dr.rectangle([xa - w * 0.01, yy - h * 0.035, xb + w * 0.01, yy + h * 0.035], fill="#000", outline="#F4F4F0", width=2)
        dr.text(((xa + xb) / 2, yy), cur, font=_fb(h * 0.05), fill="#F4F4F0", anchor="mm")
    # 上の表示（モード）
    dr.rectangle([0, 0, w, h * 0.065], fill="#000")
    for i, s in enumerate(["SPD", "HDG", "ALT", "AP1"]):
        dr.text((w * (0.14 + i * 0.24), h * 0.033), s, font=_fb(h * 0.04), fill=GREEN, anchor="mm")
    # 方位（下）
    dr.rectangle([0, h * 0.76, w, h], fill="#05080A")
    rc = w * 0.62
    ccx, ccy = cx, h * 0.80 + rc
    dr.ellipse([ccx - rc, ccy - rc, ccx + rc, ccy + rc], outline="#F4F4F0", width=2)
    for d in range(-40, 41, 5):
        a = math.radians(d - 90)
        r0 = rc * (0.94 if d % 10 else 0.90)
        dr.line([ccx + math.cos(a) * r0, ccy + math.sin(a) * r0, ccx + math.cos(a) * rc, ccy + math.sin(a) * rc], fill="#F4F4F0", width=2)
        if d % 30 == 0:
            lab = {-30: "24", 0: "27", 30: "30"}[d]
            dr.text((ccx + math.cos(a) * rc * 0.82, ccy + math.sin(a) * rc * 0.82), lab, font=_f(h * 0.04), fill="#F4F4F0", anchor="mm")
    dr.polygon([(cx, h * 0.80), (cx - w * 0.02, h * 0.78), (cx + w * 0.02, h * 0.78)], fill=MAGENTA)
    dr.text((w * 0.12, h * 0.95), "HDG 270", font=_f(h * 0.035), fill=CYAN, anchor="mm")
    dr.text((w * 0.86, h * 0.95), "CRS 268", font=_f(h * 0.035), fill=GREEN, anchor="mm")


def screen_nav(im, w, h):
    dr = ImageDraw.Draw(im)
    cx, cy = w * 0.5, h * 0.84
    # 島（暗い緑）と海岸
    rng = np.random.default_rng(7)
    for k in range(5):
        ix, iy, ir = w * (0.15 + 0.7 * rng.random()), h * (0.12 + 0.55 * rng.random()), w * (0.05 + 0.08 * rng.random())
        pts = []
        for j in range(18):
            a = 2 * math.pi * j / 18
            rr = ir * (0.7 + 0.5 * rng.random())
            pts.append((ix + math.cos(a) * rr, iy + math.sin(a) * rr * 0.7))
        dr.polygon(pts, fill="#123A22", outline="#2E7A44")
    # 距離の輪（点線）と方位の弧
    for rr in (0.25, 0.50, 0.75):
        R = h * rr
        for d in range(-70, 71, 6):
            a0, a1 = math.radians(d - 90), math.radians(d + 3 - 90)
            dr.line([cx + math.cos(a0) * R, cy + math.sin(a0) * R, cx + math.cos(a1) * R, cy + math.sin(a1) * R], fill="#6A7078", width=2)
        dr.text((cx + R * 0.72, cy - R * 0.72), str(int(rr * 40)), font=_f(h * 0.03), fill="#9AA0A8", anchor="mm")
    R = h * 0.75
    for d in range(-60, 61, 5):
        a = math.radians(d - 90)
        r0 = R * (0.95 if d % 10 else 0.91)
        dr.line([cx + math.cos(a) * r0, cy + math.sin(a) * r0, cx + math.cos(a) * R, cy + math.sin(a) * R], fill="#F4F4F0", width=2)
        if d % 30 == 0:
            lab = {-60: "21", -30: "24", 0: "27", 30: "30", 60: "33"}[d]
            dr.text((cx + math.cos(a) * R * 1.07, cy + math.sin(a) * R * 1.07), lab, font=_f(h * 0.035), fill="#F4F4F0", anchor="mm")
    # 道すじ（紫）と経由点（水色）
    route = [(cx, cy), (cx + w * 0.05, h * 0.62), (cx - w * 0.10, h * 0.38), (cx - w * 0.04, h * 0.18), (cx + w * 0.14, h * 0.10)]
    dr.line(route, fill=MAGENTA, width=max(3, w // 120))
    for (x, y), name in zip(route[1:], ["TQ01", "SKYGT", "ISLE", "HOME"]):
        s = w * 0.018
        dr.polygon([(x, y - s), (x + s * 0.35, y - s * 0.35), (x + s, y), (x + s * 0.35, y + s * 0.35), (x, y + s), (x - s * 0.35, y + s * 0.35),
                    (x - s, y), (x - s * 0.35, y - s * 0.35)], fill=CYAN)
        dr.text((x + w * 0.04, y), name, font=_f(h * 0.032), fill=CYAN, anchor="lm")
    # 自機（白い三角）
    s = w * 0.04
    dr.polygon([(cx, cy - s), (cx - s * 0.6, cy + s * 0.5), (cx + s * 0.6, cy + s * 0.5)], outline="#F4F4F0", width=3)
    dr.text((w * 0.05, h * 0.04), "GS 165  TAS 172", font=_f(h * 0.032), fill="#F4F4F0", anchor="lm")
    dr.text((w * 0.95, h * 0.04), "TRK 270", font=_f(h * 0.032), fill=GREEN, anchor="rm")
    dr.text((w * 0.05, h * 0.96), "MAP  40NM", font=_f(h * 0.03), fill=CYAN, anchor="lm")
    dr.text((w * 0.95, h * 0.96), "ETA 14:22", font=_f(h * 0.03), fill="#F4F4F0", anchor="rm")


def screen_eng(im, w, h):
    dr = ImageDraw.Draw(im)
    dr.text((w * 0.5, h * 0.04), "ENGINE", font=_fb(h * 0.04), fill="#F4F4F0", anchor="mm")
    vals = [92.5, 93.1, 91.8, 92.9]
    for i in range(4):
        cx = w * (0.14 + i * 0.24)
        cy = h * 0.17
        r = w * 0.095
        dr.arc([cx - r, cy - r, cx + r, cy + r], 135, 405, fill="#F4F4F0", width=2)
        dr.arc([cx - r * 0.9, cy - r * 0.9, cx + r * 0.9, cy + r * 0.9], 135, 330, fill=GREEN, width=max(3, w // 110))
        dr.arc([cx - r * 0.9, cy - r * 0.9, cx + r * 0.9, cy + r * 0.9], 330, 380, fill=AMBER, width=max(3, w // 110))
        a = math.radians(135 + 270 * vals[i] / 120)
        dr.line([cx, cy, cx + math.cos(a) * r * 0.85, cy + math.sin(a) * r * 0.85], fill="#F4F4F0", width=max(3, w // 130))
        dr.rectangle([cx - w * 0.07, cy + r * 0.55, cx + w * 0.07, cy + r * 1.05], outline="#F4F4F0", width=2)
        dr.text((cx, cy + r * 0.80), f"{vals[i]:.1f}", font=_f(h * 0.032), fill="#F4F4F0", anchor="mm")
        dr.text((cx, cy - r * 1.25), str(i + 1), font=_fb(h * 0.03), fill=CYAN, anchor="mm")
    dr.text((w * 0.03, h * 0.17), "TQ", font=_f(h * 0.028), fill=CYAN, anchor="lm")
    rng = np.random.default_rng(3)
    for row, (lab, base) in enumerate((("ITT", 0.72), ("NP", 0.98), ("FF", 0.64))):
        y0, y1 = h * (0.36 + row * 0.17), h * (0.48 + row * 0.17)
        dr.text((w * 0.03, (y0 + y1) / 2), lab, font=_f(h * 0.028), fill=CYAN, anchor="lm")
        for i in range(4):
            x0 = w * (0.12 + i * 0.22)
            x1 = x0 + w * 0.16
            dr.rectangle([x0, y0, x1, y1], outline="#6A7078", width=2)
            f = base + 0.03 * (rng.random() - 0.5)
            dr.rectangle([x0 + 3, y0 + 3, x0 + 3 + (x1 - x0 - 6) * f, y1 - 3], fill="#2FAF5A" if f < 0.9 else "#E0A81E")
            dr.text(((x0 + x1) / 2, y1 + h * 0.025), f"{int(f * (870 if lab == 'ITT' else 100 if lab == 'NP' else 2400))}", font=_f(h * 0.026),
                    fill="#F4F4F0", anchor="mm")
    dr.line([w * 0.03, h * 0.88, w * 0.97, h * 0.88], fill="#6A7078", width=2)
    dr.text((w * 0.05, h * 0.93), "FUEL QTY", font=_f(h * 0.03), fill=CYAN, anchor="lm")
    dr.text((w * 0.95, h * 0.93), "18 240 LB", font=_fb(h * 0.036), fill="#F4F4F0", anchor="rm")


def screen_radar(im, w, h):
    dr = ImageDraw.Draw(im)
    cx, cy = w * 0.5, h * 0.92
    R = h * 0.82
    wx = Image.new("RGB", (w, h), (0, 0, 0))
    wd = ImageDraw.Draw(wx)
    rng = np.random.default_rng(11)
    for k in range(9):
        a = math.radians(-90 + (rng.random() - 0.5) * 80)
        d = R * (0.35 + 0.6 * rng.random())
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
        s = w * (0.05 + 0.08 * rng.random())
        wd.ellipse([x - s, y - s * 0.6, x + s, y + s * 0.6], fill=(30, 170, 70))
        if rng.random() < 0.7:
            wd.ellipse([x - s * 0.55, y - s * 0.32, x + s * 0.55, y + s * 0.32], fill=(220, 200, 40))
        if rng.random() < 0.4:
            wd.ellipse([x - s * 0.22, y - s * 0.14, x + s * 0.22, y + s * 0.14], fill=(220, 50, 40))
    wx = wx.filter(ImageFilter.GaussianBlur(w * 0.012))
    fan = Image.new("L", (w, h), 0)
    ImageDraw.Draw(fan).pieslice([cx - R, cy - R, cx + R, cy + R], 225, 315, fill=255)
    im.paste(wx, (0, 0), fan)
    dr = ImageDraw.Draw(im)
    for rr in (0.25, 0.5, 0.75, 1.0):
        dr.arc([cx - R * rr, cy - R * rr, cx + R * rr, cy + R * rr], 225, 315, fill="#3E9A5A", width=2)
    for d in (-45, -30, -15, 0, 15, 30, 45):
        a = math.radians(d - 90)
        dr.line([cx, cy, cx + math.cos(a) * R, cy + math.sin(a) * R], fill="#2E6A42", width=1)
    dr.text((w * 0.05, h * 0.05), "WX", font=_fb(h * 0.04), fill=GREEN, anchor="lm")
    dr.text((w * 0.95, h * 0.05), "40 NM", font=_f(h * 0.035), fill=CYAN, anchor="rm")
    dr.text((w * 0.05, h * 0.11), "GAIN CAL", font=_f(h * 0.03), fill="#F4F4F0", anchor="lm")
    dr.text((w * 0.95, h * 0.11), "TILT -2.0", font=_f(h * 0.03), fill="#F4F4F0", anchor="rm")


def dial(kind, size_px):
    """丸い計器（正方形の絵）。"""
    n = size_px
    im = Image.new("RGB", (n, n), PANEL_BG)
    dr = ImageDraw.Draw(im)
    c, r = n / 2, n / 2 * 0.96
    dr.ellipse([c - r, c - r, c + r, c + r], fill="#0E1013", outline="#5A6068", width=max(2, n // 40))
    if kind == "att":
        r2 = r * 0.84
        dr.pieslice([c - r2, c - r2, c + r2, c + r2], 180, 360, fill="#2F78D6")
        dr.pieslice([c - r2, c - r2, c + r2, c + r2], 0, 180, fill="#8A5A2E")
        dr.line([c - r2, c, c + r2, c], fill="#F4F4F0", width=max(2, n // 70))
        for k in (-2, -1, 1, 2):
            dr.line([c - r * 0.15, c + k * r * 0.15, c + r * 0.15, c + k * r * 0.15], fill="#F4F4F0", width=max(1, n // 120))
        dr.line([c - r * 0.5, c, c - r * 0.18, c], fill="#F2C230", width=max(3, n // 40))
        dr.line([c + r * 0.18, c, c + r * 0.5, c], fill="#F2C230", width=max(3, n // 40))
        return im
    ticks = 60 if kind == "clock" else 50
    for i in range(ticks):
        a = 2 * math.pi * i / ticks
        big = i % 5 == 0
        r0 = r * (0.76 if big else 0.84)
        dr.line([c + math.sin(a) * r0, c - math.cos(a) * r0, c + math.sin(a) * r * 0.9, c - math.cos(a) * r * 0.9], fill="#E8E8E2",
                width=max(2, n // (60 if big else 140)))
    f = _f(n * 0.11)
    labels = {"clock": [str(k) for k in (12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)], "alt": [str(k) for k in range(10)],
              "spd": ["0", "40", "80", "120", "160", "200", "240", "280", "320", "360"]}[kind]
    for i, lab in enumerate(labels):
        a = 2 * math.pi * i / len(labels)
        dr.text((c + math.sin(a) * r * 0.60, c - math.cos(a) * r * 0.60), lab, font=f, fill="#E8E8E2", anchor="mm")
    if kind == "spd":
        dr.arc([c - r * 0.86, c - r * 0.86, c + r * 0.86, c + r * 0.86], -90 + 36 * 2, -90 + 36 * 6, fill="#2FAF5A", width=max(3, n // 35))
    for ang, ln, wd_ in ((47, 0.55, 30), (200, 0.78, 45)) if kind != "spd" else ((165, 0.78, 40),):
        a = math.radians(ang)
        dr.line([c, c, c + math.sin(a) * r * ln, c - math.cos(a) * r * ln], fill="#F4F4F0", width=max(2, n // wd_))
    dr.ellipse([c - r * 0.07, c - r * 0.07, c + r * 0.07, c + r * 0.07], fill="#2A2D33")
    dr.text((c, c + r * 0.32), {"clock": "CLOCK", "alt": "ALT", "spd": "KNOTS"}[kind], font=_f(n * 0.07), fill="#9AA0A8", anchor="mm")
    return im


DASH_MFDS = [(0.245, 0.205, 0.545, 0.595, "pfd"), (0.575, 0.205, 0.875, 0.595, "nav"), (0.985, 0.205, 1.285, 0.595, "eng"),
             (1.315, 0.205, 1.615, 0.595, "radar")]
DASH_DIALS = [(0.14, 0.47, 0.062, "spd"), (0.14, 0.31, 0.062, "alt"), (1.72, 0.47, 0.062, "att"), (1.72, 0.31, 0.055, "clock")]
MFD_MARGIN = (0.032, 0.026)          # 縁の幅（横・縦）：横の縁にソフトキー


def dash_panel():
    cv = Cv("dash")
    W, H = cv.wm, cv.hm
    # 盤の区切り（細い溝）とねじ
    for x0, x1 in ((0.02, 0.232), (0.232, 0.93), (0.93, 1.628), (1.628, 1.84)):
        cv.rect(x0 + 0.004, 0.012, x1 - 0.004, H - 0.03, outline="#1B1E22", w_m=0.002, rad_m=0.01)
        for x in (x0 + 0.014, x1 - 0.014):
            for y in (0.024, H - 0.042):
                cv.screw(x, y)
    knobs, lights, buttons = [], [], []
    draws = {"pfd": screen_pfd, "nav": screen_nav, "eng": screen_eng, "radar": screen_radar}
    for x0, y0, x1, y1, kind in DASH_MFDS:
        mx, my = MFD_MARGIN
        cv.rect(x0, y0, x1, y1, fill="#1C1F23", outline="#0E1013", w_m=0.002, rad_m=0.008)
        cv.sub(x0 + mx, y0 + my, x1 - mx, y1 - my, draws[kind])
        for k in range(6):
            y = y0 + my + (y1 - y0 - 2 * my) * (k + 0.5) / 6
            for x in (x0 + mx * 0.5, x1 - mx * 0.5):
                cv.rect(x - 0.009, y - 0.011, x + 0.009, y + 0.011, fill="#3A3F46", outline="#121417", w_m=0.001, rad_m=0.002)
                buttons.append([round(x, 4), round(y, 4)])
        # 下の段：つまみ 2 つと押しボタン
        for x, lab in ((x0 + 0.05, "BARO"), (x1 - 0.05, "RNG")):
            cv.ellipse(x, 0.125, 0.026, fill="#1A1C20", outline="#5A6068", w_m=0.0015)
            cv.text(x, 0.075, lab, 0.016, fill="#C9CDD1")
            knobs.append([round(x, 4), 0.125, 0.017])
        for k in range(4):
            x = x0 + 0.105 + k * 0.03
            cv.rect(x - 0.011, 0.11, x + 0.011, 0.14, fill="#3A3F46", outline="#121417", w_m=0.001, rad_m=0.003)
            cv.rect(x - 0.007, 0.132, x + 0.007, 0.136, fill=GREEN if (k + int(x0 * 10)) % 3 == 0 else "#20402A", glow=True)
    # 予備の計器（丸）
    for cx, cy, r, kind in DASH_DIALS:
        im = dial(kind, int(2 * r * cv.sx)).resize((int(2 * r * cv.sx), int(2 * r * cv.sy)), Image.LANCZOS)
        cv.img.paste(im, [int(v) for v in cv.p(cx - r, cy + r)])
    for x, y, lab in ((0.14, 0.205, "STBY"), (1.72, 0.205, "STBY")):
        cv.text(x, y, lab, 0.016, fill="#9AA0A8")
    # 真ん中の柱：主警告（赤）・主注意（黄）と小さな表示
    for y, col, lab in ((0.545, RED, "WARN"), (0.47, AMBER, "CAUT")):
        cv.rect(0.895, y - 0.03, 0.965, y + 0.03, fill="#141618", outline="#0A0B0C", w_m=0.002, rad_m=0.006)
        cv.rect(0.902, y - 0.023, 0.958, y + 0.023, fill=col, rad_m=0.004, glow=True)
        cv.text(0.93, y, lab, 0.017, fill="#2A1A10", bold=True)
        lights.append([0.895, round(y - 0.03, 4), 0.965, round(y + 0.03, 4)])
    cv.rect(0.892, 0.30, 0.968, 0.40, fill="#05080A", outline="#5A6068", w_m=0.0015, glow=True)
    cv.text(0.93, 0.372, "14:06", 0.022, fill=GREEN, glow=True)
    cv.text(0.93, 0.33, "UTC", 0.014, fill=CYAN, glow=True)
    # 上の注意灯の列（MFD 2 と 3 の上）
    caps = ["FUEL", "HYD", "OIL", "DOOR", "RAMP", "FLOAT", "ICE", "GEN", "BLEED", "FIRE"]
    for i, lab in enumerate(caps):
        x = 0.60 + i * 0.066
        lit = lab in ("RAMP", "FLOAT")
        cv.rect(x - 0.03, 0.605, x + 0.03, 0.632, fill=("#E8B21E" if lab == "RAMP" else "#2FBF5A") if lit else "#3A3020",
                outline="#0A0B0C", w_m=0.0012, rad_m=0.003, glow=lit)
        cv.text(x, 0.6185, lab, 0.013, fill="#151515" if lit else "#8A7A55", bold=True)
    # 下の真ん中：水の上の操作（水かじ・フロートのポンプ）。立体のスイッチは items の toggles
    for y, lab in ((0.215, "WTR RUDDER"), (0.115, "FLOAT PUMP")):
        cv.ellipse(0.93, y - 0.03, 0.011, fill="#15171A", outline="#6A7078", w_m=0.0012)
        cv.text(0.93, y, lab, 0.0095, fill="#C9CDD1")
    cv.grain(seed=31)
    return cv, {"mfd": [[x0, y0, x1, y1] for x0, y0, x1, y1, _ in DASH_MFDS], "mfd_margin": list(MFD_MARGIN),
                "dials": [[cx, cy, r] for cx, cy, r, _ in DASH_DIALS], "knobs": knobs, "lights": lights, "softkeys": buttons,
                "toggles": [[0.93, 0.185], [0.93, 0.085]]}


def overhead_panel():
    cv = Cv("overhead")
    W, H = cv.wm, cv.hm
    k = H / 0.95                         # 縦の座標は 0.95 m の盤で決めた値を縮める（2026-10-22：ハテナの「？」をよけて盤を短くした）
    toggles, knobs, guards = [], [], []
    sections = [  # x0, y0, x1, y1, 名前, 列, 行
        (0.03, 0.70 * k, 0.37, 0.92 * k, "ENGINE START", 4, 1),
        (0.43, 0.70 * k, 0.77, 0.92 * k, "FIRE", 4, 1),
        (0.03, 0.40 * k, 0.37, 0.66 * k, "FUEL", 4, 2),
        (0.43, 0.40 * k, 0.77, 0.66 * k, "ELECTRICAL", 4, 2),
        (0.03, 0.12 * k, 0.37, 0.36 * k, "ANTI-ICE / BLEED", 4, 2),
        (0.43, 0.12 * k, 0.77, 0.36 * k, "LIGHTS", 4, 2),
    ]
    labels = {"ENGINE START": ["1", "2", "3", "4"], "FIRE": ["1", "2", "3", "4"], "FUEL": ["PUMP", "XFEED", "PUMP", "XFEED"],
              "ELECTRICAL": ["GEN 1", "GEN 2", "GEN 3", "GEN 4"], "ANTI-ICE / BLEED": ["PROP", "ENG", "WING", "BLEED"],
              "LIGHTS": ["NAV", "BCN", "LDG", "FORM"]}
    for x0, y0, x1, y1, name, cols, rows in sections:
        cv.rect(x0, y0, x1, y1, outline="#C9CDD1", w_m=0.0015, rad_m=0.008)
        cv.rect((x0 + x1) / 2 - 0.09, y1 - 0.012, (x0 + x1) / 2 + 0.09, y1 + 0.012, fill=PANEL_BG)
        cv.text((x0 + x1) / 2, y1, name, 0.018, bold=True)
        for rr in range(rows):
            for c in range(cols):
                x = x0 + (x1 - x0) * (c + 0.5) / cols
                y = y1 - 0.06 * k - rr * 0.11 * k
                if name == "FIRE":
                    cv.rect(x - 0.028, y - 0.06, x + 0.028, y + 0.02, fill="#B8261E", outline="#4A0E0A", w_m=0.0015, rad_m=0.006)
                    cv.text(x, y - 0.02, "ENG " + labels[name][c], 0.012, fill="#F4F4F0", bold=True)
                    guards.append([round(x, 4), round(y - 0.02, 4)])
                    continue
                if name == "ENGINE START":
                    cv.ellipse(x, y, 0.020, fill="#15171A", outline="#6A7078", w_m=0.0015)
                    knobs.append([round(x, 4), round(y, 4), 0.015])
                    cv.text(x, y - 0.038, labels[name][c], 0.014)
                    cv.rect(x - 0.022, y + 0.027, x + 0.022, y + 0.042, fill="#204A2A" if c % 2 else "#2FBF5A", rad_m=0.003, glow=c % 2 == 0)
                    continue
                cv.ellipse(x, y, 0.012, fill="#15171A", outline="#6A7078", w_m=0.0012)
                toggles.append([round(x, 4), round(y, 4)])
                cv.text(x, y - 0.026, labels[name][c] if rr == 0 else ("ON" if c % 2 else "AUTO"), 0.011)
                cv.text(x, y + 0.022, "ON", 0.008, fill="#9AA0A8")
                if rr == 0 and name in ("FUEL", "ELECTRICAL"):
                    lit = (c + len(name)) % 3 == 0
                    cv.rect(x - 0.018, y + 0.029, x + 0.018, y + 0.039, fill=AMBER if lit else "#3A3020", rad_m=0.002, glow=lit)
    # 真ん中の縦の帯：表示とつまみ
    cv.rect(0.385, 0.12 * k, 0.415, 0.92 * k, fill="#202327", outline="#0E1013", w_m=0.001)
    for y in (0.25 * k, 0.52 * k, 0.80 * k):
        cv.ellipse(0.40, y, 0.011, fill="#15171A", outline="#6A7078", w_m=0.001)
        knobs.append([0.40, y, 0.009])
    for x in (0.02, W - 0.02):
        for y in (0.03, H - 0.03):
            cv.screw(x, y)
    cv.text(W / 2, 0.04, "WATER OPS  -  FLOAT BILGE PUMP  /  WATER RUDDER", 0.013, fill="#C9CDD1")
    cv.grain(seed=32)
    return cv, {"toggles": toggles, "knobs": knobs, "guards": guards}


def console_r_panel():
    cv = Cv("console_r")
    W, H = cv.wm, cv.hm
    levers = []
    # パワーレバー 4 本（内側）と条件のレバー 4 本（外側）
    for i in range(4):
        x = 0.055 + i * 0.045
        cv.rect(x - 0.008, 0.32, x + 0.008, 0.86, fill="#0B0C0E", rad_m=0.004)
        for t in range(9):
            y = 0.34 + t * 0.06
            cv.line([(x - 0.02, y), (x - 0.012, y)], fill=INK, w_m=0.0015)
        cv.text(x, 0.29, str(i + 1), 0.018, bold=True)
        levers.append({"kind": "power", "x": round(x, 4), "y0": 0.34, "y1": 0.84, "at": 0.62 + 0.03 * (i % 2)})
    for lab, y in (("MAX", 0.875), ("FLT IDLE", 0.56), ("GND IDLE", 0.43), ("REV", 0.33)):
        cv.text(0.245, y, lab, 0.013, fill="#C9CDD1", anchor="lm")
    for i in range(4):
        x = 0.235 + i * 0.038
        cv.rect(x - 0.006, 0.08, x + 0.006, 0.26, fill="#0B0C0E", rad_m=0.003)
        levers.append({"kind": "cond", "x": round(x, 4), "y0": 0.09, "y1": 0.25, "at": 0.85})
    cv.text(0.29, 0.045, "COND  RUN / STOP / FEATHER", 0.011, fill="#C9CDD1")
    # フラップ
    cv.rect(0.345, 0.32, 0.365, 0.86, fill="#0B0C0E", rad_m=0.004)
    for pct, y in (("0", 0.84), ("50", 0.60), ("100", 0.36)):
        cv.text(0.385, y, pct, 0.013, anchor="lm")
    levers.append({"kind": "flap", "x": 0.355, "y0": 0.34, "y1": 0.84, "at": 0.85})
    cv.text(0.355, 0.895, "FLAPS", 0.013, bold=True)
    cv.text(0.12, 0.93, "POWER", 0.016, bold=True)
    cv.rect(0.03, 0.06, 0.20, 0.24, outline="#C9CDD1", w_m=0.0012, rad_m=0.006)
    cv.text(0.115, 0.215, "TRIM", 0.013, bold=True)
    for k, (lab, f) in enumerate((("AIL", 0.5), ("RUD", 0.46), ("ELEV", 0.58))):
        y = 0.18 - k * 0.04
        cv.text(0.05, y, lab, 0.011, anchor="lm")
        cv.rect(0.09, y - 0.006, 0.19, y + 0.006, fill="#0B0C0E")
        cv.rect(0.09 + 0.1 * f - 0.003, y - 0.009, 0.09 + 0.1 * f + 0.003, y + 0.009, fill="#F4F4F0")
    for x in (0.015, W - 0.015):
        for y in (0.015, H - 0.015):
            cv.screw(x, y)
    cv.grain(seed=33)
    return cv, {"levers": levers}


def console_l_panel():
    cv = Cv("console_l")
    W, H = cv.wm, cv.hm
    knobs = []
    for k, (y0, name, freq) in enumerate(((0.72, "VHF 1", "121.500"), (0.52, "VHF 2", "118.300"), (0.32, "UHF", "243.000"))):
        cv.rect(0.03, y0, 0.37, y0 + 0.17, fill="#1E2125", outline="#0E1013", w_m=0.002, rad_m=0.006)
        cv.rect(0.10, y0 + 0.07, 0.30, y0 + 0.13, fill="#05080A", outline="#4A5058", w_m=0.0015, glow=True)
        cv.text(0.20, y0 + 0.10, freq, 0.03, fill=GREEN, glow=True)
        cv.text(0.20, y0 + 0.148, name, 0.013, fill="#C9CDD1")
        for x in (0.065, 0.335):
            cv.ellipse(x, y0 + 0.07, 0.022, fill="#15171A", outline="#6A7078", w_m=0.0015)
            knobs.append([x, round(y0 + 0.07, 4), 0.016])
        for b in range(4):
            cv.rect(0.115 + b * 0.05, y0 + 0.015, 0.145 + b * 0.05, y0 + 0.045, fill="#3A3F46", outline="#121417", w_m=0.001, rad_m=0.003)
    cv.rect(0.03, 0.06, 0.37, 0.28, fill="#1E2125", outline="#0E1013", w_m=0.002, rad_m=0.006)
    cv.text(0.20, 0.26, "AUDIO", 0.014, bold=True)
    for r_ in range(2):
        for c in range(5):
            x, y = 0.07 + c * 0.065, 0.20 - r_ * 0.08
            cv.ellipse(x, y, 0.014, fill="#15171A", outline="#6A7078", w_m=0.001)
            knobs.append([round(x, 4), round(y, 4), 0.010])
            cv.text(x, y - 0.03, ["VHF1", "VHF2", "UHF", "INT", "PA"][c], 0.010)
    cv.text(0.20, 0.925, "XPDR  7000", 0.022, fill=GREEN, glow=True)
    cv.rect(0.08, 0.90, 0.32, 0.95, outline="#4A5058", w_m=0.0015)
    for x in (0.015, W - 0.015):
        for y in (0.015, H - 0.015):
            cv.screw(x, y)
    cv.grain(seed=34)
    return cv, {"knobs": knobs}


def mcp_panel():
    cv = Cv("mcp", bg="#25292E")
    W, H = cv.wm, cv.hm
    knobs = []
    windows = [(0.10, "SPD", "165"), (0.32, "HDG", "270"), (0.55, "ALT", "05000"), (0.78, "V/S", "+0700")]
    for x, lab, val in windows:
        cv.rect(x - 0.05, 0.045, x + 0.05, 0.085, fill="#05080A", outline="#4A5058", w_m=0.0012, glow=True)
        cv.text(x, 0.065, val, 0.026, fill=AMBER, glow=True)
        cv.text(x, 0.096, lab, 0.011)
        knobs.append([round(x + 0.075, 4), 0.055, 0.014])
        cv.ellipse(x + 0.075, 0.055, 0.019, fill="#15171A", outline="#6A7078", w_m=0.0012)
    for i, lab in enumerate(["AP", "FD", "NAV", "APR", "ALT", "BC"]):
        x = 0.06 + i * 0.06 + (0.40 if i >= 3 else 0.0)
        x = min(x, W - 0.04)
    for i, lab in enumerate(["AP", "FD", "NAV", "APR"]):
        x = 0.205 + i * 0.065 if i < 2 else 0.665 + (i - 2) * 0.065
        cv.rect(x - 0.022, 0.012, x + 0.022, 0.034, fill="#3A3F46", outline="#121417", w_m=0.001, rad_m=0.003)
        cv.text(x, 0.023, lab, 0.011, bold=True)
        cv.rect(x - 0.012, 0.030, x + 0.012, 0.033, fill=GREEN if i in (0, 2) else "#20402A", glow=i in (0, 2))
    cv.grain(seed=35)
    return cv, {"knobs": knobs}


def cb_panel():
    cv = Cv("cb", bg="#2E3238")
    W, H = cv.wm, cv.hm
    rng = np.random.default_rng(5)
    for r_ in range(6):
        y = H - 0.04 - r_ * 0.05
        for c in range(28):
            x = 0.03 + c * 0.0312
            cv.ellipse(x, y, 0.0085, fill="#B9BEC4", outline="#5A6068", w_m=0.001)
            cv.ellipse(x, y, 0.0055, fill="#0E1013")
            if rng.random() < 0.08:
                cv.ellipse(x, y, 0.004, fill="#F4F4F0")
            cv.text(x, y - 0.016, str(int(5 + 5 * rng.integers(0, 7))), 0.008, fill="#C9CDD1")
        cv.line([(0.015, y + 0.022), (W - 0.015, y + 0.022)], fill="#F4F4F0", w_m=0.0008)
    for x in (0.01, W - 0.01):
        for y in (0.01, H - 0.01):
            cv.screw(x, y, 0.004)
    cv.grain(seed=36)
    return cv, {}


def misc_panel():
    cv = Cv("misc", bg="#2E3238")
    W, H = cv.wm, cv.hm
    # 上：酸素の調整器（緑の盤）
    cv.rect(0.02, 0.21, 0.38, 0.39, fill="#2F5A3A", outline="#14261A", w_m=0.002, rad_m=0.01)
    cv.text(0.20, 0.37, "OXYGEN", 0.02, fill="#F4F4F0", bold=True)
    dl = dial("alt", int(0.10 * cv.sx)).resize((int(0.10 * cv.sx), int(0.10 * cv.sy)), Image.LANCZOS)
    cv.img.paste(dl, [int(v) for v in cv.p(0.05, 0.345)])
    for k, lab in enumerate(("SUPPLY", "100%", "EMER")):
        y = 0.31 - k * 0.035
        cv.ellipse(0.25, y, 0.009, fill="#15171A", outline="#B9BEC4", w_m=0.001)
        cv.text(0.27, y, lab, 0.012, anchor="lm")
    # 下：インターホンと灯の調光
    cv.rect(0.02, 0.02, 0.38, 0.19, fill="#25292E", outline="#0E1013", w_m=0.002, rad_m=0.01)
    cv.text(0.20, 0.17, "INTERPHONE", 0.016, bold=True)
    for c in range(4):
        x = 0.07 + c * 0.085
        cv.ellipse(x, 0.10, 0.016, fill="#15171A", outline="#6A7078", w_m=0.0012)
        cv.text(x, 0.06, ["PILOT", "LOAD", "PA", "DIM"][c], 0.011)
    cv.grain(seed=37)
    return cv, {}


def panel(w=PANEL_W, h=PANEL_H):
    atlas = Image.new("RGB", (w, h), PANEL_BG)
    amask = Image.new("L", (w, h), 0)
    items, regions, sizes = {}, {}, {}
    for name, fn in (("dash", dash_panel), ("overhead", overhead_panel), ("console_r", console_r_panel), ("console_l", console_l_panel),
                     ("mcp", mcp_panel), ("cb", cb_panel), ("misc", misc_panel)):
        cv, it = fn()
        cv.paste_into(atlas, amask)
        x0, y0, x1, y1 = cv.box
        regions[name] = [x0 / w, 1 - y1 / h, x1 / w, 1 - y0 / h]
        sizes[name] = [cv.wm, cv.hm]
        items[name] = it
    rgba = atlas.convert("RGBA")
    rgba.putalpha(amask)
    rgba.save(OUT / "fp_panel.png")
    (OUT / "fp_panel.json").write_text(json.dumps({"size": [w, h], "regions": regions, "sizes_m": sizes, "items": items,
                                                   "note": "regions は UV（左下が原点）。sizes_m は領域の実寸、items の座標は領域の左下からの m。アルファは光る所"},
                                                  ensure_ascii=False, indent=1), encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    quilt()
    floor()
    tread()
    paint()
    webbing()
    fabric()
    decals()
    panel()
    print("wrote", sorted(p.name for p in OUT.iterdir()))


if __name__ == "__main__":
    main()

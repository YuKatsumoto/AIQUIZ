"""AIQUIZ STADIUM の手続きテクスチャを作る（決定的・乱数は固定シード）。

    python assets/aiquiz_stadium/source/textures/make_textures.py

- sail_fabric.png        帆の布（UV: u＝ラフ→リーチ、v＝フット→ヘッド）。放射状の縫い目・縁の補強・角の当て布
- booth_screen.png       ブースの画面（青地に白い「?」、枠）。発光に使う
- city_facade_{a,b,c,d,e}.png / _night.png   遠景のビルの外壁（昼の色 / 夜の窓明かり）。1 枚 = 横 8 スパン × 縦 8 階
  （横 28m × 縦 32m）。a 青いガラス、b 白い外壁、c 青緑のガラスと縦のフィン、d 濃紺のガラスと横の帯、e 石張りに縦長の窓。
  距離のかすみは Godot の遠景シェーダーがかけるので、ここではガラスに映る空の色をわずかに入れるだけ
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent
RNG = np.random.default_rng(20260927)


def hexrgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def save(arr: np.ndarray, name: str) -> None:
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(OUT / name, optimize=True)
    print("wrote", name, arr.shape[1], "x", arr.shape[0])


# --- 帆の布 ------------------------------------------------------------------
def sail_fabric(size: int = 1024) -> None:
    v, u = np.mgrid[0:size, 0:size].astype(np.float32) / (size - 1)
    v = 1.0 - v                                   # 画像の上＝ヘッド（v=1）
    base = hexrgb("#F6F3EC")
    img = np.ones((size, size, 3), np.float32) * base
    # 織り目（ごく弱い 2 方向の縞＋ノイズ）
    weave = (np.sin(u * size * 1.9) * np.sin(v * size * 1.9)) * 1.4
    noise = RNG.normal(0.0, 1.0, (size, size)).astype(np.float32)
    noise = np.array(Image.fromarray(((noise + 4) * 30).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 30 - 4
    img += (weave + noise * 1.6)[..., None]
    # 放射状の縫い目（u 一定の線がヘッドへ集まる）。影側に 1 本、光側に 1 本
    for k in range(1, 6):
        uk = k / 6.0
        d = (u - uk) * size
        img -= (np.exp(-(d / 1.3) ** 2) * 14.0)[..., None]
        img += (np.exp(-((d - 2.4) / 1.1) ** 2) * 5.0)[..., None]
    # 縁の補強（ラフ・リーチ・フット）：少し濃い帯とステッチ
    edge = np.minimum(np.minimum(u, 1.0 - u), v * 1.15)
    hem = (edge < 0.022).astype(np.float32)
    img = img * (1 - hem[..., None] * 0.07)
    stitch_d = np.abs(edge - 0.028) * size
    img -= (np.exp(-(stitch_d / 0.9) ** 2) * 10.0)[..., None]
    # 角の当て布（ヘッド・タック・クリュー）
    patch = ((v > 0.86) | ((u < 0.12) & (v < 0.13)) | ((u > 0.88) & (v < 0.13))).astype(np.float32)
    patch = np.array(Image.fromarray((patch * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)), np.float32) / 255
    img = img * (1 - patch[..., None] * 0.045)
    save(img, "sail_fabric.png")


# --- ブースの画面 ------------------------------------------------------------
def booth_screen(w: int = 512, h: int = 320) -> None:
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    top, bottom = hexrgb("#3E8DE8"), hexrgb("#1A4FB0")
    t = (y / (h - 1))[..., None]
    img = top * (1 - t) + bottom * t
    # 周辺を少し暗く、走査線
    r = np.sqrt(((x - w / 2) / (w / 2)) ** 2 + ((y - h / 2) / (h / 2)) ** 2)
    img *= (1.0 - 0.18 * np.clip(r - 0.5, 0, 1))[..., None]
    img *= (1.0 - 0.05 * (np.sin(y * math.pi / 2) > 0.7))[..., None]
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([6, 6, w - 7, h - 7], radius=18, outline=(210, 232, 255), width=6)
    # 白い「?」：円弧＋縦棒＋点（フォントに頼らない）
    cx, cy, rr, th = w / 2, h * 0.36, h * 0.19, h * 0.07
    d.arc([cx - rr, cy - rr, cx + rr, cy + rr], start=180, end=420, fill=(255, 255, 255), width=int(th))
    ex, ey = cx + rr * math.cos(math.radians(60)) - th * 0.35, cy + rr * math.sin(math.radians(60)) - th * 0.35
    d.line([ex, ey, cx, cy + rr * 1.22], fill=(255, 255, 255), width=int(th))
    d.line([cx, cy + rr * 1.18, cx, cy + rr * 1.62], fill=(255, 255, 255), width=int(th))
    d.ellipse([cx - th * 0.75, h * 0.78 - th * 0.75, cx + th * 0.75, h * 0.78 + th * 0.75], fill=(255, 255, 255))
    # 左右に小さな光の点（チームの色）
    for i, col in enumerate(((255, 150, 60), (80, 190, 255))):
        px = w * (0.12 if i == 0 else 0.88)
        for k in range(3):
            py = h * (0.35 + 0.15 * k)
            d.ellipse([px - 7, py - 7, px + 7, py + 7], fill=col)
    im.save(OUT / "booth_screen.png", optimize=True)
    print("wrote booth_screen.png", w, "x", h)


# --- 遠景のビルの外壁 -----------------------------------------------------------
HAZE = hexrgb("#D2E3EE")


def facade(style: str, size: int = 512) -> None:
    bays, floors = 8, 8
    bw, fh = size // bays, size // floors
    y, x = np.mgrid[0:size, 0:size]
    bx, fy = x % bw, y % fh
    cell_x, cell_y = x // bw, y // fh
    img = np.zeros((size, size, 3), np.float32)
    night = np.zeros((size, size, 3), np.float32)
    lit_rng = np.random.default_rng({"a": 11, "b": 22, "c": 33, "d": 44, "e": 55}[style])
    lit = lit_rng.random((floors, bays))
    warm = lit_rng.random((floors, bays))
    tint = lit_rng.normal(0, 1, (floors, bays)).astype(np.float32)
    if style == "a":        # 青いガラスのカーテンウォール
        pane_top, pane_bot = hexrgb("#A9CDE4"), hexrgb("#7FA8C6")
        t = (fy / fh)[..., None]
        img = pane_top * (1 - t) + pane_bot * t
        img += (tint[cell_y, cell_x] * 4.0)[..., None]
        mull = (bx < 3) | (bx > bw - 2)
        slab = fy > fh - 7
        img[mull] = hexrgb("#E1ECF3")
        img[slab] = hexrgb("#BFD2DF")
        win = ~(mull | slab)
        frac, dark = 0.32, 0.0
    elif style == "b":      # 白い外壁に窓のグリッド
        img[:] = hexrgb("#E9ECEE")
        win = (bx > bw * 0.16) & (bx < bw * 0.84) & (fy > fh * 0.2) & (fy < fh * 0.78)
        gl_top, gl_bot = hexrgb("#9DB9CC"), hexrgb("#7C98AE")
        t = (fy / fh)[..., None]
        glass = gl_top * (1 - t) + gl_bot * t
        img[win] = glass[win]
        img += (tint[cell_y, cell_x] * 2.0)[..., None] * win[..., None]
        frac = 0.45
    elif style == "c":      # 縦のフィンが入った青緑のガラス
        pane_top, pane_bot = hexrgb("#9FD0D8"), hexrgb("#76AEBB")
        t = (fy / fh)[..., None]
        img = pane_top * (1 - t) + pane_bot * t
        img += (tint[cell_y, cell_x] * 3.0)[..., None]
        fin = (x % (bw // 2)) < 3
        slab = fy > fh - 4
        img[fin] = hexrgb("#EEF4F5")
        img[slab] = hexrgb("#C3D8DC")
        win = ~(fin | slab)
        frac = 0.26
    elif style == "d":      # 濃紺のガラスの帯と、明るい腰壁の帯（横連窓）
        pane_top, pane_bot = hexrgb("#6F93B4"), hexrgb("#4D6F92")
        t = (fy / fh)[..., None]
        img = pane_top * (1 - t) + pane_bot * t
        img += (tint[cell_y, cell_x] * 3.0)[..., None]
        spandrel = fy > fh * 0.7
        mull = (bx % (bw // 2)) < 2
        img[spandrel] = hexrgb("#B7C7D3")
        img[mull & ~spandrel] = hexrgb("#8FA7BC")
        win = ~(spandrel | mull)
        frac = 0.36
    else:                   # 石張りの外壁に縦長の窓
        img[:] = hexrgb("#E6DCC8")
        img += (lit_rng.normal(0, 1, (size, size)) * 2.0)[..., None]
        win = (bx > bw * 0.3) & (bx < bw * 0.7) & (fy > fh * 0.15) & (fy < fh * 0.8)
        gl_top, gl_bot = hexrgb("#8FA6B6"), hexrgb("#6F8797")
        t = (fy / fh)[..., None]
        glass = gl_top * (1 - t) + gl_bot * t
        img[win] = glass[win]
        cornice = fy > fh - 3
        img[cornice] = hexrgb("#CFC3AC")
        frac = 0.42
    # ガラスに映る空：色を空の色へ 8% だけ寄せる（距離のかすみは Godot の遠景シェーダー）
    img = img * 0.92 + HAZE * 0.08
    # 夜の窓明かり：灯っている窓だけ暖色・寒色で光らせる
    on = (lit[cell_y, cell_x] < frac) & win
    warm_col, cool_col = hexrgb("#FFD49A"), hexrgb("#CFE6FF")
    col = np.where((warm[cell_y, cell_x] < 0.75)[..., None], warm_col, cool_col)
    level = (0.65 + 0.35 * lit_rng.random((floors, bays)))[cell_y, cell_x]
    night[on] = (col * level[..., None])[on]
    save(img, f"city_facade_{style}.png")
    save(night, f"city_facade_{style}_night.png")


if __name__ == "__main__":
    sail_fabric()
    booth_screen()
    for s in ("a", "b", "c", "d", "e"):
        facade(s)

"""AIQUIZ HARBOR LAUNCH（メニューのステージ）のテクスチャを作る。

- sign_aiquiz.png：看板。深い紺地に白い縁と、ゲームのロゴ（リポジトリ直下の icon.jpg）をそのまま白で載せる。
  ロゴは生成し直さず icon.jpg の形を使う（字形をゲームのロゴとそろえる）
- led_idle.png：LED の面。Godot では LED のシェーダー（shaders/aiquiz_menu_led.gdshader）に差し替えるので、
  これは Blender の確認レンダーと、シェーダーが使えないときの予備。橙と水色の斜めの帯を LED の粒で描く
- paving.png：デッキと歩道の舗装
- harbor_facade_*.png / _night.png：ビル群の手前の岸辺の街（ams_waterfront.py）の外壁と夜の窓明かり。建物の型ごとに 10 種
  （shop 地中海の家・flat 集合住宅・glass ガラス面・mansion 横ラインのマンション・tile タイル張り・corridor アパートの外廊下・
  loggia ロッジア・brick レンガ・ribbon 横連窓・punched 不規則な窓）

使い方：python assets/aiquiz_menu_stage/source/textures/make_textures.py
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
LOGO = ROOT / "icon.jpg"

NAVY = (29, 47, 92)          # #1D2F5C 看板の地
NAVY_EDGE = (19, 32, 66)
WHITE = (246, 244, 238)
ORANGE = (242, 140, 51)      # #F28C33（P1）
BLUE = (51, 166, 230)        # #33A6E6（P2）
LED_BG = (14, 22, 44)


def _logo_mask(height_px: int) -> Image.Image:
    """icon.jpg の白いロゴだけを取り出し、高さ height_px の不透明度マスクにする。"""
    grey = Image.open(LOGO).convert("L")
    a = np.asarray(grey).astype(np.float32) / 255.0
    ys, xs = np.where(a > 0.45)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    crop = grey.crop((x0, y0, x1, y1))
    # JPEG のにじみを落として縁を締める（0.25〜0.75 を 0〜1 へ）
    arr = np.asarray(crop).astype(np.float32) / 255.0
    arr = np.clip((arr - 0.25) / 0.5, 0.0, 1.0)
    mask = Image.fromarray((arr * 255).astype(np.uint8), "L")
    scale = height_px / mask.height
    # 大きく拡大してから少しぼかして縮めると、拡大の段差が消える
    big = mask.resize((int(mask.width * scale * 2), height_px * 2), Image.LANCZOS)
    big = big.filter(ImageFilter.GaussianBlur(1.2))
    out = big.resize((int(mask.width * scale), height_px), Image.LANCZOS)
    return out


def make_sign(path: Path, size=(2048, 536)) -> None:
    """看板 13×3.4m（比 3.82）。縁は白い細枠と濃い紺の外枠。"""
    w, h = size
    img = Image.new("RGB", size, NAVY_EDGE)
    d = ImageDraw.Draw(img)
    pad = int(h * 0.045)
    d.rectangle([pad, pad, w - 1 - pad, h - 1 - pad], fill=WHITE)
    inner = pad + int(h * 0.028)
    d.rectangle([inner, inner, w - 1 - inner, h - 1 - inner], fill=NAVY)
    # 地にごく弱い上下の明暗（のっぺり見えないように）
    arr = np.asarray(img).astype(np.float32)
    yy = np.linspace(0.0, 1.0, h)[:, None]
    shade = 1.06 - 0.12 * yy
    body = np.zeros((h, w), bool)
    body[inner:h - inner, inner:w - inner] = True
    arr[body] *= np.repeat(shade, w, axis=1)[body][:, None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    logo = _logo_mask(int(h * 0.50))
    lx = (w - logo.width) // 2
    ly = (h - logo.height) // 2 + int(h * 0.01)
    img.paste(Image.new("RGB", logo.size, WHITE), (lx, ly), logo)
    img.save(path)


def make_led(path: Path, size=(1024, 468), pitch=6) -> None:
    """LED 10.5×4.8m。濃紺の地に橙と水色の斜めの帯、LED の粒と横の走査線。"""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xx / w
    v = yy / h
    img = np.zeros((h, w, 3), np.float32)
    img[:] = np.array(LED_BG, np.float32)
    # 斜めの帯（左に橙、右に水色）：u + 0.55 v の周期
    t = u * 3.2 + v * 1.9
    band = (np.mod(t, 1.0) < 0.42)
    k = np.clip((u - 0.44) / 0.12, 0.0, 1.0)[..., None]        # 橙 → 水色（中央でなめらかに）
    col = np.array(ORANGE, np.float32) * (1.0 - k) + np.array(BLUE, np.float32) * k
    img = np.where(band[..., None], col, img)
    # 中央を暗くして帯を左右へ寄せる（原本の構図：左に橙、右に水色、真ん中は暗い）
    centre = np.exp(-((u - 0.5) / 0.13) ** 2)[..., None]
    img = img * (1.0 - 0.85 * centre) + np.array(LED_BG, np.float32) * 0.85 * centre
    # LED の粒：pitch px ごとの丸い点、点と点のあいだは暗い
    cx = np.mod(xx, pitch) - pitch / 2 + 0.5
    cy = np.mod(yy, pitch) - pitch / 2 + 0.5
    dot = np.clip(1.25 - np.sqrt(cx * cx + cy * cy) / (pitch * 0.42), 0.0, 1.0)[..., None]
    img = img * (0.25 + 0.85 * dot)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(path)


def make_paving(path: Path, size=512, tiles=2, seed=5) -> None:
    """床の舗装：tiles×tiles 枚のタイル（1 枚 1.5m、テクスチャ 1 枚で 3m 角）。白っぽい石の板に細い目地と、板ごとのわずかな色の差。
    頂点色を掛けて使う（明るさは頂点色で決める）。"""
    rnd = np.random.default_rng(seed)
    px = size // tiles
    img = np.zeros((size, size, 3), np.float32)
    base = np.array([236, 236, 234], np.float32)
    for ty in range(tiles):
        for tx in range(tiles):
            tone = 1.0 + rnd.uniform(-0.035, 0.035)
            warm = rnd.uniform(-4, 4)
            img[ty * px:(ty + 1) * px, tx * px:(tx + 1) * px] = base * tone + np.array([warm, warm * 0.5, -warm * 0.5])
    # ごく細かいざらつき
    img += rnd.normal(0.0, 2.2, img.shape[:2])[..., None]
    # 目地（2px、暗い灰色）と目地のわきのわずかな陰
    joint = np.array([170, 174, 180], np.float32)
    for k in range(tiles + 1):
        c = (k * px) % size
        for d, w in ((0, 1.0), (1, 1.0), (2, 0.35), (-1, 0.35)):
            r = (c + d) % size
            img[r, :, :] = img[r, :, :] * (1 - w) + joint * w
            img[:, r, :] = img[:, r, :] * (1 - w) + joint * w
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(path)


def _hex(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def make_harbor_facade(style: str, size: int = 512) -> None:
    """岸辺の街（ams_waterfront.py）の外壁。1 枚 = 横 8 スパン × 縦 8 階（1 スパン 3.2m、1 階 3.2m）。
    昼の色（頂点色のパステルを掛ける：壁はほぼ白）と、夜の窓明かり（*_night.png）。
    shop  ：いちばん下の段が 1 階の店（アーチの開口・暗いガラス）、上は窓（白い枠・窓台・ところどころ掃き出し窓と手すり）
    flat  ：集合住宅・ホテル（大きな掃き出し窓と床の帯。バルコニーは形で付ける）
    glass ：ターミナル・市場のガラス面（縦の方立と横の無目）"""
    bays = floors = 8
    cw = size // bays
    rnd = np.random.default_rng({"shop": 101, "flat": 202, "glass": 303}[style])
    y, x = np.mgrid[0:size, 0:size]
    bx, fy = x % cw, y % cw
    col_i, row_i = x // cw, floors - 1 - y // cw          # row_i：0 がいちばん下の段（UV の v=0 が画像の下）
    img = np.zeros((size, size, 3), np.float32)
    night = np.zeros((size, size, 3), np.float32)
    t = (fy / cw)[..., None]
    lit = rnd.random((floors, bays))
    warm = rnd.random((floors, bays)) < 0.78
    warm_col, cool_col = _hex("#FFD49A"), _hex("#D8E9FF")

    def glass_grad(top, bot):
        return _hex(top) * (1 - t) + _hex(bot) * t

    if style == "shop":
        img[:] = _hex("#F5F2EC")
        img += rnd.normal(0, 1.4, (size, size))[..., None]
        kind = rnd.random((floors, bays))                   # 窓の種類（< 0.3：掃き出し窓と手すり）
        tall = kind[row_i, col_i] < 0.3
        # 上の階の窓
        wx = (bx > cw * 0.28) & (bx < cw * 0.72)
        win = wx & np.where(tall, (fy > cw * 0.16) & (fy < cw * 0.9), (fy > cw * 0.22) & (fy < cw * 0.72)) & (row_i > 0)
        frame = (bx > cw * 0.24) & (bx < cw * 0.76) & np.where(tall, (fy > cw * 0.12) & (fy < cw * 0.92),
                                                                 (fy > cw * 0.18) & (fy < cw * 0.76)) & (row_i > 0)
        img[frame] = _hex("#FFFFFF")
        g = glass_grad("#6E8FA8", "#4F6E88")
        img[win] = g[win]
        # 窓台（普通の窓）と手すり（掃き出し窓）
        sill = (bx > cw * 0.22) & (bx < cw * 0.78) & (fy >= cw * 0.76) & (fy < cw * 0.82) & ~tall & (row_i > 0)
        img[sill] = _hex("#D9D6D0")
        rail = (bx > cw * 0.2) & (bx < cw * 0.8) & tall & (row_i > 0) & (
            ((fy > cw * 0.56) & (fy < cw * 0.6)) | ((fy > cw * 0.84) & (fy < cw * 0.9)) | (((bx % 5) < 1) & (fy > cw * 0.56) & (fy < cw * 0.9)))
        img[rail] = _hex("#3C4652")
        # 鎧戸（普通の窓の両脇、緑か青）と、窓台の下の花箱（緑に赤・桃・黄の花）
        extra = rnd.random((floors, bays))
        shut = ~tall & (row_i > 0) & (extra[row_i, col_i] < 0.3) & (fy > cw * 0.2) & (fy < cw * 0.74) & (
            ((bx > cw * 0.1) & (bx < cw * 0.23)) | ((bx > cw * 0.77) & (bx < cw * 0.9)))
        shut_col = np.where((extra[row_i, col_i] < 0.15)[..., None], _hex("#5E9A8E"), _hex("#6A8DBE"))
        img[shut] = shut_col[shut]
        img[shut & ((fy % 4) == 0)] *= 0.85
        box = ~tall & (row_i > 0) & (extra[row_i, col_i] > 0.62) & (bx > cw * 0.26) & (bx < cw * 0.74) & (fy >= cw * 0.82) & (fy < cw * 0.93)
        img[box] = _hex("#4E8A3E")
        flowers = box & (rnd.random((size, size)) < 0.45) & (fy < cw * 0.88)
        petal = np.array([_hex("#E0463C"), _hex("#F07AA0"), _hex("#F4C542"), _hex("#FFFFFF")])[rnd.integers(0, 4, (size, size))]
        img[flowers] = petal[flowers]
        # 階の境の細い帯
        img[(fy >= cw - 3) & (row_i > 0)] = _hex("#E4E0D8")
        # 1 階：アーチの店先（柱・暗いガラス・上の明るい映り込み）
        ground = row_i == 0
        ox = (bx - cw / 2) / (cw * 0.36)
        top_y = cw * 0.2
        arch_c = top_y + cw * 0.36 * 0.6
        opening = ground & (np.abs(ox) < 1.0) & (fy > arch_c - cw * 0.36 * 0.6 * np.sqrt(np.clip(1 - ox ** 2, 0, 1))) & (fy < cw * 0.97)
        img[ground] = _hex("#ECE7DE")
        shop = glass_grad("#6F8698", "#2E3944")
        img[opening] = shop[opening]
        img[ground & (fy < cw * 0.1)] = _hex("#D8D2C8")          # 1 階の上の帯（看板の場所）
        win_all = win | opening
        on = win_all & ((lit[row_i, col_i] < 0.42) | (ground & (lit[row_i, col_i] < 0.9)))
    elif style == "flat":
        img[:] = _hex("#F3F3F0")
        img += rnd.normal(0, 1.2, (size, size))[..., None]
        win = (bx > cw * 0.12) & (bx < cw * 0.88) & (fy > cw * 0.2) & (fy < cw * 0.86)
        g = glass_grad("#7C9BB2", "#4E6D86")
        img[win] = g[win]
        img[win & (np.abs(bx - cw / 2) < 1.5)] = _hex("#E9ECEE")        # 引き違いの中央の框
        img[(fy >= cw * 0.86) & (fy < cw * 0.9) & (bx > cw * 0.1) & (bx < cw * 0.9)] = _hex("#DADDDF")
        img[fy >= cw - 6] = _hex("#D5D9DC")                                # 床の帯
        # ところどころカーテン（明るい布）
        curtain = win & (rnd.random((floors, bays))[row_i, col_i] < 0.3) & (bx > cw * 0.62)
        img[curtain] = img[curtain] * 0.4 + _hex("#E9E2D2") * 0.6
        win_all = win
        on = win & (lit < 0.4)[row_i, col_i]
    else:
        g = glass_grad("#8FC3D2", "#5F93AA")
        img[:] = g
        img += (rnd.normal(0, 1.0, (floors, bays))[row_i, col_i] * 5.0)[..., None]
        mull = (x % (cw // 2)) < 3
        transom = fy >= cw - 4
        img[mull | transom] = _hex("#F4F6F6")
        win_all = ~(mull | transom)
        on = win_all & (lit < 0.55)[row_i, col_i]
    # 規則的すぎないように：列ごとに窓のない壁（2 列）と、上がアーチの窓（2 列）、幅の違う窓（flat）
    wall_col = img[4, 4].copy()
    if style == "shop":
        cols = rnd.permutation(bays)
        blank_cols, arch_cols = cols[:2], cols[2:4]
        for c in blank_cols:
            for r in range(1, floors):
                if rnd.random() < 0.75:
                    y0 = (floors - 1 - r) * cw
                    img[y0 + 5:y0 + cw - 4, c * cw + 5:c * cw + cw - 5] = wall_col + rnd.normal(0, 1.2, (cw - 9, cw - 10, 1))
                    win_all[y0:y0 + cw, c * cw:(c + 1) * cw] = False
        for c in arch_cols:
            for r in range(1, floors):
                y0 = (floors - 1 - r) * cw
                rr = cw * 0.24
                cx, cy = c * cw + cw / 2, y0 + cw * 0.16 + rr
                yy, xx = np.mgrid[y0:y0 + int(cy - y0), c * cw:(c + 1) * cw]
                outside = ((xx - cx) ** 2 + (yy - cy) ** 2 > rr ** 2) & (np.abs(xx - cx) < cw * 0.3)
                patch = img[y0:y0 + int(cy - y0), c * cw:(c + 1) * cw]
                patch[outside] = wall_col
                win_all[y0:y0 + int(cy - y0), c * cw:(c + 1) * cw][outside] = False
        on = on & win_all
    elif style == "flat":
        for c in rnd.permutation(bays)[:3]:
            inset = int(cw * rnd.uniform(0.18, 0.3))
            for r in range(floors):
                y0 = (floors - 1 - r) * cw
                for xa, xb in ((c * cw + 4, c * cw + inset), ((c + 1) * cw - inset, (c + 1) * cw - 4)):
                    img[y0 + 10:y0 + cw - 8, xa:xb] = wall_col
                    win_all[y0 + 10:y0 + cw - 8, xa:xb] = False
        on = on & win_all
    img = img * 0.94 + _hex("#D2E3EE") * 0.06
    level = (0.62 + 0.38 * rnd.random((floors, bays)))[row_i, col_i][..., None]
    colr = np.where(warm[row_i, col_i][..., None], warm_col, cool_col)
    night[on] = (colr * level)[on]
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(HERE / f"harbor_facade_{style}.png", optimize=True)
    Image.fromarray(np.clip(night, 0, 255).astype(np.uint8)).save(HERE / f"harbor_facade_{style}_night.png", optimize=True)


# --- 岸辺の街：住宅の型ごとの外壁（2026-09-29 追加） --------------------------------------
# アパート・マンションの外観の型（Web の資料と Codex の見本帳 r7）ごとに、窓の大きさ・位置・まとまりを変える。
# どれも 1 枚 = 横 8 スパン × 縦 8 階（1 マス 64px）。建物ごとにスパンと階の高さを変えて貼るので、隣と窓の高さがそろわない。
# 壁はほぼ白〜淡い色で、頂点色（建物の色）を掛ける。夜の窓明かりは *_night.png。
class _Sheet:
    def __init__(self, seed, size=512, cells=8):
        self.n, self.cw, self.size = cells, size // cells, size
        self.rnd = np.random.default_rng(seed)
        self.img = np.zeros((size, size, 3), np.float32)
        self.night = np.zeros((size, size, 3), np.float32)

    def floor_top(self, r):
        """r 階（0 がいちばん下）の上端の画素の行。"""
        return (self.n - 1 - r) * self.cw

    def rect(self, x0, y0, x1, y1, col, night=None):
        x0, y0, x1, y1 = (int(round(v)) for v in (x0, y0, x1, y1))
        x0, x1 = max(0, x0), min(self.size, x1)
        y0, y1 = max(0, y0), min(self.size, y1)
        if x1 <= x0 or y1 <= y0:
            return
        self.img[y0:y1, x0:x1] = col
        if night is not None:
            self.night[y0:y1, x0:x1] = night

    def glass(self, x0, y0, x1, y1, top="#7C9AB2", bot="#4C6A84", lit=None):
        h = max(1, int(round(y1)) - int(round(y0)))
        t = np.linspace(0, 1, h)[:, None, None]
        g = _hex(top) * (1 - t) + _hex(bot) * t
        xs0, xs1 = int(round(x0)), int(round(x1))
        ys0 = int(round(y0))
        self.img[ys0:ys0 + h, xs0:xs1] = g
        if lit is not None:
            self.night[ys0:ys0 + h, xs0:xs1] = lit

    def lit(self, p=0.42):
        if self.rnd.random() >= p:
            return None
        base = _hex("#FFD49A") if self.rnd.random() < 0.78 else _hex("#D8E9FF")
        return base * (0.62 + 0.38 * self.rnd.random())

    def noise(self, amount=1.3):
        self.img += self.rnd.normal(0, amount, self.img.shape[:2])[..., None]

    def save(self, name):
        img = self.img * 0.94 + _hex("#D2E3EE") * 0.06
        Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(HERE / f"harbor_facade_{name}.png", optimize=True)
        Image.fromarray(np.clip(self.night, 0, 255).astype(np.uint8)).save(HERE / f"harbor_facade_{name}_night.png", optimize=True)


def facade_mansion():
    """横ラインのマンション（バルコニーの帯は形で付ける）：2 スパンの住戸ごとに引き違いのガラス戸 4 枚、住戸の間の柱、床の帯。"""
    s = _Sheet(404)
    s.img[:] = _hex("#EEEEEA")
    s.noise()
    for r in range(s.n):
        y = s.floor_top(r)
        for u in range(s.n // 2):
            x = u * s.cw * 2
            s.rect(x, y, x + 7, y + s.cw, _hex("#E1E1DC"))                     # 住戸の境の柱
            lit = s.lit(0.4)
            kind = s.rnd.random()
            panes = 4 if kind < 0.7 else 3
            gx0, gx1 = x + 12, x + 2 * s.cw - 6
            pw = (gx1 - gx0) / panes
            for k in range(panes):
                s.glass(gx0 + k * pw + 1, y + 6, gx0 + (k + 1) * pw - 1, y + s.cw - 8, lit=lit)
                if s.rnd.random() < 0.3:                                        # カーテン・ブラインド
                    cc = _hex(["#E8DDCB", "#DCE4EC", "#EDE6D8", "#C9D3DC"][s.rnd.integers(0, 4)])
                    s.rect(gx0 + k * pw + 1, y + 6, gx0 + (k + 1) * pw - 1, y + 6 + s.rnd.integers(8, 40), cc)
            s.rect(x, y + s.cw - 6, x + 2 * s.cw, y + s.cw, _hex("#D6DADC"))   # 床の帯
    s.save("mansion")


def facade_tile():
    """縦ラインのタイル張りのマンション：二丁掛けタイル、縦長の窓の列と柱、ところどころ凹んだバルコニー。"""
    s = _Sheet(505)
    base = _hex("#DDD0C0")
    s.img[:] = base
    th, tw = 3, 7
    for yy in range(0, s.size, th):
        off = (yy // th % 2) * 3
        for xx in range(-off, s.size, tw):
            s.rect(xx, yy, xx + tw - 1, yy + th - 1, base * (1.0 + s.rnd.uniform(-0.05, 0.05)))
    layout = [1, 1, 0, 1, 1, 0, 1, 0]                     # 1：窓の列、0：柱（タイル）
    for r in range(s.n):
        y = s.floor_top(r)
        for c in range(s.n):
            if not layout[c]:
                continue
            x = c * s.cw
            if s.rnd.random() < 0.14:                     # 凹んだバルコニー
                s.glass(x + 4, y + 4, x + s.cw - 4, y + s.cw - 6, "#48525E", "#5E6B78", lit=s.lit(0.3))
                s.rect(x + 4, y + 38, x + s.cw - 4, y + 42, _hex("#D5DADD"))
                continue
            lit = s.lit()
            s.rect(x + 8, y + 5, x + s.cw - 8, y + 50, _hex("#F2F2EF"))
            s.glass(x + 10, y + 7, x + s.cw - 10, y + 48, lit=lit)
            if s.rnd.random() < 0.5:
                s.rect(x + 10, y + 20, x + s.cw - 10, y + 22, _hex("#F2F2EF"))   # 欄間の横桟
    s.save("tile")


def facade_corridor():
    """外廊下の側（アパート）：横張りのサイディング、2 スパンの住戸ごとに玄関扉・格子の小窓・メーター・玄関灯。"""
    s = _Sheet(606)
    s.img[:] = _hex("#EDEDE9")
    for yy in range(0, s.size, 5):
        s.rect(0, yy, s.size, yy + 1, _hex("#E0E0DB"))
    for r in range(s.n):
        y = s.floor_top(r)
        for u in range(s.n // 2):
            x = u * s.cw * 2
            door = _hex(["#7A6450", "#56616E", "#3E4E6A", "#8C7A62"][s.rnd.integers(0, 4)])
            s.rect(x + 14, y + 12, x + 42, y + s.cw, _hex("#C9CCCE"))
            s.rect(x + 16, y + 14, x + 40, y + s.cw, door)
            s.rect(x + 34, y + 38, x + 37, y + 44, _hex("#D9D2BF"))
            s.rect(x + 24, y + 5, x + 32, y + 9, _hex("#F3E6BF"), night=_hex("#FFD89C"))      # 玄関灯
            lit = s.lit(0.45)
            s.glass(x + 62, y + 16, x + 96, y + 38, "#D6E0E7", "#BFCBD4", lit=lit)
            for bx_ in range(64, 96, 4):
                s.rect(x + bx_, y + 16, x + bx_ + 1, y + 38, _hex("#98A2AA"))
            s.rect(x + 104, y + 20, x + 114, y + 34, _hex("#C4C8CB"))
    s.save("corridor")


def facade_loggia():
    """ロッジア（凹んだバルコニー）が階ごとに市松に並ぶ。凹みは暗く、手すりの桟と奥の戸。凹みでない所は窓 1 つ。"""
    s = _Sheet(707)
    s.img[:] = _hex("#F1EBE1")
    s.noise()
    shift = s.rnd.integers(0, 2, s.n)
    for r in range(s.n):
        y = s.floor_top(r)
        for u in range(s.n // 2):
            x = u * s.cw * 2
            recess = (r + u + shift[r // 2 * 2]) % 2 == 0
            if s.rnd.random() < 0.15:
                recess = not recess
            if recess:
                s.glass(x + 8, y + 4, x + 2 * s.cw - 8, y + s.cw - 4, "#3A4450", "#5A6774")
                s.glass(x + 22, y + 10, x + 2 * s.cw - 22, y + 44, "#6E8499", "#556B80", lit=s.lit(0.45))
                s.rect(x + 8, y + 36, x + 2 * s.cw - 8, y + 39, _hex("#DDE1E3"))
                for px_ in range(x + 10, x + 2 * s.cw - 8, 7):
                    s.rect(px_, y + 39, px_ + 1, y + s.cw - 4, _hex("#C8CDD0"))
                if s.rnd.random() < 0.35:
                    s.rect(x + 12, y + 44, x + 40, y + 52, _hex("#5C9A4A"))           # 植木
            else:
                s.rect(x + 42, y + 10, x + 86, y + 48, _hex("#FFFFFF"))
                s.glass(x + 45, y + 13, x + 83, y + 45, lit=s.lit())
                s.rect(x + 40, y + 48, x + 88, y + 51, _hex("#DAD5CC"))
    s.save("loggia")


def facade_brick():
    """レンガ（運河の家・出窓の建物）：長手積み、白い枠の縦長の窓、石のまぐさと窓台、上がアーチの窓の列。"""
    s = _Sheet(808)
    base = _hex("#E6D8CD")
    s.img[:] = _hex("#F1EBE4")
    bh, bw = 5, 12
    for yy in range(0, s.size, bh):
        off = (yy // bh % 2) * (bw // 2)
        for xx in range(-off, s.size, bw):
            s.rect(xx, yy, xx + bw - 1, yy + bh - 1, base * (1.0 + s.rnd.uniform(-0.08, 0.06)))
    arch_cols = set(s.rnd.permutation(s.n)[:3].tolist())
    for r in range(s.n):
        y = s.floor_top(r)
        for c in range(s.n):
            x = c * s.cw
            if s.rnd.random() < 0.08:
                continue
            s.rect(x + 16, y + 4, x + s.cw - 16, y + 9, _hex("#F4F1EA"))              # まぐさ
            s.rect(x + 19, y + 9, x + s.cw - 19, y + 53, _hex("#FFFFFF"))
            s.glass(x + 22, y + 12, x + s.cw - 22, y + 51, lit=s.lit())
            s.rect(x + s.cw / 2 - 1, y + 12, x + s.cw / 2 + 1, y + 51, _hex("#FFFFFF"))
            s.rect(x + 22, y + 28, x + s.cw - 22, y + 30, _hex("#FFFFFF"))
            s.rect(x + 17, y + 53, x + s.cw - 17, y + 56, _hex("#EFEBE3"))           # 窓台
            if c in arch_cols:
                rr = (s.cw - 38) / 2
                cx, cy = x + s.cw / 2, y + 12 + rr
                yy_, xx_ = np.mgrid[y + 4:int(cy), x + 16:x + s.cw - 16]
                out = (xx_ - cx) ** 2 + (yy_ - cy) ** 2 > (rr + 3) ** 2
                patch = s.img[y + 4:int(cy), x + 16:x + s.cw - 16]
                patch[out] = base
                s.night[y + 4:int(cy), x + 16:x + s.cw - 16][out] = 0
    s.save("brick")


def facade_ribbon():
    """横連窓（モダニズム）：階ごとに全幅のガラスの帯と白い腰壁、細い方立。"""
    s = _Sheet(909)
    s.img[:] = _hex("#F4F4F1")
    s.noise(1.0)
    for r in range(s.n):
        y = s.floor_top(r)
        s.rect(0, y + 7, s.size, y + 9, _hex("#9EA8AE"))
        for k in range(s.n * 2):
            x = k * s.cw / 2
            s.glass(x + 1, y + 9, x + s.cw / 2 - 1, y + 42, "#8FBCCD", "#5B8BA4", lit=s.lit(0.45))
        s.rect(0, y + 42, s.size, y + 44, _hex("#9EA8AE"))
    s.save("ribbon")


def facade_punched():
    """不規則な窓（現代の集合住宅）：階ごとに大きさの違う窓を位置をずらして散らす。濃い色の細い枠。"""
    s = _Sheet(1010)
    s.img[:] = _hex("#F2EFE9")
    s.noise()
    widths = [14, 20, 26, 34, 46, 60, 80]
    heights = [20, 26, 34, 42, 48]
    for r in range(s.n):
        y = s.floor_top(r)
        x = s.rnd.integers(4, 26)
        while True:
            w = int(s.rnd.choice(widths))
            h = int(s.rnd.choice(heights))
            if x + w > s.size - 6:
                break
            top = y + s.rnd.integers(5, max(6, s.cw - 6 - h))
            s.rect(x - 2, top - 2, x + w + 2, top + h + 2, _hex("#3E4650"))
            s.glass(x, top, x + w, top + h, lit=s.lit())
            if s.rnd.random() < 0.25:
                accent = _hex(["#E4C9A6", "#C9D9E2", "#D8C8E0", "#CFE0C8"][s.rnd.integers(0, 4)])
                s.rect(x + w + 2, top - 2, x + w + 10, top + h + 2, accent)
                x += 8
            x += w + int(s.rnd.integers(10, 64))
    s.save("punched")


def main() -> None:
    make_sign(HERE / "sign_aiquiz.png")
    make_led(HERE / "led_idle.png")
    make_paving(HERE / "paving.png")
    for style in ("shop", "flat", "glass"):
        make_harbor_facade(style)
    for fn in (facade_mansion, facade_tile, facade_corridor, facade_loggia, facade_brick, facade_ribbon, facade_punched):
        fn()
    print("textures:", [p.name for p in sorted(HERE.glob("*.png"))])


if __name__ == "__main__":
    main()

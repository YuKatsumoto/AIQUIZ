"""着地台（landing_float）のテクスチャを描く。仕様：docs/sudden_death_v2/parachute.md 6.5節、形は blender/build_landing_float.py。

  python assets/sudden_death/parachute/landing_float/source/make_float_textures.py

出力（source/textures/）：
  lf_pad.png       着地面（上から見た円、2048²。半径 PAD_TEX_R m が画像の内接円）。グレーのマットにオレンジの輪 1 本と中心の印。
                   すべり止めの溝・縫い目・すり傷・足あと・日焼け
  lf_pad_orm.png   着地面の ORM（R=1、G=粗さ、B=0）。水たまりだけ粗さを下げる
  lf_tube.png      浮き輪（4096×512、明るいグレー 1 色）。横＝輪のまわり（12 部屋）、縦＝管の断面の角度 phi（v = (phi + 90°) / 360°。
                   v=0 が管の真下＝水の中なので、継ぎ目は見えない。0.25＝外側の赤道、0.5＝真上、0.75＝内側の赤道）
  lf_tube_orm.png  浮き輪の ORM（ぬれた下側と喫水線をつやっぽく）
2026-10-18：派手すぎたので、オレンジと白の部屋・「？」の印・市松・目盛り・矢じり・旗をやめてシンプルにした（ユーザーの指示）。
文字は使わない。乱数の種は固定なので、何度描いても同じ画像になる。
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
OUT = HERE / "textures"
ROOT = HERE.parents[4]
FONT = str(ROOT / "resources" / "fonts" / "NotoSansJP-Bold.otf")

# 形と合わせる数値（build_landing_float.py と同じ値）
PAD_TEX_R = 3.2          # 着地面のテクスチャの半径（m）
RING_R = 3.55            # 浮き輪の中心の半径
TUBE_R = 0.52            # 管の半径
TUBE_Z = 0.28            # 管の中心の高さ（喫水線＝0）
CHAMBERS = 12

ORANGE = (232, 122, 42)
WHITE = (244, 242, 236)
## 着地面のマット（明るいグレー）と浮き輪（少し暖かい明るいグレー）
FOAM = (196, 198, 198)
TUBE = (222, 221, 216)
NAVY = (29, 47, 92)
SEAM = (196, 194, 188)
GRIME = (92, 98, 70)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def qmark(size, color, outline=None, outline_w=0):
    """「？」の印（正方形の RGBA）。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, int(size * 0.92))
    d.text((size / 2, size / 2 + size * 0.04), "？", font=f, fill=color, anchor="mm",
           stroke_width=outline_w, stroke_fill=outline)
    return img


def noise_layer(size, scale, seed, blur):
    rnd = random.Random(seed)
    w, h = size
    small = Image.new("L", (max(2, w // scale), max(2, h // scale)))
    small.putdata([rnd.randint(0, 255) for _ in range(small.width * small.height)])
    return small.resize(size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(blur))


# ---------------------------------------------------------------- 着地面

SS = 2   # 2 倍で描いて縮める（ふちをなめらかに）


def pad():
    S = 2048 * SS
    px_m = S / (2 * PAD_TEX_R)
    c = S / 2
    img = Image.new("RGB", (S, S), FOAM)
    d = ImageDraw.Draw(img)

    def circle(r_m, fill):
        r = r_m * px_m
        d.ellipse((c - r, c - r, c + r, c + r), fill=fill)

    # グレーのマットに、着地の目印のオレンジの輪（1.45〜1.62 m）と中心の小さな丸だけ。
    circle(PAD_TEX_R, FOAM)
    circle(1.62, ORANGE)
    circle(1.45, FOAM)
    circle(0.14, ORANGE)

    # すべり止めの菱形の溝（色の明るさに合わせて少し暗く）
    groove = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(groove)
    step = 0.032 * px_m
    n = int(S / step) + 2
    for i in range(-n, n):
        x = i * step
        gd.line((x, 0, x + S, S), fill=255, width=SS)
        gd.line((x, S, x + S, 0), fill=255, width=SS)
    shade = Image.new("RGB", (S, S), (0, 0, 0))
    img = Image.composite(shade, img, groove.point(lambda v: int(v * 0.07)))

    # 縫い目（帯のふちに沿った点線）
    d = ImageDraw.Draw(img)
    for r_m in (1.43, 1.64, 2.95):
        r = r_m * px_m
        dots = int(2 * math.pi * r / (14 * SS))
        for k in range(dots):
            a0 = 2 * math.pi * k / dots
            a1 = a0 + 2 * math.pi / dots * 0.55
            d.line((c + r * math.cos(a0), c + r * math.sin(a0), c + r * math.cos(a1), c + r * math.sin(a1)),
                   fill=(70, 72, 80), width=2 * SS)

    # 汚れ：すり傷（中心ほど多い）・足あと・ふちの汚れ・日焼けのむら
    rnd = random.Random(7)
    wear = Image.new("L", (S, S), 0)
    wd = ImageDraw.Draw(wear)
    for _ in range(200):
        rr = abs(rnd.gauss(0, 1.1)) * px_m
        a = rnd.uniform(0, 2 * math.pi)
        x, y = c + rr * math.cos(a), c + rr * math.sin(a)
        ang = rnd.uniform(0, math.pi)
        ln = rnd.uniform(0.04, 0.28) * px_m
        wd.line((x, y, x + ln * math.cos(ang), y + ln * math.sin(ang)), fill=rnd.randint(30, 80), width=rnd.choice([2, 3]) * SS)
    # 足あと（ブロックマンの靴：角の丸い長方形、つま先とかかとの 2 つ）
    for _ in range(26):
        rr = abs(rnd.gauss(0, 0.8)) * px_m
        a = rnd.uniform(0, 2 * math.pi)
        x, y = c + rr * math.cos(a), c + rr * math.sin(a)
        ang = rnd.uniform(0, 2 * math.pi)
        for off, (lw, lh) in ((0.0, (0.11, 0.09)), (0.15, (0.09, 0.07))):
            fx, fy = x + off * px_m * math.cos(ang), y + off * px_m * math.sin(ang)
            w2, h2 = lw * px_m / 2, lh * px_m / 2
            wd.rounded_rectangle((fx - w2, fy - h2, fx + w2, fy + h2), 6 * SS, fill=rnd.randint(25, 55))
    wear = wear.filter(ImageFilter.GaussianBlur(1.2 * SS))
    rim = Image.new("L", (S, S), 0)
    rd = ImageDraw.Draw(rim)
    for k in range(40):
        r = (3.2 - k * 0.012) * px_m
        rd.ellipse((c - r, c - r, c + r, c + r), fill=int(90 * (1 - k / 40)))
    rd.ellipse((c - 2.72 * px_m, c - 2.72 * px_m, c + 2.72 * px_m, c + 2.72 * px_m), fill=0)
    rim = rim.filter(ImageFilter.GaussianBlur(12 * SS))
    dirt = ImageChops.lighter(wear, rim)
    img = Image.composite(Image.new("RGB", (S, S), (110, 108, 96)), img, dirt.point(lambda v: int(v * 0.75)))
    fade = noise_layer((S, S), 64 * SS, 3, 18 * SS)
    img = Image.blend(img, Image.composite(Image.new("RGB", (S, S), (250, 246, 236)), img, fade.point(lambda v: max(0, v - 120))), 0.18)

    # 粗さ：水たまり（中心から外れたところに 5 つ）とふちのぬれ
    orm = Image.new("RGB", (S, S), (255, int(0.82 * 255), 0))
    rough = Image.new("L", (S, S), int(0.82 * 255))
    pd = ImageDraw.Draw(rough)
    for _ in range(5):
        rr = rnd.uniform(1.3, 2.6) * px_m
        a = rnd.uniform(0, 2 * math.pi)
        x, y = c + rr * math.cos(a), c + rr * math.sin(a)
        for _ in range(4):
            ox, oy = rnd.uniform(-0.12, 0.12) * px_m, rnd.uniform(-0.12, 0.12) * px_m
            rx, ry = rnd.uniform(0.08, 0.22) * px_m, rnd.uniform(0.06, 0.16) * px_m
            pd.ellipse((x + ox - rx, y + oy - ry, x + ox + rx, y + oy + ry), fill=int(0.18 * 255))
    rough = rough.filter(ImageFilter.GaussianBlur(5 * SS))
    rough = ImageChops.darker(rough, Image.eval(rim, lambda v: 255 - int(v * 1.6)))
    orm = Image.merge("RGB", (Image.new("L", (S, S), 255), rough, Image.new("L", (S, S), 0)))
    # 水たまりは色も少し濃く
    wet = Image.eval(rough, lambda v: max(0, 120 - v) * 2)
    img = Image.composite(Image.new("RGB", (S, S), (150, 150, 140)), img, wet.point(lambda v: int(v * 0.25)))
    half = (S // SS, S // SS)
    return img.resize(half, Image.LANCZOS), orm.resize(half, Image.LANCZOS)


# ---------------------------------------------------------------- 浮き輪

def tube():
    W, H = 4096, 512
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    cw = W / CHAMBERS
    d.rectangle((0, 0, W, H), fill=TUBE)

    def v_of(phi_deg):
        return ((phi_deg + 90.0) % 360) / 360 * H

    # 溶着の継ぎ目（部屋の境目。幅 2 cm の濃い帯と、両側の点線）
    for k in range(CHAMBERS + 1):
        x = k * cw
        d.rectangle((x - 4, 0, x + 4, H), fill=SEAM)
        for side in (-11, 11):
            for y in range(0, H, 14):
                d.line((x + side, y, x + side, y + 7), fill=(90, 88, 84), width=2)
    # しわ（部屋の境目の近くに細い影）
    rnd = random.Random(11)
    wr = Image.new("L", (W, H), 0)
    wd = ImageDraw.Draw(wr)
    for k in range(CHAMBERS + 1):
        x = k * cw
        for _ in range(9):
            side = rnd.choice([-1, 1])
            x0 = x + side * rnd.uniform(14, 60)
            y0 = rnd.uniform(0, H)
            wd.line((x0, y0, x0 + side * rnd.uniform(20, 70), y0 + rnd.uniform(-40, 40)), fill=rnd.randint(30, 70), width=3)
    wr = wr.filter(ImageFilter.GaussianBlur(3))
    img = Image.composite(Image.new("RGB", (W, H), (60, 56, 50)), img, wr)

    # 喫水線の汚れ：行ごとに管の高さ z を求め、水の中（z < 0）は濃く、水面の上 6 cm までを薄く
    grime = Image.new("L", (W, H), 0)
    gd = ImageDraw.Draw(grime)
    for y in range(H):
        phi = (H - 0.5 - y) / H * 360.0 - 90.0
        z = TUBE_Z + TUBE_R * math.sin(math.radians(phi))
        strength = 150 if z < 0 else max(0.0, 110 * (1 - z / 0.07))
        gd.line((0, y, W, y), fill=int(strength))
    grime = ImageChops.multiply(grime, noise_layer((W, H), 24, 5, 6).point(lambda v: 90 + v // 2))
    img = Image.composite(Image.new("RGB", (W, H), GRIME), img, grime.point(lambda v: int(v * 0.8)))
    # 日焼けのむら
    fade = noise_layer((W, H), 48, 9, 14)
    img = Image.composite(Image.new("RGB", (W, H), (252, 248, 240)), img, fade.point(lambda v: int(max(0, v - 150) * 0.35)))

    # 粗さ：上は 0.55（ビニールのつや）、喫水線から下は 0.30（ぬれ）
    rough = Image.new("L", (W, H), int(0.55 * 255))
    rd = ImageDraw.Draw(rough)
    for y in range(H):
        phi = (H - 0.5 - y) / H * 360.0 - 90.0
        z = TUBE_Z + TUBE_R * math.sin(math.radians(phi))
        if z < 0.06:
            rd.line((0, y, W, y), fill=int((0.30 + max(0.0, z) * 4.0) * 255))
    orm = Image.merge("RGB", (Image.new("L", (W, H), 255), rough, Image.new("L", (W, H), 0)))
    return img, orm


# ---------------------------------------------------------------- 旗

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    p, porm = pad()
    p.save(OUT / "lf_pad.png")
    porm.save(OUT / "lf_pad_orm.png")
    t, torm = tube()
    t.save(OUT / "lf_tube.png")
    torm.save(OUT / "lf_tube_orm.png")
    old = OUT / "lf_decal.png"
    if old.exists():
        old.unlink()
    print("wrote", sorted(x.name for x in OUT.glob("lf_*.png")))


if __name__ == "__main__":
    main()

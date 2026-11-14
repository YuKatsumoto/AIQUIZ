"""メニューの画像を作る (クイズの壁の面・ベルトの桟・UI の影)。

    python SourceAssets/Menu/make_menu_textures.py

Generated/ に PNG を書き出す。UE へは Tools/MenuLevel の Python (AssetImportTask) で取り込む。
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "Generated")
FONT = os.path.join(HERE, "..", "..", "Content", "Slate", "Fonts", "NotoSansJP-Bold.ttf")
LOGO = os.path.join(HERE, "T_TestopiaLogo.png")

# 壁 1 枚 = 23m x 5.75m (4:1)。RGB = 色、A = 光る所 (問題の板と扉)
WALL_W, WALL_H = 4096, 1024
WALL_M = 23.0
PX_PER_M = WALL_W / WALL_M
WALL_COLOR = (92, 102, 128)
RED = (188, 30, 42)
BLUE = (32, 132, 220)
BOARD = (14, 24, 66)

WALLS = [
    ("【食料自給率】私たちが食べる食料のうち、国内でどれ\nだけ作られているかを示す割合を何というでしょう？", ("食料消費率", RED), ("食料自給率", BLUE)),
    ("【けいさん】6＋9は\nいくつですか？", ("15", BLUE), ("14", RED)),
    ("四角い金ぞくの板の真ん中を熱すると、\n熱はどのように伝わりますか？", ("熱した所から\n一方向だけに\n進む", BLUE), ("熱した所から、\nまわりへ\n広がる", RED)),
    ("【ちり】日本でいちばん\n高い山はどれでしょう？", ("富士山", RED), ("北岳", BLUE)),
]

# ロゴの影の余白 (TestopiaMenuWidget.cpp の PadRatio と合わせる)
LOGO_SHADOW_W = 1288
LOGO_SHADOW_PAD = 48


def font(size):
    return ImageFont.truetype(FONT, size)


def fit_font(draw, text, max_w, max_h, start):
    size = start
    while size > 10:
        f = font(size)
        box = draw.multiline_textbbox((0, 0), text, font=f, spacing=size * 0.25, align="center")
        if box[2] - box[0] <= max_w and box[3] - box[1] <= max_h:
            return f, size
        size -= 2
    return font(10), 10


def shade(color, amount):
    return tuple(max(0, min(255, int(c + amount))) for c in color)


def make_wall(index, question, left, right):
    img = Image.new("RGB", (WALL_W, WALL_H), WALL_COLOR)
    glow = Image.new("L", (WALL_W, WALL_H), 0)
    d = ImageDraw.Draw(img)
    g = ImageDraw.Draw(glow)

    # 壁の地：上から下へわずかに暗く、2.3m ごとのパネルの継ぎ目、上の笠木
    for y in range(WALL_H):
        t = y / WALL_H
        d.line([(0, y), (WALL_W, y)], fill=shade(WALL_COLOR, 10 * (1.0 - t) - 8 * t))
    seam = int(2.3 * PX_PER_M)
    for x in range(seam, WALL_W, seam):
        d.line([(x, 0), (x, WALL_H)], fill=shade(WALL_COLOR, -22), width=3)
        d.line([(x + 3, 0), (x + 3, WALL_H)], fill=shade(WALL_COLOR, 16), width=1)
    d.rectangle([0, 0, WALL_W, 18], fill=shade(WALL_COLOR, 44))
    d.rectangle([0, 18, WALL_W, 22], fill=shade(WALL_COLOR, -26))

    # 扉 2 枚 (幅 3.6m、高さ 2.4m、中心は壁の中心から ±3.3m)
    door_w, door_h = int(3.6 * PX_PER_M), int(2.4 * PX_PER_M)
    for (label, color), cx_m in ((left, -3.3), (right, 3.3)):
        cx = WALL_W / 2 + cx_m * PX_PER_M
        x0, y0 = int(cx - door_w / 2), WALL_H - door_h
        frame = 10
        d.rectangle([x0 - frame, y0 - frame, x0 + door_w + frame, WALL_H], fill=(226, 232, 244))
        for y in range(y0, WALL_H):
            t = (y - y0) / door_h
            d.line([(x0, y), (x0 + door_w, y)], fill=shade(color, 22 * (1.0 - t) - 26 * t))
        g.rectangle([x0, y0, x0 + door_w, WALL_H], fill=200)
        f, size = fit_font(d, label, door_w - 70, door_h - 70, 128)
        d.multiline_text((cx + 3, y0 + door_h / 2 + 4), label, font=f, fill=shade(color, -70), anchor="mm", spacing=size * 0.25, align="center")
        d.multiline_text((cx, y0 + door_h / 2), label, font=f, fill=(255, 255, 255), anchor="mm", spacing=size * 0.25, align="center")

    # 問題の板 (扉の上)
    top_h = WALL_H - door_h
    f, size = fit_font(d, question, WALL_W * 0.62, top_h - 130, 92)
    box = d.multiline_textbbox((0, 0), question, font=f, spacing=size * 0.3, align="center")
    tw, th = box[2] - box[0], box[3] - box[1]
    cx, cy = WALL_W / 2, top_h / 2 + 10
    pad_x, pad_y = 56, 36
    rect = [cx - tw / 2 - pad_x, cy - th / 2 - pad_y, cx + tw / 2 + pad_x, cy + th / 2 + pad_y]
    d.rounded_rectangle(rect, radius=14, fill=BOARD, outline=(214, 224, 248), width=6)
    g.rounded_rectangle(rect, radius=14, fill=255)
    d.multiline_text((cx, cy), question, font=f, fill=(255, 255, 255), anchor="mm", spacing=size * 0.3, align="center")

    img.putalpha(glow)
    img.save(os.path.join(OUT, "T_MenuWall_%02d.png" % index))


def belt_height(t):
    """桟 1 本ぶんの断面 (0 = 溝の底、1 = 桟の上面)。t は進行方向 0..1。"""
    if t < 0.07:
        return 0.0
    if t < 0.13:
        return (t - 0.07) / 0.06
    if t > 0.97:
        return (1.0 - t) / 0.03
    return 1.0


def make_belt():
    """桟 1 本ぶん (進行方向に 2m)。縦がベルトの進む向き。RGB = 色、A = 粗さ。法線は別の画像。"""
    w, h = 64, 512
    img = Image.new("RGBA", (w, h))
    nrm = Image.new("RGB", (w, h))
    d, dn = ImageDraw.Draw(img), ImageDraw.Draw(nrm)
    for y in range(h):
        t = (y + 0.5) / h
        k = belt_height(t)
        v = int(44 + (104 - 44) * k - 10 * max(0.0, t - 0.2))
        rough = int(255 * (0.85 - 0.33 * k))
        d.line([(0, y), (w, y)], fill=(v, v + 4, v + 12, rough))
        # 高さの傾きから法線 (接空間、G が進行方向)
        slope = (belt_height(min(1.0, t + 0.004)) - belt_height(max(0.0, t - 0.004))) / 0.008
        ny = -slope * 0.035
        nz = 1.0
        ln = math.sqrt(ny * ny + nz * nz)
        dn.line([(0, y), (w, y)], fill=(128, int(128 + 127 * ny / ln), int(128 + 127 * nz / ln)))
    img.save(os.path.join(OUT, "T_MenuBeltSlat.png"))
    nrm.save(os.path.join(OUT, "T_MenuBeltSlat_N.png"))


def make_ui():
    # 左から右へ消える影
    w, h = 256, 8
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for x in range(w):
        t = x / (w - 1)
        s = 1.0 - (t * t * (3.0 - 2.0 * t))
        a = int(255 * 0.40 * s)
        for y in range(h):
            px[x, y] = (6, 14, 34, a)
    img.save(os.path.join(OUT, "T_UI_ScrimLeft.png"))

    # ボタンの落ち影 (9 スライス。余白 0.375)
    s = 128
    a = Image.new("L", (s, s), 0)
    ImageDraw.Draw(a).rounded_rectangle([30, 30, s - 30, s - 30], radius=12, fill=150)
    a = a.filter(ImageFilter.GaussianBlur(11))
    shadow = Image.new("RGBA", (s, s), (4, 10, 26, 0))
    shadow.putalpha(a)
    shadow.save(os.path.join(OUT, "T_UI_Shadow.png"))

    # ロゴのぼかした影
    logo = Image.open(LOGO).convert("RGBA")
    lh = round(logo.height * LOGO_SHADOW_W / logo.width)
    alpha = logo.resize((LOGO_SHADOW_W, lh), Image.LANCZOS).getchannel("A")
    canvas = Image.new("L", (LOGO_SHADOW_W + LOGO_SHADOW_PAD * 2, lh + LOGO_SHADOW_PAD * 2), 0)
    canvas.paste(alpha, (LOGO_SHADOW_PAD, LOGO_SHADOW_PAD))
    canvas = canvas.filter(ImageFilter.GaussianBlur(13)).point(lambda v: int(v * 0.62))
    out = Image.new("RGBA", canvas.size, (4, 12, 34, 0))
    out.putalpha(canvas)
    out.save(os.path.join(OUT, "T_TestopiaLogoShadow.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    old = os.path.join(OUT, "T_MenuSaw.png")
    if os.path.exists(old):
        os.remove(old)
    for i, (q, left, right) in enumerate(WALLS):
        make_wall(i, q, left, right)
    make_belt()
    make_ui()
    print("wrote", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()

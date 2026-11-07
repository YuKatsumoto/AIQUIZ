"""TESTOPIA のアプリアイコン「問題壁」を作る：何もない黒い地に、正面から見た 2D の 2 択の壁（灰色の枠に青と赤の扉）。

形は 1024 x 1024 の座標で 1 回だけ決め、SVG（元データ）と PNG / ICO（ゲームと書き出しが使う）の両方に出す。
色はゲームの壁（scripts/world/quiz_wall.gd の DOOR_COLORS_2・WALL_COLOR）をトゥーンで描いた画面の色に合わせる。
扉は壁の下の端まで抜けている（ゲームの壁と同じく、枠は上と左右だけ）。

    python tools/logo_editor/build_wall_icon.py

出力（見比べ用。採用したアイコンは D案で、tools/logo_editor/export_app_icon.py が出す）：
  assets/branding/icon_concepts/wall_icon.svg / .png / wall_icon_android_fg.svg / wall_icon_android_fg.png
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CONCEPT_DIR = os.path.join(ROOT, "assets/branding/icon_concepts")

SS = 4  # PNG はこの倍で描いてから縮める（縁を滑らかに）
CORNER = 200  # デスクトップ用アイコンの角丸（1024 の座標）

BACKGROUND = "#000000"
FRAME = "#a4a8ae"
RECESS = "#8c9097"
BLUE, BLUE_TOP = "#199af3", "#4ab0f6"
RED, RED_TOP = "#e52619", "#ec5a4e"

# 壁（正面）。横長はゲームの 2 択の壁の見え方（およそ 1.55 : 1）に合わせる
WALL_W, WALL_H = 780.0, 500.0
MARGIN, TOP_MARGIN, GAP, RECESS_W, BAND = 50.0, 56.0, 40.0, 11.0, 34.0


def wall_shapes(scale=1.0):
    """壁の四角形（x0, y0, x1, y1, 色）。中心は (512, 512)。scale は Android の前景用。"""
    def r(ax, ay, bx, by, color):
        return (512 + ax * scale, 512 + ay * scale, 512 + bx * scale, 512 + by * scale, color)

    hw, hh = WALL_W / 2, WALL_H / 2
    shapes = [r(-hw, -hh, hw, hh, FRAME)]
    door_w = (WALL_W - 2 * MARGIN - GAP) / 2
    for i, (color, top) in enumerate([(BLUE, BLUE_TOP), (RED, RED_TOP)]):
        x0 = -hw + MARGIN + i * (door_w + GAP)
        x1 = x0 + door_w
        y0 = -hh + TOP_MARGIN
        shapes.append(r(x0 - RECESS_W, y0 - RECESS_W, x1 + RECESS_W, hh, RECESS))
        shapes.append(r(x0, y0, x1, hh, color))
        shapes.append(r(x0, y0, x1, y0 + BAND, top))
    return shapes


def to_svg(shapes, background, rounded):
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">']
    if background:
        rx = f' rx="{CORNER}" ry="{CORNER}"' if rounded else ""
        out.append(f'<rect width="1024" height="1024"{rx} fill="{background}"/>')
    for x0, y0, x1, y1, color in shapes:
        out.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{x1 - x0:.1f}" height="{y1 - y0:.1f}" fill="{color}"/>')
    out.append("</svg>")
    return "".join(out)


def _rgb(hex_color):
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def to_png(shapes, background, rounded, size):
    big = 1024 * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    if background:
        if rounded:
            draw.rounded_rectangle([0, 0, big - 1, big - 1], radius=CORNER * SS, fill=_rgb(background) + (255,))
        else:
            draw.rectangle([0, 0, big - 1, big - 1], fill=_rgb(background) + (255,))
    for x0, y0, x1, y1, color in shapes:
        draw.rectangle([x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1], fill=_rgb(color) + (255,))
    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(CONCEPT_DIR, exist_ok=True)
    full = wall_shapes()
    open(os.path.join(CONCEPT_DIR, "wall_icon.svg"), "w", encoding="utf-8").write(to_svg(full, BACKGROUND, True))
    to_png(full, BACKGROUND, True, 1024).save(os.path.join(CONCEPT_DIR, "wall_icon.png"))
    fg = wall_shapes(0.64)
    open(os.path.join(CONCEPT_DIR, "wall_icon_android_fg.svg"), "w", encoding="utf-8").write(to_svg(fg, None, False))
    to_png(fg, None, False, 432).save(os.path.join(CONCEPT_DIR, "wall_icon_android_fg.png"))
    print("ok")


if __name__ == "__main__":
    main()

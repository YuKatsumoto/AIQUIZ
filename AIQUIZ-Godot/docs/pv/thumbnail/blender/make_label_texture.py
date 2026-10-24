"""扉の答え「56」の画像（縁取りつき、透過 PNG）を作る。t2_thumbnail.blend の板 LBL_56 に貼る。

Blender の文字（Text オブジェクト）の太らせ（offset）は角がとがるので、縁取りはここで丸い角のまま描く
（ゲームの Label3D の縁取りも角が丸い）。書体・大きさ・縁の太さはゲームの絵に合わせた値:
  書体     resources/fonts/NotoSansJP-Regular.otf（ゲームと同じ）
  字の高さ  0.7887 m（"56" の描かれている高さ。ゲームの絵で 136 px、扉の位置で 172 px/m）
  縁の太さ  片側 0.0959 m（ゲームの絵で 16.5 px）、色 (0.1, 0.1, 0.1)、中は白
出力: tex/label_56.png と tex/label_56.json（画像の px と板の m の対応）。

  python docs/pv/thumbnail/blender/make_label_texture.py
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONT = HERE.parents[3] / "resources/fonts/NotoSansJP-Regular.otf"
TEXT = "56"
EM_PX = 1600
INK_HEIGHT_M = 0.7887
OUTLINE_M = 0.0959
FILL = (255, 255, 255, 255)
OUTLINE = (26, 26, 26, 255)          # sRGB 0.1
MARGIN = 24


def ink_bbox(alpha: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.nonzero(alpha > 127)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def main() -> None:
    font = ImageFont.truetype(str(FONT), EM_PX)
    probe = Image.new("L", (EM_PX * 3, EM_PX * 2), 0)
    ImageDraw.Draw(probe).text((EM_PX // 2, EM_PX // 4), TEXT, font=font, fill=255)
    x0, y0, x1, y1 = ink_bbox(np.asarray(probe))
    m_per_px = INK_HEIGHT_M / (y1 - y0)
    stroke = int(round(OUTLINE_M / m_per_px))
    # 文字の描かれている範囲 + 縁 + 余白 の大きさの画像に描き直す
    w = (x1 - x0) + 2 * (stroke + MARGIN)
    h = (y1 - y0) + 2 * (stroke + MARGIN)
    ox = EM_PX // 2 - x0 + stroke + MARGIN
    oy = EM_PX // 4 - y0 + stroke + MARGIN
    img = Image.new("RGBA", (w, h), (OUTLINE[0], OUTLINE[1], OUTLINE[2], 0))
    ImageDraw.Draw(img).text((ox, oy), TEXT, font=font, fill=FILL,
                             stroke_width=stroke, stroke_fill=OUTLINE)
    # 中の文字だけの範囲（板の位置合わせに使う）
    fill_only = Image.new("L", (w, h), 0)
    ImageDraw.Draw(fill_only).text((ox, oy), TEXT, font=font, fill=255)
    fx0, fy0, fx1, fy1 = ink_bbox(np.asarray(fill_only))
    out = HERE / "tex"
    out.mkdir(exist_ok=True)
    img.save(out / "label_56.png")
    info = {"size_px": [w, h], "m_per_px": m_per_px, "stroke_px": stroke,
            "fill_ink_px": [fx0, fy0, fx1, fy1], "ink_width_m": (fx1 - fx0) * m_per_px, "ink_height_m": (fy1 - fy0) * m_per_px}
    (out / "label_56.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    print(json.dumps(info))


if __name__ == "__main__":
    main()

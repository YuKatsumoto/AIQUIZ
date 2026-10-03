"""参照画像の一覧シート（contact sheet）を作る。

    python make_sheet.py <出力名> <列数> <ID/name>=<ラベル> ...
出力は artifacts/aiquiz_stadium/reference_r1/<出力名>.jpg（git 管理外）。
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
OUT_DIR = HERE.parents[3] / "artifacts" / "aiquiz_stadium" / "reference_r1"


def main(argv):
    name, cols = argv[0], int(argv[1])
    items = [a.split("=", 1) for a in argv[2:]]
    tw, th, lh, gap, pad = 900, 506, 70, 14, 20
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (pad * 2 + cols * tw + (cols - 1) * gap, pad * 2 + rows * (th + lh) + (rows - 1) * gap), (18, 20, 26))
    d = ImageDraw.Draw(sheet)
    fb = ImageFont.truetype("C:/Windows/Fonts/meiryob.ttc", 30)
    ft = ImageFont.truetype("C:/Windows/Fonts/meiryob.ttc", 26)
    for i, (path, label) in enumerate(items):
        x = pad + (i % cols) * (tw + gap)
        y = pad + (i // cols) * (th + lh + gap)
        img = Image.open(HERE / f"{path}.jpg").convert("RGB")
        img.thumbnail((tw, th))
        sheet.paste(img, (x + (tw - img.width) // 2, y + (th - img.height) // 2))
        d.rectangle([x, y + th, x + tw - 1, y + th + lh - 1], fill=(30, 33, 42))
        tag = path.split("/")[0]
        d.rounded_rectangle([x + 12, y + th + 12, x + 92, y + th + 58], radius=8, fill=(40, 200, 230))
        d.text((x + 52, y + th + 35), tag, font=fb, fill=(15, 20, 30), anchor="mm")
        d.text((x + 108, y + th + 18), label, font=ft, fill=(240, 242, 248))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{name}.jpg"
    sheet.save(out, quality=88)
    print(out)


if __name__ == "__main__":
    main(sys.argv[1:])

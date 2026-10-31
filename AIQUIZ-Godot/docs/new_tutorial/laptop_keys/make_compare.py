"""3-1 ノートPC版：大きさの 2 案（panels/panel_A.png・panel_B.png。Codex CLI の画像生成）を横に並べた比べの絵。
  python docs/new_tutorial/laptop_keys/make_compare.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
OUT = HERE / "compare_size.jpg"
W = 960
FONT = "C:/Windows/Fonts/BIZ-UDGothicB.ttc"
PANELS = [
    ("panel_A.png", "案A 巨大（おすすめ）", "画面は看板の壁くらい。本番の2人のカメラのまま読める"),
    ("panel_B.png", "案B 机サイズ", "肩越しに寄る。動く練習のときはカメラを引いて机から離れる"),
]


def main():
    title = ImageFont.truetype(FONT, 34)
    note = ImageFont.truetype(FONT, 22)
    images = []
    for name, _, _ in PANELS:
        im = Image.open(HERE / "panels" / name).convert("RGB")
        images.append(im.resize((W, round(im.height * W / im.width))))
    h = max(im.height for im in images)
    sheet = Image.new("RGB", (W * 2 + 60, h + 130), (24, 28, 36))
    draw = ImageDraw.Draw(sheet)
    for i, (im, (_, head, sub)) in enumerate(zip(images, PANELS)):
        x = 20 + i * (W + 20)
        draw.text((x, 18), head, font=title, fill=(255, 210, 120) if i == 0 else (170, 210, 255))
        draw.text((x, 62), sub, font=note, fill=(220, 224, 230))
        sheet.paste(im, (x, 110))
    sheet.save(OUT, quality=90)
    print(OUT)


if __name__ == "__main__":
    main()

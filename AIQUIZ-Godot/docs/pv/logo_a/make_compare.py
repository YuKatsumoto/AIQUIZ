"""ロゴ案 A の A2 テスト：AE の書き出し（TIFF）を PNG にして、絵コンテの A2 と上下に並べる。
  python docs/pv/logo_a/make_compare.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TIF = HERE / "render" / "a2_composite_0.tif"
PNG = HERE / "render" / "a2_composite.png"
CONCEPT = ROOT / "docs" / "pv" / "storyboard_s01_s03_v2" / "panels" / "panel_a2.png"
OUT = HERE / "render" / "a2_compare.png"
FONT = str(ROOT / "resources" / "fonts" / "NotoSansJP-Bold.otf")


def main():
    shot = Image.open(TIF).convert("RGB")
    shot.save(PNG)
    concept = Image.open(CONCEPT).convert("RGB").resize(shot.size, Image.LANCZOS)
    w, h = shot.size
    label_h = 64
    sheet = Image.new("RGB", (w, (h + label_h) * 2), (24, 30, 42))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT, 34)
    for i, (img, label) in enumerate(((concept, "絵コンテ A2（Codex の画像生成のイメージ）"),
                                      (shot, "テスト：Godot の実機（ロゴ用の低いカメラ・PV フレーム 430）＋ Blender のロゴと床の破片 ＋ AE の光"))):
        y = i * (h + label_h)
        draw.text((24, y + label_h / 2), label, font=font, fill=(255, 255, 255), anchor="lm")
        sheet.paste(img, (0, y + label_h))
    sheet.save(OUT)
    print(PNG, OUT, sheet.size)


if __name__ == "__main__":
    main()

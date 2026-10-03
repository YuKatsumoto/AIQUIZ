"""寸法の注記を参照画像に重ねたシートを作る（寸法の文字は生成モデルに描かせず、ここで描く）。

    python make_overlays.py
出力: artifacts/aiquiz_stadium/reference_r1/measure/overlay_*.png
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
RAW = HERE.parents[3] / "artifacts" / "aiquiz_stadium" / "reference_r1"
OUT = RAW / "measure"
LM = json.loads((HERE / "landmarks.json").read_text(encoding="utf-8"))
REP = json.loads((HERE / "measure_report.json").read_text(encoding="utf-8"))
DIM = json.loads((HERE.parent / "dimensions.json").read_text(encoding="utf-8"))
F = ImageFont.truetype("C:/Windows/Fonts/meiryob.ttc", 30)
C = (220, 0, 120)


def hline(d, y, x0, x1, text):
    d.line([(x0, y), (x1, y)], fill=C, width=4)
    d.text((x1 + 10, y - 18), text, fill=C, font=F, stroke_width=3, stroke_fill=(255, 255, 255))


def span(d, x0, x1, y, text):
    d.line([(x0, y), (x1, y)], fill=C, width=4)
    for x in (x0, x1):
        d.line([(x, y - 14), (x, y + 14)], fill=C, width=4)
    d.text(((x0 + x1) / 2, y - 44), text, fill=C, font=F, anchor="mm", stroke_width=3, stroke_fill=(255, 255, 255))


def p01():
    lm = LM["P01_runway_side_elev"]
    m = REP["P01_runway_side_elev"]
    im = Image.open(RAW / lm["image"]).convert("RGB")
    d = ImageDraw.Draw(im)
    hline(d, lm["mast_top_y"], lm["mast_x"][0] - 60, lm["mast_x"][0] + 60, f"マスト頂部 Y {m['mast_top_Y']:.2f}m（設計 12.0）")
    hline(d, lm["upper_yard_y"], lm["upper_yard_x"][1], lm["upper_yard_x"][1] + 40, f"上のヤード Y {m['upper_yard_Y']:.2f}m")
    hline(d, lm["sail_foot_y"], lm["sail_foot_x"][1], lm["sail_foot_x"][1] + 40, f"帆の足 Y {m['sail_foot_Y']:.2f}m")
    span(d, lm["sail_foot_x"][0], lm["sail_foot_x"][1], lm["sail_foot_y"] + 70, f"帆の足の長さ {m['sail_foot_len']:.2f}m（設計 14.0）")
    span(d, lm["mast_x"][0], lm["mast_x"][1], 120, f"マスト間隔 {m['mast_spacing']:.2f}m ＝ ブロック長 20m")
    span(d, lm["booth_x"][0], lm["booth_x"][1], lm["booth_y"][1] + 60, f"ブース {m['booth_len_along_course']:.2f}m")
    hline(d, lm["water_row"], 40, 400, f"水面 Y {m['water_Y']:.2f}m（定数 -9.2）")
    im.save(OUT / "overlay_P01_runway_side_elev.png")


def p05():
    lm = LM["P05_front_elev"]
    res = DIM["modules"]["lighthouse"]["data"]["resolved"]
    W = DIM["modules"]["lighthouse"]["data"]["sign_inner_width_W"]
    im = Image.open(RAW / lm["image"]).convert("RGB")
    d = ImageDraw.Draw(im)
    span(d, lm["sign_inner_x"][0], lm["sign_inner_x"][1], lm["sign_inner_y"][0] - 60, f"看板の面 W = {W:.0f}m（2.5:1）")
    hline(d, lm["dome_top_y"], 950, 1000, f"頂部 {res['dome_top_above_water']:.1f}m")
    hline(d, lm["gallery_floor_y"], 950, 1000, f"回廊 {res['gallery_floor_above_water']:.1f}m")
    hline(d, lm["sign_outer_y"][1], 1330, 1350, f"看板の下端 {res['sign_bottom_above_water']:.1f}m")
    span(d, lm["islet_x"][0], lm["islet_x"][1], lm["water_row"] + 80, f"小島 {res['islet_width']:.0f}m")
    hline(d, lm["water_row"], 1480, 1500, "海面 0")
    im.save(OUT / "overlay_P05_front_elev.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    p01()
    p05()
    print("overlays written to", OUT)


if __name__ == "__main__":
    main()

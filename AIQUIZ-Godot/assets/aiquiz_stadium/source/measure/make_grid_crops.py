"""正投影の参照画像に、メートル目盛りの方眼を重ねた確認用の切り抜きを作る。

較正は各画像の下敷き（guides/make_underlays.py）の既知の縮尺から求める。下敷きは W×H 画素で
中心 (cx, cy) を画像中心に置き、s px/m で描いてある。生成画像は同じ比率で拡大されているので、
縮尺 = s × (生成画像の幅 / 下敷きの幅)。水線の位置で縦方向を検算する（calibration.json）。

    python make_grid_crops.py
出力: artifacts/aiquiz_stadium/reference_r1/measure/<名前>_grid.png（git 管理外）
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RAW = ROOT / "artifacts" / "aiquiz_stadium" / "reference_r1"
OUT = RAW / "measure"
SEA_Y = -9.2

# 名前: (画像, 下敷きの幅・高さ, 下敷きの中心の「横座標の意味」, 中心の高さ Y, s px/m, 横軸の説明)
VIEWS = {
    "P01_runway_side_elev": ("P01/P01_runway_side_elev.png", (1920, 1080), 2.0, 41.739, "course z (m, block joint = 20)"),
    "P01_end_elev": ("P01/P01_end_elev.png", (1440, 1080), 1.5, 55.385, "world x (m, runway at right)"),
    "P04_section": ("P04/P04_section.png", (1920, 1080), -4.5, 60.0, "world x (m)"),
    "P05_front_elev": ("P05/P05_front_elev.png", (1080, 1620), None, 13.5, "x (m) from tower axis"),
    "P07_goal_stand_B_front_elev": ("P07/P07_goal_stand_B_front_elev.png", (1920, 1080), 4.0, 60.0, "x (m) from stand axis"),
}


def water_row(img: np.ndarray) -> int | None:
    lum = img.mean(axis=2)
    frac = (lum < 110).mean(axis=1)
    rows = np.where(frac > 0.9)[0]
    return int(rows.mean()) if len(rows) else None


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype("C:/Windows/Fonts/meiryo.ttc", 20)
    calib = {}
    for name, (path, (uw, uh), cy_world, s_under, xlabel) in VIEWS.items():
        im = Image.open(RAW / path).convert("RGB")
        W, H = im.size
        kx, ky = W / uw, H / uh
        s = s_under * kx
        arr = np.asarray(im).astype(int)
        wr = water_row(arr)
        entry = {"image": path, "pixels": [W, H], "px_per_m": round(s, 3), "aspect_scale_x": round(kx, 4),
                 "aspect_scale_y": round(ky, 4), "measured_water_row": wr}
        if cy_world is not None:
            predicted = H / 2 - (SEA_Y - cy_world) * s_under * ky
            entry["predicted_water_row"] = round(predicted, 1)
            if wr is not None:
                entry["water_row_error_m"] = round((wr - predicted) / (s_under * ky), 3)
            y_of = lambda yw: H / 2 - (yw - cy_world) * s_under * ky
        else:
            y_of = (lambda yw, wr=wr: wr - (yw - SEA_Y) * s_under * ky) if wr else None
        calib[name] = entry
        d = ImageDraw.Draw(im)
        if y_of:
            for yw in range(-10, 90, 1):
                y = y_of(yw)
                if 0 <= y < H:
                    major = yw % 5 == 0
                    d.line([(0, y), (W, y)], fill=(255, 0, 180) if major else (255, 150, 220), width=2 if major else 1)
                    if major:
                        d.text((4, y - 22), f"Y {yw}", fill=(200, 0, 140), font=font)
        for xm in range(-60, 61):
            x = W / 2 + xm * s
            if 0 <= x < W:
                major = xm % 5 == 0
                d.line([(x, 0), (x, H)], fill=(0, 150, 255) if major else (150, 200, 255), width=2 if major else 1)
                if major:
                    d.text((x + 3, 4), f"{xm:+d}", fill=(0, 90, 200), font=font)
        d.text((10, H - 30), f"{name}: {xlabel}; s={s:.2f}px/m; water row {wr}", fill=(0, 0, 0), font=font)
        im.save(OUT / f"{name}_grid.png")
        print(name, entry)
    (HERE / "calibration.json").write_text(json.dumps(calib, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

"""AE の TitleLogo_Intro の指定の秒を PNG に書き出し、コンタクトシートにする。

    python tools/title_logo_ae/render_review.py artifacts/title_logo_ae/sheet.jpg 0.5,1.0,2.0 [cols]
"""
import json
import os
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = os.path.join(HERE, "..", "..", "artifacts", "title_logo_ae", "frames")


def main() -> None:
    out, times = sys.argv[1], [float(t) for t in sys.argv[2].split(",")]
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    src = open(os.path.join(HERE, "render_review.jsx"), encoding="utf-8").read().replace("$TIMES$", json.dumps(times))
    with tempfile.NamedTemporaryFile("w", suffix=".jsx", delete=False, encoding="utf-8") as tmp:
        tmp.write(src)
    subprocess.run(["node", os.path.join(HERE, "ae_run.mjs"), tmp.name], check=True, stdout=subprocess.DEVNULL)
    os.unlink(tmp.name)
    names = ["t%05d.png" % round(t * 1000) for t in times]
    for _ in range(100):  # saveFrameToPng finishes asynchronously
        if all(os.path.exists(os.path.join(FRAMES, n)) for n in names):
            break
        time.sleep(0.2)
    time.sleep(0.5)
    shots = [Image.open(os.path.join(FRAMES, n)).convert("RGB") for n in names]
    w, h = shots[0].size
    scale = 480 / w
    tw, th = int(w * scale), int(h * scale)
    rows = (len(shots) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + 22)), (20, 20, 24))
    draw = ImageDraw.Draw(sheet)
    for i, (shot, t) in enumerate(zip(shots, times)):
        x, y = (i % cols) * tw, (i // cols) * (th + 22)
        sheet.paste(shot.resize((tw, th), Image.LANCZOS), (x, y + 22))
        draw.text((x + 6, y + 4), "%.2f s" % t, fill=(255, 220, 90))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    sheet.save(out, quality=90)
    print(out, sheet.size)


if __name__ == "__main__":
    main()

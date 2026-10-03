"""previews/frames の PNG を 1 枚のコンタクトシートにまとめる（列数は引数、既定 3）。"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
frames = sorted((HERE / "previews" / "frames").glob("*.png"), key=lambda p: p.stat().st_mtime)
cols = int(sys.argv[1]) if len(sys.argv) > 1 else 3
out = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "previews" / "contact_sheet.jpg"
tw, th = 648, 294
rows = (len(frames) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + 24)), (20, 20, 24))
d = ImageDraw.Draw(sheet)
for i, p in enumerate(frames):
    im = Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS)
    x, y = (i % cols) * tw, (i // cols) * (th + 24)
    sheet.paste(im, (x, y + 24))
    d.text((x + 6, y + 5), p.stem, fill=(230, 230, 230))
sheet.save(out, quality=88)
print(out, len(frames))

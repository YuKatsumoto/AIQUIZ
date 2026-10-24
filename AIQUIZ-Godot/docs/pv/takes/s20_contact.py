import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
# usage: contact.py out.jpg cols tile_w  label:dir:f1,f2,... [label:dir:f1,...]
out, cols, tw = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
groups = []
for g in sys.argv[4:]:
    label, d, fr = g.split("|")
    groups.append((label, Path(d), [int(x) for x in fr.split(",")]))
th = tw * 9 // 16
head = 26
try:
    font = ImageFont.truetype("C:/Windows/Fonts/meiryo.ttc", 16)
except Exception:
    font = None
rows_total = sum((len(f) + cols - 1) // cols for _, _, f in groups)
sheet = Image.new("RGB", (cols * tw, rows_total * th + head * len(groups)), (16, 16, 16))
dr = ImageDraw.Draw(sheet)
y = 0
for label, d, frames in groups:
    dr.rectangle([0, y, sheet.width, y + head], fill=(40, 40, 60))
    dr.text((8, y + 4), label, fill=(255, 255, 255), font=font)
    y += head
    for i, f in enumerate(frames):
        p = d / f"pv_{f:04d}.jpg"
        if not p.exists():
            continue
        im = Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS)
        x, yy = (i % cols) * tw, y + (i // cols) * th
        sheet.paste(im, (x, yy))
        dr.rectangle([x, yy, x + 118, yy + 20], fill=(0, 0, 0))
        dr.text((x + 5, yy + 2), f"f{f}  {(f - 1) / 28.125:.2f}拍", fill=(255, 230, 0), font=font)
    y += ((len(frames) + cols - 1) // cols) * th
sheet.save(out, quality=88)
print(out, sheet.size)

"""Host-side helper: montage a folder of PNGs into a labelled contact sheet."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw


def sheet(folder, out, cols=5, width=384):
    files = sorted(Path(folder).glob("*.png"))
    if not files:
        raise SystemExit("no frames in " + folder)
    first = Image.open(files[0])
    height = int(first.height * width / first.width)
    rows = (len(files) + cols - 1) // cols
    canvas = Image.new("RGB", (cols * width, rows * height), (24, 24, 28))
    draw = ImageDraw.Draw(canvas)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB").resize((width, height))
        x, y = (i % cols) * width, (i // cols) * height
        canvas.paste(im, (x, y))
        draw.rectangle([x, y, x + 64, y + 16], fill=(0, 0, 0))
        draw.text((x + 4, y + 2), f.stem, fill=(255, 230, 0))
    canvas.save(out)
    return out


if __name__ == "__main__":
    print(sheet(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 5))

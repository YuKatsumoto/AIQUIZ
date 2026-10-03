"""Prepare the scoreboard textures for build_scoreboard.py (source/textures/sb_*.png):
crop the Higgsfield header sign, make the Higgsfield steel tileable, and draw the
procedural bulb-bank panel.

    python assets/goal_stand/source/prep_scoreboard_textures.py
"""
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
RAW = HERE / "generated"
OUT = HERE / "textures"
# Face aspect ratios from build_scoreboard.py (width / height).
# The header generation already frames the whole sign: keep that frame (x 0.5-99.5 %,
# y 5.5-98.5 %) instead of cropping to an aspect ratio.
SIGN_BOX = (0.005, 0.055, 0.995, 0.985)
# Bulb bank panel (build_scoreboard.py): 2.95 x 1.72 m, 7 x 3 lamps.
BULB_PANEL = (2.95, 1.72)
BULB_GRID = (7, 3)


def tileable(image, size, band=0.18):
    """Trim the generation's border, then wrap: each edge band fades into the
    content just past the opposite edge, so the tile repeats without a seam."""
    import numpy as np
    w, h = image.size
    inset = int(min(w, h) * 0.04)
    trimmed = image.convert("RGB").crop((inset, inset, w - inset, h - inset))
    # Flatten the photo's lighting falloff so the repeat has no bright hotspot.
    from PIL import ImageFilter
    a = np.asarray(trimmed, dtype=np.float32)
    low = np.asarray(trimmed.filter(ImageFilter.GaussianBlur(radius=trimmed.size[0] * 0.08)), dtype=np.float32)
    a = a / np.maximum(low, 1.0) * low.reshape(-1, 3).mean(axis=0)
    for axis in (1, 0):
        n = a.shape[axis]
        b = int(n * band)
        t = np.linspace(0.0, 1.0, b, dtype=np.float32)
        shape = [1, 1, 1]
        shape[axis] = b
        t = t.reshape(shape)
        head = np.take(a, range(0, b), axis=axis)
        tail = np.take(a, range(n - b, n), axis=axis)
        body = np.take(a, range(0, n - b), axis=axis).copy()
        blended = tail * (1.0 - t) + head * t
        if axis == 1:
            body[:, :b] = blended
        else:
            body[:b] = blended
        a = body
    out = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    return out.resize((size, size), Image.LANCZOS)


def bulb_panel(width=1024):
    """Procedural lamp board: warm bulbs with a hot core and soft halo in black
    sockets. Drawn at 4x and downsampled so every mip level is clean."""
    import numpy as np
    height = int(round(width * BULB_PANEL[1] / BULB_PANEL[0]))
    ss = 4
    w, h = width * ss, height * ss
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    cols, rows = BULB_GRID
    cw, ch = w / cols, h / rows
    lx = (xs % cw) / cw - 0.5
    ly = (ys % ch) / ch - 0.5
    d = np.sqrt((lx * cw) ** 2 + (ly * ch) ** 2) / min(cw, ch)   # round, sized by the short side
    socket = np.clip((0.36 - d) / 0.02, 0.0, 1.0)
    glass = np.clip((0.27 - d) / 0.02, 0.0, 1.0)
    core = np.exp(-(d / 0.11) ** 2)
    warm = np.array([1.0, 0.78, 0.42], dtype=np.float32)
    rgb = (0.02 + 0.05 * socket)[..., None] * np.ones(3, dtype=np.float32)
    rgb = rgb * (1.0 - glass[..., None]) + glass[..., None] * (warm * (0.55 + 0.45 * core[..., None]))
    rgb = np.clip(rgb + (core * 0.35)[..., None], 0.0, 1.0)
    image = Image.fromarray((rgb * 255.0).astype(np.uint8))
    return image.resize((width, height), Image.LANCZOS)


def main():
    OUT.mkdir(exist_ok=True)
    raw = RAW / "sb_header_raw.png"
    if raw.exists():
        image = Image.open(raw).convert("RGB")
        w, h = image.size
        box = (int(SIGN_BOX[0] * w), int(SIGN_BOX[1] * h), int(SIGN_BOX[2] * w), int(SIGN_BOX[3] * h))
        image.crop(box).resize((1500, 600), Image.LANCZOS).save(OUT / "sb_header.png")
        print("wrote sb_header")
    bulb_panel().save(OUT / "sb_bulbs.png")
    print("wrote sb_bulbs")
    steel = RAW / "sb_steel_raw.png"
    if steel.exists():
        tileable(Image.open(steel), 1024).save(OUT / "sb_steel.png")
        print("wrote sb_steel")


if __name__ == "__main__":
    main()

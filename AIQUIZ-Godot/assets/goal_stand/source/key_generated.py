"""Key the Higgsfield-generated sprites (flat magenta/green backgrounds) to alpha.

Input:  source/generated/*_raw.png  (Higgsfield z_image / seedream_5_0_flash)
Output: ../textures/egg_splat.png   (runtime sprite, RGBA)
        textures/sign_*.png            (opaque boards, embedded by Blender into the GLB)
Run from the project root:  python assets/goal_stand/source/key_generated.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
RAW = HERE / "generated"
OUT = HERE.parent / "textures"
BLENDER_TEXTURES = HERE / "textures"


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def key(name, out_name, screen="magenta", size=512, pad=0.04):
    im = np.asarray(Image.open(RAW / name).convert("RGB")).astype(np.float32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    if screen == "magenta":
        spill = np.minimum(r, b) - g           # background and its drop shadow
    else:
        spill = g - np.maximum(r, b)
    alpha = 1.0 - smoothstep(18.0, 46.0, spill)
    # Remove the screen tint that survives on anti-aliased edges.
    if screen == "magenta":
        cap = g + np.maximum(0.0, spill) * (1.0 - alpha)
        r = np.minimum(r, np.maximum(cap, r * alpha))
        b = np.minimum(b, np.maximum(cap, b * alpha))
    else:
        g = np.minimum(g, np.maximum(r, b) + (g - np.maximum(r, b)) * alpha)
    rgba = np.dstack([r, g, b, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    ys, xs = np.nonzero(alpha > 0.5)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    side = max(y1 - y0, x1 - x0) * (1.0 + pad * 2.0)
    cy, cx = (y0 + y1) * 0.5, (x0 + x1) * 0.5
    box = [int(cx - side / 2), int(cy - side / 2), int(cx + side / 2), int(cy + side / 2)]
    img = Image.fromarray(rgba, "RGBA").crop(box)
    img = img.resize((size, size), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / out_name)
    return OUT / out_name, img.size


def key_board(name, out_name, screen="magenta", width=512):
    im = np.asarray(Image.open(RAW / name).convert("RGB")).astype(np.float32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    spill = (np.minimum(r, b) - g) if screen == "magenta" else (g - np.maximum(r, b))
    alpha = 1.0 - smoothstep(18.0, 46.0, spill)
    # Signs are opaque boards: fill the keyed-out corners with the board colour.
    solid = alpha > 0.5
    board = np.median(np.dstack([r, g, b])[solid], axis=0)
    rgb = np.dstack([r, g, b])
    rgb[~solid] = board
    ys, xs = np.nonzero(solid)
    img = Image.fromarray(rgb.clip(0, 255).astype(np.uint8), "RGB").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    img = img.resize((width, int(width * img.size[1] / img.size[0])), Image.LANCZOS)
    BLENDER_TEXTURES.mkdir(parents=True, exist_ok=True)
    img.save(BLENDER_TEXTURES / out_name)
    return BLENDER_TEXTURES / out_name, img.size


if __name__ == "__main__":
    print(key("egg_splat_raw.png", "egg_splat.png"))
    for raw, out, screen in [("sign_p1_raw.png", "sign_p1.png", "magenta"),
                             ("sign_p2_raw.png", "sign_p2.png", "magenta"),
                             ("sign_boo_raw.png", "sign_boo.png", "green")]:
        if (RAW / raw).exists():
            print(key_board(raw, out, screen))

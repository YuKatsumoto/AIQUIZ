"""Pack the After Effects flame loop into the runtime sprite sheet.

Input : artifacts/streak_flame/frames/flame_00.tif .. (Streak_Flame_Loop, 256 x 320, RGBA)
Output: assets/ui/streak_flame/flame_sheet.png  (6 x 5 cells of 128 x 160, straight alpha)
        artifacts/streak_flame/loop_contact.png  (frames over the duo card colour, for review)

Frames are downscaled in premultiplied space (no dark fringes), then stored with straight
alpha, which is what Godot's CanvasItem blending expects.
    python tools/streak_flame_ae/pack_streak_flame.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FRAMES = ROOT / "artifacts/streak_flame/frames"
SHEET = ROOT / "assets/ui/streak_flame/flame_sheet.png"
CONTACT = ROOT / "artifacts/streak_flame/loop_contact.png"
CELL = (128, 160)
COLUMNS = 6
INK = np.array([0.027, 0.047, 0.082])


def load(path: Path) -> np.ndarray:
    img = Image.open(path)
    tags = img.tag_v2
    bits = tags[258][0]
    if tags.get(277) == 4 and img.mode == "RGB":
        # AE marks the alpha as an unspecified extra sample, which Pillow drops; the
        # strips are uncompressed, so read the four interleaved channels directly.
        if tags.get(259) != 1:
            raise SystemExit(f"{path.name}: compressed 4-channel TIFF is not supported")
        raw = path.read_bytes()
        strips = b"".join(raw[o:o + n] for o, n in zip(tags[273], tags[279]))
        dtype = np.dtype(">u2" if raw[:2] == b"MM" else "<u2") if bits == 16 else np.uint8
        data = np.frombuffer(strips, dtype=dtype).reshape(img.size[1], img.size[0], 4).astype(np.float64)
    else:
        data = np.asarray(img).astype(np.float64)
        if data.shape[2] == 3:
            raise SystemExit(f"{path.name} has no alpha channel")
    return data / (65535.0 if bits == 16 else 255.0)


def main() -> None:
    paths = sorted(FRAMES.glob("flame_*.tif"))
    if not paths:
        raise SystemExit("no frames; run render_streak_flame.jsx first")
    frames = [load(p) for p in paths]
    # AE writes premultiplied alpha unless told otherwise: colour never exceeds alpha then.
    premultiplied = all((f[..., :3] <= f[..., 3:4] + 1.5 / 255.0).all() for f in frames)
    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    sheet = np.zeros((rows * CELL[1], COLUMNS * CELL[0], 4))
    contact = np.zeros((rows * CELL[1], COLUMNS * CELL[0], 3))
    for i, f in enumerate(frames):
        alpha = f[..., 3:4]
        pm = f[..., :3] if premultiplied else f[..., :3] * alpha
        rgba = np.concatenate([pm, alpha], axis=2)
        small = np.stack([
            np.asarray(Image.fromarray(rgba[..., c].astype(np.float32), mode="F").resize(CELL, Image.LANCZOS))
            for c in range(4)
        ], axis=2).clip(0.0, 1.0)
        a = small[..., 3:4]
        straight = np.where(a > 1e-4, small[..., :3] / np.maximum(a, 1e-4), 0.0).clip(0.0, 1.0)
        y, x = divmod(i, COLUMNS)
        cell = (slice(y * CELL[1], (y + 1) * CELL[1]), slice(x * CELL[0], (x + 1) * CELL[0]))
        sheet[cell] = np.concatenate([straight, a], axis=2)
        contact[cell] = small[..., :3] + INK * (1.0 - a)
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((sheet * 255.0 + 0.5).astype(np.uint8), "RGBA").save(SHEET, optimize=True)
    Image.fromarray((contact * 255.0 + 0.5).astype(np.uint8), "RGB").save(CONTACT)
    print(f"{len(frames)} frames, premultiplied={premultiplied}, sheet {sheet.shape[1]}x{sheet.shape[0]} -> {SHEET}")


if __name__ == "__main__":
    main()

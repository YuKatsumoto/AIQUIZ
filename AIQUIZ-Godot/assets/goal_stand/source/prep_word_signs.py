"""Hand-drawn "OH" / "MY" / "GOT" boards held side by side by the losing team's
sign holders (they flip to these at the verdict, read left to right on screen).

Input:  source/generated/sign_word_*_raw.png  (hand-drawn, black ink on white)
Output: goal_stand_spectator_sign_{oh,my,got}.png  (loaded by GoalStand at runtime
        onto the GSP_SignBoo board; same 0.62 x 0.46 m front face as the other signs)
Run from the project root:  python assets/goal_stand/source/prep_word_signs.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
RAW = HERE / "generated"
OUT = HERE.parent
BOARD_ASPECT = 0.62 / 0.46
WIDTH = 512
MARGIN = 0.12


def prep(word):
    im = Image.open(RAW / ("sign_word_%s_raw.png" % word)).convert("RGBA")
    flat = Image.new("RGBA", im.size, (255, 255, 255, 255))
    flat.alpha_composite(im)
    grey = np.asarray(flat.convert("L"))
    ys, xs = np.nonzero(grey < 128)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    w, h = (x1 - x0) * (1.0 + MARGIN * 2.0), (y1 - y0) * (1.0 + MARGIN * 2.0)
    if w / h < BOARD_ASPECT:
        w = h * BOARD_ASPECT
    else:
        h = w / BOARD_ASPECT
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    board = Image.new("RGB", (int(round(w)), int(round(h))), (255, 255, 255))
    board.paste(flat.convert("RGB"), (int(round(w * 0.5 - cx)), int(round(h * 0.5 - cy))))
    board = board.resize((WIDTH, int(round(WIDTH / BOARD_ASPECT))), Image.LANCZOS)
    path = OUT / ("goal_stand_spectator_sign_%s.png" % word)
    board.save(path)
    return path, board.size


if __name__ == "__main__":
    for word in ("oh", "my", "got"):
        print(prep(word))

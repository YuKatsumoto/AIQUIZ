"""Hand-drawn "P1"/"P2" "N" "I" "C" "E" boards held side by side by the winning team's
five sign holders (they flip to these at the verdict, read left to right on screen:
P1 NICE or P2 NICE).

Input:  source/generated/sign_nice_*_raw.png  (hand-drawn on white; P1 is orange, P2 blue,
        the letters black)
Output: goal_stand_spectator_sign_nice_{p1,p2,n,i,c,e}.png  (loaded by GoalStand at runtime
        onto the GSP_SignBoo board; same 0.62 x 0.46 m front face as the other signs)
Run from the project root:  python assets/goal_stand/source/prep_nice_signs.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

from prep_word_signs import BOARD_ASPECT, MARGIN, OUT, RAW, WIDTH

# Orange ink is lighter than the black letters, so the ink is "anything that is not
# close to white" rather than a grey threshold.
INK_BELOW = 200


def prep(name):
    im = Image.open(RAW / ("sign_nice_%s_raw.png" % name)).convert("RGBA")
    flat = Image.new("RGBA", im.size, (255, 255, 255, 255))
    flat.alpha_composite(im)
    ink = np.asarray(flat.convert("RGB")).min(axis=2) < INK_BELOW
    ys, xs = np.nonzero(ink)
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
    path = OUT / ("goal_stand_spectator_sign_nice_%s.png" % name)
    board.save(path)
    return path, board.size


if __name__ == "__main__":
    for name in ("p1", "p2", "n", "i", "c", "e"):
        print(prep(name))

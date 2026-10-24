"""ロゴの書体の字形を、直線だけの多角形にして JSON に書き出す（build_testopia_logo.mjs が読む）。

    python tools/logo_editor/extract_font_glyphs.py
    （fontTools が要る：python -m pip install fonttools）

曲線（TrueType の 2 次ベジェ）は、長さに合わせて細かい直線に分ける。座標はフォントの単位（y 上）。
"""
import json
import math
import os

from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "fonts", "Stereofunk.ttf")
OUT = os.path.join(HERE, "testopia_font_glyphs.json")
CHARS = "TESOPIA"
# 曲線を分ける細かさ（フォントの単位。1000 で 1 em。ロゴでは 1 単位がおよそ 0.19 px）
STEP = 6.0


class FlattenPen(BasePen):
    def __init__(self, glyph_set):
        super().__init__(glyph_set)
        self.contours = []
        self.cur = None

    def _moveTo(self, pt):
        self.cur = [list(pt)]

    def _lineTo(self, pt):
        self.cur.append(list(pt))

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        length = math.dist(p0, p1) + math.dist(p1, p2)
        n = max(2, math.ceil(length / STEP))
        for i in range(1, n + 1):
            t = i / n
            a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t * t
            self.cur.append([a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]])

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        length = math.dist(p0, p1) + math.dist(p1, p2) + math.dist(p2, p3)
        n = max(2, math.ceil(length / STEP))
        for i in range(1, n + 1):
            t = i / n
            a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
            self.cur.append([a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]])

    def _closePath(self):
        if self.cur and len(self.cur) > 1 and self.cur[0] == self.cur[-1]:
            self.cur.pop()
        if self.cur and len(self.cur) >= 3:
            self.contours.append([[round(x, 2), round(y, 2)] for x, y in self.cur])
        self.cur = None

    _endPath = _closePath


def main():
    font = TTFont(FONT)
    cmap = font.getBestCmap()
    glyph_set = font.getGlyphSet()
    hmtx = font["hmtx"]
    glyphs = {}
    for ch in CHARS:
        name = cmap[ord(ch)]
        pen = FlattenPen(glyph_set)
        glyph_set[name].draw(pen)
        glyphs[ch] = {"advance": hmtx[name][0], "contours": pen.contours}
    t_top = max(y for c in glyphs["T"]["contours"] for _, y in c)
    out = {
        "font": os.path.basename(FONT),
        "family": font["name"].getDebugName(1),
        "unitsPerEm": font["head"].unitsPerEm,
        "capHeight": t_top,
        "glyphs": glyphs,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent="\t")
        f.write("\n")
    print(f"wrote {os.path.relpath(OUT)}  capHeight={t_top}  " + ", ".join(f"{c}:{len(g['contours'])}" for c, g in glyphs.items()))


if __name__ == "__main__":
    main()

"""黒板に書く文字の「線」のデータを、手元のフォント（Noto Sans JP）の字形から作る（docs/lecture_hall_plan.md の 3a）。

字形を 160 px で描き、Zhang-Suen の細線化で中心線にし、端点と分かれ目でつないだ線に分け、
間引いて（Ramer-Douglas-Peucker）、書く順（上から下、左から右、横画を先に）に並べる。本物の書き順の
データ（KanjiVG など）ではないが、黒板の距離では「書いている」ように見える。外部のデータは使わない。

出力: assets/settings_hall/glyph_strokes.json
  {"size": 1.0, "glyphs": {"字": {"advance": 1.0, "strokes": [[[x, y], ...], ...]}, ...}}
  座標は字の枠（0..1、y は上向き）。advance は送り幅（全角 = 1.0）。
使い方: python tools/settings_hall/glyph_strokes.py [追加の文字列 ...]
（授業の台本 scripts/world/settings_hall/lessons/*.json に出てくる文字を全部拾う）
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "resources" / "fonts" / "NotoSansJP-Medium.otf"
OUT = ROOT / "assets" / "settings_hall" / "glyph_strokes.json"
LESSONS = ROOT / "scripts" / "world" / "settings_hall" / "lessons"
BANK = ROOT / "offline_bank.json"
PX = 160
BASE_TEXT = ("★≧()①②③④謹賀新年七夕 Happy Halloween Merry Christmas Valentine連結チップソー概論第講安全な観察距離と回転数刃の半径枚分間に転する跳ぶ高さ秒前問題正解答え"
             "日直月日（）火水木金土日〇×△？！。、・＝＋－→←↑↓★☆ 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
             "abcdefghijklmnopqrstuvwxyz.,:;!?()-+=/%m")


def _thin(img: np.ndarray) -> np.ndarray:
    """Zhang-Suen の細線化（1 = 字）。"""
    a = img.copy().astype(np.uint8)
    changed = True
    while changed:
        changed = False
        for step in (0, 1):
            p = np.pad(a, 1)
            P2, P3, P4 = p[:-2, 1:-1], p[:-2, 2:], p[1:-1, 2:]
            P5, P6, P7 = p[2:, 2:], p[2:, 1:-1], p[2:, :-2]
            P8, P9 = p[1:-1, :-2], p[:-2, :-2]
            nbrs = [P2, P3, P4, P5, P6, P7, P8, P9]
            B = sum(n.astype(np.int32) for n in nbrs)
            seq = nbrs + [P2]
            A = sum(((seq[i] == 0) & (seq[i + 1] == 1)).astype(np.int32) for i in range(8))
            if step == 0:
                c1 = (P2 * P4 * P6) == 0
                c2 = (P4 * P6 * P8) == 0
            else:
                c1 = (P2 * P4 * P8) == 0
                c2 = (P2 * P6 * P8) == 0
            m = (a == 1) & (B >= 2) & (B <= 6) & (A == 1) & c1 & c2
            if m.any():
                a[m] = 0
                changed = True
    return a


NB = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]


def _unstair(sk: np.ndarray) -> np.ndarray:
    """細線化の階段の角（取っても周りがつながったままの点）を取る。残すと曲線の途中が「分かれ目」に見えて、
    1 本の曲線が細切れになる。端点（隣が 1 つ）は取らない。"""
    a = sk.copy()
    h, w = a.shape
    for y, x in zip(*np.nonzero(sk)):
        nb = [(y + dy, x + dx) for dy, dx in NB
              if 0 <= y + dy < h and 0 <= x + dx < w and a[y + dy, x + dx]]
        if len(nb) < 2:
            continue
        seen = {nb[0]}
        todo = [nb[0]]
        while todo:
            c = todo.pop()
            for o in nb:
                if o not in seen and abs(o[0] - c[0]) <= 1 and abs(o[1] - c[1]) <= 1:
                    seen.add(o)
                    todo.append(o)
        if len(seen) == len(nb):
            a[y, x] = 0
    return a


def _trace(sk: np.ndarray):
    """細線を、端点・分かれ目（隣が 3 つ以上）の間の線に分ける。輪（端点のない線）も 1 本にする。"""
    ys, xs = np.nonzero(sk)
    pts = set(zip(ys.tolist(), xs.tolist()))

    def nbrs(p):
        return [(p[0] + dy, p[1] + dx) for dy, dx in NB if (p[0] + dy, p[1] + dx) in pts]

    nodes = {p for p in pts if len(nbrs(p)) != 2}
    used = set()
    lines = []
    for n in nodes:
        for q in nbrs(n):
            if (n, q) in used:
                continue
            path = [n, q]
            used.add((n, q))
            used.add((q, n))
            prev, cur = n, q
            while cur not in nodes:
                nxt = [r for r in nbrs(cur) if r != prev and (cur, r) not in used]
                if not nxt:
                    break
                r = nxt[0]
                used.add((cur, r))
                used.add((r, cur))
                path.append(r)
                prev, cur = cur, r
            lines.append(path)
    seen = {p for line in lines for p in line}
    rest = pts - seen
    while rest:
        start = next(iter(rest))
        path = [start]
        rest.discard(start)
        cur = start
        while True:
            nxt = [r for r in nbrs(cur) if r in rest]
            if not nxt:
                break
            cur = nxt[0]
            rest.discard(cur)
            path.append(cur)
        if len(path) > 3:
            path.append(path[0])
            lines.append(path)
    return lines


def _rdp(points, eps):
    if len(points) < 3:
        return points
    a = np.array(points[0], float)
    b = np.array(points[-1], float)
    ab = b - a
    n = np.linalg.norm(ab)
    best, idx = 0.0, 0
    for i in range(1, len(points) - 1):
        p = np.array(points[i], float)
        d = abs(ab[0] * (p - a)[1] - ab[1] * (p - a)[0]) / n if n > 1e-9 else np.linalg.norm(p - a)
        if d > best:
            best, idx = d, i
    if best > eps:
        return _rdp(points[:idx + 1], eps)[:-1] + _rdp(points[idx:], eps)
    return [points[0], points[-1]]


def _length(line):
    return float(sum(np.hypot(line[i + 1][0] - line[i][0], line[i + 1][1] - line[i][1]) for i in range(len(line) - 1)))


def _merge(lines, gap=2.5, min_len=7.0):
    """分かれ目で細切れになった画をつなぐ: 端どうしが近く、向きがまっすぐ続くもの（逆向きも試す）。
    短いひげ（細線化の残り、min_len px 未満で片側が浮いている）は捨てる。"""
    lines = [list(l) for l in lines]

    def direction(line, at_end):
        if at_end:
            return np.subtract(line[-1], line[max(0, len(line) - 5)])
        return np.subtract(line[0], line[min(len(line) - 1, 4)])

    merged = True
    while merged:
        merged = False
        best = None
        for i in range(len(lines)):
            for j in range(i + 1, len(lines)):
                for ea in (True, False):
                    for eb in (True, False):
                        pa = lines[i][-1] if ea else lines[i][0]
                        pb = lines[j][-1] if eb else lines[j][0]
                        if np.hypot(pa[0] - pb[0], pa[1] - pb[1]) > gap:
                            continue
                        da, db = direction(lines[i], ea), -direction(lines[j], eb)
                        na, nb_ = np.linalg.norm(da), np.linalg.norm(db)
                        if na == 0 or nb_ == 0:
                            continue
                        c = float(np.dot(da, db)) / (na * nb_)
                        if c > 0.8 and (best is None or c > best[0]):
                            best = (c, i, j, ea, eb)
        if best is not None:
            _, i, j, ea, eb = best
            a = lines[i] if ea else lines[i][::-1]
            b = lines[j][::-1] if eb else lines[j]
            lines[i] = a + b[1:]
            del lines[j]
            merged = True
    # 短い線は、ほかの線にくっついたひげなら捨てる（離れた点・濁点のような短い画は残す）
    keep = []
    for k, l in enumerate(lines):
        if _length(l) >= min_len:
            keep.append(l)
            continue
        others = [q for m, o in enumerate(lines) if m != k for q in o]
        touching = any(min(abs(e[0] - q[0]) + abs(e[1] - q[1]) for q in others) <= 3 for e in (l[0], l[-1])) if others else False
        if not touching:
            keep.append(l)
    return keep


def _arc(cx, cy, rx, ry, a0, a1, n=24):
    import math
    return [[round(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * k / n)), 4),
             round(cy + ry * math.sin(math.radians(a0 + (a1 - a0) * k / n)), 4)] for k in range(n + 1)]


## 記号は細線化だと交点でつながり方が崩れる（× が 1 画になる等）ので、黒板の手書きの書き順で直接書く。
## 字の枠は 0..1（y は上向き）、advance は送り幅。
MANUAL = {
    "×": (1.0, [[[0.25, 0.68], [0.75, 0.18]], [[0.75, 0.68], [0.25, 0.18]]]),
    "＋": (1.0, [[[0.18, 0.43], [0.82, 0.43]], [[0.5, 0.75], [0.5, 0.11]]]),
    "－": (1.0, [[[0.18, 0.43], [0.82, 0.43]]]),
    "＝": (1.0, [[[0.2, 0.53], [0.8, 0.53]], [[0.2, 0.33], [0.8, 0.33]]]),
    "→": (1.0, [[[0.1, 0.43], [0.88, 0.43]], [[0.68, 0.6], [0.89, 0.43], [0.68, 0.26]]]),
    "←": (1.0, [[[0.9, 0.43], [0.12, 0.43]], [[0.32, 0.6], [0.11, 0.43], [0.32, 0.26]]]),
    "↑": (1.0, [[[0.5, 0.06], [0.5, 0.82]], [[0.32, 0.62], [0.5, 0.83], [0.68, 0.62]]]),
    "↓": (1.0, [[[0.5, 0.82], [0.5, 0.06]], [[0.32, 0.26], [0.5, 0.05], [0.68, 0.26]]]),
    "〇": (1.0, [_arc(0.5, 0.43, 0.36, 0.38, 100, 470, 32)]),
    "△": (1.0, [[[0.5, 0.8], [0.14, 0.1], [0.86, 0.1], [0.5, 0.8]]]),
    "☆": (1.0, [[[0.5, 0.84], [0.62, 0.52], [0.94, 0.52], [0.68, 0.32], [0.78, 0.0], [0.5, 0.2], [0.22, 0.0],
                 [0.32, 0.32], [0.06, 0.52], [0.38, 0.52], [0.5, 0.84]]]),
    "★": (1.0, [[[0.5, 0.84], [0.62, 0.52], [0.94, 0.52], [0.68, 0.32], [0.78, 0.0], [0.5, 0.2], [0.22, 0.0],
                 [0.32, 0.32], [0.06, 0.52], [0.38, 0.52], [0.5, 0.84]],
                [[0.42, 0.45], [0.58, 0.45], [0.5, 0.25], [0.45, 0.4]]]),
    "？": (0.8, [[[0.18, 0.66]] + _arc(0.42, 0.64, 0.25, 0.18, 165, -60, 14)[1:] + [[0.4, 0.38], [0.4, 0.24]],
                [[0.39, 0.06], [0.41, 0.04]]]),
    "！": (0.6, [[[0.3, 0.84], [0.3, 0.24]], [[0.29, 0.06], [0.31, 0.04]]]),
    "。": (0.6, [_arc(0.22, 0.12, 0.09, 0.09, 120, 480, 14)]),
    "、": (0.6, [[[0.12, 0.2], [0.24, 0.06]]]),
    "・": (0.6, [[[0.29, 0.43], [0.31, 0.41]]]),
    "（": (0.6, [_arc(0.75, 0.43, 0.42, 0.52, 125, 235, 14)]),
    "）": (0.6, [_arc(-0.15, 0.43, 0.42, 0.52, 55, -55, 14)]),
    "(": (0.4, [_arc(0.55, 0.43, 0.32, 0.52, 125, 235, 12)]),
    ")": (0.4, [_arc(-0.15, 0.43, 0.32, 0.52, 55, -55, 12)]),
    "①": (1.0, [_arc(0.5, 0.43, 0.4, 0.4, 100, 470, 28), [[0.44, 0.58], [0.52, 0.64], [0.52, 0.22]]]),
    "②": (1.0, [_arc(0.5, 0.43, 0.4, 0.4, 100, 470, 28),
                [[0.38, 0.55], [0.45, 0.63], [0.58, 0.62], [0.62, 0.52], [0.38, 0.24], [0.64, 0.24]]]),
    "③": (1.0, [_arc(0.5, 0.43, 0.4, 0.4, 100, 470, 28),
                [[0.38, 0.6], [0.6, 0.62], [0.47, 0.45], [0.62, 0.38], [0.58, 0.26], [0.38, 0.27]]]),
    "④": (1.0, [_arc(0.5, 0.43, 0.4, 0.4, 100, 470, 28), [[0.56, 0.22], [0.56, 0.64], [0.36, 0.36], [0.66, 0.36]]]),
    "≧": (1.0, [[[0.2, 0.75], [0.8, 0.58], [0.2, 0.41]], [[0.2, 0.25], [0.8, 0.25]], [[0.2, 0.1], [0.8, 0.1]]]),
}


def glyph(ch: str, font: ImageFont.FreeTypeFont) -> dict:
    if ch in MANUAL:
        adv, strokes = MANUAL[ch]
        return {"advance": adv, "strokes": strokes}
    img = Image.new("L", (PX, PX), 0)
    d = ImageDraw.Draw(img)
    bbox = font.getbbox(ch)
    adv = font.getlength(ch)
    ascent, descent = font.getmetrics()
    d.text((0, PX * 0.9 - ascent), ch, fill=255, font=font)
    arr = (np.array(img) > 110).astype(np.uint8)
    if arr.sum() == 0:
        return {"advance": round(adv / PX, 3), "strokes": []}
    sk = _unstair(_thin(arr))
    lines = _merge(_trace(sk))
    # 点（細線化で 1 点に縮んだ小さな塊: ピリオドなど）は、塊の中心に短い点の画を置く
    if not lines:
        ys, xs = np.nonzero(arr)
        cy, cx = float(ys.mean()), float(xs.mean())
        lines = [[(int(round(cy)), int(round(cx)) - 2), (int(round(cy)), int(round(cx))), (int(round(cy)) + 1, int(round(cx)) + 2)]]
    strokes = []
    for line in lines:
        if len(line) < 3:
            continue
        pts = _rdp([(float(x), float(y)) for y, x in line], 1.2)
        strokes.append([[round(x / PX, 4), round(1.0 - y / PX, 4)] for x, y in pts])
    # 書く順: 上の画から（始点の高さ）、同じ高さなら左から。横画（横に長い）を少し先に
    def key(s):
        xs = [p[0] for p in s]
        ys = [p[1] for p in s]
        horiz = (max(xs) - min(xs)) > (max(ys) - min(ys)) * 1.5
        return (-round(max(ys) * 8.0) / 8.0, 0 if horiz else 1, min(xs))
    strokes.sort(key=key)
    # 画の向き: 横画は左から右、縦画は上から下
    for s in strokes:
        if abs(s[-1][0] - s[0][0]) > abs(s[-1][1] - s[0][1]):
            if s[-1][0] < s[0][0]:
                s.reverse()
        elif s[-1][1] > s[0][1]:
            s.reverse()
    return {"advance": round(adv / PX, 3), "strokes": strokes}


def main(extra: list[str]):
    font = ImageFont.truetype(str(FONT), int(PX * 0.86))
    chars = set(BASE_TEXT)
    for t in extra:
        chars |= set(t)
    if LESSONS.exists():
        for f in LESSONS.glob("*.json"):
            chars |= set(f.read_text(encoding="utf-8"))
    # オフライン問題集の問題・選択肢・解説の字（教科の授業で黒板に書く: lesson_builder.gd）
    if BANK.exists():
        bank = json.loads(BANK.read_text(encoding="utf-8"))
        for grades in bank.values():
            for items in grades.values():
                for q in items:
                    chars |= set(str(q.get("q", ""))) | set(str(q.get("exp", "")))
                    for c in q.get("c", []):
                        chars |= set(str(c))
    chars = sorted(c for c in chars if c.strip() and ord(c) >= 32 and c not in '{}[]":,\\')
    data = {"size": 1.0, "source": FONT.name, "glyphs": {}}
    for ch in chars:
        data["glyphs"][ch] = glyph(ch, font)
    data["glyphs"][" "] = {"advance": 0.3, "strokes": []}
    data["glyphs"]["　"] = {"advance": 1.0, "strokes": []}
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    n = sum(len(g["strokes"]) for g in data["glyphs"].values())
    print(f"GLYPHS {len(data['glyphs'])} strokes {n} -> {OUT}")


if __name__ == "__main__":
    main(sys.argv[1:])

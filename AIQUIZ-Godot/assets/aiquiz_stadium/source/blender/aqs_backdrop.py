"""遠景：島（地形・森・岩場・砂浜・白波・海の中の浅瀬）、街（ガラスの高層ビル群・中層・低い街並み・護岸）、ヨット。

v3：原本（source/master）の遠景の密度に近づける。
- 島：尾根と谷のある地形（ノイズ）、崖と地層の岩肌、すき間なく覆う樹冠（色の揺らぎと下の陰）、ヤシの群れ、水際の岩場、白波の帯。
  ゲームの海の板の内側にある島は、海の中へ続く浅瀬（砂と藻場）も作る。ゲームの海は浅いほど透けるので、島のまわりが礁湖の色になる
- 街：高層（面取り・円筒・先細り・段・ツイン・頂部の飾り）を奥と手前の 2 層に、中層、低い街並み、並木、護岸。
  窓の割り付けを建物ごとにずらして、夜の窓明かりがそろわないようにする。高いビルの頂に航空障害灯（夜だけ赤く光る）
- かすみ：頂点色に焼き込まない。Godot の遠景シェーダー（shaders/aiquiz_backdrop.gdshader）が、空の地平線の色へ距離でかすませる。
  Blender の確認シーンは同じ式の確認用材質で見る（aqs_review.haze_review_material）
島と街は部品の原点（島の中心・海面）で作り、置き場所は dimensions.json の background（方位と距離）から決める。
材質キー：bg＝遠景の頂点色（AQS_BG_Painted）、city_a〜e＝外壁、night＝夜の灯（航空障害灯・頂部の飾り）。
"""
from __future__ import annotations

import math
import random

from mathutils import Vector, noise

from aqs_geom import Mesh, hexcol, mix, shade
from aqs_sails import coons_sail

SAND, SAND_WET = hexcol("#F1E6C8"), hexcol("#D6C398")
SAND_UNDER, SEAGRASS, REEF = hexcol("#C9DDC4"), hexcol("#6E9A82"), hexcol("#A9C2A6")
SHELF_DEPTH, SHELF_EDGE = 3.8, -0.42    # 浅瀬の深さ（ゲームの海が最も透ける 4m より浅く）と、外縁の e
SCRUB = hexcol("#A5C46A")
GROUND_DARK, GROUND_MID = hexcol("#244A29"), hexcol("#43783A")
# ゲームは環境光が強く陰影が浅いので、樹冠は少し濃く鮮やかに（原本の島の緑）
CANOPY = [hexcol("#8CC04A"), hexcol("#6FAE45"), hexcol("#56993F"), hexcol("#43863C"), hexcol("#357338"), hexcol("#285F33")]
CANOPY_W = [0.08, 0.16, 0.26, 0.24, 0.17, 0.09]
CANOPY_SUN = hexcol("#B8D86A")
FAR_SEA = hexcol("#075262")          # ゲームの海（ocean.gdshader）の沖の色：深い所の混ぜ方を計算した値
PALM_LEAF, PALM_LEAF_DARK, PALM_TRUNK = hexcol("#5E9F43"), hexcol("#3F7A35"), hexcol("#8C6E4E")
FOAM, FOAM_FAR = hexcol("#F6FCFB"), hexcol("#DDF3F0")
WHITE = (1.0, 1.0, 1.0, 1.0)


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def fbm(x, y, off, octaves=4):
    """なめらかなノイズ（おおよそ -1..1）。"""
    return noise.fractal(Vector((x + off[0], y + off[1], off[2])), 1.0, 2.0, octaves, noise_basis="PERLIN_NEW")


def ridged(x, y, off, octaves=4):
    """尾根のノイズ（おおよそ 0.1..1.8、尾根ほど大きい）。"""
    return noise.ridged_multi_fractal(Vector((x + off[0], y + off[1], off[2])), 1.0, 2.0, octaves, 1.0, 2.0,
                                      noise_basis="PERLIN_NEW")


def weighted(rnd, items, weights):
    r = rnd.random() * sum(weights)
    for it, w in zip(items, weights):
        r -= w
        if r <= 0:
            return it
    return items[-1]


ISLAND_STYLES = {
    # 丘：(中心 x, 中心 y（半幅に対する比）, 半径 x, 半径 y, 高さ（最大高に対する比）, 種類)
    # ridge：尾根の強さ、canopy：森の密度、crown_m：樹冠の間隔（m）、cliff：岩肌になる傾き、strata：地層の縞
    "lush": {"hills": [(-0.20, 0.06, 0.30, 0.46, 1.00, "green"), (0.14, -0.04, 0.26, 0.40, 0.74, "green"),
                       (0.40, 0.12, 0.16, 0.26, 0.42, "green"), (-0.45, -0.18, 0.10, 0.18, 0.30, "rock")],
             "ridge": 0.2, "canopy": 0.92, "crown_m": 16.5, "cliff": 2.2, "strata": 0.0,
             "palm_groups": 13, "rock_groups": 9, "rock": "#9E8E86"},
    "rocky": {"hills": [(0.12, 0.10, 0.24, 0.46, 1.00, "rock"), (-0.16, 0.16, 0.18, 0.36, 0.72, "rock"),
                        (0.00, 0.00, 0.44, 0.50, 0.30, "green"), (0.38, -0.06, 0.15, 0.22, 0.28, "green")],
              "ridge": 0.22, "canopy": 0.86, "crown_m": 15.5, "cliff": 1.45, "strata": 1.0,
              "palm_groups": 15, "rock_groups": 10, "rock": "#B58C80"},
    "islet": {"hills": [(0.0, 0.05, 0.40, 0.55, 1.00, "green")],
              "ridge": 0.10, "canopy": 0.55, "crown_m": 10.0, "cliff": 2.0, "strata": 0.0,
              "palm_groups": 7, "rock_groups": 3, "rock": "#A8948E"},
}


class Island:
    """高さの場。海岸線は角度だけで決まる超楕円＋ゆらぎ（中心から見て一重なので、白波の帯を角度ごとに求められる）。"""

    def __init__(self, spec, seed, wet):
        self.W, self.D, self.H = spec["width"], spec["depth"], spec["height"]
        self.style = ISLAND_STYLES[spec["style"]]
        rnd = random.Random(seed)
        self.ph = [rnd.uniform(0, 6.283) for _ in range(8)]
        self.off = [(rnd.uniform(-900, 900), rnd.uniform(-900, 900), rnd.uniform(0, 60)) for _ in range(4)]
        self.rnd = rnd
        self.wet = wet or (lambda x, y: False)      # 部品の座標 (x, y) がゲームの海の板の下か
        self.L = max(self.W, self.D)

    def r_scale(self, th):
        ph, o = self.ph, self.off[3]
        return (1 + 0.07 * math.sin(2 * th + ph[0]) + 0.06 * math.sin(3 * th + ph[1]) + 0.04 * math.sin(5 * th + ph[2])
                + 0.025 * math.sin(8 * th + ph[6]) + 0.015 * math.sin(13 * th + ph[7])
                + 0.035 * noise.noise(Vector((math.cos(th) * 3 + o[0], math.sin(th) * 3 + o[1], o[2])), noise_basis="PERLIN_NEW"))

    def edge(self, x, y):
        a, b = self.W / 2, self.D / 2
        rs = self.r_scale(math.atan2(y / b, x / a))
        return 1 - ((abs(x) / (a * rs)) ** 2.3 + (abs(y) / (b * rs)) ** 2.3)

    def hills(self, x, y):
        a, b = self.W / 2, self.D / 2
        h, rock = 0.0, 0.0
        for cx, cy, rx, ry, hh, kind in self.style["hills"]:
            dx, dy = (x - cx * a) / (rx * a), (y - cy * b) / (ry * b)
            d2 = dx * dx + dy * dy
            if kind == "rock":
                # 裾野の広い岩山。上のほうだけ岩肌（起伏は sample() の crag）で、下の斜面は森
                k = math.exp(-1.8 * d2)
                g = hh * self.H * k
                rock = max(rock, smoothstep(0.42, 0.72, k))
            else:
                g = hh * self.H * math.exp(-2.3 * d2)                    # 丸い丘
            h = max(h, g) + 0.25 * min(h, g)
        return h, rock

    def sample(self, x, y):
        """(高さ, 岩の度合い, 海岸線からの内側の度合い e, 尾根の値)。"""
        e = self.edge(x, y)
        st, H, L = self.style, self.H, self.L
        if e < -0.04:
            if not self.wet(x, y):
                return -3.0, 0.0, e, 1.0
            # 海の中の浅瀬：ほぼ平らな砂の棚（藻場と礁で少し起伏）。ゲームの海は真上の水深だけで透け方が決まるので、
            # 深い斜面を作ると低い視点から海越しに崖のように見える。棚は 4m より浅く保ち、外縁（SHELF_EDGE）で終える
            t = smoothstep(-0.04, SHELF_EDGE, e)
            z = -3.0 - (SHELF_DEPTH - 3.0 - 0.3) * t + 0.3 * fbm(x / 55.0, y / 55.0, self.off[0], 3)
            return min(z, -2.6), 0.0, e, 1.0
        shore = -3.0 + 4.6 * smoothstep(-0.04, 0.10, e) + 2.2 * smoothstep(0.10, 0.28, e)
        h, rock = self.hills(x, y)
        inland = smoothstep(0.06, 0.40, e)
        n = fbm(x / (L * 0.16), y / (L * 0.16), self.off[1], 5) * 0.10 * H
        r = ridged(x / (L * 0.11), y / (L * 0.11), self.off[2], 4)
        hill_mask = smoothstep(0.08 * H, 0.55 * H, h)
        ridge_h = (r - 0.95) * st["ridge"] * H * hill_mask
        crag = (ridged(x / (L * 0.04), y / (L * 0.04), self.off[0], 3) - 1.0) * 0.12 * H * rock     # 岩肌のごつごつ
        z = shore + max(0.0, h + n + ridge_h + crag) * inland
        if st["strata"] > 0:
            rock = max(rock, smoothstep(1.25, 1.55, r) * hill_mask)        # 尾根の岩の露頭
        return z, rock, e, r

    def z(self, x, y):
        return self.sample(x, y)[0]

    def shore_point(self, th, level=0.0):
        """角度 th（楕円のパラメータ）の方向で、高さ level になる海岸の点（二分法）。"""
        a, b = self.W / 2, self.D / 2
        lo, hi = 0.0, 1.8
        for _ in range(24):
            mid = (lo + hi) / 2
            if self.z(mid * a * math.cos(th), mid * b * math.sin(th)) > level:
                lo = mid
            else:
                hi = mid
        t = (lo + hi) / 2
        return Vector((t * a * math.cos(th), t * b * math.sin(th), 0.0))


def ground_colour(isl, x, y, z, rock, e, r, slope):
    st = isl.style
    rock_c = hexcol(st["rock"])
    if z < -0.5:
        # 海の中：砂の棚に藻場と礁のまだら（ゲームの海が透けて礁湖の色になる）。外縁ほど濃く、深い海へつなぐ
        p = fbm(x / 48.0, y / 48.0, isl.off[0], 3)
        c = mix(SAND_UNDER, REEF, smoothstep(0.05, 0.45, p) * 0.7)
        c = mix(c, SEAGRASS, smoothstep(-0.05, -0.45, p) * 0.8)
        return shade(c, 1.0 - 0.45 * smoothstep(-0.1, SHELF_EDGE, e))
    if z < 1.3:
        return mix(SAND_WET, SAND, smoothstep(-0.3, 1.1, z))
    if rock > 0.45 or slope > st["cliff"]:
        # 岩肌：地層の縞と割れ目の暗さ
        band = 0.5 + 0.5 * math.sin(z * 0.32 + 2.5 * fbm(x / 90.0, y / 90.0, isl.off[1], 2))
        k = 0.84 + 0.2 * band * (0.4 + 0.6 * st["strata"]) + 0.08 * (r - 1.0)
        c = shade(rock_c, k)
        return mix(c, GROUND_MID, 0.18 * (1 - rock) * smoothstep(1.4, 0.9, slope))
    if z < 3.4:
        return mix(SAND, SCRUB, smoothstep(1.3, 3.4, z))
    # 森の床（樹冠のすき間は陰で暗い）
    k = 0.5 + 0.5 * fbm(x / 70.0, y / 70.0, isl.off[2], 3)
    c = mix(GROUND_DARK, GROUND_MID, 0.35 + 0.4 * k)
    return mix(c, SCRUB, 0.25 * smoothstep(3.4, 2.4, z))


def crown(m: Mesh, c, r, rz, top, bot, rnd, seg=6, rings=3, mat="bg", smooth=True, squash=0.45):
    """樹冠・岩の塊。輪郭をゆらして、上から下へ色がなめらかに変わる（下は陰）。"""
    cx, cy, cz = c
    jit = [rnd.uniform(0.8, 1.14) for _ in range(seg)]
    jit.append(jit[0])
    rows, cc = [], []
    for k in range(rings + 1):
        t = k / rings
        phi = -math.pi / 2 + math.pi * t
        zz = math.sin(phi) * (rz if phi > 0 else rz * squash)
        rr = math.cos(phi)
        if k in (0, rings):
            row = [(cx, cy, cz + zz)] * (seg + 1)
        else:
            row = [(cx + r * rr * jit[i] * math.cos(2 * math.pi * i / seg),
                    cy + r * rr * jit[i] * math.sin(2 * math.pi * i / seg), cz + zz * (0.9 + 0.2 * jit[i] - 0.1)) for i in range(seg + 1)]
        rows.append(row)
        cc.append([mix(bot, top, min(1.0, max(0.0, 0.1 + 0.9 * t)))] * (seg + 1))
    m.add_grid(rows, top, mat, smooth=smooth, ccol_rows=cc)


def island(spec, seed, wet=None):
    """wet(x, y)：部品の座標がゲームの海の板の下なら True。その範囲だけ海の中の浅瀬と白波を作る。"""
    isl = Island(spec, seed, wet)
    st = isl.style
    rnd = isl.rnd
    m = Mesh()
    W, D, H = isl.W, isl.D, isl.H
    ext = 0.64
    step = 8.5 if W > 500 else 5.0
    nx, ny = int(W * 2 * ext / step), int(D * 2 * ext / step)
    xs = [-W * ext + W * 2 * ext * i / nx for i in range(nx + 1)]
    ys = [-D * ext + D * 2 * ext * j / ny for j in range(ny + 1)]
    S = [[isl.sample(x, y) for x in xs] for y in ys]
    dx, dy = xs[1] - xs[0], ys[1] - ys[0]
    pts, cols = [], []
    for j, y in enumerate(ys):
        prow, crow = [], []
        for i, x in enumerate(xs):
            z, rock, e, r = S[j][i]
            zl, zr = S[j][max(i - 1, 0)][0], S[j][min(i + 1, nx)][0]
            zd, zu = S[max(j - 1, 0)][i][0], S[min(j + 1, ny)][i][0]
            c = ground_colour(isl, x, y, z, rock, e, r, math.hypot((zr - zl) / dx / 2, (zu - zd) / dy / 2))
            if z > 1.3:
                # 谷は暗く尾根は明るく（ゲームの環境光は強く陰影が浅いので、地形の凹凸を頂点色に入れる）
                lap = (zl + zr - 2 * z) / (dx * dx) + (zd + zu - 2 * z) / (dy * dy)
                c = shade(c, 1.0 - 0.34 * smoothstep(0.004, 0.05, lap) + 0.1 * smoothstep(0.004, 0.05, -lap))
            prow.append((x, y, z))
            crow.append(c)
        pts.append(prow)
        cols.append(crow)
    wets = [[isl.wet(x, y) for x in xs] for y in ys]
    m.shelf_faces = 0
    for j in range(ny):
        for i in range(nx):
            corners = ((j, i), (j, i + 1), (j + 1, i + 1), (j + 1, i))
            zs = [S[a][b][0] for a, b in corners]
            if any(wets[a][b] for a, b in corners):
                if all(S[a][b][2] < SHELF_EDGE for a, b in corners):     # 浅瀬の外縁より外は張らない
                    continue
                if max(zs) < -0.5:
                    m.shelf_faces += 1
            elif max(zs) < -2.2:                                          # 海の板の外の水面下は張らない
                continue
            quad = [pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]
            cc = [cols[j][i], cols[j][i + 1], cols[j + 1][i + 1], cols[j + 1][i]]
            m.add_face(quad, cc[0], "bg", smooth=True, ccol=cc)

    def slope_at(x, y):
        return math.hypot(isl.z(x + 2, y) - isl.z(x - 2, y), isl.z(x, y + 2) - isl.z(x, y - 2)) / 4

    # --- 森：すき間なく覆う樹冠（空き地はノイズで）。高い所ほど日が当たって明るい
    cs = st["crown_m"]
    gx, gy = int(W / cs) + 1, int(D / cs) + 1
    for j in range(gy):
        for i in range(gx):
            x = -W / 2 + (i + rnd.uniform(0.1, 0.9)) * cs
            y = -D / 2 + (j + rnd.uniform(0.1, 0.9)) * cs
            z, rock, e, r = isl.sample(x, y)
            if z < 3.2 or rock > 0.42 or e < 0.13:
                continue
            clearing = fbm(x / 110.0, y / 110.0, isl.off[3], 2)
            if rnd.random() > st["canopy"] * (1.0 if clearing > -0.25 else 0.35):
                continue
            if slope_at(x, y) > st["cliff"] * 1.1:
                continue
            emergent = rnd.random() < 0.12
            rad = cs * rnd.uniform(0.5, 0.78) * (1.35 if emergent else 1.0)
            col = weighted(rnd, CANOPY, CANOPY_W)
            sun = smoothstep(0.1 * H, 0.9 * H, z) * 0.35 + (r - 1.0) * 0.15
            col = mix(col, CANOPY_SUN, max(0.0, min(0.45, sun)))
            k = rnd.uniform(0.9, 1.07)
            top = shade(mix(col, CANOPY_SUN, 0.18), k)
            bot = shade(col, 0.42 * k)
            crown(m, (x, y, z + rad * 0.3), rad, rad * rnd.uniform(0.74, 0.9), top, bot, rnd, seg=6, rings=4)
            if emergent or rnd.random() < 0.15:
                a = rnd.uniform(0, 6.283)
                rr = rad * rnd.uniform(0.5, 0.7)
                crown(m, (x + math.cos(a) * rad * 0.45, y + math.sin(a) * rad * 0.45, z + rad * 0.8), rr, rr * 0.8,
                      shade(top, 1.04), shade(bot, 1.1), rnd, seg=6)

    # --- ヤシ：砂浜の後ろに群れで。海へ傾ける
    ph = max(12.0, W * 0.02)
    placed = 0
    for g in range(st["palm_groups"] * 6):
        if placed >= st["palm_groups"]:
            break
        th = rnd.uniform(0, 2 * math.pi)
        p = isl.shore_point(th, 1.6)
        inward = -Vector((p.x / (W / 2) ** 2, p.y / (D / 2) ** 2, 0)).normalized()
        base = p + inward * rnd.uniform(2.0, 16.0)
        if isl.sample(base.x, base.y)[1] > 0.3:
            continue
        placed += 1
        for _ in range(rnd.randint(2, 6)):
            q = base + Vector((rnd.uniform(-11, 11), rnd.uniform(-11, 11), 0))
            z, rock, e, r = isl.sample(q.x, q.y)
            if not (1.0 < z < 7.5) or rock > 0.3:
                continue
            out = -inward
            lean = (out.x * rnd.uniform(0.12, 0.3) + rnd.uniform(-0.08, 0.08), out.y * rnd.uniform(0.12, 0.3) + rnd.uniform(-0.08, 0.08))
            palm(m, (q.x, q.y, z - 0.5), ph * rnd.uniform(0.75, 1.15), lean, rnd)

    # --- 水際の岩場（面の角が立った岩の群れ）
    rock_c = hexcol(st["rock"])
    rb = max(4.0, W * 0.008)
    for g in range(st["rock_groups"]):
        th = rnd.uniform(0, 2 * math.pi)
        p = isl.shore_point(th, 0.0)
        for _ in range(rnd.randint(3, 7)):
            q = p + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * rb * 2.2
            rad = rb * rnd.uniform(0.45, 1.3)
            k = rnd.uniform(0.85, 1.1)
            crown(m, (q.x, q.y, -0.6 + rad * 0.15), rad, rad * rnd.uniform(0.5, 0.8), shade(rock_c, 1.12 * k),
                  shade(rock_c, 0.62 * k), rnd, seg=6, rings=3, smooth=False, squash=0.9)

    # --- 白波：波打ち際の帯（ところどころ切れる）と、沖の礁で砕ける薄い帯。海の板の下だけ
    if isl.wet(0.0, D * 0.6) or isl.wet(0.0, -D * 0.6) or isl.wet(W * 0.6, 0.0) or isl.wet(-W * 0.6, 0.0):
        n = max(120, int((W + D) * 1.6 / 6.0))
        for band, (d0, d1, z_, keep, col) in enumerate(((-1.2, 3.6, 0.36, -0.45, FOAM), (14.0, 17.5, 0.3, 0.15, FOAM_FAR))):
            ring = []
            for i in range(n + 1):
                th = 2 * math.pi * i / n
                p = isl.shore_point(th, 0.0)
                nrm = Vector((p.x / (W / 2) ** 2, p.y / (D / 2) ** 2, 0)).normalized()
                ring.append((p, nrm, th))
            o = isl.off[band]
            for i in range(n):
                (p0, n0, th0), (p1, n1, _) = ring[i], ring[i + 1]
                if not isl.wet(p0.x, p0.y):
                    continue
                if noise.noise(Vector((math.cos(th0) * 7 + o[0], math.sin(th0) * 7 + o[1], o[2])), noise_basis="PERLIN_NEW") < keep:
                    continue
                a0, a1 = p0 + n0 * d0, p1 + n1 * d0
                b0, b1 = p0 + n0 * d1, p1 + n1 * d1
                m.add_face([(a0.x, a0.y, z_), (b0.x, b0.y, z_), (b1.x, b1.y, z_), (a1.x, a1.y, z_)], col, "bg")
    return m


def palm(m: Mesh, base, h, lean, rnd, mat="bg"):
    """ヤシ：曲がった幹と、弓なりに垂れる葉（両面）。"""
    x0, y0, z0 = base
    pts = []
    for k in range(5):
        t = k / 4
        pts.append(Vector((x0 + lean[0] * h * t * t, y0 + lean[1] * h * t * t, z0 + h * t)))
    for k in range(4):
        m.tube(pts[k], pts[k + 1], h * (0.026 - 0.004 * k), PALM_TRUNK, mat, n=4)
    top = pts[-1]
    nf = 8
    for i in range(nf):
        a = 2 * math.pi * i / nf + rnd.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        L = h * rnd.uniform(0.4, 0.52)
        droop = rnd.uniform(0.55, 0.8)
        leaf = mix(PALM_LEAF, PALM_LEAF_DARK, rnd.uniform(0.0, 0.6))
        prev_c, prev_w = top, 0.0
        for s in range(1, 4):
            t = s / 3
            c = top + d * L * t + Vector((0, 0, L * (0.32 * t - droop * t * t)))
            w = L * 0.14 * math.sin(math.pi * min(1.0, t * 1.1))
            col = shade(leaf, 0.82 + 0.2 * (1 - t))
            if prev_w == 0.0:
                m.tri2(prev_c, c + side * w, c - side * w, col, mat)
            else:
                m.quad2(prev_c + side * prev_w, prev_c - side * prev_w, c - side * w, c + side * w, col, mat)
            prev_c, prev_w = c, w


# --- 街 ---------------------------------------------------------------------
TILE_U, TILE_V = 28.0, 32.0         # 外壁のテクスチャ 1 枚 = 8 スパン × 8 階（1 階 4m）
FACADES = ["city_a", "city_b", "city_c", "city_d", "city_e"]
BEACON = hexcol("#FF3B2E")          # 航空障害灯（夜の灯の材質。昼は赤い小さな箱）
CROWN_LIGHT = hexcol("#FFE6B0")

LANDMARKS = [
    # x, y（奥行き、+Y が手前）, 幅, 奥行き, 高さ, 外壁, 頂部, 平面
    (-60, 10, 40, 40, 340, "city_a", "slant", "rect"),
    (45, -55, 46, 36, 300, "city_c", "spire", "chamfer"),
    (-175, -35, 36, 36, 255, "city_d", "stepped", "rect"),
    (150, 25, 38, 30, 235, "city_b", "antenna", "rect"),
    (-265, 15, 34, 34, 212, "city_c", "crown", "chamfer"),
    (255, -45, 34, 34, 200, "city_a", "round", "round"),
    (-5, 90, 44, 34, 186, "city_e", "stepped", "rect"),
    (-125, 95, 34, 30, 168, "city_c", "flat", "taper"),
    (105, 95, 36, 30, 158, "city_d", "slant", "rect"),
    (335, 45, 32, 30, 148, "city_b", "antenna", "chamfer"),
    (-345, 70, 32, 30, 138, "city_a", "flat", "rect"),
    (-430, -20, 36, 32, 118, "city_e", "stepped", "rect"),
    (430, -15, 34, 30, 112, "city_c", "flat", "round"),
]
TWIN = (205, -150, 28, 28, 192, "city_d")


def outline_for(plan, x, y, w, d):
    if plan == "round":
        n = 14
        return [(x + w / 2 * math.cos(2 * math.pi * i / n), y + d / 2 * math.sin(2 * math.pi * i / n)) for i in range(n)]
    if plan == "chamfer":
        c = min(w, d) * 0.2
        hw, hd = w / 2, d / 2
        return [(x - hw + c, y - hd), (x + hw - c, y - hd), (x + hw, y - hd + c), (x + hw, y + hd - c),
                (x + hw - c, y + hd), (x - hw + c, y + hd), (x - hw, y + hd - c), (x - hw, y - hd + c)]
    return [(x - w / 2, y - d / 2), (x + w / 2, y - d / 2), (x + w / 2, y + d / 2), (x - w / 2, y + d / 2)]


def scaled(outline, x, y, k):
    return [(x + (p[0] - x) * k, y + (p[1] - y) * k) for p in outline]


class Facade:
    """1 棟の外壁：窓の割り付けのずれ（u0, v0）と、下が暗く上が空を映して明るい頂点色。"""

    def __init__(self, m, mat, tint, h, rnd):
        self.m, self.mat, self.h = m, mat, h
        self.u0 = rnd.randint(0, 7) / 8
        self.v0 = rnd.randint(0, 7) / 8
        self.lo, self.hi = shade(tint, 0.8), shade(tint, 1.06)

    def col(self, z):
        return mix(self.lo, self.hi, min(1.0, max(0.0, z / self.h)))

    def band(self, lo_ol, hi_ol, z0, z1):
        """lo_ol（高さ z0）から hi_ol（z1）へ張る外壁の帯。2 つの外周は同じ点の数。"""
        n = len(lo_ol)
        u = self.u0
        c0, c1 = self.col(z0), self.col(z1)
        for i in range(n):
            a0, b0 = lo_ol[i], lo_ol[(i + 1) % n]
            a1, b1 = hi_ol[i], hi_ol[(i + 1) % n]
            L = math.hypot(b0[0] - a0[0], b0[1] - a0[1])
            v0, v1 = self.v0 + z0 / TILE_V, self.v0 + z1 / TILE_V
            uv = [(u, v0), (u + L / TILE_U, v0), (u + L / TILE_U, v1), (u, v1)]
            self.m.add_face([(a0[0], a0[1], z0), (b0[0], b0[1], z0), (b1[0], b1[1], z1), (a1[0], a1[1], z1)], c0, self.mat, uv,
                            ccol=[c0, c0, c1, c1])
            u += L / TILE_U


def cap(m, outline, z, col):
    n = len(outline)
    cx = sum(p[0] for p in outline) / n
    cy = sum(p[1] for p in outline) / n
    for i in range(n):
        a, b = outline[i], outline[(i + 1) % n]
        m.add_face([(cx, cy, z), (a[0], a[1], z), (b[0], b[1], z)], col, "bg")


def roof_kit(m, x, y, w, d, z, roof, rnd):
    """屋上の設備：機械室の箱・給水槽。"""
    for _ in range(rnd.randint(1, 3)):
        bw, bd = w * rnd.uniform(0.2, 0.45), d * rnd.uniform(0.2, 0.45)
        bx, by = x + rnd.uniform(-0.5, 0.5) * (w - bw), y + rnd.uniform(-0.5, 0.5) * (d - bd)
        bh = rnd.uniform(2.5, 6.0)
        m.box((bx, by, z + bh / 2), (bw, bd, bh), shade(roof, rnd.uniform(0.86, 1.0)), "bg")


def tower(m, x, y, w, d, h, mat, crown_kind, plan, rnd, roof, podium=True):
    tint = mix(WHITE, rnd.choice([hexcol("#DCE8F2"), hexcol("#F3EEE4"), hexcol("#E1F0EC"), hexcol("#E8E6F2")]), rnd.uniform(0.0, 0.6))
    tint = shade(tint, rnd.uniform(0.92, 1.03))
    fac = Facade(m, mat, tint, h, rnd)
    base = outline_for(plan, x, y, w, d)
    z = 0.0
    if podium and h > 90:
        ph = rnd.uniform(14.0, 26.0)
        pod = outline_for("rect", x, y, w * 1.45, d * 1.35)
        pf = Facade(m, rnd.choice(["city_b", "city_e"]), shade(tint, 0.97), ph * 3, rnd)
        pf.band(pod, pod, 0.0, ph)
        cap(m, pod, ph, roof)
        z = ph
    if crown_kind == "stepped":
        secs = [(0.0, 0.58, 1.0, 1.0), (0.58, 0.84, 0.84, 0.84), (0.84, 1.0, 0.66, 0.66)]
    elif plan == "taper":
        secs = [(0.0, 1.0, 1.0, 0.7)]
    else:
        secs = [(0.0, 1.0, 1.0, 1.0)]
    for f0, f1, k0, k1 in secs:
        z0 = max(z, h * f0)
        fac.band(scaled(base, x, y, k0), scaled(base, x, y, k1), z0, h * f1)
        if f1 < 1.0:
            cap(m, scaled(base, x, y, k1), h * f1, roof)
    k_top = secs[-1][3]
    top = scaled(base, x, y, k_top)
    wk, dk = w * k_top, d * k_top
    peak = h
    if crown_kind == "slant" and plan == "rect":
        # 斜めに切った頂部（+X へ上がる）
        rise = wk * 0.75
        a, b, c, dd = top
        za, zb = h, h + rise
        tc = fac.col(h)
        u = fac.u0
        m.add_face([(a[0], a[1], za), (b[0], b[1], za), (b[0], b[1], zb)], tc, mat,
                   [(u, fac.v0 + za / TILE_V), (u + wk / TILE_U, fac.v0 + za / TILE_V), (u + wk / TILE_U, fac.v0 + zb / TILE_V)])
        m.add_face([(c[0], c[1], za), (dd[0], dd[1], za), (c[0], c[1], zb)], tc, mat,
                   [(u, fac.v0 + za / TILE_V), (u + wk / TILE_U, fac.v0 + za / TILE_V), (u, fac.v0 + zb / TILE_V)])
        m.add_face([(b[0], b[1], za), (c[0], c[1], za), (c[0], c[1], zb), (b[0], b[1], zb)], tc, mat,
                   [(u, fac.v0 + za / TILE_V), (u + dk / TILE_U, fac.v0 + za / TILE_V), (u + dk / TILE_U, fac.v0 + zb / TILE_V),
                    (u, fac.v0 + zb / TILE_V)])
        m.add_face([(a[0], a[1], za), (b[0], b[1], zb), (c[0], c[1], zb), (dd[0], dd[1], za)], shade(roof, 1.02), "bg")
        peak = zb
        bx, by = (b[0] + c[0]) / 2, (b[1] + c[1]) / 2
    else:
        cap(m, top, h, roof)
        bx, by = x, y
        if crown_kind == "spire":
            m.prism(x, y, h, h + 14, wk * 0.32, wk * 0.22, 8, roof, "bg")
            m.cone(x, y, h + 14, h + 48, wk * 0.12, 6, roof, "bg")
            peak = h + 48
        elif crown_kind == "antenna":
            m.box((x, y, h + 3), (wk * 0.5, dk * 0.5, 6), roof, "bg")
            m.prism(x, y, h + 6, h + 36, 0.9, 0.5, 5, roof, "bg")
            peak = h + 36
        elif crown_kind == "round":
            m.dome(x, y, h, wk * 0.42, wk * 0.3, 12, 3, roof, "bg")
            peak = h + wk * 0.3
        elif crown_kind == "crown":
            # 頂部の飾り枠（夜に灯る）
            ch = h * 0.07
            ring = scaled(top, x, y, 0.98)
            for p in ring[::2]:
                m.box((p[0], p[1], h + ch / 2), (1.6, 1.6, ch), CROWN_LIGHT, "night")
            for zz in (h + ch * 0.45, h + ch):
                for i in range(len(ring)):
                    m.beam((ring[i][0], ring[i][1], zz), (ring[(i + 1) % len(ring)][0], ring[(i + 1) % len(ring)][1], zz), 1.2,
                           CROWN_LIGHT, "night")
            peak = h + ch
        else:
            roof_kit(m, x, y, wk * 0.8, dk * 0.8, h, roof, rnd)
            peak = h + 4
    if h >= 180:
        m.box((bx, by, peak + 1.5), (3.0, 3.0, 3.0), BEACON, "night")


def midrise(m, x, y, w, d, h, rnd, roof):
    mat = rnd.choice(FACADES)
    plan = rnd.choice(["rect", "rect", "rect", "chamfer"])
    crown_kind = rnd.choice(["flat", "flat", "flat", "stepped", "antenna"])
    tower(m, x, y, w, d, h, mat, crown_kind, plan, rnd, roof, podium=False)


def city(spec, seed=7):
    rnd = random.Random(seed)
    m = Mesh()
    roof = hexcol("#D6DDE2")
    # 土地（手前が +Y）：奥の層まで。緑の多い手前の岸
    land = [(-660, -460), (660, -460), (680, 210), (580, 252), (-580, 252), (-680, 210)]
    m.extrude_poly(land, -3.0, 4.5, hexcol("#C3CBC0"), "bg", top=hexcol("#AFC2A5"), bottom=False)
    # 護岸と砂浜（ところどころ）
    x = -580.0
    while x < 580:
        seg = rnd.uniform(40, 90)
        m.box_lohi((x, 246, -3.0), (min(580, x + seg), 254, 4.9), hexcol("#D3D6D2"), "bg", top=hexcol("#E6E6E0"), faces=["top", "+y"])
        if rnd.random() < 0.35:
            m.box_lohi((x + 4, 254, -2.5), (min(580, x + seg) - 4, 268, 0.9), SAND, "bg", faces=["top", "+y"])
        x += seg
    # 並木（護岸の内側）
    x = -560.0
    while x < 560:
        r = rnd.uniform(4.0, 6.5)
        col = weighted(rnd, CANOPY, CANOPY_W)
        crown(m, (x, 240 + rnd.uniform(-2, 2), 4.5 + r * 0.9), r, r * 0.8, shade(col, 1.05), shade(col, 0.55), rnd, seg=5)
        x += rnd.uniform(16, 28)
    # 高層：手前の層（原本の細いガラスの塔）とツイン
    for lx, ly, lw, ld, lh, mat, crown_kind, plan in LANDMARKS:
        tower(m, lx, ly, lw, ld, lh, mat, crown_kind, plan, rnd, roof)
    tx, ty, tw, td, th, tm = TWIN
    for sx in (-1, 1):
        tower(m, tx + sx * tw * 0.8, ty, tw, td, th, tm, "flat", "chamfer", rnd, roof, podium=False)
    m.box((tx, ty, th * 0.62), (tw * 0.7, td * 0.5, 9.0), roof, "bg")       # 空中の連絡橋
    taken = [(lx, ly, lw, ld) for lx, ly, lw, ld, *_ in LANDMARKS] + [(tx, ty, tw * 2.6, td)]

    def free(x, y, w, d, pad=16):
        return not any(abs(x - ox) < (w + ow) / 2 + pad and abs(y - oy) < (d + od) / 2 + pad for ox, oy, ow, od in taken)

    # 奥の層：中央ほど高く、両端へ低く
    for _ in range(40):
        if sum(1 for t in taken if t[1] < -200) >= 18:
            break
        x, y = rnd.uniform(-520, 520), rnd.uniform(-400, -215)
        w, d = rnd.uniform(26, 40), rnd.uniform(24, 36)
        if not free(x, y, w, d):
            continue
        falloff = 1 - (abs(x) / 560) ** 2
        h = rnd.uniform(95, 230) * (0.45 + 0.55 * falloff)
        tower(m, x, y, w, d, h, rnd.choice(FACADES), rnd.choice(["flat", "flat", "stepped", "antenna", "round"]),
              rnd.choice(["rect", "rect", "chamfer", "round", "taper"]), rnd, roof)
        taken.append((x, y, w, d))
    # 中層（高層の周りを埋め、両端へ低くなる）
    for _ in range(140):
        if len(taken) >= 14 + 18 + 46:
            break
        x, y = rnd.uniform(-500, 500), rnd.uniform(-190, 130)
        w, d = rnd.uniform(22, 36), rnd.uniform(20, 32)
        if not free(x, y, w, d, 10):
            continue
        falloff = 1 - (abs(x) / 540) ** 2
        h = rnd.uniform(40, 115) * (0.5 + 0.5 * falloff)
        midrise(m, x, y, w, d, h, rnd, roof)
        taken.append((x, y, w, d))
    # 公園の木立（ビルのすき間）
    for _ in range(26):
        x, y = rnd.uniform(-480, 480), rnd.uniform(-180, 120)
        if not free(x, y, 30, 30, 0):
            continue
        for _k in range(rnd.randint(3, 6)):
            r = rnd.uniform(4.5, 7.0)
            col = weighted(rnd, CANOPY, CANOPY_W)
            crown(m, (x + rnd.uniform(-14, 14), y + rnd.uniform(-14, 14), 4.5 + r * 0.8), r, r * 0.8, shade(col, 1.05),
                  shade(col, 0.55), rnd, seg=5)
    # 手前の低い街並み（白・クリーム・淡い色、ところどころ赤茶の屋根と屋上の設備）
    pastel = [hexcol("#F1EEE6"), hexcol("#E9E2D2"), hexcol("#DDE6EA"), hexcol("#F0E4D8"), hexcol("#E4E8DD"), hexcol("#EFE7DA")]
    roofs = [hexcol("#D9D6CF"), hexcol("#CFC9BE"), hexcol("#B98A6E"), hexcol("#C9CFD3")]
    for row_y, depth, hmul in ((218, 24, 1.0), (186, 26, 1.3), (152, 28, 1.6)):
        x = -590.0
        run = 0
        while x < 590:
            w = rnd.uniform(18, 44)
            run += 1
            if run > rnd.randint(3, 6):          # 通り
                x += rnd.uniform(10, 16)
                run = 0
                continue
            if free(x + w / 2, row_y, w, depth, 2):
                h = rnd.uniform(10, 30) * hmul
                c = rnd.choice(pastel)
                rc = rnd.choice(roofs)
                m.box_lohi((x, row_y - depth / 2, 4.5), (x + w - 3, row_y + depth / 2, 4.5 + h), c, "bg", top=rc)
                if rnd.random() < 0.4:
                    roof_kit(m, x + w / 2 - 1.5, row_y, w * 0.6, depth * 0.6, 4.5 + h, shade(rc, 0.95), rnd)
            x += w
    return m


# --- 遠い海 -------------------------------------------------------------------
def far_sea(center_b, half, radius, z, inset=2.0, rings=9, segs=120):
    """ゲームの海の板（半透明の海のシェーダー）の外側を埋める沖の海。Blender のワールド座標で作る。
    center_b：海の板の中心（Blender の x, y）、half：海の板の半分の大きさ、radius：外周の半径。
    内側の縁は海の板の四角形に沿わせ（角も通る）、inset m だけ下へ潜らせて重ねる。重なりを広くすると、
    海のシェーダーが浅い所の明るい色で描いて帯が見えるので最小限にする。かすみは Godot の遠景シェーダーが
    海の板の縁から少しずつかける（縁で海の色とそろえる）。"""
    m = Mesh()
    cx, cy = center_b
    hx, hy = half
    spokes = []
    for s in range(segs):                            # 4 の倍数なら 45° ごとの角（海の板の角）を通る
        a = 2 * math.pi * s / segs
        dx, dy = math.cos(a), math.sin(a)
        ix, iy = hx - inset, hy - inset              # inset m 内側の四角形の上
        t = min(ix / abs(dx) if abs(dx) > 1e-9 else 1e18, iy / abs(dy) if abs(dy) > 1e-9 else 1e18)
        ring = []
        for k in range(rings + 1):
            r = t + (radius - t) * (k / rings) ** 1.4
            ring.append((cx + dx * r, cy + dy * r))
        spokes.append(ring)
    for s in range(segs):
        a, b = spokes[s], spokes[(s + 1) % segs]
        for k in range(rings):
            m.add_face([(p[0], p[1], z) for p in (a[k], a[k + 1], b[k + 1], b[k])], FAR_SEA, "sea")
    return m


# --- ヨット -----------------------------------------------------------------
SAIL_COLS = {"white": hexcol("#F6F3EC"), "cobalt": hexcol("#2F66C0"), "orange": hexcol("#F08A34")}


def sailboat(length, sail, seed):
    rnd = random.Random(seed)
    m = Mesh()
    L, B = length, length * 0.3
    hull, deck, trim = hexcol("#F7F6F2"), hexcol("#D8C3A0"), hexcol("#2B4E86")
    # 船体：ステーションごとの断面（なめらか）
    stations = []
    for k in range(9):
        t = k / 8                                   # 0＝船尾、1＝船首
        x = -L / 2 + L * t
        half = B / 2 * (1 - (max(0.0, t - 0.55) / 0.45) ** 1.8) * (0.82 + 0.18 * math.sin(math.pi * min(1.0, t * 1.4)))
        sheer = 0.85 + 0.25 * t * t
        keel = -0.35 * math.sin(math.pi * t) - 0.1
        stations.append([(x, -half, sheer), (x, -half * 0.8, keel * 0.5 + 0.1), (x, 0.0, keel), (x, half * 0.8, keel * 0.5 + 0.1), (x, half, sheer)])
    m.add_grid(stations, hull, smooth=True)
    for k in range(8):
        a, b = stations[k], stations[k + 1]
        m.add_face([a[0], b[0], b[4], a[4]], deck)
        m.beam(a[0], b[0], 0.08, trim)
        m.beam(a[4], b[4], 0.08, trim)
    m.box((-L * 0.08, 0, 1.2), (L * 0.32, B * 0.5, 0.55), hull, top=shade(hull, 0.95))
    m.box_lohi((L * 0.075, -B * 0.22, 1.05), (L * 0.085, B * 0.22, 1.35), hexcol("#2A3440"), faces=["+x"])
    mast_x = L * 0.06
    mh = L * 1.3
    wood = hexcol("#C9CDD2")
    m.tube((mast_x, 0, 1.0), (mast_x, 0, 1.0 + mh), 0.07, wood, n=6)
    boom_end = (-L * 0.42, 0, 1.9)
    m.tube((mast_x, 0, 1.9), boom_end, 0.05, wood, n=5)
    col = SAIL_COLS[sail]
    side = 1 if rnd.random() < 0.5 else -1

    def sail_surface(H, T, K, depth, nu=6, nv=6):
        rows = coons_sail(H, T, K, 0.12, 0.06, 0.0, nu, nv)
        uvr, pts = [], []
        for i, row in enumerate(rows):
            v = i / nv
            r2, u2 = [], []
            for j, p in enumerate(row):
                u = j / nu
                f = 4 * u * (1 - u) * math.sin(math.pi * v ** 0.9)
                p.y += side * depth * f
                r2.append(tuple(p))
                u2.append((u, v))
            pts.append(r2)
            uvr.append(u2)
        m.add_grid(pts, col, "sail", uv_rows=uvr, smooth=True)

    sail_surface((mast_x - 0.12, 0, 1.0 + mh * 0.97), (mast_x - 0.12, 0, 2.05), (boom_end[0] + 0.2, 0, 2.05), L * 0.07)
    sail_surface((mast_x + 0.1, 0, 1.0 + mh * 0.8), (L * 0.47, 0, 1.2), (mast_x + L * 0.08, side * 0.3, 1.7), L * 0.05)
    return m

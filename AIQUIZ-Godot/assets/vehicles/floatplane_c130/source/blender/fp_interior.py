"""水上機 C-130 の機内（docs/sudden_death_v2/c130_float.md 第5章、A：実機ふう）。操縦席は fp_cockpit.py。

2026-10-18：ユーザーの指示で「実際の C-130 の機内を実写の水準で」作り込んだ。手本は実機の写真（Wikimedia Commons の
C-130H／C-130J の貨物室）：
  壁と天井   骨組み（リブ）の間を、灰緑のキルティングの断熱材が枕のようにふくらんで覆う（横の縫い目 0.5 m ごと）
  天井       両わきに太い空調ダクト（黄土色、留め金つき）、真ん中寄りに降下の静索 2 本、丸いダウンライト、黄色い非常灯
  壁の上     配管と電線の束（銀・灰・緑・黒）を P 形の留め金で骨組みに留める。インターホンの箱、位置番号のステンシル「LS ○○○」
  座席       赤いナイロンの布の座面（前の管と壁の管の間にたるむ）と、上の管から吊るベルトのはしご状の背もたれ。
             アルミの管の脚と横棒、席ごとの腰のベルト（垂れている）
  床         アルミの板（1 m の継ぎ目）、ローラーの列 4 本、黄色い線、丸いつなぎ止めの輪（50.8 cm の格子）
  そのほか   乗員の扉（左の前、小さな窓）、消火器・救急箱・酸素の盤・懐中電灯、座席の下の袋、太い白い縁の丸窓、
             後ろの開口の枠（黄色と黒の縞）、降下のランプ、スロープの作動筒
寸法の約束（ベンチの位置・座る高さ・通路・窓・手すり・ランプの高さ）は c130_design.py の「機内」のまま。
"""
from __future__ import annotations

import json
import math
from pathlib import Path

from mathutils import Vector

import fp_section as S
from fp_common import GMesh, W, lerp

C = S.C

FLOOR_V = C.FLOOR_V
DECK_V = C.FLIGHT_DECK_V
SEAT_V = C.BENCH_SEAT_V
BENCH_U = C.BENCH_U
BENCH_INNER_X = C.BENCH_INNER_X
SIT_U = C.SIT_U
PORTAL_U = (10.95, 11.19)        # 後ろの開口の枠（スロープの付け根の前）
OPENING_TOP_V = C.OPENING_TOP_V  # 5.20
OPENING_CORNER_R = 0.18
# 骨組み：丸窓（u 5.4・7.6・9.8）の両わき ±0.42、乗員の扉（左 u 3.38〜4.30）の上は左だけ切る
FRAME_US = [3.81, 4.42, 4.98, 5.82, 6.50, 7.18, 8.02, 8.70, 9.38, 10.22, 10.60]
RIB_DEPTH = 0.085
RIB_WIDTH = 0.06
BLANKET_BASE = 0.025             # 断熱材の縁の、内張りからの浮き
BLANKET_PUFF = 0.045             # 真ん中のふくらみ（骨組みより 1.5 cm 低い）
BACK_PUFF_SCALE = 0.40           # 座席の背もたれの後ろ（v < 3.5）は薄く（ベルトの後ろに収める）
QUILT_ROW = 0.50                 # 横の縫い目の間隔（テクスチャの 1 枚と同じ）
WALL_V0 = FLOOR_V + 0.05         # 断熱材の下の端
DOOR_U = (3.38, 4.30)            # 乗員の扉（左の壁）
DOOR_TOP_V = 4.10
DOOR_WINDOW = (3.84, 3.55, 0.12)   # 扉の窓（u, v, 半径）
BENCH_BACK_X = 1.925             # 背もたれのベルトの |x|（骨組みと断熱材より手前）
BENCH_REAR_X = 1.915             # 座面の後ろの管
SEAT_PITCH = 0.50                # 1 席の幅
SEAT_TOP_V = SEAT_V + 0.006
BACK_TOP_V = SEAT_V + 1.04
DUCT_X, DUCT_V, DUCT_R = 1.36, 5.10, 0.14
STATIC_X, STATIC_V = 0.42, 5.40
LIGHT_X = 0.75
LINES_V = [4.66, 4.71, 4.76, 4.81, 4.86]
LS_V = 3.66
PILOT_ROOT_U = C.PILOT_SEAT_U    # 1.75：ハテナの原点（足元の基準）
PILOT_ROOT_V = DECK_V + 0.25     # ヘリと同じ：原点は床から 0.25、座面は原点から 0.48
PILOT_CUSHION_V = PILOT_ROOT_V + 0.48
YOKE_GRIP = (0.586, PILOT_ROOT_V + 0.818, PILOT_ROOT_U - 0.361)    # ヘリの操縦かんとハテナの手の位置の関係と同じ（x, v, u）
DASH_FACE_U = (0.86, 0.74)       # 計器盤の面（下, 上）の u
DASH_V = (3.36, 4.02)
ROLLER_X = (0.50, 1.18)
YELLOW_X = 0.84
RING_X = (0.0, 0.84)
RING_PITCH = 0.508

TEX = Path(__file__).resolve().parents[2] / "textures"
_DEC = json.loads((TEX / "fp_decals.json").read_text(encoding="utf-8")) if (TEX / "fp_decals.json").exists() else {"regions": {}, "items": {}}

LIGHTS: list = []      # 機内の灯（Godot が光源を置く）：{"kind", "position", "direction"}


def bay_list():
    edges = [C.STEPS_U[0] + 0.01] + FRAME_US + [PORTAL_U[0]]
    return list(zip(edges[:-1], edges[1:]))


def bay_centers():
    return [0.5 * (a + b) for a, b in bay_list()]


def wall_x(u, v):
    """内張りの |x|（超楕円で近似）。"""
    return S.x_at_v(S.inner_section(u), v)


def roof_v(u, x):
    """内張りの天井の高さ（x での）。"""
    s = S.inner_section(u)
    th = math.acos(min(1.0, (abs(x) / s["a"]) ** (s["nt"] / 2)))
    return S.point(s, th)[1]


def contour(u, v_from, n=40, inset=0.0):
    """内張りの輪郭：右の v_from から上を通って左の v_from まで（inset だけ内側）。"""
    s = S.inner_section(u)
    th0 = S.theta_for_v(s, v_from)
    right = []
    for i in range(n + 1):
        th = th0 + (math.pi / 2 - th0) * i / n
        x, v = S.point(s, th)
        nx, nv = S.normal(s, th)
        right.append((x - inset * nx, v - inset * nv))
    left = [(-x, v) for x, v in reversed(right[:-1])]
    return right + left


class Profile:
    """u での内張りの輪郭を、床の右の端から測った長さ t で引けるようにした物（右 → 天井 → 左）。"""

    def __init__(self, u, v_from=WALL_V0, n=360):
        s = S.inner_section(u)
        th0 = S.theta_for_v(s, v_from)
        pts, nrm = [], []
        for i in range(n + 1):
            th = th0 + (math.pi / 2 - th0) * i / n
            pts.append(S.point(s, th))
            nrm.append(S.normal(s, th))
        L = [0.0]
        for (xa, va), (xb, vb) in zip(pts[:-1], pts[1:]):
            L.append(L[-1] + math.hypot(xb - xa, vb - va))
        self.pts, self.nrm, self.L = pts, nrm, L
        self.half = L[-1]
        self.total = 2 * self.half

    def at(self, t):
        """長さ t の点 (x, v) と外向きの法線 (nx, nv)。"""
        side = 1
        if t > self.half:
            t = self.total - t
            side = -1
        t = min(max(t, 0.0), self.half)
        lo, hi = 0, len(self.L) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if self.L[mid] <= t:
                lo = mid
            else:
                hi = mid
        f = (t - self.L[lo]) / max(1e-9, self.L[hi] - self.L[lo])
        (xa, va), (xb, vb) = self.pts[lo], self.pts[hi]
        (na, ma), (nb, mb) = self.nrm[lo], self.nrm[hi]
        x, v = lerp(xa, xb, f), lerp(va, vb, f)
        nx, nv = lerp(na, nb, f), lerp(ma, mb, f)
        ln = math.hypot(nx, nv)
        return (side * x, v), (side * nx / ln, nv / ln)

    def t_for_v(self, v, side=1):
        """右（side 1）／左（−1）の壁で、高さ v の t。"""
        best, bt = 9.9, 0.0
        for i, (x, vv) in enumerate(self.pts):
            if abs(vv - v) < best:
                best, bt = abs(vv - v), self.L[i]
        return bt if side > 0 else self.total - bt


_PROFILES: dict = {}


def profile(u):
    key = round(u, 3)
    if key not in _PROFILES:
        _PROFILES[key] = Profile(u)
    return _PROFILES[key]


def puff(s, t, v=9.0):
    row = (t / QUILT_ROW) % 1.0
    k = lerp(BACK_PUFF_SCALE, 1.0, min(1.0, max(0.0, (v - 3.40) / 0.25)))
    return BLANKET_BASE + k * BLANKET_PUFF * (math.sin(math.pi * s) ** 0.7) * (math.sin(math.pi * row) ** 0.6)


def blanket_point(u, s, t, lift=0.0):
    """断熱材の面の点（Godot）と内向きの法線。s はその間（骨組みと骨組み）の中の割合。"""
    (x, v), (nx, nv) = profile(u).at(t)
    d = puff(s, t, v) + lift
    return W(u, v - nv * d, x - nx * d), Vector((-nx, -nv, 0.0))


def strip_box(g, u0, u1, x0, x1, v0, v1, mat, uv_scale=None):
    """u・x・v の範囲の箱。uv_scale を渡すと上の面に UV（m × uv_scale）を付ける。"""
    if uv_scale is None:
        g.box(((x0 + x1) / 2, (v0 + v1) / 2, (u0 + u1) / 2 - S.U0), (abs(x1 - x0), abs(v1 - v0), abs(u1 - u0)), mat)
        return
    z0, z1 = u0 - S.U0, u1 - S.U0
    k = uv_scale
    g.oriented([(x0, v1, z0), (x1, v1, z0), (x1, v1, z1), (x0, v1, z1)], (0, 1, 0), mat,
               uv=[(x0 * k, z0 * k), (x1 * k, z0 * k), (x1 * k, z1 * k), (x0 * k, z1 * k)])
    g.box(((x0 + x1) / 2, (v0 + v1) / 2, (u0 + u1) / 2 - S.U0), (abs(x1 - x0), abs(v1 - v0), abs(u1 - u0)), mat, faces=("-x", "+x", "-y", "-z", "+z"))


def decal_quad(g, name, corner_fn, mat="FP_InteriorDecal", nu=4, nv=2):
    """アトラスの name の文字を、corner_fn(a, b)（a, b は 0〜1）が返す点の面に貼る（曲がった面にそう格子）。"""
    reg = _DEC["regions"].get(name)
    if reg is None:
        return
    u0, v0, u1, v1 = reg
    for i in range(nu):
        for j in range(nv):
            a0, a1 = i / nu, (i + 1) / nu
            b0, b1 = j / nv, (j + 1) / nv
            pts = [corner_fn(a0, b0), corner_fn(a1, b0), corner_fn(a1, b1), corner_fn(a0, b1)]
            uv = [(lerp(u0, u1, a0), lerp(v0, v1, b0)), (lerp(u0, u1, a1), lerp(v0, v1, b0)), (lerp(u0, u1, a1), lerp(v0, v1, b1)),
                  (lerp(u0, u1, a0), lerp(v0, v1, b1))]
            g.oriented([tuple(p[0]) for p in pts], tuple(pts[0][1]), mat, uv=uv)


def decal_size(name):
    return _DEC["items"].get(name, [0.3, 0.1])


# ---------------------------------------------------------------- 壁と天井：断熱材と骨組み

def in_window(u, x, v):
    for wu in C.PORTHOLES_U:
        if abs(u - wu) < 0.30 and abs(v - C.WINDOW_V) < 0.34:
            return True
    return False


def in_door(u, x, v):
    return x < 0 and DOOR_U[0] - 0.03 < u < DOOR_U[1] + 0.03 and v < DOOR_TOP_V + 0.06


def build_blankets(g: GMesh):
    for ua, ub in bay_list():
        a, b = ua + RIB_WIDTH / 2, ub - RIB_WIDTH / 2
        if ua < C.STEPS_U[0] + 0.05:
            a = ua + 0.005          # 前の壁の側には骨組みがない
        if ub > PORTAL_U[0] - 0.05:
            b = ub - 0.005          # 後ろの開口の枠の側も
        ns = 6
        prof = profile(0.5 * (a + b))
        nt = int(round(prof.total / 0.10))
        ts = [prof.total * j / nt for j in range(nt + 1)]
        grid = []
        for i in range(ns + 1):
            s = i / ns
            u = lerp(a, b, s)
            col = []
            for t in ts:
                p, _ = blanket_point(u, s, t)
                col.append(g.vert(tuple(p)))
            grid.append(col)
        for i in range(ns):
            for j in range(nt):
                um = lerp(a, b, (i + 0.5) / ns)
                (xm, vm), (nx, nv) = prof.at(0.5 * (ts[j] + ts[j + 1]))
                if in_window(um, xm, vm) or in_door(um, xm, vm):
                    continue
                quad = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                uv = [(i / ns, ts[j] / QUILT_ROW), ((i + 1) / ns, ts[j] / QUILT_ROW), ((i + 1) / ns, ts[j + 1] / QUILT_ROW),
                      (i / ns, ts[j + 1] / QUILT_ROW)]
                g.face_idx(quad, "FP_InteriorBlanket", smooth=True, hint=(-nx, -nv, 0.0), uv=uv)


def rib(g: GMesh, u, v_right, v_left, depth=RIB_DEPTH, width=RIB_WIDTH, mat="FP_InteriorFrame"):
    """内張りにそった骨組み（四角い断面）。右は v_right から、左は v_left から上（左右の高さを変えて扉の上で切る）。"""
    prof = profile(u)
    t0 = prof.t_for_v(v_right, 1)
    t1 = prof.t_for_v(v_left, -1)
    n = max(8, int((t1 - t0) / 0.10))
    z0, z1 = u - width / 2 - S.U0, u + width / 2 - S.U0
    prev = None
    for i in range(n + 1):
        t = lerp(t0, t1, i / n)
        (x, v), (nx, nv) = prof.at(t)
        a = (x + 0.01 * nx, v + 0.01 * nv)
        b = (x - depth * nx, v - depth * nv)
        if prev is not None:
            (pa, pb, pn) = prev
            g.oriented([(pb[0], pb[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (pb[0], pb[1], z1)], (-nx, -nv, 0), mat)
            g.oriented([(pa[0], pa[1], z0), (a[0], a[1], z0), (b[0], b[1], z0), (pb[0], pb[1], z0)], (0, 0, -1), mat)
            g.oriented([(pa[0], pa[1], z1), (a[0], a[1], z1), (b[0], b[1], z1), (pb[0], pb[1], z1)], (0, 0, 1), mat)
        prev = (a, b, (nx, nv))
    # 端のふた
    for t in (t0, t1):
        (x, v), (nx, nv) = prof.at(t)
        a = (x + 0.01 * nx, v + 0.01 * nv)
        b = (x - depth * nx, v - depth * nv)
        tang = (-nv, nx) if t == t0 else (nv, -nx)
        g.oriented([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], (tang[0], tang[1], 0), mat)


def build_frames(g: GMesh):
    for u in FRAME_US:
        v_left = DOOR_TOP_V + 0.10 if DOOR_U[0] < u < DOOR_U[1] else WALL_V0
        rib(g, u, WALL_V0, v_left)


# ---------------------------------------------------------------- 天井：ダクト・静索・灯・手すり

def build_ceiling(g: GMesh):
    u0, u1 = C.STEPS_U[0] + 0.06, PORTAL_U[0] - 0.02
    for side in (-1, 1):
        x = side * DUCT_X
        # ダクト（継ぎ目ごとに少し太い帯）
        g.tube(tuple(W(u0, DUCT_V, x)), tuple(W(u1, DUCT_V, x)), DUCT_R, "FP_InteriorDuct", n=16)
        for u in FRAME_US:
            g.tube(tuple(W(u - 0.02, DUCT_V, x)), tuple(W(u + 0.02, DUCT_V, x)), DUCT_R + 0.006, "FP_InteriorMetal", n=16)
            # 留め金の腕（骨組みへ）
            xw = side * (wall_x(u, DUCT_V + 0.05) - RIB_DEPTH + 0.01)
            g.box_between(tuple(W(u, DUCT_V + 0.05, x + side * (DUCT_R - 0.01))), tuple(W(u, DUCT_V + 0.05, xw)), 0.03, 0.05, "FP_InteriorMetal", up=(0, 0, 1))
        # 吹き出し口（下向き）
        for u in bay_centers()[1::2]:
            g.lathe(tuple(W(u, DUCT_V - DUCT_R + 0.02, x - side * 0.03)), (0, -1, 0), [(0.0, 0.055), (0.06, 0.05), (0.07, 0.04)], "FP_InteriorDark", n=10,
                    cap1="flat")
        # 静索（降下のときのフックを掛ける鋼の索）と吊り金具
        xs = side * STATIC_X
        g.tube(tuple(W(3.55, STATIC_V, xs)), tuple(W(10.85, STATIC_V, xs)), 0.009, "FP_InteriorMetal", n=6, smooth=False)
        for u in FRAME_US[1:]:
            top = roof_v(u, STATIC_X) - RIB_DEPTH + 0.01
            g.box(tuple(W(u, 0.5 * (top + STATIC_V + 0.02), xs)), (0.025, top - STATIC_V, 0.05), "FP_InteriorMetal")
        for u in (3.55, 10.85):
            g.box(tuple(W(u, STATIC_V, xs)), (0.06, 0.06, 0.10), "FP_InteriorDark")
        # 手すり（設計の黄色い棒 2 本。高さは床から 2.85）
        xr = side * C.RAIL_X
        g.tube(tuple(W(C.RAIL_U[0], C.RAIL_V, xr)), tuple(W(C.RAIL_U[1] - 0.2, C.RAIL_V, xr)), 0.024, "FP_InteriorYellow", n=10)
        for u in (4.42, 5.82, 7.18, 8.70, 10.22):
            top = roof_v(u, C.RAIL_X) - 0.04
            g.tube(tuple(W(u, C.RAIL_V, xr)), tuple(W(u, top, xr)), 0.016, "FP_InteriorYellow", n=8)
        # ダウンライト（丸い器具。間の真ん中ごと）
        for u in bay_centers():
            add_downlight(g, u, side * LIGHT_X)
    # 前と後ろの黄色い非常灯
    for u, x, v in ((C.STEPS_U[0] + 0.08, 1.30, 4.70), (C.STEPS_U[0] + 0.08, -1.30, 4.70), (PORTAL_U[0] - 0.05, 1.20, 4.95),
                    (PORTAL_U[0] - 0.05, -1.20, 4.95), (DOOR_U[0] + 0.45, -1.80, DOOR_TOP_V + 0.20)):
        add_amber(g, u, x, v)


def add_downlight(g: GMesh, u, x):
    s = S.inner_section(u)
    top = roof_v(u, x)
    v_face = top - BLANKET_BASE - 0.045
    # 天井の面の向き（少し真ん中へ傾く）
    th = math.acos(min(1.0, (abs(x) / s["a"]) ** (s["nt"] / 2)))
    nx, nv = S.normal(s, th)
    down = Vector((-math.copysign(nx, x), -nv, 0.0)).normalized()
    c = W(u, v_face, x)
    g.lathe(tuple(c - down * 0.05), tuple(down), [(0.0, 0.115), (0.035, 0.115), (0.05, 0.10)], "FP_InteriorTrim", n=16, cap0="flat")
    g.lathe(tuple(c + down * 0.0), tuple(down), [(0.0, 0.098), (0.008, 0.09)], "FP_InteriorMetal", n=16)
    g.lathe(tuple(c + down * 0.002), tuple(down), [(0.0, 0.085), (0.004, 0.0)], "FP_InteriorLamp", n=16)
    LIGHTS.append({"kind": "downlight", "position": [round(c.x, 4), round(c.y, 4), round(c.z, 4)],
                   "direction": [round(down.x, 4), round(down.y, 4), round(down.z, 4)]})


def add_amber(g: GMesh, u, x, v):
    side = 1 if x > 0 else -1
    xw = side * (wall_x(u, v) - BLANKET_BASE - 0.04)
    g.box(tuple(W(u, v, xw)), (0.06, 0.07, 0.16), "FP_InteriorDark")
    g.box(tuple(W(u, v - 0.01, xw - side * 0.032)), (0.012, 0.04, 0.12), "FP_InteriorLampAmber")
    p = W(u, v - 0.01, xw - side * 0.06)
    LIGHTS.append({"kind": "amber", "position": [round(p.x, 4), round(p.y, 4), round(p.z, 4)], "direction": [-side, -0.3, 0.0]})


# ---------------------------------------------------------------- 壁の上：配管・電線・箱・ステンシル

def build_wall_gear(g: GMesh):
    mats = ["FP_InteriorMetal", "FP_InteriorDark", "FP_InteriorOxygen", "FP_InteriorDark", "FP_InteriorMetal"]
    radii = [0.012, 0.022, 0.012, 0.030, 0.016]
    u0, u1 = C.STEPS_U[0] + 0.06, PORTAL_U[0] - 0.03
    for side in (-1, 1):
        for v, r, m in zip(LINES_V, radii, mats):
            x = side * (wall_x(7.0, v) - RIB_DEPTH - r - 0.005)
            g.tube(tuple(W(u0, v, x)), tuple(W(u1, v, x)), r, m, n=8)
        # P 形の留め金（骨組みごと）
        for u in FRAME_US:
            x = side * (wall_x(u, 4.76) - RIB_DEPTH - 0.02)
            strip_box(g, u - 0.022, u + 0.022, x - 0.025, x + 0.025, LINES_V[0] - 0.03, LINES_V[-1] + 0.04, "FP_InteriorMetal")
        # インターホンの箱（黒）と巻いたコード
        for u in (4.70, 8.36):
            x = side * (wall_x(u, 3.75) - BLANKET_BASE - BLANKET_PUFF - 0.04)
            strip_box(g, u - 0.09, u + 0.09, x - 0.045, x + 0.045, 3.60, 3.86, "FP_InteriorDark")
            strip_box(g, u - 0.07, u + 0.07, x - side * 0.046, x - side * 0.050, 3.64, 3.82, "FP_InteriorFrame")
            for k, (du, dv) in enumerate(((-0.035, 0.05), (0.035, 0.05), (0.0, -0.04))):
                g.lathe(tuple(W(u + du, 3.73 + dv, x - side * 0.050)), (-side, 0, 0), [(0.0, 0.016), (0.022, 0.014)], "FP_InteriorKnob" if k == 2 else "FP_InteriorDark",
                        n=8, cap1="flat")
            coil = []
            for k in range(28):
                a = k * 0.9
                coil.append(W(u + 0.06 + 0.025 * math.cos(a), 3.60 - k * 0.012, x - side * 0.03 + 0.025 * math.sin(a)))
            g.polyline_tube([tuple(p) for p in coil], 0.006, "FP_InteriorDark", n=4)
        # 位置番号のステンシル（間ごと）
        for bi, (ua, ub) in enumerate(bay_list()[1:]):
            um = 0.5 * (ua + ub)
            num = 470 + 30 * bi                 # 前から後ろへ増える（実機の位置番号のように）
            name = f"ls{num}"
            w_, h_ = decal_size(name)
            prof = profile(um)
            t_c = prof.t_for_v(LS_V, side)

            def corner(aa, bb, um=um, ua=ua, ub=ub, t_c=t_c, w_=w_, h_=h_, side=side):
                # 右の壁は読む向きが +u・上が +t、左の壁は −u・−t（t は右の床から天井を越えて左へ測る）
                uu = um + (aa - 0.5) * w_ * side
                tt = t_c + (bb - 0.5) * h_ * side
                p, n = blanket_point(uu, (uu - ua) / (ub - ua), tt, lift=0.008)
                return p, n
            decal_quad(g, name, corner)
    # 扉の上の「EMERGENCY EXIT」
    w_, h_ = decal_size("exit")
    xw = -(wall_x(3.84, DOOR_TOP_V + 0.20) - BLANKET_BASE - 0.065)
    decal_quad(g, "exit", lambda a, b: (W(3.84 - (a - 0.5) * w_, DOOR_TOP_V + 0.14 + b * h_, xw), Vector((1, 0, 0))), nu=1, nv=1)


def build_equipment(g: GMesh):
    """消火器・救急箱・酸素の盤・懐中電灯・座席の下の袋。"""
    # 消火器（前の壁の左と、後ろの右）
    for u, x in ((C.STEPS_U[0] + 0.12, -1.22), (PORTAL_U[0] - 0.22, 1.66)):
        c = W(u, FLOOR_V + 0.12, x)
        g.lathe(tuple(c), (0, 1, 0), [(0.0, 0.075), (0.42, 0.075), (0.48, 0.06), (0.52, 0.025), (0.60, 0.022)], "FP_InteriorRed", n=12, cap0="flat",
                cap1="flat", crease_deg=60)
        g.box(tuple(c + Vector((0, 0.62, 0))), (0.10, 0.03, 0.04), "FP_InteriorDark")
        g.box(tuple(c + Vector((0, 0.25, 0))), (0.17, 0.035, 0.17), "FP_InteriorMetal")
        g.box(tuple(c + Vector((0, 0.05, 0))), (0.17, 0.035, 0.17), "FP_InteriorMetal")
        w_, h_ = decal_size("fire")
        if x > 0:
            xw = wall_x(u, 2.85) - BLANKET_BASE - BLANKET_PUFF - 0.012
            decal_quad(g, "fire", lambda a, b, u=u, xw=xw: (W(u + (a - 0.5) * w_, 2.80 + b * h_, xw), Vector((-1, 0, 0))), nu=1, nv=1)
        else:
            zf = C.STEPS_U[0] - 0.005 + 0.012 - S.U0       # 前の壁の後ろ向きの面（読む向きは +x）
            decal_quad(g, "fire", lambda a, b, x=x: (Vector((x + (a - 0.5) * w_, 2.80 + b * h_, zf)), Vector((0, 0, 1))), nu=1, nv=1)
    # 救急箱（前の壁の右）
    zf = C.STEPS_U[0] - 0.005 - S.U0
    g.box((1.25, 3.30, zf + 0.07), (0.38, 0.26, 0.14), "FP_InteriorOlive")
    w_, h_ = decal_size("firstaid")
    decal_quad(g, "firstaid", lambda a, b: (Vector((1.25 + (a - 0.5) * 0.34, 3.30 - 0.04 + b * 0.075, zf + 0.142)), Vector((0, 0, 1))), nu=1, nv=1)
    # 酸素の盤（前の壁の右の下）
    g.box((1.25, 2.62, zf + 0.04), (0.30, 0.34, 0.08), "FP_InteriorFrame")
    g.lathe((1.25, 2.68, zf + 0.081), (0, 0, 1), [(0.0, 0.05), (0.01, 0.05)], "FP_InteriorGauge", n=12, cap1="flat")
    decal_quad(g, "oxygen", lambda a, b: (Vector((1.25 + (a - 0.5) * 0.20, 2.50 + b * 0.06, zf + 0.081)), Vector((0, 0, 1))), nu=1, nv=1)
    # 懐中電灯（扉の前）
    g.tube(tuple(W(DOOR_U[1] + 0.12, 3.10, -1.88)), tuple(W(DOOR_U[1] + 0.12, 3.36, -1.88)), 0.025, "FP_InteriorDark", n=8)
    # 座席の下の袋（オリーブ）
    for side in (-1, 1):
        for u in (5.15, 6.95, 8.55, 9.95) if side > 0 else (4.85, 6.40, 8.20, 10.05):
            x = side * 1.72
            strip_box(g, u - 0.20, u + 0.20, x - 0.14, x + 0.14, FLOOR_V + 0.004, FLOOR_V + 0.26, "FP_InteriorOlive")
            strip_box(g, u - 0.18, u + 0.18, x - 0.145, x + 0.145, FLOOR_V + 0.20, FLOOR_V + 0.225, "FP_InteriorDark")


# ---------------------------------------------------------------- 丸窓のまわりと乗員の扉

def build_window_trim(g: GMesh):
    """丸窓の内側の板（白い太い縁）。外の四角は断熱材の穴を隠す。"""
    for side in (-1, 1):
        for wu in C.PORTHOLES_U:
            v = C.WINDOW_V
            x = side * (wall_x(wu, v) - 0.035)
            n = 24
            ring_in, ring_out = [], []
            for k in range(n):
                a = 2 * math.pi * k / n
                ring_in.append((wu + (C.WINDOW_R + 0.005) * math.cos(a), v + (C.WINDOW_R + 0.005) * math.sin(a)))
                # 角を丸めた四角（0.78 × 0.86）
                c, s_ = math.cos(a), math.sin(a)
                ex = 0.36 * math.copysign(abs(c) ** 0.45, c)
                ey = 0.40 * math.copysign(abs(s_) ** 0.45, s_)
                ring_out.append((wu + ex, v + ey))
            d_in, d_out = 0.075, 0.050        # 縁の内と外の、内張りから手前への出（断熱材のふくらみより手前）
            for k in range(n):
                j = (k + 1) % n
                (ua, va), (ub, vb) = ring_in[k], ring_in[j]
                (uc, vc), (ud, vd) = ring_out[j], ring_out[k]
                g.oriented([tuple(W(ua, va, x - side * d_in)), tuple(W(ub, vb, x - side * d_in)), tuple(W(uc, vc, x - side * d_out)),
                            tuple(W(ud, vd, x - side * d_out))], (-side, 0, 0), "FP_InteriorTrim", smooth=True)
                # 内の筒（窓の奥へ）
                g.oriented([tuple(W(ua, va, x - side * d_in)), tuple(W(ub, vb, x - side * d_in)), tuple(W(ub, vb, x + side * 0.12)),
                            tuple(W(ua, va, x + side * 0.12))], (0.0, v - 0.5 * (va + vb), wu - 0.5 * (ua + ub)), "FP_InteriorTrim", smooth=True)
                # 外の縁（壁へ）
                g.oriented([tuple(W(ud, vd, x - side * d_out)), tuple(W(uc, vc, x - side * d_out)), tuple(W(uc, vc, x + side * 0.05)),
                            tuple(W(ud, vd, x + side * 0.05))], tuple(Vector((0.0, 0.5 * (vc + vd) - v, 0.5 * (uc + ud) - wu))), "FP_InteriorTrim")


def build_crew_door(g: GMesh):
    """乗員の扉（左の壁の前）：太い枠・灰色の扉の板（横の補強）・取っ手・小さな窓。"""
    u0, u1 = DOOR_U
    v0, v1 = FLOOR_V + 0.02, DOOR_TOP_V
    def wx(u, v):
        return -(wall_x(u, v) - 0.025)
    us = [lerp(u0, u1, i / 8) for i in range(9)]
    vs = [lerp(v0, v1, j / 10) for j in range(11)]
    wu, wv, wr = DOOR_WINDOW
    for i in range(8):
        for j in range(10):
            um, vm = 0.5 * (us[i] + us[i + 1]), 0.5 * (vs[j] + vs[j + 1])
            if math.hypot(um - wu, vm - wv) < wr + 0.03:
                continue
            q = [W(us[i], vs[j], wx(us[i], vs[j])), W(us[i + 1], vs[j], wx(us[i + 1], vs[j])), W(us[i + 1], vs[j + 1], wx(us[i + 1], vs[j + 1])),
                 W(us[i], vs[j + 1], wx(us[i], vs[j + 1]))]
            g.oriented([tuple(p) for p in q], (1, 0, 0), "FP_InteriorDoor", smooth=True)
    # 補強の横棒と枠
    for vv in (2.45, 3.05, 3.95):
        g.box_between(tuple(W(u0 + 0.06, vv, wx(u0, vv) + 0.03)), tuple(W(u1 - 0.06, vv, wx(u1, vv) + 0.03)), 0.06, 0.05, "FP_InteriorDoor", up=(1, 0, 0))
    for u in (u0 - 0.04, u1 + 0.04):
        g.box_between(tuple(W(u, v0, wx(u, v0) + 0.05)), tuple(W(u, v1 + 0.06, wx(u, v1) + 0.05)), 0.08, 0.10, "FP_InteriorFrame", up=(1, 0, 0))
    g.box_between(tuple(W(u0 - 0.08, v1 + 0.05, wx(u0, v1) + 0.05)), tuple(W(u1 + 0.08, v1 + 0.05, wx(u1, v1) + 0.05)), 0.10, 0.10, "FP_InteriorFrame",
                  up=(1, 0, 0))
    # 取っ手（レバー）と黄色の帯
    hx = wx(u1 - 0.12, 2.95) + 0.06
    g.box_between(tuple(W(u1 - 0.12, 2.80, hx)), tuple(W(u1 - 0.12, 3.12, hx)), 0.04, 0.04, "FP_InteriorYellow", up=(1, 0, 0))
    g.box(tuple(W(u1 - 0.12, 2.80, hx - 0.03)), (0.05, 0.08, 0.08), "FP_InteriorDark")
    w_, h_ = decal_size("door")
    decal_quad(g, "door", lambda a, b: (W(u1 - 0.12 - (a - 0.5) * w_, 2.62 + b * h_, wx(u1 - 0.12, 2.65) + 0.012), Vector((1, 0, 0))), nu=1, nv=1)
    # 窓の縁
    n = 16
    for k in range(n):
        a, b = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        p = [W(wu + wr * math.cos(a), wv + wr * math.sin(a), wx(wu, wv)), W(wu + wr * math.cos(b), wv + wr * math.sin(b), wx(wu, wv)),
             W(wu + (wr + 0.05) * math.cos(b), wv + (wr + 0.05) * math.sin(b), wx(wu, wv) + 0.03),
             W(wu + (wr + 0.05) * math.cos(a), wv + (wr + 0.05) * math.sin(a), wx(wu, wv) + 0.03)]
        g.oriented([tuple(q) for q in p], (1, 0, 0), "FP_InteriorTrim", smooth=True)


# ---------------------------------------------------------------- 床

def build_floor(g: GMesh):
    ua, ub = C.STEPS_U[0], PORTAL_U[1]
    fx = wall_x(7.0, FLOOR_V) + 0.01
    nu = int(round((ub - ua) / 0.5))
    nx = 7
    us = [lerp(ua, ub, i / nu) for i in range(nu + 1)]
    xs = [lerp(-fx, fx, j / nx) for j in range(nx + 1)]
    idx = [[g.vert(tuple(W(u, FLOOR_V, x))) for x in xs] for u in us]
    for i in range(nu):
        for j in range(nx):
            q = [idx[i][j], idx[i][j + 1], idx[i + 1][j + 1], idx[i + 1][j]]
            uv = [(xs[j], us[i] - S.U0), (xs[j + 1], us[i] - S.U0), (xs[j + 1], us[i + 1] - S.U0), (xs[j], us[i + 1] - S.U0)]
            g.face_idx(q, "FP_InteriorFloor", hint=(0, 1, 0), uv=uv)
    g.box((0, FLOOR_V - 0.07, 0.5 * (ua + ub) - S.U0), (2 * fx, 0.12, ub - ua), "FP_InteriorFloor", faces=("-x", "+x", "-y", "-z", "+z"))
    # 壁ぎわの縁の金具
    for side in (-1, 1):
        strip_box(g, ua + 0.75, ub, side * (fx - 0.06), side * (fx + 0.02), FLOOR_V, FLOOR_V + 0.035, "FP_InteriorMetal")
    # ローラーの列（4 本）
    for xc in (-ROLLER_X[1], -ROLLER_X[0], ROLLER_X[0], ROLLER_X[1]):
        for dx in (-0.06, 0.06):
            strip_box(g, C.STEPS_U[1] + 0.03, ub - 0.01, xc + dx - 0.006, xc + dx + 0.006, FLOOR_V, FLOOR_V + 0.055, "FP_InteriorMetal")
        strip_box(g, C.STEPS_U[1] + 0.03, ub - 0.01, xc - 0.055, xc + 0.055, FLOOR_V, FLOOR_V + 0.006, "FP_InteriorDark")
        u = C.STEPS_U[1] + 0.12
        while u < ub - 0.08:
            g.tube(tuple(W(u, FLOOR_V + 0.032, xc - 0.052)), tuple(W(u, FLOOR_V + 0.032, xc + 0.052)), 0.025, "FP_InteriorMetal", n=8)
            u += 0.254
    # 黄色い線
    for side in (-1, 1):
        strip_box(g, C.STEPS_U[1] + 0.03, ub - 0.22, side * YELLOW_X - 0.025, side * YELLOW_X + 0.025, FLOOR_V, FLOOR_V + 0.003, "FP_InteriorYellow")
    # つなぎ止めの輪（くぼみ＋寝かせた輪）
    for x in (-RING_X[1], RING_X[0], RING_X[1]):
        u = C.STEPS_U[1] + 0.12
        while u < ub - 0.25:
            c = W(u, FLOOR_V + 0.0015, x)
            g.lathe(tuple(c), (0, 1, 0), [(0.0, 0.05), (0.001, 0.05)], "FP_InteriorDark", n=10, cap1="flat")
            ring = [tuple(c + Vector((0.034 * math.cos(2 * math.pi * k / 8), 0.008, 0.034 * math.sin(2 * math.pi * k / 8)))) for k in range(8)]
            g.polyline_tube(ring, 0.0075, "FP_InteriorMetal", n=4, closed=True)
            u += RING_PITCH


# ---------------------------------------------------------------- 座席

def build_bench(g: GMesh, side):
    """実機の兵員座席：赤い布の座面（席ごと、前の管と壁の管の間にたるむ）、上の管から吊るベルトの背もたれ、アルミの脚と横棒。"""
    u0, u1 = BENCH_U
    xf = side * (BENCH_INNER_X + 0.012)
    xr = side * BENCH_REAR_X
    vr = SEAT_V - 0.022
    xb = side * BENCH_BACK_X
    g.tube(tuple(W(u0, vr, xf)), tuple(W(u1, vr, xf)), 0.022, "FP_InteriorMetal", n=10)
    g.tube(tuple(W(u0, vr, xr)), tuple(W(u1, vr, xr)), 0.020, "FP_InteriorMetal", n=10)
    g.tube(tuple(W(u0, BACK_TOP_V, xb)), tuple(W(u1, BACK_TOP_V, xb)), 0.019, "FP_InteriorMetal", n=10)
    g.tube(tuple(W(u0 + 0.05, FLOOR_V + 0.16, side * (BENCH_INNER_X - 0.02))), tuple(W(u1 - 0.05, FLOOR_V + 0.16, side * (BENCH_INNER_X - 0.02))), 0.014,
           "FP_InteriorMetal", n=8)
    n_seat = int(round((u1 - u0) / SEAT_PITCH))
    for k in range(n_seat + 1):
        u = u0 + k * SEAT_PITCH
        # 脚・床の金具・壁の金具
        g.tube(tuple(W(u, vr, xf)), tuple(W(u, FLOOR_V + 0.02, side * (BENCH_INNER_X - 0.03))), 0.019, "FP_InteriorMetal", n=8)
        strip_box(g, u - 0.035, u + 0.035, side * (BENCH_INNER_X - 0.07), side * (BENCH_INNER_X + 0.01), FLOOR_V, FLOOR_V + 0.03, "FP_InteriorDark")
        g.tube(tuple(W(u, vr, xf)), tuple(W(u, vr, xr)), 0.016, "FP_InteriorMetal", n=6)
        if k % 2 == 0:
            strip_box(g, u - 0.03, u + 0.03, xr, side * (wall_x(u, vr) - 0.02), vr - 0.03, vr + 0.02, "FP_InteriorMetal")
            strip_box(g, u - 0.03, u + 0.03, xb, side * (wall_x(u, BACK_TOP_V) - 0.02), BACK_TOP_V - 0.025, BACK_TOP_V + 0.025, "FP_InteriorMetal")
    for k in range(n_seat):
        ua = u0 + k * SEAT_PITCH + 0.022
        ub = ua + SEAT_PITCH - 0.044
        build_seat_pan(g, side, ua, ub, xf, xr)
        build_seat_back(g, side, ua - 0.01, ub + 0.01, xb)
        center = 0.5 * (ua + ub)
        if abs(center - SIT_U) > 0.2:
            build_hanging_belt(g, side, center)


def build_seat_pan(g: GMesh, side, ua, ub, xf, xr):
    nu, nx = 4, 4
    pts = {}
    for i in range(nu + 1):
        for j in range(nx + 1):
            a, b = i / nu, j / nx
            u = lerp(ua, ub, a)
            x = lerp(xf, xr, b)
            sag = 0.035 * math.sin(math.pi * b) * (0.6 + 0.4 * math.sin(math.pi * a))
            for layer, dv in ((0, 0.0), (1, -0.006)):
                pts[(i, j, layer)] = g.vert(tuple(W(u, SEAT_TOP_V - sag + dv, x)))
    for i in range(nu):
        for j in range(nx):
            for layer, hint in ((0, (0, 1, 0)), (1, (0, -1, 0))):
                q = [pts[(i, j, layer)], pts[(i + 1, j, layer)], pts[(i + 1, j + 1, layer)], pts[(i, j + 1, layer)]]
                uv = [(i / nu * 2.3, j / nx * 2.0), ((i + 1) / nu * 2.3, j / nx * 2.0), ((i + 1) / nu * 2.3, (j + 1) / nx * 2.0), (i / nu * 2.3, (j + 1) / nx * 2.0)]
                g.face_idx(q, "FP_SeatFabric", smooth=True, hint=hint, uv=uv)
    # 縁（前と後ろで管に巻く。少し太い帯）
    for x in (xf, xr):
        g.box_between(tuple(W(ua, SEAT_TOP_V - 0.004, x)), tuple(W(ub, SEAT_TOP_V - 0.004, x)), 0.05, 0.016, "FP_SeatFabric")


def _strap(g, a, b, w, normal, mat="FP_SeatWebbing", uv_len=0.10):
    """a → b の平たい帯（幅 w、厚み 4 mm）。UV は長さ方向に uv_len ごと。"""
    a, b = Vector(a), Vector(b)
    d = b - a
    if d.length < 1e-6:
        return
    t = d.normalized()
    n = Vector(normal).normalized()
    side = t.cross(n).normalized() * (w / 2)
    n = side.cross(t).normalized()
    th = n * 0.002
    L = d.length / uv_len
    for sgn in (1, -1):
        q = [a - side + th * sgn, a + side + th * sgn, b + side + th * sgn, b - side + th * sgn]
        g.oriented([tuple(p) for p in q], tuple(n * sgn), mat, uv=[(0, 0), (1, 0), (1, L), (0, L)])
    for s_ in (-1, 1):
        q = [a + side * s_ - th, a + side * s_ + th, b + side * s_ + th, b + side * s_ - th]
        g.oriented([tuple(p) for p in q], tuple(side * s_), mat)


def build_seat_back(g: GMesh, side, ua, ub, xb):
    """背もたれ：幅の広い縦のベルト 6 本（すき間 2 cm ほど。上の管に巻いて下がる）と、それを編む横のベルト 3 本。
    2026-10-22：前は細いベルトの粗い格子（柵のように見えた）。実機の兵員座席のように密にした。"""
    v_top, v_bot = BACK_TOP_V - 0.02, SEAT_V + 0.08
    n_vert = 6
    w_vert = 0.052
    us = [lerp(ua + 0.035, ub - 0.035, i / (n_vert - 1)) for i in range(n_vert)]
    inward = Vector((-side, 0, 0))
    for i, u in enumerate(us):
        sag = 0.010 + 0.004 * (i % 2)
        a = W(u, v_top, xb - side * 0.004)
        m = W(u, 0.5 * (v_top + v_bot), xb - side * (0.004 + sag))
        b = W(u, v_bot, xb - side * 0.004)
        _strap(g, a, m, w_vert, inward)
        _strap(g, m, b, w_vert, inward)
        # 管に巻いた輪
        g.box(tuple(W(u, BACK_TOP_V, xb)), (0.04, 0.055, w_vert + 0.004), "FP_SeatWebbing")
    for k in range(3):
        v = lerp(v_bot + 0.10, v_top - 0.14, k / 2)
        _strap(g, W(ua, v, xb - side * 0.014), W(ub, v, xb - side * 0.014), 0.048, inward)


def build_hanging_belt(g: GMesh, side, u):
    """座っていない席の腰のベルト：壁の管から座面にのり、前の管から垂れる。片方はバックルつき。"""
    xr = side * (BENCH_REAR_X - 0.02)
    xf = side * (BENCH_INNER_X + 0.02)
    up = Vector((0, 1, 0))
    for du, hang in ((-0.10, 0.34), (0.10, 0.22)):
        p0 = W(u + du, SEAT_TOP_V + 0.004, xr)
        p1 = W(u + du * 1.1, SEAT_TOP_V + 0.012, xf + side * 0.06)
        p2 = W(u + du * 1.15, SEAT_TOP_V - 0.02, xf - side * 0.025)
        p3 = W(u + du * 1.2, SEAT_TOP_V - hang, xf - side * 0.035)
        _strap(g, p0, p1, 0.045, up, mat="FP_InteriorBelt")
        _strap(g, p1, p2, 0.045, Vector((-side, 1, 0)), mat="FP_InteriorBelt")
        _strap(g, p2, p3, 0.045, Vector((-side, 0, 0)), mat="FP_InteriorBelt")
        if du < 0:
            g.box(tuple(p3 + Vector((0, -0.03, 0))), (0.02, 0.07, 0.06), "FP_InteriorMetal")


def build_belt(side):
    """座った 2 人の腰のベルト（ふだんは隠し、座ったら出す。Godot の set_belt）。"""
    g = GMesh()
    z = SIT_U
    x_back = BENCH_REAR_X + 0.01
    pts = [(x_back, SEAT_V + 0.02, z - 0.26), (1.80, SEAT_V + 0.24, z - 0.23), (1.68, SEAT_V + 0.33, z - 0.13), (1.64, SEAT_V + 0.35, z),
           (1.68, SEAT_V + 0.33, z + 0.13), (1.80, SEAT_V + 0.24, z + 0.23), (x_back, SEAT_V + 0.02, z + 0.26)]
    pts = [W(u, v, side * x) for x, v, u in pts]
    for a, b in zip(pts[:-1], pts[1:]):
        _strap(g, a, b, 0.05, Vector((side, 0.6, 0)), mat="FP_InteriorBelt")
    c = pts[3]
    g.box(tuple(c + Vector((side * 0.012, 0.0, 0.0))), (0.03, 0.06, 0.09), "FP_InteriorMetal")
    return g


# ---------------------------------------------------------------- 段・前の壁・後ろの開口の枠

def build_steps(g: GMesh):
    hw = C.DECK_DOOR_HALF_W
    s0, s1 = C.STEPS_U
    d = (s1 - s0) / 3
    rise = (DECK_V - FLOOR_V) / 3
    for k, (ua, top) in enumerate(((s1 - d, FLOOR_V + rise), (s1 - 2 * d, FLOOR_V + 2 * rise), (s0, DECK_V))):
        strip_box(g, ua, ua + d, -hw, hw, FLOOR_V, top, "FP_InteriorTread", uv_scale=1 / 0.30)
    for k in range(3):
        u_edge = s1 - d * k
        top = FLOOR_V + rise * (k + 1)
        strip_box(g, u_edge - 0.05, u_edge, -hw + 0.02, hw - 0.02, top, top + 0.006, "FP_InteriorYellow")
    for side in (-1, 1):
        x = side * (hw + 0.06)
        g.polyline_tube([tuple(W(s1, FLOOR_V + 0.95, x)), tuple(W(s0 - 0.05, DECK_V + 0.95, x))], 0.022, "FP_InteriorYellow")
        g.tube(tuple(W(s1, FLOOR_V, x)), tuple(W(s1, FLOOR_V + 0.95, x)), 0.02, "FP_InteriorYellow", n=8)
    # 操縦席の床の前の面（u 3.2、貨物室の床から操縦席の床まで）
    u = s0 - 0.005
    s = S.inner_section(u)
    th0, th1 = S.theta_for_v(s, FLOOR_V - 0.05), S.theta_for_v(s, DECK_V)
    right = []
    for i in range(9):
        th = lerp(th0, th1, i / 8)
        x, v = S.point(s, th)
        right.append((x + 0.03, v))
    poly = right + [(-x, v) for x, v in reversed(right)]
    g.oriented([(x, v, u - S.U0) for x, v in poly], (0, 0, 1), "FP_InteriorWall")


def build_bulkhead(g: GMesh):
    """操縦席と貨物室の間の壁（u 3.2、操縦席の床より上）。断熱材の布で覆う。出入り口は幅 1.5 m、扉はなし。"""
    hw = C.DECK_DOOR_HALF_W
    door_top = DECK_V + 2.05
    r = 0.16
    u_front, u_back = C.STEPS_U[0] - 0.09, C.STEPS_U[0] - 0.005
    s = S.inner_section(u_back)
    th0 = S.theta_for_v(s, DECK_V)
    outline = []
    for i in range(24):
        th = lerp(th0, math.pi / 2, i / 23)
        x, v = S.point(s, th)
        nx, nv = S.normal(s, th)
        outline.append((x + 0.03 * nx, v + 0.03 * nv))
    arc = [(hw - r + r * math.cos(a), door_top - r + r * math.sin(a)) for a in [math.radians(t) for t in (0, 30, 60, 90)]]
    right = [(hw, DECK_V)] + outline + [(0.0, door_top)] + list(reversed(arc))
    for side in (-1, 1):
        poly = [(side * x, v) for x, v in right]
        for z, out, mat in ((u_back - S.U0, (0, 0, 1), "FP_InteriorBlanket"), (u_front - S.U0, (0, 0, -1), "FP_InteriorWall")):
            g.oriented([(x, v, z) for x, v in poly], out, mat, uv=[(x / QUILT_ROW, v / QUILT_ROW) for x, v in poly])
        edge = [(side * hw, DECK_V)] + [(side * x, v) for x, v in arc] + [(0.0, door_top)]
        for (xa, va), (xb, vb) in zip(edge[:-1], edge[1:]):
            hint = (-0.5 * (xa + xb), DECK_V + 1.0 - 0.5 * (va + vb), 0.0)
            g.oriented([(xa, va, u_front - S.U0), (xb, vb, u_front - S.U0), (xb, vb, u_back - S.U0), (xa, va, u_back - S.U0)], hint, "FP_InteriorFrame")
    # 縫い目の帯（前の壁の断熱材の継ぎ目）
    for xx in (-1.3, -0.95, 0.95, 1.3):
        g.box((xx, DECK_V + 1.25, u_back - S.U0 + 0.006), (0.04, 2.3, 0.01), "FP_InteriorFrame")


def opening_outline(n_corner=5):
    """後ろの開口（幅 3.10 × 高さ 3.30。上の角は丸い）の右半分：下の右 → 上の角 → 上の真ん中。"""
    hw = C.RAMP_HALF_W
    r = OPENING_CORNER_R
    pts = [(hw, FLOOR_V - 0.12)]
    for i in range(n_corner + 1):
        a = math.radians(90.0 * i / n_corner)
        pts.append((hw - r + r * math.cos(a), OPENING_TOP_V - r + r * math.sin(a)))
    pts.append((0.0, OPENING_TOP_V))
    return pts


def build_portal(g: GMesh):
    """後ろの開口の枠（スロープの付け根の前）：開口のまわりの壁を厚い枠でうめる。縁は黄色と黒の縞。"""
    u_front, u_back = PORTAL_U
    s = S.inner_section(u_back)
    th0 = S.theta_for_v(s, FLOOR_V)
    outline = []
    for i in range(30):
        th = lerp(th0, math.pi / 2, i / 29)
        x, v = S.point(s, th)
        nx, nv = S.normal(s, th)
        outline.append((x + 0.04 * nx, v + 0.04 * nv))
    inner = opening_outline()
    right = inner + list(reversed(outline))
    for side in (-1, 1):
        poly = [(side * x, v) for x, v in right]
        for z, out in ((u_back - S.U0, (0, 0, 1)), (u_front - S.U0, (0, 0, -1))):
            g.oriented([(x, v, z) for x, v in poly], out, "FP_InteriorFrame")
        edge = [(side * x, v) for x, v in inner]
        for (xa, va), (xb, vb) in zip(edge[:-1], edge[1:]):
            hint = (-0.5 * (xa + xb), 3.55 - 0.5 * (va + vb), 0.0)
            g.oriented([(xa, va, u_front - S.U0), (xb, vb, u_front - S.U0), (xb, vb, u_back - S.U0), (xa, va, u_back - S.U0)], hint, "FP_InteriorDark")
        x = side * (C.RAMP_HALF_W - 0.004)
        v = FLOOR_V
        k = 0
        while v < OPENING_TOP_V - OPENING_CORNER_R - 0.05:
            v1 = min(v + 0.22, OPENING_TOP_V - OPENING_CORNER_R)
            mat = "FP_HazardYellow" if k % 2 == 0 else "FP_HazardBlack"
            poly = [(x, v, u_front - S.U0 - 0.004), (x, v1, u_front - S.U0 - 0.004), (x, v1 + 0.08, u_back - S.U0), (x, v + 0.08, u_back - S.U0)]
            g.oriented(poly, (-side, 0, 0), mat)
            v = v1
            k += 1
        strip_box(g, u_front - 0.012, u_front, side * C.RAMP_HALF_W, side * (C.RAMP_HALF_W + 0.10), FLOOR_V, OPENING_TOP_V - 0.2, "FP_HazardYellow")
        # 作動筒の取り付け金具（枠の後ろの壁）
        a = ramp_actuator_anchor(side)
        g.box(tuple(a + Vector((side * 0.05, 0, 0))), (0.18, 0.22, 0.22), "FP_InteriorMetal")
    strip_box(g, u_front - 0.012, u_front, -C.RAMP_HALF_W + 0.2, C.RAMP_HALF_W - 0.2, OPENING_TOP_V, OPENING_TOP_V + 0.08, "FP_HazardYellow")
    xs = [-C.RAMP_HALF_W + i * (2 * C.RAMP_HALF_W) / 14 for i in range(15)]
    for i, (xa, xb) in enumerate(zip(xs[:-1], xs[1:])):
        strip_box(g, u_back - 0.20, u_back, xa, xb, FLOOR_V, FLOOR_V + 0.004, "FP_HazardYellow" if i % 2 == 0 else "FP_HazardBlack")
    strip_box(g, u_front - 0.07, u_front, -0.27, 0.27, C.JUMP_LIGHT_V - 0.11, C.JUMP_LIGHT_V + 0.11, "FP_InteriorDark")
    # 「RAMP - KEEP CLEAR」（枠の上の横の帯の下）
    w_, h_ = decal_size("ramp")
    z = u_front - S.U0 - 0.013
    decal_quad(g, "ramp", lambda a, b: (Vector((-(a - 0.5) * w_, OPENING_TOP_V + 0.10 + b * h_, z)), Vector((0, 0, -1))), nu=1, nv=1)


def jump_light_positions():
    z_u = PORTAL_U[0] - 0.07
    return {"JumpLight_Red": W(z_u, C.JUMP_LIGHT_V, 0.12), "JumpLight_Green": W(z_u, C.JUMP_LIGHT_V, -0.12)}


def build_jump_lamp(pos: Vector, mat):
    g = GMesh()
    g.lathe(tuple(pos), (0, 0, -1), [(0.0, 0.075), (0.02, 0.07), (0.045, 0.05), (0.06, 0.0)], mat, ref=(0, 1, 0), n=14, cap0="flat")
    return g


# ---------------------------------------------------------------- スロープの作動筒（Godot が向きを合わせる）

def ramp_actuator_anchor(side):
    """胴体の側の付け根 A（Godot）。"""
    return W(11.45, 3.35, side * 1.74)


def ramp_actuator_ramp_point(side, ramp_point):
    """スロープの側の付け根 B（閉じた位置、Godot）。"""
    return Vector(ramp_point(1.6, side * 1.63, 0.15))


CYL_LEN, CYL_R = 1.15, 0.075
ROD_LEN, ROD_R = 1.05, 0.035


def build_actuator_cyl():
    """胴体の側の筒（原点は A、ローカル −Z が B の向き）。"""
    g = GMesh()
    g.lathe((0, 0, 0), (0, 0, -1), [(-0.06, 0.0), (-0.06, 0.05), (0.0, 0.05), (0.0, CYL_R), (CYL_LEN, CYL_R), (CYL_LEN, CYL_R * 0.7)], "FP_InteriorDark",
            ref=(0, 1, 0), n=14, crease_deg=30)
    g.box((0, 0, 0.0), (0.10, 0.10, 0.08), "FP_InteriorMetal")
    return g


def build_actuator_rod():
    """スロープの側の棒（原点は B、ローカル −Z が A の向き）。"""
    g = GMesh()
    g.lathe((0, 0, 0), (0, 0, -1), [(0.0, 0.0), (0.0, ROD_R), (ROD_LEN, ROD_R), (ROD_LEN, 0.0)], "FP_Metal", ref=(0, 1, 0), n=12)
    g.box((0, 0, 0), (0.09, 0.09, 0.07), "FP_InteriorMetal")
    return g


# ---------------------------------------------------------------- スロープの上の部品（閉じた位置。原点は付け根）

def build_ramp_details(ramp_point):
    g = GMesh()
    L = C.RAMP_LEN
    up = Vector(ramp_point(0, 0, 1)) - Vector(ramp_point(0, 0, 0))
    for xc in (-ROLLER_X[1], -ROLLER_X[0], ROLLER_X[0], ROLLER_X[1]):
        quad = [ramp_point(0.05, xc - 0.055, 0.002), ramp_point(L - 0.3, xc - 0.055, 0.002), ramp_point(L - 0.3, xc + 0.055, 0.002),
                ramp_point(0.05, xc + 0.055, 0.002)]
        g.oriented(quad, tuple(up), "FP_InteriorDark")
        for dx in (-0.06, 0.06):
            a, b = Vector(ramp_point(0.05, xc + dx, 0.025)), Vector(ramp_point(L - 0.3, xc + dx, 0.025))
            g.box_between(tuple(a), tuple(b), 0.012, 0.05, "FP_InteriorMetal", up=tuple(up))
        s = 0.18
        while s < L - 0.35:
            g.tube(ramp_point(s, xc - 0.052, 0.032), ramp_point(s, xc + 0.052, 0.032), 0.025, "FP_InteriorMetal", n=8)
            s += 0.254
    for side in (-1, 1):
        a, b = Vector(ramp_point(0.0, side * 1.47, 0.03)), Vector(ramp_point(L, side * 1.47, 0.03))
        g.box_between(tuple(a), tuple(b), 0.08, 0.06, "FP_HazardYellow", up=tuple(up))
        # 作動筒の金具（スロープの横）
        bpt = ramp_actuator_ramp_point(side, ramp_point)
        g.box(tuple(bpt - Vector((side * 0.04, 0, 0))), (0.12, 0.16, 0.20), "FP_InteriorMetal")
    # つなぎ止めの輪
    for x in (-RING_X[1], RING_X[0], RING_X[1]):
        s = 0.35
        while s < L - 0.45:
            c = Vector(ramp_point(s, x, 0.0015))
            g.lathe(tuple(c), tuple(up), [(0.0, 0.05), (0.001, 0.05)], "FP_InteriorDark", n=10, cap1="flat")
            s += RING_PITCH
    # 先の縞（斜め）と端の面の縞
    s0, s1 = L - 0.30, L - 0.01
    w = 0.16
    x = -1.43
    k = 0
    while x < 1.43 - 1e-6:
        x1 = min(x + w, 1.43)
        g.oriented([ramp_point(s0, x, 0.003), ramp_point(s0, x1, 0.003), ramp_point(s1, x1, 0.003), ramp_point(s1, x, 0.003)], tuple(up),
                   "FP_HazardYellow" if k % 2 == 0 else "FP_HazardBlack")
        x = x1
        k += 1
    for xa, xb in ((-1.40, -1.00), (-0.25, 0.25), (1.00, 1.40)):
        g.tube(ramp_point(0.02, xa, -0.09), ramp_point(0.02, xb, -0.09), 0.075, "FP_InteriorMetal", n=10)
    # 「RAMP - KEEP CLEAR」
    w_, h_ = decal_size("ramp")
    decal_quad(g, "ramp", lambda a, b: (Vector(ramp_point(0.35 + b * h_, -(a - 0.5) * w_, 0.004)), up), nu=1, nv=1)
    return g


# ---------------------------------------------------------------- 貨物室をまとめる

def build_hold():
    LIGHTS.clear()
    g = GMesh()
    build_floor(g)
    build_blankets(g)
    build_frames(g)
    build_ceiling(g)
    build_wall_gear(g)
    build_equipment(g)
    build_window_trim(g)
    build_crew_door(g)
    for side in (-1, 1):
        build_bench(g, side)
    build_steps(g)
    build_bulkhead(g)
    build_portal(g)
    return g


# 操縦席は fp_cockpit.py（2026-10-22 に作り直した）。ハテナの座る位置・操縦かんの握り・計器盤の面の寸法は上の PILOT_*・YOKE_GRIP・DASH_* を使う。

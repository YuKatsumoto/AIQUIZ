"""水上機 C-130 の外の作り込み（2026-10-18、ユーザーの指示で「機体のクオリティーをもっと」）。

実機の C-130 の外の目印になる部品：背中と腹の板アンテナ、操縦室の上から垂直尾翼の前の縁へ張る HF のワイヤー（がいしつき）、
機首の横のピトー管、前の窓のワイパー、左の前の乗員の扉（輪郭・取っ手・小さな窓）、背中の非常口の輪郭、垂直尾翼の背びれ、
方向舵と昇降舵の継ぎ目、エンジンの覆いの下の吸気口（T56 のあご）、フロートの通路（滑り止め）・クリート・水かじ・竜骨の帯、
放電索、外板の文字（登録記号・部隊名・プロペラの危険・NO STEP・RESCUE）。
パネルの線とリベットは形ではなく法線のテクスチャ（textures/fp_paint_normal.png、Godot が三方向から貼る）。
"""
from __future__ import annotations

import math

from mathutils import Vector

import fp_section as S
import fp_parts as FP
import fp_interior as FI
from fp_common import GMesh, W, lerp

C = S.C
DOOR_U = FI.DOOR_U
DOOR_V = (C.FLOOR_V + 0.05, FI.DOOR_TOP_V)


# ---------------------------------------------------------------- 外板の上の点

def skin_point(u, v, side, lift=0.0):
    """胴体の外板の、高さ v・side の側の点（Godot）と外向きの法線。"""
    s = S.section(min(max(u, S.NOSE_DOME_U), S.DOOR_END_U))
    th = S.theta_for_v(s, min(max(v, s["bottom"] + 1e-3), s["top"] - 1e-3))
    x, vv = S.point(s, th)
    nx, nv = S.normal(s, th)
    return W(u, vv + nv * lift, side * (x + nx * lift)), Vector((side * nx, nv, 0.0))


def roof_point(u, x, lift=0.0):
    """胴体の上の面の、横 x の点と法線。"""
    s = S.section(min(max(u, S.NOSE_DOME_U), S.DOOR_END_U))
    th = math.acos(min(1.0, (abs(x) / s["a"]) ** (s["nt"] / 2)))
    px, pv = S.point(s, th)
    nx, nv = S.normal(s, th)
    sg = 1 if x >= 0 else -1
    return W(u, pv + nv * lift, sg * (px + nx * lift)), Vector((sg * nx, nv, 0.0))


def belly_point(u, x, lift=0.0):
    s = S.section(u)
    th = S.theta_for_x_lower(s, abs(x))
    px, pv = S.point(s, th)
    nx, nv = S.normal(s, th)
    sg = 1 if x >= 0 else -1
    return W(u, pv + nv * lift, sg * (px + nx * lift)), Vector((sg * nx, nv, 0.0))


def wing_top_point(x, c, lift=0.0):
    lo, up = FP.airfoil(c)
    return W(FP.WING_LE + c * FP.CHORD, up + lift, x), Vector((0, 1, 0))


def fin_lines():
    (u_le0, _), (u_le1, v_le1), (u_te1, v_te1), (u_te0, _) = C.FIN
    root_le = (u_le0, S.section(u_le0)["top"] - 0.06)
    root_te = (u_te0 - 0.02, S.section(min(u_te0, 18.0))["top"] - 0.05)
    return root_le, (u_le1, v_le1), root_te, (u_te1, v_te1)


def fin_point(s_, c, side, lift=0.0):
    """垂直尾翼の面の点：s は根元 0 〜 先 1、c は前の縁 0 〜 後ろの縁 1（fp_parts.build_fin と同じ式）。"""
    rle, tle, rte, tte = fin_lines()
    le = (lerp(rle[0], tle[0], s_), lerp(rle[1], tle[1], s_))
    te = (lerp(rte[0], tte[0], s_), lerp(rte[1], tte[1], s_))
    u, v = lerp(le[0], te[0], c), lerp(le[1], te[1], c)
    half_t = lerp(0.20, 0.11, s_)
    t = half_t * FP._thickness(c) + 0.006
    return W(u, v, side * (t + lift)), Vector((side, 0, 0))


def fin_sc(u, v):
    """垂直尾翼の上の (u, v) の (s, c)。"""
    rle, tle, rte, tte = fin_lines()
    s_ = 0.5
    for _ in range(30):
        le = (lerp(rle[0], tle[0], s_), lerp(rle[1], tle[1], s_))
        te = (lerp(rte[0], tte[0], s_), lerp(rte[1], tte[1], s_))
        c = (u - le[0]) / (te[0] - le[0])
        vv = lerp(le[1], te[1], c)
        s_ += (v - vv) / 3.9
        s_ = min(max(s_, 0.0), 1.0)
    return s_, c


def densify(pts, step=0.08):
    """2 次元の点の並び（u, v など）の長い辺を step 以下に刻む。曲がった外板へ写したとき、長い辺の帯が外板の中へ沈まない。"""
    out = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        n = max(1, int(math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]) / step)))
        for k in range(1, n + 1):
            out.append((lerp(a[0], b[0], k / n), lerp(a[1], b[1], k / n)))
    return out


def strip_on(g: GMesh, pts_normals, w, mat, lift=0.003):
    """面の上の点の並び（点, 法線）にそった細い帯（線の継ぎ目・輪郭）。"""
    for (a, na), (b, nb) in zip(pts_normals[:-1], pts_normals[1:]):
        a, b = Vector(a), Vector(b)
        d = b - a
        if d.length < 1e-6:
            continue
        n = (Vector(na) + Vector(nb)).normalized()
        side = d.normalized().cross(n) * (w / 2)
        q = [a - side + n * lift, b - side + n * lift, b + side + n * lift, a + side + n * lift]
        g.oriented([tuple(p) for p in q], tuple(n), mat)


def decal_on(g: GMesh, name, fn, nu=6, nv=2):
    """アトラスの文字を fn(a, b) → (点, 法線) の面に貼る（外板用、材質 FP_Decal）。"""
    FI.decal_quad(g, name, fn, mat="FP_Decal", nu=nu, nv=nv)


# ---------------------------------------------------------------- 部品

def blade_antenna(g: GMesh, base: Vector, normal: Vector, height=0.30, chord=0.28, mat="FP_Paint"):
    n = Vector(normal).normalized()
    fwd = Vector((0, 0, -1))
    side = n.cross(fwd).normalized() * 0.012
    pts = [base + fwd * (chord * 0.5), base - fwd * (chord * 0.5), base - fwd * (chord * 0.55) + n * height, base - fwd * (chord * 0.15) + n * height]
    g.prism([tuple(p - side) for p in pts], (0, 0, 0), tuple(side * 2), mat)


def build_antennas(g: GMesh):
    for u, mat in ((4.2, "FP_Paint"), (10.3, "FP_Dark"), (12.2, "FP_Paint")):
        p, n = roof_point(u, 0.0, lift=-0.02)
        blade_antenna(g, p, n, mat=mat)
    for u in (5.6, 8.9):
        p, n = belly_point(u, 0.0, lift=-0.02)
        blade_antenna(g, p, n, height=0.22, chord=0.24, mat="FP_Dark")
    # HF のワイヤー：操縦室の上の柱 → 垂直尾翼の前の縁
    mast_base, n = roof_point(3.3, 0.0, lift=-0.02)
    mast_top = mast_base + Vector((0, 0.24, 0.05))
    g.tube(tuple(mast_base), tuple(mast_top), 0.022, "FP_Paint", n=8)
    s_ = (14.6 - 12.6) / (C.FIN[1][0] - C.FIN[0][0])
    rle, tle, _, _ = fin_lines()
    fin_p = W(14.6, lerp(rle[1], tle[1], s_) + 0.0, 0.0)
    a, b = Vector(mast_top), Vector(fin_p)
    g.tube(tuple(a), tuple(b), 0.006, "FP_Dark", n=6, smooth=False)
    for t in (0.04, 0.96):
        c = a + (b - a) * t
        d = (b - a).normalized()
        g.tube(tuple(c - d * 0.06), tuple(c + d * 0.06), 0.018, "FP_Paint", n=8)


def build_pitots(g: GMesh):
    for side in (-1, 1):
        base, n = skin_point(1.05, 3.62, side, lift=-0.01)
        tip = base + n * 0.10
        g.tube(tuple(base), tuple(tip), 0.016, "FP_Metal", n=8)
        g.tube(tuple(tip), tuple(tip + Vector((0, 0, -0.26))), 0.011, "FP_Metal", n=8)


def build_wipers(g: GMesh):
    # 止めた姿：前の窓の下の縁にそって寝かせる（窓の向こうのハテナの顔を横切らない）
    v0 = FS.FRONT_V[0]
    for side in (-1, 1):
        a = front_point(side * 0.52, v0 + 0.045)
        a = a + _front_normal(side * 0.52, v0 + 0.045) * 0.012
        b = front_point(side * 0.12, v0 + 0.07)
        b = b + _front_normal(side * 0.12, v0 + 0.07) * 0.012
        g.tube(tuple(a), tuple(b), 0.009, "FP_Dark", n=6)
        g.box(tuple(a), (0.05, 0.03, 0.05), "FP_Dark")


def build_crew_door_outline(g: GMesh):
    """左の乗員の扉の輪郭（外板の継ぎ目）と取っ手。窓は胴体のくり抜き（door_window_cutter）。"""
    side = -1
    u0, u1 = DOOR_U
    v0, v1 = DOOR_V
    r = 0.08
    pts = []
    corners = [(u0 + r, v0 + r, 180), (u1 - r, v0 + r, 270), (u1 - r, v1 - r, 0), (u0 + r, v1 - r, 90)]
    for cu, cv, a0 in corners:
        for k in range(5):
            a = math.radians(a0 + 90 * k / 4)
            pts.append((cu + r * math.cos(a), cv + r * math.sin(a)))
    pts.append(pts[0])
    pn = [skin_point(u, v, side, 0.0) for u, v in densify(pts)]
    strip_on(g, pn, 0.016, "FP_Dark", lift=0.003)
    hp, hn = skin_point(u1 - 0.14, 2.90, side, 0.004)
    g.box(tuple(hp), (0.02, 0.06, 0.16), "FP_Dark")
    # 足かけ（扉の下）
    sp, sn = skin_point(0.5 * (u0 + u1), v0 - 0.10, side, -0.02)
    g.box(tuple(sp + sn * 0.07), (0.16, 0.025, 0.36), "FP_Metal")


def door_window_cutter():
    g = GMesh()
    wu, wv, wr = FI.DOOR_WINDOW
    g.lathe((-1.2, wv, wu - S.U0), (-1, 0, 0), [(0.0, wr), (1.6, wr)], "FP_InteriorTrim", n=16, smooth=False, cap0="flat", cap1="flat")
    return g


def door_window_glass():
    g = GMesh()
    wu, wv, wr = FI.DOOR_WINDOW
    xo = S.x_at_v(S.section(wu), wv)
    g.lathe((-(xo - 0.05), wv, wu - S.U0), (-1, 0, 0), [(0.0, wr + 0.01), (0.004, wr + 0.01)], "FP_Glass", n=16, cap0="flat", cap1="flat")
    return g


def build_hatches(g: GMesh):
    """背中の非常口（四角い輪郭）。"""
    for uc in (4.05, 10.6):
        pts = []
        hw, hl, r = 0.42, 0.40, 0.07
        corners = [(uc - hl + r, -hw + r, 180), (uc + hl - r, -hw + r, 270), (uc + hl - r, hw - r, 0), (uc - hl + r, hw - r, 90)]
        for cu, cx, a0 in corners:
            for k in range(4):
                a = math.radians(a0 + 90 * k / 3)
                pts.append((cu + r * math.cos(a), cx + r * math.sin(a)))
        pts.append(pts[0])
        strip_on(g, [roof_point(u, x, 0.0) for u, x in densify(pts)], 0.014, "FP_Dark", lift=0.003)


def build_dorsal(g: GMesh):
    """垂直尾翼の背びれ（前の縁の根元を胴体へなだらかにつなぐ）。"""
    rle, tle, _, _ = fin_lines()
    us = [10.9, 11.5, 12.1, 12.7, 13.3, 13.9]
    u_end = us[-1]
    s_end = (u_end - rle[0]) / (tle[0] - rle[0])
    v_end = lerp(rle[1], tle[1], s_end)
    rings = []
    for u in us:
        top = S.section(u)["top"]
        t = (u - us[0]) / (u_end - us[0])
        h = (v_end - top) * t ** 1.4
        w = lerp(0.10, 0.19, t)
        ring = []
        for k in range(12):
            a = math.pi * k / 11
            ring.append(tuple(W(u, top - 0.04 + (h + 0.04) * math.sin(a) ** 0.8, w * math.cos(a))))
        rings.append(ring)
    g.loft(rings, "FP_Navy", closed=False, smooth=True, cap1=False,
           hint_fn=lambda i, k, rings=rings: Vector(rings[i][k]) - Vector((0, S.section(us[i])["top"] - 0.3, rings[i][k][2])))


def build_hinge_lines(g: GMesh):
    for side in (-1, 1):
        pn = [fin_point(s_, 0.74, side, 0.0) for s_ in [i / 20 * 0.92 + 0.03 for i in range(21)]]
        strip_on(g, pn, 0.012, "FP_Dark", lift=0.002)
        # 方向舵の下の縁（横の継ぎ目）
        pn = [fin_point(0.08, c, side, 0.0) for c in [0.74 + 0.25 * i / 6 for i in range(7)]]
        strip_on(g, pn, 0.010, "FP_Dark", lift=0.002)
    st = C.STAB
    for side in (-1, 1):
        for sgn in (1, -1):
            pts = []
            for i in range(9):
                x = lerp(0.35, 4.35, i / 8)
                t = x / st["half_span"]
                u0 = lerp(st["u0"], st["u0"] + 0.55, t)
                u1 = lerp(st["u1"], st["u1"] - 0.25, t)
                c = 0.70
                half_t = lerp(0.12, 0.08, t)
                v = st["v"] + sgn * (half_t * FP._thickness(c) + 0.004)
                pts.append((W(lerp(u0, u1, c), v, side * x), Vector((0, sgn, 0))))
            strip_on(g, pts, 0.010, "FP_Dark", lift=0.002)


def _float_deck_strip(g: GMesh, xc, dx, u0, u1, w, mat, n=18, lift=0.004):
    pts = []
    for i in range(n):
        u = lerp(u0, u1, i / (n - 1))
        pts.append((W(u, FP.float_deck_v(u, dx), xc + dx), Vector((0, 1, 0))))
    strip_on(g, pts, w, mat, lift=lift)


def _cleat(g: GMesh, p: Vector):
    """係留のクリート（台と左右の角）。"""
    g.box(tuple(p + Vector((0, 0.02, 0))), (0.06, 0.04, 0.10), "FP_Metal")
    g.box(tuple(p + Vector((0, 0.055, 0))), (0.045, 0.025, 0.24), "FP_Metal")


FLOAT_HATCH_U = [2.15, 4.35, 5.35, 7.35, 9.75, 11.05, 12.35, 13.6]     # 甲板の真ん中の点検口（支柱の足をよける）


def build_float_details(g: GMesh):
    """フロートの作り込み（2026-10-22 の V 字の船底の形に合わせた）：甲板の通路（滑り止め）・点検口・排水のふた・クリート・
    船首の当て物・竜骨の金具・船首のしぶきよけ（チャインのレール）・水かじと操作索・つり上げ金具。"""
    fl = C.FLOAT
    for side in (-1, 1):
        xc = side * fl["x"]
        # 通路（滑り止め）：甲板の真ん中の両わきに 2 列
        for dx in (-0.31, 0.31):
            _float_deck_strip(g, xc, dx, 2.5, 12.8, 0.19, "FP_Rubber")
        # 点検口（丸いふた）：甲板の真ん中。金属の縁と白いふた
        for u in FLOAT_HATCH_U:
            v = FP.float_deck_v(u, 0.0)
            g.lathe(tuple(W(u, v - 0.008, xc)), (0, 1, 0), [(0.0, 0.118), (0.010, 0.114), (0.015, 0.100), (0.016, 0.092)], "FP_Metal", n=16,
                    smooth=False)
            g.lathe(tuple(W(u, v + 0.007, xc)), (0, 1, 0), [(0.0, 0.092), (0.006, 0.088), (0.010, 0.0)], "FP_Paint", n=16, smooth=True)
            g.box(tuple(W(u, v + 0.018, xc)), (0.10, 0.012, 0.022), "FP_Metal")
        # 排水のふた（区画ごと、甲板の角の近く）
        for u in FLOAT_HATCH_U:
            hw = FP.float_half_w(u)
            for sx in (-1, 1):
                x = sx * (hw - 0.17)
                v = FP.float_deck_v(u + 0.35, x)
                g.lathe(tuple(W(u + 0.35, v - 0.004, xc + x)), (0, 1, 0), [(0.0, 0.032), (0.008, 0.026), (0.010, 0.0)], "FP_Metal", n=10,
                        smooth=False)
        # クリート（船首と船尾）
        for u in (1.85, 14.15):
            for dx in (-0.20, 0.20):
                _cleat(g, W(u, FP.float_deck_v(u, dx), xc + dx))
        # つり上げ金具（前と後ろの支柱の前）
        for u in (2.85, 8.2):
            p = W(u, FP.float_deck_v(u, 0.0), xc)
            g.tube(tuple(p), tuple(p + Vector((0, 0.05, 0))), 0.018, "FP_Metal", n=8)
            g.sweep([tuple(p + Vector((0, 0.05, -0.045 * math.cos(math.pi * k / 8))) + Vector((0, 0.045 * math.sin(math.pi * k / 8), 0)))
                     for k in range(9)], [0.008] * 9, "FP_Metal", n=6, caps=("flat", "flat"))
        # 船首の当て物（ゴム）
        bk, bd, bw = FP.float_profile(fl["u0"])
        g.lathe(tuple(W(fl["u0"] + 0.035, 0.5 * (bk + bd) + 0.01, xc)), (0, 0, -1), [(0.0, 0.105), (0.022, 0.098), (0.045, 0.065), (0.055, 0.0)],
                "FP_Rubber", n=14, cap0="flat")
        # 竜骨の金具（船首から段まで・段から船尾まで。下の端が竜骨の線）
        for u0, u1 in ((0.95, FP.FLOAT_STEP_U - 0.01), (FP.FLOAT_STEP_U + 0.06, fl["u1"] - 0.25)):
            pts = [tuple(W(u, FP.float_keel(u) + 0.02, xc)) for u in [lerp(u0, u1, i / 14) for i in range(15)]]
            g.polyline_tube(pts, 0.02, "FP_Metal", n=6)
        # 船首のしぶきよけ（チャインにそうレール）
        for sx in (-1, 1):
            pts = []
            for i in range(14):
                u = lerp(1.05, 6.6, i / 13)
                cx, cv = FP.float_chine(u)
                pts.append(tuple(W(u, cv - 0.006, xc + sx * (cx + 0.014))))
            g.polyline_tube(pts, 0.018, "FP_Navy", n=6)
        # 水かじ（船尾の下。暗い板と軸、甲板へ上がる操作索）
        u_r = fl["u1"] - 0.30
        kv = FP.float_keel(u_r)
        poly = [W(u_r - 0.10, kv + 0.04, xc), W(u_r + 0.24, kv + 0.04, xc), W(u_r + 0.26, kv - 0.30, xc), W(u_r - 0.02, kv - 0.36, xc)]
        g.prism([tuple(p + Vector((-0.013, 0, 0))) for p in poly], (0, 0, 0), (0.026, 0, 0), "FP_Dark")
        g.tube(tuple(W(u_r - 0.06, kv - 0.05, xc)), tuple(W(u_r - 0.06, FP.float_deck_v(u_r - 0.06, 0.0) + 0.06, xc)), 0.022, "FP_Metal", n=8)
        for sx in (-1, 1):
            a = W(u_r - 0.06, FP.float_deck_v(u_r - 0.06, 0.0) + 0.05, xc + sx * 0.03)
            b = W(u_r - 1.6, FP.float_deck_v(u_r - 1.6, 0.12) + 0.02, xc + sx * 0.12)
            g.tube(tuple(a), tuple(b), 0.006, "FP_Dark", n=5, smooth=False)


def _disc(g: GMesh, p, n, r, mat, h=0.006, rim=None):
    """面の上の丸い板（点 p・法線 n）。rim を渡すと縁を別の材質の輪にする。"""
    n = Vector(n).normalized()
    base = Vector(p) - n * 0.004
    if rim is None:
        g.lathe(tuple(base), tuple(n), [(0.0, r), (h + 0.004, r * 0.92), (h + 0.006, 0.0)], mat, n=14, smooth=True, crease_deg=50)
    else:
        g.lathe(tuple(base), tuple(n), [(0.0, r), (h + 0.004, r * 0.96), (h + 0.005, r * 0.80)], rim, n=16, smooth=False)
        g.lathe(tuple(base + n * (h + 0.002)), tuple(n), [(0.0, r * 0.82), (0.004, r * 0.70), (0.006, 0.0)], mat, n=16, smooth=True)


def _rounded_rect(u0, u1, v0, v1, r, steps=4):
    pts = []
    for cu, cv, a0 in [(u0 + r, v0 + r, 180), (u1 - r, v0 + r, 270), (u1 - r, v1 - r, 0), (u0 + r, v1 - r, 90)]:
        for k in range(steps + 1):
            a = math.radians(a0 + 90 * k / steps)
            pts.append((cu + r * math.cos(a), cv + r * math.sin(a)))
    pts.append(pts[0])
    return pts


PARA_DOOR_U = (10.30, 10.90)        # 後ろの降下の扉（左右。実機の paratroop door）
PARA_DOOR_V = (C.FLOOR_V + 0.08, 4.02)


def build_wing_details(g: GMesh):
    """主翼：燃料の給油口、下の着陸灯（引っこんだレンズ）、燃料の放出口、翼端の上の編隊灯。"""
    for side in (-1, 1):
        for x in (2.9, 6.2, 9.7):
            p, n = wing_top_point(side * x, 0.42, 0.0)
            _disc(g, p, n, 0.055, "FP_Paint", h=0.004, rim="FP_Metal")
        # 着陸灯（エンジンのあいだの下面）
        lo, _ = FP.airfoil(0.24)
        p = W(FP.WING_LE + 0.24 * FP.CHORD, lo, side * 6.2)
        g.lathe(tuple(p + Vector((0, 0.006, 0))), (0, -1, 0), [(0.0, 0.15), (0.010, 0.145), (0.014, 0.12)], "FP_Dark", n=18, smooth=False)
        g.lathe(tuple(p + Vector((0, 0.012, 0))), (0, -1, 0), [(0.0, 0.12), (0.010, 0.11), (0.016, 0.0)], "FP_Lens", n=18, smooth=True)
        # 燃料の放出口（翼端の近くの下、後ろへ向く短い管）
        lo, _ = FP.airfoil(0.70)
        a = W(FP.WING_LE + 0.70 * FP.CHORD, lo + 0.01, side * 10.9)
        g.tube(tuple(a), tuple(a + Vector((0, -0.06, 0.10))), 0.018, "FP_Metal", n=8)
        # 編隊灯（翼端の上の短い帯）
        pts = [wing_top_point(side * xx, 0.48, 0.0) for xx in (10.55, 10.95)]
        strip_on(g, pts, 0.07, "FP_Slime", lift=0.004)


def build_fuselage_details(g: GMesh):
    """胴体：後ろの降下の扉（左右。輪郭・小さな窓・取っ手）、編隊灯、静圧孔、換気の口。"""
    for side in (-1, 1):
        # 降下の扉
        pts = _rounded_rect(PARA_DOOR_U[0], PARA_DOOR_U[1], PARA_DOOR_V[0], PARA_DOOR_V[1], 0.07)
        strip_on(g, [skin_point(u, v, side, 0.0) for u, v in densify(pts)], 0.016, "FP_Dark", lift=0.003)
        wp, wn = skin_point(0.5 * (PARA_DOOR_U[0] + PARA_DOOR_U[1]), 3.62, side, 0.0)
        _disc(g, wp, wn, 0.11, "FP_WindowDark", h=0.002, rim="FP_Navy")
        hp, hn = skin_point(PARA_DOOR_U[1] - 0.12, 2.95, side, 0.004)
        g.box(tuple(hp), (0.02, 0.05, 0.14), "FP_Dark")
        # 編隊灯（前の胴体の丸窓の上と、後ろの胴体）
        for u0, u1, v in ((4.55, 5.25, 4.98), (13.0, 13.7, 4.70)):
            strip_on(g, [skin_point(u0 + (u1 - u0) * t, v, side, 0.0) for t in (0.0, 0.5, 1.0)], 0.065, "FP_Slime", lift=0.004)
        # 静圧孔（機首の横）
        for u in (1.62, 1.86):
            p, n = skin_point(u, 3.52, side, 0.0)
            _disc(g, p, n, 0.034, "FP_Metal", h=0.002)
        # 換気の口（扉の前の下と、後ろの胴体の下）
        for u, v in ((2.35, 2.35), (12.1, 2.85)):
            p, n = skin_point(u, v, side, 0.0)
            fwd = Vector((0, 0, -1))
            s_ = n.cross(fwd).normalized()
            q = [p - fwd * 0.12 - s_ * 0.05, p - fwd * 0.12 + s_ * 0.05, p + fwd * 0.10 + s_ * 0.035, p + fwd * 0.10 - s_ * 0.035]
            g.oriented([tuple(x + n * 0.004) for x in q], tuple(n), "FP_Dark")
    # 垂直尾翼の編隊灯は置かない（濃紺の上で白い傷のように見えた）


def build_tail_details(g: GMesh):
    """方向舵と昇降舵のタブ（輪郭）。"""
    for side in (-1, 1):
        pts = [fin_point(s_, c, side, 0.0) for s_, c in ((0.16, 0.86), (0.40, 0.86), (0.40, 0.995), (0.16, 0.995))]
        strip_on(g, pts, 0.010, "FP_Dark", lift=0.002)
    st = C.STAB
    for side in (-1, 1):
        for sgn in (1, -1):
            pts = []
            for x, c in ((0.9, 0.86), (2.3, 0.86), (2.3, 0.995)):
                t = x / st["half_span"]
                u0 = lerp(st["u0"], st["u0"] + 0.55, t)
                u1 = lerp(st["u1"], st["u1"] - 0.25, t)
                half_t = lerp(0.12, 0.08, t)
                v = st["v"] + sgn * (half_t * FP._thickness(c) + 0.004)
                pts.append((W(lerp(u0, u1, c), v, side * x), Vector((0, sgn, 0))))
            strip_on(g, pts, 0.010, "FP_Dark", lift=0.002)


def build_static_wicks(g: GMesh):
    for side in (-1, 1):
        for x in (10.6, 11.0, 11.4):
            lo, up = FP.airfoil(1.0)
            a = W(FP.WING_TE - 0.01, 0.5 * (lo + up), side * x)
            g.tube(tuple(a), tuple(a + Vector((0, -0.01, 0.13))), 0.004, "FP_Dark", n=4, smooth=False)
        st = C.STAB
        for x in (2.6, 3.9):
            t = x / st["half_span"]
            u1 = lerp(st["u1"], st["u1"] - 0.25, t)
            a = W(u1 - 0.01, st["v"], side * x)
            g.tube(tuple(a), tuple(a + Vector((0, 0, 0.12))), 0.004, "FP_Dark", n=4, smooth=False)
    for s_ in (0.70, 0.86):
        p, _ = fin_point(s_, 1.0, 1, 0.0)
        a = Vector((0.0, p.y, p.z))
        g.tube(tuple(a), tuple(a + Vector((0, -0.02, 0.12))), 0.004, "FP_Dark", n=4, smooth=False)


# ---------------------------------------------------------------- 文字

def _text_dir(side):
    """外から見て左から右へ読む向き（u の増える向きなら +1）。右の側（+x）は機首へ、左は尾へ。"""
    return -1 if side > 0 else 1


def build_exterior_decals(g: GMesh):
    for side in (-1, 1):
        d = _text_dir(side)
        # 登録記号（垂直尾翼）
        w, h = FI.decal_size("reg")
        uc, vc = 16.25, 7.25

        def reg(a, b, side=side, d=d, w=w, h=h, uc=uc, vc=vc):
            s_, c = fin_sc(uc + (a - 0.5) * w * d, vc + (b - 0.5) * h)
            return fin_point(s_, c, side, 0.004)
        decal_on(g, "reg", reg, nu=6, nv=2)
        # 部隊名（前の胴体、扉の上の高さ）
        w, h = FI.decal_size("unit")
        sc = 1.9 / w
        uc = 3.95

        def unit(a, b, side=side, d=d, w=w * sc, h=h * sc, uc=uc):
            return skin_point(uc + (a - 0.5) * w * d, 4.31 + (b - 0.5) * h, side, 0.004)
        decal_on(g, "unit", unit, nu=8, nv=1)
        # プロペラの危険（プロペラの回る面の高さの横）
        w, h = FI.decal_size("prop")

        def prop(a, b, side=side, d=d, w=w, h=h):
            return skin_point(C.PROP_U + (a - 0.5) * w * d, 3.47 + (b - 0.5) * h, side, 0.004)
        decal_on(g, "prop", prop, nu=6, nv=1)
        # NO STEP（主翼の付け根の上、外から後ろを背に読む）
        w, h = FI.decal_size("nostep")
        for x in (side * 3.0, side * 6.4):
            def ns(a, b, x=x, w=w, h=h):
                c = 0.50 - (b - 0.5) * h / FP.CHORD
                return wing_top_point(x + (a - 0.5) * w, c, 0.004)
            decal_on(g, "nostep", ns, nu=2, nv=2)
    # RESCUE（左の扉の前、矢じりが扉を指す）
    w, h = FI.decal_size("rescue")
    decal_on(g, "rescue", lambda a, b: skin_point(DOOR_U[0] - 0.30 - w + a * w, 2.90 + (b - 0.5) * h, -1, 0.004), nu=3, nv=1)


# ---------------------------------------------------------------- 操縦席の窓枠とガラス（外板の上にじかに作る）

import fp_shell as FS  # noqa: E402


def front_point(x, v):
    """前の窓の (x, v) を、機首の傾いた上の面に写した点（Godot）。u は二分法で求める。"""
    lo, hi = 0.25, 1.45
    for _ in range(40):
        m = 0.5 * (lo + hi)
        s = S.section(m)
        w = S.x_at_v(s, min(v, s["top"] - 1e-3)) if v < s["top"] else 0.0
        if w < abs(x):
            lo = m
        else:
            hi = m
    return W(0.5 * (lo + hi), v, x)


def _front_normal(x, v):
    e = 0.01
    a, b = front_point(x - e, v), front_point(x + e, v)
    c, d = front_point(x, v - e), front_point(x, v + e)
    n = (b - a).cross(d - c)
    if n.y < 0:
        n = -n
    return n.normalized()


def _side_pt(side, u, v, lift):
    return skin_point(u, v, side, lift)


def pane_outlines():
    """窓 1 枚ずつの輪郭の関数 (a 0〜1 の周) → (点, 法線) の並び（閉じた輪）。"""
    out = []
    for side in (-1, 1):
        for x0, x1 in FS.FRONT_PANES:
            xa, xb = sorted((side * x0, side * x1))
            v0, v1 = FS.FRONT_V
            ring = [(xa, v0), (xb, v0), (xb, v1), (xa, v1)]
            out.append(("front", ring, side))
        out.append(("corner", list(FS.CORNER_PANE), side))
        for pane in FS.SIDE_PANES:
            out.append(("side", list(pane), side))
    return out


def _pane_point(kind, ring, side, a, b, lift):
    """窓の中の (a, b)（0〜1）の点：四隅の双一次の補間。"""
    if kind == "corner":
        u, v = FS.corner_uv(a, b)
        return _side_pt(side, u, v, lift)
    (p0, p1, p2, p3) = ring
    q0 = (lerp(p0[0], p1[0], a), lerp(p0[1], p1[1], a))
    q1 = (lerp(p3[0], p2[0], a), lerp(p3[1], p2[1], a))
    q = (lerp(q0[0], q1[0], b), lerp(q0[1], q1[1], b))
    if kind == "front":
        p = front_point(q[0], q[1])
        n = _front_normal(q[0], q[1])
        return p + n * lift, n
    return _side_pt(side, q[0], q[1], lift)


def build_cockpit_frames(g: GMesh):
    for kind, ring, side in pane_outlines():
        pts = []
        steps = 6
        for e in range(4):
            for k in range(steps):
                t = k / steps
                a, b = [(t, 0.0), (1.0, t), (1.0 - t, 1.0), (0.0, 1.0 - t)][e]
                pts.append(_pane_point(kind, ring, side, a, b, 0.0))
        pts.append(pts[0])
        strip_on(g, pts, 0.06, "FP_Navy", lift=0.005)


def build_cockpit_glass():
    g = GMesh()
    for kind, ring, side in pane_outlines():
        nu, nv = 5, 4
        grid = [[_pane_point(kind, ring, side, i / nu, j / nv, -0.032) for j in range(nv + 1)] for i in range(nu + 1)]
        for i in range(nu):
            for j in range(nv):
                q = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                n = q[0][1]
                g.oriented([tuple(p[0]) for p in q], tuple(n), "FP_Glass", smooth=True)
    return g


def build_all(g: GMesh):
    build_cockpit_frames(g)
    build_antennas(g)
    build_pitots(g)
    build_wipers(g)
    build_crew_door_outline(g)
    build_hatches(g)
    build_dorsal(g)
    build_hinge_lines(g)
    build_static_wicks(g)
    build_wing_details(g)
    build_fuselage_details(g)
    build_tail_details(g)
    build_exterior_decals(g)


def build_float_extras(g: GMesh):
    build_float_details(g)

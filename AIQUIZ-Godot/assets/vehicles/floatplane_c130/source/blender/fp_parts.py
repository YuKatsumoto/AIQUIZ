"""水上機 C-130 の外の部品：主翼（フラップ・付け根の覆い）・エンジンの覆い・プロペラ・尾翼・フロートと支柱・灯。

寸法は c130_design.py（WING_*・SPAN・ENGINE_X・NACELLE・PROP_*・FIN・STAB・FLOAT・STRUTS_U）。形は設計の座標 (u, v, x) で考え、
W() で Godot の座標にする。
"""
from __future__ import annotations

import math

from mathutils import Vector

import fp_section as S
from fp_common import GMesh, W, lerp, smoothstep

C = S.C

# ---------------------------------------------------------------- 主翼

WING_LE, WING_TE = C.WING_U
WING_BOT, WING_TOP = C.WING_V
CHORD = WING_TE - WING_LE
HALF_SPAN = C.SPAN / 2
FLAP_C = 0.75                     # 翼弦のこの割合から後ろがフラップ（とその間の動かない後ろの縁）
FLAP_SPANS = [(2.35, 3.70), (5.10, 7.30), (8.70, 10.40)]     # |x| の範囲。エンジンの覆いの後ろは動かない
FLAP_MAX_DEG = 30.0
AIRFOIL_N = 22                    # 翼の断面の上下それぞれの点の数


def _thickness(c):
    """翼の厚みの形（最大 1、c≈0.3）。NACA の 4 けたの式を正規化。"""
    t = 0.2969 * math.sqrt(max(c, 0.0)) - 0.1260 * c - 0.3516 * c ** 2 + 0.2843 * c ** 3 - 0.1036 * c ** 4
    return max(t, 0.0) / 0.1500


T_MAX = WING_TOP - WING_BOT - 0.03     # 厚み 0.52（下面がわずかに丸いぶん）


def airfoil(c):
    """翼弦の割合 c での (下面の v, 上面の v)。下面はほぼ平ら。"""
    t = T_MAX * _thickness(c) + 0.012
    lo = WING_BOT + 0.03 * _thickness(c) * (1 - c) + 0.004
    return lo, lo + t


def _cs(c0, c1, n):
    """c0〜c1 の割合を、前縁の丸みで細かく。"""
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(c0 + (c1 - c0) * (1 - math.cos(math.pi * t)) / 2)
    return out


def wing_section(x, c0, c1, n, scale=1.0):
    """x での断面（下面を前から後ろ → 上面を後ろから前、閉じた輪）。scale は翼端の丸め（翼弦の 40% を中心に縮める）。"""
    cs = _cs(c0, c1, n)
    mid_v = 0.5 * (WING_BOT + WING_TOP)
    lower, upper = [], []
    for c in cs:
        lo, up = airfoil(c)
        u = WING_LE + c * CHORD
        lower.append((u, lo))
        upper.append((u, up))
    pts = lower + list(reversed(upper))
    cu = WING_LE + 0.4 * CHORD
    return [tuple(W(cu + (u - cu) * scale, mid_v + (v - mid_v) * scale, x)) for u, v in pts]


TIP_NAVY_X = 11.30


def build_wing(g: GMesh):
    """主翼（左右）。前縁〜FLAP_C は翼端まで 1 本（翼端は濃紺）。FLAP_C〜後ろの縁は、フラップのない所だけここで作る。"""
    for side in (-1, 1):
        xs = [0.0, 1.0, 2.2, 3.4, 4.4, 5.4, 6.6, 8.0, 9.2, 10.4, TIP_NAVY_X]
        tip = [(11.55, 0.97), (11.75, 0.88), (11.91, 0.70), (12.0, 0.42)]     # 翼端（x = 12.0 で翼の幅 24.0）
        rings = [wing_section(side * x, 0.0, FLAP_C, AIRFOIL_N) for x in xs]
        rings += [wing_section(side * x, 0.0, FLAP_C, AIRFOIL_N, scale=sc) for x, sc in tip]
        navy_from = len(xs) - 1
        g.loft(rings, "FP_Paint", closed=True, smooth=True, cap1=True,
               mats=lambda i, k, nf=navy_from: "FP_Navy" if i >= nf else ("FP_WingEdge" if _wing_le_face(k) else "FP_Paint"))
        for x0, x1 in _te_fixed_spans():
            r = [wing_section(side * x, FLAP_C, 1.0, 8) for x in (x0, x1)]
            g.loft(r, "FP_Navy" if x0 >= TIP_NAVY_X - 1e-6 else "FP_Paint", closed=True, smooth=False, cap0=True, cap1=True)


WING_LE_BAND = 0.062               # 前の縁の金属の帯（翼弦の割合。約 0.2 m）


def _wing_le_face(k):
    """主翼の輪（下面の前→後ろ、上面の後ろ→前）の辺 k が前の縁の帯の中か。"""
    n = AIRFOIL_N + 1
    cs = _cs(0.0, FLAP_C, AIRFOIL_N)

    def c_of(p):
        p %= 2 * n
        return cs[p] if p < n else cs[2 * n - 1 - p]
    return c_of(k) <= WING_LE_BAND + 1e-6 and c_of(k + 1) <= WING_LE_BAND + 1e-6


def _te_fixed_spans():
    out = []
    x = 0.0
    for a, b in FLAP_SPANS:
        if a > x + 1e-6:
            out.append((x, a))
        x = b
    out.append((x, TIP_NAVY_X))
    return out


def flap_hinge(side, span):
    x0, x1 = span
    lo, up = airfoil(FLAP_C)
    return W(WING_LE + FLAP_C * CHORD, 0.5 * (lo + up), side * 0.5 * (x0 + x1))


def build_flap(side, span):
    g = GMesh()
    x0, x1 = span
    r = [wing_section(side * x, FLAP_C, 1.0, 8) for x in (x0 + 0.02, x1 - 0.02)]
    g.loft(r, "FP_Paint", closed=True, smooth=False, cap0=True, cap1=True)
    return g


FAIRING_PROFILE = [(2.04, 4.30), (2.16, 4.80), (2.27, 5.25), (2.30, 5.55), (2.18, 5.82), (1.70, 5.93), (0.90, 5.95), (0.0, 5.95)]
FAIRING_U = [4.10, 4.30, 4.50, 4.70, 4.90, 5.10, 6.00, 7.00, 8.20, 8.45, 8.70, 8.95, 9.15, 9.40]


def build_wing_fairing(g: GMesh):
    """主翼の付け根の覆い：胴体の上の肩と主翼の下面のすき間をうめる（C-130 の背中のこぶ）。
    前後の端は胴体の外板の少し内側へしぼむ（つなぎ目が見えない）。しぼむ先の点は、断面の角度を輪郭の長さの割合で
    下の点から真上まで順に割りふる（点の順が入れかわらない）。"""
    prof = FAIRING_PROFILE
    lens = [0.0]
    for (xa, va), (xb, vb) in zip(prof[:-1], prof[1:]):
        lens.append(lens[-1] + math.hypot(xb - xa, vb - va))
    fr = [l_ / lens[-1] for l_ in lens]
    rings = []
    for u in FAIRING_U:
        w = smoothstep(4.10, 5.05, u) * (1 - smoothstep(8.25, 9.40, u))
        s = S.section(u)
        th0 = S.theta_for_v(s, prof[0][1])
        half = []
        for (x, v), f in zip(prof, fr):
            th = th0 + (math.pi / 2 - th0) * f
            fx, fv = S.point(s, th)
            nx, nv = S.normal(s, th)
            fx, fv = fx - 0.04 * nx, fv - 0.04 * nv
            half.append((lerp(fx, x, w), lerp(fv, v, w)))
        half[-1] = (0.0, half[-1][1])
        full = half + [(-x, v) for x, v in reversed(half[:-1])]
        rings.append([tuple(W(u, v, x)) for x, v in full])
    g.loft(rings, "FP_Paint", closed=False, smooth=True,
           hint_fn=lambda i, k, rings=rings: Vector(rings[i][k]) - Vector((0.0, 3.6, rings[i][k][2])))


# ---------------------------------------------------------------- エンジンの覆いとプロペラ

NAC = C.NACELLE
PROP_R = C.PROP_D / 2


def engine_order():
    """プロペラの番号（1〜4）：左の外から右の外へ。"""
    xs = [-C.ENGINE_X[1], -C.ENGINE_X[0], C.ENGINE_X[0], C.ENGINE_X[1]]
    return xs


# 2026-10-22：覆いを作り直した（前は丸い筒と、上に主翼へつなぐ四角い箱）。T56 の覆いのように、前の縁（濃紺の輪）から下へ
# ふくらみ、上は主翼の前の縁へなだらかに入り、主翼の後ろの縁より後ろへ細く伸びて排気口で終わる（フラップのすき間の中）。
# 下にはあごの吸気口と油の冷却口。断面は超楕円 (u, 半幅, 上, 下, 上の丸み, 下の丸み)。
NAC_FRONT_U = 3.03
NAC_STATIONS = [
    (NAC_FRONT_U, 0.470, 5.670, 4.730, 2.0, 2.0),
    (3.08, 0.500, 5.700, 4.680, 2.15, 2.2),
    (3.20, 0.540, 5.760, 4.600, 2.3, 2.35),
    (3.45, 0.572, 5.830, 4.545, 2.45, 2.5),
    (3.90, 0.588, 5.900, 4.525, 2.55, 2.6),
    (4.50, 0.594, 5.960, 4.530, 2.6, 2.6),
    (5.10, 0.592, 6.020, 4.550, 2.6, 2.6),
    (5.80, 0.580, 6.050, 4.580, 2.6, 2.5),
    (6.60, 0.555, 6.050, 4.640, 2.6, 2.4),
    (7.30, 0.515, 6.030, 4.740, 2.5, 2.3),
    (7.90, 0.450, 6.000, 4.900, 2.4, 2.2),
    (8.40, 0.360, 5.970, 5.100, 2.3, 2.1),
    (8.80, 0.262, 5.940, 5.330, 2.2, 2.05),
    (9.08, 0.168, 5.910, 5.530, 2.1, 2.0),
    (9.20, 0.128, 5.900, 5.610, 2.0, 2.0),
]
NAC_N = 32
NAC_EXHAUST_U = NAC_STATIONS[-1][0]


def nacelle_section(u):
    """u での覆いの断面 (半幅, 上, 下, 腹の高さ, 上の丸み, 下の丸み)。駅のあいだは線形。"""
    st = NAC_STATIONS
    if u <= st[0][0]:
        row = st[0]
    elif u >= st[-1][0]:
        row = st[-1]
    else:
        i = max(j for j in range(len(st) - 1) if st[j][0] <= u)
        a, b = st[i], st[i + 1]
        t = (u - a[0]) / (b[0] - a[0])
        row = tuple(lerp(a[k], b[k], t) for k in range(6))
    _, a_, top, bot, nt, nb = row
    belt = NAC["v"] if u < 4.0 else lerp(NAC["v"], 0.5 * (top + bot), smoothstep(4.0, 6.5, u))
    return a_, top, bot, belt, nt, nb


def nacelle_point(u, x_eng, th):
    """覆いの面の点（Godot）と外向きの法線。th は −π/2（下）〜 π/2（上）、右（外から見て +x）半分。負の x は x_eng からの左。"""
    a_, top, bot, belt, nt, nb = nacelle_section(u)
    c, s = math.cos(th), math.sin(th)
    n = nt if s >= 0 else nb
    h = (top - belt) if s >= 0 else (belt - bot)
    dx = a_ * math.copysign(abs(c) ** (2 / n), c)
    dv = h * math.copysign(abs(s) ** (2 / n), s)
    gx = (n / a_) * (abs(dx) / a_) ** (n - 1) * math.copysign(1, c)
    gy = (n / h) * (abs(dv) / h) ** (n - 1) * math.copysign(1, s)
    ln = math.hypot(gx, gy) or 1.0
    return W(u, belt + dv, x_eng + dx), Vector((gx / ln, gy / ln, 0.0))


def nacelle_ring(u, x_eng):
    return [tuple(nacelle_point(u, x_eng, -math.pi / 2 + 2 * math.pi * k / NAC_N)[0]) for k in range(NAC_N)]


def _scoop(g: GMesh, x, u0, u1, w0, d0, front_mat="FP_Navy"):
    """覆いの下のすくい口（前が開いた U の形のふくらみ。奥は暗い）。u0 で幅 w0・深さ d0、u1 で覆いへ消える。"""
    us = [u0 + (u1 - u0) * t for t in (0.0, 0.08, 0.3, 0.55, 0.8, 1.0)]
    rings = []
    for u in us:
        t = (u - u0) / (u1 - u0)
        w = w0 * (1 - 0.45 * t ** 1.5)
        d = d0 * (1 - t ** 1.6)
        _, _, bot, _, _, _ = nacelle_section(u)
        ring = []
        for k in range(11):
            a = math.pi * k / 10                             # 0 = 左の上 → 下 → 右の上
            ring.append(tuple(W(u, bot + 0.10 - (0.10 + d) * math.sin(a) ** 0.75, x + w * math.cos(math.pi - a))))
        rings.append(ring)
    g.loft(rings, "FP_Paint", closed=False, smooth=True,
           mats=lambda i, k: front_mat if i == 0 else "FP_Paint",
           hint_fn=lambda i, k, rings=rings, us=us: Vector(rings[i][k]) - Vector((x, nacelle_section(us[i])[2] + 0.10, us[i] - S.U0)))
    # 奥の暗い面（前の縁から 4 cm 奥）
    _, _, bot, _, _, _ = nacelle_section(u0)
    pts = []
    for k in range(11):
        a = math.pi * k / 10
        pts.append(tuple(W(u0 + 0.04, bot + 0.10 - (0.10 + d0 * 0.88) * math.sin(a) ** 0.75, x + w0 * 0.88 * math.cos(math.pi - a))))
    g.oriented(pts, (0, 0, -1), "FP_Dark")


def _nacelle_seam(g: GMesh, u, x, v_max=5.78):
    """覆いの継ぎ目（輪）：主翼の中に入る上の部分は描かない。"""
    for sgn in (-1, 1):
        pts = []
        for k in range(17):
            th = -math.pi / 2 + math.pi * k / 16
            p, n = nacelle_point(u, x, th)
            if p.y > v_max:
                break
            pts.append((p if sgn > 0 else Vector((2 * x - p.x, p.y, p.z)), n if sgn > 0 else Vector((-n.x, n.y, n.z))))
        if len(pts) > 1:
            strip_line(g, pts, 0.012, "FP_Dark")


def strip_line(g: GMesh, pts_normals, w, mat, lift=0.003):
    for (a, na), (b, nb) in zip(pts_normals[:-1], pts_normals[1:]):
        a, b = Vector(a), Vector(b)
        d = b - a
        if d.length < 1e-6:
            continue
        n = (Vector(na) + Vector(nb)).normalized()
        side = d.normalized().cross(n) * (w / 2)
        q = [a - side + n * lift, b - side + n * lift, b + side + n * lift, a + side + n * lift]
        g.oriented([tuple(p) for p in q], tuple(n), mat)


def build_nacelle(g: GMesh, x):
    us = [row[0] for row in NAC_STATIONS]
    rings = [nacelle_ring(u, x) for u in us]
    g.loft(rings, "FP_Paint", closed=True, smooth=True, cap1=True,
           mats=lambda i, k: "FP_Navy" if i <= 1 else "FP_Paint",
           hint_fn=lambda i, k, rings=rings, us=us: Vector(rings[i][k]) - Vector((x, nacelle_section(us[i])[3], us[i] - S.U0)))
    # 前の縁の内側（濃紺の唇。面は軸の側を向く）→ 奥の暗い面（スピナーのまわりの吸い込み口）
    o = W(NAC_FRONT_U, NAC["v"], x)
    r0 = NAC_STATIONS[0][1]
    lip = [(0.0, r0), (0.025, r0 * 0.95), (0.06, r0 * 0.925), (0.13, r0 * 0.915)]
    lip_rings = [[tuple(o + Vector((r * math.cos(2 * math.pi * k / NAC_N), r * math.sin(2 * math.pi * k / NAC_N), s))) for k in range(NAC_N)]
                 for s, r in lip]
    g.loft(lip_rings, "FP_Navy", closed=True, smooth=True,
           hint_fn=lambda i, k, lip=lip: o + Vector((0, 0, lip[i][0])) - Vector(lip_rings[i][k]))
    g.lathe(tuple(o + Vector((0, 0, 0.13))), (0, 0, 1), [(0.0, r0 * 0.915), (0.001, r0 * 0.915)], "FP_Dark", ref=(0, 1, 0), n=NAC_N, cap0="flat")
    # あごの吸気口と、うしろの油の冷却口
    _scoop(g, x, 3.10, 4.55, 0.31, 0.15)
    _scoop(g, x, 4.85, 5.65, 0.17, 0.07, front_mat="FP_Paint")
    # 覆いの継ぎ目と留め金
    for u in (3.52, 5.02, 7.05):
        _nacelle_seam(g, u, x)
    for u in (3.80, 4.30, 4.75):
        for sgn in (-1, 1):
            p, n = nacelle_point(u, x, -0.10)
            if sgn < 0:
                p, n = Vector((2 * x - p.x, p.y, p.z)), Vector((-n.x, n.y, n.z))
            g.box(tuple(p + n * 0.004), (0.02, 0.022, 0.07), "FP_Dark")
    # 排気口（後ろの端。熱で焼けた金属の短い管と、暗い奥）
    _, top, bot, belt, _, _ = nacelle_section(NAC_EXHAUST_U)
    vc = 0.5 * (top + bot)
    e = W(NAC_EXHAUST_U - 0.06, vc, x)
    g.lathe(tuple(e), (0, 0, 1), [(0.0, 0.122), (0.08, 0.124), (0.13, 0.118)], "FP_Exhaust", ref=(0, 1, 0), n=20, crease_deg=40)
    g.lathe(tuple(e + Vector((0, 0, 0.11))), (0, 0, 1), [(0.0, 0.112), (0.001, 0.112)], "FP_Dark", ref=(0, 1, 0), n=20, cap1="flat")
    return W(4.4, NAC["v"] + 0.54, x)


def exhaust_point(x):
    """排気口の出口の真ん中（Godot）。Godot の外板の汚れ（焼け）の中心。"""
    _, top, bot, _, _, _ = nacelle_section(NAC_EXHAUST_U)
    return W(NAC_EXHAUST_U + 0.07, 0.5 * (top + bot), x)


SPINNER_BACK = 0.10               # スピナーは羽根の面から 0.10 後ろから始まる（羽根はスピナーの横から出る）


def build_spinner(x):
    g = GMesh()
    o = W(C.PROP_U, NAC["v"], x)
    back = o + Vector((0, 0, SPINNER_BACK))
    st = [(0.0, 0.445), (0.05, 0.446), (0.14, 0.440), (0.26, 0.420), (0.38, 0.380), (0.50, 0.320), (0.60, 0.250), (0.68, 0.170),
          (0.74, 0.095), (0.775, 0.035), (0.785, 0.0)]
    g.lathe(tuple(back), (0, 0, -1), st, "FP_Spinner", ref=(0, 1, 0), n=32, cap0="flat")
    # 後ろの板（濃紺。覆いの前の縁の内側に入る）
    g.lathe(tuple(back), (0, 0, 1), [(0.0, 0.445), (0.012, 0.44), (0.02, 0.30)], "FP_Navy", ref=(0, 1, 0), n=32)
    return g, o


BLADE_COUNT = 4
BLADE_PITCH_DEG = 22.0            # ふだんの羽根の角度（回る面からのねじれ）
BLADE_TIP = 0.18                  # 先の黄色の長さ
# 羽根（Hamilton Standard 54H60 のように幅の広い櫂の形）：(半径, 翼弦, 厚み)。根元は丸い軸（カフ）から翼形へ
BLADE_STATIONS = [(0.30, 0.14, 0.14), (0.40, 0.15, 0.15), (0.47, 0.17, 0.14), (0.54, 0.24, 0.10), (0.62, 0.300, 0.072), (0.75, 0.335, 0.058),
                  (0.90, 0.345, 0.050), (1.05, 0.342, 0.042), (1.17, 0.330, 0.036), (1.25, 0.312, 0.032), (1.31, 0.285, 0.029),
                  (1.355, 0.235, 0.026), (1.385, 0.160, 0.022), (1.40, 0.070, 0.018)]
BLADE_PTS = 16


def _blade_section(round_mix: float, ch: float, th: float):
    """翼形（前の面がふくらみ、後ろの面は平ら）を、round_mix で丸い軸へまぜた断面の (翼弦の向き, 厚みの向き) の点。"""
    out = []
    for k in range(BLADE_PTS):
        a = 2 * math.pi * k / BLADE_PTS
        xc = 0.5 * (1 - math.cos(a))                 # 0 前の縁 → 1 後ろの縁
        up = a <= math.pi
        tt = _thickness(min(max(xc, 0.0), 1.0))
        y = (0.5 * th * (tt * 1.15 + 0.06)) if up else (-0.5 * th * (0.22 * tt + 0.03))
        # 前の縁は +cdir の側（回る向きの前、少し前へ：Godot は +Z まわりに正に回す）
        foil = (ch * (0.42 - xc), y)
        circ = (0.5 * ch * math.cos(a), 0.5 * th * math.sin(a))
        out.append((lerp(foil[0], circ[0], round_mix), lerp(foil[1], circ[1], round_mix)))
    return out


def build_blade(hub: Vector, angle_deg: float):
    """羽根 1 枚（原点は軸の中心）。angle_deg は回る面の中の向き（0＝真上、時計回りに見て）。返り値 (GMesh, 放射の向き)。"""
    g = GMesh()
    a = math.radians(angle_deg)
    radial = Vector((math.sin(a), math.cos(a), 0.0))
    tangent = Vector((0, 0, 1)).cross(radial)          # 回る面の中で羽根に直交
    axis = Vector((0, 0, -1))                            # 前
    r0, r1 = BLADE_STATIONS[0][0], PROP_R
    rings = []
    tip_from = None
    for i, (r, ch, th) in enumerate(BLADE_STATIONS):
        t = (r - r0) / (r1 - r0)
        twist = math.radians(BLADE_PITCH_DEG + 18.0 * (1 - t))
        cdir = tangent * math.cos(twist) + axis * math.sin(twist)
        tdir = -tangent * math.sin(twist) + axis * math.cos(twist)
        c = hub + radial * r
        rm = 1.0 - smoothstep(0.45, 0.60, r)
        rings.append([tuple(c + cdir * px + tdir * py) for px, py in _blade_section(rm, ch, th)])
        if tip_from is None and r >= r1 - BLADE_TIP:
            tip_from = i
    mats = lambda i, k: "FP_PropTip" if i >= tip_from else "FP_PropBlade"   # noqa: E731
    g.loft(rings, "FP_PropBlade", closed=True, smooth=True, mats=mats, cap1=True)
    return g, radial


# ---------------------------------------------------------------- 尾翼

def build_fin(g: GMesh):
    """垂直尾翼：根元は胴体の上の線（少し中）、先は FIN の上の辺。厚みは根元 0.40 → 先 0.22。"""
    (u_le0, v_le0), (u_le1, v_le1), (u_te1, v_te1), (u_te0, v_te0) = C.FIN
    root_le = (u_le0, S.section(u_le0)["top"] - 0.06)
    root_te = (u_te0 - 0.02, S.section(min(u_te0, 18.0))["top"] - 0.05)
    ss = [0.0, 0.12, 0.3, 0.5, 0.7, 0.86, 0.95, 1.0]
    rings = []
    for s_ in ss:
        le = (lerp(root_le[0], u_le1, s_), lerp(root_le[1], v_le1, s_))
        te = (lerp(root_te[0], u_te1, s_), lerp(root_te[1], v_te1, s_))
        half_t = lerp(0.20, 0.11, s_)
        if s_ > 0.9:
            half_t *= 0.6 + 0.4 * (1 - (s_ - 0.9) / 0.1)
        ring = []
        cs = _cs(0.0, 1.0, 12)
        upper, lower = [], []
        for c in cs:
            u = lerp(le[0], te[0], c)
            v = lerp(le[1], te[1], c)
            t = half_t * _thickness(c) + 0.006
            upper.append(tuple(W(u, v, t)))
            lower.append(tuple(W(u, v, -t)))
        ring = upper + list(reversed(lower[1:-1]))
        rings.append(ring)
    g.loft(rings, "FP_Navy", closed=True, smooth=True, cap1=True)


def build_stab(g: GMesh):
    st = C.STAB
    for side in (-1, 1):
        xs = [0.0, 1.5, 3.0, 4.0, 4.4, 4.6]
        rings = []
        for x in xs:
            t = x / st["half_span"]
            u0 = lerp(st["u0"], st["u0"] + 0.55, t)
            u1 = lerp(st["u1"], st["u1"] - 0.25, t)
            sc = 1.0 if x < 4.3 else (0.75 if x < 4.5 else 0.45)
            half_t = lerp(0.12, 0.08, t) * sc
            ch = (u1 - u0) * (1.0 if sc == 1.0 else 0.6 + 0.4 * sc)
            mid = 0.5 * (u0 + u1)
            u0, u1 = mid - 0.5 * ch, mid + 0.5 * ch
            cs = _cs(0.0, 1.0, 12)
            upper = [tuple(W(lerp(u0, u1, c), st["v"] + half_t * _thickness(c) + 0.004, side * x)) for c in cs]
            lower = [tuple(W(lerp(u0, u1, c), st["v"] - half_t * _thickness(c) - 0.004, side * x)) for c in cs]
            rings.append(upper + list(reversed(lower[1:-1])))
        g.loft(rings, "FP_Navy", closed=True, smooth=True, cap1=True)


# ---------------------------------------------------------------- フロートと支柱

FL = C.FLOAT
FLOAT_NAVY_V = 0.05         # これより下は濃紺（水面のすぐ上に細く見える）
FLOAT_LINE_V = (0.40, 0.46)  # 横の細い濃紺の線
# 2026-10-22（ユーザーの指示「輸送機のクオリティーを上げれるだけ上げて」）：丸い筒の浮き舟を、本物の水上機のフロート
# （EDO・Wipline の形）にした。船底は V 字（竜骨とチャイン＝角）、横はわずかに外へ開き、甲板は角を丸めて少し盛り上がる。
# 船首は甲板が下がって竜骨が反り上がり、平面はとがる。u 8.6 に船底の段（0.09 上がる）、段から後ろの船底は船尾へ反り上がる。
# 寸法の約束（長さ 14.2・幅 1.7・高さ 1.7・喫水 0.65・間 7.2）はそのまま。
FLOAT_STEP_U = 8.60
FLOAT_STEP_H = 0.09
FLOAT_KEEL = FL["v"] - FL["r"]          # −0.65：竜骨（いちばん下）
FLOAT_DECK = FL["v"] + FL["r"]          # 1.05：甲板の真ん中（いちばん上）
FLOAT_HW = FL["r"]                      # 0.85：半幅
FLOAT_CROWN = 0.035                     # 甲板の盛り上がり（真ん中と角の差）
FLOAT_EDGE_R = 0.11                     # 甲板の角の丸み


def float_keel(u):
    """竜骨の高さ（海面から）。船首で反り上がり、段のあとは船尾へ反り上がる。"""
    u0, u1 = FL["u0"], FL["u1"]
    bow_end = 3.4
    if u < bow_end:
        t = (u - u0) / (bow_end - u0)
        return lerp(0.52, FLOAT_KEEL, 1 - (1 - t) ** 2.1)
    if u <= FLOAT_STEP_U:
        return FLOAT_KEEL
    t = min(1.0, (u - FLOAT_STEP_U) / (u1 - FLOAT_STEP_U))
    return FLOAT_KEEL + FLOAT_STEP_H * smoothstep(FLOAT_STEP_U, FLOAT_STEP_U + 0.025, u) + 0.98 * t ** 1.45


def float_deck(u):
    """甲板の真ん中の高さ。船首と船尾で少し下がる。"""
    u0, u1 = FL["u0"], FL["u1"]
    if u < 2.7:
        t = (u - u0) / (2.7 - u0)
        return lerp(0.88, FLOAT_DECK, 1 - (1 - t) ** 2.2)
    if u > 12.4:
        t = (u - 12.4) / (u1 - 12.4)
        return lerp(FLOAT_DECK, 0.84, t ** 1.7)
    return FLOAT_DECK


def float_half_w(u):
    """平面の半幅。船首はとがり、船尾は細くなる。"""
    u0, u1 = FL["u0"], FL["u1"]
    if u < 3.3:
        t = (u - u0) / (3.3 - u0)
        return lerp(0.07, FLOAT_HW, 1 - (1 - t) ** 1.9)
    if u > 10.8:
        t = (u - 10.8) / (u1 - 10.8)
        return lerp(FLOAT_HW, 0.19, t ** 1.55)
    return FLOAT_HW


def float_deadrise(u):
    """船底の V の角度（度）。船首ほど深い。"""
    return lerp(24.0, 42.0, 1 - smoothstep(0.8, 4.2, u)) if u < 4.2 else lerp(24.0, 20.0, smoothstep(FLOAT_STEP_U, 14.0, u))


def float_profile(u):
    """u での (竜骨, 甲板の真ん中, 半幅)。"""
    return float_keel(u), float_deck(u), float_half_w(u)


def float_chine(u):
    """チャイン（船底と横の角）の (|x|, v)。"""
    hw = float_half_w(u)
    kx = 0.965 * hw
    return kx, float_keel(u) + kx * math.tan(math.radians(float_deadrise(u)))


def float_deck_v(u, x):
    """甲板の (|x|) での高さ（角の丸みの内側だけ。外は角の丸みの上の端）。"""
    hw = float_half_w(u)
    r = min(FLOAT_EDGE_R, 0.45 * hw)
    flat = max(hw - r, 1e-4)
    k = min(abs(x) / flat, 1.0)
    return float_deck(u) - FLOAT_CROWN * k * k


# 輪の区間ごとの点の数（右半分：竜骨→チャイン、チャイン→水線、水線→線の下、線、線の上→横の上、角の丸み、甲板）
FLOAT_SEG = [3, 1, 2, 1, 1, 3, 3]
FLOAT_K = 2 * sum(FLOAT_SEG)


def float_ring(u, xc):
    """u の輪（竜骨から右を上へ、甲板の真ん中から左を下へ）。点の数はどの u も同じ。"""
    keel, deck, hw = float_profile(u)
    cx, cv = float_chine(u)
    r = min(FLOAT_EDGE_R, 0.45 * hw)
    edge_v = deck - FLOAT_CROWN            # 甲板の角の高さ
    side_top = edge_v - r
    eps = 0.004
    marks = [FLOAT_NAVY_V, FLOAT_LINE_V[0], FLOAT_LINE_V[1]]
    vs = []
    lo = cv + eps
    for i, m in enumerate(marks):
        hi = side_top - eps * (len(marks) - i)
        vs.append(min(max(m, lo), hi))
        lo = vs[-1] + eps

    def side_x(v):
        f = min(max((v - cv) / max(side_top - cv, 1e-4), 0.0), 1.0)
        return cx + (hw - cx) * f ** 0.65

    right = []
    for j in range(FLOAT_SEG[0]):                       # 船底（竜骨 → チャイン、まっすぐ）
        f = j / FLOAT_SEG[0]
        right.append((cx * f, keel + (cv - keel) * f))
    right.append((cx, cv))
    v_chain = [cv, vs[0]] + [vs[0] + (vs[1] - vs[0]) * k / FLOAT_SEG[2] for k in range(1, FLOAT_SEG[2])] + [vs[1], vs[2], side_top]
    for v in v_chain[1:]:
        right.append((side_x(v), v))
    for k in range(1, FLOAT_SEG[5] + 1):                # 角の丸み（四分円）
        a = (math.pi / 2) * k / FLOAT_SEG[5]
        right.append((hw - r + r * math.cos(a), side_top + r * math.sin(a)))
    for k in range(1, FLOAT_SEG[6] + 1):                # 甲板（少し盛り上がる）
        x = (hw - r) * (1 - k / FLOAT_SEG[6])
        right.append((x, float_deck_v(u, x)))
    pts = right + [(-x, v) for x, v in reversed(right[1:-1])]
    return [(xc + x, v) for x, v in pts]


def float_seg(k):
    kk = k if k < sum(FLOAT_SEG) else FLOAT_K - 1 - k
    acc = 0
    for i, n in enumerate(FLOAT_SEG):
        if kk < acc + n:
            return i
        acc += n
    return len(FLOAT_SEG) - 1


FLOAT_US = [0.80, 0.83, 0.90, 1.02, 1.20, 1.45, 1.75, 2.10, 2.50, 2.95, 3.40, 3.90, 4.50, 5.10, 5.70, 6.30, 6.90, 7.50, 8.10, 8.45,
            FLOAT_STEP_U, FLOAT_STEP_U + 0.025, 8.80, 9.30, 9.90, 10.50, 11.10, 11.70, 12.30, 12.90, 13.45, 13.95, 14.35, 14.65, 14.86, 15.0]


def build_floats(g: GMesh):
    for side in (-1, 1):
        xc = side * FL["x"]
        rings = [[tuple(W(u, v, x)) for x, v in float_ring(u, xc)] for u in FLOAT_US]
        # 船底・水線より下・細い線は濃紺。角（チャイン・竜骨・段）は fp_common.create_object の 42° でとがる
        g.loft(rings, "FP_Paint", closed=True, smooth=True, cap0=True, cap1=True,
               mats=lambda i, k: "FP_Navy" if float_seg(k) in (0, 1, 3) else "FP_Paint")


def strut_points():
    """支柱：(下の端, 上の端) の並び（Godot）。フロートの甲板 → 胴体の下の横、フロートの甲板 → 主翼の下面。"""
    out = []
    lo, _ = airfoil(0.45)
    for side in (-1, 1):
        xf = side * FL["x"]
        for u in C.STRUTS_U:
            s = S.section(u)
            vf = 2.05
            xf_body = side * (S.x_at_v(s, vf) - 0.06)
            xa = xf - side * 0.12
            out.append((W(u - 0.25, float_deck_v(u - 0.25, 0.12) - 0.02, xa), W(u + 0.05, vf, xf_body)))
        out.append((W(6.3, float_deck_v(6.3, 0.0) - 0.02, xf), W(6.5, lo + 0.04, side * 3.55)))
    return out


def _strut_frame(a: Vector, b: Vector):
    """支柱の向き（軸・翼弦＝前から後ろ・厚み）。翼弦は機体の後ろ（Godot の +Z）を軸に直交する面へ写した向き。"""
    d = (b - a).normalized()
    c = Vector((0.0, 0.0, 1.0))
    c = (c - d * c.dot(d)).normalized()
    t = d.cross(c).normalized()
    return d, c, t


def strut_section(center: Vector, c: Vector, t: Vector, chord: float, thick: float, n: int = 16):
    """流線形の断面（対称の翼形。前の縁が −c）。点の並びは前の縁から上面を後ろへ、下面を前へ。"""
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        x01 = 0.5 * (1 - math.cos(a))                    # 0（前）〜 1（後ろ）
        half = 0.5 * thick * _thickness(min(max(x01, 0.0), 1.0)) * 0.98 + 0.002
        sgn = 1.0 if a <= math.pi else -1.0
        pts.append(tuple(center + c * (chord * (x01 - 0.35)) + t * (sgn * half)))
    return pts


def build_strut(g: GMesh, a: Vector, b: Vector, chord=0.26, thick=0.085, mat="FP_Paint", boot=True):
    """流線形の支柱 1 本と、両端の覆い（フロート側は大きく広がる靴、上は付け根の覆い）。"""
    a, b = Vector(a), Vector(b)
    d, c, t = _strut_frame(a, b)
    L = (b - a).length
    k = max(2, int(math.ceil(L / 0.3)))
    rings = [strut_section(a + d * (L * i / k), c, t, chord, thick) for i in range(k + 1)]
    g.loft(rings, mat, closed=True, smooth=True, cap0=True, cap1=True)
    # 両端の覆い：太い断面から支柱の断面へすぼまる
    if boot:
        foot = [(-0.04, 2.10), (0.06, 1.75), (0.16, 1.32), (0.26, 1.08), (0.32, 1.0)]
        rings = [strut_section(a + d * s, c, t, chord * f, thick * (1 + (f - 1) * 1.15)) for s, f in foot]
        g.loft(rings, mat, closed=True, smooth=True, cap0=True)
    head = [(-0.22, 1.0), (-0.16, 1.06), (-0.08, 1.30), (0.0, 1.55), (0.04, 1.58)]
    rings = [strut_section(b + d * s, c, t, chord * f, thick * f) for s, f in head]
    g.loft(rings, mat, closed=True, smooth=True, cap1=True)


def build_struts(g: GMesh):
    pts = strut_points()
    for i, (a, b) in enumerate(pts):
        wing = i % 3 == 2
        build_strut(g, a, b, chord=0.32 if wing else 0.26, thick=0.10 if wing else 0.085)
    # 前と後ろの胴体の支柱のあいだの X の張り線（ターンバックルつき）
    for side_i in range(2):
        fa, fb = pts[side_i * 3]
        ra, rb = pts[side_i * 3 + 1]
        for p, q in (((fa, fb, 0.22), (ra, rb, 0.80)), ((fa, fb, 0.80), (ra, rb, 0.22))):
            pa = p[0] + (p[1] - p[0]) * p[2]
            pb = q[0] + (q[1] - q[0]) * q[2]
            dd = (pb - pa).normalized()
            pa, pb = pa + dd * 0.05, pb - dd * 0.05
            g.tube(tuple(pa), tuple(pb), 0.008, "FP_Metal", n=6, smooth=False)
            m = pa + (pb - pa) * 0.5
            g.tube(tuple(m - dd * 0.09), tuple(m + dd * 0.09), 0.016, "FP_Metal", n=8)


# ---------------------------------------------------------------- 灯

def nav_light_positions():
    lo, up = airfoil(0.35)
    v = 0.5 * (lo + up)
    return {"NavLight_L": W(WING_LE + 0.35 * CHORD, v, -11.90), "NavLight_R": W(WING_LE + 0.35 * CHORD, v, 11.90),
            "Beacon": W(9.6, S.section(9.6)["top"] + 0.07, 0.0), "TailLight": W(17.98, 5.14, 0.0)}


def build_lamp(pos: Vector, r=0.09, mat="FP_LightRed"):
    g = GMesh()
    g.lathe(tuple(pos + Vector((0, -r * 0.2, 0))), (0, 1, 0), [(0.0, r), (r * 0.6, r * 0.85), (r * 1.0, r * 0.45), (r * 1.15, 0.0)], mat, n=12, cap0="flat")
    return g


def build_beacon_base(g: GMesh, pos: Vector):
    g.lathe(tuple(pos + Vector((0, -0.09, 0))), (0, 1, 0), [(0.0, 0.16), (0.05, 0.14), (0.08, 0.10)], "FP_Dark", n=14, cap1="flat")

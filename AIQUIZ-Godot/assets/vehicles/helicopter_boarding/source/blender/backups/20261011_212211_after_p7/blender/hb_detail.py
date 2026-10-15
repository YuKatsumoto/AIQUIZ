"""胴体の外の作り込み：屋根のエンジンカバー（吸気口・排気管・継ぎ目・リベット・留め具）、アンテナ、ビーコンの台座。

すべて Godot の座標（地面基準、機首 -z）。部品は "Body" に入れる（返り値の GMesh）。ドアの開く通り道・ジェットのたたむ範囲・
ローターの羽根の高さの決まりはビルダーのチェックで確かめる。
"""
from __future__ import annotations

import math

from mathutils import Matrix, Vector

from hb_common import SPEC, G, GMesh, belly_y, frame_from, pchip, section_extent

# ---------------------------------------------------------------- 屋根のエンジンカバー
#
# 屋根の上に載る流線形のカバー。断面は超楕円のアーチ（n = 2.6）で、すそは屋根へなじむ。
# 前はドアの後ろの端（z -0.549 より後ろ。ドアは開くと前へ動くので、ここより後ろには来ない）、後ろは尾の付け根へ細る。
COWL_Z = [-0.535, -0.505, -0.455, -0.385, -0.285, -0.10, 0.15, 0.45, 0.75, 0.95, 1.12, 1.28, 1.42, 1.54, 1.64]
COWL_W = [0.16, 0.30, 0.40, 0.46, 0.50, 0.52, 0.52, 0.52, 0.50, 0.47, 0.42, 0.35, 0.27, 0.19, 0.11]
COWL_CROWN = [3.62, 3.69, 3.735, 3.76, 3.78, 3.795, 3.80, 3.80, 3.77, 3.72, 3.64, 3.54, 3.42, 3.29, 3.18]
COWL_N = 2.6            # アーチの丸み
COWL_K = 12             # アーチの分割
COWL_BASE_LIFT = 0.03   # アーチの足元は屋根より少し上（すその点で屋根へもぐる）
COWL_SKIRT = 0.06       # すその幅


def roof(z, x=0.0):
    """胴体の上面の高さ（外形）。"""
    y = section_extent(z, x=x)
    return y if y is not None else 0.0


def roof_surface(x, z):
    """屋根の上の点と外向きの法線。"""
    e = 0.005
    y = roof(z, x)
    dydx = (roof(z, x + e) - roof(z, x - e)) / (2 * e)
    dydz = (roof(z + e, x) - roof(z - e, x)) / (2 * e)
    return Vector((x, y, z)), Vector((-dydx, 1.0, -dydz)).normalized()


def cowl_dims(z):
    zc = min(max(z, COWL_Z[0]), COWL_Z[-1])
    return pchip(COWL_Z, COWL_W, zc), pchip(COWL_Z, COWL_CROWN, zc)


def _arch(z, theta):
    """アーチの上の点（θ は π＝左の足元 → 0＝右の足元）。"""
    w, crown = cowl_dims(z)
    c, s = math.cos(theta), math.sin(theta)
    x = w * math.copysign(abs(c) ** (2 / COWL_N), c)
    base0 = roof(z, 0.0) + COWL_BASE_LIFT
    y = roof(z, x) + COWL_BASE_LIFT + (crown - base0) * abs(s) ** (2 / COWL_N)
    return Vector((x, y, z))


def cowl_point(z, theta, off=0.0):
    """カバーの面の点（z、アーチの角度 θ）を外向きの法線へ off だけ浮かせた点と、その法線。"""
    e = 1e-3
    p = _arch(z, theta)
    dz = _arch(z + e, theta) - _arch(z - e, theta)
    dt = _arch(z, theta + e) - _arch(z, theta - e)
    n = dt.cross(dz)
    if n.y < 0:
        n = -n
    n.normalize()
    return p + n * off, n


def cowl_top(x, z):
    """カバーの上面の高さ（カバーの外なら屋根）。ローターの部品・ビーコンの台座の足元に使う。"""
    if z < COWL_Z[0] or z > COWL_Z[-1]:
        return roof(z, x)
    w, crown = cowl_dims(z)
    if abs(x) >= w:
        return roof(z, x)
    base0 = roof(z, 0.0) + COWL_BASE_LIFT
    return roof(z, x) + COWL_BASE_LIFT + (crown - base0) * (1 - (abs(x) / w) ** COWL_N) ** (1 / COWL_N)


def _theta_metric(z, theta):
    """θ を 1 ラジアン動かしたときの面の上の長さ。"""
    e = 1e-3
    return (_arch(z, theta + e) - _arch(z, theta - e)).length / (2 * e)


def build_cowl(m: GMesh):
    rings = []
    zs = []
    for i in range(len(COWL_Z) - 1):          # 区間を 2 つに分けてなめらかに
        zs += [COWL_Z[i], (COWL_Z[i] + COWL_Z[i + 1]) / 2]
    zs.append(COWL_Z[-1])
    for z in zs:
        w, _ = cowl_dims(z)
        xs = w + COWL_SKIRT
        ring = [(-xs, roof(z, -xs) - 0.01, z)]
        for k in range(COWL_K + 1):
            ring.append(tuple(_arch(z, math.pi * (1 - k / COWL_K))))
        ring.append((xs, roof(z, xs) - 0.01, z))
        rings.append(ring)

    def hint(i, k):
        a, b = Vector(rings[i][k]), Vector(rings[i + 1][k + 1])
        mid = (a + b) / 2
        return mid - Vector((0.0, roof(mid.z, 0.0) - 0.4, mid.z))

    m.loft(rings, "BodyPaint", closed=False, weld="cowl:loft", hint_fn=hint)
    # 前：ドアの後ろの端より後ろ（z -0.545）に寄せた面。後ろ：屋根にもぐる先
    front = Vector((0.0, 3.575, -0.545))
    rear = Vector((0.0, roof(1.72, 0.0) - 0.03, 1.72))
    for ring, apex, out in ((rings[0], front, Vector((0, 0.2, -1))), (rings[-1], rear, Vector((0, 0.4, 1)))):
        for k in range(len(ring) - 1):
            m._oriented([ring[k], ring[k + 1], tuple(apex)], tuple(out), "BodyPaint", smooth=True, weld="cowl:loft")
    m.weld_groups["cowl:loft"] = len(rings[0]) * len(rings) + 2


def _outline(zc, tc, hz, ht, n=16, scale=1.0, power=4.0):
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        pts.append((zc + scale * hz * math.copysign(abs(c) ** (2 / power), c), tc + scale * ht * math.copysign(abs(s) ** (2 / power), s)))
    return pts


def build_intake(m: GMesh, side):
    """カバーの横の吸気口：白い縁（Trim）・暗い奥（Rubber）・金属の格子（Metal）。"""
    zc = -0.10
    tc = math.radians(160.0 if side < 0 else 20.0)
    hz, ht = 0.19, math.radians(13.0)
    outer = _outline(zc, tc, hz, ht)
    inner = _outline(zc, tc, hz, ht, scale=0.85)
    po = [cowl_point(z, t, -0.005)[0] for z, t in outer]
    pt = [cowl_point(z, t, 0.022)[0] for z, t in outer]
    it = [cowl_point(z, t, 0.022)[0] for z, t in inner]
    ib = [cowl_point(z, t, 0.004)[0] for z, t in inner]
    centre, normal = cowl_point(zc, tc, 0.004)
    n = len(outer)
    for k in range(n):
        j = (k + 1) % n
        mid_o = (po[k] + po[j]) / 2
        m._oriented([tuple(po[k]), tuple(po[j]), tuple(pt[j]), tuple(pt[k])], tuple(mid_o - centre), "Trim")
        m._oriented([tuple(pt[k]), tuple(pt[j]), tuple(it[j]), tuple(it[k])], tuple(normal), "Trim")
        m._oriented([tuple(it[k]), tuple(it[j]), tuple(ib[j]), tuple(ib[k])], tuple(centre - (it[k] + it[j]) / 2), "Trim")
        m._oriented([tuple(centre), tuple(ib[k]), tuple(ib[j])], tuple(normal), "Rubber")
    for dz in (-0.105, -0.035, 0.035, 0.105):
        a, na = cowl_point(zc + dz, tc - ht * 0.82, 0.010)
        b, _ = cowl_point(zc + dz, tc + ht * 0.82, 0.010)
        m.box_between(tuple(a), tuple(b), 0.014, 0.012, "Metal", up=tuple(na))


def build_exhaust(m: GMesh, side):
    """斜め後ろ上へ向いた排気管（金属の外側、暗い内側）。"""
    base = Vector((side * 0.30, 3.64, 0.98))
    d = Vector((side * 0.221, 0.281, 0.934)).normalized()
    L = 0.38
    m.lathe_axis(base, d, [(0.0, 0.092), (0.55 * L, 0.098), (0.92 * L, 0.104), (L, 0.106)], "Metal", n=14, weld=f"exh:{side}:out")
    tip = base + d * L
    m.lathe_axis(tip, d, [(0.0, 0.106), (0.0, 0.080)], "Metal", n=14, smooth=False)          # 先の縁（輪。後ろ向き）
    m.lathe_axis(base, d, [(0.62 * L, 0.080), (L, 0.080)], "Rubber", n=14, outward=False, weld=f"exh:{side}:in")
    m.lathe_axis(base + d * (0.62 * L), d, [(0.0, 0.080), (0.0, 0.0)], "Rubber", n=14, smooth=False)   # 奥のふた


def _strip(m: GMesh, path, half_w, mat, lift=0.004, depth=0.005):
    """カバーの面にそった細い帯（上の面と両側の壁）。path は [(z, θ)]。"""
    tops, walls = [], []
    for z, t in path:
        dt = half_w / max(_theta_metric(z, t), 1e-6)
        tops.append((cowl_point(z, t - dt, lift)[0], cowl_point(z, t + dt, lift)[0]))
        walls.append((cowl_point(z, t - dt, lift - depth)[0], cowl_point(z, t + dt, lift - depth)[0]))
    for i in range(len(path) - 1):
        (a0, a1), (b0, b1) = tops[i], tops[i + 1]
        (w0, w1), (v0, v1) = walls[i], walls[i + 1]
        n = cowl_point(*path[i])[1]
        m._oriented([tuple(a0), tuple(a1), tuple(b1), tuple(b0)], tuple(n), mat)
        side_dir = (a0 - a1).normalized()
        m._oriented([tuple(a0), tuple(b0), tuple(v0), tuple(w0)], tuple(side_dir), mat)
        m._oriented([tuple(a1), tuple(b1), tuple(v1), tuple(w1)], tuple(-side_dir), mat)


def _strip_z(m: GMesh, z, t0, t1, half_w, mat, steps=16, lift=0.0048, depth=0.005):
    """z を固定してアーチにそって θ を t0 → t1 へ進む帯（縦の継ぎ目）。"""
    tops, walls = [], []
    for k in range(steps + 1):
        t = t0 + (t1 - t0) * k / steps
        p, n = cowl_point(z, t, lift)
        tops.append((p + Vector((0, 0, -half_w)), p + Vector((0, 0, half_w)), n))
        q, _ = cowl_point(z, t, lift - depth)
        walls.append((q + Vector((0, 0, -half_w)), q + Vector((0, 0, half_w))))
    for k in range(steps):
        (a0, a1, n), (b0, b1, _) = tops[k], tops[k + 1]
        (w0, w1), (v0, v1) = walls[k], walls[k + 1]
        m._oriented([tuple(a0), tuple(a1), tuple(b1), tuple(b0)], tuple(n), mat)
        m._oriented([tuple(a0), tuple(b0), tuple(v0), tuple(w0)], (0, 0, -1), mat)
        m._oriented([tuple(a1), tuple(b1), tuple(v1), tuple(w1)], (0, 0, 1), mat)


def build_cowl_details(m: GMesh):
    # 継ぎ目：横（左右）と縦（上をまたぐ 2 本）
    for t_deg in (128.0, 52.0):
        t = math.radians(t_deg)
        path = [(-0.45 + (0.86 + 0.45) * i / 12, t) for i in range(13)]
        _strip(m, path, 0.007, "Charcoal")
    for z in (0.42, 0.90):
        _strip_z(m, z, math.radians(176.0), math.radians(4.0), 0.007, "Charcoal")
    # リベット：横の継ぎ目の外側と、縦の継ぎ目の両側
    rivets = []
    for t_deg, z0 in ((131.0, -0.33), (49.0, -0.45)):
        z = z0
        while z <= 0.80:
            rivets.append((z, math.radians(t_deg)))
            z += 0.115
    for z in (0.42, 0.90):
        for k in range(5):
            t = math.radians(150.0 - 30.0 * k)
            rivets += [(z - 0.022, t), (z + 0.022, t)]
    for z, t in rivets:
        p, n = cowl_point(z, t, 0.0)
        m.stud(tuple(p), tuple(n), 0.013, 0.006, "BodyPaint")
    # 留め具（横の下の方）
    for t_deg in (172.0, 8.0):
        for z in (0.35, 0.75):
            p, n = cowl_point(z, math.radians(t_deg), 0.005)
            u, w = frame_from(n, (0, 0, 1))
            m.box(tuple(p), (0.022, 0.010, 0.06), "Charcoal", rot=Matrix((w, n, u)).transposed())
    return len(rivets)


def build_antennas(m: GMesh):
    """屋根の VHF のブレードアンテナと GPS（機体の真ん中の線の上。ドアの通り道より内側）。"""
    y0 = roof(-1.075, 0.0)
    prof = [(-1.20, y0 - 0.01), (-1.00, y0 - 0.01), (-0.95, y0 + 0.23), (-1.03, y0 + 0.23)]
    m.extrude_x(prof, -0.014, 0.014, "Charcoal")
    m.box((0.0, y0 + 0.004, -1.10), (0.05, 0.015, 0.24), "Charcoal", chamfer=0.004)
    yg = roof(-1.60, 0.0)
    m.lathe_axis((0.0, yg - 0.008, -1.60), (0, 1, 0), [(0.0, 0.085), (0.034, 0.085), (0.055, 0.065), (0.064, 0.0)], "Trim", n=16, crease_deg=40.0)


def build_beacon_pedestal(m: GMesh):
    """ビーコンの台座（Charcoal と金属の縁）。返り値はビーコンの丸い頭を載せる高さ。"""
    z = 1.42
    yb = cowl_top(0.0, z) - 0.01
    m.lathe_axis((0.0, yb, z), (0, 1, 0), [(0.0, 0.065), (0.06, 0.05), (0.10, 0.046)], "Charcoal", n=16, weld="beacon:ped")
    m.lathe_axis((0.0, yb + 0.10, z), (0, 1, 0), [(0.0, 0.046), (0.0, 0.058), (0.008, 0.058), (0.008, 0.054)], "Metal", n=16, smooth=False)
    return yb + 0.108


def build_roof_kit():
    """屋根の部品一式（Body）と、灯を載せる場所。"""
    m = GMesh()
    build_cowl(m)
    for side in (-1, 1):
        build_intake(m, side)
        build_exhaust(m, side)
    n_rivets = build_cowl_details(m)
    build_antennas(m)
    beacon_y = build_beacon_pedestal(m)
    anchors = {"beacon": Vector((0.0, beacon_y, 1.42)), "rivets": n_rivets}
    return m, anchors


# ---------------------------------------------------------------- ドアの通り道（ビルド時に計算する）
#
# ドアは屋根の曲線より内側を通る真っすぐなヒンジ（p0 → p1）で回るので、開くと屋根の上で |x| 0.19 まで内側へ入り、
# 前は z -2.5 まで届く。屋根の上の部品は、この表（z ごとのいちばん内側の |x|）より内側に置く。
DOOR_SPEC = SPEC["door"]
HINGE_L = [Vector(p) for p in DOOR_SPEC["hinge_L"]]
KEEPOUT: dict = {}            # z のビン（0.05 m）→ 屋根の上に出たドアのいちばん内側の |x|
CEILING_BAND: dict = {}       # 開くドアが天井の内張りより下に入る範囲（内装の部品はここに置かない）


def _rodrigues(p, a, d, ang):
    v = p - a
    c, s = math.cos(ang), math.sin(ang)
    return a + v * c + d.cross(v) * s + d * d.dot(v) * (1 - c)


def door_rotated_points(door_pts_g, side, frac):
    """ドアの点（Godot）を、開き frac（0〜1）だけヒンジのまわりに回す。"""
    sx = 1.0 if side == "L" else -1.0
    p0 = Vector((sx * HINGE_L[0].x, HINGE_L[0].y, HINGE_L[0].z))
    p1 = Vector((sx * HINGE_L[1].x, HINGE_L[1].y, HINGE_L[1].z))
    d = (p1 - p0).normalized()
    ang = (-1.0 if side == "L" else 1.0) * math.radians(DOOR_SPEC["open_deg"]) * frac
    return [_rodrigues(p, p0, d, ang) for p in door_pts_g]


def compute_door_keepout(door_gmesh, step_deg=3.0):
    """左ドアの殻の点を 3° ごとに 90° まで回し、屋根より上に出た点の z ごとのいちばん内側の |x|（左右同じ）と、
    天井の内張りより下に入る点の範囲を求める。"""
    from hb_shell import CABIN_Z0, CABIN_Z1
    pts = [G(v) for v in door_gmesh.v]
    KEEPOUT.clear()
    band = []
    n = int(round(DOOR_SPEC["open_deg"] / step_deg))
    for k in range(1, n + 1):
        for q in door_rotated_points(pts, "L", k / n):
            y_roof = section_extent(q.z, x=q.x)
            if y_roof is not None and q.y > y_roof:
                b = round(math.floor(q.z / 0.05) * 0.05, 2)
                KEEPOUT[b] = min(KEEPOUT.get(b, 9.0), abs(q.x))
            if CABIN_Z0 < q.z < CABIN_Z1:
                y_in = section_extent(q.z, x=q.x, inner=True)
                if y_in is not None and q.y < y_in - 0.005 and q.y > SPEC["floor_y"]:
                    band.append(q)
    CEILING_BAND.clear()
    if band:
        CEILING_BAND.update({"x": (round(min(abs(q.x) for q in band), 3), round(max(abs(q.x) for q in band), 3)),
                             "y": (round(min(q.y for q in band), 3), round(max(q.y for q in band), 3)),
                             "z": (round(min(q.z for q in band), 3), round(max(q.z for q in band), 3)), "points": len(band)})
    return dict(sorted(KEEPOUT.items()))


def door_keepout(z):
    """z で、屋根の上の部品が置ける |x| の上限（ドアのいちばん内側）。ドアが来ない z は 9。"""
    b = round(math.floor(z / 0.05) * 0.05, 2)
    vals = [KEEPOUT.get(round(b + d, 2), 9.0) for d in (-0.05, 0.0, 0.05)]
    return min(vals)


# ---------------------------------------------------------------- 機首
def front_surface(x, y):
    """機首の前の面で、横 x・高さ y の点と法線（z を二分法で探す）。"""
    from hb_parts import side_surface
    lo, hi = -3.14, -2.3
    for _ in range(40):
        mid = (lo + hi) / 2
        w = section_extent(mid, y=y)
        if w >= abs(x):
            hi = mid
        else:
            lo = mid
    z = hi
    p, n = side_surface(y, z, 1 if x >= 0 else -1)
    return p, n


def build_nose_kit(m: GMesh, anchors):
    from hb_parts import _disc, _ring, side_surface
    # ワイヤーカッター（上：屋根の真ん中、下：機首の腹）
    y_top = roof(-2.06, 0.0)
    m.box((0.0, y_top + 0.005, -2.06), (0.06, 0.04, 0.18), "Charcoal", chamfer=0.008)
    dy = y_top - 3.30
    m.extrude_x([(-1.98, 3.30 + dy - 0.01), (-2.14, 3.30 + dy - 0.01), (-2.34, 3.47 + dy), (-2.30, 3.50 + dy), (-1.98, 3.37 + dy)], -0.012, 0.012, "Metal")
    y_bot = belly_y(-2.42, 0.0)
    m.box((0.0, y_bot - 0.005, -2.42), (0.06, 0.04, 0.20), "Charcoal", chamfer=0.008)
    dy = y_bot - 0.575
    m.extrude_x([(-2.32, 0.585 + dy), (-2.52, 0.585 + dy), (-2.66, 0.40 + dy), (-2.62, 0.37 + dy), (-2.36, 0.50 + dy)], -0.012, 0.012, "Metal")
    # ピトー管（左右、帯の下）
    for s in (-1, 1):
        base, n = side_surface(1.10, -2.92, s)
        tip = base + n * 0.09
        m.tube(tuple(base - n * 0.01), tuple(tip), 0.012, "Metal", n=6)
        m.lathe_axis(tuple(tip), (0, 0, -1), [(0.0, 0.014), (0.176, 0.014), (0.187, 0.009), (0.22, 0.009)], "Metal", n=8, crease_deg=40.0, cap1="flat")
    # あごのサーチライト（白い玉・黒い柱と縁・金属の反射の輪）。光るレンズは LandingLight
    c = Vector((0.0, 0.62, -2.80))
    sphere = [(-0.13 * math.cos(math.pi * k / 8), 0.13 * math.sin(math.pi * k / 8)) for k in range(9)]
    m.lathe_axis(tuple(c), (0, 0, 1), sphere, "Trim", n=16, weld="nose:ball")
    m.tube((0.0, 0.80, -2.80), (0.0, 0.72, -2.80), 0.07, "Charcoal", n=12, r1=0.06)
    ld = Vector((0.0, -0.45, -0.89)).normalized()
    m.lathe_axis(tuple(c + ld * 0.06), tuple(ld), [(0.0, 0.10), (0.071, 0.098)], "Charcoal", n=16, weld="nose:bezel")
    _ring(m, c + ld * 0.131, tuple(ld), 0.075, 0.098, "Metal", n=16)
    anchors["landing"] = (c, ld)
    # ミラー（左右。顔の帯より外。操縦席の方を向く）
    for s in (-1, 1):
        base, n = side_surface(1.60, -2.64, s)
        H = Vector((s * 1.45, 1.80, -2.95))
        f = (Vector((s * 0.77, 2.05, -1.35)) - H).normalized()
        back = H - f * 0.035
        m.polyline_tube([tuple(base - n * 0.01), tuple(base + n * 0.09 + Vector((0, 0.04, -0.05))), tuple(back)], 0.018, "Charcoal", n=6)
        m.lathe_axis(tuple(back), tuple(f), [(0.0, 0.0), (0.018, 0.055), (0.042, 0.08), (0.06, 0.085)], "Charcoal", n=12, weld=f"mirror{s}")
        _disc(m, H + f * 0.026, tuple(f), 0.078, "Metal", n=12)
        _ring(m, H + f * 0.0262, tuple(f), 0.078, 0.085, "Charcoal", n=12)
    # ワイパー（左右。風防の下の方、ひさしの線より下）
    for s in (-1, 1):
        piv, npv = front_surface(s * 0.50, 1.545)
        park, npk = front_surface(s * 0.10, 1.60)
        m.lathe_axis(tuple(piv), tuple(npv), [(0.0, 0.022), (0.016, 0.02), (0.022, 0.0)], "Charcoal", n=8, weld=f"wiper{s}")
        a = piv + npv * 0.02
        b = park + npk * 0.02
        m.box_between(tuple(a), tuple(b), 0.018, 0.012, "Charcoal", up=tuple(npv))
        mid = (piv + park) / 2 + (npv + npk).normalized() * 0.012
        dirv = (park - piv).normalized()
        m.box_between(tuple(mid - dirv * 0.18), tuple(mid + dirv * 0.18), 0.014, 0.02, "Rubber", up=tuple(npv))


def build_canopy_gaskets(m: GMesh):
    """風防のゴム枠：まん中の柱（A0）、下の縁（A2）、前の縁、後ろのアーチ（屋根の梁）。
    A1 の Body 側と、ドアの前の端のすぐ前には付けない（開くドアの通り道）。"""
    from hb_shell import ANCHOR_IDX, RING, arc_strip, ring_strip, stations
    zs = [z for z in stations() if -3.109 - 1e-6 <= z <= -2.29]
    A0, A1, A2 = ANCHOR_IDX[0], ANCHOR_IDX[1], ANCHOR_IDX[2]
    du_post = 0.15
    ring_strip(m, zs, RING - du_post, RING + du_post, "Rubber", lift=0.006)
    for u in (A2, RING - A2):
        # ドアの前の端（z -2.25）の手前で止める（開き始めのドアの前の枠が少し前へ動いて通る）
        ring_strip(m, [z for z in stations() if -3.06 <= z <= -2.39], lambda z, u=u: u - 0.10, lambda z, u=u: u + 0.10, "Rubber", lift=0.005)
    arc_strip(m, -3.109, -3.080, RING - A2, A2, "Rubber", lift=0.006, steps=18)
    # 後ろのアーチ：ドアの通り道（door_keepout）より内側だけ
    ko = door_keepout(-2.27) - 0.008
    u_lim = _u_for_x(-2.27, ko)
    arc_strip(m, -2.288, -2.253, RING - u_lim, u_lim, "Rubber", lift=0.005, steps=10)
    # A1〜A2 の風防側の後ろの帯は付けない（ドア自身の前の枠と重なり、開き始めのドアが通る）


def _u_for_x(z, x_abs):
    """左側（u 0〜HALF）で |x| が x_abs になる u。"""
    from hb_shell import HALF
    lo, hi = 0.0, float(HALF) / 2
    from hb_shell import ring_param_point
    for _ in range(40):
        mid = (lo + hi) / 2
        if abs(ring_param_point(z, mid)[0]) < x_abs:
            lo = mid
        else:
            hi = mid
    return lo


def build_door_kit(side):
    """ドア（Door_L / Door_R）に付く部品：ガラスの枠（上の枠は A1 から 8.5〜11.5 cm 下）、取っ手。"""
    from hb_shell import ANCHOR_IDX, RING, arc_strip, ring_strip, ring_u_at_distance, stations
    m = GMesh()
    A1, A2 = ANCHOR_IDX[1], ANCHOR_IDX[2]
    zs = [z for z in stations() if DOOR_SPEC["front_z"] - 1e-6 <= z <= DOOR_SPEC["rear_z"] + 1e-6]
    if side == "L":
        a1, a2, sgn = A1, A2, 1.0
    else:
        a1, a2, sgn = RING - A1, RING - A2, -1.0

    def u_top(z, s):
        return ring_u_at_distance(z, a1, s, sgn)

    ring_strip(m, zs, lambda z: min(u_top(z, 0.085), u_top(z, 0.115)), lambda z: max(u_top(z, 0.085), u_top(z, 0.115)), "Rubber", lift=0.005)
    ring_strip(m, zs, a2 - 0.10, a2 + 0.10, "Rubber", lift=0.005)
    for z0, z1 in ((DOOR_SPEC["front_z"] + 0.002, DOOR_SPEC["front_z"] + 0.035), (DOOR_SPEC["rear_z"] - 0.035, DOOR_SPEC["rear_z"] - 0.002)):
        zm = (z0 + z1) / 2
        ua = u_top(zm, 0.085)
        if side == "L":
            arc_strip(m, z0, z1, ua, a2 - 0.10, "Rubber", lift=0.006, steps=10)
        else:
            arc_strip(m, z0, z1, a2 + 0.10, ua, "Rubber", lift=0.006, steps=10)
    from hb_parts import side_surface
    s = -1 if side == "L" else 1
    p, n = side_surface(1.62, -0.80, s)
    u, w = frame_from(n, (0, 0, 1))
    rot = Matrix((w, n, u)).transposed()
    m.box(tuple(p + n * 0.002), (0.07, 0.004, 0.22), "Rubber", rot=rot)
    m.box(tuple(p + n * 0.024), (0.030, 0.022, 0.18), "Trim", rot=rot, chamfer=0.006)
    for dz in (-0.07, 0.07):
        m.box(tuple(p + n * 0.012 + u * dz), (0.02, 0.02, 0.02), "Trim", rot=rot)
    return m


def build_hinge_parts(m: GMesh):
    """ドアのヒンジ：金属の関節（ヒンジの軸の上）と、通り道より内側の胴体色のカバー。"""
    for sx in (-1, 1):
        p0 = Vector((sx * HINGE_L[0].x, HINGE_L[0].y, HINGE_L[0].z))
        p1 = Vector((sx * HINGE_L[1].x, HINGE_L[1].y, HINGE_L[1].z))
        d = (p1 - p0).normalized()

        def on_axis(z):
            return p0 + d * ((z - p0.z) / d.z)

        m.tube(tuple(on_axis(-2.31)), tuple(on_axis(-2.19)), 0.04, "Metal", n=12)
        m.tube(tuple(on_axis(-0.60)), tuple(on_axis(-0.47)), 0.042, "Metal", n=12)
        for xc, za, zb in ((0.17, -2.24, -2.02), (0.23, -0.80, -0.58)):
            x = sx * xc
            ya = roof(za, x) - 0.01
            yb = roof(zb, x) - 0.01
            a, b = Vector((x, ya, za)), Vector((x, yb, zb))
            L = (b - a).length
            m.lathe_axis(tuple(a), tuple((b - a).normalized()), [(0.0, 0.0), (0.12 * L, 0.035), (0.35 * L, 0.05), (0.7 * L, 0.045), (L, 0.0)], "BodyPaint",
                         n=10, weld=f"hingepod{sx}{xc}")


def build_hoist(m: GMesh):
    """救助用のホイスト（左のドアの後ろ上。ドアの通り道より後ろ、たたんだ・広げたポッドより上）。"""
    m.box((-0.37, 3.68, -0.44), (0.12, 0.10, 0.12), "Charcoal", chamfer=0.012)
    m.box_between((-0.42, 3.66, -0.44), (-1.78, 3.60, -0.44), 0.07, 0.06, "Trim", up=(0, 1, 0), chamfer=0.012)
    yr = roof(-0.44, -0.95)
    m.tube((-0.95, 3.60, -0.44), (-0.95, yr - 0.01, -0.44), 0.022, "Charcoal", n=8)
    a = Vector((-1.62, 3.48, -0.44))
    L = 0.38
    m.lathe_axis(tuple(a), (-1, 0, 0), [(0.0, 0.045), (0.06 * L, 0.07), (0.30 * L, 0.072)], "Trim", n=12, weld="hoist:a", cap0="flat")
    m.lathe_axis(tuple(a), (-1, 0, 0), [(0.32 * L, 0.078), (0.68 * L, 0.078)], "Charcoal", n=12, weld="hoist:drum", cap0="flat", cap1="flat")
    m.lathe_axis(tuple(a), (-1, 0, 0), [(0.70 * L, 0.072), (0.94 * L, 0.07), (L, 0.045)], "Trim", n=12, weld="hoist:b", cap1="flat")
    m.tube((-1.95, 3.40, -0.44), (-1.95, 3.26, -0.44), 0.007, "Charcoal", n=6)
    m.box((-1.95, 3.22, -0.44), (0.07, 0.09, 0.06), "Trim", chamfer=0.01)
    m.polyline_tube([(-1.95, y, z) for y, z in ((3.175, -0.44), (3.12, -0.44), (3.09, -0.465), (3.10, -0.49), (3.13, -0.495))], 0.012, "Metal", n=6)


FLANK_PANELS = [(0.12, 0.98, 1.94, 2.20), (-0.40, 0.98, 1.50, 1.90)]   # 側面のパネルの外形（z0, z1, y0, y1）。デカールの継ぎ目に使う


def build_flank_and_belly(m: GMesh, bay: GMesh, anchors):
    from hb_parts import _disc, _ring, side_surface
    # 側面の通気口（左右）：枠・暗い奥・傾けた羽根
    for s in (-1, 1):
        p, n = side_surface(2.06, 0.54, s)
        u, w = frame_from(n, (0, 0, 1))
        rot = Matrix((w, n, u)).transposed()
        m.box(tuple(p + n * 0.003), (0.15, 0.004, 0.46), "Rubber", rot=rot)
        for dz in (-0.23, 0.23):
            m.box(tuple(p + n * 0.006 + u * dz), (0.16, 0.012, 0.02), "Charcoal", rot=rot)
        for dy in (-0.075, 0.075):
            m.box(tuple(p + n * 0.006 + w * dy), (0.02, 0.012, 0.48), "Charcoal", rot=rot)
        tilt = Matrix.Rotation(math.radians(35.0), 3, Vector((0, 0, 1)))
        for k in range(4):
            q = p + n * 0.008 + w * (-0.039 + 0.026 * k)
            m.box(tuple(q), (0.018, 0.006, 0.44), "Charcoal", rot=rot @ tilt)
    # 給油口（左）
    p, n = side_surface(1.62, 0.70, -1)
    _ring(m, p + n * 0.004, tuple(n), 0.050, 0.068, "Charcoal", n=14)
    _disc(m, p + n * 0.007, tuple(n), 0.05, "Metal", n=14)
    u, w = frame_from(n, (0, 0, 1))
    m.box(tuple(p + n * 0.011), (0.012, 0.008, 0.05), "Metal", rot=Matrix((w, n, u)).transposed())
    # 外部電源のふた（右、濃紺の中）
    p, n = side_surface(1.02, 0.42, 1)
    u, w = frame_from(n, (0, 0, 1))
    rot = Matrix((w, n, u)).transposed()
    for dz in (-0.094, 0.094):
        m.box(tuple(p + n * 0.004 + u * dz), (0.14, 0.006, 0.012), "Charcoal", rot=rot)
    for dy in (-0.064, 0.064):
        m.box(tuple(p + n * 0.004 + w * dy), (0.012, 0.006, 0.20), "Charcoal", rot=rot)
    m.box(tuple(p + n * 0.007 + u * 0.06), (0.03, 0.008, 0.02), "Metal", rot=rot)
    # 腹のストロボ（覆い。光るレンズは Beacon に入れる）
    yb = belly_y(-1.80, 0.0)
    m.lathe_axis((0.0, yb + 0.015, -1.80), (0, -1, 0), [(0.0, 0.09), (0.045, 0.075)], "Charcoal", n=14, weld="belly:strobe", cap1="flat")
    anchors["belly_strobe"] = Vector((0.0, yb - 0.03, -1.80))
    # 腹のアンテナ（前：左、後ろ：右）
    for x, za, zb in ((-0.45, -0.78, -0.60), (0.45, 1.17, 1.33)):
        ya, yb2 = belly_y(za, x), belly_y(zb, x)
        prof = [(za, ya + 0.01), (zb, yb2 + 0.01), (zb + 0.04, yb2 - 0.17), (za + 0.06, ya - 0.17)]
        m.extrude_x(prof, x - 0.012, x + 0.012, "Charcoal")
        m.box((x, (ya + yb2) / 2 + 0.004, (za + zb) / 2), (0.05, 0.012, zb - za + 0.04), "Charcoal", chamfer=0.003)
    # カーゴフック（後ろ。ハッチの開口の外）
    zc = 1.32
    yh = belly_y(zc, 0.0)
    m.box((0.0, yh - 0.015, zc), (0.18, 0.06, 0.16), "Charcoal", chamfer=0.012)
    m.tube((-0.05, yh - 0.03, zc), (0.05, yh - 0.03, zc), 0.02, "Metal", n=8)
    m.polyline_tube([(0.0, yh - 0.03, zc), (0.0, yh - 0.095, zc - 0.03), (0.0, yh - 0.125, zc - 0.06), (0.0, yh - 0.11, zc - 0.09)], 0.016, "Metal", n=6)
    # 床下ハッチの関節（ハッチの軸の上。回る軸のまわりの円柱なので動かなくてよい）
    hw = SPEC["hatch"]["half_w"]
    yax = SPEC["belly_y"] - 0.03
    for sx in (-1, 1):
        for za, zb in ((-0.15, 0.10), (0.275, 0.525), (0.70, 0.95)):
            bay.tube((sx * hw, yax, za), (sx * hw, yax, zb), 0.034, "Charcoal", n=8)


def build_landing_and_belly_lenses(anchors):
    """光るレンズ（LandingLight：あごのサーチライト、Beacon に足す：腹のストロボ）。"""
    land = GMesh()
    c, ld = anchors["landing"]
    land.lathe_axis(tuple(c), tuple(ld), [(0.120, 0.080), (0.132, 0.072), (0.142, 0.050), (0.150, 0.0)], "LampWhite", n=16, weld="landing:lens")
    belly = GMesh()
    b = anchors["belly_strobe"]
    belly.lathe_axis(tuple(b), (0, -1, 0), [(0.0, 0.07), (0.025, 0.06), (0.045, 0.035), (0.05, 0.0)], "NavRed", n=14, weld="beacon:belly")
    return land, belly


def build_fuselage_kit(door_gmesh_l):
    """胴体の外の作り込み（Phase 6）。返り値：{部品名: (GMesh, tag)} と灯の場所。"""
    compute_door_keepout(door_gmesh_l)
    anchors = {}
    out = {}
    body = GMesh()
    build_nose_kit(body, anchors)
    build_hinge_parts(body)
    build_hoist(body)
    bay = GMesh()
    build_flank_and_belly(body, bay, anchors)
    gaskets = GMesh()
    build_canopy_gaskets(gaskets)
    out["Body"] = [(body, "kit"), (gaskets, "gasket")]
    out["DropBayFrame"] = [(bay, "bay")]
    out["Door_L"] = [(build_door_kit("L"), "gasket")]
    out["Door_R"] = [(build_door_kit("R"), "gasket")]
    land, belly = build_landing_and_belly_lenses(anchors)
    out["LandingLight"] = [(land, "kit")]
    out["Beacon"] = [(belly, "kit")]
    return out, anchors

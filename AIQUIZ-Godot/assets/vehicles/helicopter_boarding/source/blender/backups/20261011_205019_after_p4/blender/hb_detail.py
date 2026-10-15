"""胴体の外の作り込み：屋根のエンジンカバー（吸気口・排気管・継ぎ目・リベット・留め具）、アンテナ、ビーコンの台座。

すべて Godot の座標（地面基準、機首 -z）。部品は "Body" に入れる（返り値の GMesh）。ドアの開く通り道・ジェットのたたむ範囲・
ローターの羽根の高さの決まりはビルダーのチェックで確かめる。
"""
from __future__ import annotations

import math

from mathutils import Matrix, Vector

from hb_common import GMesh, frame_from, pchip, section_extent

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

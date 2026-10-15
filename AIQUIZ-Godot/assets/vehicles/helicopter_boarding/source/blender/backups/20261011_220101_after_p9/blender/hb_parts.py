"""胴体以外の部品：床・計器盤・座席・操縦かん・ベルト・後ろの仕切り・マストとローター・尾・スキッドとステップ・灯・床下ハッチ。

すべて Godot の座標（地面基準）で書く。数値は設計図の JSON（SPEC）。返すのは {部品名: GMesh}。
"""
from __future__ import annotations

import math

from mathutils import Matrix, Vector

from hb_common import (BP, HAZARD_BLACK, HAZARD_RED, HAZARD_YELLOW, HEAT_BLUE, HEAT_BRONZE, HEAT_STRAW, NAVY, SPEC, GMesh, body_params, pchip,
                       section_extent, section_point, smoothstep)
from hb_shell import CABIN_Z0, CABIN_Z1

FLOOR_Y = SPEC["floor_y"]
BELLY_Y = SPEC["belly_y"]
SEAT = SPEC["seat"]
DASH = SPEC["dash"]
DOOR = SPEC["door"]
HATCH = SPEC["hatch"]
ROTOR = SPEC["rotor"]
TAIL = SPEC["tail_rotor"]
BOOM = SPEC["boom"]
STAB = SPEC["stab"]
SKID = SPEC["skid"]
STEP = SPEC["step"]
MAST = SPEC["mast_fairing"]
WALL = BP["wall"]


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def inner_half_width(y, z):
    return section_extent(z, y=y, inner=True)


# ---------------------------------------------------------------- 床・仕切り・荷室の井戸

def build_interior():
    m = GMesh()
    hz0, hz1 = HATCH["z"]
    hw = HATCH["half_w"]
    zs = [CABIN_Z0 + (CABIN_Z1 - CABIN_Z0) * i / 24 for i in range(25)]
    for z in (hz0, hz1):
        zs.append(z)
    zs = sorted(set(round(z, 5) for z in zs))
    # 床（上面だけ。端は内張りに少しもぐらせる）。ハッチの上は穴
    for z0, z1 in zip(zs[:-1], zs[1:]):
        w0 = inner_half_width(FLOOR_Y, z0) + 0.02
        w1 = inner_half_width(FLOOR_Y, z1) + 0.02
        over_hatch = hz0 <= z0 and z1 <= hz1
        spans = [(-1, -hw), (hw, 1)] if over_hatch else [(-1, 1)]
        for a, b in spans:
            xa0 = -w0 if a == -1 else a
            xb0 = w0 if b == 1 else b
            xa1 = -w1 if a == -1 else a
            xb1 = w1 if b == 1 else b
            m.face([(xa0, FLOOR_Y, z0), (xa1, FLOOR_Y, z1), (xb1, FLOOR_Y, z1), (xb0, FLOOR_Y, z0)], "Floor")
    # 床の滑り止め（座席の前の足元に 3 本ずつ）
    for sx in (-1, 1):
        for i in range(3):
            z = DASH["back_z"] + 0.18 + i * 0.16
            m.box((sx * SEAT["x"], FLOOR_Y + 0.006, z), (0.70, 0.012, 0.05), "Rubber")
    # 後ろの仕切り（z = CABIN_Z1 の内側の断面をふさぐ）
    p = body_params(CABIN_Z1)
    ring = [section_point(p, 2 * math.pi * i / 48, WALL) for i in range(48)]
    c = (0.0, sum(y for _, y in ring) / 48, CABIN_Z1)
    for i in range(48):
        a = ring[i]
        b = ring[(i + 1) % 48]
        m._oriented([c, (a[0], a[1], CABIN_Z1), (b[0], b[1], CABIN_Z1)], (0, 0, -1), "Interior")
    # 計器盤のうしろのふさぎ（風防の下、床から計器盤まで）：内側の断面にそった 12 角（外板から出ない）
    zf = CABIN_Z0
    ys = [0.77 + (DASH["bottom_y"] - 0.77) * k / 5 for k in range(6)]
    right = [(inner_half_width(y, zf) - 0.01, y) for y in ys]
    poly = [(x, y, zf) for x, y in right] + [(-x, y, zf) for x, y in reversed(right)]
    m._oriented(poly, (0, 0, 1), "Interior")
    return m


def build_bay():
    """床下ハッチのまわり：井戸の壁（DropBayInterior）と、腹のふちの枠（DropBayFrame）。"""
    well = GMesh()
    frame = GMesh()
    hz0, hz1 = HATCH["z"]
    hw = HATCH["half_w"]
    y0, y1 = BELLY_Y - 0.02, FLOOR_Y
    corners = [(-hw, hz0), (hw, hz0), (hw, hz1), (-hw, hz1)]
    for i in range(4):
        (xa, za), (xb, zb) = corners[i], corners[(i + 1) % 4]
        mid = ((xa + xb) / 2, (za + zb) / 2)
        hint = (-mid[0], 0, (hz0 + hz1) / 2 - mid[1])      # 井戸の内側へ向ける
        well._oriented([(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], hint, "DropHatchInterior")
    t = 0.06
    frame.box((-(hw + t / 2), BELLY_Y - 0.035, (hz0 + hz1) / 2), (t, 0.05, hz1 - hz0 + 2 * t), "BodyAccent")
    frame.box(((hw + t / 2), BELLY_Y - 0.035, (hz0 + hz1) / 2), (t, 0.05, hz1 - hz0 + 2 * t), "BodyAccent")
    frame.box((0, BELLY_Y - 0.035, hz0 - t / 2), (2 * hw, 0.05, t), "BodyAccent")
    frame.box((0, BELLY_Y - 0.035, hz1 + t / 2), (2 * hw, 0.05, t), "BodyAccent")
    return well, frame


def build_hatch_leaf(side):
    """床下ハッチの 1 枚（side = -1 左 / +1 右）。原点は外側のふち（ここを軸に下へ開く）。"""
    m = GMesh()
    hz0, hz1 = HATCH["z"]
    hw = HATCH["half_w"]
    x0, x1 = sorted((side * hw, 0.0))
    m.box(((x0 + x1) / 2, BELLY_Y - 0.03, (hz0 + hz1) / 2), (x1 - x0 - 0.01, 0.04, hz1 - hz0 - 0.01), "BodyAccent", faces=("-y", "-x", "+x", "-z", "+z"))
    m.box(((x0 + x1) / 2, BELLY_Y - 0.008, (hz0 + hz1) / 2), (x1 - x0 - 0.04, 0.004, hz1 - hz0 - 0.04), "DropHatchInterior", faces=("+y",))
    return m, (side * hw, BELLY_Y - 0.03, (hz0 + hz1) / 2)


# 計器盤・コンソールは hb_cockpit.py


# ---------------------------------------------------------------- 座席・ブースター・ベルト・操縦かん

def build_seat(sx):
    m = GMesh()
    x = sx * SEAT["x"]
    zf, zb = SEAT["front_z"], SEAT["back_z"]
    top = SEAT["top_y"]
    w = SEAT["width"]
    m.box((x, (FLOOR_Y + top - 0.22) / 2, (zf + zb) / 2 + 0.06), (w - 0.25, top - 0.22 - FLOOR_Y, 0.50), "Charcoal", chamfer=0.03)
    m.box((x, top - 0.11, (zf + zb) / 2), (w, 0.22, zb - zf), "SeatFabric", chamfer=0.05)
    h = SEAT["back_top_y"] - top
    R = rot_x(SEAT["back_tilt_deg"])
    base = Vector((x, top, zb))
    center = base + R @ Vector((0, h / 2, 0.08))
    m.box(tuple(center), (w, h, 0.16), "SeatFabric", rot=R, chamfer=0.05)
    for s in (-1, 1):
        c = base + R @ Vector((s * (w / 2 - 0.06), h * 0.42, -0.02))
        m.box(tuple(c), (0.12, h * 0.62, 0.14), "SeatFabric", rot=R, chamfer=0.04)
    # 背もたれの裏の板
    m.box(tuple(base + R @ Vector((0, h / 2, 0.17))), (w - 0.06, h - 0.06, 0.02), "Charcoal", rot=R)
    return m


def build_booster():
    m = GMesh()
    x = SEAT["x"]
    zf, zb = SEAT["front_z"], SEAT["back_z"]
    m.box((x, SEAT["top_y"] + SEAT["booster_h"] / 2, (zf + zb) / 2 - 0.02), (SEAT["width"] - 0.16, SEAT["booster_h"], zb - zf - 0.06), "BodyPaint", chamfer=0.06)
    return m


def _strap(m, pts, width=0.10, thick=0.02, mat="Charcoal", wdir=(0, 1, 0)):
    """点列にそった平たい帯。幅の向きは wdir（線の向きに直交させて使う）。"""
    for a, b in zip(pts[:-1], pts[1:]):
        a, b = Vector(a), Vector(b)
        d = (b - a).normalized()
        w = Vector(wdir)
        w = (w - d * w.dot(d)).normalized() * (width / 2)
        nrm = d.cross(w).normalized() * (thick / 2)
        for sgn in (1, -1):
            q = [a - w + nrm * sgn, b - w + nrm * sgn, b + w + nrm * sgn, a + w + nrm * sgn]
            m._oriented([tuple(p) for p in q], tuple(nrm * sgn), mat)


def build_belt_left():
    """プレイヤーの腰のベルト（太ももの上を横切る）。"""
    m = GMesh()
    x = -SEAT["x"]
    y_top = SEAT["top_y"] + 0.36 + 0.02
    z = -1.24
    pts = [(x - 0.56, SEAT["top_y"] + 0.02, SEAT["back_z"] - 0.06), (x - 0.47, y_top - 0.04, z + 0.06), (x - 0.30, y_top, z),
           (x + 0.30, y_top, z), (x + 0.47, y_top - 0.04, z + 0.06), (x + 0.56, SEAT["top_y"] + 0.02, SEAT["back_z"] - 0.06)]
    _strap(m, pts, 0.10, 0.025, "Charcoal", wdir=(0, 0, 1))
    m.box((x, y_top + 0.005, z - 0.005), (0.16, 0.05, 0.11), "Trim", chamfer=0.012)
    return m


def build_belt_right(hatena_root):
    """ハテナの体の下のほうを横切るベルト。体（楕円体）の前を回る。"""
    m = GMesh()
    rx, ry, rz = hatena_root
    yb = ry + 0.67                # ハテナの空間で y = 0.67（体の下のほう）
    ax, az = 0.46, 0.40           # その高さの体の半径（x, z）＋少し外
    pts = []
    for i in range(9):
        t = math.radians(15 + 150 * i / 8)
        pts.append((rx + (ax + 0.03) * math.cos(t), yb, rz - (az + 0.03) * math.sin(t)))   # 機首（-z）側を回る
    _strap(m, pts, 0.10, 0.025, "Charcoal", wdir=(0, 1, 0))
    m.box((rx, yb, rz - az - 0.06), (0.16, 0.10, 0.04), "Trim", chamfer=0.012)
    return m


def build_yoke(spec):
    """U 字の操縦かん。握り（Rubber）2 本・横棒・計器盤への柱。"""
    m = GMesh()
    gl, gr = Vector(spec["grip_l"]), Vector(spec["grip_r"])
    by, bz = spec["bar_y"], spec["bar_z"]
    for g in (gl, gr):
        m.tube((g.x, by, bz), (g.x, g.y - 0.11, g.z), 0.035, "Charcoal", n=8)
        m.tube((g.x, g.y - 0.12, g.z), (g.x, g.y + 0.12, g.z), 0.052, "Rubber", n=10)
    m.tube((gl.x, by, bz), (gr.x, by, bz), 0.035, "Charcoal", n=8)
    mid = (gl.x + gr.x) / 2
    m.tube((mid, by, bz), (mid, by + 0.06, DASH["back_z"] - 0.02), 0.05, "Charcoal", n=12)
    m.box((mid, by, bz), (0.14, 0.10, 0.10), "Charcoal", chamfer=0.02)
    return m


# ---------------------------------------------------------------- マスト・ローター
#
# 3 枚ローター（ハブの高さ H = ROTOR["hub_y"] = 4.10）。止める向きは 1 枚が機首の上、2 枚が後ろ斜め（120°・240°）。
#   Body（回らない）      ：マストのブーツ・マスト・サーボのロッド 3 本・下のスワッシュプレート・回り止め
#   MainRotor（回る。原点＝ハブ、ローカル Y）：上のスワッシュプレート・ピッチリンク・シザース・星形のハブ・
#                           エラストマー・板・ボルト・ピッチホーン・根元のカフ・ドーム（BodyPaint、色替え）
#   MainRotorBlades（MainRotor の子。羽根だけ）：回っているときは Godot が隠して円盤に替える（ハブは見えたまま）
# 羽根の向き：方位 a の羽根の向きは d(a) = (sin a, 0, -cos a)、前縁の向きは side = UP × d。翼弦は軸の左右に均等
# （機首の上の羽根が左右のドアから同じだけ離れる。artifacts/heli_blueprint/analysis.py の blade_points と同じ平面形）。

BLADE_R = [0.80, 0.95, 1.30, 2.00, 2.80, 3.60, 4.30, 4.70, 4.88, 5.06, 5.16, 5.24, 5.30]
AEROFOIL6 = [(0.0, 0.0), (0.10, 0.95), (0.45, 0.80), (1.0, 0.0), (0.45, -0.55), (0.10, -0.70)]   # (前縁からの割合, 厚みの半分の何倍)
TIP_BANDS = [(4.70, 4.88, "red"), (4.88, 5.06, "white"), (5.06, 5.30, "red")]
ROOT_RADIUS = 0.82


def _lerp_table(xs, ys, x):
    if x <= xs[0]:
        return ys[0]
    for i in range(len(xs) - 1):
        if x <= xs[i + 1]:
            t = (x - xs[i]) / (xs[i + 1] - xs[i])
            return ys[i] + (ys[i + 1] - ys[i]) * t
    return ys[-1]


def blade_chord(r):
    if r <= 0.80:
        return 0.20
    if r <= 0.95:
        return 0.20 + (0.34 - 0.20) * (r - 0.80) / 0.15
    if r <= 4.88:
        return 0.34 + (0.30 - 0.34) * (r - 0.95) / (4.88 - 0.95)
    return _lerp_table([4.88, 5.06, 5.16, 5.24, 5.30], [0.30, 0.26, 0.215, 0.17, 0.13], r)


def blade_thickness(r):
    return _lerp_table([0.80, 0.95, 4.88, 5.30], [0.050, 0.044, 0.032, 0.020], r)


def blade_height(r):
    H = ROTOR["hub_y"]
    return H - 0.12 * ((max(r, 0.55) - 0.55) / 4.75) ** 2 - 0.02 * max(0.0, (r - 4.88) / 0.42) ** 2


def blade_dirs(k):
    a = math.radians(ROTOR["park_deg"]) + k * 2 * math.pi / ROTOR["blades"]
    d = Vector((math.sin(a), 0.0, -math.cos(a)))
    side = Vector((0, 1, 0)).cross(d).normalized()
    return d, side


def _aerofoil(d, side, r, chord, thick, y, te=None):
    """r での 6 点の断面（前縁から）。te を渡すと後縁の位置（side の向き）をそろえる。"""
    te_s = -0.5 * chord if te is None else te
    le_s = te_s + chord
    h = thick / 2
    out = []
    for f, k in AEROFOIL6:
        s = le_s - f * chord
        out.append(tuple(d * r + side * s + Vector((0.0, y + k * h, 0.0))))
    return out


def build_rotor_static(cowl_top):
    """回らないローターの部品（Body）。マストの根元・サーボのロッドの足元はカバーの上面に少しもぐらせる。"""
    m = GMesh()
    # マストのブーツ（ゴム）
    yb = cowl_top(0.165, 0.0) - 0.012
    m.lathe_axis((0.0, yb, 0.0), (0, 1, 0), [(0.0, 0.165), (0.03, 0.150), (0.06, 0.115), (0.075, 0.085)], "Rubber", n=16, weld="rotor:boot")
    # マスト
    m.tube((0.0, yb + 0.05, 0.0), (0.0, 4.07, 0.0), 0.075, "Metal", n=16, caps=False, weld="rotor:mast")
    # サーボのロッド（方位 90°・210°・330°、半径 0.205）
    for a_deg in (90.0, 210.0, 330.0):
        a = math.radians(a_deg)
        x, z = 0.205 * math.sin(a), -0.205 * math.cos(a)
        y0 = cowl_top(x, z) - 0.005
        m.tube((x, y0, z), (x, 3.860, z), 0.018, "Metal", n=8)
        for yy in (y0 + 0.02, 3.848):
            m.box((x, yy, z), (0.04, 0.04, 0.04), "Charcoal", chamfer=0.006)
    # 下のスワッシュプレート（回らない）：断面を一周させた輪
    prof = [(3.870, 0.095), (3.870, 0.270), (3.885, 0.285), (3.900, 0.270), (3.900, 0.095), (3.870, 0.095)]
    m.lathe_axis((0.0, 0.0, 0.0), (0, 1, 0), [(y, r) for y, r in prof], "Metal", n=16, crease_deg=30.0, weld="rotor:swlo")
    # 回り止め（後ろ）
    m.box((0.0, 3.84, 0.31), (0.035, 0.11, 0.035), "Charcoal", chamfer=0.008)
    m.tube((0.0, 3.885, 0.31), (0.0, 3.885, 0.28), 0.012, "Metal", n=8)
    return m


def _star_outline(H):
    pts = []
    for k in range(ROTOR["blades"]):
        d, side = blade_dirs(k)
        for p in (d * 0.16 - side * 0.07, d * 0.33 - side * 0.07, d * 0.33 + side * 0.07, d * 0.16 + side * 0.07):
            pts.append(p)
        c = d * 0.33
        for ang in (45.0, 90.0, 135.0):
            a = math.radians(ang)
            pts.append(c + (-side * math.cos(a) + d * math.sin(a)) * 0.07)
        a0 = math.atan2(d.z, d.x)
        for da in (math.radians(40.0), math.radians(80.0)):
            aa = a0 + da
            pts.append(Vector((math.cos(aa), 0.0, math.sin(aa))) * 0.16)
    pts.sort(key=lambda p: math.atan2(p.z, p.x))
    return [Vector((p.x, 0.0, p.z)) for p in pts]


def build_rotor_head():
    """回るハブ（MainRotor）。原点は (0, H, 0)。羽根を止めた向きで作る。"""
    H = ROTOR["hub_y"]
    m = GMesh()
    up = Vector((0, 1, 0))
    # 上のスワッシュプレート（回る）
    prof = [(3.905, 0.095), (3.905, 0.250), (3.918, 0.262), (3.930, 0.250), (3.930, 0.095), (3.905, 0.095)]
    m.lathe_axis((0.0, 0.0, 0.0), (0, 1, 0), prof, "Metal", n=16, crease_deg=30.0, weld="rotor:swup")
    # 星形のハブ（3 本の腕）
    outline = _star_outline(H)
    top = [tuple(p + Vector((0, H + 0.025, 0))) for p in outline]
    bot = [tuple(p + Vector((0, H - 0.025, 0))) for p in outline]
    ct, cb = (0.0, H + 0.025, 0.0), (0.0, H - 0.025, 0.0)
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        m._oriented([ct, top[i], top[j]], (0, 1, 0), "Charcoal")
        m._oriented([cb, bot[j], bot[i]], (0, -1, 0), "Charcoal")
        mid = (Vector(top[i]) + Vector(top[j])) / 2
        m._oriented([top[i], top[j], bot[j], bot[i]], (mid.x, 0, mid.z), "Charcoal")
    for k in range(ROTOR["blades"]):
        d, side = blade_dirs(k)
        rot = Matrix((side, up, d)).transposed()
        # スワッシュの耳・ピッチリンク・ピッチホーン
        link = d * 0.32 + side * 0.17
        lug_c = link.normalized() * 0.315
        lug_rot = Matrix((up.cross(link.normalized()), up, link.normalized())).transposed()
        m.box((lug_c.x, 3.918, lug_c.z), (0.05, 0.025, 0.15), "Metal", rot=lug_rot, chamfer=0.008)
        m.tube((link.x, 3.945, link.z), (link.x, 4.020, link.z), 0.012, "Metal", n=8, caps=False)
        for yy in (3.945, 4.020):
            m.box((link.x, yy, link.z), (0.03, 0.03, 0.03), "Charcoal", chamfer=0.005)
        horn = d * 0.32 + side * 0.115
        m.box((horn.x, 4.045, horn.z), (0.13, 0.03, 0.05), "Metal", rot=rot, chamfer=0.006)
        # エラストマー・上下の板・ボルト
        b = d * 0.38
        m.tube((b.x, 4.068, b.z), (b.x, 4.132, b.z), 0.045, "Charcoal", n=10, caps=False)
        pc = d * 0.49
        for yy in (4.0565, 4.1435):
            m.box((pc.x, yy, pc.z), (0.17, 0.023, 0.42), "Metal", rot=rot, chamfer=0.008)
        for rr in (0.63, 0.68):
            for sgn in (-1, 1):
                q = d * rr + side * (sgn * 0.045)
                m.stud((q.x, 4.155, q.z), (0, 1, 0), 0.016, 0.012, "Metal")
                m.stud((q.x, 4.045, q.z), (0, -1, 0), 0.016, 0.012, "Metal")
        # 根元のカフ（羽根の根元を包む金属の筒）
        rings = [_aerofoil(d, side, r, c, t, blade_height(r)) for r, c, t in ((0.60, 0.22, 0.060), (0.72, 0.22, 0.060), (0.84, 0.21, 0.055))]
        m.loft(rings, "Metal", weld=f"rotor:cuff{k}", hint_fn=lambda i, kk, rings=rings: _ring_out(rings, i, kk))
        m._oriented(rings[0], tuple(-d), "Metal")
        m._oriented(rings[-1], tuple(d), "Metal")
    # シザース（回る。方位 60°）
    a = math.radians(60.0)
    dd = Vector((math.sin(a), 0, -math.cos(a)))
    knee = dd * 0.25 + Vector((0, 4.00, 0))
    m.box_between(tuple(dd * 0.09 + Vector((0, 4.06, 0))), tuple(knee), 0.035, 0.02, "Charcoal")
    m.box_between(tuple(knee), tuple(dd * 0.20 + Vector((0, 3.935, 0))), 0.035, 0.02, "Charcoal")
    tang = up.cross(dd).normalized()
    m.tube(tuple(knee - tang * 0.025), tuple(knee + tang * 0.025), 0.012, "Metal", n=8)
    # ドーム（金属の輪の上に色替えの丸い帽子）
    m.lathe_axis((0.0, H, 0.0), (0, 1, 0), [(0.045, 0.185), (0.055, 0.185), (0.06, 0.175)], "Metal", n=16, smooth=False)
    m.lathe_axis((0.0, H, 0.0), (0, 1, 0), [(0.06, 0.175), (0.09, 0.170), (0.13, 0.140), (0.165, 0.090), (0.19, 0.035), (0.20, 0.0)], "BodyPaint", n=16, weld="rotor:dome")
    return m, (0.0, H, 0.0)


def _ring_out(rings, i, k):
    a = Vector(rings[i][k])
    b = Vector(rings[i + 1][(k + 1) % len(rings[i])])
    c = sum((Vector(p) for p in rings[i]), Vector()) / len(rings[i])
    return (a + b) / 2 - c


def build_rotor_blades():
    """3 枚の羽根（MainRotorBlades）。6 点の翼型、先は後退。先の帯は赤・白・赤（Trim に頂点色）。"""
    m = GMesh()
    white = (1.0, 1.0, 1.0, 1.0)
    for k in range(ROTOR["blades"]):
        d, side = blade_dirs(k)
        rings = []
        for r in BLADE_R:
            te = -0.15 if r > 4.88 else None
            rings.append(_aerofoil(d, side, r, blade_chord(r), blade_thickness(r), blade_height(r), te))

        weld = f"blade{k}"
        n = len(AEROFOIL6)
        for i in range(len(rings) - 1):
            r0, r1 = BLADE_R[i], BLADE_R[i + 1]
            mat = "Charcoal" if r0 < 4.70 - 1e-6 else "Trim"
            color = white
            for b0, b1, name in TIP_BANDS:
                if b0 - 1e-6 <= r0 and r1 <= b1 + 1e-6:
                    color = HAZARD_RED if name == "red" else white
            for kk in range(n):
                jj = (kk + 1) % n
                quad = [rings[i][kk], rings[i][jj], rings[i + 1][jj], rings[i + 1][kk]]
                m._oriented(quad, tuple(_ring_out(rings, i, kk)), mat, smooth=True, weld=f"{weld}:{mat}", col=color)
        m.weld_groups[f"{weld}:Charcoal"] = n * sum(1 for r in BLADE_R if r <= 4.70 + 1e-6)
        m.weld_groups[f"{weld}:Trim"] = n * sum(1 for r in BLADE_R if r >= 4.70 - 1e-6)
        m._oriented(rings[0], tuple(-d), "Charcoal")
        m._oriented(rings[-1], tuple(d), "Trim", col=HAZARD_RED)
    return m


# ---------------------------------------------------------------- 尾（フェネストロン）
#
# 超楕円の尾の筒が、濃紺のフェネストロンの囲い（上下の尾翼つき）へ流れ込む。囲いの穴（ダクト）の中で 10 枚のファンが回る。
#   左（-x）：吸い込み側。白い縁・回る金属の羽根・白いスピナー（乗り込み・見せ場の側）
#   右（+x）：吹き出し側。9 本のステーター・駆動軸の支柱・金属のギアボックス
# 角度 φ は横から見た面で C のまわり：u(φ) = (0, cos φ, sin φ)。0° が上、90° が後ろ。Godot の rotate_object_local(RIGHT, +a) と同じ向き。
# 数値は設計図の SPEC["fenestron"]・SPEC["boom_keys"]・SPEC["upper_fin"]・SPEC["ventral_fin"]・SPEC["stab"]。
FEN = SPEC["fenestron"]
BOOM_KEYS = SPEC["boom_keys"]
UFIN = SPEC["upper_fin"]
VFIN = SPEC["ventral_fin"]
FEN_DETAIL = {
    "n": 32,
    "white_edge_deg": (282.0, 360.0),        # 囲いの前上の縁は白（上の尾翼の前縁へつながる）
    "duct": [(-0.175, 0.555), (-0.166, 0.522), (-0.146, 0.499), (-0.118, 0.484), (-0.085, 0.475), (-0.060, 0.470),
             (0.045, 0.470), (0.105, 0.476), (0.145, 0.488), (0.166, 0.503), (0.175, 0.525)],
    "duct_mats": ["Trim", "Trim", "Charcoal", "Charcoal", "Charcoal", "Charcoal", "Charcoal", "Charcoal", "Charcoal", "Trim"],
    "blade": {"r": (0.138, 0.30, 0.452), "chord": (0.090, 0.083, 0.075), "pitch": (34.0, 27.0, 20.0), "half_t": (0.010, 0.008, 0.006), "mod": 0.10},
    "stator_deg0": 245.0, "stator_step": 40.0, "stator_x": (0.050, 0.125), "lean_deg": 8.0,
    "spinner": [(0.075, 0.142), (0.095, 0.140), (0.120, 0.122), (0.142, 0.090), (0.156, 0.050), (0.161, 0.0)],
    "gearbox": [(0.040, 0.150), (0.090, 0.155), (0.140, 0.140), (0.175, 0.105), (0.195, 0.055), (0.200, 0.0)],
}
BOOM_STATIONS = [2.24, 2.40, 2.60, 2.85, 3.15, 3.50, 3.90, 4.30, 4.70, 5.05, 5.35, 5.60, 5.78]
STRAKE_DEG = (50.0, 130.0)                     # ロゴ（z 2.97〜3.93、θ 0° / 180°）をよける
FIN_NUMBER_BOX: dict = {}                      # 上の尾翼の平らな面（機体番号のデカール）。build_tail が書く
TAIL_ANCHORS: dict = {}


def boom_params(z):
    zc = min(max(z, BOOM_KEYS["z"][0]), BOOM_KEYS["z"][-1])
    return {k: pchip(BOOM_KEYS["z"], BOOM_KEYS[src], zc) for k, src in (("a", "a"), ("top", "top"), ("bottom", "bottom"), ("belt", "belt"),
                                                                         ("n_top", "n_top"), ("n_bot", "n_bot"))}


def boom_point(z, theta, off=0.0):
    """尾の筒の面の点（θ は +x から反時計回り）と外向きの法線。off だけ外へ浮かせる。"""
    e = 1e-3

    def at(zz, tt):
        x, y = section_point(boom_params(zz), tt)
        return Vector((x, y, zz))

    p = at(z, theta)
    n = (at(z, theta + e) - at(z, theta - e)).cross(at(z + e, theta) - at(z - e, theta))
    c = Vector((0.0, boom_params(z)["belt"], z))
    if n.dot(p - c) < 0:
        n = -n
    n.normalize()
    return p + n * off, n


def _polar_R(phi):
    """囲いの外形の半径 R(φ)（C のまわりの外形の点を周期的に補間）。"""
    cz, cy = FEN["center_zy"]
    pts = []
    for z, y in FEN["outline"]:
        a = math.atan2(z - cz, y - cy) % (2 * math.pi)
        pts.append((a, math.hypot(z - cz, y - cy)))
    pts.sort()
    xs = [a - 2 * math.pi for a, _ in pts] + [a for a, _ in pts] + [a + 2 * math.pi for a, _ in pts]
    ys = [r for _, r in pts] * 3
    R = pchip(xs, ys, phi % (2 * math.pi))
    assert R - FEN["rim"] - FEN["lip_r"][0] >= 0.03, f"囲いの外形が細すぎる（φ {math.degrees(phi):.0f}° R {R:.3f}）"
    return R


def _fen_point(phi, rho, x):
    cz, cy = FEN["center_zy"]
    return (x, cy + rho * math.cos(phi), cz + rho * math.sin(phi))


def _tail_boom(m):
    rings = []
    for z in BOOM_STATIONS:
        p = boom_params(z)
        rings.append([(*section_point(p, 2 * math.pi * k / 24), z) for k in range(24)])
    rings = [[(x, y, z) for x, y, z in r] for r in rings]
    m.loft(rings, "BodyPaint", weld="Body:boom", hint_fn=lambda i, k: _boom_hint(rings, i, k))
    # 細い白い線 2 本（尾の筒の少し外）
    for z0, z1 in ((4.640, 4.675), (4.715, 4.750)):
        band = []
        for z in (z0, z1):
            p = boom_params(z)
            c = Vector((0.0, p["belt"], z))
            band.append([tuple(c + (Vector((*section_point(p, 2 * math.pi * k / 24), z)) - c) * 1.012) for k in range(24)])
        m.loft(band, "Trim", weld=f"Body:band{z0}", hint_fn=lambda i, k, band=band: _boom_hint(band, i, k))
    # 付け根のカラー（継ぎ目を隠す黒い帯と、金属のボルト 12 本）
    collar = []
    for z in (2.255, 2.315):
        p = boom_params(z)
        c = Vector((0.0, p["belt"], z))
        collar.append([tuple(c + (Vector((*section_point(p, 2 * math.pi * k / 24), z)) - c) * 1.012) for k in range(24)])
    m.loft(collar, "Charcoal", weld="Body:collar", hint_fn=lambda i, k: _boom_hint(collar, i, k))
    for k in range(12):
        q, n = boom_point(2.285, 2 * math.pi * (k + 0.5) / 12, 0.0045)
        m.stud(tuple(q), tuple(n), 0.012, 0.008, "Metal")


def _boom_hint(rings, i, k):
    a = Vector(rings[i][k])
    b = Vector(rings[i + 1][(k + 1) % len(rings[i])])
    mid = (a + b) / 2
    return mid - Vector((0.0, boom_params(mid.z)["belt"], mid.z))


def _shaft_ridge(m, cowl_top):
    """駆動軸のカバー（屋根の後ろから尾の筒の上を通って囲いへ入る、低い背）。"""
    zs = [1.60, 1.80, 2.05, 2.30, 2.65, 3.05, 3.45, 3.85, 4.25, 4.65, 5.05, 5.35, 5.55, 5.65]
    rings = []
    for z in zs:
        if z < BOOM_KEYS["z"][0]:
            base = max(cowl_top(0.0, z), section_extent(z, x=0.0) or 0.0)
        else:
            base = boom_params(z)["top"]
        base -= 0.008
        h = 0.075 * smoothstep(1.60, 1.90, z)
        ring = []
        for k in range(7):
            t = math.pi * (1 - k / 6)
            ring.append((0.08 * math.cos(t), base + h * abs(math.sin(t)) ** 0.8, z))
        rings.append(ring)
    m.loft(rings, "BodyPaint", closed=False, weld="Body:ridge", hint_fn=lambda i, k: (0, 1, 0))


def _strakes(m):
    """尾の筒の両側の細い板（ストレーキ）。"""
    zs = [2.70 + (5.30 - 2.70) * i / 9 for i in range(10)]
    for deg in STRAKE_DEG:
        th = math.radians(deg)
        rows = []
        for i, z in enumerate(zs):
            ramp = smoothstep(0.0, 1.0, min(i, 9 - i))
            b, n = boom_point(z, th, -0.004)
            tan = n.cross(Vector((0, 0, 1))).normalized() * 0.006
            tip = b + n * (0.004 + 0.035 * ramp)
            rows.append((b - tan, tip - tan, tip + tan, b + tan, n, tan))
        for a, c in zip(rows[:-1], rows[1:]):
            m._oriented([tuple(a[0]), tuple(c[0]), tuple(c[1]), tuple(a[1])], tuple(-a[5]), "Charcoal")
            m._oriented([tuple(a[3]), tuple(a[2]), tuple(c[2]), tuple(c[3])], tuple(a[5]), "Charcoal")
            m._oriented([tuple(a[1]), tuple(c[1]), tuple(c[2]), tuple(a[2])], tuple(a[4]), "Charcoal")


def _airfoil_pts(le, te, thick_dir, half_t, table, center=None):
    le, te, td = Vector(le), Vector(te), Vector(thick_dir).normalized()
    return [tuple(le + (te - le) * f + td * (k * half_t)) for f, k in table]


AIRFOIL10 = [(0.0, 0.0), (0.03, 0.55), (0.12, 0.90), (0.30, 1.0), (0.70, 0.70), (1.0, 0.08),
             (1.0, -0.08), (0.70, -0.70), (0.30, -1.0), (0.12, -0.90), (0.03, -0.55)]
FIN9 = [(0.0, 0.0), (0.04, 0.6), (0.15, 1.0), (0.88, 1.0), (1.0, 0.35), (1.0, -0.35), (0.88, -1.0), (0.15, -1.0), (0.04, -0.6)]


def _airfoil_loft(m, sections, table, mat, weld, le_frac, cap_first=False, cap_last=True, outward_fn=None):
    """断面（同じ点の数）の並びを張る。前縁から le_frac までの区間は Trim（白い前縁）。"""
    n = len(table)
    for i in range(len(sections) - 1):
        a, b = sections[i], sections[i + 1]
        ca = sum((Vector(p) for p in a), Vector()) / n
        cb = sum((Vector(p) for p in b), Vector()) / n
        for k in range(n):
            j = (k + 1) % n
            f0, f1 = table[k][0], table[j][0]
            mat_k = "Trim" if max(f0, f1) <= le_frac + 1e-6 else mat
            quad = [a[k], a[j], b[j], b[k]]
            mid = sum((Vector(p) for p in quad), Vector()) / 4
            m._oriented(quad, tuple(mid - (ca + cb) / 2), mat_k, smooth=True, weld=f"{weld}:{mat_k}")
    for idx, cap in ((0, cap_first), (len(sections) - 1, cap_last)):
        if cap:
            sec = sections[idx]
            other = sections[1] if idx == 0 else sections[-2]
            c = sum((Vector(p) for p in sec), Vector()) / n
            co = sum((Vector(p) for p in other), Vector()) / n
            m._oriented(sec, tuple(c - co), mat)


def _stab(m):
    """水平尾翼（翼型、尾の筒を貫く）と、外へ 6° 開いた端板。濃紺に白い前縁。"""
    st = SPEC["stab"]
    y = st["y"]
    span = sorted([(-x, le, te, t) for x, le, te, t in st["span"] if x > 0] + [tuple(r) for r in st["span"]])
    secs = [[(x, y + k * t, le + (te - le) * f) for f, k in AIRFOIL10] for x, le, te, t in span]
    _airfoil_loft(m, secs, AIRFOIL10, "BodyAccent", "Body:stab", 0.12, cap_first=True, cap_last=True)
    ep = st["endplate"]
    cant = math.tan(math.radians(ep["cant_deg"]))
    for sx in (-1, 1):
        secs = []
        for yy, le, te, t in ep["sections"]:
            xc = sx * (ep["x"] + (yy - y) * cant)
            secs.append([(xc + k * t, yy, le + (te - le) * f) for f, k in AIRFOIL10])
        _airfoil_loft(m, secs, AIRFOIL10, "BodyAccent", f"Body:endplate{sx}", 0.12, cap_first=True, cap_last=True)


def _shroud_and_duct(m):
    """囲い（外形 R(φ)、厚みの半分 0.175）とダクト（喉の半径 0.47）。縁で溶接して、なめらかに続ける。"""
    N = FEN_DETAIL["n"]
    lipL, lipR = FEN["lip_r"]
    rim = FEN["rim"]
    w0, w1 = (math.radians(d) for d in FEN_DETAIL["white_edge_deg"])
    phis = [2 * math.pi * k / N for k in range(N)]
    prof = []
    for phi in phis:
        R = _polar_R(phi)
        prof.append([(lipL, -0.175), (lipL + 0.45 * (R - rim - lipL), -0.170), (R - rim, -0.160), (R - 0.045, -0.130), (R - 0.012, -0.075),
                     (R, 0.0), (R - 0.012, 0.075), (R - 0.045, 0.130), (R - rim, 0.160), (lipR + 0.45 * (R - rim - lipR), 0.170), (lipR, 0.175)])
    for k in range(N):
        kk = (k + 1) % N
        pm = (phis[k] + (phis[kk] if kk else 2 * math.pi)) / 2
        white = w0 <= pm < w1
        for i in range(len(prof[k]) - 1):
            pts = [_fen_point(phis[k], *prof[k][i]), _fen_point(phis[k], *prof[k][i + 1]),
                   _fen_point(phis[kk], *prof[kk][i + 1]), _fen_point(phis[kk], *prof[kk][i])]
            core = Vector(_fen_point(pm, (lipL + _polar_R(pm)) / 2, 0.0))
            mid = sum((Vector(p) for p in pts), Vector()) / 4
            mat = "Trim" if (white and 4 <= i <= 5) else "BodyAccent"
            m._oriented(pts, tuple(mid - core), mat, smooth=True, weld="Body:fen")
    duct = FEN_DETAIL["duct"]
    for k in range(N):
        kk = (k + 1) % N
        for i in range(len(duct) - 1):
            (xa, ra), (xb, rb) = duct[i], duct[i + 1]
            pts = [_fen_point(phis[k], ra, xa), _fen_point(phis[k], rb, xb), _fen_point(phis[kk], rb, xb), _fen_point(phis[kk], ra, xa)]
            mid = sum((Vector(p) for p in pts), Vector()) / 4
            axis = Vector((mid.x, FEN["center_zy"][1], FEN["center_zy"][0]))
            m._oriented(pts, tuple(axis - mid), FEN_DETAIL["duct_mats"][i], smooth=True, weld="Body:fen")


def _stators_and_hub(m):
    """吹き出し側の 9 本のステーターと駆動軸の支柱、まん中の動かないハブ（左の白いスピナー・右の金属のギアボックス）。"""
    cz, cy = FEN["center_zy"]
    x0, x1 = FEN_DETAIL["stator_x"]
    lean = math.radians(FEN_DETAIL["lean_deg"])
    for k in range(FEN["stators"]):
        phi = math.radians(FEN_DETAIL["stator_deg0"] + FEN_DETAIL["stator_step"] * k)
        u = Vector((0.0, math.cos(phi), math.sin(phi)))
        t = Vector((0.0, -math.sin(phi), math.cos(phi)))
        d = u * math.cos(lean) + t * math.sin(lean)
        side = Vector((1, 0, 0)).cross(d).normalized()
        secs = []
        for r in (0.135, 0.49):
            c = Vector((0.0, cy, cz)) + d * r
            secs.append([tuple(c + Vector((x, 0, 0)) + side * s) for x, s in ((x0, 0.0), ((x0 + x1) / 2, 0.007), (x1, 0.0), ((x0 + x1) / 2, -0.007))])
        for i in range(4):
            j = (i + 1) % 4
            quad = [secs[0][i], secs[0][j], secs[1][j], secs[1][i]]
            mid = sum((Vector(p) for p in quad), Vector()) / 4
            axis_pt = Vector((x0 * 0.5 + x1 * 0.5, cy, cz)) + d * ((mid - Vector((0, cy, cz))).dot(d))
            m._oriented(quad, tuple(mid - axis_pt), "Charcoal")
    phi = math.radians(FEN_DETAIL["stator_deg0"])
    u = Vector((0.0, math.cos(phi), math.sin(phi)))
    a = Vector((0.06, cy, cz)) + u * 0.12
    b = Vector((0.06, cy, cz)) + u * 0.54
    m.box_between(tuple(a), tuple(b), 0.05, 0.10, "Charcoal", up=(1, 0, 0), chamfer=0.01)
    centre = (0.0, cy, cz)
    m.lathe_axis(centre, (1, 0, 0), [(-0.075, 0.142), (0.040, 0.142)], "Charcoal", n=24, weld="Body:fanband")
    m.lathe_axis(centre, (-1, 0, 0), FEN_DETAIL["spinner"], "Trim", n=24, weld="Body:spinner")
    m.lathe_axis(centre, (1, 0, 0), FEN_DETAIL["gearbox"], "Metal", n=24, weld="Body:gearbox")


def _fins(m):
    """上の尾翼（ストロボと鞭アンテナ）と下の尾翼（バンパーとすり板）。濃紺に白い前縁。"""
    def secs_of(fin):
        return [[(k * t, le[1] + (te[1] - le[1]) * f, le[0] + (te[0] - le[0]) * f) for f, k in FIN9] for le, te, t in fin]

    _airfoil_loft(m, secs_of(UFIN), FIN9, "BodyAccent", "Body:ufin", 0.15, cap_last=True)
    _airfoil_loft(m, secs_of(VFIN), FIN9, "BodyAccent", "Body:vfin", 0.15, cap_last=True)
    m.box((0.0, 4.345, 6.975), (0.05, 0.06, 0.06), "Charcoal", chamfer=0.01)
    m.tube((0.0, 4.37, 6.80), (0.0, 4.50, 7.02), 0.010, "Charcoal", n=6, r1=0.005)
    m.tube((0.0, 2.255, 6.62), (0.0, 2.262, 6.95), 0.025, "Charcoal", n=8)
    m.box((0.0, 2.232, 6.79), (0.03, 0.012, 0.30), "Metal")
    # 機体番号の場所：上の尾翼の平らな面（前縁から 15〜88 %）の、y 4.13〜4.24 で共通の z
    z0, z1 = -9.0, 9.0
    for y in (4.13, 4.185, 4.24):
        le_z = _fin_edge_z(UFIN, y, 0)
        te_z = _fin_edge_z(UFIN, y, 1)
        c = te_z - le_z
        z0, z1 = max(z0, le_z + 0.17 * c), min(z1, le_z + 0.86 * c)
    FIN_NUMBER_BOX.clear()
    FIN_NUMBER_BOX.update({"z": (round(z0, 3), round(z1, 3)), "y": (4.13, 4.24), "x": round(_fin_half_t(UFIN, 4.185), 4)})


def _fin_edge_z(fin, y, which):
    pts = [(s[which][1], s[which][0]) for s in fin]
    for (ya, za), (yb, zb) in zip(pts[:-1], pts[1:]):
        if ya <= y <= yb:
            return za + (zb - za) * (y - ya) / (yb - ya)
    return pts[-1][1]


def _fin_half_t(fin, y):
    ys = [(s[0][1] + s[1][1]) / 2 for s in fin]
    for i in range(len(fin) - 1):
        if ys[i] <= y <= ys[i + 1]:
            t = (y - ys[i]) / (ys[i + 1] - ys[i])
            return fin[i][2] + (fin[i + 1][2] - fin[i][2]) * t
    return fin[-1][2]


def _fan_blade(m, phi, k):
    """ファンの羽根 1 枚（TailRotor、原点はファンの中心）。6 点のレンズ形、根元から先へねじる。"""
    cz, cy = FEN["center_zy"]
    bd = FEN_DETAIL["blade"]
    u = Vector((0.0, math.cos(phi), math.sin(phi)))
    t = Vector((0.0, -math.sin(phi), math.cos(phi)))
    x = Vector((1.0, 0.0, 0.0))
    lens = [(0.0, 0.0), (0.3, 1.0), (0.7, 0.8), (1.0, 0.0), (0.7, -0.8), (0.3, -1.0)]
    secs = []
    for r, c, beta_deg, ht in zip(bd["r"], bd["chord"], bd["pitch"], bd["half_t"]):
        beta = math.radians(beta_deg)
        cdir = t * math.cos(beta) - x * math.sin(beta)
        ndir = t * math.sin(beta) + x * math.cos(beta)
        mid = Vector((FEN["fan_x"], cy, cz)) + u * r
        le = mid + cdir * (c / 2)
        secs.append([tuple(le - cdir * (c * f) + ndir * (kk * ht)) for f, kk in lens])
    for i in range(len(secs) - 1):
        for j in range(6):
            jj = (j + 1) % 6
            quad = [secs[i][j], secs[i][jj], secs[i + 1][jj], secs[i + 1][j]]
            mid = sum((Vector(p) for p in quad), Vector()) / 4
            axis_pt = Vector((FEN["fan_x"], cy, cz)) + u * ((mid - Vector((FEN["fan_x"], cy, cz))).dot(u))
            m._oriented(quad, tuple(mid - axis_pt), "Metal", smooth=True, weld=f"fan{k}")
    m.weld_groups[f"fan{k}"] = 6 * len(secs)
    m._oriented(secs[-1], tuple(u), "Metal")


def build_tail(cowl_top):
    """尾：尾の筒・駆動軸のカバー・ストレーキ・水平尾翼と端板・フェネストロン（囲い・ダクト・ステーター・ハブ）・上下の尾翼。
    返り値：body（Body）、fan（TailRotor）、ファンの中心（Godot）、灯の場所。"""
    body, fan = GMesh(), GMesh()
    _tail_boom(body)
    _shaft_ridge(body, cowl_top)
    _strakes(body)
    zb = 3.92
    body.box((0.0, boom_params(zb)["bottom"] - 0.065, zb), (0.014, 0.14, 0.20), "Charcoal", rot=rot_x(25.0), chamfer=0.004)
    _stab(body)
    _shroud_and_duct(body)
    _stators_and_hub(body)
    _fins(body)
    nb = FEN["blades"]
    for k in range(nb):
        phi = 2 * math.pi * k / nb + FEN_DETAIL["blade"]["mod"] * math.sin(4 * math.pi * k / nb)
        _fan_blade(fan, phi, k)
    cz, cy = FEN["center_zy"]
    anchors = {"strobe": Vector((0.0, 4.345, 7.000)), "strobe_dir": Vector((0.0, 0.0, 1.0))}
    TAIL_ANCHORS.clear()
    TAIL_ANCHORS.update(anchors)
    return body, fan, (FEN["fan_x"], cy, cz), anchors


def tail_layout():
    """尾のフェネストロンの約束（Godot が読む）。pivot はビルダーが足す。"""
    shroud_r = max(_polar_R(2 * math.pi * k / 64) for k in range(64))
    return {"node": "TailRotor", "axis_local": [1, 0, 0], "type": "fenestron", "radius": FEN["fan_r"], "duct_radius": FEN["duct_r"],
            "hub_radius": FEN["hub_r"], "blade_count": FEN["blades"], "shroud_radius": round(shroud_r, 3), "shroud_half_thickness": FEN["half_t"]}


# ---------------------------------------------------------------- スキッド・ステップ

SKID_Y = SKID["r"] + 0.006       # 管の中心の高さ（すり板だけが地面に着く）


def _catmull(pts, n):
    """Catmull-Rom（端は点を重ねる）で n 点。"""
    P_ = [Vector(pts[0])] + [Vector(p) for p in pts] + [Vector(pts[-1])]
    out = []
    segs = len(pts) - 1
    for k in range(n):
        t = k / (n - 1) * segs
        i = min(int(t), segs - 1)
        u = t - i
        p0, p1, p2, p3 = P_[i], P_[i + 1], P_[i + 2], P_[i + 3]
        out.append(tuple(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3)))
    return out


def cross_tube_path(sx, cz):
    x = sx * SKID["x"]
    return _catmull([(x, SKID_Y + 0.09, cz), (x * 0.985, 0.20, cz), (x * 0.86, 0.44, cz), (sx * 1.05, BELLY_Y + 0.03, cz)], 9)


def build_skids():
    """スキッド：前が丸く上がる 1 本の管、十字の管、固定金具、胴体の根元のカバー（濃紺）、すり板、取っ手の突起。"""
    m = GMesh()
    z0, z1 = SKID["z"]
    for sx in (-1, 1):
        x = sx * SKID["x"]
        path = []
        for k in range(8, -1, -1):
            phi = math.radians(62.0) * k / 8
            path.append((x, 0.516 - 0.45 * math.cos(phi), z0 - 0.45 * math.sin(phi)))
        for k in range(1, 11):
            path.append((x, SKID_Y, z0 + (z1 - z0) * k / 10))
        m.sweep(path, [SKID["r"]] * len(path), "Charcoal", n=12, caps=("round", "round"), weld=f"skid{sx}")
        for cz in SKID["cross_z"]:
            cp = cross_tube_path(sx, cz)
            m.sweep(cp, [0.055] * len(cp), "Charcoal", n=12, caps=(None, None), weld=f"cross{sx}{cz}")
            # 固定金具：スキッドを抱く袖（下は開ける）と鞍とボルト
            m.lathe_axis((x, SKID_Y, cz - 0.08), (0, 0, 1), [(0.0, 0.072), (0.16, 0.072)], "Metal", ref=(1, 0, 0), n=12,
                         arc=(math.radians(-40.0), math.radians(220.0)), weld=f"sleeve{sx}{cz}")
            m.box((x, SKID_Y + 0.07, cz), (0.11, 0.05, 0.13), "Charcoal", chamfer=0.01)
            for dz in (-0.05, 0.05):
                for dx in (-1, 1):
                    m.stud((x + dx * 0.072, SKID_Y, cz + dz), (dx, 0, 0), 0.012, 0.008, "Metal")
            # 胴体の根元のカバー（濃紺）
            end, prev = Vector(cp[-1]), Vector(cp[-2])
            d = (prev - end).normalized()
            m.lathe_axis(tuple(end), tuple(d), [(0.0, 0.10), (0.06, 0.085), (0.14, 0.065)], "BodyAccent", n=12, weld=f"cuff{sx}{cz}")
        # すり板（地面に着く金属の板）と取っ手の突起
        for za, zb in ((-1.95, -0.85), (0.07, 1.17)):
            m.box((x, 0.006, (za + zb) / 2), (0.075, 0.012, zb - za), "Metal", chamfer=0.004)
        for zz in (-1.95, 0.95):
            m.stud((x + sx * SKID["r"], SKID_Y, zz), (sx, 0, 0), 0.035, 0.03, "Metal", n=8)
    return m


def build_step():
    """左のステップ：白い枠・ゴムの滑り止め・黄黒の縁（形で作る）・金属の支柱と管の留め具。上面 0.353〜0.358。"""
    m = GMesh()
    x0, x1, z0, z1 = STEP["x0"], STEP["x1"], STEP["z0"], STEP["z1"]
    y = SPEC["step_y"]
    m.box(((x0 + x1) / 2, y - 0.025, (z0 + z1) / 2), (x1 - x0, 0.05, z1 - z0), "Trim", chamfer=0.012)
    m.box(((x0 + x1) / 2, y + 0.0015, (z0 + z1) / 2), (0.40, 0.003, 0.72), "Rubber", faces=("+y", "-x", "+x", "-z", "+z"))
    for k in range(7):
        z = (z0 + z1) / 2 - 0.30 + 0.10 * k
        m.box(((x0 + x1) / 2, y + 0.0055, z), (0.40, 0.005, 0.025), "Rubber")
    # 黄黒の 45° の縞（外側の面と前の面、2 mm 浮かせる）
    def stripes(origin, u_dir, v_dir, length, height, normal):
        w = 0.04
        k = 0
        u = -height
        while u < length:
            col = HAZARD_YELLOW if k % 2 == 0 else HAZARD_BLACK
            quad = []
            for uu, vv in ((u, 0.0), (u + w, 0.0), (u + w + height, height), (u + height, height)):
                cu = min(max(uu, 0.0), length)
                quad.append(tuple(origin + u_dir * cu + v_dir * vv + normal * 0.002))
            if (Vector(quad[1]) - Vector(quad[0])).length > 1e-4 or (Vector(quad[2]) - Vector(quad[3])).length > 1e-4:
                m._oriented(quad, tuple(normal), "Trim", col=col)
            u += w
            k += 1

    stripes(Vector((x0, y - 0.048, z0 + 0.012)), Vector((0, 0, 1)), Vector((0, 1, 0)), (z1 - z0) - 0.024, 0.044, Vector((-1, 0, 0)))
    stripes(Vector((x0 + 0.012, y - 0.048, z0)), Vector((1, 0, 0)), Vector((0, 1, 0)), (x1 - x0) - 0.024, 0.044, Vector((0, 0, -1)))
    cp = cross_tube_path(-1, SKID["cross_z"][0])
    target = Vector(cp[3])
    for zz in (z0 + 0.12, z1 - 0.12):
        m.tube((x1 - 0.03, y - 0.05, zz), tuple(target + Vector((0, 0, (zz - target.z) * 0.15))), 0.03, "Metal", n=10)
    tang = (Vector(cp[4]) - Vector(cp[2])).normalized()
    m.tube(tuple(target - tang * 0.035), tuple(target + tang * 0.035), 0.07, "Metal", n=12)
    return m


# ---------------------------------------------------------------- 灯

def side_surface(y, z, side):
    """胴体の横の点（外板の上）と外向きの法線（Godot の座標）。"""
    w = section_extent(z, y=y)
    eps = 0.01
    dwdy = (section_extent(z, y=y + eps) - section_extent(z, y=y - eps)) / (2 * eps)
    dwdz = (section_extent(z + eps, y=y) - section_extent(z - eps, y=y)) / (2 * eps)
    n = Vector((side * 1.0, -dwdy, -dwdz)).normalized()
    return Vector((side * w, y, z)), n


def _disc(m, center, normal, radius, mat, n=14):
    normal = Vector(normal).normalized()
    up = Vector((0, 1, 0)) if abs(normal.y) < 0.9 else Vector((1, 0, 0))
    u = normal.cross(up).normalized()
    w = normal.cross(u).normalized()
    pts = [tuple(center + radius * (math.cos(2 * math.pi * k / n) * u + math.sin(2 * math.pi * k / n) * w)) for k in range(n)]
    m._oriented(pts, tuple(normal), mat)


def _ring(m, center, normal, r0, r1, mat, n=14):
    normal = Vector(normal).normalized()
    up = Vector((0, 1, 0)) if abs(normal.y) < 0.9 else Vector((1, 0, 0))
    u = normal.cross(up).normalized()
    w = normal.cross(u).normalized()
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        p = [center + r0 * (math.cos(a0) * u + math.sin(a0) * w), center + r1 * (math.cos(a0) * u + math.sin(a0) * w),
             center + r1 * (math.cos(a1) * u + math.sin(a1) * w), center + r0 * (math.cos(a1) * u + math.sin(a1) * w)]
        m._oriented([tuple(q) for q in p], tuple(normal), mat)


def build_lights(anchors):
    """灯の部品。光る物（Godot が全部の面を光る材質に塗り替える）は面を 1 つだけにし、覆いは "Body" に入れる。
    anchors：灯を載せる場所（hb_detail.build_roof_kit の beacon など）。"""
    out = {}
    housing = GMesh()
    lens = GMesh()
    for name, side, mat in (("NavLight_L", -1, "NavRed"), ("NavLight_R", 1, "NavGreen")):
        # しずく形：光る芯（NavLight_*）、透明な殻（Windows）、胴体色の覆いと黒い縁（Body）。前（機首の向き）が丸い
        m = GMesh()
        c, n = side_surface(1.62, -2.45, side)
        t = n.cross(Vector((0, 1, 0))).normalized() * (-side)
        o = c - n * 0.008
        front = o + t * 0.12
        ax = tuple(-t)
        ref = tuple(n)
        m.lathe_axis(tuple(front), ax, [(0.015, 0.0), (0.03, 0.028), (0.06, 0.042), (0.10, 0.044), (0.115, 0.0)], mat, ref=ref, n=12, weld=f"nav{side}:core")
        out[name] = m
        lens.lathe_axis(tuple(front), ax, [(0.0, 0.0), (0.02, 0.034), (0.05, 0.052), (0.09, 0.060), (0.12, 0.060)], "Windows", ref=ref, n=10,
                        arc=(math.radians(-100.0), math.radians(100.0)), weld=f"nav{side}:lens")
        housing.lathe_axis(tuple(front), ax, [(0.12, 0.060), (0.17, 0.050), (0.22, 0.030), (0.26, 0.010), (0.28, 0.0)], "BodyPaint", ref=ref, n=12, weld=f"nav{side}:housing")
        housing.lathe_axis(tuple(front), ax, [(0.115, 0.062), (0.12, 0.066), (0.125, 0.062)], "Charcoal", ref=ref, n=12, smooth=False)
    out["Windows"] = lens
    b = GMesh()
    bc = anchors["beacon"]
    b.lathe_axis(tuple(bc), (0, 1, 0), [(0.0, 0.055), (0.025, 0.056), (0.05, 0.05), (0.07, 0.034), (0.082, 0.012), (0.085, 0.0)], "NavRed", n=16, weld="beacon:dome")
    out["Beacon"] = b
    # LandingLight はあごのサーチライトのレンズ（hb_detail.build_fuselage_kit）
    # 尾のストロボ（上の尾翼の後ろの端。白く光る。回っている間だけ点滅）
    if "strobe" in anchors:
        st = GMesh()
        st.lathe_axis(tuple(anchors["strobe"]), tuple(anchors["strobe_dir"]), [(0.0, 0.030), (0.012, 0.028), (0.022, 0.018), (0.028, 0.0)], "LampWhite", n=10, weld="strobe:dome")
        out["StrobeLights"] = st
    out["Body"] = housing
    return out


# ---------------------------------------------------------------- ジェットブースト（左右のポッド）
#
# 機体の後ろ寄りの肩に、ヒンジ（前後の軸）で付いた短い翼の先にジェットのポッドが 1 つずつ付く。
# 形は「広げた形」（翼が水平）で作り、GLB のふだんの形は STOW_DEG だけ下へたたんだ向きにする（ビルダーが回す）。
# 発進するとき Godot が翼を水平まで上げ（deploy）、噴射口の羽根（JetNozzle_*）を広げ、奥の光（JetGlow_*）を強め、
# 噴射口の出口（nozzle_exit）から炎を出す。数値は設計図の外（この部品だけの値）なのでここに置く。
JET = {
    "hinge_y": 3.08,          # ヒンジの高さ（屋根の肩）
    "hinge_z": (0.24, 1.26),  # ヒンジの前後の範囲
    "arm": 0.80,              # ヒンジの軸 → ポッドの軸（広げたとき水平）
    "stow_deg": 38.0,         # ふだんは翼を下へ 38° たたむ
    "pod_r": 0.27,
    "nozzle_z": (1.80, 2.08), # 羽根の付け根と先
    "nozzle_r": (0.195, 0.150),
    "glow_z": 1.76,
    "petals": 10,
}


def jet_hinge(side):
    """side（-1＝左、+1＝右）のヒンジの軸の中心（Godot の座標、地面基準）。軸の向きは +Z。"""
    z0, z1 = JET["hinge_z"]
    zm = (z0 + z1) / 2
    x = section_extent(zm, y=JET["hinge_y"]) - 0.03
    return Vector((side * x, JET["hinge_y"], zm))


def jet_axis(side):
    """広げたときのポッドの軸の中心（x, y）。"""
    h = jet_hinge(side)
    return Vector((h.x + side * JET["arm"], h.y, 0.0))


def _lathe(m, cx, cy, stations, mat, n=16, smooth=True, outward=True, weld=None, **kw):
    """z にそった回転体（GMesh.lathe_axis の z 軸版）。stations は [(z, r)]。outward=False で内向きの面（筒の内側）。"""
    return m.lathe_axis((cx, cy, 0.0), (0, 0, 1), stations, mat, ref=(1, 0, 0), n=n, outward=outward, smooth=smooth, weld=weld, **kw)


POD_SKIN = [(-0.235, 0.252), (-0.14, 0.27 * 0.99), (0.30, 0.27), (1.20, 0.27 * 0.965), (1.55, 0.27 * 0.87), (1.72, 0.27 * 0.76)]
DARK = (0.45, 0.45, 0.45, 1.0)


def _pod_r(z):
    """ポッドの外板の半径（z、広げた形のポッドの軸から）。"""
    for (za, ra), (zb, rb) in zip(POD_SKIN[:-1], POD_SKIN[1:]):
        if za <= z <= zb:
            return ra + (rb - ra) * (z - za) / (zb - za)
    return POD_SKIN[0][1] if z < POD_SKIN[0][0] else POD_SKIN[-1][1]


def _pod_point(cx, cy, z, phi, off=0.0):
    r = _pod_r(z) + off
    return Vector((cx + r * math.cos(phi), cy + r * math.sin(phi), z))


def build_jet(side):
    """1 つの側の部品：pod（翼・ヒンジの関節・ポッド・先端灯・シェブロン）、nozzle（羽根）、glow（奥の光）、mount（機体の取り付け：パイロン・関節・ボルト、Body）。
    返す pivots は Godot の座標：pod＝ヒンジの中心、nozzle＝羽根の付け根の中心、glow＝光の円の中心。"""
    pod, nozzle, glow, mount = GMesh(), GMesh(), GMesh(), GMesh()
    h = jet_hinge(side)
    a = jet_axis(side)
    cx, cy = a.x, a.y
    r = JET["pod_r"]
    z0, z1 = JET["hinge_z"]
    n = 24
    # 外板・白い帯・継ぎ目の輪・リベット
    _lathe(pod, cx, cy, POD_SKIN, "BodyPaint", n=n, weld=f"pod{side}:skin")
    _lathe(pod, cx, cy, [(0.055, r * 1.001), (0.06, r * 1.012), (0.22, r * 1.012), (0.225, r * 1.001)], "Trim", n=n, weld=f"pod{side}:band", crease_deg=30.0)
    _lathe(pod, cx, cy, [(0.695, r * 0.995 * 1.001), (0.710, r * 0.995 * 1.010), (0.725, r * 0.995 * 1.001)], "Metal", n=n, weld=f"pod{side}:seam")
    inboard = math.pi if side > 0 else 0.0
    for zr in (0.68, 0.74):
        for k in range(12):
            phi = 2 * math.pi * k / 12
            dphi = math.atan2(math.sin(phi - inboard), math.cos(phi - inboard))
            if abs(dphi) < math.radians(25.0):
                continue
            p = _pod_point(cx, cy, zr, phi, -0.002)
            nrm = Vector((math.cos(phi), math.sin(phi), 0.0))
            pod.stud(tuple(p), tuple(nrm), 0.009, 0.004, "Metal")
    # 吸い込み口：金属の縁・暗いダクト・暗い輪・白いスピナー
    _lathe(pod, cx, cy, [(-0.235, 0.252), (-0.27, 0.238), (-0.300, 0.214), (-0.305, 0.195), (-0.29, 0.180), (-0.255, 0.176)], "Metal", n=n, weld=f"pod{side}:lip", crease_deg=50.0)
    _lathe(pod, cx, cy, [(-0.255, 0.176), (-0.20, 0.172)], "Charcoal", n=n, outward=False, weld=f"pod{side}:duct")
    _lathe(pod, cx, cy, [(-0.20, 0.172), (-0.20, 0.085)], "Charcoal", n=n, smooth=False, cols=[DARK, DARK])
    _lathe(pod, cx, cy, [(-0.33, 0.004), (-0.29, 0.045), (-0.20, 0.085)], "Trim", n=12, weld=f"pod{side}:spinner")
    # 噴射口の付け根（暗い輪）と、焼け色の金属の内側
    _lathe(pod, cx, cy, [(1.72, r * 0.76), (1.80, 0.195)], "Charcoal", n=n, weld=f"pod{side}:tail")
    _lathe(pod, cx, cy, [(1.80, 0.195), (1.80, 0.172)], "Charcoal", n=n, smooth=False)
    _lathe(pod, cx, cy, [(1.66, 0.172), (1.80, 0.172)], "Metal", n=n, outward=False, weld=f"pod{side}:pipe", cols=[HEAT_BLUE, HEAT_BRONZE])
    _lathe(pod, cx, cy, [(1.66, 0.172), (1.66, 0.0)], "Charcoal", n=n, smooth=False, cols=[DARK, DARK])
    # 下のフィン（30° 外へ傾ける）
    e = Vector((side * 0.5, -0.866, 0.0))
    tdir = Vector((0, 0, 1)).cross(e).normalized()
    prof = [(0.95, _pod_r(0.95) - 0.01), (1.25, 0.335), (1.48, 0.33), (1.52, _pod_r(1.52) - 0.01)]
    base = Vector((cx, cy, 0.0))
    pts = [base + Vector((0, 0, z)) + e * rho for z, rho in prof]
    lo = [tuple(p - tdir * 0.009) for p in pts]
    hi = [tuple(p + tdir * 0.009) for p in pts]
    pod._oriented(lo, tuple(-tdir), "Charcoal")
    pod._oriented(hi, tuple(tdir), "Charcoal")
    for i in range(3):
        j = i + 1
        mid = (pts[i] + pts[j]) / 2
        pod._oriented([lo[i], lo[j], hi[j], hi[i]], tuple(mid - (base + Vector((0, 0, mid.z))) - e * 0.25), "Charcoal")
    # 翼（前縁が丸い 7 点の断面。前縁は白）
    wing7 = [(0.0, 0.0), (0.08, 0.85), (0.35, 1.0), (1.0, 0.08), (1.0, -0.08), (0.35, -1.0), (0.08, -0.80)]
    tip_x = cx - side * 0.1485
    spans = [(h.x, 0.30, 1.20, 0.06), ((h.x + tip_x) / 2, 0.36, 1.13, 0.055), (tip_x, 0.42, 1.06, 0.05)]
    secs = [[(x, cy + k * hh, za + f * (zb - za)) for f, k in wing7] for x, za, zb, hh in spans]
    for i in range(2):
        for kk in range(7):
            jj = (kk + 1) % 7
            quad = [secs[i][kk], secs[i][jj], secs[i + 1][jj], secs[i + 1][kk]]
            mid = sum((Vector(q) for q in quad), Vector()) / 4
            le_seg = kk in (0, 6)
            te_seg = kk == 3
            mat = "Trim" if le_seg else "BodyPaint"
            hint = mid - Vector((mid.x, cy, (spans[i][1] + spans[i][2]) / 2))
            if te_seg:
                pod._oriented(quad, (0, 0, 1), mat)
            else:
                pod._oriented(quad, tuple(hint), mat, smooth=True, weld=f"pod{side}:wing:{mat}")
    pod._oriented(secs[-1], (side, 0, 0), "BodyPaint")
    # ヒンジの関節（動く 3 つ）とピンの頭
    for za, zb in ((0.240, 0.430), (0.656, 0.846), (1.072, 1.260)):
        pod.tube((h.x, h.y, za), (h.x, h.y, zb), 0.085, "Metal", n=16)
    pod.stud((h.x, h.y, 0.23), (0, 0, -1), 0.04, 0.015, "Metal", n=8)
    pod.stud((h.x, h.y, 1.27), (0, 0, 1), 0.04, 0.015, "Metal", n=8)
    # 先端灯（外側の前。左は赤、右は緑。いつも点いている）と黒い縁
    lamp = "NavRed" if side < 0 else "NavGreen"
    outward = Vector((side, 0.0, 0.0))
    lc = Vector((cx + side * 0.262, cy, -0.18))
    arc = (math.radians(-100.0), math.radians(100.0))
    ref = outward
    pod.lathe_axis(tuple(lc), (0, 0, 1), [(0.0, 0.0), (0.015, 0.022), (0.04, 0.032), (0.08, 0.030), (0.13, 0.016), (0.16, 0.0)], lamp, ref=tuple(ref), n=10,
                   arc=arc, weld=f"pod{side}:tip")
    pod.lathe_axis(tuple(lc + Vector((0, 0, 0.13))), (0, 0, 1), [(0.0, 0.034), (0.006, 0.036), (0.012, 0.034)], "Charcoal", ref=tuple(ref), n=10, arc=arc, smooth=False)
    # シェブロン 3 つ（外側、前向きの「く」。白に濃紺の頂点色、3 mm 浮かせる）
    for k in range(3):
        za = 0.80 + 0.20 * k
        for sgn in (-1, 1):
            arm = []
            for t in (0.0, 0.5, 1.0):
                z = za + 0.12 * t
                phi = (0.0 if side > 0 else math.pi) + sgn * math.radians(16.0) * t
                arm.append((phi, z))
            for (p0, za_), (p1, zb_) in zip(arm[:-1], arm[1:]):
                quad = [_pod_point(cx, cy, za_, p0, 0.003) + Vector((0, 0, -0.018)), _pod_point(cx, cy, zb_, p1, 0.003) + Vector((0, 0, -0.018)),
                        _pod_point(cx, cy, zb_, p1, 0.003) + Vector((0, 0, 0.018)), _pod_point(cx, cy, za_, p0, 0.003) + Vector((0, 0, 0.018))]
                mid = sum(quad, Vector()) / 4
                pod._oriented([tuple(q) for q in quad], tuple(mid - Vector((cx, cy, mid.z))), "Trim", col=NAVY)
    # 噴射口の羽根（JetNozzle）：外は黒、内側と縁は焼け色の金属
    nz0, nz1 = JET["nozzle_z"]
    nr0, nr1 = JET["nozzle_r"]
    npet = JET["petals"]
    zm = 1.94
    rm = nr0 + (nr1 - nr0) * (zm - nz0) / (nz1 - nz0)
    for k in range(npet):
        a0 = 2 * math.pi * (k + 0.06) / npet
        a1 = 2 * math.pi * (k + 0.94) / npet
        am = (a0 + a1) / 2

        def pt(rr, zz, t, dr=0.0):
            return (cx + (rr - dr) * math.cos(t), cy + (rr - dr) * math.sin(t), zz)

        nrm = (math.cos(am) * (nz1 - nz0), math.sin(am) * (nz1 - nz0), nr0 - nr1)
        nozzle._oriented([pt(nr0, nz0, a0), pt(nr0, nz0, a1), pt(nr1, nz1, a1), pt(nr1, nz1, a0)], nrm, "Charcoal")
        inner_n = tuple(-v for v in nrm)
        nozzle._oriented([pt(nr0, nz0, a0, 0.012), pt(nr0, nz0, a1, 0.012), pt(rm, zm, a1, 0.012), pt(rm, zm, a0, 0.012)], inner_n, "Metal",
                         col=[HEAT_BLUE, HEAT_BLUE, HEAT_BRONZE, HEAT_BRONZE])
        nozzle._oriented([pt(rm, zm, a0, 0.012), pt(rm, zm, a1, 0.012), pt(nr1, nz1, a1, 0.012), pt(nr1, nz1, a0, 0.012)], inner_n, "Metal",
                         col=[HEAT_BRONZE, HEAT_BRONZE, HEAT_STRAW, HEAT_STRAW])
        nozzle._oriented([pt(nr1, nz1, a0), pt(nr1, nz1, a1), pt(nr1, nz1, a1, 0.012), pt(nr1, nz1, a0, 0.012)], (0, 0, 1), "Metal", col=HEAT_STRAW)
    # 奥の光（JetGlow）
    _disc(glow, Vector((cx, cy, JET["glow_z"])), (0, 0, 1), 0.165, "JetGlow", n=16)
    # 機体の取り付け（Body、動かない）：胴体からヒンジの軸までのパイロン・2 つの関節・腕・ボルト
    rings = []
    for z in (0.20, 0.45, 0.75, 1.05, 1.30):
        s_hi = section_extent(z, y=3.24) - 0.01
        s_lo = section_extent(z, y=3.02) - 0.01
        rings.append([(side * s_hi, 3.24, z), (h.x, 3.14, z), (h.x, 3.02, z), (side * s_lo, 3.02, z)])
    for i in range(len(rings) - 1):
        for k in range(3):
            quad = [rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]]
            mid = sum((Vector(q) for q in quad), Vector()) / 4
            mount._oriented(quad, tuple(mid - Vector((0.0, 3.13, mid.z))), "BodyPaint")
    mount._oriented(rings[0], (0, 0, -1), "BodyPaint")
    mount._oriented(rings[-1], (0, 0, 1), "BodyPaint")
    for za, zb in ((0.448, 0.638), (0.864, 1.054)):
        mount.tube((h.x, h.y, za), (h.x, h.y, zb), 0.085, "Metal", n=16)
        zc = (za + zb) / 2
        skin_x = section_extent(zc, y=h.y) - 0.01
        mount.box_between((h.x, h.y, zc), (side * skin_x, h.y, zc), 0.04, 0.12, "Charcoal", up=(0, 1, 0))
    for zb_ in (0.30, 0.75, 1.20):
        bx = h.x - side * 0.05
        mount.stud((bx, 3.24, zb_), (0, 1, 0), 0.016, 0.01, "Metal")
        mount.stud((bx + side * 0.03, 3.24, zb_ + 0.05), (0, 1, 0), 0.016, 0.01, "Metal")
    pivots = {"pod": Vector((h.x, h.y, h.z)), "nozzle": Vector((cx, cy, nz0)), "glow": Vector((cx, cy, JET["glow_z"])),
              "exit": Vector((cx, cy, nz1))}
    return pod, nozzle, glow, mount, pivots

"""胴体以外の部品：床・計器盤・座席・操縦かん・ベルト・後ろの仕切り・マストとローター・尾・スキッドとステップ・灯・床下ハッチ。

すべて Godot の座標（地面基準）で書く。数値は設計図の JSON（SPEC）。返すのは {部品名: GMesh}。
"""
from __future__ import annotations

import math

from mathutils import Matrix, Vector

from hb_common import BP, HAZARD_RED, SPEC, GMesh, body_params, section_extent, section_point
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
    # 計器盤のうしろのふさぎ（風防の下、床から計器盤まで）
    zf = CABIN_Z0
    w = inner_half_width(FLOOR_Y + 0.3, zf)
    m._oriented([(-w, FLOOR_Y, zf), (w, FLOOR_Y, zf), (w, DASH["bottom_y"], zf), (-w, DASH["bottom_y"], zf)], (0, 0, 1), "Interior")
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


# ---------------------------------------------------------------- 計器盤・コンソール

def build_dash():
    m = GMesh()
    screens = GMesh()
    zb, zf = DASH["back_z"], DASH["front_z"]
    yb, yt = DASH["bottom_y"], DASH["top_y"]
    zm = (zb + zf) / 2
    w = min(1.42, inner_half_width(yt, zm) - 0.04)
    m.box((0, (yb + yt) / 2, zm), (2 * w, yt - yb, zf - zb if zf > zb else zb - zf), "DashDark", chamfer=0.03)
    # ひさし（座席の側へ少し張り出す）
    m.box((0, yt + 0.03, zm + 0.04), (2 * w + 0.04, 0.06, abs(zb - zf) + 0.16), "Charcoal", chamfer=0.02)
    for sx in (-1, 1):
        x = sx * SEAT["x"]
        screens.box((x, yt - 0.17, zb + 0.004), (0.50, 0.22, 0.008), "ScreenGlow")
        m.box((x, yt - 0.17, zb + 0.002), (0.56, 0.28, 0.006), "Charcoal")
        for dx in (-0.40, 0.40):
            gx = x + dx * 0.9
            m.tube((gx, yt - 0.17, zb + 0.003), (gx, yt - 0.17, zb + 0.03), 0.07, "Trim", n=12)
            screens.tube((gx, yt - 0.17, zb + 0.031), (gx, yt - 0.17, zb + 0.034), 0.055, "ScreenGlow", n=12)
    # コンソール（2 つの席のあいだ）
    cz0, cz1 = zb, SEAT["back_z"] - 0.05
    hw = SPEC["console_half_w"]
    m.box((0, (FLOOR_Y + 1.28) / 2, (cz0 + cz1) / 2), (2 * hw, 1.28 - FLOOR_Y, cz1 - cz0), "DashDark", chamfer=0.04)
    m.tube((0.0, 1.28, -1.25), (0.0, 1.52, -1.32), 0.025, "Charcoal", n=8)
    m.box((0.0, 1.55, -1.33), (0.08, 0.07, 0.08), "Rubber", chamfer=0.015)
    for i, mat in enumerate(("NavGreen", "LampWhite", "NavRed")):
        screens.box((-0.09 + i * 0.09, 1.285, -1.55), (0.05, 0.012, 0.05), mat)
    return m, screens


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


# ---------------------------------------------------------------- 尾

def build_tail():
    body = GMesh()
    z0 = 2.10
    z1 = BOOM["z1"]
    n = 16
    stations = [z0 + (z1 - z0) * i / 10 for i in range(11)]

    def ring(z):
        t = (z - BOOM["z0"]) / (BOOM["z1"] - BOOM["z0"])
        r = BOOM["r0"] + (BOOM["r1"] - BOOM["r0"]) * t
        yc = BOOM["y0"] + (BOOM["y1"] - BOOM["y0"]) * t
        return [(r * math.cos(2 * math.pi * k / n), yc + r * math.sin(2 * math.pi * k / n), z) for k in range(n)], yc

    rings = [ring(z) for z in stations]
    for (ra, ya), (rb, yb), za, zb in zip(rings[:-1], rings[1:], stations[:-1], stations[1:]):
        for k in range(n):
            j = (k + 1) % n
            hint = ((ra[k][0] + ra[j][0]) / 2, (ra[k][1] + ra[j][1]) / 2 - ya, 0)
            body._oriented([ra[k], ra[j], rb[j], rb[k]], hint, "BodyPaint", smooth=True, weld="boom")
    last, yl = rings[-1]
    for k in range(n):
        body._oriented([(0, yl, stations[-1]), last[k], last[(k + 1) % n]], (0, 0, 1), "BodyPaint")
    # 白い帯（尾の付け根寄り）
    zt0, zt1 = 4.60, 4.78
    ra, ya = ring(zt0)
    rb, yb = ring(zt1)
    for k in range(n):
        j = (k + 1) % n
        sa = [(p[0] * 1.012, ya + (p[1] - ya) * 1.012, p[2]) for p in (ra[k], ra[j])]
        sb = [(p[0] * 1.012, yb + (p[1] - yb) * 1.012, p[2]) for p in (rb[j], rb[k])]
        body._oriented([sa[0], sa[1], sb[0], sb[1]], ((ra[k][0] + ra[j][0]) / 2, (ra[k][1] + ra[j][1]) / 2 - ya, 0), "Trim", smooth=True, weld="boom_band")
    # 垂直尾翼・水平尾翼・端板・尾のそり
    body.extrude_x([tuple(p) for p in SPEC["fin"]], -0.06, 0.06, "BodyAccent")
    body.box((0, STAB["y"], (STAB["z0"] + STAB["z1"]) / 2), (2 * STAB["half_span"], 0.07, STAB["z1"] - STAB["z0"]), "BodyAccent", chamfer=0.02)
    for sx in (-1, 1):
        body.box((sx * STAB["half_span"], STAB["y"] + 0.05, (STAB["z0"] + STAB["z1"]) / 2 + 0.03), (0.05, 0.36, 0.44), "BodyAccent", chamfer=0.015)
    body.tube((0, 2.16, 6.58), (0, 1.86, 6.78), 0.035, "Charcoal", n=8)
    body.tube((TAIL["x"] - 0.24, TAIL["y"], TAIL["z"]), (TAIL["x"] - 0.04, TAIL["y"], TAIL["z"]), 0.09, "Charcoal", n=12)
    # 尾のローター（原点＝ハブ、Godot の X 軸で回す）
    rotor = GMesh()
    hx, hy, hz = TAIL["x"], TAIL["y"], TAIL["z"]
    rotor.tube((hx - 0.04, hy, hz), (hx + 0.08, hy, hz), 0.09, "Charcoal", n=12)
    for k in range(2):
        ang = math.radians(35) + k * math.pi
        d = Vector((0, math.cos(ang), math.sin(ang)))
        side = d.cross(Vector((1, 0, 0))).normalized()
        for t0, t1, mat in ((0.08, 0.53, "Charcoal"), (0.53, TAIL["radius"], "Trim")):
            c = Vector((hx + 0.03, hy, hz)) + d * ((t0 + t1) / 2)
            rot = Matrix((Vector((1, 0, 0)), side, d)).transposed()
            rotor.box(tuple(c), (0.035, 0.13, t1 - t0), mat, rot=rot)
    return body, rotor, (hx, hy, hz)


# ---------------------------------------------------------------- スキッド・ステップ

def build_skids():
    m = GMesh()
    r = 0.055
    for sx in (-1, 1):
        x = sx * SKID["x"]
        z0, z1 = SKID["z"]
        pts = [(x, 0.30, z0 - 0.42), (x, 0.16, z0 - 0.30), (x, 0.08, z0 - 0.14), (x, SKID["r"], z0), (x, SKID["r"], z1)]
        m.polyline_tube(pts, SKID["r"], "Charcoal", n=8)
        for cz in SKID["cross_z"]:
            m.polyline_tube([(x, SKID["r"], cz), (x * 0.985, 0.20, cz), (x * 0.86, 0.44, cz), (sx * 1.05, BELLY_Y + 0.03, cz)], r, "Charcoal", n=8)
    return m


def build_step():
    m = GMesh()
    x0, x1, z0, z1 = STEP["x0"], STEP["x1"], STEP["z0"], STEP["z1"]
    y = SPEC["step_y"]
    m.box(((x0 + x1) / 2, y - 0.025, (z0 + z1) / 2), (x1 - x0, 0.05, z1 - z0), "Trim", chamfer=0.012)
    for i in range(4):
        z = z0 + 0.12 + i * (z1 - z0 - 0.24) / 3
        m.box(((x0 + x1) / 2, y + 0.002, z), (x1 - x0 - 0.08, 0.008, 0.04), "Rubber")
    for zz in (z0 + 0.12, z1 - 0.12):
        m.tube((x1 - 0.03, y - 0.05, zz), (-SKID["x"] * 0.94, 0.24, SKID["cross_z"][0]), 0.03, "Charcoal", n=8)
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
    for name, side, mat in (("NavLight_L", -1, "NavRed"), ("NavLight_R", 1, "NavGreen")):
        m = GMesh()
        c, n = side_surface(1.62, -2.45, side)
        m.box(tuple(c + n * 0.04), (0.10, 0.10, 0.18), mat, chamfer=0.02)
        out[name] = m
    b = GMesh()
    bc = anchors["beacon"]
    b.lathe_axis(tuple(bc), (0, 1, 0), [(0.0, 0.055), (0.025, 0.056), (0.05, 0.05), (0.07, 0.034), (0.082, 0.012), (0.085, 0.0)], "NavRed", n=16, weld="beacon:dome")
    out["Beacon"] = b
    land = GMesh()
    c = Vector((0.0, 0.96, -2.82))
    _disc(land, c, (0, -0.55, -0.83), 0.11, "LampWhite")
    _ring(housing, c + Vector((0, -0.55, -0.83)).normalized() * 0.004, (0, -0.55, -0.83), 0.10, 0.15, "Charcoal")
    out["LandingLight"] = land
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


def build_jet(side):
    """1 つの側の部品：pod（翼・ヒンジの筒・ポッド）、nozzle（羽根）、glow（奥の光）、mount（機体の取り付け台・動かない）。
    返す pivots は Godot の座標：pod＝ヒンジの中心、nozzle＝羽根の付け根の中心、glow＝光の円の中心。"""
    pod, nozzle, glow, mount = GMesh(), GMesh(), GMesh(), GMesh()
    h = jet_hinge(side)
    a = jet_axis(side)
    cx, cy = a.x, a.y
    r = JET["pod_r"]
    z0, z1 = JET["hinge_z"]
    # ヒンジの筒（軸と同じ向きなので、回っても形が変わらない）
    pod.tube((h.x, h.y, z0), (h.x, h.y, z1), 0.085, "Charcoal", n=12)
    # 短い翼：付け根（機体の中）から先（ポッドの中）へ、厚さと幅を細らせる
    root_x, tip_x = h.x - side * 0.05, cx - side * r * 0.55
    rz0, rz1, rt = 0.30, 1.20, 0.075
    tz0, tz1, tt = 0.42, 1.06, 0.050
    q = {
        "r0d": (root_x, cy - rt, rz0), "r1d": (root_x, cy - rt, rz1), "r0u": (root_x, cy + rt, rz0), "r1u": (root_x, cy + rt, rz1),
        "t0d": (tip_x, cy - tt, tz0), "t1d": (tip_x, cy - tt, tz1), "t0u": (tip_x, cy + tt, tz0), "t1u": (tip_x, cy + tt, tz1),
    }
    pod._oriented([q["r0u"], q["r1u"], q["t1u"], q["t0u"]], (0, 1, 0), "BodyPaint")
    pod._oriented([q["r0d"], q["t0d"], q["t1d"], q["r1d"]], (0, -1, 0), "BodyPaint")
    pod._oriented([q["r0d"], q["r0u"], q["t0u"], q["t0d"]], (0, 0, -1), "Trim")      # 前の縁は白
    pod._oriented([q["r1d"], q["t1d"], q["t1u"], q["r1u"]], (0, 0, 1), "BodyPaint")
    # ポッド（外板）
    _lathe(pod, cx, cy, [(-0.28, r * 0.80), (-0.24, r * 0.93), (-0.14, r * 0.99), (0.30, r), (1.20, r * 0.965), (1.55, r * 0.87), (1.72, r * 0.76)], "BodyPaint")
    # 白い帯（外板の少し外）
    _lathe(pod, cx, cy, [(0.06, r * 1.012), (0.22, r * 1.012)], "Trim")
    # 吸い込み口：内側の縁 → 暗い奥 → 円すいのスピナー
    _lathe(pod, cx, cy, [(-0.28, r * 0.80), (-0.20, r * 0.70)], "Charcoal", outward=False)
    _ring(pod, Vector((cx, cy, -0.20)), (0, 0, -1), 0.085, r * 0.70, "DashDark", n=16)
    _lathe(pod, cx, cy, [(-0.33, 0.004), (-0.29, 0.045), (-0.20, 0.085)], "Trim", n=12)
    # 噴射口の付け根（動かない輪）と奥の暗い面
    _lathe(pod, cx, cy, [(1.72, r * 0.76), (1.80, 0.195)], "Charcoal")
    _ring(pod, Vector((cx, cy, 1.80)), (0, 0, 1), 0.172, 0.195, "Charcoal", n=16)
    _lathe(pod, cx, cy, [(1.66, 0.172), (1.80, 0.172)], "Charcoal", outward=False)
    _disc(pod, Vector((cx, cy, 1.66)), (0, 0, 1), 0.172, "DashDark", n=16)
    # 噴射口の羽根（JetNozzle）：付け根から先へすぼまる 10 枚。Godot は付け根の中心で x・y に広げる
    nz0, nz1 = JET["nozzle_z"]
    nr0, nr1 = JET["nozzle_r"]
    n = JET["petals"]
    for k in range(n):
        a0 = 2 * math.pi * (k + 0.06) / n
        a1 = 2 * math.pi * (k + 0.94) / n
        am = (a0 + a1) / 2
        pts_o = [(cx + rr * math.cos(t), cy + rr * math.sin(t), zz) for rr, zz, t in ((nr0, nz0, a0), (nr0, nz0, a1), (nr1, nz1, a1), (nr1, nz1, a0))]
        nrm = (math.cos(am) * (nz1 - nz0), math.sin(am) * (nz1 - nz0), nr0 - nr1)
        nozzle._oriented(pts_o, nrm, "Charcoal")
        pts_i = [(cx + (rr - 0.012) * math.cos(t), cy + (rr - 0.012) * math.sin(t), zz) for rr, zz, t in ((nr0, nz0, a0), (nr0, nz0, a1), (nr1, nz1, a1), (nr1, nz1, a0))]
        nozzle._oriented(pts_i, tuple(-v for v in nrm), "DashDark")
        # 先の縁（羽根の厚み）
        e = [pts_o[3], pts_o[2], pts_i[2], pts_i[3]]
        nozzle._oriented(e, (0, 0, 1), "Trim")
    # 奥の光（JetGlow）
    _disc(glow, Vector((cx, cy, JET["glow_z"])), (0, 0, 1), 0.165, "JetGlow", n=16)
    # 機体の取り付け台（動かない）：ヒンジを抱える黒い台
    mount.box((h.x - side * 0.02, h.y, (z0 + z1) / 2), (0.12, 0.26, z1 - z0 + 0.10), "Charcoal", chamfer=0.03)
    pivots = {"pod": Vector((h.x, h.y, h.z)), "nozzle": Vector((cx, cy, nz0)), "glow": Vector((cx, cy, JET["glow_z"])),
              "exit": Vector((cx, cy, nz1))}
    return pod, nozzle, glow, mount, pivots

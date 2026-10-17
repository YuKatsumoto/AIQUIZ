"""乗り込めるヘリのコックピット（ガラス越しに見える室内）：計器盤・ひさし・コンソール・天井のパネル・壁とドアの内側・後ろの仕切り・床・座席。

すべて Godot の座標（地面基準、機首 -z）。座席・操縦かん・計器盤の位置と高さは動かさない（ハテナの姿勢がこれに合わせてある）。
守る決まり（cabin_checks で確かめる）：
  - 計器盤の上は、ハテナの口（1.935）の前（|x − 0.77| < 0.35）で 1.835 まで
  - 左の壁の出っ張りは、プレイヤーの足（Zone A）と肘（Zone B）のあたりで 0.02 まで
  - 天井のパネルは z −1.98〜−1.62、|x| ≤ 0.13、下面 ≥ 3.12（立って乗り込むときの帽子）。天井灯（MK_CockpitLight）から 0.15 離す
  - 床下ハッチの縦穴（|x| < 0.64、z −0.19〜0.99）と、プレイヤーの足の床（≤ 0.704）
"""
from __future__ import annotations

import math

from mathutils import Matrix, Vector

from hb_common import HAZARD_BLACK, HAZARD_RED, HAZARD_YELLOW, NAVY, SPEC, GMesh, body_params, section_extent, section_point

DASH = SPEC["dash"]
SEAT = SPEC["seat"]
FLOOR_Y = SPEC["floor_y"]
WALL = SPEC["body_profile"]["wall"]


def inner_hw(y, z):
    return section_extent(z, y=y, inner=True)


def yoke_mids():
    return [(Vector(y["grip_l"]).x + Vector(y["grip_r"]).x) / 2 for y in SPEC["yokes"]]


def _rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def _rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def _rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


# ---------------------------------------------------------------- 計器盤

def build_dash():
    """計器盤（六角の箱・ひさし・丸い縁・コンパス・前の面の機器・後ろの面の分割した画面と計器・無線）と、光る画面（DashScreens）。"""
    from hb_parts import _disc, _ring
    m, glow = GMesh(), GMesh()
    zb, zf = DASH["back_z"], DASH["front_z"]
    yb, yt = DASH["bottom_y"], DASH["top_y"]
    # D1 六角の箱（角が外板に当たらない）
    m.prism_y([(-1.42, zb), (1.42, zb), (1.42, -2.48), (1.28, zf), (-1.28, zf), (-1.42, -2.48)], yb, yt, "DashDark")
    # D2 ひさし（風防に当たらないよう、内側の幅 − 0.03 で切る）
    zs = [-2.205, -2.46, -2.52, -2.58, -2.62, -2.665]
    right = [(min(1.44, inner_hw(1.81, z) - 0.03), z) for z in zs]
    poly = right + [(-x, z) for x, z in reversed(right)]
    m.prism_y(poly, yt, 1.81, "Charcoal")
    # D3 後ろの丸い縁
    m.tube((-1.40, 1.78, -2.205), (1.40, 1.78, -2.205), 0.025, "Rubber", n=8)
    # D4 コンパス（まん中だけ。顔の帯より内）
    m.box((0.0, 1.8425, -2.40), (0.10, 0.065, 0.085), "Charcoal", chamfer=0.012)
    _disc(m, Vector((0.0, 1.845, -2.3565)), (0, 0, 1), 0.026, "Trim", n=10)
    mids = yoke_mids()
    xm = [mids[0] - 0.215, mids[0] + 0.215, mids[1] - 0.215, mids[1] + 0.215]
    # D5 前の面（風防越しに見える）：機器の背中
    for x in xm:
        m.box((x, 1.585, -2.645), (0.16, 0.13, 0.05), "Charcoal", chamfer=0.008)
    # D6 計器の缶
    for x in (mids[0] + 0.445, mids[1] - 0.445):
        m.tube((x, 1.585, -2.62), (x, 1.585, -2.70), 0.055, "Charcoal", n=10)
        _disc(m, Vector((x, 1.585, -2.702)), (0, 0, -1), 0.04, "Trim", n=10)
    # D7 まん中の機器（格子・銘板）
    m.box((0.0, 1.585, -2.655), (0.40, 0.20, 0.07), "Charcoal", chamfer=0.012)
    for y in (1.505, 1.525, 1.545, 1.565):
        m.box((0.0, y, -2.694), (0.30, 0.010, 0.008), "Trim")
    m.box((0.0, 1.635, -2.693), (0.30, 0.065, 0.006), "Trim")
    # D8 配線の束
    for pts in ([(xm[1], 1.52, -2.67), (xm[1] + 0.07, 1.42, -2.74), (xm[1] + 0.21, 1.26, -2.79), (xm[1] + 0.35, 1.08, -2.80)],
                [(0.0, 1.485, -2.66), (0.03, 1.38, -2.73), (0.05, 1.20, -2.78), (0.05, 1.02, -2.80)],
                [(xm[2], 1.52, -2.67), (xm[2] + 0.07, 1.42, -2.74), (xm[2] + 0.21, 1.26, -2.79), (xm[2] + 0.35, 1.08, -2.80)]):
        m.polyline_tube(pts, 0.011, "Rubber", n=6)
    # D9 横の吹き出し口
    for s in (-1, 1):
        c = Vector((s * 1.35, 1.58, -2.55))
        n = Vector((s * 0.707, 0.0, -0.707))
        _ring(m, c + n * 0.004, tuple(n), 0.032, 0.048, "Charcoal", n=10)
        _disc(m, c + n * 0.002, tuple(n), 0.032, "Rubber", n=10)
        m.tube(tuple(c), tuple(c + n * 0.02), 0.012, "Trim", n=6)
    # D10 後ろの面の分割した画面（操縦かんの柱をよける）
    for k, x in enumerate(xm):
        m.box((x, 1.585, zb + 0.007), (0.25, 0.20, 0.014), "Charcoal", chamfer=0.005)
        glow._oriented([(x - 0.10, 1.51, zb + 0.0155), (x + 0.10, 1.51, zb + 0.0155), (x + 0.10, 1.66, zb + 0.0155), (x - 0.10, 1.66, zb + 0.0155)], (0, 0, 1), "ScreenGlow",
                       uv=UI_RECTS.get(f"mfd{k}"))
        for dy in (-0.087, 0.087):
            m.box((x, 1.585 + dy, zb + 0.016), (0.16, 0.010, 0.005), "Trim")
    # D11 操縦かんの柱のブーツ
    for y in SPEC["yokes"]:
        mid = (Vector(y["grip_l"]).x + Vector(y["grip_r"]).x) / 2
        by = y["bar_y"] + 0.06
        m.lathe_axis((mid, by, zb), (0, 0, 1), [(0.0, 0.085), (0.02, 0.074), (0.042, 0.056)], "Rubber", n=12, weld=f"cockpit:boot{mid:.2f}")
    # D12 計器（白い縁・黒い輪・光る文字盤・針）
    for k, x in enumerate((mids[0] - 0.445, mids[0] + 0.445, mids[1] - 0.445, mids[1] + 0.445)):
        m.tube((x, 1.585, zb + 0.003), (x, 1.585, zb + 0.03), 0.07, "Trim", n=12)
        _ring(m, Vector((x, 1.585, zb + 0.031)), (0, 0, 1), 0.058, 0.07, "Charcoal", n=16)
        glow._oriented([(x + 0.058 * math.cos(2 * math.pi * j / 16), 1.585 + 0.058 * math.sin(2 * math.pi * j / 16), zb + 0.033) for j in range(16)], (0, 0, 1), "ScreenGlow",
                       uv=_disc_uv(UI_RECTS.get(f"dial{k}"), 16))
        ang = (35.0, -50.0, 110.0, -15.0)[k]
        m.box((x, 1.585, zb + 0.035), (0.006, 0.048, 0.003), "Charcoal", rot=_rot_z(ang))
    # D13 無線
    for k, y in enumerate((1.47, 1.555, 1.64)):
        m.box((0.0, y, zb + 0.01), (0.36, 0.072, 0.02), "Charcoal", chamfer=0.004)
        glow._oriented([(-0.135, y - 0.016, zb + 0.0205), (-0.005, y - 0.016, zb + 0.0205), (-0.005, y + 0.016, zb + 0.0205), (-0.135, y + 0.016, zb + 0.0205)], (0, 0, 1), "ScreenGlow",
                       uv=UI_RECTS.get(f"radio{k}"))
        for kx in (0.08, 0.135):
            m.tube((kx, y, zb + 0.02), (kx, y, zb + 0.038), 0.014, "Trim", n=6)
    return m, glow


UI_RECTS: dict = {}     # 光る画面の UV の四角（hb_textures が書く。なければ UV なし＝不透明のマス）


def _disc_uv(rect, n):
    if rect is None:
        return None
    (u0, v0), (u1, _), (_, v1), _ = rect
    cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
    ru, rv = (u1 - u0) / 2, (v1 - v0) / 2
    return [(cu + ru * math.cos(2 * math.pi * j / n), cv + rv * math.sin(2 * math.pi * j / n)) for j in range(n)]


# ---------------------------------------------------------------- コンソール・天井のパネル

def build_console():
    from hb_parts import _disc, _ring
    m, glow = GMesh(), GMesh()
    top = 1.28
    # 計器盤の下からの箱（今までの形）とレバー・ボタン
    cz0, cz1 = DASH["back_z"], SEAT["back_z"] - 0.05
    hw = SPEC["console_half_w"]
    m.box((0, (FLOOR_Y + top) / 2, (cz0 + cz1) / 2), (2 * hw, top - FLOOR_Y, cz1 - cz0), "DashDark", chamfer=0.04)
    m.tube((0.0, top, -1.25), (0.0, 1.52, -1.32), 0.025, "Charcoal", n=8)
    m.box((0.0, 1.55, -1.33), (0.08, 0.07, 0.08), "Rubber", chamfer=0.015)
    for i, mat in enumerate(("NavGreen", "LampWhite", "NavRed")):
        glow.box((-0.09 + i * 0.09, 1.285, -1.55), (0.05, 0.012, 0.05), mat)
    # C1 スイッチの板とトグル
    m.box((0.0, 1.287, -2.06), (0.30, 0.014, 0.36), "DashDark")
    for z in (-2.16, -2.02):
        for x in (-0.105, -0.035, 0.035, 0.105):
            m.box((x, 1.298, z), (0.024, 0.008, 0.024), "Charcoal")
            m.box((x, 1.318, z - 0.004), (0.009, 0.040, 0.009), "Trim", rot=_rot_x(-20.0))
    # C2 回すつまみ
    for x in (-0.07, 0.07):
        m.tube((x, 1.294, -1.93), (x, 1.316, -1.93), 0.022, "Rubber", n=10)
        m.box((x, 1.318, -1.93 - 0.012), (0.006, 0.004, 0.02), "Trim")
    # C3 縁の板
    m.box((0.0, 1.283, -1.55), (0.28, 0.006, 0.09), "Charcoal")
    m.box((0.0, 1.284, -1.30), (0.07, 0.008, 0.22), "Charcoal")
    # C4 ジェットのレバー（赤く光るつまみ）と黄黒の札
    m.tube((-0.08, top, -1.22), (-0.08, 1.44, -1.28), 0.012, "Charcoal", n=6)
    glow.tube((-0.08, 1.44, -1.28), (-0.08, 1.475, -1.29), 0.02, "NavRed", n=8)
    _hazard_tile(m, Vector((-0.08, top + 0.0015, -1.20)), Vector((1, 0, 0)), Vector((0, 0, 1)), 0.08, 0.08, (0, 1, 0))
    # C5 カップホルダー
    _ring(m, Vector((0.08, 1.282, -1.02)), (0, 1, 0), 0.035, 0.05, "Charcoal", n=12)
    m.lathe_axis((0.08, 1.282, -1.02), (0, -1, 0), [(0.0, 0.035), (0.06, 0.035)], "DashDark", n=12, outward=False, weld="cockpit:cup")
    _disc(m, Vector((0.08, 1.222, -1.02)), (0, 1, 0), 0.035, "DashDark", n=12)
    # C6 横の継ぎ目
    for s in (-1, 1):
        for z in (-1.9, -1.4):
            m.box((s * (hw + 0.003), 0.98, z), (0.006, 0.30, 0.012), "Charcoal")
    return m, glow


def _hazard_tile(m, centre, u, v, w, h, normal):
    """黄黒の 45° の縞の小さな札（形で作る。頂点色）。"""
    k = 0
    step = 0.02
    s = -h
    while s < w:
        col = HAZARD_YELLOW if k % 2 == 0 else HAZARD_BLACK
        quad = []
        for a, b in ((s, 0.0), (s + step, 0.0), (s + step + h, h), (s + h, h)):
            aa = min(max(a, 0.0), w)
            quad.append(tuple(centre + u * (aa - w / 2) + v * (b - h / 2)))
        if (Vector(quad[1]) - Vector(quad[0])).length > 1e-5 or (Vector(quad[2]) - Vector(quad[3])).length > 1e-5:
            m._oriented(quad, tuple(normal), "Trim", col=col)
        s += step
        k += 1


def build_overhead():
    """天井のパネル（z −1.98〜−1.62、|x| ≤ 0.13。立って乗り込むときの帽子と天井灯をよける）。"""
    from hb_parts import _disc, _ring
    m, glow = GMesh(), GMesh()
    zs = [-1.98, -1.89, -1.80, -1.71, -1.62]
    secs = []
    for z in zs:
        yc = section_extent(z, x=0.0, inner=True) + 0.015
        secs.append([(-0.13, yc, z), (-0.10, yc - 0.10, z), (0.10, yc - 0.10, z), (0.13, yc, z)])
    for i in range(len(secs) - 1):
        for k in range(3):
            quad = [secs[i][k], secs[i][k + 1], secs[i + 1][k + 1], secs[i + 1][k]]
            mid = sum((Vector(q) for q in quad), Vector()) / 4
            m._oriented(quad, tuple(mid - Vector((0.0, secs[i][0][1] - 0.04, mid.z))), "DashDark")
    m._oriented(secs[0], (0, 0, -1), "DashDark")
    m._oriented(secs[-1], (0, 0, 1), "DashDark")

    def bottom_frame(z):
        y0 = section_extent(z - 0.01, x=0.0, inner=True)
        y1 = section_extent(z + 0.01, x=0.0, inner=True)
        dy = (y1 - y0) / 0.02
        t = Vector((0.0, dy, 1.0)).normalized()
        n = Vector((0.0, -1.0, dy)).normalized()
        y = section_extent(z, x=0.0, inner=True) + 0.015 - 0.10
        return y, n, t

    for z in (-1.92, -1.80):
        y, n, t = bottom_frame(z)
        for x in (-0.075, -0.025, 0.025, 0.075):
            b = Vector((1, 0, 0))
            rot = Matrix((b, -n, t)).transposed()
            p = Vector((x, y, z))
            m.box(tuple(p + n * 0.004), (0.022, 0.008, 0.022), "Charcoal", rot=rot)
            m.box(tuple(p + n * 0.02), (0.008, 0.03, 0.008), "Trim", rot=rot @ _rot_x(-20.0))
    y, n, t = bottom_frame(-1.69)
    for x in (-0.06, 0.0, 0.06):
        p = Vector((x, y, -1.69))
        m.tube(tuple(p), tuple(p + n * 0.02), 0.016, "Rubber", n=8)
    y, n, t = bottom_frame(-1.65)
    for x in (-0.065, 0.065):
        p = Vector((x, y, -1.65)) + n * 0.002
        _ring(m, p, tuple(n), 0.02, 0.028, "Charcoal", n=10)
        _disc(glow, p + n * 0.001, tuple(n), 0.02, "LampWhite", n=10)
    y, n, t = bottom_frame(-1.95)
    c = Vector((0.0, y, -1.95)) + n * 0.002
    rect = UI_RECTS.get("annunciator")
    glow._oriented([tuple(c + Vector((-0.09, 0, 0)) - t * 0.011), tuple(c + Vector((0.09, 0, 0)) - t * 0.011),
                    tuple(c + Vector((0.09, 0, 0)) + t * 0.011), tuple(c + Vector((-0.09, 0, 0)) + t * 0.011)], tuple(n), "ScreenGlow", uv=rect)
    return m, glow


# ---------------------------------------------------------------- 壁・ドアの内側

def _rail(m, zs, side, y_top, y_bot, protrude, mat):
    rows = []
    for z in zs:
        xt = inner_hw(y_top, z)
        xb = inner_hw(y_bot, z)
        rows.append([(side * (xt + 0.004), y_top, z), (side * (xt - protrude), y_top, z), (side * (xb - protrude), y_bot, z), (side * (xb + 0.004), y_bot, z)])
    for i in range(len(rows) - 1):
        for k in range(3):
            quad = [rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]]
            hint = ((0, 1, 0), (-side, 0, 0), (0, -1, 0))[k]
            m._oriented(quad, hint, mat)


def build_cabin_walls():
    """ドアの内側（ベルトの線のレール・取っ手・内張りの縁）と、後ろの壁のレール・骨・敷居の板・天井の取っ手。"""
    from hb_shell import stations
    out = {"Interior": GMesh(), "Door_L": GMesh(), "Door_R": GMesh()}
    door_zs = [z for z in stations() if -2.24 <= z <= -0.56]
    door_zs = [-2.24] + [z for z in door_zs if -2.24 < z < -0.56] + [-0.56]
    for side, name, prot in ((-1, "Door_L", 0.015), (1, "Door_R", 0.030)):
        m = out[name]
        _rail(m, door_zs, side, 1.935, 1.875, prot, "Rubber")
        # W3 取っ手
        x = side * (inner_hw(1.53, -0.70) - 0.035)
        m.tube((x, 1.42, -0.70), (x, 1.64, -0.70), 0.012, "Trim", n=6)
        for y in (1.42, 1.64):
            m.box((x + side * 0.02, y, -0.70), (0.035, 0.02, 0.02), "Rubber")
        # W4 内張りの縁（0.006 浮かせる）
        for y in (0.95, 1.75):
            _rail(m, [z for z in door_zs if -2.05 <= z <= -0.75], side, y + 0.0075, y - 0.0075, 0.006, "Rubber")
    walls = out["Interior"]
    rear_zs = [-0.54, -0.30, 0.0, 0.30, 0.60, 0.90, 1.12]
    for side in (-1, 1):
        _rail(walls, rear_zs, side, 1.935, 1.875, 0.02, "Rubber")
        # W5 骨（z 0.05・0.65）
        for zc in (0.05, 0.65):
            pts = []
            p = body_params(zc)
            for k in range(9):
                y = 0.86 + (3.05 - 0.86) * k / 8
                x = inner_hw(y, zc)
                if x is None:
                    continue
                pts.append((side * (x - 0.008), y))
            for (xa, ya), (xb, yb) in zip(pts[:-1], pts[1:]):
                q = [(xa, ya, zc - 0.025), (xb, yb, zc - 0.025), (xb, yb, zc + 0.025), (xa, ya, zc + 0.025)]
                walls._oriented(q, (-side, 0, 0), "Charcoal")
        # 敷居の板は付けない（プレイヤーが足を置くドア口の床 0.70 にかかる）
        # W7 天井の取っ手（ヒンジより内、開くドアの帯より後ろ）
        c = section_extent(-0.80, x=0.27, inner=True)
        x = side * 0.27
        walls.polyline_tube([(x, c - 0.03, -0.95), (x, c - 0.08, -0.90), (x, c - 0.08, -0.70), (x, c - 0.03, -0.65)], 0.014, "Charcoal", n=6)
        for z in (-0.95, -0.65):
            walls.box((x, c - 0.021, z), (0.04, 0.026, 0.04), "Charcoal")     # 上面は内張りの 8 mm 下（屋根の板の中を開いたドアの縁が通る）
    return out


# ---------------------------------------------------------------- 後ろの仕切り・床

# 後ろの仕切りのコルクボード：ハテナがこれまで乗せた人との写真（Godot で撮る：tests/heli_board_photos.gd）。
# 絵（コルク・写真の枠・シール）は hb_textures がアトラスの BOARD に描き、ここは板と画びょうを作る。
# 座標は板の上の (s, t)：s は見る人の右（Godot の −x）、t は上、単位 m、コルクの中心が原点。傾きは度（見る人から反時計回り）。
BOARD = {
    "center": (0.0, 2.45),            # コルクの中心（Godot の x, y）
    "size": (0.64, 1.08),             # コルク（紺の板 0.72 × 1.16 の、面取りの内側の平らな面に収める）
    "lift": 0.0015,                   # 紺の板の前の面からコルクの面まで
    "polaroid": (0.270, 0.320, 0.236),   # 写真の枠の幅・高さ、写真の一辺（上と左右の余白が同じ、下が広い）
    "photos": [
        # 名前（board_photos/<名前>.png）、中心 (s, t)、傾き、画びょうの色
        ("goal", (-0.148, 0.272), -4.0, "#D8352B"),
        ("shark", (0.150, 0.236), 5.0, "#F2C230"),
        ("wave", (-0.150, -0.106), 3.0, "#2F7FE0"),
        ("hatena", (0.148, -0.140), -5.0, "#3BB36A"),
    ],
    "sticker": {"center": (0.150, -0.432), "diameter": 0.10},
}
BOARD_GRID = (6, 10)                  # コルクの面の分け方（焼いた AO が板の中で変われるように）


def board_point(s, t, z):
    """板の上の (s, t) → Godot の点。z はそのままの Godot の z。"""
    cx, cy = BOARD["center"]
    return (cx - s, cy + t, z)


def board_pin_points():
    """写真ごとの画びょうの位置 (s, t) と色：枠の上の辺のまん中から 0.022 下（写真の傾きで回す）。"""
    _, ph, _ = BOARD["polaroid"]
    out = []
    for _name, (cs, ct), deg, col in BOARD["photos"]:
        a = math.radians(deg)
        ds, dt = 0.0, ph / 2 - 0.022
        out.append(((cs + ds * math.cos(a) - dt * math.sin(a), ct + ds * math.sin(a) + dt * math.cos(a)), col))
    return out


def build_board(m, zb):
    """コルクの面（材質 Decal、アトラスの BOARD）と画びょう（Trim に頂点色）。"""
    from hb_common import hexcol
    w, h = BOARD["size"]
    z = zb - 0.047 - BOARD["lift"]
    rect = UI_RECTS.get("board")
    nu, nv = BOARD_GRID
    (u0, v0), (u1, _), (_, v1), _ = rect if rect is not None else [(0.5, 0.5)] * 4
    for i in range(nu):
        for j in range(nv):
            ss = [-w / 2 + w * (i + k) / nu for k in (0, 1)]
            ts = [-h / 2 + h * (j + k) / nv for k in (0, 1)]
            corners = [(ss[0], ts[0]), (ss[1], ts[0]), (ss[1], ts[1]), (ss[0], ts[1])]
            pts = [board_point(s, t, z) for s, t in corners]
            uv = [(u0 + (s / w + 0.5) * (u1 - u0), v0 + (t / h + 0.5) * (v1 - v0)) for s, t in corners] if rect is not None else None
            m._oriented(pts, (0, 0, -1), "Decal", uv=uv, col=(1.0, 1.0, 1.0, 1.0))
    # 画びょう：コルクに当たる鍔・首・つまみ（-z へ出る）
    for (s, t), col in board_pin_points():
        x, y, _ = board_point(s, t, z)
        c = hexcol(col)
        m.lathe_axis((x, y, z), (0, 0, -1), [(0.0, 0.011), (0.003, 0.011), (0.004, 0.0045), (0.009, 0.0045),
                                             (0.010, 0.008), (0.019, 0.007)], "Trim", n=10, cols=[c] * 6, cap1="flat")


def build_bulkhead():
    from hb_parts import _disc, _ring
    m, glow = GMesh(), GMesh()
    zb = SPEC["bay"]["rear_z"]
    # B1 ふかふかの紺の板（コルクボードの縁）
    m.box((0.0, 2.45, zb - 0.0245), (0.72, 1.16, 0.045), "SeatFabric", chamfer=0.03)
    # B2 コルクボード：写真 4 枚・見出し・メモ・シール（絵はアトラス）と画びょう
    build_board(m, zb)
    # B4 道具のレール
    m.tube((-0.62, 3.08, zb - 0.05), (0.62, 3.08, zb - 0.05), 0.016, "Charcoal", n=6)
    for x in (-0.55, 0.55):
        m.box((x, 3.08, zb - 0.025), (0.03, 0.03, 0.05), "Charcoal")
    # B5 天井の灯（後ろ）
    _ring(m, Vector((0.0, 3.452, 0.4)), (0, -1, 0), 0.10, 0.13, "Charcoal", n=12)
    _disc(glow, Vector((0.0, 3.450, 0.4)), (0, -1, 0), 0.10, "LampWhite", n=12)
    # B6 消火器（赤い頂点色の白い材質）
    base = (1.02, 1.16, 1.07)
    m.lathe_axis(base, (0, 1, 0), [(0.0, 0.062), (0.03, 0.072), (0.40, 0.072), (0.45, 0.05), (0.48, 0.025)], "Trim", n=12, weld="cockpit:ext", cols=[HAZARD_RED] * 5, cap0="flat")
    m.box((1.02, 1.665, 1.07), (0.05, 0.05, 0.05), "Charcoal")
    m.box((1.02, 1.70, 1.05), (0.012, 0.02, 0.10), "Trim", rot=_rot_x(-15.0))
    m.polyline_tube([(1.05, 1.66, 1.07), (1.10, 1.62, 1.05), (1.10, 1.35, 1.03), (1.08, 1.25, 1.02)], 0.009, "Rubber", n=6)
    for y in (1.30, 1.52):
        m.lathe_axis((1.02, y - 0.01, 1.07), (0, 1, 0), [(0.0, 0.075), (0.02, 0.075)], "Charcoal", n=12, smooth=False)
    m.box((1.02, 1.40, zb - 0.006), (0.10, 0.40, 0.012), "Charcoal")
    # B7 地図入れ・B8 点検のふた
    m.box((0.60, 1.28, zb - 0.02), (0.40, 0.34, 0.035), "SeatFabric", chamfer=0.01)
    m.box((0.60, 1.44, zb - 0.04), (0.40, 0.02, 0.006), "Charcoal")
    m.box((0.60, 1.47, zb - 0.035), (0.30, 0.06, 0.006), "Trim")
    m.box((-0.60, 1.30, zb - 0.003), (0.36, 0.28, 0.006), "DashDark")
    for dx in (-0.16, 0.16):
        for dy in (-0.12, 0.12):
            _disc(m, Vector((-0.60 + dx, 1.30 + dy, zb - 0.0065)), (0, 0, -1), 0.008, "Trim", n=6)
    return m, glow


def build_floor_detail():
    """入口の踏み板（上面 ≤ 0.704）と、床下ハッチのまわりの黄黒の縁（形で作る）。"""
    m = GMesh()
    m.box((-0.97, FLOOR_Y + 0.001, -1.40), (0.24, 0.002, 0.90), "DashDark", faces=("+y",))
    for k in range(6):
        m.box((-0.97, FLOOR_Y + 0.003, -1.775 + 0.15 * k), (0.20, 0.002, 0.03), "Rubber", faces=("+y",))
    hw = SPEC["hatch"]["half_w"]
    hz0, hz1 = SPEC["hatch"]["z"]
    y = FLOOR_Y + 0.002
    up = Vector((0, 1, 0))
    for sx in (-1, 1):
        _hazard_strip(m, Vector((sx * (hw + 0.03), y, hz0 - 0.06)), Vector((0, 0, 1)), Vector((1, 0, 0)), (hz1 - hz0) + 0.12, 0.06, up)
    for zc in (hz0 - 0.03, hz1 + 0.03):
        _hazard_strip(m, Vector((-hw, y, zc)), Vector((1, 0, 0)), Vector((0, 0, 1)), 2 * hw, 0.06, up)
    return m


def _hazard_strip(m, start, u, v, length, width, normal):
    step = 0.06
    k = 0
    s = 0.0
    while s < length - 1e-6:
        e = min(s + step, length)
        col = HAZARD_YELLOW if k % 2 == 0 else HAZARD_BLACK
        quad = [tuple(start + u * s - v * (width / 2)), tuple(start + u * e - v * (width / 2)), tuple(start + u * e + v * (width / 2)), tuple(start + u * s + v * (width / 2))]
        m._oriented(quad, tuple(normal), "Trim", col=col)
        s = e
        k += 1


# ---------------------------------------------------------------- 座席

def build_seat_detail(sx):
    """座席（Seat_*）：ヘッドレスト・しまった肩のベルト・レール・高さのレバー・背中の物入れ。"""
    from hb_parts import _strap
    m = GMesh()
    x = sx * SEAT["x"]
    R = _rot_x(SEAT["back_tilt_deg"])
    h = SEAT["back_top_y"] - SEAT["top_y"]
    base = Vector((x, SEAT["top_y"], SEAT["back_z"]))

    def L(lx, ly, lz):
        return base + R @ Vector((lx, ly, lz))

    m.box(tuple(L(0.0, h + 0.16, 0.075)), (0.50, 0.24, 0.13), "SeatFabric", rot=R, chamfer=0.055)
    for lx in (-0.10, 0.10):
        m.tube(tuple(L(lx, h - 0.02, 0.075)), tuple(L(lx, h + 0.05, 0.075)), 0.013, "Charcoal", n=6)
    for lx in (-0.20, 0.20):
        path = [L(lx, h - 0.30, 0.188), L(lx, h - 0.05, 0.188), L(lx, h + 0.012, 0.12), L(lx, h + 0.012, 0.048), L(lx, h - 0.05, -0.012),
                L(lx * 0.92, h - 0.40, -0.012), L(lx * 0.85, h - 0.60, -0.012)]
        _strap(m, [tuple(p) for p in path], 0.05, 0.01, "Charcoal", wdir=(1, 0, 0))
        m.box(tuple(L(lx, h - 0.25, -0.02)), (0.055, 0.025, 0.012), "Trim", rot=R)
        m.box(tuple(L(lx * 0.85, h - 0.62, -0.02)), (0.045, 0.06, 0.010), "Trim", rot=R)
    for dx in (-0.30, 0.30):
        m.box((x + dx, 0.7125, -0.94), (0.035, 0.025, 0.72), "Charcoal")
    lx = x + sx * (0.425 + 0.03)
    m.polyline_tube([(lx, 0.90, -1.30), (lx, 0.90, -1.20), (lx, 0.93, -1.16)], 0.009, "Trim", n=6)
    m.box(tuple(L(0.0, 0.32, 0.20)), (0.66, 0.36, 0.035), "SeatFabric", rot=R, chamfer=0.012)
    m.box(tuple(L(0.0, 0.50, 0.22)), (0.62, 0.02, 0.006), "Charcoal", rot=R)
    return m


def build_headset():
    """左の席の外側の上に掛けたヘッドセット（Seat_L）。"""
    m = GMesh()
    m.box((-1.335, 2.01, -0.592), (0.03, 0.04, 0.03), "Charcoal")
    arc = []
    for k in range(9):
        phi = math.radians(200.0 - 220.0 * k / 8)
        arc.append((-1.36, 1.94 + 0.085 * math.sin(phi), -0.592 + 0.085 * math.cos(phi)))
    m.polyline_tube(arc, 0.011, "Trim", n=6)
    for z, d in ((-0.672, 1), (-0.512, -1)):
        m.tube((-1.36, 1.88, z), (-1.36, 1.88, z + d * 0.035), 0.048, "Trim", n=12, col=NAVY)
        m.tube((-1.36, 1.88, z + d * 0.035), (-1.36, 1.88, z + d * 0.045), 0.042, "Charcoal", n=12)
    m.polyline_tube([(-1.36, 1.86, -0.672), (-1.33, 1.80, -0.70), (-1.30, 1.79, -0.72)], 0.005, "Charcoal", n=4)
    m.polyline_tube([(-1.36, 1.84, -0.60), (-1.37, 1.70, -0.62), (-1.37, 1.55, -0.62)], 0.004, "Charcoal", n=4)
    return m


# ---------------------------------------------------------------- 確かめ

def cabin_checks(objs, G, ceiling_band, floor_points=None):
    """客室の決まり（行のリスト）。G は Blender → Godot の変換。floor_points：足の床を測る点（Godot。座席・操縦かんを除いた Interior）。"""
    rows = []

    def add(name, ok, detail=""):
        rows.append({"check": name, "ok": bool(ok), "detail": detail})

    def world_pts(name):
        o = objs[name]
        return [G(o.matrix_world @ v.co) for v in o.data.vertices]

    cabin = [n for n in ("Interior", "DashScreens") if n in objs]       # 座席は Interior にまとめてある
    poke = []
    for n in cabin:
        for g in world_pts(n):
            w = section_extent(g.z, y=g.y) if -3.1 < g.z < 2.2 else None
            if w is not None and w > 0 and abs(g.x) > w - 0.008 and g.y > FLOOR_Y + 0.01:
                poke.append([n, round(g.x, 3), round(g.y, 3), round(g.z, 3)])
                break
    add("客室の部品が外板から出ない", not poke, str(poke))
    mouth = max((g.y for n in cabin for g in world_pts(n) if abs(abs(g.x) - SEAT["x"]) < 0.35 and -2.7 <= g.z <= -2.1 and g.x > 0), default=0.0)
    add("計器盤の上はハテナの口の前で 1.835 まで", mouth <= 1.835 + 1e-4, f"{mouth:.3f}")
    # 壁に付いた部品（壁から 10 cm 以内）が、プレイヤーの足（Zone A）と肘（Zone B）のあたりで壁から 2 cm より出ないか
    prot = 0.0
    for n in ("Door_L", "Interior"):
        if n not in objs:
            continue
        for g in world_pts(n):
            in_a = -1.80 <= g.z <= -1.45 and 0.76 <= g.y <= 1.00
            in_b = -1.70 <= g.z <= -1.38 and 1.70 <= g.y <= 1.95
            if (in_a or in_b) and g.x < -0.9:
                wall = section_extent(g.z, y=g.y, inner=True)
                if wall is not None and wall - abs(g.x) < 0.10:
                    prot = max(prot, wall - abs(g.x))
    add("左の壁の出っ張り（足・肘のあたり）≤ 0.02", prot <= 0.02 + 1e-4, f"{prot:.3f}")
    low = min((g.y for n in cabin for g in world_pts(n) if abs(g.x) < 0.25 and -2.7 <= g.z <= -0.6 and g.y > 2.5), default=9.0)
    add("天井の部品の下面 ≥ 3.12", low >= 3.12, f"{low:.3f}")
    hole = [n for n in cabin for g in world_pts(n) if abs(g.x) < 0.64 and -0.19 < g.z < 0.99 and g.y < 2.5 and g.y > FLOOR_Y - 0.3][:3]
    add("床下ハッチの縦穴が空いている", not hole, str(hole))
    pts = floor_points if floor_points is not None else world_pts("Interior")
    feet = max((g.y for g in pts if -1.30 <= g.x <= -0.25 and -1.75 <= g.z <= -1.30 and g.y < 0.9), default=0.0)
    add("プレイヤーの足の床 ≤ 0.704", feet <= 0.704 + 1e-4, f"{feet:.4f}")
    light = Vector(SPEC["markers"]["MK_CockpitLight"]["ground"])
    near = min(((g - light).length for g in world_pts("Interior") if g.y > 3.0 and abs(g.x) < 0.2), default=9.0)
    add("天井のパネルと天井灯 ≥ 0.15", near >= 0.15, f"{near:.3f}")
    band_hits = 0
    if ceiling_band:
        (x0, x1), (y0, y1), (z0, z1) = ceiling_band["x"], ceiling_band["y"], ceiling_band["z"]
        for n in cabin:
            for g in world_pts(n):
                if x0 <= abs(g.x) <= x1 and y0 <= g.y <= y1 and z0 <= g.z <= z1:
                    band_hits += 1
    add("開くドアが入る天井の帯に内装の部品がない", band_hits == 0, f"{band_hits} {ceiling_band}")
    return rows

"""AIQUIZ HARBOR LAUNCH の部品。すべて Blender のワールド座標（= メニューの Godot 座標を g2b したもの）で作る。

材質キー（ams_common の Materials）：
  paint    頂点色の塗装（AQS_Painted。ゲームの共有材質に差し替わる）
  lamp     昼も光る灯（AMS_Lamp：琥珀の灯・スポットライトのレンズ）
  glass    ガラスの手すり（AMS_Glass）
  led      LED の面（AMS_LedScreen、UV 0..1）
  sign     看板の面（AMS_Sign、UV 0..1）
  pennant  旗（AMS_Pennant、両面は裏の面を作る。UV2.x = 揺れの重み）
  foliage  ヤシの葉（AMS_Foliage、UV2.x = 揺れの重み）
"""
from __future__ import annotations

import math
import random

from mathutils import Matrix, Vector

from aqs_geom import Mesh, hexcol, mix, shade
from ams_common import (BELT_EDGE, BELT_HALF, BELT_Z0, BELT_Z1, C, CAMERA, DECK_C, DECK_R, DECK_T,
                        FASCIA_T, FASCIA_TOP, LAMP_STEP, NEAR_Z, PILE_BOTTOM, PILE_R, PILE_STEP, RAIL_POST_STEP,
                        SEA_Y, TOWER_H, TOWER_X, TOWER_Z, WALK_BOTTOM, WALK_OUT, WALK_TOP, facing_yaw, g2b)

WALL_T = 0.8


# --- 共通の小道具 ----------------------------------------------------------------
def gv(x, y, z):
    """Godot の座標 → Blender の座標（タプル）。"""
    return (x, -z, y)


def ring(cx, cy, z, r, n, phase=0.0):
    return [(cx + r * math.cos(phase + 2 * math.pi * i / n), cy + r * math.sin(phase + 2 * math.pi * i / n), z) for i in range(n)]


def band_prism(m: Mesh, cx, cy, bands, r, n, smooth=True, phase=0.0):
    """縦の帯（z0, z1, 色）を重ねた丸柱。上下の蓋は最初と最後だけ。"""
    for k, (z0, z1, col) in enumerate(bands):
        m.prism(cx, cy, z0, z1, r, r, n, col, "paint", cap_top=(k == len(bands) - 1), cap_bottom=(k == 0), phase=phase,
                smooth=smooth)


def lamp(m: Mesh, x, y, z, r=0.16, h=0.42, lens_h=0.16):
    """琥珀の灯（暗い台＋光るレンズ）。x, y, z は Blender（z は立ち上がりの下端）。"""
    m.prism(x, y, z, z + h, r, r * 0.92, 8, C["dark"], "paint", cap_top=False)
    m.prism(x, y, z + h, z + h + lens_h, r * 0.88, r * 0.7, 8, C["amber"], "lamp", smooth=True)
    m.prism(x, y, z + h + lens_h, z + h + lens_h + 0.04, r * 0.7, r * 0.5, 8, C["dark"], "paint")


def glass_run(m: Mesh, a, b, z0, z1, post_step, rail_col=None, first_post=True, last_post=True):
    """a→b（Blender の xy）に沿うガラスの手すり：柱・ガラス・コバルトの笠木。"""
    rail_col = rail_col or C["cobalt"]
    ax, ay = a
    bx, by = b
    L = math.hypot(bx - ax, by - ay)
    if L < 0.05:
        return
    n = max(1, round(L / post_step))
    ux, uy = (bx - ax) / L, (by - ay) / L
    nx, ny = -uy, ux
    t = 0.015
    for i in range(n + 1):
        if (i == 0 and not first_post) or (i == n and not last_post):
            continue
        px, py = ax + (bx - ax) * i / n, ay + (by - ay) * i / n
        m.box((px, py, (z0 + z1) / 2), (0.07, 0.07, z1 - z0), C["white"], "paint")
    for i in range(n):
        p0 = (ax + (bx - ax) * i / n + ux * 0.05, ay + (by - ay) * i / n + uy * 0.05)
        p1 = (ax + (bx - ax) * (i + 1) / n - ux * 0.05, ay + (by - ay) * (i + 1) / n - uy * 0.05)
        za, zb = z0 + 0.08, z1 - 0.06
        m.add_face([(p0[0] + nx * t, p0[1] + ny * t, za), (p1[0] + nx * t, p1[1] + ny * t, za),
                    (p1[0] + nx * t, p1[1] + ny * t, zb), (p0[0] + nx * t, p0[1] + ny * t, zb)], C["glass"], "glass")
        m.add_face([(p1[0] - nx * t, p1[1] - ny * t, za), (p0[0] - nx * t, p0[1] - ny * t, za),
                    (p0[0] - nx * t, p0[1] - ny * t, zb), (p1[0] - nx * t, p1[1] - ny * t, zb)], C["glass"], "glass")
    m.beam((ax, ay, z1 + 0.03), (bx, by, z1 + 0.03), 0.11, rail_col, "paint", h=0.07)


PAVE_TILE = 3.0                       # paving.png 1 枚 = 3m 角（1.5m のタイル 2×2）
PAVE_TINT = (0.93, 0.93, 0.93, 1.0)   # 舗装の画像に掛ける頂点色


def planar_uv(pts, tile=PAVE_TILE):
    """上面の平面投影の UV（x, y → u, v）。"""
    return [(p[0] / tile, p[1] / tile) for p in pts]


def arc_points(cx, cy, r, a0, a1, n):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


# --- 走路の縁：外装（KEEP_PIER_FASCIA のときだけ）と、使っていない杭・奥の歩道・灯・照明塔 -------------
# 2026-09-30 から組み立てるのは外装だけ（ams_common.KEEP_PIER_FASCIA が True のとき）。杭・奥の歩道・灯・照明塔
# （piles / edge_walk / edge_lamps / edge_towers）は組み立てから外した。戻すときの参考に関数は残す（light_tower と
# windsock は発進デッキの照明塔が使う）。
def pier_fascia(side: int) -> Mesh:
    """ベルトの箱の側面（x = ±12）を白い桟橋の外装にする。手前（台車の動く所）は操縦席のデッキの下から、奥は歩道の下から。"""
    m = Mesh()
    s = side
    xi, xo = s * BELT_HALF, s * (BELT_HALF + FASCIA_T)
    bottom = SEA_Y - 1.2
    for z_a, z_b, top in ((BELT_Z1 - 0.2, NEAR_Z, FASCIA_TOP), (NEAR_Z, BELT_Z0 + 0.6, WALK_BOTTOM)):
        # Blender：y = -z。z_a が手前（大きい）
        ya, yb = -z_a, -z_b
        cap_lo = top - 0.25
        band_hi, band_lo = top - 0.3, top - 1.0
        rows = [(top, cap_lo, C["white"]), (cap_lo, band_hi, C["white2"]), (band_hi, band_lo, C["cobalt"]),
                (band_lo, SEA_Y + 0.4, C["white"]), (SEA_Y + 0.4, bottom, shade(C["white"], 0.72))]
        for y0, y1, col in rows:
            pts = [(xo, ya, y0), (xo, yb, y0), (xo, yb, y1), (xo, ya, y1)]
            if s > 0:
                pts = [pts[1], pts[0], pts[3], pts[2]]
            m.add_face(pts, col, "paint")
        # 上面（外装の天端）と端の面
        top_pts = [(xi, ya, top), (xo, ya, top), (xo, yb, top), (xi, yb, top)]
        if s < 0:
            top_pts = [top_pts[1], top_pts[0], top_pts[3], top_pts[2]]
        m.add_face(top_pts, C["white"], "paint")
        for yy, sign_y in ((ya, -1), (yb, 1)):
            pts = [(xi, yy, bottom), (xo, yy, bottom), (xo, yy, top), (xi, yy, top)]
            if (s > 0) == (sign_y > 0):
                pts = list(reversed(pts))
            m.add_face(pts, C["white2"], "paint")
    return m


def piles(side: int) -> Mesh:
    """（使っていない）外装の前の白い丸杭（8m ごと）。水際にコバルトの輪、頭に笠。"""
    m = Mesh()
    s = side
    z = BELT_Z1 - 5.0          # 3, -5, -13, ...：手前と奥の境（NEAR_Z）をまたぐ杭を作らない
    while z > BELT_Z0 + 2.0:
        near = z > NEAR_Z
        top = FASCIA_TOP if near else WALK_BOTTOM
        x = s * (BELT_HALF + FASCIA_T + PILE_R - 0.12) if near else s * (WALK_OUT - 0.55)
        bx, by = x, -z
        bands = [(PILE_BOTTOM, SEA_Y - 0.35, shade(C["white"], 0.7)), (SEA_Y - 0.35, SEA_Y + 0.25, C["pile_ring"]),
                 (SEA_Y + 0.25, top - 0.3, C["white"])]
        band_prism(m, bx, by, bands, PILE_R, 12)
        m.prism(bx, by, top - 0.3, top, PILE_R + 0.1, PILE_R + 0.1, 12, C["white2"], "paint", smooth=True)
        z -= PILE_STEP
    return m


def edge_walk(side: int) -> Mesh:
    """（使っていない）奥（台車の動かない所）の歩道：白い板・外面の帯・ガラスの手すり。"""
    m = Mesh()
    s = side
    xi, xo = s * BELT_EDGE, s * WALK_OUT
    z_a, z_b = NEAR_Z, BELT_Z0 + 0.6
    ya, yb = -z_a, -z_b
    # 上面（舗装）：2m ごとに目地の色を交互に
    n = int(abs(yb - ya) / 2.0)
    for i in range(n):
        y0 = ya + (yb - ya) * i / n
        y1 = ya + (yb - ya) * (i + 1) / n
        pts = [(xi, y0, WALK_TOP), (xo, y0, WALK_TOP), (xo, y1, WALK_TOP), (xi, y1, WALK_TOP)]
        if s < 0:
            pts = [pts[1], pts[0], pts[3], pts[2]]
        m.add_face(pts, PAVE_TINT, "paving", uv=planar_uv(pts))
    # 外面：白・コバルト・白
    for y0, y1, col in ((WALK_TOP, WALK_TOP - 0.18, C["white"]), (WALK_TOP - 0.18, WALK_BOTTOM + 0.2, C["cobalt"]),
                        (WALK_BOTTOM + 0.2, WALK_BOTTOM, C["white2"])):
        pts = [(xo, ya, y0), (xo, yb, y0), (xo, yb, y1), (xo, ya, y1)]
        if s > 0:
            pts = [pts[1], pts[0], pts[3], pts[2]]
        m.add_face(pts, col, "paint")
    # 下面と端（手前の端は目立つので白い面）
    bot = [(xi, ya, WALK_BOTTOM), (xi, yb, WALK_BOTTOM), (xo, yb, WALK_BOTTOM), (xo, ya, WALK_BOTTOM)]
    if s < 0:
        bot = [bot[1], bot[0], bot[3], bot[2]]
    m.add_face(bot, shade(C["white"], 0.75), "paint")
    for yy, sign_y in ((ya, -1), (yb, 1)):
        pts = [(xi, yy, WALK_BOTTOM), (xo, yy, WALK_BOTTOM), (xo, yy, WALK_TOP), (xi, yy, WALK_TOP)]
        if (s > 0) == (sign_y > 0):
            pts = list(reversed(pts))
        m.add_face(pts, C["white2"], "paint")
    # ガラスの手すり（外端の少し内側）
    xr = s * (WALK_OUT - 0.18)
    glass_run(m, (xr, -(z_a - 0.3)), (xr, -(z_b + 0.3)), WALK_TOP, WALK_TOP + 1.0, RAIL_POST_STEP)
    # 手前の端の小さな柵（台車の動く区間との境）
    glass_run(m, (xi + s * 0.1, -z_a + 0.15), (xr, -z_a + 0.15), WALK_TOP, WALK_TOP + 1.0, 1.0)
    return m


def edge_lamps(side: int) -> Mesh:
    """（使っていない）奥の歩道の琥珀の灯（8m ごと）。"""
    m = Mesh()
    s = side
    z = NEAR_Z - 4.0
    while z > BELT_Z0 + 2.0:
        lamp(m, s * (WALK_OUT - 0.55), -z, WALK_TOP)
        z -= LAMP_STEP
    return m


def light_tower(m: Mesh, base_g, aim_g, height, r=0.28, head_scale=1.0, with_base=True, sock=False):
    """照明塔：白い丸柱・コバルトの帯・頂部の箱に丸いレンズ 3 灯（aim_g の方を向く）。base_g は Godot の足元の位置。"""
    bx, by, bz = gv(*base_g)
    top = bz + height
    if with_base:
        m.prism(bx, by, bz, bz + 0.35, r * 2.2, r * 2.0, 12, C["white2"], "paint", smooth=True)
    bands = [(bz + 0.35, bz + 1.6, C["white"]), (bz + 1.6, bz + 2.0, C["cobalt"]), (bz + 2.0, top - 2.9, C["white"]),
             (top - 2.9, top - 2.6, C["cobalt"]), (top - 2.6, top, C["white"])]
    band_prism(m, bx, by, bands, r, 12)
    # 頂部の箱：レンズの面を aim へ向ける
    ax, ay, _ = gv(*aim_g)
    yaw = math.atan2(ay - by, ax - bx)
    fx, fy = math.cos(yaw), math.sin(yaw)          # 前（レンズの向き）
    sx, sy = fy, -fx                               # 右（前・右・上で右手系）
    hw, hd, hh = 0.42 * head_scale, 0.30 * head_scale, 1.35 * head_scale
    zc = top - hh + 0.35 * head_scale
    corners = []
    for dz in (-hh, hh):
        for ds, df in ((-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)):
            corners.append((bx + sx * ds + fx * df, by + sy * ds + fy * df, zc + dz))
    idx = {"bottom": (3, 2, 1, 0), "top": (4, 5, 6, 7), "front": (1, 2, 6, 5), "back": (3, 0, 4, 7), "l": (0, 1, 5, 4),
           "r": (2, 3, 7, 6)}
    for key, (a, b, c, d) in idx.items():
        col = C["white"] if key != "bottom" else shade(C["white"], 0.8)
        # 面の向きの確認は外向きの巻き順（corners の並び）で決める
        m.add_face([corners[a], corners[b], corners[c], corners[d]], col, "paint")
    # レンズ 3 灯：前面に平らに貼る光る円板と、少し大きい白い縁（くぼみを作らない）。
    # フードの筒でくぼみを作ると、ゲームの SSAO がくぼみを暗くして、遠目に「0」の字に見えた
    for k in (-1, 0, 1):
        cz = zc + k * 0.82 * head_scale
        lens_r = 0.3 * head_scale
        nseg = 16
        for off, rr, col, key in ((0.006, lens_r * 1.16, C["white2"], "paint"), (0.012, lens_r, C["lens"], "lamp")):
            cxl, cyl = bx + fx * (hd + off), by + fy * (hd + off)
            rim = [(cxl + sx * rr * math.cos(2 * math.pi * i / nseg), cyl + sy * rr * math.cos(2 * math.pi * i / nseg),
                    cz + rr * math.sin(2 * math.pi * i / nseg)) for i in range(nseg)]
            ctr = (cxl, cyl, cz)
            for i in range(nseg):
                a, b = rim[i], rim[(i + 1) % nseg]
                m.add_face([b, a, ctr], col, key)
    if sock:
        windsock(m, (bx - fx * 0.3, by - fy * 0.3, top + 0.1), yaw + math.radians(100))
    return m


def windsock(m: Mesh, base, yaw, length=1.9):
    """吹き流し：細い竿の先に橙と白の縞の円錐（風下へ少し垂れる）。"""
    bx, by, bz = base
    m.prism(bx, by, bz, bz + 1.5, 0.04, 0.035, 6, C["steel"], "paint")
    hx, hy, hz = bx, by, bz + 1.45
    dx, dy = math.cos(yaw), math.sin(yaw)
    n = 10
    segs = 5
    for k in range(segs):
        t0, t1 = k / segs, (k + 1) / segs
        r0, r1 = 0.32 * (1 - 0.55 * t0), 0.32 * (1 - 0.55 * t1)
        c0 = (hx + dx * length * t0, hy + dy * length * t0, hz - 0.35 * t0 * t0)
        c1 = (hx + dx * length * t1, hy + dy * length * t1, hz - 0.35 * t1 * t1)
        col = C["orange"] if k % 2 == 0 else C["sock_w"]
        for i in range(n):
            a0 = 2 * math.pi * i / n
            a1 = 2 * math.pi * (i + 1) / n
            def p(c, r, a):
                return (c[0] - dy * r * math.cos(a), c[1] + dx * r * math.cos(a), c[2] + r * math.sin(a))
            m.add_face([p(c0, r0, a0), p(c0, r0, a1), p(c1, r1, a1), p(c1, r1, a0)], col, "pennant", smooth=True,
                       uv2=[(0.4 * t0, 0), (0.4 * t0, 0), (0.4 * t1, 0), (0.4 * t1, 0)])
            m.add_face([p(c1, r1 * 0.97, a0), p(c1, r1 * 0.97, a1), p(c0, r0 * 0.97, a1), p(c0, r0 * 0.97, a0)], col,
                       "pennant", smooth=True, uv2=[(0.4 * t1, 0), (0.4 * t1, 0), (0.4 * t0, 0), (0.4 * t0, 0)])


def edge_towers(side: int) -> Mesh:
    """（使っていない）走路の脇の照明塔（x ±15.6、z -24 から 28m おき）。"""
    m = Mesh()
    s = side
    for z in TOWER_Z:
        base = (s * TOWER_X, WALK_TOP, z)
        # 塔の台：歩道から張り出した丸い台と下の杭
        bx, by, bz = gv(*base)
        m.prism(bx, by, WALK_BOTTOM, WALK_TOP, 1.05, 1.05, 16, C["white"], "paint", top=C["paving"], smooth=True)
        m.prism(bx, by, WALK_BOTTOM - 0.35, WALK_BOTTOM - 0.001, 1.07, 1.07, 16, C["cobalt"], "paint", smooth=True,
                cap_top=False)
        band_prism(m, bx, by, [(PILE_BOTTOM, SEA_Y - 0.35, shade(C["white"], 0.7)), (SEA_Y - 0.35, SEA_Y + 0.25, C["pile_ring"]),
                                (SEA_Y + 0.25, WALK_BOTTOM - 0.35, C["white"])], 0.6, 12)
        # 歩道との間の板
        x0, x1 = s * (WALK_OUT - 0.1), s * (TOWER_X - 0.6)
        m.box_lohi((min(x0, x1), -z - 0.7, WALK_BOTTOM + 0.35), (max(x0, x1), -z + 0.7, WALK_TOP), C["white"], "paint",
                   top=C["paving"])
        light_tower(m, base, (0.0, 2.0, NEAR_Z + 4.0), TOWER_H, r=0.26, head_scale=0.9, with_base=True)
    return m


# --- 発進デッキ --------------------------------------------------------------------
def deck_frame():
    """発進デッキのローカル（Blender）→ ワールドの行列。ローカル：原点＝床の中心・床の上面、-Y＝カメラの側、+X＝カメラから見て右。"""
    cam = CAMERA["position"]
    yaw = facing_yaw(DECK_C, (cam[0], cam[2]))       # Godot：ローカル +Z がカメラ
    # Blender：ローカル -Y をカメラの方向へ。Godot のローカル +Z は Blender のローカル -Y、Y 回りと Z 回りは同じ符号
    rot = Matrix.Rotation(yaw, 4, "Z")
    loc = Matrix.Translation(g2b(DECK_C[0], WALK_TOP, DECK_C[1]))
    return loc @ rot, yaw


def launch_deck() -> tuple[Mesh, dict]:
    """床・縁・杭と筋交い・ガラスの手すり（一周）・琥珀の灯・リングパッド（ローカル座標で作り、最後に変換）。
    走路への橋（と手すり・灯の橋の口）は 2026-09-30 に取り除いた：ディスプレイのステージだけが海に立つ。"""
    m = Mesh()
    frame, yaw = deck_frame()
    R = DECK_R
    n = 72
    # 床の上面：中心から 3 つの輪（色を少しずつ変える）＋外周の白い縁
    radii = [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, R - 0.55, R]
    for k in range(len(radii) - 1):
        r0, r1 = radii[k], radii[k + 1]
        for i in range(n):
            a0 = 2 * math.pi * i / n
            a1 = 2 * math.pi * (i + 1) / n
            rim = k == len(radii) - 2
            col = C["white"] if rim else PAVE_TINT
            mat = "paint" if rim else "paving"
            if r0 == 0.0:
                pts = [(0, 0, 0), (r1 * math.cos(a0), r1 * math.sin(a0), 0), (r1 * math.cos(a1), r1 * math.sin(a1), 0)]
            else:
                pts = [(r0 * math.cos(a0), r0 * math.sin(a0), 0), (r1 * math.cos(a0), r1 * math.sin(a0), 0),
                       (r1 * math.cos(a1), r1 * math.sin(a1), 0), (r0 * math.cos(a1), r0 * math.sin(a1), 0)]
            m.add_face(pts, col, mat, uv=None if rim else planar_uv(pts))
    # 縁の面：白・コバルトの帯・白
    for z0, z1, col in ((0.0, -0.22, C["white"]), (-0.22, -0.85, C["cobalt"]), (-0.85, -DECK_T, C["white2"])):
        for i in range(n):
            a0 = 2 * math.pi * i / n
            a1 = 2 * math.pi * (i + 1) / n
            m.add_face([(R * math.cos(a0), R * math.sin(a0), z1), (R * math.cos(a1), R * math.sin(a1), z1),
                        (R * math.cos(a1), R * math.sin(a1), z0), (R * math.cos(a0), R * math.sin(a0), z0)], col, "paint",
                       smooth=True)
    for i in range(12):
        a = 2 * math.pi * i / 12 + math.pi / 12
        da = 0.03 / R
        rr = R + 0.006
        m.add_face([(rr * math.cos(a - da), rr * math.sin(a - da), -0.84), (rr * math.cos(a + da), rr * math.sin(a + da), -0.84),
                    (rr * math.cos(a + da), rr * math.sin(a + da), -0.23), (rr * math.cos(a - da), rr * math.sin(a - da), -0.23)],
                   C["cobalt_dark"], "paint")
    # 下面
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 1) / n
        m.add_face([(0, 0, -DECK_T), (R * math.cos(a1), R * math.sin(a1), -DECK_T), (R * math.cos(a0), R * math.sin(a0), -DECK_T)],
                   shade(C["white"], 0.7), "paint")
    # 杭：外の輪 10 本、内の輪 4 本。水際にコバルトの輪
    deck_base = -DECK_T
    sea_local = SEA_Y - WALK_TOP
    pile_bottom = PILE_BOTTOM - WALK_TOP
    ring_pts = []
    for i in range(10):
        a = 2 * math.pi * (i + 0.5) / 10
        ring_pts.append((8.9 * math.cos(a), 8.9 * math.sin(a)))
    inner_pts = [(4.2 * math.cos(math.pi / 4 + i * math.pi / 2), 4.2 * math.sin(math.pi / 4 + i * math.pi / 2)) for i in range(4)]
    for (px, py) in ring_pts + inner_pts:
        band_prism(m, px, py, [(pile_bottom, sea_local - 0.35, shade(C["white"], 0.7)), (sea_local - 0.35, sea_local + 0.3, C["pile_ring"]),
                                (sea_local + 0.3, deck_base, C["white"])], 0.72, 14)
    # 筋交い（外の輪の杭どうし、水面の少し上）
    zb = sea_local + 2.4
    for i in range(10):
        a, b = ring_pts[i], ring_pts[(i + 1) % 10]
        m.beam((a[0], a[1], zb), (b[0], b[1], zb), 0.34, C["white"], "paint", h=0.4)
    # ガラスの手すり（一周。柱は各区間の終わりに立てる：最初の区間の始まりの柱は最後の区間の終わりと同じ所）
    zr0, zr1 = 0.0, 1.0
    segs = 40
    pts = arc_points(0, 0, R - 0.22, 0.0, 2 * math.pi, segs)
    for i in range(segs):
        glass_run(m, pts[i], pts[i + 1], zr0, zr1, 3.0, first_post=False, last_post=True)
    # 琥珀の灯（縁の内側、18）
    for i in range(18):
        a = 2 * math.pi * (i + 0.5) / 18
        lamp(m, (R - 0.75) * math.cos(a), (R - 0.75) * math.sin(a), 0.0, r=0.18, h=0.38)
    # リングパッド（カメラ側 -Y の左右）：橙＝P1（左）、水色＝P2（右）
    pads = {}
    for name, px, col in (("P1", -4.3, C["orange"]), ("P2", 4.3, C["blue"])):
        py = -2.6
        disc(m, px, py, 0.012, 2.35, col, 48)
        annulus(m, px, py, 0.022, 1.62, 1.92, C["pad_line"], 48)
        disc(m, px, py, 0.02, 0.42, C["pad_line"], 24)
        pads[name] = (px, py)
    return m.transformed(frame), {"frame": frame, "yaw": yaw, "pads": pads}


def disc(m: Mesh, cx, cy, z, r, col, n):
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 1) / n
        m.add_face([(cx, cy, z), (cx + r * math.cos(a0), cy + r * math.sin(a0), z), (cx + r * math.cos(a1), cy + r * math.sin(a1), z)],
                   col, "paint")


def annulus(m: Mesh, cx, cy, z, r0, r1, col, n):
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 1) / n
        m.add_face([(cx + r0 * math.cos(a0), cy + r0 * math.sin(a0), z), (cx + r1 * math.cos(a0), cy + r1 * math.sin(a0), z),
                    (cx + r1 * math.cos(a1), cy + r1 * math.sin(a1), z), (cx + r0 * math.cos(a1), cy + r0 * math.sin(a1), z)], col, "paint")


# --- 背景の壁・スピーカー塔・LED・看板 --------------------------------------------
BACK_Y = 8.2          # 中央の壁の前面（ローカル +Y が奥）
WALL_H = 7.4
LED_W, LED_H, LED_Z0 = 10.4, 4.7, 1.45
SIGN_W, SIGN_H, SIGN_Z0 = 13.0, 3.4, 7.55
SPK_W, SPK_D, SPK_H = 2.5, 1.5, 8.3
SPK_X = 7.55


def chamfer_box(m: Mesh, cx, cy, z0, z1, w, d, c, col, top_col=None, bottom=False, front_col=None):
    """角を面取りした箱（平面 8 角形の柱）。front_col は -Y（前）の面の色。"""
    hw, hd = w / 2, d / 2
    outline = [(cx - hw + c, cy - hd), (cx + hw - c, cy - hd), (cx + hw, cy - hd + c), (cx + hw, cy + hd - c),
               (cx + hw - c, cy + hd), (cx - hw + c, cy + hd), (cx - hw, cy + hd - c), (cx - hw, cy - hd + c)]
    n = len(outline)
    for i in range(n):
        a, b = outline[i], outline[(i + 1) % n]
        col_i = front_col if (front_col is not None and i == 0) else shade(col, 0.96 + 0.04 * math.cos(i))
        m.add_face([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], col_i, "paint")
    m.add_face([(p[0], p[1], z1) for p in outline], top_col or col, "paint")
    if bottom:
        m.add_face([(p[0], p[1], z0) for p in reversed(outline)], shade(col, 0.8), "paint")


def speaker(m: Mesh, cx, y_face, cz, r):
    """前面（-Y 向き）に丸いスピーカー：壁から 0.12 出た暗い縁の輪、奥へ下がるコーン、中心のキャップ（すべて壁の面より前）。"""
    n = 20
    yl = y_face - 0.12      # 縁の前面
    yc = y_face - 0.04      # コーンの奥（壁の面より少し前）

    def pt(rr, y, k):
        a = 2 * math.pi * k / n
        return (cx + rr * math.cos(a), y, cz + rr * math.sin(a))

    for i in range(n):
        j = (i + 1) % n
        m.add_face([pt(r, y_face + 0.001, i), pt(r, y_face + 0.001, j), pt(r, yl, j), pt(r, yl, i)], C["dark"], "paint")
        m.add_face([pt(r, yl, i), pt(r, yl, j), pt(0.82 * r, yl, j), pt(0.82 * r, yl, i)], C["speaker_ring"], "paint", smooth=True)
        m.add_face([pt(0.82 * r, yl, i), pt(0.82 * r, yl, j), pt(0.32 * r, yc, j), pt(0.32 * r, yc, i)], C["speaker"], "paint",
                   smooth=True)
        m.add_face([pt(0.32 * r, yc, i), pt(0.32 * r, yc, j), (cx, yc - 0.07, cz)], shade(C["speaker_ring"], 1.25), "paint",
                   smooth=True)


def backdrop() -> tuple[Mesh, Mesh, Mesh, dict]:
    """背景の壁（中央の壁・スピーカー塔・袖壁・台座・笠木）、LED の面、看板の面。ローカルで作ってワールドへ。"""
    frame, _ = deck_frame()
    m = Mesh()
    led = Mesh()
    sign = Mesh()
    y0 = BACK_Y
    # 中央の壁：前面は白、LED の枠は紺
    hw = SPK_X - SPK_W / 2 + 0.05
    m.box_lohi((-hw, y0, 0.0), (hw, y0 + WALL_T, WALL_H), C["white"], "paint", top=C["cobalt"])
    # 笠木と台座（コバルト）
    m.box_lohi((-hw - 0.02, y0 - 0.06, WALL_H - 0.38), (hw + 0.02, y0 + WALL_T + 0.02, WALL_H), C["cobalt"], "paint")
    m.box_lohi((-hw - 0.02, y0 - 0.1, 0.0), (hw + 0.02, y0 + 0.1, 0.42), C["cobalt"], "paint", faces=["-y", "top", "+x", "-x"])
    # LED の枠（紺、前へ 0.12）
    fz0, fz1 = LED_Z0 - 0.22, LED_Z0 + LED_H + 0.22
    fx = LED_W / 2 + 0.22
    for (x0, x1, z0, z1) in ((-fx, fx, fz0, LED_Z0), (-fx, fx, LED_Z0 + LED_H, fz1), (-fx, -LED_W / 2, LED_Z0, LED_Z0 + LED_H),
                             (LED_W / 2, fx, LED_Z0, LED_Z0 + LED_H)):
        m.box_lohi((x0, y0 - 0.12, z0), (x1, y0 + 0.01, z1), C["navy"], "paint", faces=["-y", "top", "bottom", "+x", "-x"])
    # LED の面（UV 0..1、前向き）
    ly = y0 - 0.02
    led.add_face([(-LED_W / 2, ly, LED_Z0), (LED_W / 2, ly, LED_Z0), (LED_W / 2, ly, LED_Z0 + LED_H), (-LED_W / 2, ly, LED_Z0 + LED_H)],
                 (1, 1, 1, 1), "led", uv=[(0, 0), (1, 0), (1, 1), (0, 1)])
    # 看板：紺の箱と前面の画像
    sy0 = y0 + 0.05
    m.box_lohi((-SIGN_W / 2, sy0, SIGN_Z0), (SIGN_W / 2, sy0 + 0.55, SIGN_Z0 + SIGN_H), C["navy"], "paint",
               faces=["top", "bottom", "+x", "-x", "+y"])
    sign.add_face([(-SIGN_W / 2, sy0 - 0.01, SIGN_Z0), (SIGN_W / 2, sy0 - 0.01, SIGN_Z0), (SIGN_W / 2, sy0 - 0.01, SIGN_Z0 + SIGN_H),
                   (-SIGN_W / 2, sy0 - 0.01, SIGN_Z0 + SIGN_H)], (1, 1, 1, 1), "sign", uv=[(0, 0), (1, 0), (1, 1), (0, 1)])
    # 看板の裏の支え（コバルトの脚 2 本）
    for sx in (-4.2, 4.2):
        m.box_lohi((sx - 0.2, sy0 + 0.55, WALL_H - 0.4), (sx + 0.2, sy0 + 0.95, SIGN_Z0 + 1.2), C["cobalt_dark"], "paint")
    # スピーカー塔（左右）
    for sx in (-1, 1):
        cx = sx * SPK_X
        chamfer_box(m, cx, y0 - 0.25 + SPK_D / 2, 0.0, SPK_H, SPK_W, SPK_D, 0.35, C["white"], top_col=C["cobalt"], bottom=False)
        # 帯：上と下のコバルト
        chamfer_box(m, cx, y0 - 0.25 + SPK_D / 2, SPK_H - 0.45, SPK_H - 0.05, SPK_W + 0.08, SPK_D + 0.08, 0.37, C["cobalt"],
                    top_col=C["cobalt"])
        chamfer_box(m, cx, y0 - 0.25 + SPK_D / 2, 0.0, 0.5, SPK_W + 0.08, SPK_D + 0.08, 0.37, C["cobalt"], top_col=C["cobalt"])
        face_y = y0 - 0.25
        for cz in (2.05, 3.85, 5.65):
            speaker(m, cx, face_y, cz, 0.68)
        # 塔の頂の小さな灯
        lamp(m, cx, face_y + SPK_D / 2, SPK_H, r=0.2, h=0.25)
    # 袖壁：スピーカー塔の外から前へ 25° 折れて照明塔へ
    for sx in (-1, 1):
        x_in = sx * (SPK_X + SPK_W / 2 - 0.1)
        ang = math.radians(25)
        length = 3.6
        x_out = x_in + sx * length * math.cos(ang)
        y_out = y0 + 0.2 - length * math.sin(ang)
        a = (x_in, y0 + 0.35)
        b = (x_out, y_out)
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy)
        nx, ny = -dy / L * sx, dx / L * sx
        t = 0.6
        h = 4.6
        quad_front = [(a[0], a[1], 0), (b[0], b[1], 0), (b[0], b[1], h), (a[0], a[1], h)]
        quad_back = [(a[0] + nx * t, a[1] + ny * t, 0), (b[0] + nx * t, b[1] + ny * t, 0), (b[0] + nx * t, b[1] + ny * t, h),
                     (a[0] + nx * t, a[1] + ny * t, h)]
        if sx > 0:
            m.add_face(quad_front, C["white"], "paint")
            m.add_face(list(reversed(quad_back)), shade(C["white"], 0.9), "paint")
        else:
            m.add_face(list(reversed(quad_front)), C["white"], "paint")
            m.add_face(quad_back, shade(C["white"], 0.9), "paint")
        top = [quad_front[3], quad_front[2], quad_back[2], quad_back[3]]
        m.add_face(top if sx > 0 else list(reversed(top)), C["cobalt"], "paint")
        end = [quad_front[1], quad_back[1], quad_back[2], quad_front[2]]
        m.add_face(end if sx > 0 else list(reversed(end)), shade(C["white"], 0.95), "paint")
        # 袖壁のコバルトの細帯（前面）
        m.beam((a[0] - nx * 0.01, a[1] - ny * 0.01, h - 0.55), (b[0] - nx * 0.01, b[1] - ny * 0.01, h - 0.55), 0.02, C["cobalt"],
               "paint", h=0.22)
    info = {"sign_top_local": (SIGN_W / 2, y0, SIGN_Z0 + SIGN_H)}
    return m.transformed(frame), led.transformed(frame), sign.transformed(frame), info


def deck_towers() -> tuple[Mesh, list]:
    """発進デッキの照明塔 2 本（背景の外側）。右の塔に吹き流し。レンズはデッキの前（カメラの側）へ。"""
    frame, _ = deck_frame()
    m = Mesh()
    tops = []
    for sx in (-1, 1):
        lx, ly = sx * 11.0, 5.4
        wpos = frame @ Vector((lx, ly, 0.0))
        aim = frame @ Vector((lx * 0.2, -30.0, 3.0))
        base_g = (wpos.x, wpos.z, -wpos.y)
        aim_g = (aim.x, aim.z, -aim.y)
        light_tower(m, base_g, aim_g, 13.0, r=0.36, head_scale=1.15, with_base=True, sock=(sx > 0))
        tops.append(frame @ Vector((lx, ly, 13.0 - 0.6)))
    return m, tops


# --- ヤシ ------------------------------------------------------------------------
def palm(m: Mesh, foliage: Mesh, base, height, lean_dir, rnd: random.Random):
    """白い植木鉢のヤシ。base は Blender（鉢の底の中心）。幹は節のある曲がった柱、葉 9 枚（揺れの重みを UV2.x に）。"""
    bx, by, bz = base
    pot_h = 0.95
    chamfer_box(m, bx, by, bz, bz + pot_h, 1.55, 1.55, 0.18, C["white"], top_col=C["white2"], bottom=False)
    chamfer_box(m, bx, by, bz + pot_h - 0.16, bz + pot_h, 1.63, 1.63, 0.2, C["cobalt"], top_col=C["cobalt"])
    disc(m, bx, by, bz + pot_h + 0.001, 0.62, C["soil"], 12)
    # 幹：7 節、根元から少しずつ lean_dir へ曲がる
    segs = 10
    pts = []
    lx, ly = lean_dir
    for k in range(segs + 1):
        t = k / segs
        off = 0.9 * t * t
        pts.append(Vector((bx + lx * off, by + ly * off, bz + pot_h + height * t)))
    for k in range(segs):
        a, b = pts[k], pts[k + 1]
        r0 = 0.24 - 0.09 * (k / segs)
        r1 = 0.24 - 0.09 * ((k + 1) / segs)
        n = 8
        d = (b - a).normalized()
        s1 = d.cross(Vector((0, 0, 1))).normalized() if abs(d.z) < 0.99 else Vector((1, 0, 0))
        s2 = d.cross(s1).normalized()
        ra = [a + (s1 * math.cos(2 * math.pi * i / n) + s2 * math.sin(2 * math.pi * i / n)) * r0 for i in range(n)]
        rb = [b + (s1 * math.cos(2 * math.pi * i / n) + s2 * math.sin(2 * math.pi * i / n)) * r1 * 1.08 for i in range(n)]
        for i in range(n):
            j = (i + 1) % n
            col = C["trunk"] if k % 2 == 0 else mix(C["trunk"], C["trunk_dark"], 0.55)
            m.add_face([tuple(ra[i]), tuple(ra[j]), tuple(rb[j]), tuple(rb[i])], col, "paint", smooth=True)
    crown = pts[-1]
    # 実（3 個）
    for i in range(3):
        a = 2 * math.pi * i / 3
        m.blob((crown.x + 0.22 * math.cos(a), crown.y + 0.22 * math.sin(a), crown.z - 0.25), 0.16, 0.16, 0.17,
               hexcol_safe("#7A5A2E"), hexcol_safe("#5A3F1E"), seg=6, rings=4)
    # 葉：9 枚。付け根から外へ弧を描いて垂れる細い葉（幅が先へ細くなる）
    fronds = [(2 * math.pi * i / 12 + rnd.uniform(-0.1, 0.1), rnd.uniform(2.5, 3.2), rnd.uniform(0.35, 0.8), 1.0) for i in range(12)]
    fronds += [(2 * math.pi * (i + 0.5) / 5 + rnd.uniform(-0.2, 0.2), rnd.uniform(1.5, 1.9), rnd.uniform(0.9, 1.2), 0.75) for i in range(5)]
    for a, length, lift, wscale in fronds:
        dirx, diry = math.cos(a), math.sin(a)
        n = 7
        spine = []
        for k in range(n + 1):
            t = k / n
            h = lift * math.sin(t * math.pi * 0.8) - 1.25 * t * t
            spine.append(Vector((crown.x + dirx * length * t, crown.y + diry * length * t, crown.z + 0.05 + h)))
        side = Vector((-diry, dirx, 0.0))
        for k in range(n):
            t0, t1 = k / n, (k + 1) / n
            w0 = (0.52 * math.sin(math.pi * min(1.0, t0 * 1.1 + 0.08)) + 0.04) * wscale
            w1 = (0.52 * math.sin(math.pi * min(1.0, t1 * 1.1 + 0.08)) + 0.04) * wscale
            a0, a1 = spine[k], spine[k + 1]
            droop0 = Vector((0, 0, -0.10 * w0))
            droop1 = Vector((0, 0, -0.10 * w1))
            c0 = mix(C["leaf"], C["leaf_light"], 0.25 + 0.6 * t0)
            c1 = mix(C["leaf"], C["leaf_light"], 0.25 + 0.6 * t1)
            quad_l = [tuple(a0), tuple(a1), tuple(a1 + side * w1 + droop1), tuple(a0 + side * w0 + droop0)]
            quad_r = [tuple(a1), tuple(a0), tuple(a0 - side * w0 + droop0), tuple(a1 - side * w1 + droop1)]
            for quad, cc in ((quad_l, [c0, c1, c1, c0]), (quad_r, [c1, c0, c0, c1])):
                uv2 = [(t0, 0), (t1, 0), (t1, 0), (t0, 0)] if quad is quad_l else [(t1, 0), (t0, 0), (t0, 0), (t1, 0)]
                foliage.add_face(quad, c0, "foliage", uv2=uv2, smooth=True, ccol=cc)
                back = list(reversed(quad))
                foliage.add_face(back, shade(c0, 0.8), "foliage", uv2=list(reversed(uv2)), smooth=True,
                                 ccol=[shade(c, 0.8) for c in reversed(cc)])


def hexcol_safe(h):
    return hexcol(h)


def palms() -> tuple[Mesh, Mesh]:
    frame, _ = deck_frame()
    m = Mesh()
    foliage = Mesh()
    rnd = random.Random(11)
    for sx in (-1, 1):
        lx, ly = sx * 8.7, 4.3
        local = Mesh()
        local_f = Mesh()
        palm(local, local_f, (lx, ly, 0.0), 4.4 + (0.3 if sx > 0 else 0.0), (sx * 0.55, -0.35), rnd)
        m.extend(local.transformed(frame))
        foliage.extend(local_f.transformed(frame))
    return m, foliage


# --- 旗 ---------------------------------------------------------------------------
def pennant_string(m: Mesh, a: Vector, b: Vector, sag: float, count: int, start_orange=True):
    """a→b に垂れる紐と三角の旗（橙と水色の交互）。旗は両面（裏の面を作る）。UV2.x = 紐からの距離の重み（0..1）。"""
    n = 24
    pts = []
    for i in range(n + 1):
        t = i / n
        p = a.lerp(b, t)
        p = p + Vector((0, 0, -sag * 4 * t * (1 - t)))
        pts.append(p)
    for i in range(n):
        m.beam(tuple(pts[i]), tuple(pts[i + 1]), 0.025, C["dark"], "paint", caps=False)
    for k in range(count):
        t0 = (k + 0.18) / count
        t1 = (k + 0.82) / count
        def at(t):
            p = a.lerp(b, t)
            return p + Vector((0, 0, -sag * 4 * t * (1 - t)))
        p0, p1 = at(t0), at(t1)
        mid = (p0 + p1) / 2
        tip = mid + Vector((0, 0, -0.78))
        col = C["orange"] if (k % 2 == 0) == start_orange else C["blue"]
        m.add_face([tuple(p0), tuple(p1), tuple(tip)], col, "pennant", uv2=[(0, 0), (0, 0), (1, 0)])
        m.add_face([tuple(p1), tuple(p0), tuple(tip)], shade(col, 0.85), "pennant", uv2=[(0, 0), (0, 0), (1, 0)])


def pennants(tower_tops: list, sign_top_local: tuple) -> Mesh:
    frame, _ = deck_frame()
    m = Mesh()
    sw, sy, sz = sign_top_local
    for idx, sx in enumerate((-1, 1)):
        a = tower_tops[idx]
        b = frame @ Vector((sx * (sw - 0.3), sy + 0.1, sz - 0.1))
        pennant_string(m, a, b, 0.75, 8, start_orange=(sx < 0))
    return m

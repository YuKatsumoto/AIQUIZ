"""AIQUIZ ONLINE HELIPORT の部品（aqs_geom.Mesh で面を組み立てる。座標は Blender、Z が上、単位 m）。v2：パッド 1 つ。

材質キー（build_online_heliport.materials() で登録）：
  paint    頂点色の塗装（AQS_Painted）          night   投光器のレンズ（AQS_NightGlow）
  deck     パッドの床（OHP_PadDeck、画像）       net     安全ネット（OHP_Net、画像のアルファ）
  lamp     パッドの縁の灯（OHP_PadLamp、UV2.x = 灯の番号 / 灯の数）
  flag     旗（OHP_Flag、UV2.x = 揺れの重み）
揺れる部品（吹き流し・旗）は、原点が軸の局所座標で作る（ビルダーが位置を置く）。
小物の位置はヘリの座標（H）で ohp_common に書き、K.h2g_xz でワールドへ直す。
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

import ohp_common as K
from aqs_geom import Mesh, mix, shade

C = K.C
DY = K.DECK_Y


# --- 小さな道具 ----------------------------------------------------------------------
def face(mesh: Mesh, pts, col, mat="paint", normal=None, uv=None, uv2=None, smooth=False):
    """面を足す。normal を渡すと、その向きを表にそろえる（点の並びを必要なら逆にする）。"""
    pts = [tuple(p) for p in pts]
    if normal is not None and len(pts) >= 3:
        a, b, c = (Vector(p) for p in pts[:3])
        n = (b - a).cross(c - a)
        if n.dot(Vector(normal)) < 0:
            pts = list(reversed(pts))
            uv = list(reversed(uv)) if uv else None
            uv2 = list(reversed(uv2)) if uv2 else None
    mesh.add_face(pts, col, mat, uv=uv, uv2=uv2, smooth=smooth)


def octagon(cx, cy, apothem, z, phase=math.pi / 8):
    """平らな辺が ±X・±Y を向く八角形の頂点（反時計回り）。"""
    r = apothem / math.cos(math.pi / 8)
    return [(cx + r * math.cos(phase + k * math.pi / 4), cy + r * math.sin(phase + k * math.pi / 4), z) for k in range(8)]


def chamfer_square(cx, cy, half, cut, z):
    """角を cut だけ落とした正方形（反時計回り）。"""
    h, c = half, cut
    pts = [(h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c), (-h + c, -h), (h - c, -h)]
    return [(cx + x, cy + y, z) for x, y in pts]


def band_ring(mesh: Mesh, outline_lo, outline_hi, col, mat="paint", normal_out=True, smooth=False):
    """同じ点数の 2 つの外周（下と上）のあいだの側面。"""
    n = len(outline_lo)
    for i in range(n):
        j = (i + 1) % n
        a, b, c, d = outline_lo[i], outline_lo[j], outline_hi[j], outline_hi[i]
        mid = Vector(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0))
        cen = Vector((sum(p[0] for p in outline_lo) / n, sum(p[1] for p in outline_lo) / n, 0.0))
        out = (mid - cen).normalized() if normal_out else (cen - mid).normalized()
        face(mesh, [a, b, c, d], col, mat, normal=out, smooth=smooth)


def planar_uv(pts, cx, cy, size):
    return [((p[0] - cx) / size + 0.5, (p[1] - cy) / size + 0.5) for p in pts]


def torus(mesh: Mesh, centre, axis, major, minor, cols, seg=16, ring=6):
    """浮輪のような輪。cols は周方向の色の並び（等分して塗る）。"""
    centre = Vector(centre)
    axis = Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(ref).normalized()
    v = axis.cross(u).normalized()
    rows = []
    for i in range(seg + 1):
        t = 2 * math.pi * i / seg
        radial = u * math.cos(t) + v * math.sin(t)
        row = []
        for j in range(ring + 1):
            s = 2 * math.pi * j / ring
            row.append(tuple(centre + radial * (major + minor * math.cos(s)) + axis * (minor * math.sin(s))))
        rows.append(row)
    for i in range(seg):
        col = cols[int(i * len(cols) / seg) % len(cols)]
        for j in range(ring):
            mesh.add_face([rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]], col, smooth=True)


# --- パッド ----------------------------------------------------------------------------
def pad(centre_g, bridge_dir=None):
    """八角形のヘリパッド。bridge_dir：渡り廊下がつながる辺（+1＝Blender +Y、-1＝-Y、None＝なし）。

    返り値：{"body": Mesh（床・桁・柱・ネット）, "lamps": Mesh（縁の灯）, "lamp_points": [...]}"""
    cx, cy = K.gxz(centre_g)
    ap = K.PAD_FLAT / 2
    body = Mesh()
    rim_in = ap - K.PAD_RIM_W
    top = octagon(cx, cy, rim_in, DY)
    body.add_face(top, C["white"], "deck", uv=planar_uv(top, cx, cy, 2 * K.PAD_R))
    # 縁の立ち上がり（白）と外側の帯（白→コバルト）
    rim_lo_in = octagon(cx, cy, rim_in, DY)
    rim_hi_in = octagon(cx, cy, rim_in, DY + K.PAD_RIM_H)
    rim_hi_out = octagon(cx, cy, ap, DY + K.PAD_RIM_H)
    band_ring(body, rim_lo_in, rim_hi_in, C["white2"], normal_out=False)
    for i in range(8):
        j = (i + 1) % 8
        face(body, [rim_hi_in[i], rim_hi_in[j], rim_hi_out[j], rim_hi_out[i]], C["white"], normal=(0, 0, 1))
    z_white = DY - 0.12
    z_bottom = DY - K.PAD_T
    band_ring(body, octagon(cx, cy, ap, z_white), rim_hi_out, C["white"])
    band_ring(body, octagon(cx, cy, ap, z_bottom), octagon(cx, cy, ap, z_white), C["cobalt"])
    body.add_face(list(reversed(octagon(cx, cy, ap, z_bottom))), C["steel_dark"])
    # 床の下：放射状の桁 8 本、外周と内周の輪の桁
    g_top = z_bottom
    for k in range(8):
        a = k * math.pi / 4
        d = Vector((math.cos(a), math.sin(a), 0))
        p0 = Vector((cx, cy, g_top - 0.42)) + d * (K.COLUMN_R + 0.3)
        p1 = Vector((cx, cy, g_top - 0.42)) + d * (ap - 0.45)
        body.beam(p0, p1, 0.26, C["steel"], h=0.84)
    for ring_ap, w, h in ((ap - 0.45, 0.32, 0.72), (3.1, 0.24, 0.6)):
        pts = octagon(cx, cy, ring_ap, g_top - h / 2)
        for i in range(8):
            body.beam(pts[i], pts[(i + 1) % 8], w, C["steel"], h=h)
    # 中央の柱（上は広がった柱頭、水際にコバルトの帯）
    col_top = g_top - 0.84
    body.prism(cx, cy, col_top - 1.6, col_top, K.COLUMN_R, 2.8, 24, C["white"], smooth=True, cap_top=True, cap_bottom=False)
    body.prism(cx, cy, K.SEA_Y + 1.1, col_top - 1.6, K.COLUMN_R, K.COLUMN_R, 24, C["white2"], smooth=True, cap_top=False, cap_bottom=False)
    body.prism(cx, cy, K.SEA_Y - 0.7, K.SEA_Y + 1.1, K.COLUMN_R + 0.04, K.COLUMN_R + 0.04, 24, C["cobalt"], smooth=True,
               cap_top=True, cap_bottom=True)
    body.prism(cx, cy, K.LEG_BOTTOM, K.SEA_Y - 0.7, K.COLUMN_R, K.COLUMN_R, 24, C["white2"], smooth=True, cap_top=False)
    # 斜めの支柱 8 本（柱の中ほど → 外周の桁）
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        d = Vector((math.cos(a), math.sin(a), 0))
        p0 = Vector((cx, cy, K.SEA_Y + 3.0)) + d * (K.COLUMN_R - 0.1)
        p1 = Vector((cx, cy, g_top - 0.5)) + d * (ap - 1.2)
        body.tube(p0, p1, 0.2, C["white2"], n=8, caps=True)
    # 安全ネットの棚（渡り廊下の辺を除く）
    verts_in = octagon(cx, cy, ap, DY - 0.06)
    verts_out = octagon(cx, cy, ap + K.NET_W, DY - 0.06 - K.NET_DROP)
    for i in range(8):
        j = (i + 1) % 8
        mid = Vector(((verts_in[i][0] + verts_in[j][0]) / 2 - cx, (verts_in[i][1] + verts_in[j][1]) / 2 - cy, 0)).normalized()
        if bridge_dir is not None and abs(mid.y - bridge_dir) < 1e-3:
            continue
        a, b, c, d = verts_in[i], verts_in[j], verts_out[j], verts_out[i]
        length = (Vector(b) - Vector(a)).length
        uv = [(0, 0), (length, 0), (length, K.NET_W), (0, K.NET_W)]
        body.quad2(a, b, c, d, C["white"], "net", uv=uv)
        # 枠：外の管、内の管、腕（角と辺の中ほど）
        body.tube(c, d, 0.04, C["steel"], n=6)
        body.tube(a, b, 0.03, C["steel"], n=6)
        for t in (0.0, 0.5, 1.0):
            pa = Vector(a).lerp(Vector(b), t)
            pb = Vector(d).lerp(Vector(c), t)
            body.beam(pa + Vector((0, 0, -0.04)), pb + Vector((0, 0, -0.04)), 0.06, C["steel"], h=0.08)
    # 縁の灯 16 個（各辺 2 個。渡り廊下の辺は廊下の外側の角寄りに置く）
    lamps = Mesh()
    points = []
    edge_half = K.PAD_R * math.sin(math.pi / 8)
    ordered = []
    for i in range(8):
        a = i * math.pi / 4
        nrm = Vector((math.cos(a), math.sin(a), 0))
        tan = Vector((-nrm.y, nrm.x, 0))
        offs = (-edge_half * 0.5, edge_half * 0.5)
        if bridge_dir is not None and abs(nrm.y - bridge_dir) < 1e-3:
            offs = (-(edge_half - 0.42), edge_half - 0.42)
        for o in offs:
            pos = Vector((cx, cy, DY + K.PAD_RIM_H)) + nrm * (ap - K.PAD_RIM_W / 2) + tan * o
            ordered.append((math.atan2(pos.y - cy, pos.x - cx), pos))
    ordered.sort(key=lambda t: t[0])
    count = len(ordered)
    for idx, (_ang, pos) in enumerate(ordered):
        points.append(tuple(pos))
        _lamp(lamps, pos, idx / count)
    return {"body": body, "lamps": lamps, "lamp_points": points, "lamp_count": count}


def _lamp(mesh: Mesh, pos: Vector, index_u: float, n=10):
    base_r, lens_r = 0.11, 0.085
    z0 = pos.z
    ring0 = [(pos.x + base_r * math.cos(2 * math.pi * i / n), pos.y + base_r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    for i in range(n):
        j = (i + 1) % n
        mesh.add_face([(ring0[i][0], ring0[i][1], z0), (ring0[j][0], ring0[j][1], z0),
                       (ring0[j][0], ring0[j][1], z0 + 0.035), (ring0[i][0], ring0[i][1], z0 + 0.035)], C["dark"])
    mesh.add_face([(p[0], p[1], z0 + 0.035) for p in ring0], C["dark"])
    prev = [(pos.x + lens_r * math.cos(2 * math.pi * i / n), pos.y + lens_r * math.sin(2 * math.pi * i / n), z0 + 0.036) for i in range(n)]
    rings = 3
    for k in range(1, rings + 1):
        t = k / rings
        rr = lens_r * math.cos(t * math.pi / 2)
        zz = z0 + 0.036 + 0.07 * math.sin(t * math.pi / 2)
        cur = [(pos.x + rr * math.cos(2 * math.pi * i / n), pos.y + rr * math.sin(2 * math.pi * i / n), zz) for i in range(n)]
        for i in range(n):
            j = (i + 1) % n
            pts = [prev[i], prev[j], cur[0]] if k == rings else [prev[i], prev[j], cur[j], cur[i]]
            mesh.add_face(pts, C["lamp_green"], "lamp", uv2=[(index_u, 0.0)] * len(pts), smooth=True)
        prev = cur


# --- 吹き流し・旗・投光器・小物 ---------------------------------------------------------
WINDSOCK_LEN = 2.4


def windsock():
    """原点＝支点（柱の先）。袋は +X へ伸び、先ほど少し垂れる。オレンジと白の 5 帯。"""
    m = Mesh()
    n = 16
    stations = 11
    rows = []
    cols = []
    for k in range(stations):
        t = k / (stations - 1)
        x = 0.08 + t * WINDSOCK_LEN
        r = 0.34 + (0.14 - 0.34) * t
        z = -0.06 - 0.16 * t ** 1.6
        rows.append([(x, r * math.cos(2 * math.pi * i / n), z + r * math.sin(2 * math.pi * i / n)) for i in range(n + 1)])
        cols.append(int(t * 5 - 1e-6))
    for k in range(stations - 1):
        band = min(4, int(((k + 0.5) / (stations - 1)) * 5))
        col = C["orange"] if band % 2 == 0 else C["white"]
        for i in range(n):
            m.add_face([rows[k][i], rows[k + 1][i], rows[k + 1][i + 1], rows[k][i + 1]], col, smooth=True)
            m.add_face([rows[k][i + 1], rows[k + 1][i + 1], rows[k + 1][i], rows[k][i]], shade(col, 0.6), smooth=True)
    # 口の輪と支点の金具
    ring_pts = [(0.06, 0.36 * math.cos(2 * math.pi * i / n), -0.06 + 0.36 * math.sin(2 * math.pi * i / n)) for i in range(n + 1)]
    for i in range(n):
        m.tube(ring_pts[i], ring_pts[i + 1], 0.018, C["steel"], n=4)
    m.tube((0.06, 0, 0.3), (0.0, 0, 0.0), 0.02, C["steel"], n=4)
    m.tube((0.06, 0, -0.42), (0.0, 0, 0.0), 0.02, C["steel"], n=4)
    m.prism(0, 0, -0.08, 0.08, 0.06, 0.06, 8, C["dark"])
    return m


FLAG_W, FLAG_H = 1.8, 1.1


def flag(field, stripe):
    """原点＝旗の竿側の上端。+X へなびく。UV2.x = 竿からの距離の割合（揺れの重み）。"""
    m = Mesh()
    nu, nv = 9, 5
    for i in range(nu):
        for j in range(nv):
            u0, u1 = i / nu, (i + 1) / nu
            v0, v1 = j / nv, (j + 1) / nv
            pts = [(u0 * FLAG_W, 0, -v0 * FLAG_H), (u1 * FLAG_W, 0, -v0 * FLAG_H), (u1 * FLAG_W, 0, -v1 * FLAG_H), (u0 * FLAG_W, 0, -v1 * FLAG_H)]
            uc, vc = (u0 + u1) / 2, (v0 + v1) / 2
            on_stripe = abs((uc - 0.33) - (vc - 0.5) * 0.55) < 0.09
            col = stripe if on_stripe else field
            m.add_face(pts, col, "flag", uv=[(u0, v0), (u1, v0), (u1, v1), (u0, v1)],
                       uv2=[(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
    return m


def flagpole(m: Mesh, x, y, height=6.0):
    m.prism(x, y, DY, DY + 0.12, 0.2, 0.2, 10, C["steel_dark"])
    m.prism(x, y, DY + 0.12, DY + height, 0.06, 0.045, 10, C["white"], smooth=True)
    m.dome(x, y, DY + height, 0.07, 0.08, 8, 2, C["amber"], smooth=True)
    return (x, y, DY + height - 0.15)


def floodlight(m: Mesh, x, y, aim_xy, height=5.0):
    m.prism(x, y, DY, DY + 0.15, 0.22, 0.22, 10, C["steel_dark"])
    m.prism(x, y, DY + 0.15, DY + height, 0.08, 0.065, 10, C["steel"], smooth=True)
    d = Vector((aim_xy[0] - x, aim_xy[1] - y, 0)).normalized()
    side = Vector((-d.y, d.x, 0))
    top = Vector((x, y, DY + height))
    m.tube(top - side * 0.55, top + side * 0.55, 0.035, C["steel"], n=6, caps=True)
    for s in (-0.38, 0.38):
        c = top + side * s + d * 0.12 + Vector((0, 0, 0.08))
        tilt = Matrix.Rotation(math.radians(25), 4, side) @ Matrix.Rotation(math.atan2(d.y, d.x), 4, "Z")   # 前を 25° 下へ
        head = Mesh()
        head.box((0, 0, 0), (0.3, 0.42, 0.32), C["navy2"])
        head.add_face([(0.152, -0.17, -0.12), (0.152, 0.17, -0.12), (0.152, 0.17, 0.12), (0.152, -0.17, 0.12)], C["lens"], "night")
        m.extend(head.transformed(Matrix.Translation(c) @ tilt))


def fire_monitor(m: Mesh, x, y, aim_xy):
    m.prism(x, y, DY, DY + 0.75, 0.13, 0.1, 10, C["red"], smooth=True)
    m.box((x, y, DY + 0.85), (0.3, 0.3, 0.22), C["red_dark"])
    d = Vector((aim_xy[0] - x, aim_xy[1] - y, 0)).normalized()
    a = Vector((x, y, DY + 0.9))
    b = a + d * 0.85 + Vector((0, 0, 0.28))
    m.tube(a, b, 0.07, C["red"], n=8, caps=True)
    m.tube(b, b + (b - a).normalized() * 0.18, 0.05, C["steel"], n=8, caps=True)
    m.tube(a + Vector((0, 0, -0.05)), a + Vector((0, 0, -0.05)) - d * 0.35, 0.025, C["dark"], n=5, caps=True)


def cabinet(m: Mesh, x, y, size, col, facing):
    sx, sy, sz = size
    m.box((x, y, DY + sz / 2), size, col)
    f = Vector(facing).normalized()
    offset = Vector((x, y, DY + sz * 0.55)) + Vector((f.x * sx / 2, f.y * sy / 2, 0)) * 1.01
    side = Vector((-f.y, f.x, 0))
    w = (sy if abs(f.x) > 0.5 else sx) * 0.42
    for s in (-1, 1):
        c = offset + side * s * w * 0.52
        m.box(c, (0.02 if abs(f.x) > 0.5 else w, w if abs(f.x) > 0.5 else 0.02, sz * 0.8), shade(col, 0.9))
    m.box(Vector((x, y, DY + sz + 0.03)), (sx + 0.06, sy + 0.06, 0.06), shade(col, 0.8))


def _toward_centre(x, y):
    cx, cy = K.gxz(K.PAD)
    return (cx, cy) if math.hypot(x - cx, y - cy) > 1e-3 else (x + 1.0, y)


def buoy_post(m: Mesh, x, y):
    """救命浮輪の掛け台（パッドの縁の内側。浮輪は外を向く）。"""
    cx, cy = K.gxz(K.PAD)
    out = Vector((x - cx, y - cy, 0)).normalized()
    m.prism(x, y, DY, DY + 0.06, 0.16, 0.16, 8, C["steel_dark"])
    m.prism(x, y, DY + 0.06, DY + 1.05, 0.045, 0.045, 8, C["white"], smooth=True)
    m.box((x, y, DY + 1.08), (0.18, 0.18, 0.08), C["cobalt"])
    centre = Vector((x, y, DY + 0.72)) + out * 0.11
    torus(m, centre, out, 0.3, 0.07, [C["orange"], C["white"]] * 2)


def props():
    """小物：吹き流しの柱、旗の竿、投光器、救命浮輪、消火砲、機器箱。返り値は (Mesh, 吊り点)。
    位置はヘリの座標（H）で決める（K.H_*）。どれもローターの円の外（パッドの中心から 5.8 m 以上）。"""
    m = Mesh()
    pivots = {}
    wx, wy = K.gxz(K.h2g_xz(*K.H_WINDSOCK))
    m.prism(wx, wy, DY, DY + 0.1, 0.25, 0.25, 10, C["steel_dark"])
    m.prism(wx, wy, DY + 0.1, DY + 4.5, 0.075, 0.06, 10, C["white"], smooth=True)
    for k in range(3):
        z = DY + 1.0 + k * 1.2
        m.prism(wx, wy, z, z + 0.35, 0.078, 0.078, 10, C["orange"], smooth=True)
    pivots["windsock"] = (wx, wy, DY + 4.5)
    for i, hp in enumerate(K.H_FLAGS):
        x, y = K.gxz(K.h2g_xz(*hp))
        pivots["flag_%d" % i] = flagpole(m, x, y)
    for hp in K.H_FLOODS:
        x, y = K.gxz(K.h2g_xz(*hp))
        floodlight(m, x, y, _toward_centre(x, y))
    for hp in K.H_MONITORS:
        x, y = K.gxz(K.h2g_xz(*hp))
        fire_monitor(m, x, y, _toward_centre(x, y))
    cx, cy = K.gxz(K.PAD)
    for i, (hx, hz, _turn) in enumerate(K.H_CABINETS):
        x, y = K.gxz(K.h2g_xz(hx, hz))
        inward = (cx - x, cy - y)
        axis = (round(inward[0] / max(abs(inward[0]), abs(inward[1]))), round(inward[1] / max(abs(inward[0]), abs(inward[1]))))
        size = (0.7, 0.9, 1.25) if i == 0 else (0.7, 0.8, 0.95)
        if axis[1] != 0:
            size = (size[1], size[0], size[2])
        cabinet(m, x, y, size, C["white2"] if i == 0 else C["cobalt"], axis)
    for hp in K.H_BUOYS:
        x, y = K.gxz(K.h2g_xz(*hp))
        buoy_post(m, x, y)
    return m, pivots

# --- 確認用の仮置き --------------------------------------------------------------------
def player_proxy(col):
    """高さ 2.0m のキャラの仮置き（足元が原点）。"""
    m = Mesh()
    m.box((0, 0, 0.45), (0.5, 0.3, 0.9), shade(col, 0.8))
    m.box((0, 0, 1.2), (0.7, 0.42, 0.62), col)
    m.box((0, 0, 1.75), (0.55, 0.55, 0.5), col)
    for s in (-1, 1):
        m.box((s * 0.45, 0, 1.15), (0.18, 0.2, 0.62), col)
    m.box((0, -0.28, 1.78), (0.32, 0.02, 0.1), C["dark"])
    return m

"""水上機 C-130 の胴体：外板・内張り・切れ目の縁を 1 つの閉じた立体にし、スロープと上のふたを別の部品にする。

断面と輪は fp_section.py。外板と内張りは同じ番号の点を持つので、切れ目（スロープ・上のふた）の縁は点どうしをじかにつなぐ。
立体が閉じている（穴がない）ので、窓は Blender のブーリアン（exact）でくり抜ける。
"""
from __future__ import annotations

import math

from mathutils import Vector

import fp_section as S
from fp_common import GMesh, W

K = S.K
US = S.U_STATIONS

V_DOOR_OPEN = 5.00          # 上のふたを開けたときの前の端の下面（海面から）。スロープの床から 3.10（設計の「尾の下のすき間 3.1」）


def _center_v(u):
    s = S.section(min(max(u, S.NOSE_DOME_U), S.DOOR_END_U))
    return 0.5 * (s["top"] + s["bottom"])


def outer_material(u_mid, k):
    seg = S.edge_segment(k)
    if u_mid < S.HINGE_U:
        if seg <= 2:
            return "FP_Navy"
        if S.STRIPE_U[0] <= u_mid:
            if seg == 4:
                return "FP_StripeBlue"
            if seg == 6:
                return "FP_StripeOrange"
    return "FP_Paint"


def excluded(u_mid, k):
    return S.in_ramp(u_mid, k) or S.in_door(u_mid, k)


def build_shell():
    """外板＋内張り＋縁＋内張りの前後のふた（閉じた立体）。返り値 (GMesh, 情報)。"""
    g = GMesh()
    outer, inner = [], {}
    for i, u in enumerate(US):
        pts, _ = S.ring(u)
        if S.dome_scale(u) <= 0.0:
            vi = g.vert(pts[0])
            outer.append([vi] * K)
        else:
            outer.append([g.vert(p) for p in pts])
        if S.LINING_U0 - 1e-9 <= u <= S.LINING_U1 + 1e-9:
            ipts, _ = S.ring(u, offset=S.wall_at(u))
            inner[i] = [g.vert(p) for p in ipts]
    n_ring = len(US)
    stats = {"rings": n_ring, "points_per_ring": K, "outer_faces": 0, "inner_faces": 0, "rim_faces": 0}

    def centroid(idx):
        return sum((g.vg[j] for j in idx), Vector()) / len(idx)

    # 外板
    for i in range(n_ring - 1):
        u_mid = 0.5 * (US[i] + US[i + 1])
        axis = Vector((0.0, _center_v(u_mid), u_mid - S.U0))
        for k in range(K):
            if excluded(u_mid, k):
                continue
            kk = (k + 1) % K
            quad = [outer[i][k], outer[i][kk], outer[i + 1][kk], outer[i + 1][k]]
            c = centroid(quad)
            hint = c - axis
            if US[i] < S.NOSE_DOME_U:
                hint += Vector((0, 0, -0.3 * hint.length))
            g.face_idx(quad, outer_material(u_mid, k), smooth=True, hint=tuple(hint))
            stats["outer_faces"] += 1
    # 内張り
    lin = sorted(inner)
    for a, b in zip(lin[:-1], lin[1:]):
        u_mid = 0.5 * (US[a] + US[b])
        axis = Vector((0.0, _center_v(u_mid), u_mid - S.U0))
        for k in range(K):
            if excluded(u_mid, k):
                continue
            kk = (k + 1) % K
            quad = [inner[a][k], inner[a][kk], inner[b][kk], inner[b][k]]
            g.face_idx(quad, "FP_InteriorWall", smooth=True, hint=tuple(axis - centroid(quad)))
            stats["inner_faces"] += 1
    # 切れ目の縁（外板と内張りの両方がある所だけ。u 11.2〜17.85）
    for i in range(n_ring - 1):
        if i not in inner or (i + 1) not in inner:
            continue
        u_mid = 0.5 * (US[i] + US[i + 1])
        for k in range(K):
            a_ex = excluded(u_mid, (k - 1) % K)
            b_ex = excluded(u_mid, k)
            if a_ex == b_ex:
                continue
            # 点 k の線（u_i → u_i+1）。切れ目の側へ向ける
            o0, o1 = outer[i][k], outer[i + 1][k]
            n0, n1 = inner[i][k], inner[i + 1][k]
            toward = (k + 1) % K if b_ex else (k - 1) % K
            hint = g.vg[outer[i][toward]] - g.vg[o0]
            g.face_idx([o0, o1, n1, n0], "FP_InteriorFrame", smooth=False, hint=tuple(hint))
            stats["rim_faces"] += 1
    for i in range(1, n_ring - 1):
        if i not in inner:
            continue
        u_prev = 0.5 * (US[i - 1] + US[i])
        u_next = 0.5 * (US[i] + US[i + 1])
        for k in range(K):
            p_ex = excluded(u_prev, k)
            n_ex = excluded(u_next, k)
            if p_ex == n_ex:
                continue
            kk = (k + 1) % K
            hint = (0.0, 0.0, 1.0) if n_ex else (0.0, 0.0, -1.0)
            g.face_idx([outer[i][k], outer[i][kk], inner[i][kk], inner[i][k]], "FP_InteriorFrame", smooth=False, hint=hint)
            stats["rim_faces"] += 1
    # 内張りの前（計器盤の奥）と後ろ（尾の先）のふた
    for idx, out, mat in ((lin[0], (0, 0, 1), "FP_InteriorDark"), (lin[-1], (0, 0, -1), "FP_InteriorWall")):
        ring_idx = inner[idx]
        c = g.vert(tuple(centroid(ring_idx)))
        for k in range(K):
            g.face_idx([ring_idx[k], ring_idx[(k + 1) % K], c], mat, smooth=False, hint=out)
    stats["triangles"] = g.triangles()
    stats["rejected"] = g.rejected
    return g, stats


# ---------------------------------------------------------------- スロープ（閉じた位置で作る。原点は付け根）

def ramp_frame():
    """スロープの上面の座標：原点（付け根の線の真ん中）、後ろ上への向き、横、上面の法線（Godot）。"""
    a = math.radians(S.RAMP_CLOSED_DEG)
    origin = W(S.HINGE_U, S.FLOOR_V, 0.0)
    along = Vector((0.0, math.sin(a), math.cos(a)))
    across = Vector((1.0, 0.0, 0.0))
    up = Vector((0.0, math.cos(a), -math.sin(a)))
    return origin, along, across, up


def ramp_point(s, x, h=0.0):
    o, al, ac, up = ramp_frame()
    return tuple(o + al * s + ac * x + up * h)


def build_ramp():
    g = GMesh()
    ids = [i for i, u in enumerate(US) if S.HINGE_U - 1e-9 <= US[i] <= S.RAMP_END_U + 1e-9]
    kr = S.SEG_START[2]
    arc = list(range(K - kr, K)) + list(range(0, kr + 1))        # R 左 → B → R 右
    rings = {}
    for i in ids:
        pts, nrm = S.ring(US[i])
        rings[i] = ([g.vert(pts[k]) for k in arc], [nrm[k] for k in arc])
    tops = {}
    for i in ids:
        s = (US[i] - S.HINGE_U) / math.cos(math.radians(S.RAMP_CLOSED_DEG))
        tops[i] = (g.vert(ramp_point(s, -S.RAMP_HALF_W)), g.vert(ramp_point(s, S.RAMP_HALF_W)))
    _, _, _, up = ramp_frame()
    for a, b in zip(ids[:-1], ids[1:]):
        ra, rb = rings[a][0], rings[b][0]
        for j in range(len(arc) - 1):
            quad = [ra[j], ra[j + 1], rb[j + 1], rb[j]]
            nx, nv, _ = rings[a][1][j]
            g.face_idx(quad, "FP_Paint", smooth=True, hint=(nx, nv, 0.0))
        g.face_idx([tops[a][0], tops[a][1], tops[b][1], tops[b][0]], "FP_InteriorFloor", hint=tuple(up))
        g.face_idx([tops[a][1], tops[b][1], rb[-1], ra[-1]], "FP_InteriorFrame", hint=(1, 0, 0))
        g.face_idx([tops[a][0], tops[b][0], rb[0], ra[0]], "FP_InteriorFrame", hint=(-1, 0, 0))
    for i, out in ((ids[0], (0, 0, -1)), (ids[-1], (0, 0, 1))):
        poly = [tops[i][0], tops[i][1]] + list(reversed(rings[i][0]))
        g.face_idx(poly, "FP_InteriorFrame", hint=out)
    return g, W(S.HINGE_U, S.FLOOR_V, 0.0)


# ---------------------------------------------------------------- 上のふた（尾の下。閉じた位置で作る。原点は後ろの端の蝶番）

def door_hinge():
    s = S.section(S.DOOR_END_U)
    return S.DOOR_END_U, s["bottom"] + S.DOOR_THICK


def door_open_deg():
    """前の端の真ん中の下面が V_DOOR_OPEN に来る角度（前を上げる向き＝Godot のローカル +X まわりの正）。"""
    hu, hv = door_hinge()
    fu, fv = S.RAMP_END_U, S.section(S.RAMP_END_U)["bottom"]
    du, dv = fu - hu, fv - hv
    lo, hi = 0.0, 1.2
    for _ in range(60):
        m = 0.5 * (lo + hi)
        if hv - du * math.sin(m) + dv * math.cos(m) < V_DOOR_OPEN:
            lo = m
        else:
            hi = m
    return math.degrees(lo)


def build_door():
    g = GMesh()
    ids = [i for i, u in enumerate(US) if S.RAMP_END_U - 1e-9 <= US[i] <= S.DOOR_END_U + 1e-9]
    kd = S.SEG_START[1]
    arc = list(range(K - kd, K)) + list(range(0, kd + 1))        # D 左 → B → D 右
    outer, inner, nrms = {}, {}, {}
    for i in ids:
        pts, nrm = S.ring(US[i])
        outer[i] = [g.vert(pts[k]) for k in arc]
        inner[i] = [g.vert((pts[k][0] - S.DOOR_THICK * nrm[k][0], pts[k][1] - S.DOOR_THICK * nrm[k][1], pts[k][2])) for k in arc]
        nrms[i] = [nrm[k] for k in arc]
    for a, b in zip(ids[:-1], ids[1:]):
        for j in range(len(arc) - 1):
            nx, nv, _ = nrms[a][j]
            g.face_idx([outer[a][j], outer[a][j + 1], outer[b][j + 1], outer[b][j]], "FP_Paint", smooth=True, hint=(nx, nv, 0))
            g.face_idx([inner[a][j], inner[a][j + 1], inner[b][j + 1], inner[b][j]], "FP_InteriorWall", smooth=True, hint=(-nx, -nv, 0))
        for j, side in ((0, -1), (len(arc) - 1, 1)):
            g.face_idx([outer[a][j], outer[b][j], inner[b][j], inner[a][j]], "FP_InteriorFrame", hint=(side, 0.3, 0))
    for i, out in ((ids[0], (0, 0, -1)), (ids[-1], (0, 0, 1))):
        for j in range(len(arc) - 1):
            g.face_idx([outer[i][j], outer[i][j + 1], inner[i][j + 1], inner[i][j]], "FP_InteriorFrame", hint=out)
    hu, hv = door_hinge()
    return g, W(hu, hv, 0.0)


# ---------------------------------------------------------------- 窓の型（閉じた立体。ブーリアンでくり抜く）

PORTHOLE_U = list(S.C.PORTHOLES_U)               # 丸窓（左右に 3 つずつ）
FRONT_PANES = [(0.04, 0.60)]                        # 前の窓（|x| の範囲、左右に同じ）：真ん中の 2 枚
# 窓の下の端はハテナの目（座って v 約 4.4）より下：計器盤のひさし（v 4.12）のすぐ上まで下げて、外から顔が見える。
# 上の端は実機のように低く（前の窓は横に長い。ハテナの頭のてっぺんは窓の上の外板に隠れる）
FRONT_V = (4.15, 4.68)
FRONT_U = (0.30, 1.26)                               # 前の窓の型は u のこの範囲だけ（横の壁を切らない）
# 横の窓（u, v）。左右に同じ。実機（C-130）のように：
#   角の窓：前の真ん中の窓のとなり（外板の |x| 0.66、柱 6 cm）から角を回り込み、横の窓の前の柱（u 1.26〜1.32）まで。
#           上と下の端は前の窓と同じ高さ（v 4.15〜4.68）。内の縁は外板の |x| 0.66 の線そのもの（corner_inner_u。
#           真ん中の窓の外の縁 |x| 0.60 と平行で、柱の幅が上から下まで同じ 6 cm）。下 u 0.465・上 u 0.911。
#   横の窓：前の窓の上の端（v 4.68）を真ん中に横の枠（6 cm のすき間）を入れて、下の段と上の段（ブロウ窓）に分ける。
FRONT_TOP_LINE = FRONT_V[1]
SIDE_BAR = (FRONT_TOP_LINE - 0.03, FRONT_TOP_LINE + 0.03)
CORNER_X = 0.66
CORNER_PANE = ((0.465, 4.15), (1.26, 4.135), (1.26, FRONT_TOP_LINE), (0.911, FRONT_TOP_LINE))   # 前の 2 点の u は目安（corner_inner_u）
SIDE_PANES = [((1.32, 4.13), (2.08, 4.15), (2.08, SIDE_BAR[0]), (1.32, SIDE_BAR[0])),
              ((1.32, SIDE_BAR[1]), (2.08, SIDE_BAR[1]), (2.08, 5.10), (1.32, 4.98)),
              ((2.15, 4.15), (2.86, 4.17), (2.86, SIDE_BAR[0]), (2.15, SIDE_BAR[0])),
              ((2.15, SIDE_BAR[1]), (2.86, SIDE_BAR[1]), (2.86, 5.16), (2.15, 5.10))]
SIDE_X = (0.63, 2.70)                                # 横の窓の型の |x| の範囲（0.63＝前の真ん中の窓と角の窓の柱の真ん中。型が重ならない）
FRAME_MARGIN = 0.065


def corner_inner_u(v, x=CORNER_X):
    """高さ v で外板の |x| が x になる u（角の窓の内の縁）。"""
    lo, hi = 0.25, 1.6
    for _ in range(50):
        m = 0.5 * (lo + hi)
        s = S.section(m)
        w = S.x_at_v(s, min(v, s["top"] - 1e-3)) if v < s["top"] else 0.0
        if w < abs(x):
            lo = m
        else:
            hi = m
    return 0.5 * (lo + hi)


def corner_uv(a, b):
    """角の窓の中の (a, b)（a 0＝内の縁 → 1＝外の縁、b 0＝下 → 1＝上）の (u, v)。内の縁は |x| 0.66 の線にそう。"""
    p0, p1, p2, p3 = CORNER_PANE
    v_in = p0[1] + (p3[1] - p0[1]) * b
    u_in = corner_inner_u(v_in)
    u_out = p1[0] + (p2[0] - p1[0]) * b
    v_out = p1[1] + (p2[1] - p1[1]) * b
    return (u_in + (u_out - u_in) * a, v_in + (v_out - v_in) * a)


def corner_outline(n=8):
    """角の窓の型の輪郭（u, v）：下の内 → 外の 2 点 → 上の内 → 内の縁を上から下へ（凸）。"""
    pts = [corner_uv(0.0, 0.0), corner_uv(1.0, 0.0), corner_uv(1.0, 1.0)]
    for k in range(n, 0, -1):
        pts.append(corner_uv(0.0, k / n))
    return pts


def window_cutters(margin=0.0):
    """操縦席の窓の型（前・横）。margin > 0 で外へ広げた型（窓枠用、1 つの帯にまとめる）。"""
    g = GMesh()
    if margin <= 0:
        for side in (-1, 1):
            for x0, x1 in FRONT_PANES:
                xa, xb = sorted((side * x0, side * x1))
                poly = [(xa, FRONT_V[0], 0), (xb, FRONT_V[0], 0), (xb, FRONT_V[1], 0), (xa, FRONT_V[1], 0)]
                poly = [(x, v, FRONT_U[0] - S.U0) for x, v, _ in poly]
                g.prism(poly, (0, 0, 0), (0, 0, FRONT_U[1] - FRONT_U[0]), "FP_Navy")
            for pane in SIDE_PANES + [corner_outline()]:
                poly = [(side * SIDE_X[0], v, u - S.U0) for u, v in pane]
                g.prism(poly, (0, 0, 0), (side * (SIDE_X[1] - SIDE_X[0]), 0, 0), "FP_Navy")
    else:
        m = margin
        poly = [(-FRONT_PANES[-1][1] - m, FRONT_V[0] - m), (FRONT_PANES[-1][1] + m, FRONT_V[0] - m),
                (FRONT_PANES[-1][1] + m, FRONT_V[1] + m), (-FRONT_PANES[-1][1] - m, FRONT_V[1] + m)]
        g.prism([(x, v, FRONT_U[0] - S.U0) for x, v in poly], (0, 0, 0), (0, 0, FRONT_U[1] + 0.04 - FRONT_U[0]), "FP_Navy")
        for side in (-1, 1):
            a, b = SIDE_PANES[0], SIDE_PANES[-1]
            poly = [(a[0][0] - m, a[0][1] - m), (b[1][0] + m, b[1][1] - m), (b[2][0] + m, b[2][1] + m), (a[3][0] - m, a[3][1] + m)]
            g.prism([(side * SIDE_X[0], v, u - S.U0) for u, v in poly], (0, 0, 0), (side * (SIDE_X[1] - SIDE_X[0]), 0, 0), "FP_Navy")
    return g


def porthole_cutters():
    g = GMesh()
    for side in (-1, 1):
        for u in PORTHOLE_U:
            c = W(u, C_WINDOW_V(), 0.0)
            g.lathe((side * 1.2, c.y, c.z), (side, 0, 0), [(0.0, C_WINDOW_R()), (1.6, C_WINDOW_R())], "FP_InteriorFrame", n=20,
                    smooth=False, cap0="flat", cap1="flat")
    return g


def C_WINDOW_V():
    return S.C.WINDOW_V


def C_WINDOW_R():
    return S.C.WINDOW_R


def skin_sheet(u0, u1, off0, off1, k_from=None):
    """外板を法線にそって off0〜off1 だけずらした薄い板（閉じた立体）。窓のガラス（内へ）と窓枠（外へ）を作る元。
    off は外向きが正。k_from 以降の点（上の区間）だけ使う。"""
    g = GMesh()
    ka = S.SEG_START[7] if k_from is None else k_from
    ks = list(range(ka, K - ka + 1))       # 右の o2 から T を通って左の o2 まで
    us = [u for u in US if u0 - 1e-9 <= u <= u1 + 1e-9]
    if us[0] > u0 + 1e-9:
        us = [u0] + us
    if us[-1] < u1 - 1e-9:
        us = us + [u1]
    lay = {0: [], 1: []}
    for u in us:
        pts, nrm = S.ring(u)
        for li, off in ((0, off0), (1, off1)):
            lay[li].append([g.vert((pts[k][0] + off * nrm[k][0], pts[k][1] + off * nrm[k][1], pts[k][2])) for k in ks])
    nk = len(ks)
    for i in range(len(us) - 1):
        for j in range(nk - 1):
            for li, sgn in ((0, -1), (1, 1)):
                r0, r1 = lay[li][i], lay[li][i + 1]
                quad = [r0[j], r0[j + 1], r1[j + 1], r1[j]]
                c = sum((g.vg[q] for q in quad), Vector()) / 4
                axis = Vector((0, _center_v(us[i]), us[i] - S.U0))
                g.face_idx(quad, "FP_Glass", smooth=True, hint=tuple((c - axis) * sgn))
        for j, jn in ((0, 1), (nk - 1, nk - 2)):
            hint = g.vg[lay[0][i][j]] - g.vg[lay[0][i][jn]]
            g.face_idx([lay[0][i][j], lay[0][i + 1][j], lay[1][i + 1][j], lay[1][i][j]], "FP_Glass", hint=tuple(hint))
    for i, out in ((0, (0, 0, -1)), (len(us) - 1, (0, 0, 1))):
        for j in range(nk - 1):
            g.face_idx([lay[0][i][j], lay[0][i][j + 1], lay[1][i][j + 1], lay[1][i][j]], "FP_Glass", hint=out)
    return g


def tail_passage():
    """尾の下の通り道（上のふたを開けたとき）。u ごとに、動かない「ほお」の内側の半幅と、ほおの下端の高さ（海面から）。"""
    rows = []
    for u in [S.RAMP_END_U, 14.4, 14.8, 15.2, 15.6, 16.0, 16.4, 16.8, 17.2, 17.6, S.DOOR_END_U]:
        s = S.section(u)
        xd = S.door_x(u, s)
        rows.append({"z": round(u - S.U0, 3), "u": round(u, 3), "half_width": round(xd, 3), "cheek_bottom_y": round(S.v_at_x_lower(s, xd), 3),
                     "top_inner_y": round(s["top"] - S.wall_at(u), 3)})
    return rows

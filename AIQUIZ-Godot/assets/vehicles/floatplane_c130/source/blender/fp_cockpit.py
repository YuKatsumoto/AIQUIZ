"""水上機 C-130 の操縦席（2026-10-22、ユーザーの指示「輸送機のクオリティーを上げれるだけ上げて」で作り直した）。

前の操縦席は箱を並べた形だった（座席・台・天井の盤が四角い箱、計器盤の絵が左右反転して貼られていた）。
C-130J のグラスコックピットを手本に：
  計器盤     4 つの画面（PFD・地図・エンジン・気象レーダー）の立体の縁とソフトキー・ガラス、予備計器の縁、主警告／主注意の押しボタン、
             画面の下のつまみ。両わきの壁までの盤（遮断器）。絵は textures/fp_panel.png（make_textures.py の panel()）
  日よけ     角を丸めた布張りのひさし。後ろの面に自動操縦の盤（SPD・HDG・ALT・V/S の表示とつまみ）、上に磁気コンパス
  操縦かん   計器盤の下から斜めに出る柱（じゃばらの覆い）・真ん中の板・羊の角のような握り（ゴム）・無線のボタン
  ペダル     方向舵のペダル 2 つ
  座席       台座とレール・座面と背もたれのクッション（両わきのふくらみ）・頭あて・ひじかけ・肩のベルト・オレンジの縁取り
  台         右：パワーレバー 4・条件レバー 4・フラップのレバー・トリムの輪。左：無線の盤とつまみ
  天井の盤   天井の曲がりにそって下がる盤（エンジン始動・消火の取っ手・燃料・電気・防氷・灯）と、トグルスイッチ・つまみ
  そのほか   窓の内側の枠、窓の下の台（さん）、壁の酸素の盤とインターホン、座席の後ろの左の遮断器の棚、消火器と斧、床のマット
寸法の約束（ハテナの座る位置・操縦かんの握りの位置）は fp_interior.py の PILOT_* と YOKE_GRIP のまま。
カメラの通り道（floatplane_staging.gd の COCKPIT_EYE・COCKPIT_PASS・COCKPIT_BACK・TURN_MID・WINDSHIELD_*。右の x 0.5〜1.1、
v 4.4〜4.7）には物を置かない。
"""
from __future__ import annotations

import json
import math
from pathlib import Path

from mathutils import Matrix, Vector

import fp_section as S
import fp_interior as FI
import fp_detail as FD
from fp_common import GMesh, W, lerp

C = S.C
DECK_V = C.FLIGHT_DECK_V
TEX = Path(__file__).resolve().parents[2] / "textures"
PAN = json.loads((TEX / "fp_panel.json").read_text(encoding="utf-8"))
REG = PAN["regions"]
SIZE = PAN["sizes_m"]
ITEMS = PAN["items"]


def uv_of(region, X, Y):
    u0, v0, u1, v1 = REG[region]
    wm, hm = SIZE[region]
    return (u0 + (u1 - u0) * X / wm, v0 + (v1 - v0) * Y / hm)


# ---------------------------------------------------------------- 道具

def soft_box(g: GMesh, center, half, r, mat, axes=None, n=8, k=28):
    """角を丸めた箱（クッション・つまみ・台）。axes は (ex, ey, ez)（Godot）、half はその向きの半分の大きさ。ez にそって輪を並べる。"""
    ex, ey, ez = [Vector(a).normalized() for a in (axes or ((1, 0, 0), (0, 1, 0), (0, 0, 1)))]
    c = Vector(center)
    hx, hy, hz = half
    r = min(r, 0.95 * hx, 0.95 * hy, 0.95 * hz)
    ss = [-hz, -hz + r * 0.08, -hz + r * 0.3, -hz + r * 0.62, -hz + r]
    span = 2 * (hz - r)
    m = max(1, int(math.ceil(span / 0.25)))
    ss += [-hz + r + span * i / m for i in range(1, m)]
    ss += [hz - r, hz - r * 0.62, hz - r * 0.3, hz - r * 0.08, hz]
    rings = []
    for s in ss:
        e = max(0.0, abs(s) - (hz - r))
        d = r - math.sqrt(max(0.0, r * r - e * e))
        ax_, ay_ = hx - d, hy - d
        ring = []
        for i in range(k):
            a = 2 * math.pi * i / k
            cs, sn = math.cos(a), math.sin(a)
            ring.append(tuple(c + ex * (ax_ * math.copysign(abs(cs) ** (2 / n), cs)) + ey * (ay_ * math.copysign(abs(sn) ** (2 / n), sn)) + ez * s))
        rings.append(ring)
    g.loft(rings, mat, closed=True, smooth=True, cap0=True, cap1=True)


def axes_from(ez, up=(0, 1, 0)):
    """ez を長さの向きにした (ex, ey, ez)。ey は up にいちばん近い向き。"""
    ez = Vector(ez).normalized()
    ex = Vector(up).cross(ez)
    if ex.length < 1e-6:
        ex = Vector((1, 0, 0)).cross(ez)
    ex.normalize()
    ey = ez.cross(ex).normalized()
    return ex, ey, ez


def knob(g: GMesh, base, normal, r, h=0.02, mat="FP_KnobBlack", pointer=True):
    """丸いつまみ（ぎざぎざの胴と白い印）。"""
    n = Vector(normal).normalized()
    b = Vector(base)
    g.lathe(tuple(b - n * 0.002), tuple(n), [(0.0, r * 1.08), (0.003, r * 1.08), (0.004, r), (h * 0.85, r), (h, r * 0.82), (h + 0.001, 0.0)], mat,
            n=18, smooth=True, crease_deg=50)
    if pointer:
        ex, ey, ez = axes_from(n, up=(0, 1, 0) if abs(n.y) < 0.9 else (0, 0, -1))
        g.box(tuple(b + n * (h + 0.0012) + ey * (r * 0.45)), (r * 0.18, r * 0.75, 0.002), "FP_InteriorTrim", rot=Matrix((ex, ey, ez)).transposed())


def toggle(g: GMesh, base, normal, lean, mat="FP_InteriorMetal"):
    """トグルスイッチ（六角のナットと、少し傾いた棒と先の玉）。lean は棒の傾く向き。"""
    n = Vector(normal).normalized()
    b = Vector(base)
    g.lathe(tuple(b - n * 0.001), tuple(n), [(0.0, 0.0085), (0.006, 0.0085), (0.007, 0.006)], mat, n=6, smooth=False)
    tip = b + (n * 0.85 + Vector(lean).normalized() * 0.45).normalized() * 0.026
    g.tube(tuple(b + n * 0.005), tuple(tip), 0.0026, mat, n=8)
    g.lathe(tuple(tip - (tip - b).normalized() * 0.003), tuple((tip - b).normalized()), [(0.0, 0.0045), (0.004, 0.0045), (0.007, 0.0)], mat, n=10)


# ---------------------------------------------------------------- 計器盤

UB, UT = FI.DASH_FACE_U            # 0.86（下）, 0.74（上）
VB, VT = FI.DASH_V                 # 3.36, 4.02
DASH_W, DASH_L = SIZE["dash"]
HW = DASH_W / 2
FACE_A = W(UB, VB, 0.0)
FACE_UP = (W(UT, VT, 0.0) - FACE_A).normalized()
FACE_N = Vector((0.0, UB - UT, VT - VB)).normalized()
FACE_ROT = Matrix((Vector((1, 0, 0)), FACE_UP, FACE_N)).transposed()


def dash_pt(X, Y, lift=0.0):
    """計器盤の面の点。X はパイロットから見て左の端から（m）、Y は下の端から面にそって（m）。"""
    return FACE_A + Vector((X - HW, 0.0, 0.0)) + FACE_UP * Y + FACE_N * lift


def face_quad(g: GMesh, X0, Y0, X1, Y1, lift, mat, region="dash"):
    q = [dash_pt(X0, Y0, lift), dash_pt(X1, Y0, lift), dash_pt(X1, Y1, lift), dash_pt(X0, Y1, lift)]
    uv = [uv_of(region, X0, Y0), uv_of(region, X1, Y0), uv_of(region, X1, Y1), uv_of(region, X0, Y1)] if region else None
    g.oriented([tuple(p) for p in q], tuple(FACE_N), mat, uv=uv)


def face_walls(g: GMesh, X0, Y0, X1, Y1, l0, l1, mat, inward=False):
    corners = [(X0, Y0), (X1, Y0), (X1, Y1), (X0, Y1)]
    cx, cy = 0.5 * (X0 + X1), 0.5 * (Y0 + Y1)
    for (xa, ya), (xb, yb) in zip(corners, corners[1:] + corners[:1]):
        q = [dash_pt(xa, ya, l0), dash_pt(xb, yb, l0), dash_pt(xb, yb, l1), dash_pt(xa, ya, l1)]
        mid = dash_pt(0.5 * (xa + xb), 0.5 * (ya + yb), 0.0) - dash_pt(cx, cy, 0.0)
        g.oriented([tuple(p) for p in q], tuple(-mid if inward else mid), mat)


def face_frame(g: GMesh, outer, inner, h, mat_top, mat_side, region="dash"):
    """outer と inner の長方形のあいだの縁（高さ h）。上の面は絵（region）を貼る。"""
    (ox0, oy0, ox1, oy1), (ix0, iy0, ix1, iy1) = outer, inner
    o = [(ox0, oy0), (ox1, oy0), (ox1, oy1), (ox0, oy1)]
    i_ = [(ix0, iy0), (ix1, iy0), (ix1, iy1), (ix0, iy1)]
    for k in range(4):
        a, b = o[k], o[(k + 1) % 4]
        c, d = i_[(k + 1) % 4], i_[k]
        pts = [a, b, c, d]
        q = [dash_pt(x, y, h) for x, y in pts]
        g.oriented([tuple(p) for p in q], tuple(FACE_N), mat_top, uv=[uv_of(region, x, y) for x, y in pts] if region else None)
    face_walls(g, ox0, oy0, ox1, oy1, 0.0, h, mat_side)
    face_walls(g, ix0, iy0, ix1, iy1, 0.004, h, mat_side, inward=True)


def build_dash(g: GMesh):
    """計器盤の本体（暗い台）と、絵を貼った面・立体の縁・ガラス・つまみ・ボタン。"""
    poly_side = [(UB, VB), (UT, VT), (0.66, VT), (0.66, VB - 0.10), (UB, VB - 0.10)]
    g.prism([tuple(W(u, v, -HW)) for u, v in poly_side], (0, 0, 0), (2 * HW, 0, 0), "FP_InteriorDark")
    # 絵の面（パイロットから見て左 → 右が絵の左 → 右。前の版は左右が逆だった）
    nx_, ny_ = 12, 4
    for i in range(nx_):
        for j in range(ny_):
            face_quad(g, DASH_W * i / nx_, DASH_L * j / ny_, DASH_W * (i + 1) / nx_, DASH_L * (j + 1) / ny_, 0.004, "FP_InteriorPanel")
    it = ITEMS["dash"]
    mx, my = it["mfd_margin"]
    for x0, y0, x1, y1 in it["mfd"]:
        face_frame(g, (x0, y0, x1, y1), (x0 + mx, y0 + my, x1 - mx, y1 - my), 0.022, "FP_InteriorPanel", "FP_KnobBlack")
        face_quad(g, x0 + mx, y0 + my, x1 - mx, y1 - my, 0.012, "FP_Glass", region=None)
        # 縁の上の角のねじ
        for x, y in ((x0 + 0.008, y0 + 0.008), (x1 - 0.008, y0 + 0.008), (x0 + 0.008, y1 - 0.008), (x1 - 0.008, y1 - 0.008)):
            g.lathe(tuple(dash_pt(x, y, 0.021)), tuple(FACE_N), [(0.0, 0.0035), (0.0015, 0.0025), (0.002, 0.0)], "FP_InteriorMetal", n=8)
    for x, y in it["softkeys"]:
        g.box(tuple(dash_pt(x, y, 0.026)), (0.015, 0.019, 0.008), "FP_InteriorDoor", rot=FACE_ROT)
    for cx, cy, r in it["dials"]:
        c = dash_pt(cx, cy, 0.004)
        g.lathe(tuple(c), tuple(FACE_N), [(0.0, r + 0.013), (0.010, r + 0.013), (0.016, r + 0.008), (0.017, r + 0.002), (0.012, r)], "FP_KnobBlack",
                n=28, smooth=True, crease_deg=55)
        g.lathe(tuple(c + FACE_N * 0.008), tuple(FACE_N), [(0.0, r + 0.001), (0.001, r + 0.001)], "FP_Glass", n=28, cap1="flat")
        knob(g, dash_pt(cx + r * 0.80, cy - r * 0.80, 0.004), FACE_N, 0.009, h=0.012)
    for x, y, r in it["knobs"]:
        knob(g, dash_pt(x, y, 0.004), FACE_N, r, h=0.022)
    for x0, y0, x1, y1 in it["lights"]:
        face_walls(g, x0, y0, x1, y1, 0.004, 0.012, "FP_KnobBlack")
        face_quad(g, x0, y0, x1, y1, 0.012, "FP_InteriorPanel")
    # 両わきの盤（計器盤の端から壁まで。遮断器の絵）
    # 外の端は壁にそう（行の境ごとに壁までの幅を測る。階段にならない）
    cb_w, cb_h = SIZE["cb"]
    rows = 6
    ys = [DASH_L * j / rows for j in range(rows + 1)]
    exts = []
    for y in ys:
        p = dash_pt(0.0, y)
        exts.append(max(0.0, FI.wall_x(p.z + S.U0, p.y) - 0.012 - HW))
    for side in (-1, 1):
        for j in range(rows):
            y0, y1 = ys[j], ys[j + 1]
            e0, e1 = exts[j], exts[j + 1]
            if max(e0, e1) < 0.02:
                continue
            if side < 0:
                pts = [(-e0, y0), (0.0, y0), (0.0, y1), (-e1, y1)]
            else:
                pts = [(DASH_W, y0), (DASH_W + e0, y0), (DASH_W + e1, y1), (DASH_W, y1)]
            q = [dash_pt(X, Y, 0.004) for X, Y in pts]
            emax = max(exts)
            uv = [uv_of("cb", 0.05 + (X - DASH_W if side > 0 else X + emax), cb_h * (0.08 + 0.84 * Y / DASH_L)) for X, Y in pts]
            g.oriented([tuple(p) for p in q], tuple(FACE_N), "FP_InteriorPanel", uv=uv)
    # 足もとの板（操縦席の床から計器盤の下まで）
    g.oriented([tuple(W(0.88, DECK_V, -0.98)), tuple(W(0.88, DECK_V, 0.98)), tuple(W(0.86, VB - 0.08, 0.98)), tuple(W(0.86, VB - 0.08, -0.98))],
               (0, 0, 1), "FP_InteriorDark")


# ---------------------------------------------------------------- 日よけ（ひさし）と自動操縦の盤

GLARE_TOP = 4.128                  # 前の窓の下の端（v 4.15）より下
GLARE_LIP_U = 0.824
MCP_V = (4.012, 4.112)


def _outer_x(u, v):
    s = S.section(u)
    if v >= s["top"]:
        return 0.0
    return S.x_at_v(s, v)


def _glare_front_u(x):
    """ひさしの前の端の u：外板の外へ出ない（外板の |x| が x + 0.05 になる u より後ろ）。"""
    lo, hi = 0.40, 0.80
    for _ in range(40):
        m = 0.5 * (lo + hi)
        if _outer_x(m, GLARE_TOP + 0.01) < abs(x) + 0.05:
            lo = m
        else:
            hi = m
    return max(0.66, hi)


def build_glareshield(g: GMesh):
    x_end = min(0.97, FI.wall_x(0.80, GLARE_TOP) - 0.02)
    xs = [-x_end + 2 * x_end * i / 16 for i in range(17)]
    rings = []
    for x in xs:
        uf = _glare_front_u(x)
        prof = [(uf, 4.03), (uf, GLARE_TOP - 0.008), (uf + 0.04, GLARE_TOP), (0.79, GLARE_TOP - 0.002), (0.812, GLARE_TOP - 0.008),
                (GLARE_LIP_U - 0.002, MCP_V[1] + 0.004), (GLARE_LIP_U, MCP_V[1] - 0.004), (GLARE_LIP_U, MCP_V[0] + 0.004),
                (GLARE_LIP_U - 0.006, MCP_V[0] - 0.003), (0.79, MCP_V[0] - 0.008), (UT, VT - 0.002)]
        rings.append([tuple(W(u, v, x)) for u, v in prof])
    # 断面の輪を x にそって張る（ふたは平ら）
    g.loft(rings, "FP_Glareshield", closed=True, smooth=True, cap0=True, cap1=True,
           hint_fn=lambda i, k, rings=rings: _glare_hint(rings, i, k))
    # 自動操縦の盤（後ろの縦の面）
    mw, mh = SIZE["mcp"]
    x0, x1 = -mw / 2, mw / 2
    z = GLARE_LIP_U + 0.0015 - S.U0
    q = [(x0, MCP_V[0], z), (x1, MCP_V[0], z), (x1, MCP_V[1], z), (x0, MCP_V[1], z)]
    uv = [uv_of("mcp", 0.0, 0.0), uv_of("mcp", mw, 0.0), uv_of("mcp", mw, mh), uv_of("mcp", 0.0, mh)]
    g.oriented(q, (0, 0, 1), "FP_InteriorPanel", uv=uv)
    for X, Y, r in ITEMS["mcp"]["knobs"]:
        v = MCP_V[0] + Y * (MCP_V[1] - MCP_V[0]) / mh
        knob(g, (X - mw / 2, v, z), (0, 0, 1), r, h=0.018)
    # 磁気コンパス（ひさしの上の真ん中。窓の外から見える）
    cpos = W(0.70, GLARE_TOP + 0.002, 0.0)
    soft_box(g, cpos + Vector((0, 0.032, 0)), (0.045, 0.032, 0.040), 0.012, "FP_KnobBlack")
    g.oriented([tuple(cpos + Vector((sx * 0.026, 0.032 + sy * 0.018, 0.0405))) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))], (0, 0, 1), "FP_Lens")
    g.box(tuple(cpos + Vector((0, 0.032, 0.041))), (0.002, 0.03, 0.001), "FP_InteriorLampAmber")


def _glare_hint(rings, i, k):
    ring = rings[i]
    n = len(ring)
    c = sum((Vector(p) for p in ring), Vector()) / n
    a, b = Vector(ring[k]), Vector(ring[(k + 1) % n])
    mid = 0.5 * (a + b)
    d = mid - c
    return (0.0, d.y, d.z)


# ---------------------------------------------------------------- 操縦かんとペダル

def build_yoke(g: GMesh):
    gx, gv, gu = FI.YOKE_GRIP
    hub = W(gu - 0.03, gv - 0.06, 0.0)
    base = W(UB - 0.006, VB + 0.04, 0.0)
    d = (hub - base).normalized()
    L = (hub - base).length
    # 柱（太い外の管 → 細い中の管）と、付け根のじゃばら
    g.tube(tuple(base), tuple(base + d * L * 0.55), 0.046, "FP_InteriorDark", n=16)
    g.tube(tuple(base + d * L * 0.5), tuple(hub - d * 0.04), 0.034, "FP_InteriorMetal", n=16)
    bel = []
    for k in range(9):
        bel.append((0.012 * k, 0.074 if k % 2 == 0 else 0.058))
    g.lathe(tuple(base - d * 0.01), tuple(d), bel, "FP_Rubber", n=18, smooth=True, crease_deg=80)
    # 真ん中の板（オレンジの丸い印）
    ex, ey, ez = axes_from((0, 0, 1))
    soft_box(g, hub + Vector((0, 0.005, 0.0)), (0.075, 0.055, 0.035), 0.018, "FP_InteriorDark", axes=(ex, ey, ez))
    g.lathe(tuple(hub + Vector((0, 0.005, 0.034))), (0, 0, 1), [(0.0, 0.028), (0.004, 0.026), (0.006, 0.0)], "FP_InteriorKnob", n=20)
    # 羊の角のような握り（左右）
    for side in (-1, 1):
        pts = [(0.05, -0.065), (0.17, -0.078), (0.33, -0.092), (gx - 0.07, -0.082), (gx - 0.012, -0.045), (gx, 0.0), (gx, 0.075),
               (gx + 0.012, 0.115), (gx + 0.035, 0.135)]
        path = [tuple(W(gu + 0.004 * (1 - abs(px) / gx), gv + pv, side * px)) for px, pv in pts]
        g.polyline_tube(path, 0.022, "FP_InteriorDark", n=12)
        g.tube(tuple(W(gu, gv - 0.025, side * gx)), tuple(W(gu, gv + 0.085, side * gx)), 0.031, "FP_Rubber", n=14)
        tip = W(gu, gv + 0.135, side * (gx + 0.035))
        g.box(tuple(tip + Vector((0, 0.012, 0))), (0.03, 0.02, 0.03), "FP_InteriorRed")
        g.box(tuple(W(gu + 0.02, gv + 0.06, side * (gx - 0.03))), (0.018, 0.026, 0.016), "FP_InteriorMetal")


def build_pedals(g: GMesh):
    for side in (-1, 1):
        c = W(1.06, DECK_V + 0.22, side * 0.21)
        ez = Vector((0, 0.82, -0.57)).normalized()           # 板の長さ（上が前へ倒れる。面はパイロットの側を向く）
        ex, ey, ez = axes_from(ez, up=(0, 0, 1))
        soft_box(g, c, (0.05, 0.012, 0.10), 0.01, "FP_InteriorDark", axes=(Vector((1, 0, 0)), ey, ez))
        soft_box(g, c + ey * 0.012, (0.043, 0.006, 0.085), 0.005, "FP_Rubber", axes=(Vector((1, 0, 0)), ey, ez))
        g.tube(tuple(c - ey * 0.01), tuple(W(0.885, DECK_V + 0.30, side * 0.21)), 0.016, "FP_InteriorDark", n=10)


# ---------------------------------------------------------------- 座席

def build_seat(g: GMesh):
    ru = FI.PILOT_ROOT_U
    cv_ = FI.PILOT_CUSHION_V
    # 床のレールと台座
    for sx in (-1, 1):
        g.box(tuple(W(ru + 0.2, DECK_V + 0.012, sx * 0.17)), (0.04, 0.024, 1.0), "FP_InteriorMetal")
    soft_box(g, W(ru + 0.2, 0.5 * (DECK_V + cv_ - 0.14), 0.0), (0.17, 0.5 * (cv_ - 0.14 - DECK_V), 0.21), 0.03, "FP_InteriorDark")
    for sx in (-1, 1):
        g.tube(tuple(W(ru + 0.36, DECK_V + 0.08, sx * 0.17)), tuple(W(ru + 0.36, cv_ - 0.15, sx * 0.17)), 0.018, "FP_InteriorMetal", n=10)
        g.tube(tuple(W(ru + 0.02, DECK_V + 0.08, sx * 0.17)), tuple(W(ru + 0.02, cv_ - 0.15, sx * 0.17)), 0.018, "FP_InteriorMetal", n=10)
    g.box(tuple(W(ru - 0.13, cv_ - 0.16, 0.12)), (0.06, 0.02, 0.10), "FP_InteriorYellow")      # 高さの調整のレバー
    # 座面（枠とクッション。両わきが少しふくらむ）
    soft_box(g, W(ru + 0.17, cv_ - 0.125, 0.0), (0.355, 0.035, 0.335), 0.02, "FP_InteriorDark")
    soft_box(g, W(ru + 0.17, cv_ - 0.05, 0.0), (0.33, 0.05, 0.32), 0.045, "FP_InteriorSeat")
    for sx in (-1, 1):
        soft_box(g, W(ru + 0.17, cv_ - 0.035, sx * 0.30), (0.055, 0.055, 0.31), 0.045, "FP_InteriorSeat")
    soft_box(g, W(ru - 0.155, cv_ - 0.05, 0.0), (0.33, 0.012, 0.008), 0.006, "FP_StripeOrange")         # 前の縁取り
    # 背もたれ（少し後ろへ倒れる）
    a = W(ru + 0.47, cv_ - 0.02, 0.0)
    b = W(ru + 0.63, cv_ + 0.92, 0.0)
    ez = (b - a).normalized()
    ex = Vector((1, 0, 0))
    ey = ez.cross(ex).normalized()           # 前（パイロットの背中の向き）
    mid = 0.5 * (a + b)
    half_len = 0.5 * (b - a).length
    soft_box(g, mid - ey * 0.03, (0.34, 0.06, half_len), 0.03, "FP_InteriorDark", axes=(ex, ey, ez))
    soft_box(g, mid + ey * 0.03, (0.31, 0.055, half_len - 0.04), 0.05, "FP_InteriorSeat", axes=(ex, ey, ez))
    for sx in (-1, 1):
        soft_box(g, mid + ey * 0.05 + ex * (sx * 0.29), (0.06, 0.075, half_len - 0.06), 0.05, "FP_InteriorSeat", axes=(ex, ey, ez))
        soft_box(g, mid + ey * 0.075 + ex * (sx * 0.343), (0.007, 0.012, half_len - 0.05), 0.005, "FP_StripeOrange", axes=(ex, ey, ez))
    # 頭あて
    h0 = b + ez * 0.15 - ey * 0.01
    soft_box(g, h0, (0.21, 0.07, 0.12), 0.05, "FP_InteriorSeat", axes=(ex, ey, ez))
    for sx in (-1, 1):
        g.tube(tuple(h0 - ez * 0.08 + ex * (sx * 0.12) - ey * 0.02), tuple(b - ez * 0.02 + ex * (sx * 0.12) - ey * 0.02), 0.009, "FP_InteriorMetal", n=8)
    # ひじかけ（左右。座面より外）
    for sx in (-1, 1):
        soft_box(g, W(ru + 0.30, cv_ + 0.22, sx * 0.43), (0.035, 0.03, 0.19), 0.022, "FP_InteriorSeat")
        g.box(tuple(W(ru + 0.44, cv_ + 0.10, sx * 0.43)), (0.03, 0.22, 0.04), "FP_InteriorDark")
        g.tube(tuple(W(ru + 0.44, cv_ + 0.21, sx * 0.43)), tuple(W(ru + 0.52, cv_ + 0.21, sx * 0.36)), 0.012, "FP_InteriorMetal", n=8)
    # 肩のベルト（背もたれの上から垂れる）と腰のベルトの金具
    for sx in (-1, 1):
        top = b + ey * 0.06 + ex * (sx * 0.15) - ez * 0.05
        FI._strap(g, top, top - ez * 0.55 + ey * 0.04, 0.05, ey, mat="FP_InteriorBelt")
        g.box(tuple(W(ru + 0.30, cv_ + 0.01, sx * 0.31)), (0.05, 0.02, 0.08), "FP_InteriorMetal")


# ---------------------------------------------------------------- 横の台（右：スロットル、左：無線）

CONSOLE_U = (1.05, 2.05)
CONSOLE_X = (0.82, 1.22)
CONSOLE_TOP = DECK_V + 0.62


def _console_point(side, X, Y, lift=0.002):
    """台の上の面の点。右（side 1）は X 0 が内側、左（−1）は X 0 が外側。Y 0 が後ろ（u 2.05）、1.0 が前（u 1.05）。"""
    u = CONSOLE_U[1] - Y
    x = CONSOLE_X[0] + X if side > 0 else -CONSOLE_X[1] + X
    return W(u, CONSOLE_TOP + lift, x)


def build_consoles(g: GMesh):
    cw, ch = CONSOLE_X[1] - CONSOLE_X[0], CONSOLE_U[1] - CONSOLE_U[0]
    for side, region in ((1, "console_r"), (-1, "console_l")):
        xc = side * 0.5 * (CONSOLE_X[0] + CONSOLE_X[1])
        soft_box(g, W(0.5 * (CONSOLE_U[0] + CONSOLE_U[1]), 0.5 * (DECK_V + CONSOLE_TOP), xc), (0.5 * cw + 0.006, 0.5 * (CONSOLE_TOP - DECK_V), 0.5 * ch + 0.006),
                 0.012, "FP_InteriorDark")
        wm, hm = SIZE[region]
        q = [_console_point(side, 0, 0), _console_point(side, wm, 0), _console_point(side, wm, hm), _console_point(side, 0, hm)]
        uv = [uv_of(region, 0, 0), uv_of(region, wm, 0), uv_of(region, wm, hm), uv_of(region, 0, hm)]
        g.oriented([tuple(p) for p in q], (0, 1, 0), "FP_InteriorPanel", uv=uv)
    # 右：レバー
    for lv in ITEMS["console_r"]["levers"]:
        y_at = lv["y0"] + (lv["y1"] - lv["y0"]) * lv["at"]
        base = _console_point(1, lv["x"], y_at, 0.0)
        tall = {"power": 0.17, "cond": 0.11, "flap": 0.14}[lv["kind"]]
        top = base + Vector((0, tall, -0.035))
        g.box_between(tuple(base - Vector((0, 0.03, 0))), tuple(top), 0.010, 0.022, "FP_InteriorMetal", up=(0, 0, 1))
        if lv["kind"] == "power":
            soft_box(g, top + Vector((0, 0.012, 0)), (0.018, 0.022, 0.028), 0.012, "FP_InteriorTrim")
        elif lv["kind"] == "cond":
            soft_box(g, top + Vector((0, 0.010, 0)), (0.014, 0.016, 0.020), 0.010, "FP_InteriorRed")
        else:
            soft_box(g, top + Vector((0, 0.010, 0)), (0.032, 0.010, 0.022), 0.008, "FP_InteriorTrim")
    # 右の台の内側の面：トリムの輪（半分が台から出る）
    c = W(1.72, DECK_V + 0.33, CONSOLE_X[0] - 0.004)
    g.lathe(tuple(c), (-1, 0, 0), [(0.0, 0.105), (0.03, 0.105), (0.034, 0.095), (0.034, 0.0)], "FP_KnobBlack", n=28, smooth=False)
    g.box(tuple(c + Vector((-0.035, 0.0, -0.104))), (0.004, 0.012, 0.012), "FP_InteriorTrim")
    for k in range(12):
        a = 2 * math.pi * k / 12
        g.box(tuple(c + Vector((-0.015, math.sin(a) * 0.106, math.cos(a) * 0.106))), (0.026, 0.008, 0.008), "FP_KnobBlack")
    # 左：無線のつまみ
    for X, Y, r in ITEMS["console_l"]["knobs"]:
        knob(g, _console_point(-1, X, Y, 0.0), (0, 1, 0), r, h=0.02)


# ---------------------------------------------------------------- 天井の盤

# ハテナの頭の「？」は天井（v 約 5.2、u 1.3〜2.2）まで届くので、盤は座席の頭あての後ろから出入り口の前まで（実機の C-130 も
# 天井の盤は座席の上から後ろへ伸びる）。長さは絵の領域（fp_panel.json の sizes_m.overhead）と同じ
OH_HW = 0.40
OH_DROP = 0.075
OH_U = (2.30, 2.30 + SIZE["overhead"][1])


def oh_point(X, Y, extra=0.0):
    """天井の盤の下の面の点。X 0 が左（−x）、Y 0 が前（OH_U[0]）、領域の高さが後ろ（OH_U[1]）。
    前を向いて頭を後ろへ倒して見上げると、目に映る上は機体の後ろ：絵の上を後ろにすると文字が正しく読める。"""
    x = X - OH_HW
    u = OH_U[0] + Y
    return W(u, FI.roof_v(u, x) - OH_DROP - extra, x)


def build_overhead(g: GMesh):
    wm, hm = SIZE["overhead"]
    nx_, ny_ = 8, 10
    grid = [[oh_point(wm * i / nx_, hm * j / ny_) for j in range(ny_ + 1)] for i in range(nx_ + 1)]
    for i in range(nx_):
        for j in range(ny_):
            pts = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            q = [grid[a][b] for a, b in pts]
            uv = [uv_of("overhead", wm * a / nx_, hm * b / ny_) for a, b in pts]
            g.oriented([tuple(p) for p in q], (0, -1, 0), "FP_InteriorPanel", uv=uv)
    # 縁の壁（天井の中まで）
    def up_pt(X, Y):
        x = X - OH_HW
        u = OH_U[0] + Y
        return W(u, FI.roof_v(u, x) + 0.03, x)
    edges = [[(wm * i / nx_, 0.0) for i in range(nx_ + 1)], [(wm, hm * j / ny_) for j in range(ny_ + 1)],
             [(wm * (nx_ - i) / nx_, hm) for i in range(nx_ + 1)], [(0.0, hm * (ny_ - j) / ny_) for j in range(ny_ + 1)]]
    outs = [(0, 0, -1), (1, 0, 0), (0, 0, 1), (-1, 0, 0)]
    for edge, out in zip(edges, outs):
        for (xa, ya), (xb, yb) in zip(edge[:-1], edge[1:]):
            q = [oh_point(xa, ya), oh_point(xb, yb), up_pt(xb, yb), up_pt(xa, ya)]
            g.oriented([tuple(p) for p in q], out, "FP_InteriorDark")
    it = ITEMS["overhead"]
    for X, Y in it["toggles"]:
        toggle(g, oh_point(X, Y, 0.001), (0, -1, 0), (0, 0, -1))
    for X, Y, r in it["knobs"]:
        knob(g, oh_point(X, Y, 0.0), (0, -1, 0), r, h=0.018)
    for X, Y in it["guards"]:
        p = oh_point(X, Y, 0.0)
        g.box(tuple(p + Vector((0, -0.012, 0))), (0.012, 0.024, 0.012), "FP_InteriorMetal")
        soft_box(g, p + Vector((0, -0.032, 0)), (0.028, 0.012, 0.016), 0.008, "FP_InteriorRed")
    # 両わきの吹き出し口（丸い首ふり）
    for sx in (-1, 1):
        p = oh_point(OH_HW + sx * (OH_HW + 0.06), 0.62 * hm, -0.03)
        g.lathe(tuple(p), (0, -1, 0), [(0.0, 0.035), (0.012, 0.034), (0.022, 0.024), (0.022, 0.0)], "FP_InteriorTrim", n=14)
        g.lathe(tuple(p + Vector((0, -0.021, 0))), (0, -1, 0), [(0.0, 0.016), (0.003, 0.0)], "FP_InteriorDark", n=12)


# ---------------------------------------------------------------- 窓の内側の枠・窓の下の台・壁の盤

def build_window_trims(g: GMesh):
    for kind, ring, side in FD.pane_outlines():
        # 横の窓は内張りの面。前と角の窓は機首の丸みで内へ押すと窓の上の縁が下がり、窓から入るカメラの道すじ
        # （floatplane_staging.gd の WINDSHIELD_IN、v 4.45）に近づくので、窓の穴の中ほどに置く（12 cm より離す）
        wall = 0.185 if kind == "side" else 0.07
        pts = []
        steps = 8
        for e in range(4):
            for k in range(steps):
                t = k / steps
                a, b = [(t, 0.0), (1.0, t), (1.0 - t, 1.0), (0.0, 1.0 - t)][e]
                p, n = FD._pane_point(kind, ring, side, a, b, -wall)
                pts.append((p, -Vector(n)))
        pts.append(pts[0])
        FD.strip_on(g, pts, 0.055, "FP_InteriorDark", lift=0.004)


def build_sills(g: GMesh):
    """横の窓の下の台（さん）：窓の下の端にそう丸い棒（ひじを置く）。"""
    for side in (-1, 1):
        pts = []
        for i in range(9):
            u = lerp(1.15, 2.95, i / 8)
            v = 4.06
            x = FI.wall_x(u, v) - 0.035
            pts.append(tuple(W(u, v, side * x)))
        g.polyline_tube(pts, 0.032, "FP_InteriorDark", n=10)


def _wall_panel(g: GMesh, side, u0, u1, v0, v1, region, X0, Y0, X1, Y1, depth=0.05):
    """壁に付けた平らな盤（箱）。表の面に絵（region の X0..X1, Y0..Y1）。"""
    xw = min(FI.wall_x(u, v) for u in (u0, u1) for v in (v0, v1)) - 0.012
    xf = xw - depth
    sx = side
    # 壁に向かって見たとき、絵の左が左に来る並び（右の壁は前が左、左の壁は後ろが左）
    face = [W(u0, v0, sx * xf), W(u1, v0, sx * xf), W(u1, v1, sx * xf), W(u0, v1, sx * xf)] if side > 0 else \
        [W(u1, v0, sx * xf), W(u0, v0, sx * xf), W(u0, v1, sx * xf), W(u1, v1, sx * xf)]
    uv = [uv_of(region, X0, Y0), uv_of(region, X1, Y0), uv_of(region, X1, Y1), uv_of(region, X0, Y1)]
    g.oriented([tuple(p) for p in face], (-sx, 0, 0), "FP_InteriorPanel", uv=uv)
    strip = FI.strip_box
    strip(g, u0 - 0.01, u1 + 0.01, sx * xf, sx * (xw + 0.05), v0 - 0.01, v0, "FP_InteriorDark")
    strip(g, u0 - 0.01, u1 + 0.01, sx * xf, sx * (xw + 0.05), v1, v1 + 0.01, "FP_InteriorDark")
    strip(g, u0 - 0.01, u0, sx * xf, sx * (xw + 0.05), v0, v1, "FP_InteriorDark")
    strip(g, u1, u1 + 0.01, sx * xf, sx * (xw + 0.05), v0, v1, "FP_InteriorDark")


def build_walls(g: GMesh):
    mw, mh = SIZE["misc"]
    # 左の壁：酸素の盤（座席の横）、右の壁：インターホン（低い所。カメラの通り道より下）
    _wall_panel(g, -1, 2.30, 2.66, 3.62, 3.80, "misc", 0.0, 0.20, mw, mh)
    _wall_panel(g, 1, 2.35, 2.71, 3.40, 3.58, "misc", 0.0, 0.0, mw, 0.20)
    # 左の後ろの棚（遮断器の盤 2 段。座席の後ろ、操縦席の床から）
    u0, u1 = 2.42, 3.05
    x_in = -1.42
    FI.strip_box(g, u0, u1, x_in, -FI.wall_x(2.7, 3.6) + 0.02, DECK_V, 4.42, "FP_InteriorDark")
    cw, ch = SIZE["cb"]
    for k, (v0, v1) in enumerate(((3.50, 3.84), (3.92, 4.26))):
        x = x_in + 0.002
        q = [W(u1, v0, x), W(u0, v0, x), W(u0, v1, x), W(u1, v1, x)]
        uv = [uv_of("cb", 0.02 + 0.2 * k, 0.0), uv_of("cb", 0.02 + 0.2 * k + (u1 - u0), 0.0), uv_of("cb", 0.02 + 0.2 * k + (u1 - u0), ch),
              uv_of("cb", 0.02 + 0.2 * k, ch)]
        g.oriented([tuple(p) for p in q], (1, 0, 0), "FP_InteriorPanel", uv=uv)
    g.box(tuple(W(0.5 * (u0 + u1), 4.30, x_in + 0.10)), (0.20, 0.02, u1 - u0 - 0.04), "FP_InteriorTrim")       # 棚の上の灯の器具
    # 後ろの壁（操縦席の側、出入り口の左）：消火器・斧・懐中電灯
    ub = C.STEPS_U[0] - 0.09 - 0.005
    ex = W(ub - 0.10, DECK_V + 0.45, -1.02)
    g.lathe(tuple(ex), (0, 1, 0), [(0.0, 0.0), (0.0, 0.07), (0.40, 0.07), (0.44, 0.05), (0.46, 0.02)], "FP_InteriorRed", n=16, cap0="flat")
    g.tube(tuple(ex + Vector((0, 0.46, 0))), tuple(ex + Vector((0, 0.52, 0))), 0.015, "FP_KnobBlack", n=8)
    g.box(tuple(ex + Vector((0, 0.53, 0.0))), (0.10, 0.015, 0.025), "FP_KnobBlack")
    FI.strip_box(g, ub - 0.02, ub, -1.12, -0.92, DECK_V + 0.55, DECK_V + 0.60, "FP_InteriorMetal")
    ax = W(ub - 0.03, DECK_V + 0.95, -1.15)
    g.box(tuple(ax), (0.035, 0.42, 0.03), "FP_InteriorRed")
    g.box(tuple(ax + Vector((0.0, 0.21, 0.0))), (0.12, 0.05, 0.014), "FP_InteriorMetal")
    fl = W(ub - 0.04, DECK_V + 1.25, -0.92)
    g.tube(tuple(fl), tuple(fl + Vector((0, 0.22, 0))), 0.022, "FP_KnobBlack", n=10)
    g.lathe(tuple(fl + Vector((0, 0.22, 0))), (0, 1, 0), [(0.0, 0.032), (0.04, 0.032), (0.04, 0.0)], "FP_KnobBlack", n=12)


def build_floor(g: GMesh):
    d0, d1 = C.FLIGHT_DECK_U
    us = [d0 + (d1 - d0) * i / 10 for i in range(11)]
    left, right = [], []
    for u in us:
        x = FI.wall_x(u, DECK_V) + 0.02
        right.append(W(u, DECK_V, x))
        left.append(W(u, DECK_V, -x))
    for i in range(len(us) - 1):
        q = [left[i], right[i], right[i + 1], left[i + 1]]
        g.oriented([tuple(p) for p in q], (0, 1, 0), "FP_InteriorTread", uv=[(p.x / 0.30, p.z / 0.30) for p in q])
    # 足もとのゴムのマット
    FI.strip_box(g, 0.95, 1.55, -0.55, 0.55, DECK_V, DECK_V + 0.008, "FP_Rubber")


def build_cockpit():
    g = GMesh()
    build_floor(g)
    build_dash(g)
    build_glareshield(g)
    build_yoke(g)
    build_pedals(g)
    build_seat(g)
    build_consoles(g)
    build_overhead(g)
    build_window_trims(g)
    build_sills(g)
    build_walls(g)
    # 操縦席の灯：器具は天井の両わき（ハテナの「？」の上をよける）、光は前と同じ真ん中の u 2.1
    for sx in (-1, 1):
        x = sx * 0.62
        lv = FI.roof_v(1.95, x)
        FI.strip_box(g, 1.85, 2.05, x - 0.11, x + 0.11, lv - 0.05, lv + 0.02, "FP_InteriorDark")
        FI.strip_box(g, 1.87, 2.03, x - 0.085, x + 0.085, lv - 0.055, lv - 0.045, "FP_InteriorLamp")
    lt = S.inner_section(2.1)["top"]
    p = W(2.1, lt - 0.10, 0.0)
    FI.LIGHTS.append({"kind": "cockpit", "position": [round(p.x, 4), round(p.y, 4), round(p.z, 4)], "direction": [0, -1, 0]})
    return g

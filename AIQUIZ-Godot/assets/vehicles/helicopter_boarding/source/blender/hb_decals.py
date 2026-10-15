"""デカール（ロゴ・機体番号・紋章・細い線・黄黒の帯・吊り上げの印・計器盤の銘板）を、外板の面に貼る。

貼り方：外板（GMesh）の三角形を「チャート」（面の上の 2D の座標）へ写し、デカールの形（凸の多角形）で切り抜いて、
頂点の法線（なめらかな面の法線）の向きに少し浮かせる。切り抜いた形は外板の三角形の中にあるので、
平らな面の折れ目でも沈まない。UV はチャートの座標からアトラス（hb_textures）の四角へ。
デカールの形が外板で覆いきれない（面積が 97 % に足りない）ときは DecalMiss で止める（書き出す前に気づく）。

座標は Godot（x 右、y 上は地面から、機首 -z）。読むデカール（ロゴ・番号・紋章）は、見る人の右が U：
左の横（-x を向く面）は U = +z、右の横は U = -z。V = N × U（外から見て左右が逆にならない）。
"""
from __future__ import annotations

import math

from mathutils import Vector
from mathutils.bvhtree import BVHTree

import hb_common as K
import hb_textures as T
from hb_common import NAVY, SPEC, GMesh, belly_y

WHITE = (1.0, 1.0, 1.0, 1.0)
TRIM_WHITE = WHITE
MIN_COVER = 0.97
STATS: dict = {}


class DecalMiss(RuntimeError):
    pass


class Hull:
    """GMesh（Blender の座標）の面のうち、材質が mats（と溶接の名前が welds）のものを、Godot の座標の三角形で持つ。
    頂点の法線は、その GMesh の全部の面の法線（面積の重み）の平均。溶接した点は面どうしで共有するので、なめらかな陰影の法線と同じ。
    keep(中心, 法線) で面を選ぶ。all_bvh は選ぶ前の全部の面（すき間の測定に使う）。"""

    def __init__(self, sources, mats, keep=None, welds=None):
        self.tris = []
        all_v, all_f = [], []
        for gm in sources:
            vg = [K.G(v) for v in gm.v]
            acc = [Vector() for _ in vg]
            fns = []
            for f in gm.f:
                n = K._newell([vg[i] for i in f])
                fns.append(n)
                for i in f:
                    acc[i] += n
            vn = [a.normalized() if a.length > 1e-12 else Vector((0.0, 0.0, 1.0)) for a in acc]
            base = len(all_v)
            all_v += vg
            for f in gm.f:
                for k in range(1, len(f) - 1):
                    all_f.append((base + f[0], base + f[k], base + f[k + 1]))
            for f, mat, n, w in zip(gm.f, gm.mat, fns, gm.weld_of):
                if mat not in mats or n.length < 1e-12:
                    continue
                if welds is not None and w not in welds:
                    continue
                pts = [vg[i] for i in f]
                c = sum(pts, Vector()) / len(pts)
                nn = n.normalized()
                if keep is not None and not keep(c, nn):
                    continue
                for k in range(1, len(f) - 1):
                    ids = (f[0], f[k], f[k + 1])
                    self.tris.append(([vg[i] for i in ids], [vn[i] for i in ids]))
        self.all_bvh = BVHTree.FromPolygons(all_v, all_f, all_triangles=True) if all_f else None
        kv = [p for pts, _ in self.tris for p in pts]
        self.out_bvh = BVHTree.FromPolygons(kv, [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(self.tris))], all_triangles=True) if self.tris else None


# ---------------------------------------------------------------- 切り抜き

def _clip(poly, planes):
    """凸の切り抜き（Sutherland–Hodgman）。poly の点は (s, t, wa, wb, wc)、planes は (a, b, d)：a s + b t ≤ d が内側。"""
    for a, b, d in planes:
        if len(poly) < 3:
            return []
        out = []
        n = len(poly)
        for i in range(n):
            P_, Q = poly[i], poly[(i + 1) % n]
            fp = a * P_[0] + b * P_[1] - d
            fq = a * Q[0] + b * Q[1] - d
            if fp <= 0.0:
                out.append(P_)
            if (fp <= 0.0) != (fq <= 0.0):
                t = fp / (fp - fq)
                out.append(tuple(p + (q - p) * t for p, q in zip(P_, Q)))
        poly = out
    return poly


def _area2(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))


def rect_planes(s0, t0, s1, t1):
    return [(-1.0, 0.0, -s0), (1.0, 0.0, s1), (0.0, -1.0, -t0), (0.0, 1.0, t1)]


def poly_planes(pts):
    """反時計回りの凸の多角形（s, t）の辺の半平面。"""
    out = []
    for i in range(len(pts)):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
        a, b = (y1 - y0), -(x1 - x0)          # 外向きの法線（反時計回りなら右側が外）
        out.append((a, b, a * x0 + b * y0))
    return out


def project(m, hull, chart, regions, mat, offset, weld, col=WHITE):
    """hull の三角形を chart で 2D にし、regions [(planes, (s0, t0, s1, t1), uv_fn)] のそれぞれで切り抜いて m へ足す。
    返り値：切り抜いた面積（チャートの上）と、作った面の数。"""
    tris = []
    for pts, nors in hull.tris:
        st = [chart(p) for p in pts]
        if any(q is None for q in st):
            continue
        ss = [q[0] for q in st]
        ts = [q[1] for q in st]
        tris.append((pts, nors, st, (min(ss), min(ts), max(ss), max(ts))))
    area = 0.0
    faces = 0
    for planes, (s0, t0, s1, t1), uv_fn in regions:
        for (A, B, C), (na, nb, nc), st, bb in tris:
            if bb[2] < s0 or bb[0] > s1 or bb[3] < t0 or bb[1] > t1:
                continue
            poly = [(st[0][0], st[0][1], 1.0, 0.0, 0.0), (st[1][0], st[1][1], 0.0, 1.0, 0.0), (st[2][0], st[2][1], 0.0, 0.0, 1.0)]
            poly = _clip(poly, planes)
            if len(poly) < 3:
                continue
            a2 = abs(_area2(poly))
            if a2 < 1e-9:
                continue
            pts, uvs = [], []
            for s, t, wa, wb, wc in poly:
                p = A * wa + B * wb + C * wc
                n = (na * wa + nb * wb + nc * wc).normalized()
                q = p + n * offset
                if pts and (q - Vector(pts[-1])).length < 1e-6:
                    continue
                pts.append(tuple(q))
                uvs.append(uv_fn(s, t))
            if len(pts) >= 3 and (Vector(pts[0]) - Vector(pts[-1])).length < 1e-6:
                pts.pop()
                uvs.pop()
            if len(pts) < 3:
                continue
            m.face(pts, mat, smooth=weld is not None, weld=weld, uv=uvs, col=col)
            area += a2
            faces += 1
    return area, faces


def clearance(m, hulls):
    """m の頂点と、外板（hulls の全部の面）のいちばん近い距離（mm）。外側にない点の数も
    （表か裏かは、貼った面（表の材質）だけで見る。ドアの継ぎ目の縁の面で間違えない）。"""
    lo, hi, inside = 9e9, 0.0, 0
    for v in m.v:
        p = K.G(v)
        best, side = None, None
        for h in hulls:
            if h.all_bvh is None:
                continue
            loc, nor, _, dist = h.all_bvh.find_nearest(p, 0.05)
            if loc is not None and (best is None or dist < best):
                best = dist
            if h.out_bvh is not None:
                loc, nor, _, dist = h.out_bvh.find_nearest(p, 0.02)
                if loc is not None and (side is None or dist < side[0]):
                    side = (dist, (p - loc).dot(nor))
        if best is None:
            continue
        if side is not None and side[1] < 0:
            inside += 1
        lo, hi = min(lo, best), max(hi, best)
    return {"min_mm": round(lo * 1000, 2) if lo < 9e9 else None, "max_mm": round(hi * 1000, 2), "inside": inside}


def _record(name, m, hulls, area, want, faces):
    cover = area / want if want > 0 else 0.0
    st = {"faces": faces, "cover": round(cover, 4), **clearance(m, hulls)}
    STATS[name] = st
    if faces == 0 or cover < MIN_COVER:
        raise DecalMiss(f"{name}：外板で覆いきれない（{st}）")
    return st


def _planar(c, N, U):
    """平らなチャート：中心 c、外向き N、右 U（N に直交させる）。返り値：chart(p) → (s, t)。"""
    N = Vector(N).normalized()
    U = Vector(U)
    U = (U - N * U.dot(N)).normalized()
    V = N.cross(U)
    c = Vector(c)

    def chart(p):
        d = p - c
        if abs(d.dot(N)) > 0.25:
            return None
        return (d.dot(U), d.dot(V))
    return chart


def _uv_box(name, s0, t0, s1, t1, inset=2.0):
    u0, v0, u1, v1 = T.uv_rect(name, inset, inset)

    def uv(s, t):
        return (u0 + (s - s0) / (s1 - s0) * (u1 - u0), v0 + (t - t0) / (t1 - t0) * (v1 - v0))
    return uv


def _aspect(name):
    x, y, w, h = T.REGIONS[name]
    return w / h


# ---------------------------------------------------------------- D1 尾の筒のロゴ

LOGO_LETTER_H = 0.22          # 字の高さ（m）
BOOM_LOGO_Z = 3.45


def _boom_theta(p):
    from hb_parts import boom_params
    b = boom_params(p.z)
    c = p.x / b["a"]
    if p.y >= b["belt"]:
        s, n = (p.y - b["belt"]) / (b["top"] - b["belt"]), b["n_top"]
    else:
        s, n = (p.y - b["belt"]) / (b["belt"] - b["bottom"]), b["n_bot"]
    C = math.copysign(min(abs(c), 1.0) ** (n / 2), c)
    S = math.copysign(min(abs(s), 1.0) ** (n / 2), s)
    return math.atan2(S, C)


def _boom_arc(z, th0, th1, steps=48):
    from hb_parts import boom_params
    from hb_common import section_point
    b = boom_params(z)
    acc = 0.0
    prev = section_point(b, th0)
    for i in range(1, steps + 1):
        cur = section_point(b, th0 + (th1 - th0) * i / steps)
        acc += math.hypot(cur[0] - prev[0], cur[1] - prev[1])
        prev = cur
    return acc if th1 >= th0 else -acc


def build_boom_logo(tail):
    out = GMesh()
    h = LOGO_LETTER_H * T.REGIONS["LOGO_KEY"][3] / (T.REGIONS["LOGO_KEY"][3] - 24)
    w = h * _aspect("LOGO_KEY")
    want = 0.0
    total = 0.0
    faces = 0
    for side in (-1, 1):
        th_c = 0.0 if side > 0 else math.pi
        hull = Hull([tail], {"BodyPaint"}, keep=lambda c, n, s=side: n.x * s > 0.2 and 2.6 < c.z < 4.4, welds={"Body:boom"})

        def chart(p, side=side, th_c=th_c):
            th = _boom_theta(p)
            d = (th - th_c + math.pi) % (2 * math.pi) - math.pi
            if abs(d) > 1.2:
                return None
            arc = _boom_arc(p.z, th_c, th_c + d)
            # 右（+x）：U = -z、上へ θ が増える。左（-x）：U = +z、上へ θ が減る
            return ((-(p.z - BOOM_LOGO_Z)) if side > 0 else (p.z - BOOM_LOGO_Z), arc if side > 0 else -arc)

        reg = (rect_planes(-w / 2, -h / 2, w / 2, h / 2), (-w / 2, -h / 2, w / 2, h / 2), _uv_box("LOGO_KEY", -w / 2, -h / 2, w / 2, h / 2))
        a, f = project(out, hull, chart, [reg], "Decal", 0.005, "decal:boomlogo")
        total += a
        faces += f
        want += w * h
        hulls = [hull]
    _record("D1_boom_logo", out, hulls, total, want, faces)
    STATS["D1_boom_logo"]["size_m"] = [round(w, 3), round(h, 3)]
    return out


# ---------------------------------------------------------------- D2 腹のロゴ・D7 床下ハッチのまわりの黄黒の帯

BELLY_LOGO = {"z": -1.15, "width": 1.40}
HAZARD_BAND = {"outer_x": 0.81, "inner_x": 0.71, "z_out": (-0.36, 1.16), "z_in": (-0.26, 1.06), "tile": 0.20}


def _belly_hull(body_shell):
    return Hull([body_shell], {"BodyAccent"}, keep=lambda c, n: n.y < -0.3 and abs(c.x) < 1.2)


def build_belly(body_shell):
    hull = _belly_hull(body_shell)
    zc = BELLY_LOGO["z"]
    chart = _planar((0.0, belly_y(zc), zc), (0, -1, 0), (1, 0, 0))     # U = +x、V = +z（字の上は尾の方。後ろの下から読める）
    w = BELLY_LOGO["width"]
    h = w / _aspect("LOGO_MASK")
    logo = GMesh()
    reg = (rect_planes(-w / 2, -h / 2, w / 2, h / 2), (-w / 2, -h / 2, w / 2, h / 2), _uv_box("LOGO_MASK", -w / 2, -h / 2, w / 2, h / 2))
    a, f = project(logo, hull, chart, [reg], "Decal", 0.004, "decal:bellylogo")
    _record("D2_belly_logo", logo, [hull], a, w * h, f)
    # 黄黒の帯：前後は横いっぱい、左右はそのあいだ。タイル（0.20 × 0.10 m）ごとに切る
    hz = HAZARD_BAND
    chart0 = _planar((0.0, belly_y(0.4), 0.0), (0, -1, 0), (1, 0, 0))   # s = x、t = z
    u0, v0, u1, v1 = T.uv_rect("HAZARD", 0.0, 2.0)
    L = hz["tile"]
    regions = []
    want = 0.0

    def tiles(a0, a1, b0, b1, along_s):
        nonlocal want
        n = int(math.ceil((a1 - a0) / L - 1e-6))
        for k in range(n):
            s0 = a0 + k * L
            s1 = min(a0 + (k + 1) * L, a1)
            if along_s:
                box = (s0, b0, s1, b1)

                def uv(s, t, s0=s0, b0=b0, b1=b1):
                    return (u0 + (s - s0) / L * (u1 - u0), v0 + (t - b0) / (b1 - b0) * (v1 - v0))
            else:
                box = (b0, s0, b1, s1)

                def uv(s, t, s0=s0, b0=b0, b1=b1):
                    return (u0 + (t - s0) / L * (u1 - u0), v0 + (s - b0) / (b1 - b0) * (v1 - v0))
            regions.append((rect_planes(*box), box, uv))
            want += (box[2] - box[0]) * (box[3] - box[1])

    ox, ix = hz["outer_x"], hz["inner_x"]
    tiles(-ox, ox, hz["z_out"][0], hz["z_in"][0], True)
    tiles(-ox, ox, hz["z_in"][1], hz["z_out"][1], True)
    tiles(hz["z_in"][0], hz["z_in"][1], -ox, -ix, False)
    tiles(hz["z_in"][0], hz["z_in"][1], ix, ox, False)
    band = GMesh()
    a, f = project(band, hull, chart0, regions, "Decal", 0.004, "decal:hazard")
    _record("D7_hatch_hazard", band, [hull], a, want, f)
    logo.extend(band)
    return logo


# ---------------------------------------------------------------- D3 尾翼の機体番号

def build_fin_number(tail):
    from hb_parts import FIN_NUMBER_BOX
    box = FIN_NUMBER_BOX
    z0, z1 = box["z"][0] + 0.01, box["z"][1] - 0.01
    y0, y1 = box["y"][0] + 0.005, box["y"][1] - 0.005
    w, h = z1 - z0, y1 - y0
    out = GMesh()
    total, want, faces = 0.0, 0.0, 0
    hull = None
    for side in (-1, 1):
        hull = Hull([tail], {"BodyAccent"}, keep=lambda c, n, s=side: n.x * s > 0.3 and 6.2 < c.z < 7.1 and 3.9 < c.y < 4.5, welds={"Body:ufin:BodyAccent"})
        U = (0, 0, 1) if side < 0 else (0, 0, -1)
        chart = _planar((side * box["x"], (y0 + y1) / 2, (z0 + z1) / 2), (side, 0, 0), U)
        reg = (rect_planes(-w / 2, -h / 2, w / 2, h / 2), (-w / 2, -h / 2, w / 2, h / 2), _uv_box("NUM_0", -w / 2, -h / 2, w / 2, h / 2))
        a, f = project(out, hull, chart, [reg], "DecalNumber", 0.003, "decal:number")
        total += a
        want += w * h
        faces += f
    _record("D3_fin_number", out, [hull], total, want, faces)
    return out


# ---------------------------------------------------------------- D4 ドアの紋章

EMBLEM = {"y": 1.015, "z": -1.40, "d": 0.40}


def build_door_emblem(door_shell, side):
    from hb_parts import side_surface
    s = -1 if side == "L" else 1
    p, n = side_surface(EMBLEM["y"], EMBLEM["z"], s)
    hull = Hull([door_shell], {"BodyAccent"}, keep=lambda c, nn: nn.dot(n) > 0.3)
    chart = _planar(p, n, (0, 0, 1) if s < 0 else (0, 0, -1))
    r = EMBLEM["d"] / 2
    m = GMesh()
    reg = (rect_planes(-r, -r, r, r), (-r, -r, r, r), _uv_box("EMBLEM", -r, -r, r, r))
    a, f = project(m, hull, chart, [reg], "Decal", 0.004, f"decal:emblem{side}")
    _record(f"D4_emblem_{side}", m, [hull], a, 4 * r * r, f)
    return m


# ---------------------------------------------------------------- D5 / D6 細い線（白い帯の上下）

PIN = {"upper_y": 1.486, "lower_y": 1.245, "w": 0.022, "w_nose": 0.008, "gap": 0.035, "gap_nose": 0.012, "taper": (-2.70, -3.14), "geo": 2.3}


def pin_center(which, z):
    """細い線のまん中の高さと、見える幅。上の線は機首へ向けて帯へ寄り、細くなる（風防の下の線から 2 cm 以上離す）。"""
    bot, top = SPEC["stripe_y"]
    if which == "lower":
        return PIN["lower_y"], PIN["w"]
    k = K.smoothstep(PIN["taper"][0], PIN["taper"][1], z)
    w = PIN["w"] + (PIN["w_nose"] - PIN["w"]) * k
    gap = PIN["gap"] + (PIN["gap_nose"] - PIN["gap"]) * k
    return top + gap + w / 2, w


def pin_z_end(which, stripe_z_end):
    """後ろの端：白い帯の終わり（ステーション）か、胴体の下面が線の 5 cm 下まで上がる所の手前。"""
    from hb_common import body_params
    y, _ = pin_center(which, 0.0)
    z = stripe_z_end
    zz = 0.0
    while zz < stripe_z_end:
        if body_params(zz)["bottom"] >= y - 0.05:
            return min(z, zz - 0.02)
        zz += 0.01
    return z


def build_pinstripes(shell, shell_stats):
    """左右・上下の 4 本。ドアの上の部分はドア（Door_L / Door_R）に入れる。返り値：{部品名: GMesh}。"""
    import hb_shell
    zs_all = hb_shell.stations()
    z_nose = zs_all[0]
    stripe_end = shell_stats.get("stripe_z_end", 1.6)
    out = {"Body": GMesh(), "Door_L": GMesh(), "Door_R": GMesh()}
    pu = T.uv_center("PIN")[0]
    _, pv0, _, pv1 = T.uv_rect("PIN", 2.0, 2.0)
    mats = {"BodyPaint", "BodyAccent", "Trim"}
    for which, col in (("upper", NAVY), ("lower", WHITE)):
        z_end = pin_z_end(which, stripe_end)
        zs = [z for z in zs_all if z <= z_end + 1e-9]
        if zs[-1] < z_end - 1e-6:
            zs.append(z_end)
        rows = []
        for z in zs:
            yc, w = pin_center(which, z)
            hg = PIN["geo"] * w / 2
            rows.append((z, yc - hg, yc + hg))
        regions = []
        want = 0.0
        for (za, la, ha), (zb, lb, hb) in zip(rows[:-1], rows[1:]):
            gl = (lb - la) / (zb - za)
            gh = (hb - ha) / (zb - za)
            planes = [(-1.0, 0.0, -za), (1.0, 0.0, zb), (gl, -1.0, -(la - gl * za)), (-gh, 1.0, ha - gh * za)]

            def uv(s, t, za=za, la=la, ha=ha, gl=gl, gh=gh):
                lo = la + (s - za) * gl
                hi = ha + (s - za) * gh
                return (pu, pv0 + (t - lo) / max(hi - lo, 1e-9) * (pv1 - pv0))
            regions.append((planes, (za, min(la, lb), zb, max(ha, hb)), uv))
            want += (zb - za) * ((ha - la) + (hb - lb)) / 2
        for side in (-1, 1):
            tag = "L" if side < 0 else "R"
            got, faces = 0.0, 0
            hulls = []
            mine = GMesh()
            for obj, gm in (("Body", shell["Body"]), (f"Door_{tag}", shell[f"Door_{tag}"])):
                hull = Hull([gm], mats, keep=lambda c, n, s=side: c.x * s > 0.0 and abs(n.x) > 0.02)
                hulls.append(hull)
                piece = GMesh()
                a, f = project(piece, hull, lambda p: (p.z, p.y), regions, "Decal", 0.004, f"decal:pin_{which}{tag}", col=col)
                if obj == "Body":
                    # 機首の先：輪 0 の線の幅から、先の一点（白い帯の V の先）へ細くなる三角
                    tip = _pin_tip(piece, which, side, z_nose, col, pu, pv0, pv1)
                got += a
                faces += f
                out[obj].extend(piece)
                mine.extend(piece)
            st = _record(f"D{5 if which == 'upper' else 6}_pin_{which}_{tag}", mine, hulls, got, want, faces)
            st["z_end"] = round(z_end, 3)
            st["tip"] = tip
    return out


def _pin_tip(m, which, side, z0, col, pu, pv0, pv1):
    import hb_shell
    ring, _ = hb_shell.full_ring(z0)
    c = Vector((0.0, (max(p[1] for p in ring) + min(p[1] for p in ring)) / 2, z0 - 0.04))
    yc, w = pin_center(which, z0)
    hg = PIN["geo"] * w / 2
    half = ring[:hb_shell.HALF + 1] if side < 0 else [ring[0]] + list(reversed(ring[hb_shell.HALF:]))

    def at_y(y):
        for a, b in zip(half[:-1], half[1:]):
            if (a[1] - y) * (b[1] - y) <= 0 and abs(a[1] - b[1]) > 1e-9:
                t = (y - a[1]) / (b[1] - a[1])
                return Vector(a) + (Vector(b) - Vector(a)) * t
        return None

    lo, hi = at_y(yc - hg), at_y(yc + hg)
    if lo is None or hi is None:
        return "skip"
    n = K._newell([lo, hi, c])
    out_dir = Vector((side * 0.5, 0.0, -1.0))
    if n.dot(out_dir) < 0:
        n = -n
        pts, uvs = [hi, lo, c], [(pu, pv1), (pu, pv0), (pu, (pv0 + pv1) / 2)]
    else:
        pts, uvs = [lo, hi, c], [(pu, pv0), (pu, pv1), (pu, (pv0 + pv1) / 2)]
    n.normalize()
    m.face([tuple(p + n * 0.004) for p in pts], "Decal", smooth=False, uv=uvs, col=col)
    return [round(v, 3) for v in lo] + [round(v, 3) for v in hi]


# ---------------------------------------------------------------- 吊り上げの印（形、白）と、計器盤の銘板

LIFT_MARKS = [(1.41, 0.70, -1.40), (1.34, 0.70, 0.62)]


def build_lift_marks(body_shell):
    from hb_parts import side_surface
    m = GMesh()
    for x, y, z in LIFT_MARKS:
        for s in (-1, 1):
            p, n = side_surface(y, z, s)
            hull = Hull([body_shell], {"BodyAccent"}, keep=lambda c, nn, n=n: nn.dot(n) > 0.5 and (c - p).length < 0.5)
            chart = _planar(p, n, (0, 0, 1) if s < 0 else (0, 0, -1))
            tri = [(-0.035, 0.022), (0.0, -0.038), (0.035, 0.022)]          # ▼（反時計回り）
            reg = (poly_planes(tri), (-0.035, -0.038, 0.035, 0.022), lambda a, b: (0.5, 0.5))
            a, f = project(m, hull, chart, [reg], "Trim", 0.004, None, col=TRIM_WHITE)
            if f == 0:
                raise DecalMiss(f"吊り上げの印 {x, y, z} が外板に当たらない")
    STATS["lift_marks"] = {"count": 2 * len(LIFT_MARKS)}
    return m


def build_nameplate():
    """計器盤の前の面（風防越しに見える）の白い銘板に、AIQUIZ のロゴ。前から見て右は -x。"""
    m = GMesh()
    z = -2.698
    x, y0, y1 = 0.11, 1.6075, 1.6625
    u0, v0, u1, v1 = T.uv_rect("LOGO_KEY")
    m._oriented([(x, y0, z), (-x, y0, z), (-x, y1, z), (x, y1, z)], (0, 0, -1), "Decal",
                uv=[(u0, v0), (u1, v0), (u1, v1), (u0, v1)], col=WHITE)
    STATS["nameplate"] = {"faces": 1}
    return m


# ---------------------------------------------------------------- まとめ

def build_decals(src, shell_stats):
    """src：{"Body": 胴体の殻, "Door_L", "Door_R": ドアの殻, "tail": 尾}（どれも GMesh）。
    返り値：{部品名: [(GMesh, tag)]}（tag は decal / decal_pin）。"""
    STATS.clear()
    out: dict[str, list] = {}

    def put(name, gm, tag="decal"):
        out.setdefault(name, []).append((gm, tag))

    put("Body", build_boom_logo(src["tail"]))
    put("Body", build_belly(src["Body"]))
    put("Body", build_fin_number(src["tail"]))
    put("Body", build_lift_marks(src["Body"]), "kit")
    for side in ("L", "R"):
        put(f"Door_{side}", build_door_emblem(src[f"Door_{side}"], side))
    for name, gm in build_pinstripes(src, shell_stats).items():
        put(name, gm, "decal_pin")
    put("Interior", build_nameplate(), "interior")
    return out, dict(STATS)

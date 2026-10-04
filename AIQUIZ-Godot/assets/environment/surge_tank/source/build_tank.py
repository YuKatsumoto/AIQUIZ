"""Geometry of the surge tank modules (LIVE Blender only; the survey numbers are in tank_common.py).

    ns = {"__name__": "tank_build"}
    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/build_tank.py", encoding="utf-8").read(), ns)
    ns["clear_old"]()              # once: remove the first (grid guess) build
    ns["build_module"]("K04")      # K00..K10, P, S, Q, T

Every module is unique and authored in hall (Godot) coordinates at the origin (x = -v, z = 132.8 - u):
  K<k>  pillar line k (u_k = 20.8 + 14 k), u_k - 6 .. u_k + 8: the coffers between the pillar-head beams with
        a pendant high-bay in the middle of every coffer of the line (the free rows |v| <= 21, i.e. midway
        between two pillars of the same row), the pillars of the line, the transverse beam on its shaft side,
        the trench floor, 60 deg slopes, shelves, wall fillets, side walls (chamfered in K10), catwalks, floods.
  P     pump end, u 0 .. 14.8: gate face, five dividing walls with round tips (v = 0, +-14, +-28), the four
        intake channels behind the gate face ("altars"), a pendant lamp over each channel, the transverse
        beam before line 0.
  S     shaft-side end, u 168.8 ..: the last coffer, the end wall (u = 171.4) with two 10 m openings and the
        2 x 8 m pier, the passage to shaft No.1 with chamfered jamb feet, fence, concrete blocks, lamps.
  Q     shaft No.1: wall (cut where the passage enters), roof with daylight, stair tower, pipes, ring catwalk.
  T     visitor access: door portal in the +v side wall, walkway over the shelf, steel stair into the trench,
        green exit light, bollards at the end of the visitor area.

Each module = one object per material ("<TAG>|TK_Concrete", ...). Light fixtures carry lens meshes (TK_Lens)
and LGT_ lights for the Cycles bake; empties <TAG>|TK_Light_<Kind>_<name> record them for Godot (local -Z = beam).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/tank_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)
GAcc = C.GAcc
V = C.V

MATS = ("TK_Concrete", "TK_Pillar", "TK_Floor", "TK_Steel", "TK_Galv", "TK_Grate", "TK_Lens", "TK_Void", "TK_Sky", "TK_Paint")
PART = {"TK_Concrete": "shell", "TK_Pillar": "shell", "TK_Floor": "floor", "TK_Steel": "steel", "TK_Galv": "galv", "TK_Grate": "grate",
        "TK_Lens": "lens", "TK_Void": "dark", "TK_Sky": "dark", "TK_Paint": "steel"}
HALF_LINE = C.LINE_PITCH * 0.5          # 7.0
# Lamps (official photo, measured against the plan): one pendant LED high-bay in the middle of every coffer, i.e.
# at the free rows of each pillar line (|v| <= 21) and at the line's u, lens 14.84 m over the trench floor.
TB_HALF = C.TB_W * 0.5                  # 1.0
HEAD_HZ = HALF_LINE - TB_HALF           # 6.0: a pillar head reaches the faces of both transverse beams
LAMP_Y = C.BEAM_Y - 0.66                # lens of the hanging high-bay
HAUNCH_Y = C.H - C.HAUNCH               # beam sides / walls meet the 45 deg haunches under the slab
Y5 = C.SHELF_Y
PASSAGE_CHAMFER = (2.4, 4.2)            # jamb feet of the passage to shaft No.1 (across, up)
PASSAGE_PIER_LEN = 8.0


def P(v, y, u):
    """Plan point (v across, y up, u from the pump gate face) -> Godot point."""
    return Vector((-v, y, C.z_of(u)))


def shaft_u(v):
    """u of the inner face of shaft No.1 on the tank side at v (|v| <= R)."""
    return C.SHAFT_CENTRE_U - math.sqrt(max(0.0, C.SHAFT_R ** 2 - v * v))


# ------------------------------------------------------------------ materials (bake look-dev placeholders)
def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
    return m


def mats():
    return {n: material(n) for n in MATS}


class Mod:
    """The per-material accumulators of one module."""

    def __init__(self, tag):
        self.tag = tag
        self.acc = {
            "TK_Concrete": GAcc(scale=C.S_CONCRETE),
            "TK_Pillar": GAcc(scale=C.S_CONCRETE),
            "TK_Floor": GAcc(scale=C.S_FLOOR),
            "TK_Steel": GAcc(scale=C.S_STEEL, color=C.TINT["fixture"] + (1.0,)),
            "TK_Paint": GAcc(scale=C.S_STEEL, color=C.TINT["green"] + (1.0,)),
            "TK_Galv": GAcc(scale=C.S_GALV),
            "TK_Grate": GAcc(scale=C.S_GRATE),
            "TK_Lens": GAcc(scale=1.0),
            "TK_Void": GAcc(scale=1.0),
            "TK_Sky": GAcc(scale=1.0),
        }
        self.lights = []      # (kind, pos_g, aim_g, params)

    def __getitem__(self, key):
        return self.acc[key]


def face_to(acc, pts, ref, **kw):
    """Face whose normal points toward the Godot point ref (seen from the face centre)."""
    pts = [Vector(p) for p in pts]
    f = acc.face(pts, **kw)
    mid = sum(pts, Vector()) / len(pts)
    acc.orient(f, Vector(ref) - mid)
    return f


def abox(acc, a, b, **kw):
    """Axis-aligned box between two Godot points (any corner order)."""
    acc.box((min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)), (max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)), **kw)


# ------------------------------------------------------------------ outlines and lofts
def rrect(cv, cu, hv, hu, rc, nc=8):
    """Rounded rectangle in plan (v, u): 4 corner arcs of nc segments -> 4 * (nc + 1) points; the same count
    for every size, so outlines loft into each other."""
    rc = min(rc, hv, hu)
    pts = []
    corners = ((hv - rc, hu - rc, 0.0), (-(hv - rc), hu - rc, 0.5 * math.pi), (-(hv - rc), -(hu - rc), math.pi), (hv - rc, -(hu - rc), 1.5 * math.pi))
    for (ov, ou, a0) in corners:
        for i in range(nc + 1):
            a = a0 + 0.5 * math.pi * i / nc
            pts.append((cv + ov + rc * math.cos(a), cu + ou + rc * math.sin(a)))
    return pts


def ring_at(outline, y):
    return [P(v, y, u) for (v, u) in outline]


def perimeter_u(outline, scale, u0=0.0):
    us = [u0]
    for i in range(1, len(outline) + 1):
        a = outline[i - 1]
        b = outline[i % len(outline)]
        us.append(us[-1] + math.hypot(b[0] - a[0], b[1] - a[1]) / scale)
    return us


def loft(acc, rings, us, vs, centre_fn, smooth=True):
    """Skin closed rings (equal counts) with explicit UVs: us per outline point (n + 1), vs per ring."""
    n = len(rings[0])
    for r in range(len(rings) - 1):
        ra, rb = rings[r], rings[r + 1]
        for i in range(n):
            j = (i + 1) % n
            pts = (ra[i], ra[j], rb[j], rb[i])
            uv = ((us[i], vs[r]), (us[i + 1], vs[r]), (us[i + 1], vs[r + 1]), (us[i], vs[r + 1]))
            if (pts[0] - pts[1]).length < 1e-6 and (pts[2] - pts[3]).length < 1e-6:
                continue
            if (pts[0] - pts[1]).length < 1e-6:
                pts, uv = (ra[i], rb[j], rb[i]), (uv[0], uv[2], uv[3])
            elif (pts[2] - pts[3]).length < 1e-6:
                pts, uv = (ra[i], ra[j], rb[j]), (uv[0], uv[1], uv[2])
            f = acc.face(pts, smooth=smooth, uv=uv)
            mid = sum(pts, Vector()) / len(pts)
            acc.orient(f, mid - centre_fn(mid))


# ------------------------------------------------------------------ pillar
def pillar(m, v, u, y0=0.0):
    """7 x 2 m pillar with half-round ends standing at y0 (trench floor 0 or shelf 5): base flare, shaft, head
    flaring into its 4 m pillar-head beam, which spans u +- 6 to the faces of the transverse beams at BEAM_Y.
    A pillar on a shelf gets a 1 m skirt below the shelf so its flare meets the slope where it overhangs it."""
    acc = m["TK_Pillar"]
    nc = 8
    base = rrect(v, u, C.PIL_R + C.FLARE_OUT, C.PIL_HALF_LEN + C.FLARE_OUT, C.PIL_R + C.FLARE_OUT - 1e-4, nc)
    shaft = rrect(v, u, C.PIL_R, C.PIL_HALF_LEN, C.PIL_R - 1e-4, nc)
    head = rrect(v, u, C.LB_HALF_W, HEAD_HZ, 0.05, nc)
    ys = [y0, y0 + C.FLARE_LIP, y0 + C.FLARE_Y, C.PIL_HEAD_Y, C.BEAM_Y]
    outlines = [base, base, shaft, shaft, head]
    if y0 > 0.0:
        ys = [y0 - 1.0] + ys
        outlines = [base] + outlines
    rings = [ring_at(o, y) for (o, y) in zip(outlines, ys)]
    us = perimeter_u(shaft, C.S_CONCRETE, u0=(v * 0.37 + u * 0.11) % 1.0)
    vs = [y / C.S_CONCRETE for y in ys]
    centre = P(v, 0.0, u)
    loft(acc, rings, us, vs, lambda p: Vector((centre.x, p.y, centre.z)))


# ------------------------------------------------------------------ floor, slopes, shelves, side walls
def stations(u0, u1):
    cuts = [b for b in C.TRENCH_U + (C.CHAMFER_U0, C.END_U) if u0 + 1e-6 < b < u1 - 1e-6]
    return [u0] + sorted(cuts) + [u1]


def floor_band(m, u0, u1):
    """Trench floor, the two 60 deg slopes, shelves, wall fillets and side walls over u0..u1 (piecewise linear
    between the plan stations)."""
    fl = m["TK_Floor"]
    cc = m["TK_Concrete"]
    st = stations(u0, u1)
    F = C.WALL_FILLET
    for a, b in zip(st[:-1], st[1:]):
        ta, tb = C.toe(a), C.toe(b)
        ca, cb = C.crest(a), C.crest(b)
        wa, wb = C.wall_half(a), C.wall_half(b)
        mid_u = (a + b) * 0.5
        n = 6
        for i in range(n):
            f0, f1 = i / n, (i + 1) / n
            fl.face((P(-ta + 2 * ta * f0, 0.0, a), P(-ta + 2 * ta * f1, 0.0, a), P(-tb + 2 * tb * f1, 0.0, b), P(-tb + 2 * tb * f0, 0.0, b)), out=(0, 1, 0))
        for s in (-1.0, 1.0):
            face_to(cc, (P(s * ta, 0.0, a), P(s * ca, Y5, a), P(s * cb, Y5, b), P(s * tb, 0.0, b)), P(0.0, Y5 + 6.0, mid_u))
            fl.face((P(s * ca, Y5, a), P(s * (wa - F), Y5, a), P(s * (wb - F), Y5, b), P(s * cb, Y5, b)), out=(0, 1, 0))
            face_to(cc, (P(s * (wa - F), Y5, a), P(s * wa, Y5 + F, a), P(s * wb, Y5 + F, b), P(s * (wb - F), Y5, b)), P(0.0, Y5 + 6.0, mid_u))
            face_to(cc, (P(s * wa, Y5 + F, a), P(s * wa, HAUNCH_Y, a), P(s * wb, HAUNCH_Y, b), P(s * wb, Y5 + F, b)), P(0.0, 9.0, mid_u))


# ------------------------------------------------------------------ ceiling
def coffer(m, va0, vb0, va1, vb1, u0, u1, flags=(True, True, True, True)):
    """Inverted tray between beams / walls. Plan corners (va0, u0) (vb0, u0) (vb1, u1) (va1, u1), va < vb.
    flags: vertical beam faces BEAM_Y .. HAUNCH_Y on the va, vb, u0, u1 sides (False where a wall stands)."""
    acc = m["TK_Concrete"]
    h = C.HAUNCH
    yb, yh, yt = C.BEAM_Y, HAUNCH_Y, C.H
    ref = P((va0 + vb0 + va1 + vb1) * 0.25, yb - 2.0, (u0 + u1) * 0.5)
    A, B, Cc, Dd = (va0, u0), (vb0, u0), (vb1, u1), (va1, u1)
    Ai, Bi, Ci, Di = (va0 + h, u0 + h), (vb0 - h, u0 + h), (vb1 - h, u1 - h), (va1 + h, u1 - h)
    face_to(acc, (P(Ai[0], yt, Ai[1]), P(Bi[0], yt, Bi[1]), P(Ci[0], yt, Ci[1]), P(Di[0], yt, Di[1])), ref)
    for (p, q, pi, qi) in ((A, B, Ai, Bi), (B, Cc, Bi, Ci), (Cc, Dd, Ci, Di), (Dd, A, Di, Ai)):
        face_to(acc, (P(p[0], yh, p[1]), P(q[0], yh, q[1]), P(qi[0], yt, qi[1]), P(pi[0], yt, pi[1])), ref)
    for (p, q, on) in ((Dd, A, flags[0]), (B, Cc, flags[1]), (A, B, flags[2]), (Cc, Dd, flags[3])):
        if on:
            face_to(acc, (P(p[0], yb, p[1]), P(q[0], yb, q[1]), P(q[0], yh, q[1]), P(p[0], yh, p[1])), ref)


def ceiling_strip(m, rows, u0, u1, beam_u0=True, beam_u1=True):
    """Coffers of the strip u0..u1 between the pillar-head beams of `rows` (|v - r| <= 2) and the side walls."""
    w0, w1 = C.wall_half(u0), C.wall_half(u1)
    bounds = ["wall"]
    for r in sorted(rows):
        bounds += [r - C.LB_HALF_W, r + C.LB_HALF_W]
    bounds.append("wall")
    for i in range(0, len(bounds), 2):
        a, b = bounds[i], bounds[i + 1]
        va0 = -w0 if a == "wall" else a
        va1 = -w1 if a == "wall" else a
        vb0 = w0 if b == "wall" else b
        vb1 = w1 if b == "wall" else b
        if min(vb0 - va0, vb1 - va1) < 2.0 * C.HAUNCH + 0.2:
            continue
        coffer(m, va0, vb0, va1, vb1, u0, u1, flags=(a != "wall", b != "wall", beam_u0, beam_u1))


def transverse_beam(m, u0, u1):
    """Soffit of a transverse beam over u0..u1 with the haunches under its ends at the side walls."""
    acc = m["TK_Concrete"]
    hw = C.TB_WALL_HAUNCH
    w0, w1 = C.wall_half(u0), C.wall_half(u1)
    yb = C.BEAM_Y
    face_to(acc, (P(-(w0 - hw), yb, u0), P(w0 - hw, yb, u0), P(w1 - hw, yb, u1), P(-(w1 - hw), yb, u1)), P(0.0, 0.0, (u0 + u1) * 0.5))
    for s in (-1.0, 1.0):
        face_to(acc, (P(s * w0, yb - hw, u0), P(s * w1, yb - hw, u1), P(s * (w1 - hw), yb, u1), P(s * (w0 - hw), yb, u0)), P(0.0, yb - 4.0, (u0 + u1) * 0.5))
        for uu, ww, du in ((u0, w0, -1.0), (u1, w1, 1.0)):
            face_to(acc, (P(s * ww, yb - hw, uu), P(s * (ww - hw), yb, uu), P(s * ww, yb, uu)), P(s * (ww - 0.3), yb - 0.3, uu + du * 3.0))


def lb_flat(m, v, u0, u1):
    """A plain stretch of pillar-head beam soffit (over the dividing walls at the pump end)."""
    acc = m["TK_Concrete"]
    face_to(acc, (P(v - C.LB_HALF_W, C.BEAM_Y, u0), P(v + C.LB_HALF_W, C.BEAM_Y, u0), P(v + C.LB_HALF_W, C.BEAM_Y, u1), P(v - C.LB_HALF_W, C.BEAM_Y, u1)), P(v, 0.0, (u0 + u1) * 0.5))


# ------------------------------------------------------------------ steel: railings, catwalks, lamps
def railing(m, a, b, base_y, post_step=1.8, height=1.1, toe=True, mat="TK_Galv", r=0.024):
    """Straight railing between Godot points a and b at deck level: posts, top and mid rails, toe board."""
    acc = m[mat]
    a, b = Vector(a), Vector(b)
    d = b - a
    d.y = 0.0
    L = d.length
    if L < 1e-3:
        return
    n = max(1, int(math.ceil(L / post_step)))
    for i in range(n + 1):
        q = a + d * (i / n)
        acc.cyl(V(q.x, base_y, q.z), V(q.x, base_y + height, q.z), r * 1.15, segs=6, caps=True)
    for hgt in (height, height * 0.5):
        acc.cyl(V(a.x, base_y + hgt, a.z), V(b.x, base_y + hgt, b.z), r, segs=6, caps=True)
    if toe:
        t = d.normalized()
        nrm = Vector((-t.z, 0.0, t.x)) * 0.004
        acc.face((V(a.x, base_y, a.z) - nrm, V(b.x, base_y, b.z) - nrm, V(b.x, base_y + 0.1, b.z) - nrm, V(a.x, base_y + 0.1, a.z) - nrm), out=Vector((-t.z, 0.0, t.x)))
        acc.face((V(a.x, base_y, a.z) + nrm, V(a.x, base_y + 0.1, a.z) + nrm, V(b.x, base_y + 0.1, b.z) + nrm, V(b.x, base_y, b.z) + nrm), out=Vector((t.z, 0.0, -t.x)))


def catwalk_run(m, s, u0, u1, y=C.CATWALK_Y, w=C.CATWALK_W):
    """Steel catwalk on a straight side wall (v = s * 35.5): grating deck, green-painted cantilever brackets
    every ~2.3 m with struts back to the wall, galvanised railing on the open edge."""
    vw = s * C.INNER_HALF
    ve = s * (C.INNER_HALF - w)
    g = m["TK_Grate"]
    g.face((P(ve, y, u0), P(ve, y, u1), P(vw, y, u1), P(vw, y, u0)), out=(0, 1, 0))
    g.face((P(ve, y - 0.03, u0), P(vw, y - 0.03, u0), P(vw, y - 0.03, u1), P(ve, y - 0.03, u1)), out=(0, -1, 0))
    pm = m["TK_Paint"]
    e0, e1 = P(ve, y - 0.18, u0), P(ve, y, u1)
    pm.box((e0.x - 0.04, y - 0.18, min(e0.z, e1.z)), (e0.x + 0.04, y, max(e0.z, e1.z)), skip=("-z", "+z"))
    n = max(1, int(round((u1 - u0) / 2.33)))
    for i in range(n):
        uc = u0 + (u1 - u0) * (i + 0.5) / n
        abox(pm, P(vw, y - 0.16, uc - 0.05), P(ve, y - 0.03, uc + 0.05))
        pm.cyl(P(ve, y - 0.16, uc), P(vw, y - 1.05, uc), 0.045, segs=6, caps=True)
        abox(pm, P(vw, y - 1.2, uc - 0.09), P(vw - s * 0.012, y - 0.05, uc + 0.09))
    railing(m, P(ve, y, u0), P(ve, y, u1), y, post_step=2.33)


def high_bay(m, v, u, name, y_mount=C.H):
    """LED high-bay hanging at plan (v, u) from the ceiling above it (the coffer's slab, on a hoist cable in the
    real tank): stem, finned body, lens facing down."""
    st = m["TK_Steel"]
    c = P(v, 0.0, u)
    x, z = c.x, c.z
    st.cyl(V(x, y_mount, z), V(x, LAMP_Y + 0.22, z), 0.022, segs=6, caps=False)
    st.cyl(V(x, LAMP_Y + 0.22, z), V(x, LAMP_Y + 0.13, z), 0.17, r1=0.25, segs=16, caps=True)
    st.cyl(V(x, LAMP_Y + 0.13, z), V(x, LAMP_Y + 0.015, z), 0.26, segs=16, caps=False)
    st.cyl(V(x, LAMP_Y + 0.015, z), V(x, LAMP_Y + 0.0, z), 0.26, r1=0.235, segs=16, caps=False)
    for i in range(8):
        a = math.tau * i / 8
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        st.obox(V(x, LAMP_Y + 0.17, z) + d * 0.2, (0.01, 0.08, 0.1), M=Matrix.Rotation(-a, 4, "Y"))
    ring = [V(x + 0.225 * math.cos(math.tau * i / 16), LAMP_Y - 0.002, z + 0.225 * math.sin(math.tau * i / 16)) for i in range(16)]
    m["TK_Lens"].face(ring, out=(0, -1, 0))
    m.lights.append(("Bay", (x, LAMP_Y - 0.06, z), (0.0, -1.0, 0.0), {"name": name}))


def wall_lamp(m, s, u, name, y=C.CATWALK_Y + 1.9, vwall=C.INNER_HALF, tilt=0.55):
    """Flood on a wall face at v = s * vwall, washing the wall and the floor below toward the centre."""
    w = P(s * vwall, y, u)
    inward = Vector((1.0 if s > 0 else -1.0, 0.0, 0.0))      # toward the centre line, in Godot x
    st = m["TK_Steel"]
    abox(st, w + Vector((0.0, 0.0, -0.06)), w + inward * 0.35 + Vector((0.0, 0.08, 0.06)))
    c = w + inward * 0.45 + Vector((0.0, -0.05, 0.0))
    R = Matrix.Rotation(inward.x * math.radians(35), 4, "Z")
    st.obox(c, (0.22, 0.30, 0.42), M=R)
    off = R @ Vector((0.0, -0.152, 0.0))
    hx, hz = 0.1, 0.19
    pts = [c + off + R @ Vector((sx * hx, 0.0, sz * hz)) for (sx, sz) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    m["TK_Lens"].face(pts, out=R @ Vector((0, -1, 0)))
    aim = (inward * tilt + Vector((0.0, -1.0, 0.0))).normalized()
    m.lights.append(("Wall", tuple(c + off * 1.3), tuple(aim), {"name": name}))


# ------------------------------------------------------------------ pillar-line slices (K00..K10)
def lamp_rows(k):
    """Rows of the pendant lamps of line k: the free rows (no pillar on this line), |v| <= 21."""
    return [v for v in C.ROWS if v not in C.pillar_rows(k) and abs(v) <= 21.0]


def build_slice(k):
    m = Mod("K%02d" % k)
    uk = C.line_u(k)
    u0, u1 = uk - HEAD_HZ, uk + HALF_LINE + TB_HALF           # u_k - 6 .. u_k + 8
    floor_band(m, u0, u1)
    rows = C.pillar_rows(k)
    for v in rows:
        pillar(m, v, uk, Y5 if C.on_shelf(v, uk) else 0.0)
    ceiling_strip(m, rows, u0, uk + HEAD_HZ)
    transverse_beam(m, uk + HEAD_HZ, u1)
    for v in lamp_rows(k):
        high_bay(m, v, uk, "%+d" % int(v))
    cu1 = min(u1, C.CHAMFER_U0)
    for s in (-1.0, 1.0):
        if cu1 - u0 > 1.0:
            catwalk_run(m, s, u0, cu1)
        if uk < C.CHAMFER_U0:
            wall_lamp(m, s, uk, "%s" % ("L" if s < 0 else "R"))
    return m


# ------------------------------------------------------------------ pump end (P)
def build_pump_end():
    m = Mod("P")
    u_tb0 = C.line_u(-1) + HEAD_HZ                           # 12.8: pump-side face of the beam before line 0
    u1 = u_tb0 + C.TB_W                                      # 14.8
    floor_band(m, 0.0, u1)
    cc = m["TK_Concrete"]
    ref_in = P(0.0, 8.0, 10.0)
    # gate face at u = 0 where there is neither a channel nor a dividing wall
    solid = [(-C.INNER_HALF, C.INNER_HALF)]
    for (a, b) in sorted((c - C.CHANNEL_HALF, c + C.CHANNEL_HALF) for c in C.CHANNELS_V):
        solid = [piece for (lo, hi) in solid for piece in ((lo, min(hi, a)), (max(lo, b), hi)) if piece[1] - piece[0] > 0.05]
    for p in C.PIERS_V:
        a, b = p - C.PIER_HALF, p + C.PIER_HALF
        solid = [piece for (lo, hi) in solid for piece in ((lo, min(hi, a)), (max(lo, b), hi)) if piece[1] - piece[0] > 0.05]
    for (a, b) in solid:
        if abs(a) > abs(b):
            a, b = b, a
        s = 1.0 if b > 0 else -1.0
        # outside the trench: from the shelf, closing the fillet at the wall
        prof = [(a, Y5), (s * (C.INNER_HALF - C.WALL_FILLET), Y5), (b, Y5 + C.WALL_FILLET), (b, HAUNCH_Y), (a, HAUNCH_Y)]
        for i in range(1, len(prof) - 2):
            face_to(cc, (P(prof[-1][0], prof[-1][1], 0.0), P(prof[i][0], prof[i][1], 0.0), P(prof[i + 1][0], prof[i + 1][1], 0.0)), ref_in)
        face_to(cc, (P(prof[-1][0], prof[-1][1], 0.0), P(prof[0][0], prof[0][1], 0.0), P(prof[1][0], prof[1][1], 0.0)), ref_in)
    # the slope ends inside the outer channels: cap it toward the chamber
    for s in (-1.0, 1.0):
        face_to(cc, (P(s * C.toe(0.0), 0.0, 0.0), P(s * C.crest(0.0), Y5, 0.0), P(s * C.crest(0.0), 0.0, 0.0)), P(s * 25.0, 2.0, -3.0))
    # lintels over the channels
    for c in C.CHANNELS_V:
        a, b = c - C.CHANNEL_HALF, c + C.CHANNEL_HALF
        face_to(cc, (P(a, C.BEAM_Y, 0.0), P(b, C.BEAM_Y, 0.0), P(b, HAUNCH_Y, 0.0), P(a, HAUNCH_Y, 0.0)), ref_in)
    # dividing walls: 2 m thick, round tips 9.3 m into the tank, up to the beam soffit; their beams run on to
    # the transverse beam before line 0
    for p in C.PIERS_V:
        ybase = Y5 if abs(p) - C.PIER_HALF >= C.CREST_PUMP - 0.05 else 0.0
        tip_c = C.PIER_TIP_U - C.PIER_HALF
        outline = [(p - C.PIER_HALF, 0.0)]
        for i in range(13):
            a = math.pi + math.pi * i / 12.0
            outline.append((p + C.PIER_HALF * math.cos(a), tip_c - C.PIER_HALF * math.sin(a)))
        outline.append((p + C.PIER_HALF, 0.0))
        perim = 0.0
        for i in range(len(outline) - 1):
            (va, ua), (vb, ub) = outline[i], outline[i + 1]
            seg = math.hypot(vb - va, ub - ua) / C.S_CONCRETE
            uv = ((perim, ybase / C.S_CONCRETE), (perim + seg, ybase / C.S_CONCRETE), (perim + seg, C.BEAM_Y / C.S_CONCRETE), (perim, C.BEAM_Y / C.S_CONCRETE))
            perim += seg
            f = m["TK_Pillar"].face((P(va, ybase, ua), P(vb, ybase, ub), P(vb, C.BEAM_Y, ub), P(va, C.BEAM_Y, ua)), smooth=0 < i < len(outline) - 2, uv=uv)
            mid = P((va + vb) * 0.5, 5.0, (ua + ub) * 0.5)
            m["TK_Pillar"].orient(f, mid - P(p, 5.0, min(tip_c, (ua + ub) * 0.5)))
        lb_flat(m, p, 0.0, u_tb0)
    ceiling_strip(m, list(C.PIERS_V), 0.0, u_tb0, beam_u0=False, beam_u1=True)
    transverse_beam(m, u_tb0, u1)
    for c in C.CHANNELS_V:
        high_bay(m, c, u_tb0 * 0.5, "Front_%+d" % int(c))
    for bi, c in enumerate(C.CHANNELS_V):
        intake_channel(m, c, bi)
    for s in (-1.0, 1.0):
        catwalk_run(m, s, 0.0, u1)
        wall_lamp(m, s, 7.0, "%s" % ("L" if s < 0 else "R"))
    return m


def intake_channel(m, c, index):
    """One intake channel seen from the tank (the "altar"): behind the gate face a 6 m chamber 12 m wide with a
    sill, a dark slot under a lip, a curved ramp up to a ledge, the back wall, a catwalk at 9.5 m and lamps."""
    acc = m["TK_Concrete"]
    hw = C.CHANNEL_HALF
    v0, v1 = c - hw, c + hw
    ub = -C.CHANNEL_DEPTH
    ys, yl = 2.4, 4.6
    ceil_y = 16.6
    inner = P(c, 6.0, ub * 0.5)
    for vv in (v0, v1):
        face_to(acc, (P(vv, 0.0, 0.0), P(vv, 0.0, ub), P(vv, ceil_y - 1.0, ub), P(vv, C.BEAM_Y, 0.0)), inner)
    face_to(acc, (P(v0, yl, ub), P(v1, yl, ub), P(v1, ceil_y - 1.0, ub), P(v0, ceil_y - 1.0, ub)), inner)
    # chamber ceiling: soffit sloping up from the lintel, flat panel, haunches
    face_to(acc, (P(v0, C.BEAM_Y, 0.0), P(v1, C.BEAM_Y, 0.0), P(v1 - 1.0, ceil_y, -1.6), P(v0 + 1.0, ceil_y, -1.6)), inner)
    face_to(acc, (P(v0 + 1.0, ceil_y, -1.6), P(v1 - 1.0, ceil_y, -1.6), P(v1 - 1.0, ceil_y, ub + 1.0), P(v0 + 1.0, ceil_y, ub + 1.0)), inner)
    face_to(acc, (P(v0, ceil_y - 1.0, ub), P(v0 + 1.0, ceil_y, ub + 1.0), P(v1 - 1.0, ceil_y, ub + 1.0), P(v1, ceil_y - 1.0, ub)), inner)
    face_to(acc, (P(v0, C.BEAM_Y, 0.0), P(v0 + 1.0, ceil_y, -1.6), P(v0 + 1.0, ceil_y, ub + 1.0), P(v0, ceil_y - 1.0, ub)), inner)
    face_to(acc, (P(v1, C.BEAM_Y, 0.0), P(v1, ceil_y - 1.0, ub), P(v1 - 1.0, ceil_y, ub + 1.0), P(v1 - 1.0, ceil_y, -1.6)), inner)
    # sill at the gate face, dark slot under a lip, curved ramp, ledge
    tank = P(c, 1.0, 5.0)
    face_to(acc, (P(v0, 0.0, 0.0), P(v1, 0.0, 0.0), P(v1, ys, 0.0), P(v0, ys, 0.0)), tank)
    face_to(acc, (P(v0, ys, 0.0), P(v1, ys, 0.0), P(v1, ys, -0.35), P(v0, ys, -0.35)), P(c, ys + 3.0, 0.5))
    slot_top = ys + 0.32
    face_to(m["TK_Void"], (P(v0, ys, -0.35), P(v1, ys, -0.35), P(v1, slot_top, -0.35), P(v0, slot_top, -0.35)), tank)
    face_to(acc, (P(v0, slot_top, -0.35), P(v1, slot_top, -0.35), P(v1, slot_top, 0.0), P(v0, slot_top, 0.0)), P(c, 0.0, 0.5))
    face_to(acc, (P(v0, slot_top, 0.0), P(v1, slot_top, 0.0), P(v1, slot_top + 0.25, 0.0), P(v0, slot_top + 0.25, 0.0)), tank)
    ramp_d = 4.1
    prev = None
    for i in range(9):
        a = 0.5 * math.pi * i / 8
        uu = -ramp_d * math.sin(a)
        yy = slot_top + 0.25 + (yl - slot_top - 0.25) * (1.0 - math.cos(a))
        if prev is not None:
            f = acc.face((P(v0, prev[1], prev[0]), P(v1, prev[1], prev[0]), P(v1, yy, uu), P(v0, yy, uu)), smooth=True)
            acc.orient(f, P(c, yy + 4.0, uu + 2.0) - P(c, yy, uu))
        prev = (uu, yy)
    face_to(acc, (P(v0, yl, -ramp_d), P(v1, yl, -ramp_d), P(v1, yl, ub), P(v0, yl, ub)), P(c, yl + 3.0, -5.0))
    # catwalk along the back wall
    yc = C.CATWALK_CHANNEL_Y
    uc0 = ub + 1.2
    g = m["TK_Grate"]
    g.face((P(v0, yc, uc0), P(v1, yc, uc0), P(v1, yc, ub), P(v0, yc, ub)), out=(0, 1, 0))
    g.face((P(v0, yc - 0.03, uc0), P(v0, yc - 0.03, ub), P(v1, yc - 0.03, ub), P(v1, yc - 0.03, uc0)), out=(0, -1, 0))
    pm = m["TK_Paint"]
    abox(pm, P(v0, yc - 0.2, uc0 - 0.05), P(v1, yc, uc0 + 0.05))
    for i in range(5):
        vv = v0 + 0.6 + (v1 - v0 - 1.2) * i / 4
        abox(pm, P(vv - 0.05, yc - 0.18, uc0), P(vv + 0.05, yc - 0.03, ub))
        pm.cyl(P(vv, yc - 0.18, uc0 + 0.1), P(vv, yc - 1.0, ub), 0.045, segs=6)
    railing(m, P(v0, yc, uc0), P(v1, yc, uc0), yc, post_step=1.6)
    # lamps: chamber ceiling and a strip over the catwalk
    high_bay(m, c, -3.6, "Pit_%d" % index, y_mount=ceil_y)
    st = m["TK_Steel"]
    abox(st, P(c - 0.6, yc + 2.05, ub + 0.18), P(c + 0.6, yc + 2.17, ub))
    face_to(m["TK_Lens"], (P(c - 0.55, yc + 2.049, ub + 0.16), P(c + 0.55, yc + 2.049, ub + 0.16), P(c + 0.55, yc + 2.049, ub + 0.02), P(c - 0.55, yc + 2.049, ub + 0.02)), P(c, 0.0, ub + 0.1))
    m.lights.append(("Strip", tuple(P(c, yc + 2.0, ub + 0.1)), (0.0, -1.0, 0.0), {"name": "%d" % index, "size": (1.1, 0.14)}))


# ------------------------------------------------------------------ shaft-side end (S)
def arc_points(v0, v1, n):
    """Points (v, u) on the shaft's inner face from v0 to v1."""
    return [(v0 + (v1 - v0) * i / n, shaft_u(v0 + (v1 - v0) * i / n)) for i in range(n + 1)]


def build_shaft_end():
    m = Mod("S")
    u0 = C.line_u(10) + HALF_LINE + TB_HALF                 # 168.8
    ue = C.END_U
    floor_band(m, u0, ue)
    cc = m["TK_Concrete"]
    coffer(m, -C.wall_half(u0), C.wall_half(u0), -C.wall_half(ue), C.wall_half(ue), u0, ue, flags=(False, False, True, False))
    tank = P(0.0, 8.0, ue - 6.0)
    ho = C.OPEN_HALF
    t, cr, w = C.toe(ue), C.crest(ue), C.wall_half(ue)
    # end wall beside the openings, standing on the floor profile (trench, slope, shelf, fillet)
    for s in (-1.0, 1.0):
        prof = [(ho, 0.0), (t, 0.0), (cr, Y5), (w - C.WALL_FILLET, Y5), (w, Y5 + C.WALL_FILLET), (w, HAUNCH_Y), (ho, HAUNCH_Y)]
        prof = [(s * v_, y_) for (v_, y_) in prof]
        for i in range(1, len(prof) - 2):
            face_to(cc, (P(prof[-1][0], prof[-1][1], ue), P(prof[i][0], prof[i][1], ue), P(prof[i + 1][0], prof[i + 1][1], ue)), tank)
        face_to(cc, (P(prof[-1][0], prof[-1][1], ue), P(prof[0][0], prof[0][1], ue), P(prof[1][0], prof[1][1], ue)), tank)
    face_to(cc, (P(-ho, C.OPEN_TOP, ue), P(ho, C.OPEN_TOP, ue), P(ho, HAUNCH_Y, ue), P(-ho, HAUNCH_Y, ue)), tank)
    # passage to shaft No.1: jambs with chamfered feet, soffit and floor, all ending on the shaft's inner face
    cx, cy = PASSAGE_CHAMFER
    mid_passage = P(0.0, 7.0, (ue + C.SHAFT_INNER_U) * 0.5)
    for s in (-1.0, 1.0):
        prof = [(s * ho, C.OPEN_TOP), (s * ho, cy), (s * (ho - cx), 0.0)]
        for i in range(len(prof) - 1):
            (va, ya), (vb, yb_) = prof[i], prof[i + 1]
            face_to(cc, (P(va, ya, ue), P(vb, yb_, ue), P(vb, yb_, shaft_u(vb)), P(va, ya, shaft_u(va))), mid_passage)
    arc = arc_points(-ho, ho, 22)
    for i in range(len(arc) - 1):
        (va, ua), (vb, ub_) = arc[i], arc[i + 1]
        face_to(cc, (P(va, C.OPEN_TOP, ue), P(vb, C.OPEN_TOP, ue), P(vb, C.OPEN_TOP, ub_), P(va, C.OPEN_TOP, ua)), P((va + vb) * 0.5, 0.0, ue + 2.0))
    fl = m["TK_Floor"]
    farc = arc_points(-(ho - cx), ho - cx, 18)
    for i in range(len(farc) - 1):
        (va, ua), (vb, ub_) = farc[i], farc[i + 1]
        fl.face((P(va, 0.0, ue), P(vb, 0.0, ue), P(vb, 0.0, ub_), P(va, 0.0, ua)), out=(0, 1, 0))
    # the 2 x 8 m pier between the openings
    pc = ue + PASSAGE_PIER_LEN * 0.5
    outline = rrect(0.0, pc, C.OPEN_PIER_HALF, PASSAGE_PIER_LEN * 0.5, C.OPEN_PIER_HALF - 1e-4, 6)
    rings = [ring_at(outline, 0.0), ring_at(outline, C.OPEN_TOP)]
    us = perimeter_u(outline, C.S_CONCRETE)
    centre = P(0.0, 0.0, pc)
    loft(m["TK_Pillar"], rings, us, [0.0, C.OPEN_TOP / C.S_CONCRETE], lambda p: Vector((centre.x, p.y, centre.z)))
    # fence along the drop into the shaft, concrete blocks in front of the end wall
    for s in (-1.0, 1.0):
        pts = arc_points(s * (C.OPEN_PIER_HALF + 0.3), s * (ho - cx - 0.15), 6)
        for i in range(len(pts) - 1):
            (va, ua), (vb, ub_) = pts[i], pts[i + 1]
            railing(m, P(va, 0.0, ua - 0.3), P(vb, 0.0, ub_ - 0.3), 0.0, post_step=2.0, mat="TK_Steel", r=0.03, toe=False)
    for i in range(7):
        v = -12.0 + 4.0 * i
        abox(cc, P(v - 0.5, 0.0, ue - 1.9), P(v + 0.5, 0.85, ue - 1.0), skip=("-y",))
    # lamps on brackets under the lintel, one per opening
    st = m["TK_Steel"]
    for v in (-6.0, 6.0):
        abox(st, P(v - 0.06, C.OPEN_TOP - 0.1, ue - 0.8), P(v + 0.06, C.OPEN_TOP + 0.02, ue))
        high_bay(m, v, ue - 0.75, "Open_%+d" % int(v), y_mount=C.OPEN_TOP - 0.05)
    return m


# ------------------------------------------------------------------ shaft No.1 (Q)
def build_shaft():
    m = Mod("Q")
    R = C.SHAFT_R
    uc = C.SHAFT_CENTRE_U
    ho = C.OPEN_HALF
    half = math.asin(ho / R)
    centre = P(0.0, 0.0, uc)
    # angle a from the tank direction (-u) about the shaft axis: v = R sin a, u = uc - R cos a; the window
    # |a| < half, 0 < y < OPEN_TOP is where the passage enters
    angles = [-half + 2.0 * half * i / 12 for i in range(12)] + [half + (math.tau - 2.0 * half) * i / 72 for i in range(73)]
    ys = [C.SHAFT_BOTTOM, -24.0, -12.0, -4.0, 0.0, 6.0, 12.0, C.OPEN_TOP, C.SHAFT_TOP - 3.0, C.SHAFT_TOP]
    acc = m["TK_Pillar"]
    arc_len = [0.0]
    for i in range(1, len(angles)):
        arc_len.append(arc_len[-1] + R * (angles[i] - angles[i - 1]))
    for r in range(len(ys) - 1):
        for i in range(len(angles) - 1):
            a0, a1 = angles[i], angles[i + 1]
            if a1 <= half + 1e-6 and ys[r] >= -1e-6 and ys[r + 1] <= C.OPEN_TOP + 1e-6:
                continue
            pts = [P(R * math.sin(a), y, uc - R * math.cos(a)) for (a, y) in ((a0, ys[r]), (a1, ys[r]), (a1, ys[r + 1]), (a0, ys[r + 1]))]
            uv = tuple((arc_len[i + di] / C.S_CONCRETE, y / C.S_CONCRETE) for (di, y) in ((0, ys[r]), (1, ys[r]), (1, ys[r + 1]), (0, ys[r + 1])))
            f = acc.face(pts, smooth=True, uv=uv)
            mid = sum(pts, Vector()) / 4
            acc.orient(f, Vector((centre.x, mid.y, centre.z)) - mid)
    cc = m["TK_Concrete"]
    pool = [P(R * math.sin(math.tau * i / 48), C.SHAFT_BOTTOM, uc - R * math.cos(math.tau * i / 48)) for i in range(48)]
    m["TK_Void"].face(pool, out=(0, 1, 0))
    sky_r = 9.0
    ring_out = [P(R * math.sin(math.tau * i / 48), C.SHAFT_TOP, uc - R * math.cos(math.tau * i / 48)) for i in range(48)]
    ring_in = [P(sky_r * math.sin(math.tau * i / 48), C.SHAFT_TOP, uc - sky_r * math.cos(math.tau * i / 48)) for i in range(48)]
    for i in range(48):
        j = (i + 1) % 48
        f = cc.face((ring_out[i], ring_out[j], ring_in[j], ring_in[i]))
        cc.orient(f, Vector((0.0, -1.0, 0.0)))
    sky = [P(sky_r * math.sin(math.tau * i / 48), C.SHAFT_TOP + 0.05, uc - sky_r * math.cos(math.tau * i / 48)) for i in range(48)]
    m["TK_Sky"].face(sky, out=(0, -1, 0))
    # ring catwalk near the top, all the way round
    yr = C.SHAFT_TOP - 3.4
    g = m["TK_Grate"]
    pm = m["TK_Paint"]
    nr = 48
    for i in range(nr):
        aa, bb = math.tau * i / nr, math.tau * (i + 1) / nr
        p0, p1 = P(R * math.sin(aa), yr, uc - R * math.cos(aa)), P(R * math.sin(bb), yr, uc - R * math.cos(bb))
        q0, q1 = P((R - 1.2) * math.sin(aa), yr, uc - (R - 1.2) * math.cos(aa)), P((R - 1.2) * math.sin(bb), yr, uc - (R - 1.2) * math.cos(bb))
        g.face((q0, q1, p1, p0), out=(0, 1, 0))
        g.face((q0, p0, p1, q1), out=(0, -1, 0))
        pm.cyl(V(q0.x, yr, q0.z), V(q0.x, yr + 1.1, q0.z), 0.03, segs=6, caps=False)
        pm.cyl(V(q0.x, yr + 1.1, q0.z), V(q1.x, yr + 1.1, q1.z), 0.03, segs=6, caps=False)
        pm.cyl(V(q0.x, yr + 0.55, q0.z), V(q1.x, yr + 0.55, q1.z), 0.025, segs=6, caps=False)
    # scissor stair tower against the far wall, left of the axis seen from the tank (photos)
    ang = math.radians(152.0)
    t = P((R - 2.2) * math.sin(ang), 0.0, uc - (R - 2.2) * math.cos(ang))
    stair_tower(m, t.x, t.z, C.SHAFT_BOTTOM + 2.0, C.SHAFT_TOP - 3.4)
    for deg, rad in ((132.0, 0.35), (128.0, 0.28), (210.0, 0.4)):
        a = math.radians(deg)
        p = P((R - rad - 0.15) * math.sin(a), 0.0, uc - (R - rad - 0.15) * math.cos(a))
        m["TK_Galv"].cyl(V(p.x, C.SHAFT_BOTTOM, p.z), V(p.x, C.SHAFT_TOP - 0.5, p.z), rad, segs=12, caps=False)
    for i in range(8):
        a = math.tau * (i + 0.5) / 8
        p = P((R - 0.8) * math.sin(a), C.SHAFT_TOP - 1.2, uc - (R - 0.8) * math.cos(a))
        aim = (Vector((0.0, -1.0, 0.0)) * 0.8 + (Vector((centre.x, p.y, centre.z)) - p).normalized() * 0.6).normalized()
        m.lights.append(("Shaft", tuple(p), tuple(aim), {"name": "%d" % i}))
        m["TK_Steel"].obox(p, (0.5, 0.35, 0.35))
    m.lights.append(("Sky", (centre.x, C.SHAFT_TOP + 0.4, centre.z), (0.0, -1.0, 0.0), {"name": "Top", "radius": sky_r}))
    return m


def stair_tower(m, cx, cz, y0, y1, w=3.4, d=3.0, flight=3.0):
    """Scissor stair tower: corner posts, landings, flights, railings (painted steel). Axis aligned in Godot."""
    pm = m["TK_Paint"]
    g = m["TK_Grate"]
    for sx in (-1, 1):
        for sz in (-1, 1):
            pm.box((cx + sx * w * 0.5 - 0.08, y0, cz + sz * d * 0.5 - 0.08), (cx + sx * w * 0.5 + 0.08, y1 + 1.1, cz + sz * d * 0.5 + 0.08))
    y = y0
    flip = 1.0
    while y < y1 - 0.1:
        yn = min(y1, y + flight)
        for sx in (-1, 1):
            x_a, x_b = sorted((cx + sx * w * 0.5, cx + sx * (w * 0.5 - 0.9)))
            g.face((V(x_a, yn, cz - d * 0.5), V(x_a, yn, cz + d * 0.5), V(x_b, yn, cz + d * 0.5), V(x_b, yn, cz - d * 0.5)), out=(0, 1, 0))
            g.face((V(x_a, yn - 0.04, cz - d * 0.5), V(x_b, yn - 0.04, cz - d * 0.5), V(x_b, yn - 0.04, cz + d * 0.5), V(x_a, yn - 0.04, cz + d * 0.5)), out=(0, -1, 0))
        zf = cz + flip * d * 0.25
        xa, xb = cx - w * 0.5 + 0.9, cx + w * 0.5 - 0.9
        if flip < 0:
            xa, xb = xb, xa
        steps = 14
        for i in range(steps):
            t0, t1 = i / steps, (i + 1) / steps
            xs0, xs1 = xa + (xb - xa) * t0, xa + (xb - xa) * t1
            ys_ = y + (yn - y) * t1
            x_lo, x_hi = sorted((xs0, xs1))
            g.face((V(x_lo, ys_, zf - d * 0.24), V(x_lo, ys_, zf + d * 0.24), V(x_hi, ys_, zf + d * 0.24), V(x_hi, ys_, zf - d * 0.24)), out=(0, 1, 0))
        for sz in (-1, 1):
            zz = zf + sz * d * 0.25
            pm.cyl(V(xa, y, zz), V(xb, yn, zz), 0.05, segs=6, caps=True)
            pm.cyl(V(xa, y + 1.0, zz), V(xb, yn + 1.0, zz), 0.025, segs=6, caps=True)
        flip = -flip
        y = yn


# ------------------------------------------------------------------ visitor access (T)
DOOR_U = 152.25                 # plan: the stair "階段" (5) in the +v wall where the chamfer starts
PORTAL = (3.7, 1.0, 3.2)        # portal block around the door: along u, depth, height above the shelf
STAIR_W = 1.3


def steel_flight(m, a, b, width, rise=0.18):
    """Straight steel flight from a (top nosing, Godot point) to b (bottom): grating treads, painted stringers,
    galvanised handrails both sides."""
    a, b = Vector(a), Vector(b)
    d = b - a
    horiz = Vector((d.x, 0.0, d.z))
    t = horiz.normalized()
    side = Vector((-t.z, 0.0, t.x))
    n = max(2, int(round(abs(d.y) / rise)))
    g = m["TK_Grate"]
    pm = m["TK_Paint"]
    for i in range(n):
        f0, f1 = i / n, (i + 1) / n
        y = a.y + d.y * f1
        c0, c1 = a + horiz * f0, a + horiz * f1
        pts = [c0 + side * (width * 0.5), c1 + side * (width * 0.5), c1 - side * (width * 0.5), c0 - side * (width * 0.5)]
        g.face([V(q.x, y, q.z) for q in pts], out=(0, 1, 0))
        g.face([V(q.x, y - 0.03, q.z) for q in reversed(pts)], out=(0, -1, 0))
    for sgn in (-1.0, 1.0):
        o = side * (sgn * (width * 0.5 + 0.04))
        top, bot = a + o, b + o
        pm.cyl(V(top.x, a.y - 0.12, top.z), V(bot.x, b.y - 0.12, bot.z), 0.06, segs=4, caps=True)
        railing_slope(m, a + side * (sgn * width * 0.5), b + side * (sgn * width * 0.5))


def railing_slope(m, a, b, height=1.0, posts=4):
    acc = m["TK_Galv"]
    a, b = Vector(a), Vector(b)
    for i in range(posts + 1):
        q = a + (b - a) * (i / posts)
        acc.cyl(V(q.x, q.y, q.z), V(q.x, q.y + height, q.z), 0.024, segs=6, caps=True)
    for h in (height, height * 0.5):
        acc.cyl(V(a.x, a.y + h, a.z), V(b.x, b.y + h, b.z), 0.022, segs=6, caps=True)


def build_stairs():
    m = Mod("T")
    cc = m["TK_Concrete"]
    vw = C.INNER_HALF
    pl, pd, ph = PORTAL
    vf = vw - pd
    ua, ub = DOOR_U - pl * 0.5, DOOR_U + pl * 0.5
    yt = Y5 + ph
    front = P(vf - 4.0, Y5 + 1.5, DOOR_U)
    # portal block on the shelf against the side wall (its foot hides the wall fillet)
    face_to(cc, (P(vf, Y5, ua), P(vf, Y5, ub), P(vf, yt, ub), P(vf, yt, ua)), front)
    for uu, du in ((ua, -1.0), (ub, 1.0)):
        face_to(cc, (P(vf, Y5, uu), P(vw, Y5, uu), P(vw, yt, uu), P(vf, yt, uu)), P(vf - 1.0, Y5 + 1.5, uu + du * 3.0))
    face_to(cc, (P(vf, yt, ua), P(vw, yt, ua), P(vw, yt, ub), P(vf, yt, ub)), P(vf, yt + 3.0, DOOR_U))
    # doorway (dark) with a steel frame, and the green exit light over it
    du0, du1 = DOOR_U - 1.0, DOOR_U + 1.0
    face_to(m["TK_Void"], (P(vf - 0.02, Y5, du0), P(vf - 0.02, Y5, du1), P(vf - 0.02, Y5 + 2.4, du1), P(vf - 0.02, Y5 + 2.4, du0)), front)
    st = m["TK_Steel"]
    abox(st, P(vf, Y5, du0 - 0.12), P(vf - 0.1, Y5 + 2.52, du0))
    abox(st, P(vf, Y5, du1), P(vf - 0.1, Y5 + 2.52, du1 + 0.12))
    abox(st, P(vf, Y5 + 2.4, du0), P(vf - 0.1, Y5 + 2.52, du1))
    abox(st, P(vf, Y5 + 2.62, DOOR_U - 0.4), P(vf - 0.14, Y5 + 2.92, DOOR_U + 0.4))
    face_to(m["TK_Lens"], (P(vf - 0.142, Y5 + 2.64, DOOR_U - 0.38), P(vf - 0.142, Y5 + 2.64, DOOR_U + 0.38), P(vf - 0.142, Y5 + 2.9, DOOR_U + 0.38), P(vf - 0.142, Y5 + 2.9, DOOR_U - 0.38)), front)
    m.lights.append(("Exit", tuple(P(vf - 0.6, Y5 + 2.6, DOOR_U)), tuple(Vector((1.0, -0.6, 0.0)).normalized()), {"name": "Door"}))
    # walkway across the shelf to the trench crest, railings both sides
    cr = C.crest(DOOR_U)
    for uu in (DOOR_U - 1.65, DOOR_U + 1.65):
        railing(m, P(vf - 0.2, Y5, uu), P(cr + 0.1, Y5, uu), Y5, post_step=1.8, toe=False)
    # steel stair into the trench: two flights with a landing, straight toward the centre line
    top = P(cr, Y5, DOOR_U)
    mid_top = P(cr - 3.6, Y5 * 0.5, DOOR_U)
    mid_bot = P(cr - 4.9, Y5 * 0.5, DOOR_U)
    bot = P(cr - 8.5, 0.0, DOOR_U)
    steel_flight(m, top, mid_top, STAIR_W)
    steel_flight(m, mid_bot, bot, STAIR_W)
    g = m["TK_Grate"]
    y_l = Y5 * 0.5
    l0, l1 = P(cr - 3.6, y_l, DOOR_U - STAIR_W * 0.5), P(cr - 4.9, y_l, DOOR_U + STAIR_W * 0.5)
    lx0, lx1 = sorted((l0.x, l1.x))
    lz0, lz1 = sorted((l0.z, l1.z))
    g.face((V(lx0, y_l, lz0), V(lx0, y_l, lz1), V(lx1, y_l, lz1), V(lx1, y_l, lz0)), out=(0, 1, 0))
    g.face((V(lx0, y_l - 0.03, lz0), V(lx1, y_l - 0.03, lz0), V(lx1, y_l - 0.03, lz1), V(lx0, y_l - 0.03, lz1)), out=(0, -1, 0))
    pm = m["TK_Paint"]
    for (px, pz) in ((lx0 + 0.06, lz0 + 0.06), (lx1 - 0.06, lz0 + 0.06), (lx0 + 0.06, lz1 - 0.06), (lx1 - 0.06, lz1 - 0.06)):
        pm.box((px - 0.06, 0.0, pz - 0.06), (px + 0.06, y_l, pz + 0.06))
    for uu in (DOOR_U - STAIR_W * 0.5, DOOR_U + STAIR_W * 0.5):
        railing(m, P(cr - 3.6, y_l, uu), P(cr - 4.9, y_l, uu), y_l, post_step=1.3, toe=False, height=1.0)
    # flood on the portal, lighting the walkway and the stair
    wall_lamp(m, 1.0, DOOR_U + 1.5, "Stair", y=yt - 0.1, vwall=vf, tilt=0.9)
    # bollards: the end of the visitor area toward the pumps
    for i in range(13):
        b0 = P(-15.0 + 2.5 * i, 0.0, 136.0)
        cc.box((b0.x - 0.18, 0.0, b0.z - 0.18), (b0.x + 0.18, 0.32, b0.z + 0.18), skip=("-y",))
    return m


# ------------------------------------------------------------------ objects, lights, anchors
def _finish(m, collection):
    out = []
    mt = mats()
    for name, acc in m.acc.items():
        if len(acc.bm.faces) == 0:
            acc.bm.free()
            continue
        obj = acc.to_object("%s|%s" % (m.tag, name), mt[name], collection, merge=(name not in ("TK_Galv", "TK_Paint", "TK_Steel")))
        obj["tk_part"] = PART[name]
        obj["tk_module"] = m.tag
        _sharp_by_angle(obj, 50.0)
        out.append(obj.name)
    return out


def _sharp_by_angle(obj, deg):
    """Edges between faces meeting at more than deg are sharp (split normals on export)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    lim = math.radians(deg)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a, b = e.link_faces
            e.smooth = not (a.normal.angle(b.normal, 0.0) > lim or not (a.smooth and b.smooth))
        else:
            e.smooth = False
    bm.to_mesh(me)
    bm.free()


LIGHT_SPEC = {
    # kind: (blender type, power W, size, spot deg, blend, colour K)
    # the LED high-bays as Lambertian discs (the lens, 0.45 m): their light reaches the pillar heads at grazing
    # angles, as in the official photo (a 150 deg spot left the upper pillars dark)
    "Bay": ("AREA", 800.0, 0.45, 0.0, 0.0, C.LAMP_K),
    "Wall": ("SPOT", 700.0, 0.15, 110.0, 0.5, C.WALL_LAMP_K),
    "Strip": ("AREA", 300.0, 0.0, 0.0, 0.0, C.WALL_LAMP_K),
    "Shaft": ("SPOT", 5000.0, 0.25, 70.0, 0.4, 5200.0),
    "Sky": ("AREA", 60000.0, 0.0, 0.0, 0.0, 6500.0),
    "Exit": ("SPOT", 60.0, 0.1, 150.0, 0.8, 0.0),
}


def _lights(m, collection):
    names = []
    for idx, (kind, pos, aim, prm) in enumerate(m.lights):
        typ, power, size, spot, blend, kelvin = LIGHT_SPEC[kind]
        tail = "%s_%s" % (kind, prm.get("name", str(idx)))
        lname = "%s|LGT_%s" % (m.tag, tail)
        ld = bpy.data.lights.get(lname)
        if ld is not None and ld.type != typ:
            bpy.data.lights.remove(ld)
            ld = None
        if ld is None:
            ld = bpy.data.lights.new(lname, typ)
        ld.energy = power
        ld.color = C.blackbody(kelvin) if kelvin > 0.0 else (0.05, 1.0, 0.25)
        if typ == "SPOT":
            ld.shadow_soft_size = size
            ld.spot_size = math.radians(spot)
            ld.spot_blend = blend
        elif typ == "AREA":
            if kind == "Sky":
                ld.shape = "DISK"
                ld.size = prm.get("radius", 9.0) * 2.0
            elif kind == "Bay":
                ld.shape = "DISK"
                ld.size = size
            else:
                ld.shape = "RECTANGLE"
                sx, sy = prm.get("size", (1.0, 0.2))
                ld.size, ld.size_y = sx, sy
        ld.use_shadow = True
        try:
            ld.cycles.cast_shadow = True
        except Exception:
            pass
        obj = bpy.data.objects.get(lname)
        if obj is None:
            obj = bpy.data.objects.new(lname, ld)
        else:
            obj.data = ld
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        collection.objects.link(obj)
        obj.location = C.g2b(pos)
        d = C.g2b(aim).normalized()
        obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        obj["tk_kind"] = kind
        names.append(lname)
        an = C.empty("%s|TK_Light_%s" % (m.tag, tail), collection, pos, aim_g=aim, size=0.25)
        an["tk_kind"] = kind
    return names


def module_tags():
    return ["K%02d" % k for k in range(C.LINES)] + ["P", "S", "Q", "T"]


def module_name(tag):
    if tag.startswith("K"):
        return "tank_line_%02d" % int(tag[1:])
    return {"P": "tank_end_pump", "S": "tank_end_shaft", "Q": "tank_shaft1", "T": "tank_stairs"}[tag]


def build_module(tag):
    import time
    t = time.time()
    root = C.collection("TK_Modules")
    col = C.collection("TK_" + tag, root)
    C.clear_collection(col)
    if tag.startswith("K"):
        m = build_slice(int(tag[1:]))
    elif tag == "P":
        m = build_pump_end()
    elif tag == "S":
        m = build_shaft_end()
    elif tag == "Q":
        m = build_shaft()
    elif tag == "T":
        m = build_stairs()
    else:
        raise ValueError(tag)
    objs = _finish(m, col)
    lights = _lights(m, col)
    tris = sum(C.tri_count(bpy.data.objects[n]) for n in objs)
    return {"module": module_name(tag), "objects": len(objs), "lights": len(lights), "triangles": tris, "secs": round(time.time() - t, 2)}


def rebuild_lights(tag):
    """Re-make the lights and anchors of a module from LIGHT_SPEC without touching its meshes (their UV2 atlases
    and bakes stay valid): the geometry is built in memory only to collect the lamp positions."""
    builders = {"P": build_pump_end, "S": build_shaft_end, "Q": build_shaft, "T": build_stairs}
    m = build_slice(int(tag[1:])) if tag.startswith("K") else builders[tag]()
    for acc in m.acc.values():
        acc.bm.free()
    col = bpy.data.collections["TK_" + tag]
    for obj in list(col.objects):
        if obj.type == "LIGHT" or (obj.type == "EMPTY" and "|TK_Light_" in obj.name):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data is not None and data.users == 0:
                bpy.data.lights.remove(data)
    return {"module": module_name(tag), "lights": len(_lights(m, col))}


def clear_old():
    """Remove the first build (slice templates E / O and their linked copies in TK_Hall) and orphaned data."""
    removed = []
    for name in ("TK_Hall", "TK_E", "TK_O"):
        col = bpy.data.collections.get(name)
        if col is None:
            continue
        C.clear_collection(col)
        for ch in list(col.children):
            bpy.data.collections.remove(ch)
        bpy.data.collections.remove(col)
        removed.append(name)
    for coll in (bpy.data.meshes, bpy.data.lights):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)
    return {"removed": removed}

"""Build the underground cistern modules (docs/sudden_death_m3_interface.md) in the LIVE Blender.

Run through the Higgsfield bl_execute connector, never in a headless Blender:

    ns = {"__name__": "cistern_build"}
    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/build_cistern.py",
              encoding="utf-8").read(), ns)
    ns["build_module"]("A")      # A, B, C (bays), O (opening), U (upstream end), D (downstream end)
    ns["setup_review"]()          # world, fog, cameras (preview only, never exported)

Every module lives in its own collection CIS_<TAG> with the meshes ("<TAG>|CIS_*"), the
light anchors ("<TAG>|CIS_Light_<kind>_<n>", exported) and the Blender lights used for the
lightmap bake ("<TAG>|LGT_*", not exported). Geometry is authored in Godot space (see
cistern_common.py). Bays are module-local (z -7.5..7.5); the two ends keep world z.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/cistern_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)
GAcc, V, NB = C.GAcc, C.V, C.NB
UV_WORLD, UV_FACE, UV_EXPLICIT = C.UV_WORLD, C.UV_FACE, C.UV_EXPLICIT
TAU = C.TAU

MODULES = {
    "A": {"name": "cistern_bay_a", "kind": "bay", "seed": 11},
    "B": {"name": "cistern_bay_b", "kind": "bay", "seed": 23},
    "C": {"name": "cistern_bay_c", "kind": "bay", "seed": 37},
    "O": {"name": "cistern_bay_opening", "kind": "opening", "seed": 5},
    "U": {"name": "cistern_end_upstream", "kind": "upstream", "seed": 71},
    "D": {"name": "cistern_end_downstream", "kind": "downstream", "seed": 83},
}

FLOOD_POWER = 2600.0     # W (Cycles), tuned against the look renders
AMBER_POWER = 70.0
WINDOW_POWER = 45.0
END_FLOOD_POWER = {"U": 1500.0, "D": 2400.0}   # end-wall floods (closer to what they light than the bay floods)
TUNNEL_LAMP_POWER = 14.0


# =============================================================== materials (names = contract)
MAT_NAMES = {
    "shell": "CIS_Concrete", "floor": "CIS_Floor", "steel": "CIS_SteelPaint", "galv": "CIS_Galvanized",
    "grate": "CIS_Grate", "lens": "CIS_LampLens", "amber": "CIS_LampLensAmber", "hazard": "CIS_Hazard",
    "sign": "CIS_Sign", "glass": "CIS_WindowGlass", "interior": "CIS_Interior", "dark": "CIS_Void",
}
OBJ_NAMES = {
    "shell": "CIS_Shell", "floor": "CIS_Floor", "steel": "CIS_Steel", "galv": "CIS_Galv", "grate": "CIS_Grate",
    "lens": "CIS_FloodLens", "amber": "CIS_AmberLens", "hazard": "CIS_Hazard", "sign": "CIS_Sign",
    "glass": "CIS_WindowGlass", "interior": "CIS_Interior", "dark": "CIS_Void",
}
SCALES = {
    "shell": C.S_CONCRETE, "floor": C.S_FLOOR, "steel": C.S_STEEL, "galv": C.S_GALV, "grate": C.S_GRATE,
    "lens": 1.0, "amber": 1.0, "hazard": C.S_HAZARD, "sign": 1.0, "glass": 1.0, "interior": C.S_CONCRETE, "dark": 1.0,
}


def material(key):
    name = MAT_NAMES[key]
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
    return mat


# =============================================================== small helpers
def frame_from(d, up=(0.0, 1.0, 0.0)):
    """3x3 with columns (side, up', fwd) for a forward direction d (Godot space)."""
    d = Vector(d).normalized()
    u = Vector(up)
    u = (u - d * u.dot(d))
    if u.length < 1e-6:
        u = Vector((0.0, 0.0, 1.0)) - d * d.z
    u.normalize()
    s = u.cross(d).normalized()
    return Matrix((s, u, d)).transposed()


def at(M, origin, local):
    return Vector(origin) + M @ Vector(local)


# =============================================================== concrete shell parts
def pillar(acc, cx, z0=C.PILLAR_Z0, z1=C.PILLAR_Z1, hw=C.PILLAR_HW, top=C.CEIL_Y, offu=0.0, joints=None):
    hd = (z1 - z0) * 0.5
    cz = (z0 + z1) * 0.5
    c = C.CHAMFER

    def ring(y, inset):
        a, b = hw - inset, hd - inset
        pts = [(a, b - c), (a - c, b), (-a + c, b), (-a, b - c), (-a, -b + c), (-a + c, -b), (a - c, -b), (a, -b + c)]
        return [V(cx + px, y, cz + pz) for (px, pz) in pts]

    stations = [(0.0, 0.0)]
    for h in (joints if joints is not None else (C.KICKER,) + C.COLD_JOINTS):
        if h >= top - 0.1:
            continue
        stations += [(h - C.JOINT_G, 0.0), (h, C.JOINT_D), (h + C.JOINT_G, 0.0)]
    stations.append((top, 0.0))
    rings = [ring(y, d) for (y, d) in stations]
    acc.rings(rings, closed=True, center_fn=lambda m: V(cx, m.y, cz), mode=UV_FACE, offu=offu)


def wall_grid(acc, plane_fn, us, vs, inset_u, inset_v, outward, mode=UV_WORLD, offu=0.0):
    """Grid surface: plane_fn(u, v, depth) -> point; insets per station give real grooves."""
    for i in range(len(us) - 1):
        for j in range(len(vs) - 1):
            pts = []
            for (a, b) in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)):
                d = max(inset_u[a], inset_v[b])
                pts.append(plane_fn(us[a], vs[b], d))
            acc.face(pts, out=outward, mode=mode, offu=offu)


def joint_stations(lo, hi, joints, end_half=False):
    """Stations (value, inset) between lo and hi with V-grooves at the joints; end_half puts a
    half groove at both ends (expansion joints on the module boundary)."""
    st = []
    if end_half:
        st += [(lo, C.JOINT_D), (lo + C.JOINT_G, 0.0)]
    else:
        st.append((lo, 0.0))
    for h in joints:
        if lo + 0.05 < h < hi - 0.05:
            st += [(h - C.JOINT_G, 0.0), (h, C.JOINT_D), (h + C.JOINT_G, 0.0)]
    if end_half:
        st += [(hi - C.JOINT_G, 0.0), (hi, C.JOINT_D)]
    else:
        st.append((hi, 0.0))
    return [s[0] for s in st], [s[1] for s in st]


def side_wall(acc, side, z0=-C.HB, z1=C.HB, expansion=True):
    x = side * C.HALF_W
    ys, iy = joint_stations(0.0, C.CEIL_Y, (C.KICKER,) + C.COLD_JOINTS)
    zs, iz = joint_stations(z0, z1, (), end_half=expansion)
    wall_grid(acc, lambda z, y, d: V(x + side * d, y, z), zs, ys, iz, iy, V(-side, 0, 0))


def beam_x(acc, xa, xb, z0, z1, bottom, haunch_a=True, haunch_b=True, hl=C.TB_HAUNCH[0], hd=C.TB_HAUNCH[1], ch=C.BEAM_CH):
    """Transverse beam segment along x between two supports (faces: bottom, chamfers, sides)."""
    stations = [xa]
    if haunch_a:
        stations.append(xa + hl)
    if haunch_b:
        stations.append(xb - hl)
    stations.append(xb)
    stations = sorted(set(round(s, 5) for s in stations))

    def yb(x):
        y = bottom
        if haunch_a and x < xa + hl:
            y -= hd * (1.0 - (x - xa) / hl)
        if haunch_b and x > xb - hl:
            y -= hd * (1.0 - (xb - x) / hl)
        return y

    for a, b in zip(stations[:-1], stations[1:]):
        ya, yb_ = yb(a), yb(b)
        # bottom
        acc.face((V(a, ya, z0 + ch), V(b, yb_, z0 + ch), V(b, yb_, z1 - ch), V(a, ya, z1 - ch)), out=V(0, -1, 0))
        # chamfers
        acc.face((V(a, ya, z0 + ch), V(a, ya + ch, z0), V(b, yb_ + ch, z0), V(b, yb_, z0 + ch)), out=V(0, -1, -1))
        acc.face((V(a, ya, z1 - ch), V(b, yb_, z1 - ch), V(b, yb_ + ch, z1), V(a, ya + ch, z1)), out=V(0, -1, 1))
        # sides up to the soffit
        acc.face((V(a, ya + ch, z0), V(a, C.CEIL_Y, z0), V(b, C.CEIL_Y, z0), V(b, yb_ + ch, z0)), out=V(0, 0, -1))
        acc.face((V(a, ya + ch, z1), V(b, yb_ + ch, z1), V(b, C.CEIL_Y, z1), V(a, C.CEIL_Y, z1)), out=V(0, 0, 1))


def beam_z(acc, x0, x1, za, zb, bottom, haunch_a, haunch_b, hl=C.LB_HAUNCH[0], hd=C.LB_HAUNCH[1], ch=C.BEAM_CH):
    """Longitudinal beam segment along z (flush with the pillar faces)."""
    stations = [za]
    if haunch_a:
        stations.append(min(zb, za + hl))
    if haunch_b:
        stations.append(max(za, zb - hl))
    stations.append(zb)
    stations = sorted(set(round(s, 5) for s in stations))

    def yb(z):
        y = bottom
        if haunch_a and z < za + hl:
            y -= hd * (1.0 - (z - za) / hl)
        if haunch_b and z > zb - hl:
            y -= hd * (1.0 - (zb - z) / hl)
        return y

    for a, b in zip(stations[:-1], stations[1:]):
        ya, yb_ = yb(a), yb(b)
        acc.face((V(x0 + ch, ya, a), V(x1 - ch, ya, a), V(x1 - ch, yb_, b), V(x0 + ch, yb_, b)), out=V(0, -1, 0))
        acc.face((V(x0 + ch, ya, a), V(x0 + ch, yb_, b), V(x0, yb_ + ch, b), V(x0, ya + ch, a)), out=V(-1, -1, 0))
        acc.face((V(x1 - ch, ya, a), V(x1, ya + ch, a), V(x1, yb_ + ch, b), V(x1 - ch, yb_, b)), out=V(1, -1, 0))
        acc.face((V(x0, ya + ch, a), V(x0, yb_ + ch, b), V(x0, C.CEIL_Y, b), V(x0, C.CEIL_Y, a)), out=V(-1, 0, 0))
        acc.face((V(x1, ya + ch, a), V(x1, C.CEIL_Y, a), V(x1, C.CEIL_Y, b), V(x1, yb_ + ch, b)), out=V(1, 0, 0))


def x_gaps():
    """Free x intervals between pillar columns and walls (for beams / soffit cells)."""
    edges = [-C.HALF_W]
    for px in sorted([-p for p in C.PILLAR_X] + list(C.PILLAR_X)):
        edges += [px - C.PILLAR_HW, px + C.PILLAR_HW]
    edges.append(C.HALF_W)
    return [(edges[i], edges[i + 1]) for i in range(0, len(edges), 2)]


def soffit_cell(acc, x0, x1, z0, z1, hole=None, segs=96):
    y = C.CEIL_Y
    if hole is None:
        acc.face((V(x0, y, z0), V(x0, y, z1), V(x1, y, z1), V(x1, y, z0)), out=V(0, -1, 0))
        return
    cx, cz, r = hole
    angles = set(TAU * i / segs for i in range(segs))
    corners = [(x1, z1), (x0, z1), (x0, z0), (x1, z0)]
    for (px, pz) in corners:
        angles.add(math.atan2(pz - cz, px - cx) % TAU)
    angles = sorted(angles)

    def boundary(a):
        dx, dz = math.cos(a), math.sin(a)
        ts = []
        if abs(dx) > 1e-9:
            ts += [(x1 - cx) / dx, (x0 - cx) / dx]
        if abs(dz) > 1e-9:
            ts += [(z1 - cz) / dz, (z0 - cz) / dz]
        t = min(t for t in ts if t > 0)
        return V(cx + dx * t, y, cz + dz * t)

    n = len(angles)
    for i in range(n):
        a0, a1 = angles[i], angles[(i + 1) % n]
        p0 = V(cx + r * math.cos(a0), y, cz + r * math.sin(a0))
        p1 = V(cx + r * math.cos(a1), y, cz + r * math.sin(a1))
        acc.face((p0, p1, boundary(a1), boundary(a0)), out=V(0, -1, 0))


# =============================================================== floor
def floor_grid(acc, xs, zs, skip, y=0.0):
    for i in range(len(xs) - 1):
        for j in range(len(zs) - 1):
            cx = (xs[i] + xs[i + 1]) * 0.5
            cz = (zs[j] + zs[j + 1]) * 0.5
            if skip(cx, cz):
                continue
            acc.face((V(xs[i], y, zs[j]), V(xs[i], y, zs[j + 1]), V(xs[i + 1], y, zs[j + 1]), V(xs[i + 1], y, zs[j])), out=V(0, 1, 0))


def steps(a, b, step):
    n = max(1, int(round(abs(b - a) / step)))
    return [a + (b - a) * k / n for k in range(n + 1)]


def floor_xs():
    xs = set()
    for s in (-1, 1):
        for v in steps(0.0, C.CH_X[0] - 0.04, 0.52):
            xs.add(round(s * v, 5))
        for v in (C.CH_X[1] + 0.04, C.CORR_X):
            xs.add(round(s * v, 5))
        outer = [C.CORR_X]
        for px in C.PILLAR_X:
            outer += [px - C.PILLAR_HW, px + C.PILLAR_HW]
        outer.append(C.HALF_W)
        for a, b in zip(outer[:-1], outer[1:]):
            for v in steps(a, b, 1.1):
                xs.add(round(s * v, 5))
    return sorted(xs)


def in_pillar(x, z, z0=C.PILLAR_Z0, z1=C.PILLAR_Z1):
    if not (z0 < z < z1):
        return False
    for px in C.PILLAR_X:
        if abs(abs(x) - px) < C.PILLAR_HW:
            return True
    return False


def in_channel(x):
    return C.CH_X[0] - 0.04 < abs(x) < C.CH_X[1] + 0.04


def channels(acc, galv, grate, z0=-C.HB, z1=C.HB):
    d = C.CH_DEPTH
    for s in (-1, 1):
        xa, xb = s * C.CH_X[0], s * C.CH_X[1]
        lo, hi = min(xa, xb), max(xa, xb)
        # channel walls and invert (wet concrete)
        acc.face((V(lo, 0, z0), V(lo, -d, z0), V(lo, -d, z1), V(lo, 0, z1)), out=V(1, 0, 0))
        acc.face((V(hi, 0, z0), V(hi, 0, z1), V(hi, -d, z1), V(hi, -d, z0)), out=V(-1, 0, 0))
        acc.face((V(lo, -d, z0), V(hi, -d, z0), V(hi, -d, z1), V(lo, -d, z1)), out=V(0, 1, 0))
        # steel nosing angles flush with the floor
        for (e, o) in ((lo, -1), (hi, 1)):
            x_out = e + o * 0.04
            galv.face((V(min(e, x_out), 0.001, z0), V(min(e, x_out), 0.001, z1), V(max(e, x_out), 0.001, z1), V(max(e, x_out), 0.001, z0)), out=V(0, 1, 0))
            el = e - o * 0.004
            galv.face((V(el, 0.001, z0), V(el, -0.07, z0), V(el, -0.07, z1), V(el, 0.001, z1)), out=V(-o, 0, 0))
        # grating (alpha-tested) resting just below the floor plane
        y = -0.006
        grate.face((V(lo, y, z0), V(lo, y, z1), V(hi, y, z1), V(hi, y, z0)),
            uv=((0.0, z0 / C.S_GRATE), (0.0, z1 / C.S_GRATE), ((hi - lo) / C.S_GRATE, z1 / C.S_GRATE), ((hi - lo) / C.S_GRATE, z0 / C.S_GRATE)),
            out=V(0, 1, 0))


# =============================================================== fixtures
def floodlight(A, mount, out_dir, aim, cond_top=None):
    """Caged LED floodlight on a vertical face. mount: point on the face; out_dir: face normal;
    aim: beam direction. Returns the lens-centre (light anchor) position."""
    steel, galv, lens = A["steel"], A["galv"], A["lens"]
    o = Vector(mount)
    n = Vector(out_dir).normalized()
    Mw = frame_from(n)                       # wall frame: x side, y up, z out
    tint = C.TINT["fixture"]
    # wall plate + bolts + junction box
    steel.obox(at(Mw, o, (0, 0, 0.012)), (0.40, 0.56, 0.024), Mw, color=tint)
    for sx in (-0.15, 0.15):
        for sy in (-0.22, 0.22):
            galv.cyl(at(Mw, o, (sx, sy, 0.024)), at(Mw, o, (sx, sy, 0.05)), 0.012, 6)
    steel.obox(at(Mw, o, (0.0, 0.42, 0.06)), (0.18, 0.16, 0.10), Mw, color=tint)
    # yoke: base bar + two arms reaching the housing pivots
    pivot = o + n * 0.30
    Mh = frame_from(aim)
    half_w = 0.30
    for s in (-1, 1):
        side_pt = pivot + Mh.col[0] * (s * (half_w + 0.03))
        base_pt = o + n * 0.03 + Mw.col[0] * (s * (half_w + 0.03))
        steel.obox((base_pt + side_pt) * 0.5, (0.012, 0.05, (side_pt - base_pt).length + 0.03), frame_from(side_pt - base_pt), color=tint)
        galv.cyl(side_pt - Mh.col[0] * 0.03 * s, side_pt + Mh.col[0] * 0.02 * s, 0.03, 10)
    steel.obox(o + n * 0.035, (2 * half_w + 0.1, 0.06, 0.02), Mw, color=tint)
    # housing (tilted), heat-sink fins on the back
    hc = pivot
    steel.obox(hc, (0.58, 0.44, 0.14), Mh, color=tint)
    for k in range(9):
        fy = -0.18 + 0.045 * k
        steel.obox(at(Mh, hc, (0.0, fy, -0.10)), (0.54, 0.012, 0.07), Mh, color=tint)
    # bezel and lens
    front = at(Mh, hc, (0, 0, 0.07))
    for (cx, cy, sx, sy) in ((0, 0.205, 0.58, 0.03), (0, -0.205, 0.58, 0.03), (0.275, 0, 0.03, 0.38), (-0.275, 0, 0.03, 0.38)):
        steel.obox(at(Mh, front, (cx, cy, 0.012)), (sx, sy, 0.024), Mh, color=tint)
    lens.face([at(Mh, front, p) for p in ((-0.26, -0.19, 0.017), (0.26, -0.19, 0.017), (0.26, 0.19, 0.017), (-0.26, 0.19, 0.017))],
        out=Mh.col[2], uv=((0, 0), (1, 0), (1, 1), (0, 1)))
    # wire guard: frame + bars
    gz = 0.075
    for (cx, cy, sx, sy) in ((0, 0.205, 0.56, 0.012), (0, -0.205, 0.56, 0.012), (0.275, 0, 0.012, 0.42), (-0.275, 0, 0.012, 0.42)):
        galv.obox(at(Mh, front, (cx, cy, gz)), (sx, sy, 0.012), Mh)
    for k in range(5):
        cx = -0.2 + 0.1 * k
        galv.obox(at(Mh, front, (cx, 0, gz)), (0.007, 0.40, 0.007), Mh)
    for cy in (-0.07, 0.07):
        galv.obox(at(Mh, front, (0, cy, gz)), (0.54, 0.007, 0.007), Mh)
    for (cx, cy) in ((0.275, 0.205), (-0.275, 0.205), (0.275, -0.205), (-0.275, -0.205)):
        galv.obox(at(Mh, front, (cx, cy, gz * 0.5)), (0.012, 0.012, gz), Mh)
    # conduit from the junction box up to the tray
    if cond_top is not None:
        jb = at(Mw, o, (0.0, 0.50, 0.06))
        galv.cyl(jb, V(jb.x, cond_top, jb.z), 0.022, 8, caps=False)
    return front + Mh.col[2] * 0.03


def amber_lamp(A, mount, out_dir, lit=True):
    """Caged bulkhead safety lamp (amber well-glass along the face normal)."""
    steel, galv = A["steel"], A["galv"]
    o = Vector(mount)
    n = Vector(out_dir).normalized()
    M = frame_from(n)
    tint = C.TINT["yellow"]
    steel.obox(at(M, o, (0, 0, 0.015)), (0.20, 0.26, 0.03), M, color=tint)
    steel.obox(at(M, o, (0, 0.17, 0.04)), (0.09, 0.08, 0.07), M, color=tint)          # gland box
    Mz = M @ Matrix.Rotation(math.pi * 0.5, 3, "X")                                     # lathe axis -> out
    prof = [(0.0, 0.135), (0.035, 0.135), (0.062, 0.12), (0.066, 0.095), (0.066, 0.06)]
    glass_prof = [(0.0, 0.185), (0.03, 0.183), (0.052, 0.17), (0.058, 0.15), (0.058, 0.11)]
    base = [(0.088, 0.055), (0.088, 0.03), (0.0, 0.03)]
    MM = Matrix.Translation(o) @ Mz.to_4x4()
    # flipped lathe: profile heights along the local +Y = out
    A["amber" if lit else "steel"].lathe(glass_prof, 16, MM, **({} if lit else {"color": (0.06, 0.04, 0.02)}))
    steel.lathe([(0.0, 0.06), (0.09, 0.06), (0.09, 0.03), (0.07, 0.03)], 16, MM, color=tint)
    # cage: 4 bars along the axis + ring
    for k in range(4):
        a = TAU * (k + 0.5) / 4
        p0 = o + n * 0.06 + (M.col[0] * math.cos(a) + M.col[1] * math.sin(a)) * 0.074
        p1 = o + n * 0.175 + (M.col[0] * math.cos(a) + M.col[1] * math.sin(a)) * 0.05
        p2 = o + n * 0.198
        galv.tube([p0, p1, p2], 0.005, 4, caps=False)
    ring = [o + n * 0.12 + (M.col[0] * math.cos(TAU * i / 12) + M.col[1] * math.sin(TAU * i / 12)) * 0.072 for i in range(12)]
    galv.tube(ring, 0.005, 4, closed=True)
    return o + n * 0.13


def ladder_tray(galv, steel, x_in, x_out, y, z0, z1, rung=0.3, cables=3, side=1):
    """Ladder-type cable tray along z between x_in and x_out (bottom at y)."""
    lo, hi = min(x_in, x_out), max(x_in, x_out)
    for xr in (lo, hi):
        galv.box((xr - 0.006, y, z0), (xr + 0.006, y + 0.10, z1))
        galv.box((xr - 0.03, y, z0), (xr + 0.03, y + 0.008, z1), skip=("-z", "+z"))
    n = int(round((z1 - z0) / rung))
    for k in range(n):
        z = z0 + (k + 0.5) * rung
        galv.box((lo, y + 0.005, z - 0.02), (hi, y + 0.02, z + 0.02))
    w = hi - lo
    for k in range(cables):
        r = 0.028 + 0.008 * (k % 2)
        x = lo + w * (0.2 + 0.6 * k / max(1, cables - 1))
        steel.cyl(V(x, y + 0.02 + r, z0), V(x, y + 0.02 + r, z1), r, 6, caps=False, color=C.TINT["black"])


def wall_pipe(galv, steel, x, y, r, z0, z1, side, supports, flanges=()):
    galv.cyl(V(x, y, z0), V(x, y, z1), r, 14, caps=False)
    wall_x = side * C.HALF_W
    for z in supports:
        # saddle bracket: wall plate + arm + strap
        steel.box((min(wall_x, x) - 0.0 + (0.0 if side < 0 else 0.0), y - r - 0.05, z - 0.04),
                  (max(wall_x, x), y - r - 0.03, z + 0.04), color=C.TINT["grey"])
        steel.box((wall_x - side * 0.012 - 0.006, y - r - 0.12, z - 0.07), (wall_x - side * 0.012 + 0.006, y + 0.05, z + 0.07), color=C.TINT["grey"])
        ring = [V(x + (r + 0.008) * math.cos(TAU * i / 12), y + (r + 0.008) * math.sin(TAU * i / 12), z) for i in range(7)]
        galv.sweep(ring, [(-0.004, -0.02), (0.004, -0.02), (0.004, 0.02), (-0.004, 0.02)], up=V(0, 0, 1))
    for z in flanges:
        galv.cyl(V(x, y, z - 0.025), V(x, y, z + 0.025), r + 0.06, 16)
        for k in range(8):
            a = TAU * (k + 0.5) / 8
            galv.cyl(V(x + (r + 0.035) * math.cos(a), y + (r + 0.035) * math.sin(a), z - 0.045),
                     V(x + (r + 0.035) * math.cos(a), y + (r + 0.035) * math.sin(a), z + 0.045), 0.011, 6)


def railing(galv, x, z_from, z_to, posts, y_top=1.1, y_mid=0.55, base_plates=True):
    galv.cyl(V(x, y_top, z_from), V(x, y_top, z_to), 0.024, 8, caps=False)
    galv.cyl(V(x, y_mid, z_from), V(x, y_mid, z_to), 0.019, 8, caps=False)
    for z in posts:
        galv.cyl(V(x, 0.0, z), V(x, y_top, z), 0.024, 8, caps=True)
        if base_plates:
            galv.box((x - 0.09, 0.0, z - 0.09), (x + 0.09, 0.012, z + 0.09), skip=("-y",))


# =============================================================== bay
def bay_geometry(A, tag, variant, opening=False, z_range=(-C.HB, C.HB)):
    shell, floor, steel, galv, grate = A["shell"], A["floor"], A["steel"], A["galv"], A["grate"]
    z0, z1 = z_range
    # --- pillars (6), per-pillar panel offset so neighbours show different panels
    for s in (-1, 1):
        for k, px in enumerate(C.PILLAR_X):
            pillar(shell, s * px, offu=0.25 * ((k * 3 + (s > 0) + variant) % 4))
    # --- outer walls
    for s in (-1, 1):
        side_wall(shell, s)
    # --- beams
    for (xa, xb) in x_gaps():
        if opening and xa < 0 < xb:
            continue
        beam_x(shell, xa, xb, C.TB_Z[0], C.TB_Z[1], C.TB_BOTTOM)
    for s in (-1, 1):
        for px in C.PILLAR_X:
            x0, x1 = s * px - C.PILLAR_HW, s * px + C.PILLAR_HW
            beam_z(shell, x0, x1, C.PILLAR_Z1, z1, C.LB_BOTTOM, True, False)
            beam_z(shell, x0, x1, z0, C.PILLAR_Z0, C.LB_BOTTOM, False, True)
    # --- soffit cells
    for (xa, xb) in x_gaps():
        if opening and xa < 0 < xb:
            soffit_cell(shell, xa, xb, z0, z1, hole=(0.0, 0.0, C.OPENING_R))
        else:
            soffit_cell(shell, xa, xb, z0, C.TB_Z[0])
            soffit_cell(shell, xa, xb, C.TB_Z[1], z1)
    # --- floor and channels
    zs = steps(z0, z1, 0.5)
    floor_grid(floor, floor_xs(), zs, lambda x, z: in_pillar(x, z) or in_channel(x))
    channels(floor, galv, grate, z0, z1)
    # --- corridor railings (in line with the inner pillars, between the rows)
    for s in (-1, 1):
        x = s * C.PILLAR_X[0]
        railing(galv, x, C.PILLAR_Z1, z1, [])
        railing(galv, x, z0, C.PILLAR_Z0, [-6.0, -4.0, -2.0])
        for zz in (C.PILLAR_Z1, C.PILLAR_Z0):
            for y in (1.1, 0.55):
                galv.box((x - 0.06, y - 0.06, zz - (0.012 if zz == C.PILLAR_Z0 else -0.012) - 0.006), (x + 0.06, y + 0.06, zz - (0.012 if zz == C.PILLAR_Z0 else -0.012) + 0.006))
    # --- cable trays on the corridor faces of the inner pillars, conduits to the floods
    tray_y = 15.0
    for s in (-1, 1):
        x_in, x_out = s * (C.CORR_X - 0.05), s * (C.CORR_X - 0.55)
        ladder_tray(galv, steel, x_in, x_out, tray_y, z0, z1, side=s)
        for z in (0.75, 3.5, 6.25):       # brackets on the pillar face
            steel.box((min(s * C.CORR_X, s * (C.CORR_X - 0.62)), tray_y - 0.05, z - 0.03), (max(s * C.CORR_X, s * (C.CORR_X - 0.62)), tray_y - 0.005, z + 0.03), color=C.TINT["grey"])
            steel.box((min(s * C.CORR_X, s * (C.CORR_X - 0.012)), tray_y - 0.35, z - 0.05), (max(s * C.CORR_X, s * (C.CORR_X - 0.012)), tray_y + 0.05, z + 0.05), color=C.TINT["grey"])
            steel.cyl(V(s * (C.CORR_X - 0.01), tray_y - 0.33, z), V(s * (C.CORR_X - 0.5), tray_y - 0.04, z), 0.012, 6, color=C.TINT["grey"])
        for z in (-6.25, -3.75, -1.25):   # trapeze hangers from the beam face in the gap
            xb = s * C.CORR_X
            steel.box((min(xb, s * (C.CORR_X - 0.7)), 16.62, z - 0.03), (max(xb, s * (C.CORR_X - 0.7)), 16.68, z + 0.03), color=C.TINT["grey"])
            steel.box((min(xb, s * (C.CORR_X - 0.62)), tray_y - 0.05, z - 0.03), (max(xb, s * (C.CORR_X - 0.62)), tray_y - 0.005, z + 0.03), color=C.TINT["grey"])
            for xr in (C.CORR_X - 0.02, C.CORR_X - 0.6):
                galv.cyl(V(s * xr, tray_y - 0.05, z), V(s * xr, 16.62, z), 0.008, 6, caps=False)
    # --- outer-wall services: two pipes low, a ladder tray high
    for s in (-1, 1):
        sup = [-6.0, -3.0, 0.0, 3.0, 6.0]
        wall_pipe(galv, steel, s * (C.HALF_W - 0.36), 2.2, 0.20, z0, z1, s, sup, flanges=(-3.75, 3.75))
        wall_pipe(galv, steel, s * (C.HALF_W - 0.30), 2.95, 0.11, z0, z1, s, sup, flanges=(1.5,))
        ladder_tray(galv, steel, s * (C.HALF_W - 0.05), s * (C.HALF_W - 0.60), 9.5, z0, z1, side=s, cables=2)
        for k in range(10):
            z = z0 + 0.75 + 1.5 * k
            steel.box((min(s * C.HALF_W, s * (C.HALF_W - 0.66)), 9.45, z - 0.025), (max(s * C.HALF_W, s * (C.HALF_W - 0.66)), 9.5, z + 0.025), color=C.TINT["grey"])
    # --- lights
    lights = []
    for i, s in enumerate((-1, 1)):
        mount = V(s * C.CORR_X, C.FLOOD_Y, C.FLOOD_Z)
        aim = (V(-s * 1.5, 0.0, C.FLOOD_Z) - (mount + V(-s * 0.45, 0, 0))).normalized()
        p = floodlight(A, mount, V(-s, 0, 0), aim, cond_top=tray_y)
        lights.append(("Flood", p, aim))
    amber = [(V(-C.PILLAR_X[1] + C.PILLAR_HW, 3.0, 3.5), V(1, 0, 0)), (V(C.PILLAR_X[1] - C.PILLAR_HW, 3.0, 3.5), V(-1, 0, 0)),
             (V(-C.PILLAR_X[2] + C.PILLAR_HW, 3.0, 3.5), V(1, 0, 0)), (V(C.PILLAR_X[2] - C.PILLAR_HW, 3.0, 3.5), V(-1, 0, 0)),
             (V(-C.HALF_W, 3.4, -3.75), V(1, 0, 0)), (V(C.HALF_W, 3.4, -3.75), V(-1, 0, 0))]
    dead = {1: (5,), 2: (2,)}.get(variant, ())
    for i, (m, n) in enumerate(amber):
        lit = i not in dead
        p = amber_lamp(A, m, n, lit=lit)
        if lit:
            lights.append(("Amber", p, n))
    return lights


# =============================================================== bay variant props
def props(A, variant):
    steel, galv, shell = A["steel"], A["galv"], A["shell"]
    if variant == 0:
        # electrical panel on the upstream face of the left inner pillar + a fire-hose cabinet
        steel.box((-13.75, 0.9, -0.32), (-12.05, 2.5, 0.0), color=C.TINT["green"])
        steel.box((-13.7, 2.5, -0.30), (-12.1, 2.56, -0.02), color=C.TINT["green"])
        galv.cyl(V(-12.4, 2.56, -0.16), V(-12.4, C.TB_BOTTOM - 0.4, -0.16), 0.03, 8, caps=False)
        steel.box((24.0, 0.8, 0.1), (24.8, 1.9, 1.0), color=C.TINT["red"])
        # spare cable drum lying by the right middle pillar
        steel.cyl(V(23.4, 0.6, 9.5), V(23.4, 0.6, 10.4), 0.6, 20, color=C.TINT["grey"])
        steel.cyl(V(23.4, 0.6, 9.62), V(23.4, 0.6, 10.28), 0.42, 16, color=C.TINT["black"])
    elif variant == 1:
        # steel drums against the left middle pillar, fixed caged ladder on the right outer pillar
        for k, (x, z) in enumerate(((-23.9, 1.2), (-23.9, 2.0), (-23.15, 1.6), (-23.85, 5.2))):
            col = C.TINT["blue"] if k % 2 == 0 else C.TINT["orange"]
            steel.cyl(V(x, 0.0, z), V(x, 0.88, z), 0.29, 16, color=col)
            steel.cyl(V(x, 0.29, z), V(x, 0.31, z), 0.30, 16, caps=False, color=col)
            steel.cyl(V(x, 0.58, z), V(x, 0.60, z), 0.30, 16, caps=False, color=col)
        x = C.PILLAR_X[2] - C.PILLAR_HW - 0.18
        for rx in (-0.25, 0.25):
            steel.box((x - 0.03, 0.0, 3.5 + rx - 0.03), (x + 0.03, 16.0, 3.5 + rx + 0.03), color=C.TINT["yellow"])
        for k in range(52):
            y = 0.3 + 0.3 * k
            galv.cyl(V(x, y, 3.25), V(x, y, 3.75), 0.014, 6, caps=False)
        for k in range(8):
            y = 2.6 + 1.8 * k
            hoop = [V(x - 0.02 - 0.36 * math.sin(math.pi * i / 10), y, 3.5 - 0.36 * math.cos(math.pi * i / 10)) for i in range(11)]
            steel.tube(hoop, 0.012, 5, caps=False, color=C.TINT["yellow"])
    else:
        # sandbag berm + rubble by the left wall, suction hose snaking to a sump
        import random as _r
        rnd = _r.Random(7)
        for row in range(3):
            for k in range(9 - row * 2):
                z = -5.2 + row * 0.25 + k * 0.62
                x = -C.HALF_W + 1.1 + row * 0.08
                y = 0.13 + row * 0.24
                Mz = Matrix.Rotation(rnd.uniform(-0.12, 0.12), 3, "Y")
                steel.obox(V(x, y, z), (0.42, 0.24, 0.6), Mz, color=(0.30, 0.27, 0.20))
        for k in range(14):
            p = V(-C.HALF_W + 2.5 + rnd.uniform(0, 3.0), 0.0, -6.0 + rnd.uniform(0, 5.0))
            sz = rnd.uniform(0.25, 0.7)
            Mr = Matrix.Rotation(rnd.uniform(0, TAU), 3, "Y") @ Matrix.Rotation(rnd.uniform(-0.4, 0.4), 3, "X")
            shell.obox(V(p.x, sz * 0.35, p.z), (sz, sz * 0.7, sz * 0.9), Mr)
        path = [V(-C.HALF_W + 0.5, 2.0, 4.0), V(-C.HALF_W + 0.9, 0.12, 4.4), V(-41.5, 0.1, 5.5), V(-40.2, 0.1, 4.6), V(-39.0, 0.1, 6.4), V(-36.5, 0.1, 6.8)]
        steel.tube(path, 0.1, 10, color=C.TINT["black"])


# =============================================================== light objects
def make_light(tag, kind, idx, pos_g, aim_g, col, power=None):
    name = "%s|LGT_%s_%d" % (tag, kind, idx)
    data = bpy.data.lights.get(name)
    ltype = "SPOT" if kind == "Flood" else ("AREA" if kind == "Room" else "POINT")
    if data is not None and data.type != ltype:
        bpy.data.lights.remove(data)
        data = None
    if data is None:
        data = bpy.data.lights.new(name, ltype)
    if kind == "Flood":
        data.energy = END_FLOOD_POWER.get(tag, FLOOD_POWER)
        data.color = C.blackbody(C.FLOOD_K)
        data.spot_size = math.radians(118.0)
        data.spot_blend = 0.45
        data.shadow_soft_size = 0.16
    elif kind == "Amber":
        data.energy = AMBER_POWER if power is None else power
        data.color = C.blackbody(C.AMBER_K)
        data.shadow_soft_size = 0.04
    else:
        data.energy = WINDOW_POWER
        data.color = C.blackbody(C.WINDOW_K)
        data.shape = "RECTANGLE"
        data.size = 4.0
        data.size_y = 1.2
    obj = bpy.data.objects.get(name) or bpy.data.objects.new(name, data)
    obj.data = data
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)
    obj.location = C.g2b(pos_g)
    d = C.g2b(aim_g).normalized()
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    obj["cis_kind"] = kind
    return obj


# =============================================================== module assembly
def new_accs():
    return {k: GAcc(SCALES[k], color=(1.0, 1.0, 1.0, 1.0)) for k in OBJ_NAMES}


def floor_colour_fn(seed, kind="bay"):
    """Floor COLOR_0: R standing water (puddle), G damp/wet darkening, B silt/mud.

    Within 1 m of the module ends every variant uses the same x-only field, so any bay
    order joins without a seam."""
    def fn(co, f):
        x, y, z = co.x, co.y, co.z
        if y < -0.02:
            return (0.85, 1.0, 0.7, 1.0)
        w = C.smoothstep(6.3, 7.5, abs(z)) if kind == "bay" else 0.0
        nv = C.fbm((x * 0.24, 0.0, z * 0.24), 4, seed)
        nc = C.fbm((x * 0.24, 0.0, 0.0), 4, 99.0)
        n = nv * (1.0 - w) + nc * w
        ax = abs(x)
        near_ch = C.smoothstep(8.6, 10.3, ax) * (1.0 - C.smoothstep(11.0, 11.9, ax))
        mid = 1.0 - C.smoothstep(2.5, 6.0, ax)
        outer = C.smoothstep(12.0, 16.0, ax)
        near_wall = C.smoothstep(40.0, 44.8, ax)
        dv = C.fbm((x * 0.05 + 3.1, 0.0, z * 0.05), 2, seed + 5)
        dc = C.fbm((x * 0.05 + 3.1, 0.0, 0.0), 2, 98.0)
        d = dv * (1.0 - w) + dc * w
        puddle = max(0.0, min(1.0, 0.42 + 1.5 * (n - 0.5) + 0.16 * near_ch + 0.04 * mid + 0.10 * outer + 0.10 * (d - 0.5)))
        wet = min(1.0, 0.35 + 0.65 * C.smoothstep(0.35, 0.55, n + 0.1 * outer) + 0.3 * near_wall)
        mud = min(1.0, C.smoothstep(0.55, 0.75, d) * 0.6 + near_wall * 0.7 + outer * 0.15 + near_ch * 0.2)
        # pillar feet collect silt
        for px in C.PILLAR_X:
            dx = max(0.0, abs(ax - px) - C.PILLAR_HW)
            dz = max(0.0, C.PILLAR_Z0 - z, z - C.PILLAR_Z1)
            dd = math.hypot(dx, dz)
            mud = max(mud, 0.55 * (1.0 - C.smoothstep(0.0, 0.9, dd)))
        return (puddle, wet, mud, 1.0)
    return fn


def finish_module(tag, A, lights, colour_seed, kind="bay"):
    col = C.collection("CIS_" + tag)
    objs = {}
    for key, acc in A.items():
        if len(acc.bm.faces) == 0:
            acc.bm.free()
            continue
        name = "%s|%s" % (tag, OBJ_NAMES[key])
        fn = floor_colour_fn(colour_seed, kind) if key == "floor" else None
        objs[key] = acc.to_object(name, material(key), col, colour_fn=fn)
        objs[key]["cis_part"] = key
        objs[key]["cis_seed"] = colour_seed * 0.1
    counts = {}
    for i, entry in enumerate(lights):
        kind_l, p, aim = entry[:3]
        power = entry[3] if len(entry) > 3 else None
        counts[kind_l] = counts.get(kind_l, -1) + 1
        k = counts[kind_l]
        if kind_l != "Room":
            C.empty("%s|CIS_Light_%s_%d" % (tag, kind_l, k), col, p, aim)
        if kind_l != "Window":
            make_light(tag, kind_l, k, p, aim, col, power)
    return objs


def build_module(tag):
    info = MODULES[tag]
    col = C.collection("CIS_" + tag)
    C.clear_collection(col)
    A = new_accs()
    if info["kind"] in ("bay", "opening"):
        variant = {"A": 0, "B": 1, "C": 2, "O": 0}[tag]
        lights = bay_geometry(A, tag, variant, opening=(info["kind"] == "opening"))
        if info["kind"] == "bay":
            props(A, variant)
        else:
            opening_rim(A)
    elif info["kind"] == "upstream":
        lights = upstream_geometry(A)
    else:
        lights = downstream_geometry(A)
    objs = finish_module(tag, A, lights, info["seed"], "bay" if info["kind"] in ("bay", "opening") else "end")
    extra = []
    if info["kind"] == "upstream":
        root, extra = gate_meshes(tag, col)
    elif info["kind"] == "downstream":
        extra = hatch_meshes(tag, col)
    for o in extra:
        o["cis_seed"] = info["seed"] * 0.1
        objs[o.name.split("|", 1)[1]] = o
    tris = {k: C.tri_count(o) for k, o in objs.items()}
    col["cis_module"] = info["name"]
    return {"module": info["name"], "tris": tris, "total": sum(tris.values()), "lights": len(lights)}


def opening_rim(A, segs=96):
    """Ceiling opening of bay k = 0: concrete rim y 18..19 facing the axis, yellow/black band on the
    soffit around it and a painted steel edge angle (the shaft tiles continue above y = 19)."""
    shell, hazard, steel = A["shell"], A["hazard"], A["steel"]
    r = C.OPENING_R
    ring_lo = [V(r * math.cos(TAU * i / segs), C.CEIL_Y, r * math.sin(TAU * i / segs)) for i in range(segs)]
    ring_hi = [V(r * math.cos(TAU * i / segs), C.SLAB_TOP, r * math.sin(TAU * i / segs)) for i in range(segs)]
    # rim faces point toward the axis
    for i in range(segs):
        j = (i + 1) % segs
        f = shell.face((ring_lo[i], ring_lo[j], ring_hi[j], ring_hi[i]))
        mid = (ring_lo[i] + ring_hi[j]) * 0.5
        shell.orient(f, V(-mid.x, 0.0, -mid.z))
    # hazard band on the soffit (r 7.0 .. 7.6), stripes run diagonally across it
    r0, r1, y = r + 0.08, r + 0.62, C.CEIL_Y - 0.004
    circ = TAU * r
    for i in range(segs):
        j = i + 1
        a0, a1 = TAU * i / segs, TAU * j / segs
        pts = (V(r0 * math.cos(a0), y, r0 * math.sin(a0)), V(r0 * math.cos(a1), y, r0 * math.sin(a1)),
               V(r1 * math.cos(a1), y, r1 * math.sin(a1)), V(r1 * math.cos(a0), y, r1 * math.sin(a0)))
        u0, u1 = circ * i / segs / C.S_HAZARD, circ * j / segs / C.S_HAZARD
        hazard.face(pts, uv=((u0, 0.0), (u1, 0.0), (u1, (r1 - r0) / C.S_HAZARD), (u0, (r1 - r0) / C.S_HAZARD)), out=V(0, -1, 0))
    # painted steel edge angle: vertical leg on the rim, horizontal leg on the soffit
    prof = [(r - 0.012, 18.32), (r - 0.012, C.CEIL_Y - 0.012), (r + 0.08, C.CEIL_Y - 0.012), (r + 0.08, C.CEIL_Y - 0.001),
            (r - 0.001, C.CEIL_Y - 0.001), (r - 0.001, 18.32)]
    for i in range(segs):
        j = (i + 1) % segs
        a0, a1 = TAU * i / segs, TAU * j / segs
        for k in range(len(prof)):
            p0, p1 = prof[k], prof[(k + 1) % len(prof)]
            pts = (V(p0[0] * math.cos(a0), p0[1], p0[0] * math.sin(a0)), V(p0[0] * math.cos(a1), p0[1], p0[0] * math.sin(a1)),
                   V(p1[0] * math.cos(a1), p1[1], p1[0] * math.sin(a1)), V(p1[0] * math.cos(a0), p1[1], p1[0] * math.sin(a0)))
            f = steel.face(pts, color=C.TINT["yellow"])
            # outward = away from the angle's own centre line
            cr, cy = r + 0.02, C.CEIL_Y - 0.01
            mid = (pts[0] + pts[2]) * 0.5
            rad = math.hypot(mid.x, mid.z)
            n2 = Vector((rad - cr, mid.y - cy))
            radial = V(mid.x / rad, 0.0, mid.z / rad)
            steel.orient(f, radial * n2.x + V(0, 1, 0) * n2.y)
    # anchor bolts around the angle
    for i in range(48):
        a = TAU * (i + 0.5) / 48
        p = V((r + 0.045) * math.cos(a), C.CEIL_Y - 0.012, (r + 0.045) * math.sin(a))
        steel.cyl(p, p + V(0, -0.02, 0), 0.012, 6, color=C.TINT["yellow"])


# =============================================================== end modules: shared parts
def side_wall_span(acc, side, z0, z1, half_lo, half_hi):
    x = side * C.HALF_W
    ys, iy = joint_stations(0.0, C.CEIL_Y, (C.KICKER,) + C.COLD_JOINTS)
    zs = [z0]
    iz = [C.JOINT_D if half_lo else 0.0]
    if half_lo:
        zs.append(z0 + C.JOINT_G)
        iz.append(0.0)
    if half_hi:
        zs += [z1 - C.JOINT_G, z1]
        iz += [0.0, C.JOINT_D]
    else:
        zs.append(z1)
        iz.append(0.0)
    wall_grid(acc, lambda z, y, d: V(x + side * d, y, z), zs, ys, iz, iy, V(-side, 0, 0))


def end_wall(acc, z, facing, holes=(), circle=None, step=1.875):
    """End wall plane at z, normal (0, 0, facing). holes: rects (xa, xb, ya, yb) left open.
    circle: (cx, cy, r, (xa, xb, ya, yb)) built as a ring between the circle and that rect."""
    xs = set(steps(-C.HALF_W, C.HALF_W, step))
    ys = set(steps(0.0, C.CEIL_Y, step))
    rects = list(holes) + ([circle[3]] if circle else [])
    for (xa, xb, ya, yb) in rects:
        xs.update((xa, xb))
        ys.update((ya, yb))
    xs = sorted(round(v, 5) for v in xs)
    ys = sorted(round(v, 5) for v in ys)
    n = V(0, 0, facing)
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            cx, cy = (xs[i] + xs[i + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5
            if any(xa < cx < xb and ya < cy < yb for (xa, xb, ya, yb) in rects):
                continue
            acc.face((V(xs[i], ys[j], z), V(xs[i + 1], ys[j], z), V(xs[i + 1], ys[j + 1], z), V(xs[i], ys[j + 1], z)), out=n)
    if circle:
        cx, cy, r, (xa, xb, ya, yb) = circle
        segs = 72
        angles = set(TAU * k / segs for k in range(segs))
        for (px, py) in ((xb, yb), (xa, yb), (xa, ya), (xb, ya)):
            angles.add(math.atan2(py - cy, px - cx) % TAU)
        angles = sorted(angles)

        def bnd(a):
            dx, dy = math.cos(a), math.sin(a)
            ts = []
            if abs(dx) > 1e-9:
                ts += [(xb - cx) / dx, (xa - cx) / dx]
            if abs(dy) > 1e-9:
                ts += [(yb - cy) / dy, (ya - cy) / dy]
            t = min(t for t in ts if t > 0)
            return V(cx + dx * t, cy + dy * t, z)

        for k in range(len(angles)):
            a0, a1 = angles[k], angles[(k + 1) % len(angles)]
            p0 = V(cx + r * math.cos(a0), cy + r * math.sin(a0), z)
            p1 = V(cx + r * math.cos(a1), cy + r * math.sin(a1), z)
            b0, b1 = bnd(a0), bnd(a1)
            if (p0 - b0).length < 1e-4 and (p1 - b1).length < 1e-4:
                continue
            if (p0 - b0).length < 1e-4:
                acc.face((p0, p1, b1), out=n)
            elif (p1 - b1).length < 1e-4:
                acc.face((p0, p1, b0), out=n)
            else:
                acc.face((p0, p1, b1, b0), out=n)


def reveal(acc, xa, xb, ya, yb, z_face, depth, facing, sill=True):
    """Window / door reveal through the wall thickness (faces point into the opening)."""
    z_in = z_face - facing * depth
    zz = (min(z_face, z_in), max(z_face, z_in))
    acc.face((V(xa, ya, zz[0]), V(xa, yb, zz[0]), V(xa, yb, zz[1]), V(xa, ya, zz[1])), out=V(1, 0, 0))
    acc.face((V(xb, ya, zz[0]), V(xb, ya, zz[1]), V(xb, yb, zz[1]), V(xb, yb, zz[0])), out=V(-1, 0, 0))
    acc.face((V(xa, yb, zz[0]), V(xb, yb, zz[0]), V(xb, yb, zz[1]), V(xa, yb, zz[1])), out=V(0, -1, 0))
    if sill:
        acc.face((V(xa, ya, zz[0]), V(xa, ya, zz[1]), V(xb, ya, zz[1]), V(xb, ya, zz[0])), out=V(0, 1, 0))


def end_floor_and_services(A, za, zb, wall_z, rail_posts, hanger_z, support_z, bracket_z):
    """Floor, channels, side walls, beams, soffit (cells given separately), trays, pipes, railings
    for an end region between za < zb (wall_z = the end wall plane)."""
    shell, floor, steel, galv, grate = A["shell"], A["floor"], A["steel"], A["galv"], A["grate"]
    zs = steps(za, zb, 0.5)
    floor_grid(floor, floor_xs(), zs, lambda x, z: in_channel(x))
    channels(floor, galv, grate, za, zb)
    # channel end caps against the end wall
    for s in (-1, 1):
        lo, hi = sorted((s * C.CH_X[0], s * C.CH_X[1]))
        fz = 1.0 if wall_z < za + 0.01 else -1.0
        floor.face((V(lo, 0, wall_z), V(hi, 0, wall_z), V(hi, -C.CH_DEPTH, wall_z), V(lo, -C.CH_DEPTH, wall_z)), out=V(0, 0, fz))
    for s in (-1, 1):
        side_wall_span(shell, s, za, zb, half_lo=(za > wall_z - 0.01 and False) or (wall_z > za + 0.01), half_hi=(wall_z < zb - 0.01))
    for s in (-1, 1):
        for px in C.PILLAR_X:
            x0, x1 = s * px - C.PILLAR_HW, s * px + C.PILLAR_HW
            beam_z(shell, x0, x1, za, zb, C.LB_BOTTOM, haunch_a=(wall_z <= za + 0.01), haunch_b=(wall_z >= zb - 0.01))
    # corridor railings + trays + wall services continue to the end wall
    tray_y = 15.0
    for s in (-1, 1):
        x = s * C.PILLAR_X[0]
        railing(galv, x, za, zb, rail_posts)
        for y in (1.1, 0.55):
            galv.box((x - 0.06, y - 0.06, wall_z - 0.006), (x + 0.06, y + 0.06, wall_z + 0.006))
        x_in, x_out = s * (C.CORR_X - 0.05), s * (C.CORR_X - 0.55)
        ladder_tray(galv, steel, x_in, x_out, tray_y, za, zb, side=s)
        for z in hanger_z:
            xb = s * C.CORR_X
            steel.box((min(xb, s * (C.CORR_X - 0.7)), 16.62, z - 0.03), (max(xb, s * (C.CORR_X - 0.7)), 16.68, z + 0.03), color=C.TINT["grey"])
            steel.box((min(xb, s * (C.CORR_X - 0.62)), tray_y - 0.05, z - 0.03), (max(xb, s * (C.CORR_X - 0.62)), tray_y - 0.005, z + 0.03), color=C.TINT["grey"])
            for xr in (C.CORR_X - 0.02, C.CORR_X - 0.6):
                galv.cyl(V(s * xr, tray_y - 0.05, z), V(s * xr, 16.62, z), 0.008, 6, caps=False)
        wall_pipe(galv, steel, s * (C.HALF_W - 0.36), 2.2, 0.20, za, zb, s, support_z)
        wall_pipe(galv, steel, s * (C.HALF_W - 0.30), 2.95, 0.11, za, zb, s, support_z)
        ladder_tray(galv, steel, s * (C.HALF_W - 0.05), s * (C.HALF_W - 0.60), 9.5, za, zb, side=s, cables=2)
        for z in bracket_z:
            steel.box((min(s * C.HALF_W, s * (C.HALF_W - 0.66)), 9.45, z - 0.025), (max(s * C.HALF_W, s * (C.HALF_W - 0.66)), 9.5, z + 0.025), color=C.TINT["grey"])


def soffit_span(shell, za, zb, slot=None):
    """Soffit cells between za and zb; slot = (xa, xb, z0, z1) left open in the corridor cell."""
    for (xa, xb) in x_gaps():
        if slot and xa < 0 < xb:
            sx0, sx1, sz0, sz1 = slot
            rects = [(xa, xb, sz1, zb), (xa, sx0, za, sz1), (sx1, xb, za, sz1)]
            if sz0 > za:
                rects.append((sx0, sx1, za, sz0))
            for (a, b, c, d) in rects:
                if b - a > 1e-4 and d - c > 1e-4:
                    soffit_cell(shell, a, b, c, d)
        else:
            soffit_cell(shell, xa, xb, za, zb)


def caged_ladder(A, x, wall_z, facing, y0, y1, cage_from=2.3):
    """Fixed steel ladder on a wall (rails 0.6 apart, rung every 0.3 m) with safety hoops."""
    steel, galv = A["steel"], A["galv"]
    zr = wall_z + facing * 0.2
    for rx in (-0.3, 0.3):
        steel.box((x + rx - 0.03, y0, zr - 0.035), (x + rx + 0.03, y1, zr + 0.035), color=C.TINT["yellow"])
        for y in steps(y0 + 0.4, y1 - 0.2, 1.5):
            steel.box((x + rx - 0.02, y - 0.03, min(wall_z, zr)), (x + rx + 0.02, y + 0.03, max(wall_z, zr)), color=C.TINT["yellow"])
    n = int((y1 - y0 - 0.15) / 0.3)
    for k in range(n):
        y = y0 + 0.3 * (k + 1)
        galv.cyl(V(x - 0.3, y, zr), V(x + 0.3, y, zr), 0.016, 6, caps=False)
    hoops = []
    y = cage_from
    while y < y1 + 0.01:
        hoops.append(y)
        y += 0.9
    for y in hoops:
        pts = [V(x + 0.36 * math.cos(math.pi * k / 10), y, zr + facing * (0.36 * math.sin(math.pi * k / 10))) for k in range(11)]
        pts = [V(x + 0.36, y, wall_z + facing * 0.05)] + pts[0:1] + pts[1:] + [V(x - 0.36, y, wall_z + facing * 0.05)]
        steel.tube(pts, 0.013, 5, caps=False, color=C.TINT["yellow"])
    for k in range(5):
        a = math.pi * (k + 0.5) / 5
        px, pz = x + 0.36 * math.cos(a), zr + facing * 0.36 * math.sin(a)
        steel.box((px - 0.02, cage_from, pz - 0.006), (px + 0.02, y1, pz + 0.006), color=C.TINT["yellow"])


def yellow_railing(steel, path, h=1.1, posts_every=1.5, mid=True):
    """Painted safety railing along a polyline on a deck (path points carry the deck height)."""
    top = [p + V(0, h, 0) for p in path]
    steel.tube(top, 0.024, 8, caps=True, color=C.TINT["yellow"])
    if mid:
        steel.tube([p + V(0, h * 0.5, 0) for p in path], 0.019, 8, caps=True, color=C.TINT["yellow"])
    steel.tube([p + V(0, 0.1, 0) for p in path], 0.012, 6, caps=True, color=C.TINT["yellow"])
    for a, b in zip(path[:-1], path[1:]):
        L = (b - a).length
        n = max(1, int(math.ceil(L / posts_every)))
        for k in range(n + 1):
            p = a + (b - a) * (k / n)
            steel.cyl(p, p + V(0, h, 0), 0.024, 8, color=C.TINT["yellow"])


# =============================================================== upstream end (world z)
U_WALL = -30.0
U_BACK = -30.6
U_JOIN = -22.5
TUNNEL_R = 5.0
TUNNEL_Y = 5.0
TUNNEL_END = -45.0
GATE_Z = (-29.62, -29.56)     # skin plate
GATE_TOP = 10.6
GATE_HW = 5.58
ROOM = {"x": (13.5, 22.5), "y": (8.0, 11.6), "z": (-34.6, U_BACK)}
WINDOWS = [(14.4, 16.0), (16.2, 17.8), (18.0, 19.6)]
WIN_Y = (9.0, 10.4)
DOOR = (20.5, 21.5, 8.0, 10.1)
BALCONY = {"x": (13.5, 22.5), "z": (U_WALL, -28.5), "y": 8.0}
STAIR = {"x_top": 22.5, "x_bottom": 32.0, "z": (U_WALL + 0.05, -28.95)}


def upstream_geometry(A):
    shell, floor, steel, galv = A["shell"], A["floor"], A["steel"], A["galv"]
    lights = []
    za, zb = U_WALL, U_JOIN
    end_floor_and_services(A, za, zb, U_WALL, rail_posts=[-24.5, -26.5, -28.5],
                           hanger_z=[-23.75, -26.25, -28.75], support_z=[-24.0, -27.0], bracket_z=[-23.25 - 1.5 * k for k in range(5)])
    # --- soffit with the gate slot, slot shaft above
    slot = (-6.0, 6.0, U_WALL, -28.9)
    soffit_span(shell, za, zb, slot)
    sx0, sx1, sz0, sz1 = slot
    top = 23.5
    shell.face((V(sx0, C.CEIL_Y, sz0), V(sx0, C.CEIL_Y, sz1), V(sx0, top, sz1), V(sx0, top, sz0)), out=V(1, 0, 0))
    shell.face((V(sx1, C.CEIL_Y, sz0), V(sx1, top, sz0), V(sx1, top, sz1), V(sx1, C.CEIL_Y, sz1)), out=V(-1, 0, 0))
    shell.face((V(sx0, C.CEIL_Y, sz1), V(sx1, C.CEIL_Y, sz1), V(sx1, top, sz1), V(sx0, top, sz1)), out=V(0, 0, -1))
    shell.face((V(sx0, C.CEIL_Y, sz0), V(sx0, top, sz0), V(sx1, top, sz0), V(sx1, C.CEIL_Y, sz0)), out=V(0, 0, 1))
    A["dark"].face((V(sx0, top, sz0), V(sx1, top, sz0), V(sx1, top, sz1), V(sx0, top, sz1)), out=V(0, -1, 0))
    # --- end wall with the tunnel mouth, windows and door
    holes = [(w[0], w[1], WIN_Y[0], WIN_Y[1]) for w in WINDOWS] + [(DOOR[0], DOOR[1], DOOR[2], DOOR[3])]
    end_wall(shell, U_WALL, 1.0, holes=holes, circle=(0.0, TUNNEL_Y, TUNNEL_R, (-5.625, 5.625, 0.0, 11.25)))
    for (xa, xb) in WINDOWS:
        reveal(shell, xa, xb, WIN_Y[0], WIN_Y[1], U_WALL, U_WALL - U_BACK, 1.0)
    reveal(shell, DOOR[0], DOOR[1], DOOR[2], DOOR[3], U_WALL, U_WALL - U_BACK, 1.0, sill=False)
    # --- shield tunnel (segment rings every 1.2 m), dark plug far upstream
    segs = 64
    zst = [U_WALL]
    zin = [0.0]
    z = U_WALL - 1.2
    while z > TUNNEL_END + 0.6:
        zst += [z + 0.02, z, z - 0.02]
        zin += [0.0, 0.025, 0.0]
        z -= 1.2
    zst.append(TUNNEL_END)
    zin.append(0.0)
    rings = []
    for zz, d in zip(zst, zin):
        rr = TUNNEL_R + d
        rings.append([V(rr * math.cos(TAU * k / segs), TUNNEL_Y + rr * math.sin(TAU * k / segs), zz) for k in range(segs)])
    shell.rings(rings, closed=True, center_fn=lambda m: m + (m - V(0.0, TUNNEL_Y, m.z)))
    A["dark"].face([V(TUNNEL_R * math.cos(TAU * k / 24), TUNNEL_Y + TUNNEL_R * math.sin(TAU * k / 24), TUNNEL_END + 0.01) for k in range(24)], out=V(0, 0, 1))
    # tunnel lamps
    for k, zt in enumerate((-36.0, -42.0)):
        for s in (-1, 1):
            a = math.radians(30.0)
            m = V(s * TUNNEL_R * math.cos(a), TUNNEL_Y + TUNNEL_R * math.sin(a), zt)
            n = (V(0.0, TUNNEL_Y, zt) - m).normalized()
            p = amber_lamp(A, m, n)
            lights.append(("Amber", p, n, TUNNEL_LAMP_POWER))
    # --- gate guides (fixed) and the roller gate (moving node, built in its own accumulators)
    for s in (-1, 1):
        steel.box((min(s * 5.70, s * 5.95), 0.0, U_WALL), (max(s * 5.70, s * 5.95), C.CEIL_Y + 4.0, -28.95), color=C.TINT["blue"])
        steel.box((min(s * 5.45, s * 5.70), 0.0, -29.10), (max(s * 5.45, s * 5.70), C.CEIL_Y + 4.0, -28.95), color=C.TINT["blue"])
        steel.box((min(s * 5.45, s * 5.70), 0.0, U_WALL), (max(s * 5.45, s * 5.70), C.CEIL_Y + 4.0, -29.75), color=C.TINT["blue"])
        for y in steps(0.6, 17.4, 2.8):
            steel.box((min(s * 5.95, s * 6.25), y - 0.12, U_WALL), (max(s * 5.95, s * 6.25), y + 0.12, -29.6), color=C.TINT["blue"])
    # sill beam across the mouth
    steel.box((-5.95, 0.0, U_WALL), (5.95, 0.025, -29.0), skip=("-y",), color=C.TINT["grey"])
    # --- balcony, stair, control room
    bx0, bx1 = BALCONY["x"]
    bz0, bz1 = BALCONY["z"]
    by = BALCONY["y"]
    shell.box((bx0, by - 0.3, bz0), (bx1, by, bz1), skip=("-z",))
    yellow_railing(steel, [V(bx0 + 0.05, by, bz0 + 0.05), V(bx0 + 0.05, by, bz1 - 0.06), V(bx1 - 1.15, by, bz1 - 0.06)])
    # stair down along the wall toward +x
    sx_top, sx_bot = STAIR["x_top"], STAIR["x_bottom"]
    sz0, sz1 = STAIR["z"]
    n = 40
    rise = by / n
    going = (sx_bot - sx_top) / n
    for k in range(n):
        y = by - rise * (k + 1)
        x0 = sx_top + going * k
        A["grate"].face((V(x0, y, sz0), V(x0, y, sz1), V(x0 + going + 0.03, y, sz1), V(x0 + going + 0.03, y, sz0)),
            uv=((0, sz0 / C.S_GRATE), (0, sz1 / C.S_GRATE), ((going + 0.03) / C.S_GRATE, sz1 / C.S_GRATE), ((going + 0.03) / C.S_GRATE, sz0 / C.S_GRATE)), out=V(0, 1, 0))
        A["grate"].face((V(x0, y, sz0), V(x0, y, sz1), V(x0 + going + 0.03, y, sz1), V(x0 + going + 0.03, y, sz0)),
            uv=((0, sz0 / C.S_GRATE), (0, sz1 / C.S_GRATE), ((going + 0.03) / C.S_GRATE, sz1 / C.S_GRATE), ((going + 0.03) / C.S_GRATE, sz0 / C.S_GRATE)), out=V(0, -1, 0))
        galv.box((x0, y - 0.03, sz0), (x0 + 0.03, y, sz1))
    for zz in (sz0, sz1):
        d = V(sx_bot - sx_top, -by, 0.0).normalized()
        up = V(0, 1, 0)
        a = V(sx_top - 0.05, by - 0.02, zz)
        b = V(sx_bot + 0.05, 0.0, zz)
        steel.sweep([a, b], [(0.0, -0.006), (0.25, -0.006), (0.25, 0.006), (0.0, 0.006)], up=V(0, 0, 1), color=C.TINT["yellow"])
    yellow_railing(steel, [V(sx_top - 1.1, by, -28.56), V(sx_top, by, -28.56)], mid=True)
    yellow_railing(steel, [V(sx_top, by, sz1 - 0.04), V(sx_bot, 0.0, sz1 - 0.04)], posts_every=2.4)
    for k in range(4):
        p = V(sx_top + (sx_bot - sx_top) * (k + 0.5) / 4.0, by * (1.0 - (k + 0.5) / 4.0) - 0.15, U_WALL)
        steel.box((p.x - 0.08, p.y - 0.08, U_WALL), (p.x + 0.08, p.y + 0.08, sz0 + 0.01), color=C.TINT["yellow"])
    # control room interior (behind the wall)
    rx0, rx1 = ROOM["x"]
    ry0, ry1 = ROOM["y"]
    rz0, rz1 = ROOM["z"]
    inter = A["interior"]
    made = inter.box((rx0, ry0, rz0), (rx1, ry1, rz1), skip=("+z",))
    for f in made:
        f.normal_flip()
    xs = sorted(set([rx0, rx1] + [v for w in WINDOWS for v in w] + [DOOR[0], DOOR[1]]))
    ys = sorted(set([ry0, ry1, WIN_Y[0], WIN_Y[1], DOOR[3]]))
    holes = [(w[0], w[1], WIN_Y[0], WIN_Y[1]) for w in WINDOWS] + [(DOOR[0], DOOR[1], DOOR[2], DOOR[3])]
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            cx, cy = (xs[i] + xs[i + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5
            if any(a < cx < b and c < cy < d for (a, b, c, d) in holes):
                continue
            inter.face((V(xs[i], ys[j], rz1), V(xs[i + 1], ys[j], rz1), V(xs[i + 1], ys[j + 1], rz1), V(xs[i], ys[j + 1], rz1)), out=V(0, 0, -1))
    lens = A["lens"]
    lens.face((V(16.0, ry1 - 0.01, -33.6), V(20.0, ry1 - 0.01, -33.6), V(20.0, ry1 - 0.01, -32.4), V(16.0, ry1 - 0.01, -32.4)),
              out=V(0, -1, 0), uv=((0, 0), (1, 0), (1, 1), (0, 1)))
    steel.box((14.0, ry0, -31.6), (21.5, ry0 + 0.85, -30.7), color=C.TINT["grey"])            # console desk
    for k in range(4):
        x = 14.8 + 1.7 * k
        steel.obox(V(x, ry0 + 1.12, -31.15), (0.62, 0.40, 0.05), Matrix.Rotation(-0.25, 3, "X"), color=C.TINT["black"])
        lens.face((V(x - 0.27, ry0 + 0.95, -31.12), V(x + 0.27, ry0 + 0.95, -31.12), V(x + 0.27, ry0 + 1.29, -31.21), V(x - 0.27, ry0 + 1.29, -31.21)),
                  out=V(0, 0, 1), uv=((0, 0), (1, 0), (1, 1), (0, 1)))
    steel.box((13.6, ry0, -34.5), (15.6, ry0 + 2.2, -33.9), color=C.TINT["green"])           # cabinets
    steel.box((19.8, ry0, -34.5), (22.4, ry0 + 2.0, -33.9), color=C.TINT["grey"])
    # windows: frames + glass, door slab
    for (xa, xb) in WINDOWS:
        A["glass"].face((V(xa, WIN_Y[0], -30.3), V(xb, WIN_Y[0], -30.3), V(xb, WIN_Y[1], -30.3), V(xa, WIN_Y[1], -30.3)),
                        out=V(0, 0, 1), uv=((0, 0), (1, 0), (1, 1), (0, 1)))
        for (fx0, fx1, fy0, fy1) in ((xa, xb, WIN_Y[0], WIN_Y[0] + 0.05), (xa, xb, WIN_Y[1] - 0.05, WIN_Y[1]),
                                     (xa, xa + 0.05, WIN_Y[0], WIN_Y[1]), (xb - 0.05, xb, WIN_Y[0], WIN_Y[1])):
            steel.box((fx0, fy0, -30.34), (fx1, fy1, -30.26), color=C.TINT["grey"])
    steel.box((DOOR[0] + 0.02, DOOR[2], -30.36), (DOOR[1] - 0.02, DOOR[3] - 0.02, -30.30), color=C.TINT["grey"])
    steel.cyl(V(DOOR[1] - 0.15, 9.05, -30.30), V(DOOR[1] - 0.15, 9.05, -30.22), 0.02, 6, color=C.TINT["black"])
    # signage plate beside the door (blank, painted)
    steel.box((DOOR[0] - 0.9, 9.3, U_WALL), (DOOR[0] - 0.2, 9.75, U_WALL + 0.02), color=C.TINT["white"])
    # --- lights: floods on the end wall toward the gate, window light, amber safety lamps
    for s in (-1, 1):
        mount = V(s * 8.6, 12.5, U_WALL)
        tgt = V(s * 0.8, 2.5, -24.5)
        aim = (tgt - (mount + V(0, 0, 0.3))).normalized()
        p = floodlight(A, mount, V(0, 0, 1), aim)
        lights.append(("Flood", p, aim))
    for k, (xa, xb) in enumerate(WINDOWS):
        p = V((xa + xb) * 0.5, (WIN_Y[0] + WIN_Y[1]) * 0.5, -29.95)
        lights.append(("Window", p, V(0.0, -0.35, 1.0).normalized()))
    lights.append(("Room", V(18.0, ry1 - 0.05, -33.0), V(0, -1, 0)))
    for (m, n) in ((V(21.0, 10.75, U_WALL), V(0, 0, 1)), (V(33.0, 2.6, U_WALL), V(0, 0, 1)), (V(-8.2, 3.0, U_WALL), V(0, 0, 1)),
                   (V(-24.0, 3.4, U_WALL), V(0, 0, 1)), (V(-38.0, 3.4, U_WALL), V(0, 0, 1)), (V(40.0, 3.4, U_WALL), V(0, 0, 1)),
                   (V(-C.HALF_W, 3.4, -26.25), V(1, 0, 0)), (V(C.HALF_W, 3.4, -26.25), V(-1, 0, 0))):
        p = amber_lamp(A, m, n)
        lights.append(("Amber", p, n))
    return lights


def gate_meshes(tag, col):
    """CIS_InflowGate: empty at the gate's bottom centre, children = steel + hazard meshes.
    Closed in the GLB; Godot raises the node +Y 11.4 m (it slides up into the ceiling slot)."""
    g_steel = GAcc(C.S_STEEL)
    g_haz = GAcc(C.S_HAZARD)
    tint = C.TINT["blue"]
    z0, z1 = GATE_Z
    g_steel.box((-GATE_HW, 0.03, z0), (GATE_HW, GATE_TOP, z1), color=tint)
    g_steel.box((-GATE_HW + 0.02, 0.0, z0 + 0.005), (GATE_HW - 0.02, 0.03, z1 - 0.005), color=C.TINT["black"])     # bottom seal
    for y in (0.8, 2.6, 4.4, 6.2, 8.0, 9.8):
        g_steel.box((-5.42, y - 0.01, z1), (5.42, y + 0.01, -29.22), color=tint)                                       # web
        g_steel.box((-5.42, y - 0.15, -29.22), (5.42, y + 0.15, -29.20), color=tint)                                   # flange
    for x in (-5.42, -1.8, 1.8, 5.42):
        hw = 0.08 if abs(x) > 5 else 0.01
        g_steel.box((x - hw, 0.03, z1), (x + hw, GATE_TOP, -29.22), color=tint)
    for s in (-1, 1):
        for y in (1.2, 5.3, 9.4):
            g_steel.cyl(V(s * 5.5, y, -29.40), V(s * 5.64, y, -29.40), 0.13, 14, color=C.TINT["grey"])
            g_steel.cyl(V(s * 5.56, y, -29.62), V(s * 5.56, y, -29.15), 0.03, 8, color=C.TINT["grey"])
    for x in (-3.5, 3.5):
        g_steel.box((x - 0.12, GATE_TOP, -29.45), (x + 0.12, GATE_TOP + 0.3, -29.35), color=tint)                       # lifting lugs
    g_haz.face((V(-5.34, 0.05, -29.195), V(5.34, 0.05, -29.195), V(5.34, 0.62, -29.195), V(-5.34, 0.62, -29.195)),
               uv=((0.0, 0.0), (10.68 / C.S_HAZARD, 0.0), (10.68 / C.S_HAZARD, 0.57 / C.S_HAZARD), (0.0, 0.57 / C.S_HAZARD)), out=V(0, 0, 1))
    g_haz.face((V(-5.4, 0.05, z1 + 0.003), V(5.4, 0.05, z1 + 0.003), V(5.4, 0.62, z1 + 0.003), V(-5.4, 0.62, z1 + 0.003)),
               uv=((0.0, 0.0), (10.8 / C.S_HAZARD, 0.0), (10.8 / C.S_HAZARD, 0.57 / C.S_HAZARD), (0.0, 0.57 / C.S_HAZARD)), out=V(0, 0, 1))
    root = C.empty("%s|CIS_InflowGate" % tag, col, (0.0, 0.0, (GATE_Z[0] + GATE_Z[1]) * 0.5))
    root.empty_display_type = "CUBE"
    root.empty_display_size = 0.5
    o1 = g_steel.to_object("%s|CIS_InflowGate_Steel" % tag, material("steel"), col)
    o2 = g_haz.to_object("%s|CIS_InflowGate_Hazard" % tag, material("hazard"), col)
    for o, part in ((o1, "steel"), (o2, "hazard")):
        o.parent = root
        o.matrix_parent_inverse = root.matrix_basis.inverted()
        o["cis_part"] = part
    return root, [o1, o2]


# =============================================================== downstream end (world z)
D_WALL = 210.0
D_BACK = 211.2
D_JOIN = 202.5
WALK_Y = 6.0
WALK_Z = (208.4, D_WALL)
WALK_X = 12.0
LADDER_X = 3.5
HATCH_W = 1.1
HATCH_H = 1.6
HATCH_OPEN_DEG = 170.0
INTAKES = [(-11.0, -6.0, 3.0), (6.0, 11.0, 3.0), (-23.0, -16.0, 3.75), (16.0, 23.0, 3.75), (-36.0, -29.0, 3.75), (29.0, 36.0, 3.75)]
SIGN = {"x": (-4.6, 4.6), "y": (10.4, 12.24), "z": D_WALL - 0.12}


def downstream_geometry(A):
    shell, floor, steel, galv = A["shell"], A["floor"], A["steel"], A["galv"]
    lights = []
    za, zb = D_JOIN, D_WALL
    end_floor_and_services(A, za, zb, D_WALL, rail_posts=[204.0, 206.0, 208.0],
                           hanger_z=[203.75, 206.25, 208.75], support_z=[204.0, 207.0], bracket_z=[203.25 + 1.5 * k for k in range(5)])
    soffit_span(shell, za, zb)
    # --- end wall: intakes at the foot, hatch openings above the ladders
    hatch_holes = [(s * LADDER_X - HATCH_W * 0.5, s * LADDER_X + HATCH_W * 0.5, WALK_Y, WALK_Y + HATCH_H) for s in (-1, 1)]
    holes = [(a, b, 0.0, h) for (a, b, h) in INTAKES] + hatch_holes
    end_wall(shell, D_WALL, -1.0, holes=holes)
    depth = D_BACK - D_WALL
    for (a, b, h) in INTAKES:
        reveal(shell, a, b, 0.0, h, D_WALL, depth, -1.0, sill=False)
        floor.face((V(a, 0.0, D_WALL), V(b, 0.0, D_WALL), V(b, 0.0, D_BACK), V(a, 0.0, D_BACK)), out=V(0, 1, 0))
        A["dark"].face((V(a, 0.0, D_BACK - 0.01), V(b, 0.0, D_BACK - 0.01), V(b, h, D_BACK - 0.01), V(a, h, D_BACK - 0.01)), out=V(0, 0, -1))
        # trash rack: frame angles + vertical flat bars + two tie bars, set just inside the reveal
        zr = D_WALL + 0.18
        for (fx0, fx1, fy0, fy1) in ((a - 0.12, b + 0.12, h, h + 0.12), (a - 0.12, a, 0.0, h), (b, b + 0.12, 0.0, h)):
            steel.box((fx0, fy0, D_WALL - 0.03), (fx1, fy1, D_WALL), color=C.TINT["grey"])
        nb_ = int((b - a) / 0.15)
        for k in range(1, nb_):
            x = a + (b - a) * k / nb_
            steel.box((x - 0.011, 0.0, zr - 0.06), (x + 0.011, h, zr + 0.06), skip=("-y",), color=C.TINT["grey"])
        for y in (1.0, 2.1):
            if y < h - 0.3:
                steel.box((a, y - 0.04, zr - 0.075), (b, y + 0.04, zr - 0.06), color=C.TINT["grey"])
    for s in (-1, 1):
        xa, xb = s * LADDER_X - HATCH_W * 0.5, s * LADDER_X + HATCH_W * 0.5
        reveal(shell, xa, xb, WALK_Y, WALK_Y + HATCH_H, D_WALL, depth, -1.0)
        A["dark"].face((V(xa, WALK_Y, D_BACK - 0.01), V(xb, WALK_Y, D_BACK - 0.01), V(xb, WALK_Y + HATCH_H, D_BACK - 0.01), V(xa, WALK_Y + HATCH_H, D_BACK - 0.01)), out=V(0, 0, -1))
        # yellow/black frame around the hatch on the wall face
        hz = D_WALL - 0.006
        for (fx0, fx1, fy0, fy1) in ((xa - 0.16, xb + 0.16, WALK_Y + HATCH_H, WALK_Y + HATCH_H + 0.16), (xa - 0.16, xa, WALK_Y, WALK_Y + HATCH_H),
                                     (xb, xb + 0.16, WALK_Y, WALK_Y + HATCH_H)):
            A["hazard"].face((V(fx0, fy0, hz), V(fx1, fy0, hz), V(fx1, fy1, hz), V(fx0, fy1, hz)),
                             uv=((fx0, fy0), (fx1, fy0), (fx1, fy1), (fx0, fy1)), out=V(0, 0, -1))
        # hinge blocks on the outer jamb
        hx = s * (LADDER_X + HATCH_W * 0.5 + 0.03)
        for y in (WALK_Y + 0.25, WALK_Y + HATCH_H - 0.25):
            steel.box((hx - 0.04, y - 0.09, D_WALL - 0.08), (hx + 0.04, y + 0.09, D_WALL), color=C.TINT["grey"])
        caged_ladder(A, s * LADDER_X, D_WALL, -1.0, 0.0, WALK_Y - 0.02, cage_from=2.3)
    # --- walkway at y 6 (gaps at the ladders), grating deck, frame, knee braces, railings
    gaps = [(-WALK_X, -LADDER_X - 0.5), (-LADDER_X + 0.5, LADDER_X - 0.5), (LADDER_X + 0.5, WALK_X)]
    wz0, wz1 = WALK_Z
    for (x0, x1) in gaps:
        uvs = ((x0 / C.S_GRATE, wz0 / C.S_GRATE), (x0 / C.S_GRATE, wz1 / C.S_GRATE), (x1 / C.S_GRATE, wz1 / C.S_GRATE), (x1 / C.S_GRATE, wz0 / C.S_GRATE))
        A["grate"].face((V(x0, WALK_Y, wz0), V(x0, WALK_Y, wz1), V(x1, WALK_Y, wz1), V(x1, WALK_Y, wz0)), uv=uvs, out=V(0, 1, 0))
        A["grate"].face((V(x0, WALK_Y - 0.002, wz0), V(x0, WALK_Y - 0.002, wz1), V(x1, WALK_Y - 0.002, wz1), V(x1, WALK_Y - 0.002, wz0)), uv=uvs, out=V(0, -1, 0))
        galv.box((x0, WALK_Y - 0.18, wz0), (x1, WALK_Y + 0.005, wz0 + 0.07))
        galv.box((x0, WALK_Y - 0.18, wz1 - 0.07), (x1, WALK_Y, wz1))
        for xe in (x0, x1 - 0.07):
            galv.box((xe, WALK_Y - 0.18, wz0), (xe + 0.07, WALK_Y, wz1))
        A["hazard"].face((V(x0, WALK_Y - 0.18, wz0 - 0.002), V(x1, WALK_Y - 0.18, wz0 - 0.002), V(x1, WALK_Y + 0.005, wz0 - 0.002), V(x0, WALK_Y + 0.005, wz0 - 0.002)),
                         uv=((x0, 0.0), (x1, 0.0), (x1, 0.185), (x0, 0.185)), out=V(0, 0, -1))
        n = max(1, int(round((x1 - x0) / 3.0)))
        for k in range(n + 1):
            x = x0 + 0.1 + (x1 - x0 - 0.2) * k / n
            steel.sweep([V(x, WALK_Y - 0.18, wz0 + 0.1), V(x, WALK_Y - 1.4, wz1 - 0.02)], [(-0.04, -0.005), (0.04, -0.005), (0.04, 0.005), (-0.04, 0.005)],
                        up=V(1, 0, 0), color=C.TINT["grey"])
        yellow_railing(steel, [V(x0 + 0.04, WALK_Y, wz0 + 0.05), V(x1 - 0.04, WALK_Y, wz0 + 0.05)])
        for xe in (x0 + 0.04, x1 - 0.04):
            if abs(abs(xe) - WALK_X) > 0.2:
                yellow_railing(steel, [V(xe, WALK_Y, wz0 + 0.05), V(xe, WALK_Y, wz1 - 0.3)], posts_every=2.0)
    for s in (-1, 1):
        yellow_railing(steel, [V(s * (WALK_X - 0.04), WALK_Y, wz0 + 0.05), V(s * (WALK_X - 0.04), WALK_Y, wz1 - 0.05)], posts_every=2.0)
    # --- fictional facility sign (CIS_Sign) on stand-offs
    sx0, sx1 = SIGN["x"]
    sy0, sy1 = SIGN["y"]
    szf = SIGN["z"]
    A["sign"].face((V(sx0, sy0, szf), V(sx1, sy0, szf), V(sx1, sy1, szf), V(sx0, sy1, szf)), uv=((0, 0), (1, 0), (1, 1), (0, 1)), out=V(0, 0, -1))
    steel.box((sx0 - 0.06, sy0 - 0.06, szf), (sx1 + 0.06, sy1 + 0.06, szf + 0.05), skip=("-z",), color=C.TINT["grey"])
    for x in (sx0 + 0.6, 0.0, sx1 - 0.6):
        for y in (sy0 + 0.3, sy1 - 0.3):
            steel.box((x - 0.05, y - 0.05, szf + 0.05), (x + 0.05, y + 0.05, D_WALL), color=C.TINT["grey"])
    # --- lights: two floods high on the end wall onto ladders / walkway, amber over the hatches
    for s in (-1, 1):
        mount = V(s * 9.6, 13.0, D_WALL)
        tgt = V(s * 3.0, 3.0, 205.0)
        aim = (tgt - (mount + V(0, 0, -0.3))).normalized()
        p = floodlight(A, mount, V(0, 0, -1), aim)
        lights.append(("Flood", p, aim))
    for (m, n) in ((V(-LADDER_X, WALK_Y + HATCH_H + 0.45, D_WALL), V(0, 0, -1)), (V(LADDER_X, WALK_Y + HATCH_H + 0.45, D_WALL), V(0, 0, -1)),
                   (V(-8.5, 3.6, D_WALL), V(0, 0, -1)), (V(8.5, 3.6, D_WALL), V(0, 0, -1)),
                   (V(-19.5, 4.6, D_WALL), V(0, 0, -1)), (V(19.5, 4.6, D_WALL), V(0, 0, -1)),
                   (V(-32.5, 4.6, D_WALL), V(0, 0, -1)), (V(32.5, 4.6, D_WALL), V(0, 0, -1)),
                   (V(-C.HALF_W, 3.4, 206.25), V(1, 0, 0)), (V(C.HALF_W, 3.4, 206.25), V(-1, 0, 0))):
        p = amber_lamp(A, m, n)
        lights.append(("Amber", p, n))
    return lights


def hatch_meshes(tag, col):
    """CIS_Hatch_L / _R: empties on the vertical hinge (outer jamb, wall face, y = 6.0). The meshes
    are authored CLOSED in the node frame; the nodes are exported OPEN (rotated +-170 deg about Y).
    Godot closes a hatch by tweening its rotation.y to 0."""
    out = []
    for side, s in (("L", -1), ("R", 1)):
        hx = s * (LADDER_X + HATCH_W * 0.5)
        acc = GAcc(C.S_STEEL)
        # door leaf extends from the hinge toward the ladder axis (-s along x), recessed in the reveal
        x_far = -s * HATCH_W
        lo, hi = min(0.0, x_far), max(0.0, x_far)
        acc.box((lo + 0.01, 0.01, 0.03), (hi - 0.01, HATCH_H - 0.01, 0.11), color=C.TINT["blue"])
        for y in (0.35, 0.8, 1.25):
            acc.box((lo + 0.06, y - 0.03, -0.01), (hi - 0.06, y + 0.03, 0.03), color=C.TINT["blue"])
        c = V(x_far * 0.5, 0.85, -0.05)
        ring = [c + V(0.17 * math.cos(TAU * k / 16), 0.17 * math.sin(TAU * k / 16), 0.0) for k in range(16)]
        acc.tube(ring, 0.018, 6, closed=True, color=C.TINT["red"])
        for k in range(3):
            a = TAU * k / 3
            acc.cyl(c, c + V(0.17 * math.cos(a), 0.17 * math.sin(a), 0.0), 0.012, 6, color=C.TINT["red"])
        acc.cyl(c + V(0, 0, 0.0), c + V(0, 0, 0.08), 0.035, 10, color=C.TINT["red"])
        for y in (0.25, HATCH_H - 0.25):
            acc.cyl(V(0.0, y - 0.1, 0.0), V(0.0, y + 0.1, 0.0), 0.035, 10, color=C.TINT["grey"])
        root = C.empty("%s|CIS_Hatch_%s" % (tag, side), col, (hx, WALK_Y, D_WALL))
        root.empty_display_type = "ARROWS"
        mesh_obj = acc.to_object("%s|CIS_Hatch_%s_Steel" % (tag, side), material("steel"), col)
        mesh_obj.parent = root
        mesh_obj.matrix_parent_inverse = Matrix.Identity(4)
        mesh_obj["cis_part"] = "steel"
        root.rotation_euler = (0.0, 0.0, math.radians(-s * HATCH_OPEN_DEG))
        out.append(mesh_obj)
    return out


if __name__ == "__main__":
    result = build_module("A")

"""Shared constants and helpers for the surge tank (調圧水槽) of the Metropolitan Area Outer
Underground Discharge Channel, rebuilt at real scale for the AIQUIZ underground stage.

Loaded by the build / bake / export scripts INSIDE the user's live Blender (never a headless
process):

    ns = {}
    exec(open(SOURCE + "/tank_common.py", encoding="utf-8").read(), ns)

Geometry is authored in GODOT space (metres, Y up). GAcc.to_object() rotates the finished bmesh into
Blender space, Blender (x, y, z) = Godot (x, -z, y), which is exactly what the glTF exporter (+Y up)
undoes. Light anchors (empties) aim their Blender local +Y along the beam: that axis becomes the Godot
node's -Z.

Survey (docs/surge_tank_reproduction.md), from the MLIT plan "調圧水槽内平面図" and sections B-B / A-A:
  * u = distance from the pump-side gate face (u = 0) toward shaft No.1; v = across (centre line 0).
    Godot: z = Z_PUMP - u, x = -v (the visitor stair, +v in the plan, is on -x).
  * inner width 71 m (side walls at v = +-35.5; 78 m is the outside), 177.1 m from the gate face to
    the outer face of shaft No.1. The shaft-side corners are chamfered (~45 deg) from u = 156.2 to the
    end wall at u = 171.4 (half width 20 m); two 10 m openings with a 2 x 8 m pier lead to the shaft.
  * 59 pillars (7 x 2 m, half-round ends) on 11 lines u_k = 20.8 + 14 k (k = 0..10) and 9 rows
    v = 0, +-7, +-14, +-21, +-28: even k -> +-7, +-21, +-28; odd k -> 0, +-14, +-28; k = 10 -> +-7, +-21.
  * floor: a central trench (floor AP-10.4) between shelves 5 m higher: trench 54 m wide at the pump
    end (u < 41.7), narrowing to 40 m (u 69.4 .. 153.8), then to ~30 m at the shaft-side end wall.
    Slab soffit AP+7.3 -> 17.7 m over the trench floor, 12.7 m over the shelves.
  * pump end: five dividing walls (2 m, round tips, ~9.3 m into the tank) at v = 0, +-14, +-28 make the
    four intake channels (12 m clear) at v = +-7, +-21.
  * transverse beams half way between the pillar lines; every pillar head carries a 4 m beam to them; the
    coffers between the beams are centred on the pillar lines at the free rows.
  * lamps: one pendant LED high-bay in the middle of every coffer of the inner rows (|v| <= 21), i.e. at the
    free rows of each line, midway between two pillars of the same row (the official photo fits this to a
    few pixels: the two big lamps flank the centre pillar at its own depth, 14.9 m up).
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils import noise as mnoise

ROOT = "C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank"
SOURCE = ROOT + "/source"
TEXTURES = ROOT + "/textures"
PREVIEWS = SOURCE + "/previews"
BLEND_PATH = SOURCE + "/surge_tank.blend"
OLD_TEXTURES = "C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/textures"

TAU = math.tau

# ------------------------------------------------------------------ plan (u from the pump gate face, v across)
Z_PUMP = 132.8                      # Godot z of the gate face; the landing (0, 0) is the free node on line 8
INNER_HALF = 35.5
LINE_U0 = 20.8
LINE_PITCH = 14.0
LINES = 11
ROW_PITCH = 7.0
ROWS = (-28.0, -21.0, -14.0, -7.0, 0.0, 7.0, 14.0, 21.0, 28.0)
CHAMFER_U0 = 156.2                  # side walls start to close in toward the shaft
END_U = 171.4                       # shaft-side end wall
END_HALF = 20.0                     # half width at the end wall
OPEN_HALF = 11.0                    # the two openings span |v| 1 .. 11
OPEN_PIER_HALF = 1.0                # the 2 x 8 m pier between them
OPEN_TOP = 15.5
SHAFT_INNER_U = 179.6               # nearest point of shaft No.1's inner wall
SHAFT_R = 15.8                      # inner radius (31.6 m)
SHAFT_CENTRE_U = SHAFT_INNER_U + SHAFT_R
SHAFT_TOP = 22.4                    # ground (AP+12.0) over the trench floor (AP-10.4)
SHAFT_BOTTOM = -49.7                # GL-72.1
# trench crest (half width at the top of the slope) along u; the slope is 60 deg, 5 m high
SHELF_Y = 5.0
SLOPE_RUN = 2.9
CREST_PUMP = 27.0                   # = inner face of the +-28 dividing walls / pillars (plan: 54000)
CREST_MAIN = 20.0                   # = inner face of the +-21 pillars (plan: 40000)
CREST_END = 15.0
TRENCH_U = (41.7, 69.4, 153.8)
# pump end
PIERS_V = (-28.0, -14.0, 0.0, 14.0, 28.0)
PIER_HALF = 1.0
PIER_TIP_U = 9.3
CHANNELS_V = (-21.0, -7.0, 7.0, 21.0)
CHANNEL_HALF = 6.0
CHANNEL_DEPTH = 6.0                 # recess behind the gate face (gate chamber) seen from the tank
# vertical
H = 17.7                            # slab soffit over the trench floor
PIL_R = 1.0
PIL_HALF_LEN = 3.5
PIL_HEAD_Y = 13.5                   # vertical faces end, the head flares up to the beams
FLARE_Y = 1.6
FLARE_OUT = 0.45
FLARE_LIP = 0.12
BEAM_Y = 15.5                       # soffit of the transverse beams and the pillar-head beams
TB_W = 2.0
LB_HALF_W = 2.0
HAUNCH = 0.8
WALL_FILLET = 2.0                   # haunch at the foot of the side walls (on the shelves)
TB_WALL_HAUNCH = 0.9
CATWALK_Y = 12.0
CATWALK_W = 1.2
CATWALK_CHANNEL_Y = 9.5

# ------------------------------------------------------------------ UV0 scales (metres per UV unit)
S_CONCRETE = 3.75
S_FLOOR = 3.75
S_STEEL = 1.0
S_GALV = 1.0
S_GRATE = 0.5
S_HAZARD = 1.0


def z_of(u):
    return Z_PUMP - u


def u_of(z):
    return Z_PUMP - z


def line_u(k):
    return LINE_U0 + LINE_PITCH * k


def line_z(k):
    return z_of(line_u(k))


def tb_u(k):
    """Transverse beam on the shaft side of line k (k = -1 .. 10)."""
    return line_u(k) + LINE_PITCH * 0.5


def pillar_rows(k):
    """v of the pillars on line k."""
    if k % 2 == 1:
        return [-28.0, -14.0, 0.0, 14.0, 28.0]
    rows = [-21.0, -7.0, 7.0, 21.0]
    if k != 10:
        rows = [-28.0] + rows + [28.0]
    return rows


def pillars():
    """(x, z, v, k) of the 59 pillars in Godot space."""
    return [(-v, line_z(k), v, k) for k in range(LINES) for v in pillar_rows(k)]


def lerp(a, b, t):
    return a + (b - a) * t


def wall_half(u):
    """Half width of the tank (inner face of the side walls) at u."""
    if u <= CHAMFER_U0:
        return INNER_HALF
    t = min(1.0, (u - CHAMFER_U0) / (END_U - CHAMFER_U0))
    return lerp(INNER_HALF, END_HALF, t)


def crest(u):
    """Half width of the trench at the top of its slope."""
    a, b, c = TRENCH_U
    if u <= a:
        return CREST_PUMP
    if u <= b:
        return lerp(CREST_PUMP, CREST_MAIN, (u - a) / (b - a))
    if u <= c:
        return CREST_MAIN
    return lerp(CREST_MAIN, CREST_END, min(1.0, (u - c) / (END_U - c)))


def toe(u):
    return crest(u) - SLOPE_RUN


def on_shelf(v, u):
    """A pillar stands on the shelf when its inner face clears the trench crest."""
    return abs(v) - PIL_R >= crest(u) - FLARE_OUT - 0.05


# ------------------------------------------------------------------ colours
def blackbody(kelvin):
    """Approximate linear-sRGB colour of a blackbody (normalised to max 1)."""
    t = kelvin / 100.0
    if t <= 66:
        r = 255.0
        g = 99.4708025861 * math.log(t) - 161.1195681661
        b = 0.0 if t <= 19 else 138.5177312231 * math.log(t - 10) - 305.0447927307
    else:
        r = 329.698727446 * ((t - 60) ** -0.1332047592)
        g = 288.1221695283 * ((t - 60) ** -0.0755148492)
        b = 255.0
    c = [max(0.0, min(255.0, v)) / 255.0 for v in (r, g, b)]
    lin = [(v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    m = max(lin)
    return tuple(v / m for v in lin)



LAMP_K = 4800.0                     # LED high-bay floods (photos: cool white)
WALL_LAMP_K = 4300.0
EXIT_K = 0.0                        # green exit light (colour given directly)

# steel paint tints (vertex colour COLOR_0, linear)
TINT = {
    "fixture": (0.30, 0.31, 0.31),      # luminaire bodies
    "grey": (0.42, 0.43, 0.43),
    "green": (0.10, 0.30, 0.16),        # catwalk underside paint (photo 2008)
    "yellow": (0.80, 0.52, 0.05),
    "black": (0.035, 0.035, 0.038),
    "white": (0.78, 0.78, 0.76),
    "red": (0.55, 0.06, 0.04),
    "lens": (1.0, 1.0, 1.0),
}

# ------------------------------------------------------------------ space conversion
G2B = Matrix(((1.0, 0.0, 0.0, 0.0), (0.0, 0.0, -1.0, 0.0), (0.0, 1.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)))


def g2b(p):
    """Godot point -> Blender point."""
    return Vector((p[0], -p[2], p[1]))


def b2g(p):
    return Vector((p[0], p[2], -p[1]))


def V(x, y, z):
    return Vector((float(x), float(y), float(z)))


def smoothstep(a, b, x):
    if b == a:
        return 0.0 if x < a else 1.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def fbm(p, octaves=3, seed=0.0):
    """Python fBm in [0, 1] (mathutils noise), for vertex colours and placement."""
    total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
    for _ in range(octaves):
        q = Vector((p[0] * freq + seed * 17.13, p[1] * freq + seed * 3.71, p[2] * freq - seed * 9.37))
        total += amp * mnoise.noise(q, noise_basis="PERLIN_ORIGINAL")
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return 0.5 + 0.5 * total / norm


# ------------------------------------------------------------------ mesh accumulator (Godot space)
UV_WORLD, UV_FACE, UV_EXPLICIT = 0, 1, 2


class GAcc:
    """bmesh accumulator in Godot space.

    UV0: per-face box projection in module coordinates (UV_WORLD, seamless across modules
    when the scale divides 15 m), box projection aligned to the face's own edge (UV_FACE,
    pillars: formwork panels start at the arris) or explicit UVs.
    COLOR (corner): steel tint, or the floor wetness masks (set by colour_fn at the end).
    """

    def __init__(self, scale=1.0, color=(1.0, 1.0, 1.0, 1.0)):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = self.bm.loops.layers.float_color.new("Color")
        self.l_mode = self.bm.faces.layers.int.new("cis_uvmode")
        self.l_scale = self.bm.faces.layers.float.new("cis_uvscale")
        self.l_offu = self.bm.faces.layers.float.new("cis_uvoffu")
        self.l_offv = self.bm.faces.layers.float.new("cis_uvoffv")
        self.scale = scale
        self.color = color

    # -------------------------------------------------------------- core
    def face(self, pts, smooth=False, mode=UV_WORLD, scale=None, uv=None, color=None, offu=0.0, offv=0.0, out=None):
        verts = [self.bm.verts.new(Vector(p)) for p in pts]
        f = self.bm.faces.new(verts)
        f.smooth = smooth
        f[self.l_mode] = UV_EXPLICIT if uv is not None else mode
        f[self.l_scale] = scale if scale is not None else self.scale
        f[self.l_offu] = offu
        f[self.l_offv] = offv
        c = color if color is not None else self.color
        if len(c) == 3:
            c = (c[0], c[1], c[2], 1.0)
        for i, loop in enumerate(f.loops):
            loop[self.col] = c
            if uv is not None:
                loop[self.uv].uv = uv[i]
        f.normal_update()
        if out is not None:
            self.orient(f, out)
        return f

    def orient(self, f, outward):
        """Flip f so its normal agrees with the outward direction (a Vector) ."""
        if f.normal.dot(Vector(outward)) < 0.0:
            f.normal_flip()
        return f

    def quad(self, a, b, c, d, **kw):
        return self.face((a, b, c, d), **kw)

    def box(self, mn, mx, skip=(), **kw):
        x0, y0, z0 = mn
        x1, y1, z1 = mx
        P = lambda x, y, z: V(x, y, z)
        faces = []
        spec = {
            "-x": ((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (-1, 0, 0)),
            "+x": ((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1), (1, 0, 0)),
            "-y": ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0)),
            "+y": ((x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (0, 1, 0)),
            "-z": ((x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (0, 0, -1)),
            "+z": ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (0, 0, 1)),
        }
        for key, (a, b, c, d, n) in spec.items():
            if key in skip:
                continue
            faces.append(self.face((P(*a), P(*b), P(*c), P(*d)), out=n, **kw))
        return faces

    def obox(self, center, size, M=None, skip=(), **kw):
        """Box of size (sx, sy, sz) about center, optionally transformed by a 3x3/4x4 matrix M
        (rotation about the centre)."""
        c = Vector(center)
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        R = (M.to_3x3() if M is not None else Matrix.Identity(3))
        corners = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    corners[(sx, sy, sz)] = c + R @ Vector((sx * hx, sy * hy, sz * hz))
        faces = []
        for axis in range(3):
            for s in (-1, 1):
                key = ("-" if s < 0 else "+") + "xyz"[axis]
                if key in skip:
                    continue
                quad = []
                for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    idx = [0, 0, 0]
                    idx[axis] = s
                    others = [i for i in range(3) if i != axis]
                    idx[others[0]] = a
                    idx[others[1]] = b
                    quad.append(corners[tuple(idx)])
                n = R @ Vector([s if i == axis else 0 for i in range(3)])
                faces.append(self.face(quad, out=n, **kw))
        return faces

    def rings(self, rings, closed=True, smooth=False, center_fn=None, **kw):
        """Skin consecutive rings (lists of Vectors with equal counts). Faces point away from
        center_fn(point) (default: away from each ring's centroid)."""
        faces = []
        for k in range(len(rings) - 1):
            ra, rb = rings[k], rings[k + 1]
            n = len(ra)
            ca = sum(ra, Vector()) / n
            cb = sum(rb, Vector()) / n
            last = n if closed else n - 1
            for i in range(last):
                j = (i + 1) % n
                pts = (ra[i], ra[j], rb[j], rb[i])
                if (pts[0] - pts[3]).length < 1e-7 and (pts[1] - pts[2]).length < 1e-7:
                    continue
                mid = (ra[i] + ra[j] + rb[j] + rb[i]) * 0.25
                cen = center_fn(mid) if center_fn else (ca + cb) * 0.5
                f = self.face(pts, smooth=smooth, **kw)
                self.orient(f, mid - cen)
                faces.append(f)
        return faces

    def cap(self, ring, normal, **kw):
        return self.face(list(ring), out=normal, **kw)

    def cyl(self, p0, p1, r, segs=12, caps=True, smooth=True, r1=None, **kw):
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0).normalized()
        ref = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
        u = d.cross(ref).normalized()
        v = d.cross(u).normalized()
        ra = [p0 + (u * math.cos(TAU * i / segs) + v * math.sin(TAU * i / segs)) * r for i in range(segs)]
        rr = r if r1 is None else r1
        rb = [p1 + (u * math.cos(TAU * i / segs) + v * math.sin(TAU * i / segs)) * rr for i in range(segs)]
        axis_pt = lambda m: p0 + d * (m - p0).dot(d)
        faces = self.rings([ra, rb], closed=True, smooth=smooth, center_fn=axis_pt, **kw)
        if caps:
            faces.append(self.cap(ra, -d, **kw))
            faces.append(self.cap(rb, d, **kw))
        return faces

    def tube(self, path, r, segs=8, closed=False, caps=True, smooth=True, **kw):
        pts = [Vector(p) for p in path]
        n = len(pts)
        tangents = []
        for k in range(n):
            if closed:
                d = pts[(k + 1) % n] - pts[(k - 1) % n]
            elif k == 0:
                d = pts[1] - pts[0]
            elif k == n - 1:
                d = pts[-1] - pts[-2]
            else:
                d = (pts[k + 1] - pts[k]).normalized() + (pts[k] - pts[k - 1]).normalized()
            tangents.append(d.normalized())
        ref = Vector((0, 1, 0)) if abs(tangents[0].y) < 0.9 else Vector((1, 0, 0))
        normal = tangents[0].cross(ref).normalized()
        rings = []
        for k in range(n):
            t = tangents[k]
            normal = (normal - t * normal.dot(t)).normalized()
            binormal = t.cross(normal)
            # keep the cross-section size constant through bends (mitre)
            scale = 1.0
            if 0 < k < n - 1 or closed:
                a = (pts[(k + 1) % n] - pts[k]).normalized()
                b = (pts[k] - pts[(k - 1) % n]).normalized()
                cosh = max(0.5, math.sqrt(max(0.0, (1.0 + a.dot(b)) * 0.5)))
                scale = 1.0 / cosh
            ring = []
            for i in range(segs):
                ang = TAU * i / segs
                off = normal * math.cos(ang) + binormal * math.sin(ang)
                # stretch only the component in the bend plane
                ring.append(pts[k] + off * r * (1.0 if scale == 1.0 else 1.0) )
            rings.append(ring)
        faces = []
        segs_n = n if closed else n - 1
        for k in range(segs_n):
            ra, rb = rings[k], rings[(k + 1) % n]
            pa, pb = pts[k], pts[(k + 1) % n]
            for i in range(segs):
                j = (i + 1) % segs
                f = self.face((ra[i], ra[j], rb[j], rb[i]), smooth=smooth, **kw)
                mid = (ra[i] + ra[j] + rb[j] + rb[i]) * 0.25
                axis = pb - pa
                foot = pa + axis * ((mid - pa).dot(axis) / max(1e-9, axis.length_squared))
                self.orient(f, mid - foot)
                faces.append(f)
        if caps and not closed:
            faces.append(self.cap(rings[0], -tangents[0], **kw))
            faces.append(self.cap(rings[-1], tangents[-1], **kw))
        return faces

    def sweep(self, path, profile, up=Vector((0, 1, 0)), closed_profile=True, caps=True, smooth=False, **kw):
        """Sweep a 2D profile [(s, t)] along a polyline: s along the side vector (path x up),
        t along up. Mitred corners."""
        pts = [Vector(p) for p in path]
        n = len(pts)
        rings = []
        for k in range(n):
            if k == 0:
                d = pts[1] - pts[0]
            elif k == n - 1:
                d = pts[-1] - pts[-2]
            else:
                d = (pts[k + 1] - pts[k]).normalized() + (pts[k] - pts[k - 1]).normalized()
            d.normalize()
            side = d.cross(up).normalized()
            upv = side.cross(d).normalized()
            mit = 1.0
            if 0 < k < n - 1:
                a = (pts[k + 1] - pts[k]).normalized()
                cosh = max(0.3, abs(a.dot(d)))
                mit = 1.0 / cosh
            rings.append([pts[k] + side * (s * mit) + upv * t for (s, t) in profile])
        faces = []
        m = len(profile)
        last = m if closed_profile else m - 1
        for k in range(n - 1):
            ra, rb = rings[k], rings[k + 1]
            cen_a = sum(ra, Vector()) / m
            cen_b = sum(rb, Vector()) / m
            for i in range(last):
                j = (i + 1) % m
                f = self.face((ra[i], ra[j], rb[j], rb[i]), smooth=smooth, **kw)
                mid = (ra[i] + ra[j] + rb[j] + rb[i]) * 0.25
                self.orient(f, mid - (cen_a + cen_b) * 0.5)
                faces.append(f)
        if caps and closed_profile:
            faces.append(self.cap(rings[0], -(pts[1] - pts[0]).normalized(), **kw))
            faces.append(self.cap(rings[-1], (pts[-1] - pts[-2]).normalized(), **kw))
        return faces

    def lathe(self, prof, segs, M=None, smooth=True, sharp_rows=(), **kw):
        """Revolve (r, h) pairs about the local +Y axis (Godot up), transformed by M (4x4).
        Profile traced top -> bottom along the outside; faces point away from the axis."""
        M = M or Matrix.Identity(4)
        rings = []
        for (r, h) in prof:
            rings.append([M @ Vector((r * math.cos(TAU * i / segs), h, r * math.sin(TAU * i / segs))) for i in range(segs)])
        axis0 = M @ Vector((0, 0, 0))
        axis1 = M @ Vector((0, 1, 0))
        ax = (axis1 - axis0).normalized()
        faces = []
        for k in range(len(rings) - 1):
            ra, rb = rings[k], rings[k + 1]
            dr = prof[k + 1][0] - prof[k][0]
            dh = prof[k + 1][1] - prof[k][1]
            for i in range(segs):
                j = (i + 1) % segs
                pts = (ra[i], ra[j], rb[j], rb[i])
                if (pts[0] - pts[1]).length < 1e-7 and (pts[2] - pts[3]).length < 1e-7:
                    continue
                if (pts[0] - pts[1]).length < 1e-7:
                    pts = (ra[i], rb[j], rb[i])
                elif (pts[2] - pts[3]).length < 1e-7:
                    pts = (ra[i], ra[j], rb[j])
                f = self.face(pts, smooth=smooth, **kw)
                mid = sum(pts, Vector()) / len(pts)
                foot = axis0 + ax * (mid - axis0).dot(ax)
                rad = mid - foot
                rad = rad.normalized() if rad.length > 1e-7 else Vector((0, 0, 0))
                # profile traced top -> bottom along the outside: outward 2D normal = (-dh, dr)
                self.orient(f, rad * (-dh) + ax * dr)
                faces.append(f)
        return faces

    # -------------------------------------------------------------- finish
    def _uv_for(self, f):
        mode = f[self.l_mode]
        if mode == UV_EXPLICIT:
            return
        s = f[self.l_scale] or 1.0
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        coords = []
        for loop in f.loops:
            p = loop.vert.co
            if ax == 0:
                u, v = (-p.z if n.x > 0 else p.z), p.y
            elif ax == 2:
                u, v = (p.x if n.z > 0 else -p.x), p.y
            else:
                u, v = (p.x, -p.z) if n.y > 0 else (-p.x, -p.z)
            coords.append([u, v])
        if mode == UV_FACE:
            umin = min(c[0] for c in coords)
            for c in coords:
                c[0] -= umin
        for loop, (u, v) in zip(f.loops, coords):
            loop[self.uv].uv = (u / s + f[self.l_offu], v / s + f[self.l_offv])

    def to_object(self, name, material, collection, colour_fn=None, merge=True):
        bm = self.bm
        bm.normal_update()
        for f in bm.faces:
            self._uv_for(f)
        if colour_fn is not None:
            for f in bm.faces:
                for loop in f.loops:
                    loop[self.col] = colour_fn(loop.vert.co, f)
        if merge:
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
        bm.transform(G2B)
        mesh = bpy.data.meshes.get(name)
        if mesh is None:
            mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        for attr in ("cis_uvmode", "cis_uvscale", "cis_uvoffu", "cis_uvoffv"):
            a = mesh.attributes.get(attr)
            if a is not None:
                mesh.attributes.remove(a)
        mesh.materials.clear()
        mats = material if isinstance(material, (list, tuple)) else [material]
        for m in mats:
            mesh.materials.append(m)
        if mesh.color_attributes.get("Color") is not None:
            mesh.color_attributes.active_color = mesh.color_attributes["Color"]
            try:
                mesh.color_attributes.render_color_index = mesh.color_attributes.active_color_index
            except Exception:
                pass
        obj = bpy.data.objects.get(name)
        if obj is None:
            obj = bpy.data.objects.new(name, mesh)
        else:
            obj.data = mesh
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        collection.objects.link(obj)
        obj.location = (0.0, 0.0, 0.0)
        obj.rotation_euler = (0.0, 0.0, 0.0)
        obj.scale = (1.0, 1.0, 1.0)
        return obj


def tri_count(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


# ------------------------------------------------------------------ shader node builder
class NB:
    """Tiny shader-node builder: inputs may be floats or sockets."""

    def __init__(self, tree_owner, clear=True):
        if isinstance(tree_owner, bpy.types.NodeTree):
            self.nt = tree_owner
        else:
            try:
                tree_owner.use_nodes = True
            except Exception:
                pass
            self.nt = tree_owner.node_tree
        if clear:
            self.nt.nodes.clear()
        self.x = -3000

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        n.location = (self.x, 0)
        self.x += 6
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def _in(self, sock, value):
        if value is None:
            return
        if hasattr(value, "is_output"):
            self.nt.links.new(value, sock)
        else:
            sock.default_value = value

    def math(self, op, a, b=None, c=None, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self._in(n.inputs[0], a)
        self._in(n.inputs[1], b)
        self._in(n.inputs[2], c)
        return n.outputs[0]

    def add(self, a, b):
        return self.math("ADD", a, b)

    def sub(self, a, b):
        return self.math("SUBTRACT", a, b)

    def mul(self, a, b):
        return self.math("MULTIPLY", a, b)

    def div(self, a, b):
        return self.math("DIVIDE", a, b)

    def madd(self, a, b, c):
        return self.math("MULTIPLY_ADD", a, b, c)

    def mix(self, a, b, t):
        return self.add(a, self.mul(self.sub(b, a), t))

    def clamp01(self, a):
        return self.math("ADD", a, 0.0, clamp=True)

    def smooth(self, a, lo, hi):
        n = self.node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP", clamp=True)
        self._in(n.inputs["Value"], a)
        self._in(n.inputs["From Min"], lo)
        self._in(n.inputs["From Max"], hi)
        n.inputs["To Min"].default_value = 0.0
        n.inputs["To Max"].default_value = 1.0
        return n.outputs["Result"]

    def combine(self, x, y, z):
        n = self.node("ShaderNodeCombineXYZ")
        self._in(n.inputs[0], x)
        self._in(n.inputs[1], y)
        self._in(n.inputs[2], z)
        return n.outputs[0]

    def rgb(self, r, g, b):
        n = self.node("ShaderNodeCombineColor")
        self._in(n.inputs[0], r)
        self._in(n.inputs[1], g)
        self._in(n.inputs[2], b)
        return n.outputs[0]

    def separate(self, v):
        n = self.node("ShaderNodeSeparateXYZ")
        self._in(n.inputs[0], v)
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def sep_rgb(self, c):
        n = self.node("ShaderNodeSeparateColor")
        self._in(n.inputs[0], c)
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def noise3(self, vec, scale=1.0, detail=2.0, rough=0.5, lac=2.0, distortion=0.0):
        n = self.node("ShaderNodeTexNoise", noise_dimensions="3D")
        try:
            n.normalize = True
        except Exception:
            pass
        self._in(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Lacunarity"].default_value = lac
        n.inputs["Distortion"].default_value = distortion
        return n.outputs["Fac"]

    def noise4(self, vec, w, detail=2.0, rough=0.5, lac=2.0, distortion=0.0):
        n = self.node("ShaderNodeTexNoise", noise_dimensions="4D")
        try:
            n.normalize = True
        except Exception:
            pass
        self._in(n.inputs["Vector"], vec)
        self._in(n.inputs["W"], w)
        n.inputs["Scale"].default_value = 1.0
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Lacunarity"].default_value = lac
        n.inputs["Distortion"].default_value = distortion
        return n.outputs["Fac"]

    def voronoi4(self, vec, w, randomness=1.0, feature="F1"):
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature=feature, distance="EUCLIDEAN")
        self._in(n.inputs["Vector"], vec)
        self._in(n.inputs["W"], w)
        n.inputs["Scale"].default_value = 1.0
        n.inputs["Randomness"].default_value = randomness
        return n.outputs["Distance"], n.outputs["Color"]

    def voronoi3(self, vec, scale=1.0, randomness=1.0, feature="F1"):
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature=feature, distance="EUCLIDEAN")
        self._in(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = randomness
        return n.outputs["Distance"], n.outputs["Color"]

    def white(self, vec, dims="3D"):
        n = self.node("ShaderNodeTexWhiteNoise", noise_dimensions=dims)
        self._in(n.inputs["Vector"], vec)
        return n.outputs["Value"]

    def bw(self, color):
        n = self.node("ShaderNodeRGBToBW")
        self._in(n.inputs[0], color)
        return n.outputs[0]

    def value(self, v, label=None):
        n = self.node("ShaderNodeValue")
        n.outputs[0].default_value = v
        if label:
            n.label = label
            n.name = label
        return n.outputs[0]

    def image(self, img, uvmap="UVMap", interp="Linear", ext="REPEAT", vec=None):
        n = self.node("ShaderNodeTexImage")
        n.image = img
        n.interpolation = interp
        n.extension = ext
        if vec is None:
            uvn = self.node("ShaderNodeUVMap")
            uvn.uv_map = uvmap
            self.nt.links.new(uvn.outputs[0], n.inputs[0])
        else:
            self._in(n.inputs[0], vec)
        return n


# ------------------------------------------------------------------ collections
def collection(name, parent=None):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    parent = parent or bpy.context.scene.collection
    if col.name not in [c.name for c in parent.children]:
        parent.children.link(col)
    return col


def clear_collection(col):
    for child in list(col.children):
        clear_collection(child)
    for obj in list(col.objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and getattr(data, "users", 1) == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Light):
                bpy.data.lights.remove(data)
            elif isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)
            elif isinstance(data, bpy.types.Curve):
                bpy.data.curves.remove(data)


def empty(name, collection_, pos_g, aim_g=None, up_g=(0.0, 1.0, 0.0), size=0.3):
    """Anchor empty at a Godot position. aim_g (Godot direction) -> Blender local +Y, which the
    glTF exporter turns into the Godot node's -Z."""
    obj = bpy.data.objects.get(name)
    if obj is None:
        obj = bpy.data.objects.new(name, None)
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection_.objects.link(obj)
    obj.empty_display_type = "SINGLE_ARROW" if aim_g is not None else "PLAIN_AXES"
    obj.empty_display_size = size
    obj.location = g2b(pos_g)
    if aim_g is not None:
        d = g2b(aim_g).normalized()
        up = g2b(up_g).normalized()
        if abs(d.dot(up)) > 0.98:
            up = g2b((0.0, 0.0, 1.0))
        # local +Y = d, local +Z ~ up
        x = d.cross(up).normalized()
        z = x.cross(d).normalized()
        R = Matrix((x, d, z)).transposed()
        obj.rotation_euler = R.to_euler()
    else:
        obj.rotation_euler = (0.0, 0.0, 0.0)
    return obj

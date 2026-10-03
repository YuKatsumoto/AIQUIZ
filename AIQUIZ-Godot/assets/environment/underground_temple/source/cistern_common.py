"""Shared constants and helpers for the underground cistern (地下神殿) art.

docs/sudden_death_m3_interface.md is the contract; docs/sudden_death_underground.md ch.6
the brief. Loaded by the build / bake / export scripts INSIDE the user's live Blender
(never a headless process):

    ns = {}
    exec(open(SOURCE + "/cistern_common.py", encoding="utf-8").read(), ns)

Geometry is authored in GODOT space (metres, Y up, flood flows toward +Z). GAcc.to_object()
rotates the finished bmesh into Blender space, Blender (x, y, z) = Godot (x, -z, y), which is
exactly what the glTF exporter (+Y up) undoes. Light anchors (empties) aim their Blender local
+Y along the beam: that axis becomes the Godot node's -Z.

Object names carry a module tag: "<TAG>|CIS_Shell", "<TAG>|CIS_Light_Flood_0". The exporter
strips "<TAG>|" so every GLB gets the clean contract names.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils import noise as mnoise

ROOT = "C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple"
SOURCE = ROOT + "/source"
TEXTURES = ROOT + "/textures"
PREVIEWS = SOURCE + "/previews"
BLEND_PATH = SOURCE + "/underground_temple.blend"

TAU = math.tau

# ------------------------------------------------------------------ hall (interface values)
HALF_W = 45.0               # outer walls (inner faces) at x = +-45
WALL_T = 1.0
CEIL_Y = 18.0               # soffit
SLAB_TOP = 19.0
CORR_X = 11.9               # inner pillar inner faces
BAY = 15.0
HB = 7.5                    # module z range -7.5 .. +7.5
PILLAR_X = (12.9, 25.8, 38.7)
PILLAR_HW = 1.0             # 2 m wide (x)
PILLAR_Z0, PILLAR_Z1 = 0.0, 7.0
CHAMFER = 0.06              # pillar edge chamfer (real geometry)
JOINT_G = 0.016             # half width of a V-groove (cold joints, expansion joints)
JOINT_D = 0.014             # groove depth
KICKER = 0.15               # first pour (kicker) joint
LIFT = 3.75                 # pour height = two form-panel rows
COLD_JOINTS = (3.75, 7.5, 11.25, 15.0)
TB_Z = (2.9, 4.1)           # transverse beam over the pillar row (z extent)
TB_BOTTOM = 16.0
TB_HAUNCH = (1.0, 0.5)      # length along x, drop
LB_BOTTOM = 16.5            # longitudinal beams between pillar rows (x extent = pillar)
LB_HAUNCH = (0.5, 0.5)
BEAM_CH = 0.05              # beam bottom edge chamfer
CH_X = (10.4, 10.8)         # corridor drain channels (|x|)
CH_DEPTH = 0.35
RAIL_X = 11.84              # corridor railing between the inner pillars
FLOOD_Y = 7.0
FLOOD_Z = 3.5
OPENING_R = 7.0

# ------------------------------------------------------------------ UV0 scales (metres per UV unit)
# Concrete: 3.75 m = 4 x 2 form panels of 0.9375 x 1.875 m (0.9 x 1.8 rounded so the tile
# divides the 15 m bay: seamless UVs across modules).
S_CONCRETE = 3.75
S_FLOOR = 3.75
S_STEEL = 1.0
S_GALV = 1.0
S_GRATE = 0.5
S_HAZARD = 1.0

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


FLOOD_K = 5000.0
AMBER_K = 2000.0
WINDOW_K = 3600.0

# steel paint tints (vertex colour COLOR_0, linear)
TINT = {
    "fixture": (0.20, 0.215, 0.20),     # dark grey-green luminaire bodies
    "blue": (0.24, 0.33, 0.40),         # grey-blue gate / machinery
    "yellow": (0.80, 0.52, 0.05),       # safety yellow
    "black": (0.035, 0.035, 0.038),     # cable sheaths, rubber
    "white": (0.78, 0.78, 0.76),
    "grey": (0.42, 0.43, 0.43),
    "green": (0.10, 0.22, 0.14),        # cabinet green
    "red": (0.55, 0.06, 0.04),          # fire equipment
    "orange": (0.85, 0.30, 0.04),
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

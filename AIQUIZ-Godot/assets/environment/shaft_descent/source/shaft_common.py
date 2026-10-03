"""Shared constants and helpers for the shaft-descent assets (docs/sudden_death_underground.md ch.5).

Loaded by build_shaft.py / bake_shaft.py / export_shaft.py inside the user's live
Blender (never a headless process):

    ns = {}
    exec(open(SOURCE + "/shaft_common.py", encoding="utf-8").read(), ns)

Blender is Z-up metres; Godot is Y-up (glTF maps Blender (x, y, z) to Godot
(x, z, -y)). Prop azimuths are written in GODOT terms: psi is measured from +X
toward +Z in Godot, which is the Blender angle -psi.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = "C:/AIQUIZ/AIQUIZ-Godot/assets/environment/shaft_descent"
SOURCE = ROOT + "/source"
TEXTURES = ROOT + "/textures"
BLEND_PATH = SOURCE + "/shaft_descent.blend"

TAU = math.tau

# ------------------------------------------------------------------ shaft tile
R = 7.0                     # inner radius of the concrete
TILE_H = 5.0                # one lamp row
LIFT = TILE_H / 3.0         # pour height between horizontal form joints (1.667 m, tiles every 5 m)
JOINT_Z = (0.5, 0.5 + LIFT, 0.5 + 2.0 * LIFT)
PANELS = 24                 # vertical form-panel joints around the circumference (1.83 m)
PANEL_W = TAU * R / PANELS
WALL_SEGMENTS = 192

LAMP_PSI = (45.0, 135.0, 225.0, 315.0)   # Godot azimuths; the guide rails own +-X
LAMP_Z = 2.95               # light centre (well-glass centre) inside a tile
LAMP_R = 6.55               # luminaire axis radius
RAIL_PSI = (0.0, 180.0)
RAIL_BRACKET_Z = tuple(0.29 + 1.25 * k for k in range(4))   # clear of the form joints
STANDOFF_Z = tuple(0.708 + 1.25 * k for k in range(4))
HOOP_Z = tuple(1.125 + 1.25 * k for k in range(4))
RUNG_Z = tuple(0.15625 + 0.3125 * k for k in range(16))
PIPES = (
    {"psi": 60.0, "radius": 0.16, "v": 6.69, "flange_z": 4.40, "segs": 24},
    {"psi": 67.0, "radius": 0.11, "v": 6.74, "flange_z": 1.90, "segs": 20},
)
PIPE_SUPPORT_Z = (1.125, 3.625)
LADDER_PSI = 112.0
LADDER_V = 6.72
TRAY_PSI = 160.0
CONDUIT_Z = 3.45
CONDUIT_R = 6.97
SIGN_PSI = 90.0             # depth signs are placed by Godot on this azimuth

# ------------------------------------------------------------------ deck / mouth
DECK_RADIUS = 5.2
GRATING_RADIUS = 4.95
DECK_DEPTH = 0.45
ANCHOR_R = 4.4
ANCHOR_PSI = (45.0, 135.0, 225.0, 315.0)
ANCHOR_TOP = 0.30
SHOE_V = 6.42
COLLAR_IN = 7.0
COLLAR_OUT = 7.6
IRIS_IN = 5.205             # meets the deck edge (5.2) so a closed iris shows nothing below
IRIS_OVERLAP = 0.014        # each blade tucks this far under its neighbour (no see-through seams)
PAD_X = 2.2                 # SuddenDeathLayout.PAD_X: score-tower sockets at (+-PAD_X, 0, 0)
PAD_PLATE_R = 1.3           # opaque plate under each socket (towers hang tier columns below)
IRIS_BLADES = 8
IRIS_TWIST = math.radians(22.0)
IRIS_HINGE_R = 7.10         # blades fold down about a tangential hinge here, into the wall pocket
IRIS_HINGE_Y = -0.045
COLLAR_PROUD = 0.008        # collar top sits 8 mm above the floor plane so it never z-fights it
BEACON_PSI = (45.0, 135.0, 225.0, 315.0)
BEACON_R = 7.3


def godot_angle(psi_deg):
    """Blender azimuth (radians) of a Godot azimuth in degrees."""
    return -math.radians(psi_deg)


def frame(psi_deg):
    """Local prop frame at Godot azimuth psi: (u tangential, v radius from the axis, w up).

    Columns are t, r, z with t x r = z, so the matrix is a proper rotation.
    """
    a = math.radians(psi_deg)
    t = Vector((-math.sin(a), -math.cos(a), 0.0))
    r = Vector((math.cos(a), -math.sin(a), 0.0))
    return Matrix((
        (t.x, r.x, 0.0, 0.0),
        (t.y, r.y, 0.0, 0.0),
        (0.0, 0.0, 1.0, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    ))


IDENT = Matrix.Identity(4)


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def rot_z(angle):
    return Matrix.Rotation(angle, 4, "Z")


class Acc:
    """bmesh accumulator: every helper takes a local point list and a 4x4 matrix."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    # -------------------------------------------------------------- utilities
    def _faces_of(self, verts):
        faces = set()
        for v in verts:
            faces.update(v.link_faces)
        return faces

    def _finish(self, verts, axis=None, smooth=False):
        faces = self._faces_of(verts)
        for f in faces:
            f.normal_update()
            if axis is not None:
                f.smooth = abs(f.normal.dot(axis)) < 0.5
            else:
                f.smooth = smooth
        return faces

    # -------------------------------------------------------------- primitives
    def box(self, c, s, M=IDENT, rot=None):
        mat = M @ T(*c) @ (rot if rot is not None else IDENT) @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mat, calc_uvs=True)
        return self._finish(res["verts"], smooth=False)

    def cyl(self, p0, p1, r, segs=12, M=IDENT, caps=True, r2=None):
        p0 = Vector(p0)
        p1 = Vector(p1)
        d = p1 - p0
        length = d.length
        rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        mat = M @ Matrix.Translation((p0 + p1) * 0.5) @ rot
        res = bmesh.ops.create_cone(
            self.bm, cap_ends=caps, cap_tris=False, segments=segs,
            radius1=r, radius2=(r if r2 is None else r2), depth=length, matrix=mat, calc_uvs=True,
        )
        axis = (M.to_3x3() @ d).normalized()
        return self._finish(res["verts"], axis=axis)

    def lathe(self, prof, segs, M=IDENT, outward=True, smooth=True, phi0=0.0, phi1=TAU, sharp_rows=()):
        """Revolve (r, z) pairs about the local Z axis.

        Trace the profile top -> bottom along the outside silhouette; outward=True
        then points the normals away from the solid.
        """
        full = abs((phi1 - phi0) - TAU) < 1e-6
        cols = segs if full else segs + 1
        rows = []
        for j, (r, z) in enumerate(prof):
            if r < 1e-7:
                rows.append(("pole", self.bm.verts.new(M @ Vector((0.0, 0.0, z)))))
                continue
            ring = []
            for i in range(cols):
                a = phi0 + (phi1 - phi0) * i / segs
                ring.append(self.bm.verts.new(M @ Vector((r * math.cos(a), r * math.sin(a), z))))
            rows.append(("ring", ring))
        made = []
        total = len(prof)
        for j in range(total - 1):
            ka, ra = rows[j]
            kb, rb = rows[j + 1]
            span = segs
            for i in range(span):
                i1 = (i + 1) % cols if full else i + 1
                ua0, ua1 = i / segs, (i + 1) / segs
                va, vb = 1.0 - j / (total - 1), 1.0 - (j + 1) / (total - 1)
                if ka == "pole" and kb == "pole":
                    continue
                if ka == "pole":
                    quad = [(ra, (ua0 + 0.5 / segs, va)), (rb[i1], (ua1, vb)), (rb[i], (ua0, vb))]
                elif kb == "pole":
                    quad = [(ra[i], (ua0, va)), (ra[i1], (ua1, va)), (rb, (ua0 + 0.5 / segs, vb))]
                else:
                    quad = [(ra[i], (ua0, va)), (ra[i1], (ua1, va)), (rb[i1], (ua1, vb)), (rb[i], (ua0, vb))]
                if outward:
                    quad.reverse()
                face = self.bm.faces.new([q[0] for q in quad])
                for loop, q in zip(face.loops, quad):
                    loop[self.uv].uv = q[1]
                face.smooth = smooth
                made.append(face)
        for f in made:
            f.normal_update()
        for row in sharp_rows:
            kind, ring = rows[row]
            if kind == "ring":
                for i in range(cols):
                    a = ring[i]
                    b = ring[(i + 1) % cols] if full else (ring[i + 1] if i + 1 < cols else None)
                    if b is None:
                        continue
                    e = self.bm.edges.get((a, b))
                    if e is not None:
                        e.smooth = False
        return made

    def tube(self, path, r, segs=6, M=IDENT, closed=False, caps=True):
        """Sweep a circle along a local polyline (parallel-transport frames)."""
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
        ref = Vector((0.0, 0.0, 1.0)) if abs(tangents[0].z) < 0.9 else Vector((1.0, 0.0, 0.0))
        normal = tangents[0].cross(ref).normalized()
        rings = []
        for k in range(n):
            t = tangents[k]
            normal = (normal - t * normal.dot(t)).normalized()
            binormal = t.cross(normal)
            ring = []
            for i in range(segs):
                a = TAU * i / segs
                p = pts[k] + (normal * math.cos(a) + binormal * math.sin(a)) * r
                ring.append(self.bm.verts.new(M @ p))
            rings.append(ring)
        faces = []
        last = n if closed else n - 1
        for k in range(last):
            ra = rings[k]
            rb = rings[(k + 1) % n]
            for i in range(segs):
                f = self.bm.faces.new((ra[i], ra[(i + 1) % segs], rb[(i + 1) % segs], rb[i]))
                f.smooth = True
                faces.append(f)
        if caps and not closed:
            f0 = self.bm.faces.new(list(reversed(rings[0])))
            f1 = self.bm.faces.new(rings[-1])
            f0.smooth = f1.smooth = False
            faces += [f0, f1]
        for f in faces:
            f.normal_update()
        # Make sure the sweep faces outward (the winding depends on the frame handedness).
        probe = faces[0]
        c = probe.calc_center_median()
        axis_pt = M @ pts[0]
        if (c - axis_pt).dot(probe.normal) < 0.0:
            for f in faces:
                f.normal_flip()
        return faces

    def sweep_rect(self, path, z, half_h, half_w, M=IDENT, caps=True):
        """Flat bar along a horizontal local path at height z: half_h across, half_w vertical."""
        pts = [Vector((p[0], p[1], z)) for p in path]
        n = len(pts)
        rings = []
        up = Vector((0.0, 0.0, 1.0))
        for k in range(n):
            if k == 0:
                d = pts[1] - pts[0]
            elif k == n - 1:
                d = pts[-1] - pts[-2]
            else:
                d = (pts[k + 1] - pts[k]).normalized() + (pts[k] - pts[k - 1]).normalized()
            side = d.normalized().cross(up).normalized()
            ring = [
                pts[k] + side * half_h + up * half_w,
                pts[k] - side * half_h + up * half_w,
                pts[k] - side * half_h - up * half_w,
                pts[k] + side * half_h - up * half_w,
            ]
            rings.append([self.bm.verts.new(M @ p) for p in ring])
        faces = []
        for k in range(n - 1):
            ra, rb = rings[k], rings[k + 1]
            for i in range(4):
                faces.append(self.bm.faces.new((ra[i], rb[i], rb[(i + 1) % 4], ra[(i + 1) % 4])))
        if caps:
            faces.append(self.bm.faces.new(rings[0]))
            faces.append(self.bm.faces.new(list(reversed(rings[-1]))))
        for f in faces:
            f.normal_update()
            f.smooth = False
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        return faces

    def ring_tube(self, center, radius, r, segs, sides, M=IDENT):
        cx, cy, cz = center
        path = [(cx + radius * math.cos(TAU * i / segs), cy + radius * math.sin(TAU * i / segs), cz) for i in range(segs)]
        return self.tube(path, r, sides, M, closed=True)

    # -------------------------------------------------------------- output
    def to_object(self, name, materials, collection, origin=None):
        mesh = bpy.data.meshes.get(name)
        if mesh is None:
            mesh = bpy.data.meshes.new(name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=0.00005)
        self.bm.to_mesh(mesh)
        self.bm.free()
        mesh.materials.clear()
        for m in materials:
            mesh.materials.append(m)
        obj = bpy.data.objects.get(name)
        if obj is None:
            obj = bpy.data.objects.new(name, mesh)
        else:
            obj.data = mesh
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        collection.objects.link(obj)
        if origin is not None:
            mesh.transform(Matrix.Translation(-Vector(origin)))
            obj.location = origin
        return obj


# ---------------------------------------------------------------------- nodes
class NB:
    """Tiny shader-node builder: inputs may be floats or sockets."""

    def __init__(self, mat):
        try:
            mat.use_nodes = True
        except Exception:
            pass
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.x = -2000

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        n.location = (self.x, 0)
        self.x += 6
        return n

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

    def madd(self, a, b, c):
        return self.math("MULTIPLY_ADD", a, b, c)

    def clamp01(self, a):
        return self.math("ADD", a, 0.0, clamp=True)

    def smooth(self, a, lo, hi):
        """smoothstep(lo, hi, a) for lo < hi; use sub(1, ...) to invert."""
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

    def separate(self, v):
        n = self.node("ShaderNodeSeparateXYZ")
        self._in(n.inputs[0], v)
        return n.outputs[0], n.outputs[1], n.outputs[2]

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

    def voronoi4(self, vec, w, randomness=1.0):
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature="F1", distance="EUCLIDEAN")
        self._in(n.inputs["Vector"], vec)
        self._in(n.inputs["W"], w)
        n.inputs["Scale"].default_value = 1.0
        n.inputs["Randomness"].default_value = randomness
        return n.outputs["Distance"], n.outputs["Color"]

    def white(self, vec):
        n = self.node("ShaderNodeTexWhiteNoise", noise_dimensions="3D")
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


def collection(name, parent=None):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    parent = parent or bpy.context.scene.collection
    if col.name not in [c.name for c in parent.children]:
        parent.children.link(col)
    return col


def clear_collection(col):
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
    for child in list(col.children):
        clear_collection(child)

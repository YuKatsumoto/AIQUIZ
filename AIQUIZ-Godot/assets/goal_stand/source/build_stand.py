"""Finish-line grandstand: three standing tiers with blue benches, a low parapet, a
back wall carrying the Higgsfield-generated AIQUIZ banner, team flag poles and
Santorini arches standing in the sea.

Blender space: origin = front centre at conveyor-top height, front faces -Y,
tiers climb toward +Y.  Godot turns the stand PI so it looks down the conveyor.
Also writes goal_stand_layout.json (spectator rows in this same space).
"""
import json
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
G = type("G", (), ns)

WIDTH = 26.0
HALF = WIDTH * 0.5
TIERS = 3
RISE = 0.55
TREAD = 1.35
FIRST_FLOOR = 0.35
PARAPET_T = 0.30
PARAPET_H = 0.50          # above the first tier floor
DECK_BOTTOM = -0.60
BACK_T = 0.30
BACK_TOP = 3.20
BENCH_DEPTH = 0.40
BENCH_H = 0.42
AISLES = [-6.0, 6.0]
AISLE_W = 1.10
WATER_Z = -8.0             # ocean surface relative to the conveyor top
SEABED_Z = -128.0
BAY = 2.6
BANNER_W, BANNER_H, BANNER_Z = 10.5, 4.5, 3.45
FLAG_X = 12.55


def tier_floor(i):
    return FIRST_FLOOR + i * RISE


def tier_front(i):
    return PARAPET_T + i * TREAD


BACK_Y = tier_front(TIERS)


def mats():
    return {
        "white": G.flat_material("GS_White", (0.93, 0.92, 0.89), 0.78),
        "tread": G.flat_material("GS_Tread", (0.80, 0.79, 0.76), 0.85),
        "blue": G.flat_material("GS_Blue", (0.12, 0.33, 0.66), 0.55),
        "seat": G.flat_material("GS_Seat", (0.16, 0.45, 0.85), 0.40),
        "trim": G.flat_material("GS_Trim", (0.58, 0.62, 0.68), 0.35, 0.6),
        "p1": G.flat_material("GS_FlagP1", (0.95, 0.55, 0.20), 0.6),
        "p2": G.flat_material("GS_FlagP2", (0.20, 0.65, 0.90), 0.6),
        "sun": G.flat_material("GS_PennantSun", (1.0, 0.80, 0.25), 0.6),
        "banner": G.image_material("GS_Banner", G.SOURCE + "/textures/banner.png"),
    }


class Stand:
    def __init__(self, m):
        self.m = m
        self.order = list(m)
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def idx(self, key):
        return self.order.index(key)

    def box(self, lo, hi, key, top=None, front=None):
        lo, hi = Vector(lo), Vector(hi)
        size = hi - lo
        m = Matrix.Translation((lo + hi) * 0.5) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        faces = {f for v in res["verts"] for f in v.link_faces}
        for f in faces:
            f.material_index = self.idx(key)
            if top and f.normal.z > 0.9:
                f.material_index = self.idx(top)
            if front and f.normal.y < -0.9:
                f.material_index = self.idx(front)
        return faces

    def prism(self, points_yz, x0, x1, key, side_key=None):
        """Extrude a YZ polygon along X (used for the stepped deck and side walls)."""
        a = [self.bm.verts.new((x0, y, z)) for y, z in points_yz]
        b = [self.bm.verts.new((x1, y, z)) for y, z in points_yz]
        n = len(points_yz)
        faces = [self.bm.faces.new(list(reversed(a))), self.bm.faces.new(b)]
        for i in range(n):
            faces.append(self.bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i])))
        for f in faces:
            f.material_index = self.idx(key)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        return faces

    def tri_prism(self, a, b, tip, depth, key):
        """Thin triangular pennant, closed so both sides render."""
        front = [self.bm.verts.new(v) for v in (a, b, tip)]
        back = [self.bm.verts.new((v[0], v[1] + depth, v[2])) for v in (a, b, tip)]
        faces = [self.bm.faces.new(front), self.bm.faces.new(list(reversed(back)))]
        for i in range(3):
            faces.append(self.bm.faces.new((front[(i + 1) % 3], front[i], back[i], back[(i + 1) % 3])))
        for f in faces:
            f.material_index = self.idx(key)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)

    def arch_panel(self, x0, x1, y0, y1, z_top, z_spring, key):
        """Panel between two piers with a round arch cut out of its underside."""
        rise = (x1 - x0) * 0.5
        steps = 10
        outline = [(x0, z_top), (x1, z_top), (x1, z_spring)]
        for k in range(1, steps):
            ang = math.pi * k / steps
            outline.append(((x0 + x1) * 0.5 + rise * math.cos(ang), z_spring + rise * math.sin(ang)))
        outline.append((x0, z_spring))
        a = [self.bm.verts.new((x, y0, z)) for x, z in outline]
        b = [self.bm.verts.new((x, y1, z)) for x, z in outline]
        n = len(outline)
        faces = [self.bm.faces.new(a), self.bm.faces.new(list(reversed(b)))]
        for i in range(n):
            faces.append(self.bm.faces.new((a[(i + 1) % n], a[i], b[i], b[(i + 1) % n])))
        for f in faces:
            f.material_index = self.idx(key)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)

    def finish(self, name, coll):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.get(name) or bpy.data.meshes.new(name)
        # Slots first: clearing slots after to_mesh() would reset every face to slot 0.
        mesh.materials.clear()
        for key in self.order:
            mesh.materials.append(self.m[key])
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.get(name)
        if obj is not None and not any(c.name.startswith("GS_") for c in obj.users_collection):
            raise RuntimeError("name collision: " + name)
        if obj is None:
            obj = bpy.data.objects.new(name, mesh)
            coll.objects.link(obj)
        obj.data = mesh
        return obj


def banner_uv(obj):
    """Map the banner quad (front face of GS_BannerBoard's material) to 0..1."""
    mesh = obj.data
    uv = mesh.uv_layers.active or mesh.uv_layers.new(name="UVMap")
    banner = list(mesh.materials).index(bpy.data.materials["GS_Banner"])
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            if poly.material_index == banner and poly.normal.y < -0.9:
                uv.data[li].uv = ((co.x + BANNER_W * 0.5) / BANNER_W, (co.z - BANNER_Z) / BANNER_H)
            else:
                uv.data[li].uv = (0.5, 0.5)


def build():
    G.scene()
    coll = G.collection("GS_Stand")
    G.clear_collection("GS_Stand")
    m = mats()
    s = Stand(m)
    # Stepped deck: parapet, three treads, back wall (YZ profile, extruded along X).
    parapet_top = tier_floor(0) + PARAPET_H
    profile = [(0.0, DECK_BOTTOM), (0.0, parapet_top), (PARAPET_T, parapet_top), (PARAPET_T, tier_floor(0))]
    for i in range(TIERS):
        profile.append((tier_front(i + 1), tier_floor(i)))
        if i + 1 < TIERS:
            profile.append((tier_front(i + 1), tier_floor(i + 1)))
    profile += [(BACK_Y, BACK_TOP), (BACK_Y + BACK_T, BACK_TOP), (BACK_Y + BACK_T, DECK_BOTTOM)]
    faces = s.prism(profile, -HALF, HALF, "white")
    for f in faces:
        c = f.calc_center_median()
        if f.normal.z > 0.9 and c.z < BACK_TOP - 0.01:
            f.material_index = s.idx("tread")
        elif f.normal.y < -0.9 and 0.2 < c.y < BACK_Y - 0.05:
            f.material_index = s.idx("blue")          # risers between tiers
    # Blue band along the parapet front and a trim cap on its top.
    s.box((-HALF, -0.02, tier_floor(0) + 0.05), (HALF, 0.0, tier_floor(0) + 0.33), "blue")
    s.box((-HALF - 0.05, -0.05, tier_floor(0) + PARAPET_H), (HALF + 0.05, PARAPET_T + 0.05, tier_floor(0) + PARAPET_H + 0.06), "trim")
    # Side walls following the steps, one metre above the treads.
    for sign in (-1.0, 1.0):
        x0, x1 = (HALF, HALF + 0.30) if sign > 0 else (-HALF - 0.30, -HALF)
        wall = [(-0.05, DECK_BOTTOM), (-0.05, tier_floor(0) + PARAPET_H + 0.06)]
        for i in range(TIERS):
            wall += [(tier_front(i) + 0.2, tier_floor(i) + 1.05), (tier_front(i + 1), tier_floor(i) + 1.05)]
        wall += [(BACK_Y + BACK_T, BACK_TOP), (BACK_Y + BACK_T, DECK_BOTTOM)]
        s.prism(wall, x0, x1, "white")
    # Benches (with aisle gaps) and aisle steps.
    spans = []
    edges = [-HALF + 0.2] + [v for a in AISLES for v in (a - AISLE_W * 0.5, a + AISLE_W * 0.5)] + [HALF - 0.2]
    for k in range(0, len(edges), 2):
        spans.append((edges[k], edges[k + 1]))
    for i in range(TIERS):
        back = tier_front(i + 1) - 0.08
        for x0, x1 in spans:
            s.box((x0, back - BENCH_DEPTH, tier_floor(i)), (x1, back, tier_floor(i) + BENCH_H), "seat", top="seat")
            s.box((x0, back - 0.05, tier_floor(i) + BENCH_H), (x1, back, tier_floor(i) + BENCH_H + 0.32), "seat")
        for a in AISLES:
            if i + 1 < TIERS:
                s.box((a - AISLE_W * 0.5, tier_front(i + 1) - 0.45, tier_floor(i)),
                      (a + AISLE_W * 0.5, tier_front(i + 1), tier_floor(i) + RISE * 0.5), "white", top="tread")
    # Banner board on two posts above the back wall.
    for x in (-BANNER_W * 0.5 + 0.6, BANNER_W * 0.5 - 0.6):
        s.box((x - 0.12, BACK_Y + 0.05, BACK_TOP - 0.2), (x + 0.12, BACK_Y + 0.29, BANNER_Z + 0.4), "trim")
    s.box((-BANNER_W * 0.5 - 0.15, BACK_Y - 0.02, BANNER_Z - 0.15), (BANNER_W * 0.5 + 0.15, BACK_Y + 0.05, BANNER_Z + BANNER_H + 0.15), "white")
    s.box((-BANNER_W * 0.5, BACK_Y - 0.06, BANNER_Z), (BANNER_W * 0.5, BACK_Y - 0.02, BANNER_Z + BANNER_H), "white", front="banner")
    # Team flag poles at the back corners. Blender -X becomes Godot +X, P1's lane.
    for sign, team in ((-1.0, "p1"), (1.0, "p2")):
        x = sign * FLAG_X
        s.box((x - 0.07, BACK_Y + 0.08, BACK_TOP), (x + 0.07, BACK_Y + 0.22, BACK_TOP + 5.2), "trim")
        s.box((x - 0.12, BACK_Y + 0.03, BACK_TOP + 5.2), (x + 0.12, BACK_Y + 0.27, BACK_TOP + 5.35), "sun")
        cloth_x0, cloth_x1 = (x + 0.07, x + 2.2) if sign < 0 else (x - 2.2, x - 0.07)
        s.box((cloth_x0, BACK_Y + 0.13, BACK_TOP + 3.85), (cloth_x1, BACK_Y + 0.17, BACK_TOP + 5.1), team)
    # Pennant string hanging along the parapet front.
    x = -HALF + 0.35
    k = 0
    while x < HALF - 0.3:
        key = ("p1", "sun", "p2")[k % 3]
        top = tier_floor(0) + PARAPET_H + 0.02
        s.tri_prism((x, -0.08, top), (x + 0.56, -0.08, top), (x + 0.28, -0.08, top - 0.36), 0.012, key)
        x += 0.62
        k += 1
    # Sea substructure: fascia, arcade in front, piers down to the seabed.
    s.box((-HALF - 0.3, -0.02, DECK_BOTTOM - 1.2), (HALF + 0.3, BACK_Y + BACK_T, DECK_BOTTOM), "white")
    bays = int(round(WIDTH / BAY))
    for k in range(bays + 1):
        px = -HALF + k * (WIDTH / bays)
        for y0, y1 in ((0.0, 0.6), (BACK_Y - 0.3, BACK_Y + 0.3)):
            s.box((px - 0.3, y0, SEABED_Z), (px + 0.3, y1, DECK_BOTTOM - 1.2), "white")
        if k < bays:
            s.arch_panel(px + 0.3, px + WIDTH / bays - 0.3, 0.0, 0.3, DECK_BOTTOM - 1.2, DECK_BOTTOM - 1.2 - 2.6, "white")
    obj = s.finish("GS_Stand", coll)
    banner_uv(obj)
    layout = {
        "width": WIDTH, "tiers": [], "aisles": AISLES, "aisle_width": AISLE_W,
        "front_y": 0.0, "back_y": BACK_Y + BACK_T, "parapet_top": tier_floor(0) + PARAPET_H + 0.06,
        "banner": {"width": BANNER_W, "height": BANNER_H, "z": BANNER_Z},
        "flags": {"p1_x": -FLAG_X, "p2_x": FLAG_X}, "water_z": WATER_Z,
    }
    for i in range(TIERS):
        layout["tiers"].append({"floor_z": tier_floor(i), "stand_y": tier_front(i) + 0.42,
                                "bench_y": tier_front(i + 1) - 0.08 - BENCH_DEPTH * 0.5, "spans": spans})
    with open(G.OUT + "/goal_stand_layout.json", "w", encoding="utf-8") as fh:
        json.dump(layout, fh, indent=1)
    return {"object": obj.name, "verts": len(obj.data.vertices), "faces": len(obj.data.polygons),
            "materials": [mm.name for mm in obj.data.materials], "dims": [round(v, 2) for v in obj.dimensions]}


result = build()

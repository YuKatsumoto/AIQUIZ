"""Electric scoreboard behind the goal stand: a baseball-park LED board standing on
two steel legs behind the back wall.

    header   backlit AIQUIZ STADIUM sign flanked by bulb banks, visor and four
             floodlights on top
    screen   11.2 x 4.8 m LED face (7:3, GS_ScoreboardScreen) in a black bezel;
             Godot draws the score grid / winner cut-in onto it
    sides    pilasters with P1 (orange, Blender -X = Godot +X) and P2 (blue) light strips
    back     louvred cabinet, service catwalk with railing, ladder, braced legs

Same stand space as build_stand.py (front faces -Y, z = 0 at the conveyor top).
Header / steel images are Higgsfield generations (see README). The bulb banks are
one textured panel each (sb_bulbs.png from prep_scoreboard_textures.py) rather than
dozens of tiny boxes, so mipmaps keep them from sparkling far away.
Adds the "scoreboard" block to goal_stand_layout.json.
"""
import json

import bmesh
import bpy
from mathutils import Matrix, Vector

ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
G = type("G", (), ns)

BACK_Y = 4.35 + 0.30            # back face of the stand's back wall
BACK_TOP = 3.20
DECK_FOOT = -1.80               # underside of the sea fascia
FRONT = BACK_Y + 0.05           # cabinet front plane
DEPTH = 1.00
SCREEN_W, SCREEN_H = 11.2, 4.8
BEZEL = 0.30
HALF = SCREEN_W * 0.5 + BEZEL   # cabinet half width (5.9)
CAB_BOTTOM = 3.25               # cabinet underside, just above the back wall
SCREEN_Z = CAB_BOTTOM + BEZEL   # bottom of the LED face
CAB_TOP = SCREEN_Z + SCREEN_H + BEZEL
HEADER = (CAB_TOP, CAB_TOP + 2.20)
SIGN_W, SIGN_H = 4.60, 1.85             # the generated sign's own 2.5:1 frame
PILASTER = 0.42
LEG_X = 4.10
STEEL_TILE = 1.6                # metres per steel texture repeat
IMAGE_KEYS = ("screen", "sign", "bulbs")


def mats():
    tex = G.SOURCE + "/textures/"
    return {
        "steel": G.image_material("GS_SBSteel", tex + "sb_steel.png"),
        "bezel": G.flat_material("GS_SBBezel", (0.012, 0.012, 0.014), 0.35),
        "frame": G.flat_material("GS_SBFrame", (0.20, 0.21, 0.23), 0.40, 0.7),
        "trim": G.flat_material("GS_Trim", (0.58, 0.62, 0.68), 0.35, 0.6),
        "screen": G.flat_material("GS_ScoreboardScreen", (0.02, 0.03, 0.025), 0.25),
        "sign": G.image_material("GS_SBHeaderSign", tex + "sb_header.png"),
        "bulbs": emissive_image_material("GS_SBBulbs", tex + "sb_bulbs.png", 2.5),
        "lens": G.flat_material("GS_SBLens", (0.95, 0.95, 1.0), 0.1, 0.0, (1.0, 0.97, 0.90), 4.0),
        "p1": G.flat_material("GS_SBStripP1", (0.95, 0.55, 0.20), 0.4, 0.0, (0.95, 0.50, 0.15), 2.0),
        "p2": G.flat_material("GS_SBStripP2", (0.20, 0.65, 0.90), 0.4, 0.0, (0.15, 0.60, 0.95), 2.0),
        "grate": G.flat_material("GS_SBGrate", (0.16, 0.17, 0.18), 0.7, 0.5),
    }


def emissive_image_material(name, path, strength):
    """Image drives both base colour and emission (exported as glTF emissive texture)."""
    mat = G.image_material(name, path)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Roughness"].default_value = 0.35
    return mat


class Board:
    def __init__(self, m):
        self.m = m
        self.order = list(m)
        self.bm = bmesh.new()
        self.rects = {}             # image key -> [(x0, x1, z0, z1)] of its front faces

    def box(self, lo, hi, key, front=None):
        lo, hi = Vector(lo), Vector(hi)
        size = hi - lo
        mat = Matrix.Translation((lo + hi) * 0.5) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mat)
        faces = {f for v in res["verts"] for f in v.link_faces}
        for f in faces:
            f.normal_update()
            f.material_index = self.order.index(key)
            if front and f.normal.y < -0.9:
                f.material_index = self.order.index(front)
        if front in IMAGE_KEYS:
            self.rects.setdefault(front, []).append((lo.x, hi.x, lo.z, hi.z))
        return faces

    def beam(self, a, b, thick, key):
        """Square tube from a to b (for braces, rails, ladder stiles)."""
        a, b = Vector(a), Vector(b)
        axis = b - a
        rot = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
        mat = Matrix.Translation((a + b) * 0.5) @ rot @ Matrix.Diagonal((thick, thick, axis.length, 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mat)
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = self.order.index(key)

    def finish(self, name, coll):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.get(name) or bpy.data.meshes.new(name)
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


def assign_uv(obj, board):
    """Image faces map 0..1 over their front rect; steel is tiled planar by metres."""
    mesh = obj.data
    uv = mesh.uv_layers.active or mesh.uv_layers.new(name="UVMap")
    index = {key: board.order.index(key) for key in board.order}
    for poly in mesh.polygons:
        key = board.order[poly.material_index]
        n = poly.normal
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            if key in board.rects and n.y < -0.9:
                cx = poly.center.x
                x0, x1, z0, z1 = next(r for r in board.rects[key] if r[0] - 1e-3 <= cx <= r[1] + 1e-3)
                uv.data[li].uv = ((co.x - x0) / (x1 - x0), (co.z - z0) / (z1 - z0))
            elif key == "steel":
                if abs(n.z) > 0.7:
                    uv.data[li].uv = (co.x / STEEL_TILE, co.y / STEEL_TILE)
                elif abs(n.x) > 0.7:
                    uv.data[li].uv = (co.y / STEEL_TILE, co.z / STEEL_TILE)
                else:
                    uv.data[li].uv = (co.x / STEEL_TILE, co.z / STEEL_TILE)
            else:
                uv.data[li].uv = (0.5, 0.5)
    return index


def build():
    G.scene()
    coll = G.collection("GS_Scoreboard")
    G.clear_collection("GS_Scoreboard")
    b = Board(mats())
    back = FRONT + DEPTH
    # --- Main cabinet: apron + screen block + header as one steel box, faces cut in.
    b.box((-HALF, FRONT + 0.06, CAB_BOTTOM), (HALF, back, HEADER[1]), "steel")
    # LED face in a stepped black bezel (outer lip, then the recessed screen).
    b.box((-HALF + 0.04, FRONT, SCREEN_Z - BEZEL + 0.04), (HALF - 0.04, FRONT + 0.06, CAB_TOP - 0.04), "frame")
    b.box((-SCREEN_W * 0.5 - 0.12, FRONT - 0.03, SCREEN_Z - 0.12), (SCREEN_W * 0.5 + 0.12, FRONT, SCREEN_Z + SCREEN_H + 0.12), "bezel")
    b.box((-SCREEN_W * 0.5, FRONT - 0.035, SCREEN_Z), (SCREEN_W * 0.5, FRONT - 0.03, SCREEN_Z + SCREEN_H), "bezel", front="screen")
    # Header: backlit sign, bulb banks either side, trim rails.
    sz0 = (HEADER[0] + HEADER[1]) * 0.5 - SIGN_H * 0.5
    b.box((-SIGN_W * 0.5 - 0.08, FRONT - 0.02, sz0 - 0.08), (SIGN_W * 0.5 + 0.08, FRONT + 0.06, sz0 + SIGN_H + 0.08), "trim")
    b.box((-SIGN_W * 0.5, FRONT - 0.06, sz0), (SIGN_W * 0.5, FRONT - 0.02, sz0 + SIGN_H), "trim", front="sign")
    # Bulb banks: one lamp-board panel per side in a black surround.
    inner = SIGN_W * 0.5 + 0.35
    outer = HALF - 0.30
    for side in (-1.0, 1.0):
        x0, x1 = sorted((side * inner, side * outer))
        b.box((x0 - 0.06, FRONT - 0.02, HEADER[0] + 0.16), (x1 + 0.06, FRONT + 0.06, HEADER[1] - 0.20), "bezel")
        b.box((x0, FRONT - 0.05, HEADER[0] + 0.22), (x1, FRONT - 0.02, HEADER[1] - 0.26), "bezel", front="bulbs")
    for z in (HEADER[0] + 0.02, HEADER[1] - 0.10):
        b.box((-HALF, FRONT - 0.04, z), (HALF, FRONT + 0.06, z + 0.08), "trim")
    # Visor over the header and a cap rail.
    b.box((-HALF - 0.25, FRONT - 0.55, HEADER[1]), (HALF + 0.25, back + 0.10, HEADER[1] + 0.14), "frame")
    b.box((-HALF - 0.25, FRONT - 0.58, HEADER[1] - 0.10), (HALF + 0.25, FRONT - 0.52, HEADER[1] + 0.16), "trim")
    # Floodlights on brackets, aimed down at the board face.
    for x in (-4.2, -1.4, 1.4, 4.2):
        top = HEADER[1] + 0.14
        b.box((x - 0.05, FRONT - 0.20, top), (x + 0.05, FRONT - 0.10, top + 0.55), "frame")
        b.box((x - 0.34, FRONT - 0.78, top + 0.40), (x + 0.34, FRONT - 0.18, top + 0.78), "frame")
        b.box((x - 0.28, FRONT - 0.82, top + 0.44), (x + 0.28, FRONT - 0.78, top + 0.74), "lens")
    # Side pilasters with the players' light strips.
    for side, key in ((-1.0, "p1"), (1.0, "p2")):
        x0, x1 = (-HALF - PILASTER, -HALF) if side < 0 else (HALF, HALF + PILASTER)
        b.box((x0, FRONT - 0.08, CAB_BOTTOM - 0.05), (x1, back, HEADER[1] + 0.05), "frame")
        xm = (x0 + x1) * 0.5
        b.box((xm - 0.07, FRONT - 0.11, CAB_BOTTOM + 0.20), (xm + 0.07, FRONT - 0.08, HEADER[1] - 0.20), key)
    # Base beam the cabinet sits on, legs, knee braces and X-bracing behind the wall.
    b.box((-HALF - PILASTER, FRONT + 0.15, CAB_BOTTOM - 0.30), (HALF + PILASTER, back - 0.10, CAB_BOTTOM - 0.05), "frame")
    leg_y0, leg_y1 = FRONT + 0.30, FRONT + 0.75
    for side in (-1.0, 1.0):
        x = side * LEG_X
        b.box((x - 0.24, leg_y0, DECK_FOOT), (x + 0.24, leg_y1, CAB_BOTTOM - 0.30), "frame")
        b.beam((x, (leg_y0 + leg_y1) * 0.5, CAB_BOTTOM - 1.6), (x + side * 1.7, (leg_y0 + leg_y1) * 0.5, CAB_BOTTOM - 0.32), 0.14, "frame")
    ym = (leg_y0 + leg_y1) * 0.5
    for z0, z1 in ((DECK_FOOT + 0.2, 0.9), (0.9, CAB_BOTTOM - 0.35)):
        b.beam((-LEG_X, ym, z0), (LEG_X, ym, z1), 0.12, "frame")
        b.beam((LEG_X, ym, z0), (-LEG_X, ym, z1), 0.12, "frame")
        b.box((-LEG_X, ym - 0.07, z1 - 0.07), (LEG_X, ym + 0.07, z1 + 0.07), "frame")
    # Back: louvre bands on the cabinet rear, catwalk with railing, ladder down a leg.
    for k in range(9):
        z = CAB_BOTTOM + 0.6 + k * 0.85
        b.box((-HALF + 0.4, back, z), (HALF - 0.4, back + 0.05, z + 0.10), "frame")
    walk_z = CAB_BOTTOM - 0.30
    b.box((-HALF, back - 0.10, walk_z - 0.08), (HALF, back + 0.85, walk_z), "grate")
    rail_y = back + 0.80
    for k in range(9):
        x = -HALF + k * (2.0 * HALF / 8.0)
        b.box((x - 0.03, rail_y - 0.03, walk_z), (x + 0.03, rail_y + 0.03, walk_z + 1.05), "trim")
    for z in (walk_z + 0.55, walk_z + 1.05):
        b.box((-HALF, rail_y - 0.03, z - 0.03), (HALF, rail_y + 0.03, z + 0.03), "trim")
    lx = LEG_X + 0.55
    for off in (-0.22, 0.22):
        b.beam((lx + off, back + 0.30, 0.0), (lx + off, back + 0.30, walk_z), 0.05, "trim")
    rung = 0.30
    while rung < walk_z:
        b.box((lx - 0.22, back + 0.285, rung - 0.02), (lx + 0.22, back + 0.315, rung + 0.02), "trim")
        rung += 0.30
    obj = b.finish("GS_Scoreboard", coll)
    assign_uv(obj, b)
    # Flat-shade the hard-surface plate.
    for poly in obj.data.polygons:
        poly.use_smooth = False
    path = G.OUT + "/goal_stand_layout.json"
    with open(path, encoding="utf-8") as fh:
        layout = json.load(fh)
    layout.pop("banner", None)
    layout["scoreboard"] = {"screen_width": SCREEN_W, "screen_height": SCREEN_H, "screen_z": SCREEN_Z,
                            "screen_y": FRONT - 0.035, "top": HEADER[1] + 0.92, "width": 2.0 * (HALF + PILASTER)}
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(layout, fh, indent=1)
    return {"object": obj.name, "verts": len(obj.data.vertices), "faces": len(obj.data.polygons),
            "materials": [mm.name for mm in obj.data.materials], "dims": [round(v, 2) for v in obj.dimensions],
            "screen": layout["scoreboard"]}


result = build()

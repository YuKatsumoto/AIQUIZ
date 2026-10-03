"""Tileable 20 m blocks of the Santorini waterfront terrace.

The side stands used to be one 160 m mesh that Godot stretched along the course.
These blocks are laid end to end instead, one per 20 m of conveyor, so seats,
stairs, pergolas and piers keep their real size on any stage length.

Run: blender --background --factory-startup --python this_file.py

Geometry, materials and the grounded changes follow build_santorini_grandstand.py
and santorini_waterfront/source/live_waterfront.py (piers and footings reach the
-17.2 m authored seabed; the rear rail opens at every aisle).  Blender X points
away from the course, Y runs along it, Z is up; glTF maps that to Godot (X, Z, -Y).

Blocks (block-local Y -10..+10; the aisle stair sits on the +Y edge):
  Terrace_Bay         middle block, aisle on +Y, previous block's aisle on -Y
  Terrace_BayPergola  the same with a rear pergola in the middle
  Terrace_CapStart    closes the -Y end (end balustrade), aisle on +Y
  Terrace_CapEnd      closes the +Y end (end balustrade, extra pier), no aisle
"""
from __future__ import annotations

import ast
import json
import math
import random
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector

SOURCE = Path(__file__).resolve().parent
ASSET = SOURCE.parent
BUILDER = SOURCE / "build_santorini_grandstand.py"
GLB = ASSET / "santorini_terrace_modules.glb"
LAYOUT = ASSET / "santorini_terrace_modules.json"
BLEND = SOURCE / "santorini_terrace_modules.blend"
BLOCK_LENGTH = 20.0
GROUND_DROP = 7.2           # live_waterfront.py: sea piers reach the -17.2 m seabed
SEATS_PER_ROW = 19          # centred between the two aisle clearances
LAMP_GLASS = 12

# Reuse the authored constants, palette and shape helpers without running the
# builder's scene reset, 160 m export or renders.
KEEP_ASSIGN = {"ROW_COUNT", "ROW_BASE", "SEAT_EDGE", "AISLES", "AISLE_HALF_WIDTH",
               "FRONT_X", "RNG", "materials", "lamp_shader"}
KEEP_DEF = {"material", "Geometry", "flower_pot", "lantern", "pergola"}


def _load_builder() -> dict:
    tree = ast.parse(BUILDER.read_text(encoding="utf-8-sig"))
    body = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in KEEP_DEF:
            body.append(node)
        elif isinstance(node, ast.Assign):
            names = set()
            for target in node.targets:
                names |= {n.id for n in ast.walk(target) if isinstance(n, ast.Name)}
            if names & KEEP_ASSIGN:
                body.append(node)
        elif isinstance(node, ast.Expr) and "lamp_shader" in ast.unparse(node):
            body.append(node)
    # Materials must exist before the palette list is evaluated.
    body.sort(key=lambda n: 0 if isinstance(n, (ast.FunctionDef, ast.ClassDef)) else 1)
    ns = {"bpy": bpy, "Vector": Vector, "math": math, "random": random, "json": json,
          "defaultdict": defaultdict}
    exec(compile(ast.Module(body=body, type_ignores=[]), str(BUILDER), "exec"), ns)
    return ns


def _reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for data in list(bpy.data.materials):
        bpy.data.materials.remove(data)
    for data in list(bpy.data.meshes):
        bpy.data.meshes.remove(data)
    bpy.context.scene.unit_settings.system = "METRIC"


_reset_scene()
B = _load_builder()
Geometry = B["Geometry"]
PALETTE = B["materials"]
ROW_COUNT, ROW_FRONT, ROW_PITCH, ROW_RISE = B["ROW_COUNT"], B["ROW_FRONT"], B["ROW_PITCH"], B["ROW_RISE"]
ROW_BASE, SEAT_OFFSET, SEAT_PITCH = B["ROW_BASE"], B["SEAT_OFFSET"], B["SEAT_PITCH"]
AISLE_HALF_WIDTH, AISLE_CLEARANCE = B["AISLE_HALF_WIDTH"], B["AISLE_CLEARANCE"]


def seat_columns() -> list[float]:
    half = (SEATS_PER_ROW - 1) * SEAT_PITCH * 0.5
    columns = [-half + i * SEAT_PITCH for i in range(SEATS_PER_ROW)]
    assert columns[0] >= -BLOCK_LENGTH * 0.5 + AISLE_CLEARANCE - 1e-6, columns[0]
    return columns


def build_block(kind: str):
    g = Geometry()
    y0, y1 = -BLOCK_LENGTH * 0.5, BLOCK_LENGTH * 0.5
    yc = 0.0
    prev_aisle = kind != "cap_start"
    next_aisle = kind != "cap_end"
    g.box((3.8, yc, -.10), (9.2, 20., .64), 0, "white waterfront deck", .08)
    g.box((-.63, yc, -.48), (.31, 20., .22), 1, "waterfront cornice", .03)
    g.box((-.60, yc, .42), (.26, 20., .40), 0, "front low wall", .045)
    g.box((-.60, yc, .64), (.34, 20., .06), 1, "front wall coping", .04)
    for yy in [y0 + .45 + j * 2.4 for j in range(9) if y0 + .45 + j * 2.4 < y1 - .2]:
        g.box((-.60, yy, .89), (.045, .045, .52), 2, "front rail upright")
    g.box((-.60, yc, 1.12), (.055, 20., .06), 2, "front rail handrail")
    for j in range(15):
        yy = y0 + .45 + j * 1.31
        g.box((.02, yy, .229), (.59, 1.11, .018), 4 if j % 3 else 1, "promenade stone", .12)
        g.box((7.10, yy, 1.529), (1.70, 1.13, .018), 4 if j % 3 else 1, "rear paving", .14)
    # Sea piers already lowered to the seabed (bottom -17.2, tops unchanged).
    for x in (.00, 7.65):
        for yy in ((y0 + .2, y1 - .2) if kind == "cap_end" else (y0 + .2,)):
            g.box((x, yy, -5.1 - GROUND_DROP * .5), (.70, .72, 9.8 + GROUND_DROP), 0, "white stone sea pier", .06)
            g.box((x, yy, -8.90 - GROUND_DROP), (1.15, 1.20, 2.2), 5, "volcanic pier footing", .09)
            g.box((x, yy, -.65), (1.00, 1.16, .52), 1, "pier capital", .06)
    for x in (.0, 7.65):
        for i in range(12):
            a0 = math.pi * i / 12
            a1 = math.pi * (i + 1) / 12
            aa = (x, y0 + .2 + 9.99 * (1 - math.cos(a0)), -3.1 + 2.48 * math.sin(a0))
            bb = (x, y0 + .2 + 9.99 * (1 - math.cos(a1)), -3.1 + 2.48 * math.sin(a1))
            g.beam(aa, bb, .36, 0, "open supporting arch")
    for row in range(ROW_COUNT):
        x = ROW_FRONT + row * ROW_PITCH
        top = ROW_BASE + row * ROW_RISE
        front = x - .55
        left = y0 + AISLE_HALF_WIDTH if prev_aisle else y0 + .3
        right = y1 - AISLE_HALF_WIDTH if next_aisle else y1 - .3
        g.box(((front + 5.72) * .5, (left + right) * .5, (top + .22) * .5),
              (5.72 - front, right - left, top - .22), 0, "white seating terrace", .045)
        g.box((front + .065, (left + right) * .5, top + .016), (.13, right - left, .032), 1,
              "terrace rounded nosing", .025)
    g.box((7.06, yc, .87), (2.68, 20., 1.30), 0, "rear promenade foundation", .06)
    # Rear rail: low posts, an open gate at every aisle (grounded stand).
    aisles = ([y0] if prev_aisle else []) + ([y1] if next_aisle else [])
    for yy in [y0 + .3 + j * 3.2 for j in range(7) if y0 + .3 + j * 3.2 < y1]:
        if all(abs(yy - a) >= 1.15 for a in aisles):
            g.box((8.18, yy, 1.96), (.10, .10, .88), 2, "rear rail upright", .018)
    rail_a = y0 + 1.15 if prev_aisle else y0
    rail_b = y1 - 1.15 if next_aisle else y1
    for height in (1.88, 2.40):
        g.box((8.18, (rail_a + rail_b) * .5, height), (.065, rail_b - rail_a, .07), 2, "open entry rear rail")
    if prev_aisle:
        g.box((8.18, y0 + 1.17, 1.96), (.13, .13, .88), 2, "entry gate end post", .02)
    if next_aisle:
        g.box((8.18, y1 - 1.17, 1.96), (.13, .13, .88), 2, "entry gate end post", .02)
        for step in range(7):
            start = .6 + step * .625
            top = .32 + step * .20
            g.box((start + .3125, y1, (top + .22) * .5), (.625, 2.2, top - .22), 0, "aisle stair", .035)
            g.box((start + .035, y1, top + .015), (.07, 2.2, .03), 1, "stair nosing")
        g.box(((4.975 + 5.72) * .5, y1, .87), (.745, 2.2, 1.30), 0, "flush upper stair landing", .025)
        for sign in (-1., 1.):
            yy = y1 + sign * .89
            for x, z in ((.70, 1.22), (5.70, 2.42)):
                g.box((x, yy, z - .45), (.05, .05, .90), 2, "stair rail foot")
            g.beam((.7, yy, 1.22), (5.7, yy, 2.42), .055, 2, "stair blue handrail")
    seats = []
    for row in range(ROW_COUNT):
        x = ROW_FRONT + row * ROW_PITCH
        floor = ROW_BASE + row * ROW_RISE
        for column, yy in enumerate(seat_columns()):
            seat_mat = 3 if (column // 4 + row) % 5 == 0 else 2
            g.box((x, yy, floor + .50), (.61, .66, .09), seat_mat, "seat cushion", .045)
            g.box((x + .265, yy, floor + .78), (.10, .65, .43), seat_mat, "seat back", .040)
            for dy in (-.235, .235):
                for dx in (-.20, .22):
                    g.box((x + dx, yy + dy, floor + .245), (.055, .055, .49), 2, "painted chair leg")
            # Godot block space: (x, seat cushion top, -y).
            seats.append([round(x, 4), round(floor + SEAT_OFFSET, 4), round(-yy, 4), row])
    for yy in (yc - 5.0, yc + 5.0):
        B["flower_pot"](g, 7.78, yy, 1.52, .72)
        B["lantern"](g, 8.12, yy, 2.40)
    if kind in ("cap_start", "cap_end"):
        end = y0 + .2 if kind == "cap_start" else y1 - .2
        for row in range(4):
            x = ROW_FRONT + row * ROW_PITCH
            top = ROW_BASE + row * ROW_RISE
            g.box((x, end, top + .30), (1.20, .28, .60), 0, "stepped end balustrade", .07)
            g.box((x, end, top + .63), (1.25, .34, .06), 1, "end coping", .045)
    if kind == "bay_pergola":
        B["pergola"](g, yc)
    return g, seats, next_aisle


def vertex_colour_materials():
    """Two surfaces per block: painted stone/wood by vertex colour, and lantern glass."""
    painted = bpy.data.materials.new("Santorini terrace painted")
    painted.use_nodes = True
    nodes = painted.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.78
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Col"
    painted.node_tree.links.new(attribute.outputs["Color"], shader.inputs["Base Color"])
    return [painted, PALETTE[LAMP_GLASS]]


def create_block(name, g, collection, mats):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(g.v, [], g.f)
    for mat in mats:
        mesh.materials.append(mat)
    colours = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for polygon, palette_index in zip(mesh.polygons, g.m):
        polygon.material_index = 1 if palette_index == LAMP_GLASS else 0
        colour = tuple(PALETTE[palette_index].diffuse_color)
        for loop in polygon.loop_indices:
            colours.data[loop].color = colour
    mesh.color_attributes.active_color = colours
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj["element_counts"] = json.dumps(dict(g.elements))
    return obj


def main():
    collection = bpy.data.collections.new("Santorini terrace blocks")
    bpy.context.scene.collection.children.link(collection)
    mats = vertex_colour_materials()
    blocks = {}
    objects = []
    for kind, name in (("bay", "Terrace_Bay"), ("bay_pergola", "Terrace_BayPergola"),
                       ("cap_start", "Terrace_CapStart"), ("cap_end", "Terrace_CapEnd")):
        g, seats, own_aisle = build_block(kind)
        obj = create_block(name, g, collection, mats)
        objects.append(obj)
        obj.data.calc_loop_triangles()
        blocks[kind] = {"node": name, "seats": seats, "aisle_z": [-BLOCK_LENGTH * 0.5] if own_aisle else [],
                        "triangles": len(obj.data.loop_triangles)}
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True,
                              export_apply=True, export_animations=False, export_cameras=False,
                              export_lights=False, export_extras=False, export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True)
    layout = {
        "block_length": BLOCK_LENGTH,
        "note": "Godot block space: x away from the course, y up, z along it. The aisle of a block is on its -Z edge.",
        "seat_rows": ROW_COUNT,
        "blocks": blocks,
        "pergola_every": 3,
    }
    LAYOUT.write_text(json.dumps(layout, indent=1), encoding="utf-8")
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    print("TERRACE_MODULES " + json.dumps({k: {"seats": len(v["seats"]), "triangles": v["triangles"]}
                                           for k, v in blocks.items()}), flush=True)


main()

"""Raw egg contents for the thrown eggs: the white (GSE_White) and the yolk
(GSE_Yolk), exported to goal_stand_egg_contents.glb.

Both are unit-sized reference shapes; Godot (GoalStandEggs) deforms them at run
time with a small physics model, so the topology matters more than the size:

GSE_White  radial disc, radius 1 in the XY plane, thickness along +Z (Godot +Y),
           normalised height 1 at the centre. Top profile: thick albumen plateau,
           slope, thin outer albumen, a surface-tension bead at the rim. Flat
           bottom on the same radial rings so the whole sheet stretches per angle
           (the shader reads each vertex's angle and radius from its position).
GSE_Yolk   slightly flattened sphere of radius 1 standing on a flat base at z=0.

Run inside Blender (connector or `blender -b --factory-startup --python <this>`).
"""
import math

import bmesh
import bpy

OUT = "C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/goal_stand_egg_contents.glb"
SEGMENTS = 48
# (radius fraction, normalised height) from the centre out to the rim.
WHITE_PROFILE = [
    (0.0, 1.0), (0.12, 0.99), (0.24, 0.96), (0.36, 0.88), (0.46, 0.72), (0.56, 0.52),
    (0.66, 0.40), (0.76, 0.36), (0.84, 0.37), (0.90, 0.40), (0.95, 0.36), (0.98, 0.22), (1.0, 0.0),
]
WHITE_BOTTOM = [0.0, 0.3, 0.6, 0.85]
YOLK_FLATTEN = 0.82
YOLK_BASE = -0.35


def _ring(bm, fraction, height):
    return [bm.verts.new((math.cos(TAU * i / SEGMENTS) * fraction, math.sin(TAU * i / SEGMENTS) * fraction, height))
            for i in range(SEGMENTS)]


TAU = math.tau


def _bridge(bm, inner, outer, flip):
    for i in range(SEGMENTS):
        j = (i + 1) % SEGMENTS
        quad = [inner[i], outer[i], outer[j], inner[j]]
        bm.faces.new(list(reversed(quad)) if flip else quad)


def _fan(bm, centre, ring, flip):
    for i in range(SEGMENTS):
        tri = [centre, ring[i], ring[(i + 1) % SEGMENTS]]
        bm.faces.new(list(reversed(tri)) if flip else tri)


def build_white():
    bm = bmesh.new()
    top_centre = bm.verts.new((0.0, 0.0, WHITE_PROFILE[0][1]))
    rings = [_ring(bm, f, h) for f, h in WHITE_PROFILE[1:]]
    _fan(bm, top_centre, rings[0], False)
    for inner, outer in zip(rings, rings[1:]):
        _bridge(bm, inner, outer, False)
    rim = rings[-1]
    bottom_centre = bm.verts.new((0.0, 0.0, 0.0))
    bottom = [_ring(bm, f, 0.0) for f in WHITE_BOTTOM[1:]] + [rim]
    _fan(bm, bottom_centre, bottom[0], True)
    for inner, outer in zip(bottom, bottom[1:]):
        _bridge(bm, inner, outer, True)
    return _object("GSE_White", bm)


def build_yolk():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    for v in bm.verts:
        v.co.z *= YOLK_FLATTEN
    cut = YOLK_BASE * YOLK_FLATTEN
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < cut - 1e-4], context="VERTS")
    # Flatten the lowest remaining ring onto the cut plane and close it.
    lowest = min(v.co.z for v in bm.verts)
    base = [v for v in bm.verts if abs(v.co.z - lowest) < 1e-4]
    for v in base:
        v.co.z = cut
    edges = [e for e in bm.edges if e.is_boundary]
    bmesh.ops.contextual_create(bm, geom=edges)
    for v in bm.verts:
        v.co.z -= cut
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _object("GSE_Yolk", bm)


def _object(name, bm):
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    mesh = bpy.data.meshes.get(name)
    if mesh is not None:
        bpy.data.meshes.remove(mesh)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    return obj


def build(export=True):
    coll = bpy.data.collections.get("GS_EggContents") or bpy.data.collections.new("GS_EggContents")
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    made = [build_white(), build_yolk()]
    for obj in made:
        coll.objects.link(obj)
    if export:
        for obj in bpy.context.view_layer.objects:
            obj.select_set(obj in made)
        bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True,
                                  export_materials="NONE", export_apply=True, export_yup=True)
    return {"egg_contents": [(o.name, len(o.data.vertices), len(o.data.polygons)) for o in made], "out": OUT if export else ""}


result = build()
print("EGG_CONTENTS", result)

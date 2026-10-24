"""Raw egg contents for the thrown eggs, exported to goal_stand_egg_contents.glb.

The glTF export flips V (v -> 1 - v), so the shaders read t = 1 - UV.y. Every mesh
is a unit reference shape that a Godot shader bends into place at run
time (GoalStandEggContents and shaders/goal_stand_egg_*.gdshader), so what matters
is the topology and the parameters stored in UV, not the size. Godot axes below
(the glTF export turns Blender Z-up into Godot Y-up: Blender (x, y, z) -> (x, z, -y)).

GSE_White    radial disc of radius 1 in the XZ plane, top flagged by y = 1 (no
             underside: the film lies on the surface). 72 spokes, rings packed toward
             the rim where the outline, the surface-tension bead and the folds over
             box edges need vertices. UV = (angle / tau, radius fraction).
GSE_Yolk     UV sphere of radius 1 around the origin, lat-long UV. The shader makes it
             a sessile or pendant drop and drives its wobble modes.
GSE_Chalaza  twisted three-strand rope of length 1 along +Y, tapering to its far end.
GSE_Drip     lathe along -Y: unit rings at t = UV.y in [0, 1], closed at both ends.
             The shader gives each ring its radius (edge base, thread, hanging drop).
GSE_Strand   tube along +Y, unit rings at t = UV.y, closed ends (a Bezier in the shader).
GSE_Ribbon   strip for rivulets: UV.x along it (0..1), UV.y across (0..1), y = 1.

Run inside the live Blender (Higgsfield connector):
    exec(open(r"C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/build_egg_contents.py", encoding="utf-8").read())
"""
import math

import bmesh
import bpy

OUT = "C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/goal_stand_egg_contents.glb"
COLLECTION = "GS_EggContents"
TAU = math.tau

WHITE_SPOKES = 72
WHITE_RINGS = [0.035, 0.08, 0.13, 0.19, 0.25, 0.31, 0.37, 0.43, 0.49, 0.55, 0.61, 0.67, 0.72, 0.77,
               0.815, 0.855, 0.89, 0.92, 0.945, 0.965, 0.982, 1.0]
YOLK_SEGMENTS = (48, 24)
CHALAZA = {"rings": 40, "sides": 8, "strands": 3, "turns": 1.6, "helix": 0.36, "thickness": 0.34, "taper": 0.55}
DRIP = {"rings": 34, "sides": 14}
STRAND = {"rings": 22, "sides": 6}
RIBBON = {"along": 40, "across": 7}


def _uv_layer(bm):
    return bm.loops.layers.uv.verify()


def _set_uvs(bm, uv_of):
    """uv_of(vert) -> (u, v) per vertex (seams do not matter: the shaders do not wrap UV)."""
    layer = _uv_layer(bm)
    for face in bm.faces:
        for loop in face.loops:
            loop[layer].uv = uv_of(loop.vert)


def build_white():
    bm = bmesh.new()
    centre = bm.verts.new((0.0, 0.0, 1.0))
    rings = []
    for fraction in WHITE_RINGS:
        rings.append([bm.verts.new((math.cos(TAU * i / WHITE_SPOKES) * fraction, math.sin(TAU * i / WHITE_SPOKES) * fraction, 1.0))
                      for i in range(WHITE_SPOKES)])
    for i in range(WHITE_SPOKES):
        bm.faces.new([centre, rings[0][i], rings[0][(i + 1) % WHITE_SPOKES]])
    for inner, outer in zip(rings, rings[1:]):
        for i in range(WHITE_SPOKES):
            j = (i + 1) % WHITE_SPOKES
            bm.faces.new([inner[i], outer[i], outer[j], inner[j]])

    def uv(v):
        x, y = v.co.x, v.co.y
        return ((math.atan2(y, x) / TAU) % 1.0, math.hypot(x, y))
    _set_uvs(bm, uv)
    return _object("GSE_White", bm)


def build_yolk():
    bm = bmesh.new()
    _uv_layer(bm)
    bmesh.ops.create_uvsphere(bm, u_segments=YOLK_SEGMENTS[0], v_segments=YOLK_SEGMENTS[1], radius=1.0, calc_uvs=True)
    return _object("GSE_Yolk", bm)


def _tube(bm, path, radius, sides, t_values):
    """Tube along `path(t)` (Blender coordinates) with radius `radius(t)`, closed ends.
    Returns the created verts with their t (for UV)."""
    rings = []
    for t in t_values:
        centre = path(t)
        ahead = path(min(t + 0.01, 1.0)) - path(max(t - 0.01, 0.0))
        tangent = ahead.normalized()
        side = tangent.orthogonal().normalized()
        other = tangent.cross(side)
        r = radius(t)
        rings.append([bm.verts.new(centre + (side * math.cos(TAU * k / sides) + other * math.sin(TAU * k / sides)) * r)
                      for k in range(sides)])
    for inner, outer in zip(rings, rings[1:]):
        for k in range(sides):
            m = (k + 1) % sides
            bm.faces.new([inner[k], inner[m], outer[m], outer[k]])
    start = bm.verts.new(path(t_values[0]))
    end = bm.verts.new(path(t_values[-1]))
    for k in range(sides):
        m = (k + 1) % sides
        bm.faces.new([start, rings[0][m], rings[0][k]])
        bm.faces.new([end, rings[-1][k], rings[-1][m]])
    return rings, start, end


def build_chalaza():
    from mathutils import Vector
    spec = CHALAZA
    bm = bmesh.new()
    t_values = [i / (spec["rings"] - 1) for i in range(spec["rings"])]
    t_of = {}
    for strand in range(spec["strands"]):
        phase = TAU * strand / spec["strands"]

        def path(t, phase=phase):
            angle = phase + TAU * spec["turns"] * t
            twist = spec["helix"] * (1.0 - spec["taper"] * t)
            return Vector((math.cos(angle) * twist, math.sin(angle) * twist, t))

        def radius(t):
            return spec["thickness"] * (1.0 - spec["taper"] * t)
        rings, start, end = _tube(bm, path, radius, spec["sides"], t_values)
        for ring, t in zip(rings, t_values):
            for v in ring:
                t_of[v] = t
        t_of[start] = 0.0
        t_of[end] = 1.0
    _set_uvs(bm, lambda v: (0.0, t_of.get(v, 0.0)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _object("GSE_Chalaza", bm)


def _lathe(name, spec, down):
    """Unit rings along Godot -Y (down) or +Y, UV.y = t, closed with a pole at each end."""
    bm = bmesh.new()
    count = spec["rings"]
    sides = spec["sides"]
    # Rings packed toward both ends (the edge base and the drop's tip need them).
    t_values = [0.5 - 0.5 * math.cos(math.pi * i / (count - 1)) for i in range(count)]
    sign = -1.0 if down else 1.0
    rings = [[bm.verts.new((math.cos(TAU * k / sides), math.sin(TAU * k / sides), sign * t)) for k in range(sides)] for t in t_values]
    for inner, outer in zip(rings, rings[1:]):
        for k in range(sides):
            m = (k + 1) % sides
            bm.faces.new([inner[k], inner[m], outer[m], outer[k]])
    top = bm.verts.new((0.0, 0.0, 0.0))
    tip = bm.verts.new((0.0, 0.0, sign * 1.0))
    for k in range(sides):
        m = (k + 1) % sides
        bm.faces.new([top, rings[0][m], rings[0][k]])
        bm.faces.new([tip, rings[-1][k], rings[-1][m]])
    _set_uvs(bm, lambda v: ((math.atan2(v.co.y, v.co.x) / TAU) % 1.0, abs(v.co.z)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _object(name, bm)


def build_ribbon():
    bm = bmesh.new()
    along, across = RIBBON["along"], RIBBON["across"]
    grid = [[bm.verts.new((i / (along - 1), -(2.0 * j / (across - 1) - 1.0), 1.0)) for j in range(across)] for i in range(along)]
    for i in range(along - 1):
        for j in range(across - 1):
            bm.faces.new([grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]])
    _set_uvs(bm, lambda v: (v.co.x, (-v.co.y + 1.0) * 0.5))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Face up (+Z in Blender, +Y in Godot).
    if bm.faces and bm.faces[0].normal.z < 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return _object("GSE_Ribbon", bm)


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
    return bpy.data.objects.new(name, mesh)


def build(export=True):
    coll = bpy.data.collections.get(COLLECTION) or bpy.data.collections.new(COLLECTION)
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    made = [build_white(), build_yolk(), build_chalaza(), _lathe("GSE_Drip", DRIP, True),
            _lathe("GSE_Strand", STRAND, False), build_ribbon()]
    # Side by side for a look in the viewport; each one is exported at the origin.
    for index, obj in enumerate(made):
        coll.objects.link(obj)
        obj.location = (index * 3.0, 0.0, 0.0)
    if export:
        saved = {obj.name: tuple(obj.location) for obj in made}
        for obj in made:
            obj.location = (0.0, 0.0, 0.0)
        for obj in bpy.context.view_layer.objects:
            obj.select_set(obj in made)
        bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True,
                                  export_materials="NONE", export_apply=True, export_yup=True,
                                  use_active_scene=True)
        for obj in made:
            obj.location = saved[obj.name]
    return {"egg_contents": [(o.name, len(o.data.vertices), len(o.data.polygons)) for o in made], "out": OUT if export else ""}


result = build()
print("EGG_CONTENTS", result)

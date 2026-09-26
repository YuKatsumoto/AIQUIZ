"""Score Tower Finale — set pieces, built procedurally in the live Blender scene.

Run inside Blender (bl_execute): exec(open(path).read()); build_all()
Idempotent: every object this script owns is prefixed TWR_/PRP_/ENV_/LGT_ and is
rebuilt from scratch; the cast (WIN_/LOSE_/RIG_Referee) is never touched here.
Units are metres, Z up. Characters face -Y (toward the camera).
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix

SCENE = "AIQUIZ_ScoreTowerFinale"
TOWER_X = 2.2            # WIN tower at -X, LOSE tower at +X (Blender)
COLLAR_H = 0.05
PLATFORM_R = 0.85
PLATFORM_T = 0.20
COLUMN_R = 0.62
COLUMN_LEN = 3.2
OWNED = ("TWR_", "PRP_", "ENV_", "LGT_")


def scene():
    return bpy.data.scenes[SCENE]


def collection(name):
    s = scene()
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
    if c.name not in s.collection.children:
        s.collection.children.link(c)
    return c


def material(name, color, rough=0.5, metal=0.0, emission=None, strength=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = (*color, 1.0)
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1.0)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    if emission is not None:
        p.inputs['Emission Color'].default_value = (*emission, 1.0)
        p.inputs['Emission Strength'].default_value = strength
    else:
        p.inputs['Emission Strength'].default_value = 0.0
    return m


def mats():
    return {
        "body": material("FIN_TowerBody", (0.90, 0.92, 0.95), 0.42),
        "trim": material("FIN_TowerTrim", (0.030, 0.050, 0.095), 0.55),
        # White emissive so Godot can tint per player (P1 orange / P2 blue).
        "accent": material("FIN_TowerAccent", (1.0, 1.0, 1.0), 0.3, emission=(1.0, 1.0, 1.0), strength=2.0),
        "hz_y": material("FIN_HazardYellow", (1.0, 0.74, 0.04), 0.5),
        "hz_k": material("FIN_HazardBlack", (0.025, 0.025, 0.03), 0.6),
        "metal": material("FIN_CannonMetal", (0.95, 0.70, 0.24), 0.28, 0.9),
        "gold": material("FIN_CrownGold", (1.0, 0.74, 0.18), 0.22, 1.0),
        "gem_r": material("FIN_GemRed", (0.85, 0.04, 0.10), 0.1, emission=(0.9, 0.05, 0.1), strength=0.6),
        "gem_b": material("FIN_GemBlue", (0.05, 0.35, 1.0), 0.1, emission=(0.1, 0.4, 1.0), strength=0.6),
        "cloud": material("FIN_CloudGrey", (0.50, 0.55, 0.64), 0.85),
        "cloud_face": material("FIN_CloudFace", (0.04, 0.05, 0.08), 0.6),
        "flag_w": material("FIN_FlagWhite", (0.95, 0.95, 0.95), 0.7),
        "flag_k": material("FIN_FlagBlack", (0.02, 0.02, 0.025), 0.7),
        "silver": material("FIN_PoleSilver", (0.80, 0.82, 0.86), 0.25, 1.0),
        "floor": material("ENV_PreviewFloor", (0.26, 0.28, 0.32), 0.8),
    }


def clear_owned():
    s = scene()
    for o in list(s.objects):
        if o.name.startswith(OWNED):
            data = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if data is not None and data.users == 0 and isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)


def link(o, coll):
    coll.objects.link(o)
    return o


def empty(name, coll, parent=None, loc=(0, 0, 0), size=0.2):
    o = bpy.data.objects.new(name, None)
    o.empty_display_size = size
    o.parent = parent
    o.location = loc
    return link(o, coll)


def mesh_object(name, bm, coll, materials, parent=None, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(m)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    o.parent = parent
    return link(o, coll)


def ring(bm, segments, radius, z, phase=0.0):
    return [bm.verts.new((radius * math.cos(phase + i * math.tau / segments),
                          radius * math.sin(phase + i * math.tau / segments), z)) for i in range(segments)]


def bridge(bm, a, b, mat=0):
    faces = []
    n = len(a)
    for i in range(n):
        f = bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
        f.material_index = mat
        faces.append(f)
    return faces


def cap(bm, loop, mat=0, flip=False):
    f = bm.faces.new(list(reversed(loop)) if flip else loop)
    f.material_index = mat
    return f


# ---------------------------------------------------------------- tower

def build_collar(name, coll, parent, M):
    """Static floor collar: hazard-striped octagon ring the column rises through."""
    bm = bmesh.new()
    seg = 32
    inner, outer = COLUMN_R + 0.05, 1.08
    z0, z1 = 0.0, COLLAR_H
    oi0, oo0 = ring(bm, seg, inner, z0), ring(bm, seg, outer, z0)
    oi1, oo1 = ring(bm, seg, inner, z1), ring(bm, seg, outer - 0.04, z1)
    bridge(bm, oo0, oo1, 1)              # beveled outer wall (trim)
    bridge(bm, oi1, oi0, 1)              # inner wall
    top = bridge(bm, oi1, oo1, 0)        # top face, hazard stripes
    for i, f in enumerate(top):
        f.material_index = 2 if (i // 2) % 2 == 0 else 3
    # thin glowing lip around the hole
    lip_a, lip_b = ring(bm, seg, inner + 0.001, z1 + 0.004), ring(bm, seg, inner + 0.045, z1 + 0.004)
    for f in bridge(bm, lip_a, lip_b, 4):
        f.material_index = 4
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm, coll, [M["trim"], M["trim"], M["hz_y"], M["hz_k"], M["accent"]], parent)


def build_platform(name, coll, parent, M):
    """Platform top at local z=0. Navy deck with a glowing inlay ring and white rim."""
    bm = bmesh.new()
    seg = 48
    r, t = PLATFORM_R, PLATFORM_T
    centre = bm.verts.new((0, 0, 0))
    deck_inner = ring(bm, seg, r - 0.20, 0.0)
    inlay_a = ring(bm, seg, r - 0.17, 0.0)
    inlay_b = ring(bm, seg, r - 0.11, 0.0)
    rim_top = ring(bm, seg, r - 0.03, 0.0)
    edge_top = ring(bm, seg, r, -0.03)
    edge_mid = ring(bm, seg, r, -t + 0.05)
    edge_bot = ring(bm, seg, r - 0.05, -t)
    skirt = ring(bm, seg, COLUMN_R + 0.02, -t - 0.12)
    for i in range(seg):
        f = bm.faces.new((centre, deck_inner[i], deck_inner[(i + 1) % seg]))
        f.material_index = 1
    bridge(bm, deck_inner, inlay_a, 1)
    bridge(bm, inlay_a, inlay_b, 2)       # emissive player ring
    bridge(bm, inlay_b, rim_top, 0)
    bridge(bm, rim_top, edge_top, 0)
    bridge(bm, edge_top, edge_mid, 2)     # glowing side band
    bridge(bm, edge_mid, edge_bot, 0)
    bridge(bm, edge_bot, skirt, 1)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # recalc may point the deck down if the shell is open; force deck normals up
    for f in bm.faces:
        if f.calc_center_median().z > -0.001 and f.normal.z < 0:
            f.normal_flip()
    return mesh_object(name, bm, coll, [M["body"], M["trim"], M["accent"]], parent)


def build_column(name, coll, parent, M):
    """Octagonal column hanging below the platform; glowing bands every 0.5 m."""
    bm = bmesh.new()
    seg = 8
    top_z = -PLATFORM_T - 0.10
    bottom_z = top_z - COLUMN_LEN
    zs = [top_z]
    z = top_z
    while z - 0.5 > bottom_z:
        z -= 0.44
        zs += [z, z - 0.06]
        z -= 0.06
    zs.append(bottom_z)
    loops = [ring(bm, seg, COLUMN_R, zz, math.pi / 8) for zz in zs]
    for i in range(len(loops) - 1):
        band = i % 2 == 1
        bridge(bm, loops[i], loops[i + 1], 2 if band else 0)
    cap(bm, loops[-1], 1)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # vertical navy grooves: inset each white face slightly
    white = [f for f in bm.faces if f.material_index == 0 and abs(f.normal.z) < 0.1]
    res = bmesh.ops.inset_individual(bm, faces=white, thickness=0.045, depth=-0.012)
    for f in res.get("faces", []):
        f.material_index = 1
    return mesh_object(name, bm, coll, [M["body"], M["trim"], M["accent"]], parent)


def build_cannon(name, coll, parent, M, angle):
    bm = bmesh.new()
    seg = 16
    loops = [ring(bm, seg, r, z) for r, z in [(0.085, 0.0), (0.085, 0.05), (0.07, 0.07), (0.07, 0.26), (0.085, 0.28), (0.06, 0.28), (0.06, 0.12)]]
    for i in range(len(loops) - 1):
        bridge(bm, loops[i], loops[i + 1], 0)
    cap(bm, loops[0], 0, flip=True)
    cap(bm, loops[-1], 1)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_object(name, bm, coll, [M["metal"], M["trim"]], parent, smooth=True)
    radius = PLATFORM_R - 0.10
    o.location = (radius * math.cos(angle), radius * math.sin(angle), -0.02)
    outward = Vector((math.cos(angle), math.sin(angle), 0))
    tilt = math.radians(28)
    direction = (outward * math.sin(tilt) + Vector((0, 0, math.cos(tilt)))).normalized()
    o.rotation_euler = Vector((0, 0, 1)).rotation_difference(direction).to_euler()
    muzzle = empty(name + "_Muzzle", coll, o, (0, 0, 0.29), 0.08)
    return o, muzzle


def build_tower(side, x, coll, M):
    root = empty("TWR_%s_Root" % side, coll, None, (x, 0, 0), 0.4)
    build_collar("TWR_%s_Collar" % side, coll, root, M)
    lift = empty("TWR_%s_Lift" % side, coll, root, (0, 0, COLLAR_H), 0.3)
    build_platform("TWR_%s_Platform" % side, coll, lift, M)
    build_column("TWR_%s_Column" % side, coll, lift, M)
    # Cannons on the sides/back so they never cover the performer's feet.
    for i, deg in enumerate((12, 168, 62, 118)):
        build_cannon("TWR_%s_Cannon%d" % (side, i), coll, lift, M, math.radians(deg))
    return root, lift


# ---------------------------------------------------------------- crown

def build_crown(coll, M):
    bm = bmesh.new()
    seg, points = 80, 5
    r_out, r_in, base_h, spike_h = 0.23, 0.205, 0.12, 0.15

    def height(i):
        u = (i / seg * points) % 1.0
        tri = 1.0 - abs(u - 0.5) * 2.0          # 0 at valleys, 1 at peaks
        return base_h + spike_h * tri ** 1.35

    out_b = [bm.verts.new((r_out * math.cos(i * math.tau / seg), r_out * math.sin(i * math.tau / seg), 0.0)) for i in range(seg)]
    out_t = [bm.verts.new((r_out * math.cos(i * math.tau / seg), r_out * math.sin(i * math.tau / seg), height(i))) for i in range(seg)]
    in_t = [bm.verts.new((r_in * math.cos(i * math.tau / seg), r_in * math.sin(i * math.tau / seg), height(i) - 0.01)) for i in range(seg)]
    in_b = [bm.verts.new((r_in * math.cos(i * math.tau / seg), r_in * math.sin(i * math.tau / seg), 0.0)) for i in range(seg)]
    bridge(bm, out_b, out_t, 0)
    bridge(bm, out_t, in_t, 0)
    bridge(bm, in_t, in_b, 0)
    bridge(bm, in_b, out_b, 0)
    # raised band around the base
    band_a = [bm.verts.new((r_out * 1.06 * math.cos(i * math.tau / seg), r_out * 1.06 * math.sin(i * math.tau / seg), 0.012)) for i in range(seg)]
    band_b = [bm.verts.new((r_out * 1.06 * math.cos(i * math.tau / seg), r_out * 1.06 * math.sin(i * math.tau / seg), 0.052)) for i in range(seg)]
    band_c = [bm.verts.new((r_out * 0.999 * math.cos(i * math.tau / seg), r_out * 0.999 * math.sin(i * math.tau / seg), 0.062)) for i in range(seg)]
    band_d = [bm.verts.new((r_out * 0.999 * math.cos(i * math.tau / seg), r_out * 0.999 * math.sin(i * math.tau / seg), 0.004)) for i in range(seg)]
    bridge(bm, band_d, band_a, 0)
    bridge(bm, band_a, band_b, 0)
    bridge(bm, band_b, band_c, 0)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    crown = mesh_object("PRP_Crown", bm, coll, [M["gold"]], None, smooth=True)
    crown.data.polygons.foreach_set("use_smooth", [True] * len(crown.data.polygons))
    # balls on the tips and gems on the band (front gem faces -Y)
    for k in range(points):
        a = (k + 0.5) / points * math.tau - math.pi / 2 - math.pi / points * 0
        a = (k + 0.5) * math.tau / points
        tip = Vector(((r_out - 0.012) * math.cos(a), (r_out - 0.012) * math.sin(a), base_h + spike_h + 0.018))
        bm2 = bmesh.new()
        bmesh.ops.create_uvsphere(bm2, u_segments=16, v_segments=10, radius=0.026)
        ball = mesh_object("PRP_CrownBall%d" % k, bm2, coll, [M["gold"]], crown, smooth=True)
        ball.location = tip
    for k in range(points):
        a = (k + 0.5) * math.tau / points
        bm2 = bmesh.new()
        bmesh.ops.create_uvsphere(bm2, u_segments=14, v_segments=8, radius=0.028)
        gem = mesh_object("PRP_CrownGem%d" % k, bm2, coll, [M["gem_r"] if k % 2 == 0 else M["gem_b"]], crown, smooth=True)
        gem.location = ((r_out * 1.07) * math.cos(a), (r_out * 1.07) * math.sin(a), 0.032)
        gem.scale = (1.0, 1.0, 0.8)
    return crown


# ---------------------------------------------------------------- cloud

def build_cloud(coll, M):
    mb = bpy.data.metaballs.new("PRP_CloudMeta")
    mb.resolution = 0.05
    mb.render_resolution = 0.04
    blobs = [((0.0, 0.0, 0.10), 0.36), ((-0.33, 0.02, 0.02), 0.28), ((0.34, -0.02, 0.03), 0.30),
             ((-0.15, 0.08, 0.22), 0.26), ((0.16, 0.06, 0.24), 0.27), ((-0.55, 0.0, -0.04), 0.18),
             ((0.58, 0.0, -0.03), 0.19), ((0.0, 0.10, -0.06), 0.30)]
    for co, radius in blobs:
        e = mb.elements.new()
        e.co = co
        e.radius = radius
    meta = bpy.data.objects.new("PRP_CloudMetaTmp", mb)
    coll.objects.link(meta)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(meta.evaluated_get(dg))
    bpy.data.objects.remove(meta, do_unlink=True)
    bpy.data.metaballs.remove(mb)
    me.name = "PRP_Cloud"
    # flatten the underside a little so rain reads from a shelf
    for v in me.vertices:
        if v.co.z < -0.12:
            v.co.z = -0.12 + (v.co.z + 0.12) * 0.35
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(M["cloud"])
    cloud = bpy.data.objects.new("PRP_Cloud", me)
    coll.objects.link(cloud)
    # sad little face on the camera side (-Y)
    for i, x in enumerate((-0.12, 0.12)):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.035)
        eye = mesh_object("PRP_CloudEye%d" % i, bm, coll, [M["cloud_face"]], cloud, smooth=True)
        eye.location = (x, -0.335, 0.12)
        eye.scale = (0.8, 0.5, 1.25)
    bm = bmesh.new()
    pts = []
    for k in range(9):
        u = k / 8.0
        pts.append(Vector((-0.09 + 0.18 * u, -0.34, 0.0 + 0.04 * math.sin(u * math.pi))))  # frown arcs upward
    verts_a = [bm.verts.new(p + Vector((0, 0, 0.012))) for p in pts]
    verts_b = [bm.verts.new(p - Vector((0, 0, 0.012))) for p in pts]
    for k in range(8):
        bm.faces.new((verts_a[k], verts_a[k + 1], verts_b[k + 1], verts_b[k]))
    mouth = mesh_object("PRP_CloudMouth", bm, coll, [M["cloud_face"]], cloud)
    rain = empty("PRP_CloudRain", coll, cloud, (0, 0, -0.14), 0.1)
    return cloud


# ---------------------------------------------------------------- flag

def build_flag(coll, M):
    pole_len = 0.85
    bm = bmesh.new()
    seg = 12
    a = ring(bm, seg, 0.018, -0.12)
    b = ring(bm, seg, 0.018, pole_len)
    bridge(bm, a, b, 0)
    cap(bm, a, 0, flip=True)
    cap(bm, b, 0)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    flag = mesh_object("PRP_Flag", bm, coll, [M["silver"]], None, smooth=True)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.035)
    knob = mesh_object("PRP_FlagKnob", bm, coll, [M["silver"]], flag, smooth=True)
    knob.location = (0, 0, pole_len + 0.02)
    # waving checker cloth, 8x6 checks, hung from the pole top toward +X
    bm = bmesh.new()
    cols, rows, w, h = 16, 6, 0.46, 0.32
    grid = [[bm.verts.new((0.02 + w * i / cols,
                           0.035 * math.sin(i / cols * math.pi * 1.6) * (i / cols),
                           pole_len - 0.02 - h * j / rows - 0.03 * (i / cols) ** 2)) for i in range(cols + 1)] for j in range(rows + 1)]
    for j in range(rows):
        for i in range(cols):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            f.material_index = ((i // 2) + j) % 2
    cloth = mesh_object("PRP_FlagCloth", bm, coll, [M["flag_w"], M["flag_k"]], flag, smooth=True)
    return flag


def attach_flag(flag):
    """Hold the pole like a torch: it continues the right arm (the winner's -X side).

    The plush mitt is the dominant visible part of the arm, so the flag direction
    is driven by aiming the arm instead of twisting the mitt away from it.
    """
    rig = bpy.data.objects["RIG_Referee"]
    pb = rig.pose.bones["DEF-hand.R"]
    mw = rig.matrix_world
    head, tail = mw @ pb.head, mw @ pb.tail
    axis = (tail - head).normalized()                 # pole (+Z local) along the hand
    side = Vector((-1.0, 0.0, 0.0))                   # cloth trails outward, facing camera
    side = (side - axis * side.dot(axis)).normalized()
    normal = side.cross(axis)
    basis = Matrix((side, normal, axis)).transposed()
    flag.parent = rig
    flag.parent_type = 'BONE'
    flag.parent_bone = "DEF-hand.R"
    flag.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()
    flag.matrix_world = Matrix.Translation(head + axis * 0.02) @ basis.to_4x4()


# ---------------------------------------------------------------- preview env

def build_env(coll, M):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1.0)
    floor = mesh_object("ENV_PreviewFloor", bm, coll, [M["floor"]])
    floor.scale = (12.0, 22.0, 1.0)
    floor.location = (0.0, 6.0, 0.0)
    s = scene()
    if s.world is None:
        s.world = bpy.data.worlds.new("FIN_PreviewWorld")
    s.world.use_nodes = True
    bg = next(n for n in s.world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Color'].default_value = (0.52, 0.72, 0.95, 1)
    bg.inputs['Strength'].default_value = 0.8


def build_lights(coll):
    for name, loc, power, size, color, purpose in [
        ("LGT_Key", (4.5, -6.0, 7.5), 2600, 4.0, (1.0, 0.93, 0.82), "sun-side key, stadium floodlight"),
        ("LGT_Fill", (-6.0, -5.0, 3.5), 700, 5.0, (0.70, 0.80, 1.0), "sky fill on shadow side"),
        ("LGT_Rim", (0.0, 7.0, 6.0), 1800, 3.0, (1.0, 0.85, 0.65), "separates towers from sky"),
    ]:
        d = bpy.data.lights.new(name, 'AREA')
        d.energy = power
        d.size = size
        d.color = color
        o = bpy.data.objects.new(name, d)
        o.location = loc
        o.rotation_euler = (Vector((0, 0, 1.5)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        o["purpose"] = purpose
        link(o, coll)


def build_all():
    clear_owned()
    M = mats()
    set_coll = collection("FINALE_Set")
    light_coll = collection("FINALE_Light")
    build_tower("W", -TOWER_X, set_coll, M)
    build_tower("L", TOWER_X, set_coll, M)
    crown = build_crown(set_coll, M)
    crown.location = (-2.2, 0.0, 3.2)
    cloud = build_cloud(set_coll, M)
    cloud.location = (2.2, 0.0, 3.2)
    flag = build_flag(set_coll, M)
    attach_flag(flag)
    build_env(set_coll, M)
    build_lights(light_coll)
    bpy.context.view_layer.update()
    return {
        "objects": sorted(o.name for o in scene().objects if o.name.startswith(OWNED)),
    }

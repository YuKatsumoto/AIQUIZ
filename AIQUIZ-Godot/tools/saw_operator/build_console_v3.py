"""Godot-kun operator console v3. Run stage by stage inside the live Blender:

    exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/tools/saw_operator/build_console_v3.py', encoding='utf-8').read(),
         {'console_stage': 'setup'})

Stages: setup, blockout, detail, inspect, write_source, export.
Everything lives in its own scene (GodotConsole_V3), so the file that is open in the
live Blender is not otherwise touched. The runtime seat/plush/chair-launch kit/dock
mount stay in saw_operator.glb; this builds a new console GLB (godot_console_v3.glb)
with the deck, seat pedestal, both control pods, the instrument dash, pedals and
every control. saw_operator.glb is imported only as a REF_ reference.

Asset space: the operator faces -Y, left hand +X, Z up (Godot: +Z front, Y up, X
left). Reach was measured from the plush rig: the wrist stays within 0.237 m of the
shoulder and the palm contact sits 0.08 m ahead of the wrist, so every hand contact
lies within 0.21 m of (+-0.416, 0.14, 1.645).
"""
import bpy, bmesh, math, json, os
from mathutils import Vector, Matrix

ROOT = 'C:/AIQUIZ/AIQUIZ-Godot'
ASSET = ROOT + '/assets/hazards/saw_operator'
OUT = ROOT + '/artifacts/saw_operator/v3'
REFERENCE_GLB = ASSET + '/saw_operator.glb'
CONSOLE_GLB = ASSET + '/godot_console_v3.glb'
SOURCE = ASSET + '/source/saw_operator_v3.blend'
SCENE = 'GodotConsole_V3'
STAGE = globals().get('console_stage', 'setup')
os.makedirs(OUT, exist_ok=True)
result = {'stage': STAGE}

SHOULDER = {'L': Vector((.416, .22, 1.645)), 'R': Vector((-.416, .22, 1.645))}
PALM_REACH_CENTER = {k: v + Vector((0, -.08, 0)) for k, v in SHOULDER.items()}
# Old console parts in the reference import: hidden so only seat, plush and mount remain.
OLD_CONSOLE = ('OP_Cover', 'OP_Dial', 'OP_GaugeMount', 'OP_InputIndex', 'OP_Lever', 'OP_Pedal',
               'OP_Start', 'OP_Toggle', 'OperatorStation_', 'SL_LapWebbing', 'SL_Tongue', 'SL_Reel', 'SL_Receiver')


def scene():
    return bpy.data.scenes[SCENE]


# ------------------------------------------------------------------ materials
def material(name, color, metal=0.0, rough=.5, emit=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = (*color, alpha)
    nodes = m.node_tree.nodes
    p = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if p is None:
        p = nodes.new('ShaderNodeBsdfPrincipled')
        out = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None) or nodes.new('ShaderNodeOutputMaterial')
        m.node_tree.links.new(p.outputs['BSDF'], out.inputs['Surface'])
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    p.inputs['Alpha'].default_value = alpha
    if emit is not None:
        p.inputs['Emission Color'].default_value = (*emit, 1)
        p.inputs['Emission Strength'].default_value = strength
    if alpha < 1.0:
        m.surface_render_method = 'BLENDED'
    m['v3'] = True
    return m


def mats():
    return dict(
        shell=material('V3_ShellGraphite', (.030, .036, .044), .35, .40),
        panel=material('V3_PanelBlue', (.055, .270, .600), .10, .34),
        trim=material('V3_TrimYellow', (.960, .560, .020), .10, .40),
        black=material('V3_StripeBlack', (.012, .013, .015), 0.0, .60),
        steel=material('V3_Steel', (.620, .660, .700), .90, .22),
        dark_steel=material('V3_DarkSteel', (.100, .110, .125), .80, .32),
        rubber=material('V3_Rubber', (.013, .015, .018), 0.0, .80),
        grip=material('V3_GripRubber', (.020, .022, .026), 0.0, .60),
        face=material('V3_GaugeFace', (.018, .021, .026), 0.0, .42),
        ink=material('V3_Ink', (.930, .950, .960), 0.0, .48),
        redline=material('V3_Redline', (.800, .040, .025), 0.0, .45),
        needle=material('V3_Needle', (1.00, .330, .040), 0.0, .35, (1.0, .32, .04), 1.2),
        red=material('V3_StartRed', (.780, .030, .020), .05, .26),
        guard=material('V3_GuardAmber', (.980, .430, .010), .05, .22),
        key=material('V3_KeyBrass', (.850, .660, .260), .95, .24),
        deck=material('V3_DeckMat', (.026, .029, .034), 0.0, .88),
        # Lenses start dark; Godot drives the emission per lamp and state.
        lamp_green=material('V3_LampGreen', (.030, .160, .055), 0.0, .18, (.15, 1.0, .35), 0.0),
        lamp_amber=material('V3_LampAmber', (.220, .110, .010), 0.0, .18, (1.0, .55, .06), 0.0),
        lamp_red=material('V3_LampRed', (.220, .020, .015), 0.0, .18, (1.0, .10, .05), 0.0),
        lamp_blue=material('V3_LampBlue', (.020, .080, .220), 0.0, .18, (.25, .62, 1.0), 0.0),
        beacon=material('V3_BeaconLens', (1.00, .480, .030), 0.0, .12, (1.0, .50, .05), 0.0, alpha=.62),
    )


# ------------------------------------------------------------------ construction helpers
def link(o):
    scene().collection.objects.link(o)
    o['v3'] = True
    return o


def empty(name, loc=(0, 0, 0), parent=None, rot=(0, 0, 0), size=.03, matrix=None):
    assert name not in bpy.data.objects, name
    o = link(bpy.data.objects.new(name, None))
    o.parent = parent
    o.empty_display_size = size
    if matrix is not None:
        o.matrix_basis = matrix
    else:
        o.location = loc
        o.rotation_euler = rot
    return o


def finish(name, bm, mat, parent, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0, segments=2, smooth=False, matrix=None):
    assert name not in bpy.data.objects, name
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name + '_Mesh')
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = smooth
    o = link(bpy.data.objects.new(name, me))
    o.parent = parent
    if matrix is not None:
        o.matrix_basis = matrix
    else:
        o.location = loc
        o.rotation_euler = rot
    me.materials.append(mat)
    if bevel:
        mod = o.modifiers.new('Edge radius', 'BEVEL')
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(35)
        mod.harden_normals = True
        o.modifiers.new('Corner normals', 'WEIGHTED_NORMAL').keep_sharp = True
    return o


def add_box(bm, size, center=(0, 0, 0), matrix=None):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    vs = geom['verts']
    bmesh.ops.scale(bm, vec=Vector(size), verts=vs)
    bmesh.ops.translate(bm, vec=Vector(center), verts=vs)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=vs)
    return vs


def add_cyl(bm, radius, depth, segments=24, center=(0, 0, 0), radius2=None, matrix=None):
    geom = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                                 radius2=radius if radius2 is None else radius2, depth=depth)
    vs = geom['verts']
    bmesh.ops.translate(bm, vec=Vector(center), verts=vs)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=vs)
    return vs


def add_lathe(bm, profile, segments=32, matrix=None, closed=False):
    """Revolve (radius, z) points. closed=True joins the last point back to the first
    (rings, bezels); otherwise non-zero end radii are capped (solid knobs, domes)."""
    if closed:
        profile = list(profile) + [profile[0]]
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(a * math.tau / segments), r * math.sin(a * math.tau / segments), z)) for a in range(segments)])
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for i in range(segments):
                bm.faces.new((a[0], b[i], b[(i + 1) % segments]))
        elif len(b) == 1:
            for i in range(segments):
                bm.faces.new((a[i], a[(i + 1) % segments], b[0]))
        else:
            for i in range(segments):
                bm.faces.new((a[i], a[(i + 1) % segments], b[(i + 1) % segments], b[i]))
    if closed:
        bmesh.ops.remove_doubles(bm, verts=rings[0] + rings[-1], dist=1e-7)
        rings = rings[:-1]
    else:
        if len(rings[0]) > 1:
            bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            bm.faces.new(rings[-1])
    vs = [v for ring in rings for v in ring if v.is_valid]
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=vs)
    return vs


def add_prism(bm, outline, z0, z1, matrix=None):
    lo = [bm.verts.new((x, y, z0)) for x, y in outline]
    hi = [bm.verts.new((x, y, z1)) for x, y in outline]
    n = len(outline)
    for i in range(n):
        bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=lo + hi)
    return lo + hi


def box(name, loc, size, mat, parent, bevel=.004, rot=(0, 0, 0)):
    bm = bmesh.new()
    add_box(bm, size)
    return finish(name, bm, mat, parent, loc, rot, bevel)


def cylinder(name, loc, radius, depth, mat, parent, segments=24, radius2=None, rot=(0, 0, 0), bevel=.0015):
    bm = bmesh.new()
    add_cyl(bm, radius, depth, segments, radius2=radius2)
    return finish(name, bm, mat, parent, loc, rot, bevel, 2, True)


def lathe(name, profile, mat, parent, loc=(0, 0, 0), rot=(0, 0, 0), segments=32, smooth=True, closed=False):
    bm = bmesh.new()
    add_lathe(bm, profile, segments, closed=closed)
    return finish(name, bm, mat, parent, loc, rot, 0, 2, smooth)


def loft(name, sections, mat, parent, loc=(0, 0, 0), bevel=.008):
    """Chamfered rectangles swept along Z: (z, width_x, depth_y, center_y, chamfer)."""
    bm = bmesh.new()
    rings = []
    for z, w, d, cy, c in sections:
        x, h = w / 2, d / 2
        pts = [(-x + c, -h), (x - c, -h), (x, -h + c), (x, h - c), (x - c, h), (-x + c, h), (-x, h - c), (-x, -h + c)]
        rings.append([bm.verts.new((px, py + cy, z)) for px, py in pts])
    for a, b in zip(rings, rings[1:]):
        for i in range(8):
            bm.faces.new((a[i], a[(i + 1) % 8], b[(i + 1) % 8], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return finish(name, bm, mat, parent, loc, (0, 0, 0), bevel)


def side_prism(name, profile, x0, x1, mat, parent, bevel=.008):
    """Extrude a (y, z) side profile across X."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in profile]
    b = [bm.verts.new((x1, y, z)) for y, z in profile]
    n = len(profile)
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    return finish(name, bm, mat, parent, bevel=bevel)


def pipe(name, points, radius, mat, parent, resolution=10):
    curve = bpy.data.curves.new(name + '_Curve', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    curve.resolution_u = resolution
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for p, co in zip(spline.bezier_points, points):
        p.co = co
        p.handle_left_type = p.handle_right_type = 'AUTO'
    o = link(bpy.data.objects.new(name, curve))
    o.parent = parent
    curve.materials.append(mat)
    return o


FONT = None


def font():
    global FONT
    if FONT is None:
        path = 'C:/Windows/Fonts/arialbd.ttf'
        FONT = bpy.data.fonts.load(path, check_existing=True) if os.path.exists(path) else None
    return FONT


def label(name, text, loc, size, mat, parent, rot=(0, 0, 0), align='CENTER', extrude=.0008):
    curve = bpy.data.curves.new(name + '_Text', 'FONT')
    curve.body = text
    curve.size = size
    curve.align_x = align
    curve.align_y = 'CENTER'
    curve.extrude = extrude
    if font():
        curve.font = font()
    o = link(bpy.data.objects.new(name, curve))
    o.parent = parent
    o.location = loc
    o.rotation_euler = rot
    curve.materials.append(mat)
    return o


def clip(poly, lo, hi):
    """Clip a 2D polygon to lo <= x <= hi (Sutherland-Hodgman, two planes)."""
    for limit, keep in ((lo, lambda x: x >= lo), (hi, lambda x: x <= hi)):
        out = []
        for i, p in enumerate(poly):
            q = poly[(i + 1) % len(poly)]
            if keep(p[0]):
                out.append(p)
            if keep(p[0]) != keep(q[0]):
                t = (limit - p[0]) / (q[0] - p[0])
                out.append((limit, p[1] + t * (q[1] - p[1])))
        poly = out
    return poly


def hazard(name, length, height, frame, parent, mats_, period=.07, depth=.003):
    """Yellow/black 45 degree stripes in a local (u across, v up) plate; frame maps u,v,w."""
    bm_black = bmesh.new()
    add_box(bm_black, (length, height, depth), (0, 0, depth / 2), frame)
    black = finish(name + '_Band', bm_black, mats_['black'], parent)
    bm = bmesh.new()
    u = -length / 2 - height
    while u < length / 2:
        poly = [(u, -height / 2), (u + period / 2, -height / 2), (u + period / 2 + height, height / 2), (u + height, height / 2)]
        poly = clip(poly, -length / 2, length / 2)
        if len(poly) >= 3:
            add_prism(bm, poly, depth, depth + .0015, frame)
        u += period
    return black, finish(name + '_Stripes', bm, mats_['trim'], parent)


def frame(origin, u, v):
    u, v = Vector(u).normalized(), Vector(v).normalized()
    w = u.cross(v)
    m = Matrix((u, v, w)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


def descendants(root):
    return [root] + list(root.children_recursive)


def clear_console():
    root = bpy.data.objects.get('ConsoleV3')
    if root is None:
        return 0
    doomed = descendants(root)
    for o in doomed:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and data.users == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Curve):
                bpy.data.curves.remove(data)
    return len(doomed)


def reach_report():
    """Palm contact distance from each shoulder's reach centre (limit 0.237 incl. sway margin)."""
    out = {}
    for o in scene().objects:
        if o.type == 'EMPTY' and 'Contact' in o.name and not o.name.startswith('REF_'):
            if 'Foot' in o.name:
                continue
            side = 'L' if o.matrix_world.translation.x > 0 else 'R'
            out[o.name] = round((o.matrix_world.translation - PALM_REACH_CENTER[side]).length, 4)
    return out


# ------------------------------------------------------------------ setup
if STAGE == 'setup':
    assert SCENE not in bpy.data.scenes, 'workbench already exists'
    ws = bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = ws
    ref = bpy.data.collections.new('REF_OperatorRuntime')
    ws.collection.children.link(ref)
    layer = bpy.context.view_layer
    layer.active_layer_collection = layer.layer_collection.children[ref.name]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=REFERENCE_GLB, bone_heuristic='BLENDER')
    imported = [o for o in bpy.data.objects if o not in before]
    hidden = []
    for o in imported:
        o.name = 'REF_' + o.name
        o['reference_only'] = True
        if o.name[4:].startswith(OLD_CONSOLE):
            o.hide_viewport = o.hide_render = True
            hidden.append(o.name)
    for o in imported:
        # Hiding is not inherited: children of old console parts go too.
        parent = o.parent
        while parent is not None and not parent.hide_render:
            parent = parent.parent
        if parent is not None:
            o.hide_viewport = o.hide_render = True
    layer.active_layer_collection = layer.layer_collection
    ws.render.engine = 'BLENDER_EEVEE'
    ws.render.fps = 60
    ws.frame_start, ws.frame_end = 1, 600
    ws.render.resolution_x, ws.render.resolution_y = 1400, 1000
    ws.view_settings.view_transform = 'AgX'
    world = bpy.data.worlds.new('V3_StudioWorld')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (.20, .23, .27, 1)
    bg.inputs[1].default_value = .55
    ws.world = world
    result.update(imported=len(imported), hidden=len(hidden), armature=[o.name for o in imported if o.type == 'ARMATURE'])

# ------------------------------------------------------------------ blockout: masses, pivots, contacts
if STAGE in ('blockout', 'rebuild'):
    bpy.context.window.scene = scene()
    removed = clear_console()
    M = mats()
    root = empty('ConsoleV3', size=.2)
    # Deck slab keeps the proven 1.64 x 1.74 footprint that clears the blade sweep.
    box('OP_Deck', (0, 0, .90), (1.64, 1.74, .14), M['shell'], root, .012)
    box('OP_DeckMat', (0, .03, .9735), (1.56, 1.62, .007), M['deck'], root, .003)
    # Seat pedestal and suspension bellows under the flying chair (same envelope as v2).
    loft('OP_SeatPedestal', [(.975, .44, .50, .30, .05), (1.20, .40, .46, .30, .05), (1.215, .36, .42, .30, .04)], M['shell'], root)
    for j in range(4):
        box('OP_SeatBellows%d' % j, (0, .30, 1.0 + j * .046), (.49, .55, .028), M['rubber'], root, .010)
    lathe('SL_FixedSocket', [(.072, 1.200), (.072, 1.218), (.043, 1.218), (.043, 1.200)], M['steel'], root, (0, .30, 0), closed=True)
    for side, s in (('L', 1), ('R', -1)):
        # Control pod: plinth, yellow step band, armrest body and a chamfered top.
        cx, cy, depth = s * .575, -.29, .94
        loft('OP_Pod_' + side, [(.974, .27, depth - .04, cy, .025), (1.058, .27, depth - .04, cy, .025),
                                (1.080, .33, depth, cy, .05), (1.405, .34, depth, cy, .055),
                                (1.460, .31, depth - .03, cy, .04)], M['shell'], root, (cx, 0, 0), .010)
        loft('OP_PodBand_' + side, [(1.058, .334, depth + .004, cy, .05), (1.080, .334, depth + .004, cy, .05)], M['trim'], root, (cx, 0, 0), .002)
        box('OP_PodTop_' + side, (cx, cy + .02, 1.4625), (.25, depth - .10, .006), M['panel'], root, .003)
        # Joystick: pivot on the pod top; DRIVE tilts sideways (travel is to the operator's
        # left), BLADE tilts fore/aft. The palm contact sits on the grip.
        lever = empty('OP_Lever_' + side, (s * .50, 0, 1.4655), root)
        lathe('OP_LeverBoot_' + side, [(.058, 0), (.056, .012), (.046, .018), (.048, .026), (.036, .034), (.038, .042), (.026, .050), (.020, .056)], M['rubber'], lever)
        cylinder('OP_LeverShaft_' + side, (0, 0, .082), .010, .06, M['steel'], lever)
        lathe('OP_Grip_' + side, [(.0, .104), (.020, .105), (.027, .117), (.031, .138), (.032, .160), (.030, .180), (.025, .195), (.014, .204), (.0, .207)], M['grip'], lever)
        empty('OP_GripContact_' + side, (0, 0, .165), lever)
        # Pedals keep the calibrated v2 hinge, angle and sole contact.
        pedal = empty('OP_Pedal_' + side, (s * .15, -.14, 1.11), root, (math.radians(22), 0, 0))
        box('OP_PedalPlate_' + side, (0, -.10, .015), (.20, .28, .03), M['dark_steel'], pedal, .006)
        empty('OP_FootContact_' + side, (0, -.11, .035), pedal)
    # Instrument dash between the pods: face tilted 28 degrees back toward the eyes.
    side_prism('OP_Dash', [(-.76, .974), (-.52, .974), (-.52, 1.20), (-.545, 1.245), (-.625, 1.395), (-.65, 1.43), (-.745, 1.43), (-.76, 1.415)], -.405, .405, M['shell'], root)
    face_up = Vector((0, -.47, .882)).normalized()
    face_n = Vector((0, .882, .47)).normalized()
    face_c = Vector((0, -.585, 1.32)) + face_n * .004
    for name, x, radius in (('Speed', .22, .058), ('RPM', 0.0, .072), ('Lift', -.22, .058)):
        g = empty('OP_Gauge_' + name, matrix=frame(face_c + Vector((x, 0, 0)), Vector((-1, 0, 0)), face_up), parent=root)
        g['radius'] = radius
        cylinder('OP_GaugeFace_' + name, (0, 0, .003), radius, .006, M['face'], g, 48)
        needle = empty('OP_Needle_' + name, (0, 0, .009), g)
        box('OP_NeedleBar_' + name, (0, radius * .38, 0), (.006, radius * .9, .003), M['needle'], needle, .0008)
    # Key (left) and guarded START (right) behind the joysticks; horn and trim dial inboard.
    cylinder('OP_KeyBoss', (.585, .10, 1.475), .032, .03, M['shell'], root)
    key = empty('OP_Key', (.585, .10, 1.512), root)
    box('OP_KeyHead', (0, 0, .030), (.034, .006, .028), M['key'], key, .002)
    empty('OP_KeyContact', (0, 0, .043), key)
    cylinder('OP_StartBoss', (-.585, .10, 1.475), .040, .03, M['trim'], root)
    start = empty('OP_Start', (-.585, .10, 1.505), root)
    lathe('OP_StartCap', [(.0, 0), (.016, 0), (.016, .016), (.034, .020), (.036, .028), (.030, .036), (.016, .039), (.0, .040)], M['red'], start)
    empty('OP_StartContact', (0, 0, .050), start)
    guard = empty('OP_Guard', (-.585, .165, 1.565), root)
    box('OP_GuardLid', (0, -.065, 0), (.10, .13, .006), M['guard'], guard, .002)
    empty('OP_GuardContact', (0, -.09, .008), guard)
    horn = empty('OP_Horn', (.47, .14, 1.465), root)
    lathe('OP_HornCap', [(.0, 0), (.026, 0), (.028, .030), (.022, .042), (.0, .045)], M['trim'], horn)
    empty('OP_HornContact', (0, 0, .050), horn)
    dial = empty('OP_Dial', (-.47, .14, 1.465), root)
    lathe('OP_DialKnob', [(.0, 0), (.034, 0), (.034, .008), (.029, .012), (.029, .060), (.024, .068), (.0, .069)], M['shell'], dial)
    empty('OP_DialContact', (0, 0, .075), dial)
    # Lamps: five on the dash top, direction lamps beside each stick; beacon on the left pod.
    for name, x, m in (('Power', .24, 'lamp_green'), ('Ready', .12, 'lamp_green'), ('Saw', 0.0, 'lamp_amber'), ('Lift', -.12, 'lamp_blue'), ('Warn', -.24, 'lamp_red')):
        lamp = empty('OP_Lamp_' + name, (x, -.70, 1.43), root)
        lathe('OP_LampLens_' + name, [(.0, 0), (.019, 0), (.019, .008), (.015, .018), (.008, .023), (.0, .024)], M[m], lamp, segments=24)
    for name, loc, m in (('Fwd', (.575, -.09, 1.4655), 'lamp_green'), ('Rev', (.425, -.09, 1.4655), 'lamp_amber'),
                         ('Up', (-.50, .075, 1.4655), 'lamp_blue'), ('Down', (-.50, -.075, 1.4655), 'lamp_amber')):
        lamp = empty('OP_Lamp_' + name, loc, root)
        lathe('OP_LampLens_' + name, [(.0, 0), (.012, 0), (.012, .006), (.008, .010), (.0, .011)], M[m], lamp, segments=20)
    cylinder('OP_BeaconBase', (.575, -.64, 1.478), .050, .03, M['shell'], root, 32)
    beacon = empty('OP_Beacon', (.575, -.64, 1.493), root)
    box('OP_BeaconMirror', (0, .012, .032), (.050, .004, .045), M['steel'], beacon, .001)
    dome = empty('OP_BeaconDome', (.575, -.64, 1.493), root)
    lathe('OP_BeaconLensShell', [(.0, 0), (.042, 0), (.042, .045), (.036, .065), (.022, .077), (.0, .080)], M['beacon'], dome, segments=32)
    bpy.context.view_layer.update()
    result.update(removed=removed, objects=len(descendants(root)), reach=reach_report())


# ------------------------------------------------------------------ detail
def bolts(name, points, mat, parent, radius=.0075, height=.005, normal=(0, 0, 1)):
    bm = bmesh.new()
    rot = Vector((0, 0, 1)).rotation_difference(Vector(normal)).to_matrix().to_4x4()
    for p in points:
        m = Matrix.Translation(Vector(p)) @ rot
        add_cyl(bm, radius, height, 6, (0, 0, height / 2), matrix=m)
    return finish(name, bm, mat, parent, smooth=False)


def ticks(bm, radius, count, length, width, start=135.0, sweep=270.0, z=.0065, major_every=1, minor_scale=.55):
    for i in range(count):
        phi = math.radians(start - sweep * i / (count - 1))
        major = i % major_every == 0
        ln = length if major else length * minor_scale
        r = radius - ln / 2
        m = Matrix.Translation((-math.sin(phi) * r, math.cos(phi) * r, z)) @ Matrix.Rotation(phi, 4, 'Z')
        add_box(bm, (width if major else width * .7, ln, .0012), matrix=m)


if STAGE == 'detail':
    bpy.context.window.scene = scene()
    M = mats()
    root = bpy.data.objects['ConsoleV3']
    assert 'OP_DeckTread' not in bpy.data.objects, 'detail already built; run rebuild then detail'
    # --- deck: diamond tread outside the occupied footprints, pedal plate, hazard edge, bumpers
    busy = [((.39, .76), (-.79, .21)), ((-.76, -.39), (-.79, .21)), ((-.42, .42), (-.79, -.49)),
            ((-.32, .32), (.00, .60)), ((-.33, .33), (-.49, .02))]
    bm = bmesh.new()
    n = 0
    for i in range(-10, 11):
        for j in range(-10, 11):
            x, y = i * .075, j * .075 + .03
            if abs(x) > .74 or abs(y - .03) > .76 or any(a <= x <= b and c <= y <= d for (a, b), (c, d) in busy):
                continue
            add_box(bm, (.042, .011, .004), (0, 0, 0), Matrix.Translation((x, y, .979)) @ Matrix.Rotation(math.radians(45 if (i + j) % 2 else -45), 4, 'Z'))
            n += 1
    finish('OP_DeckTread', bm, M['dark_steel'], root)
    box('OP_PedalFloor', (0, -.235, .979), (.64, .50, .006), M['panel'], root, .003)
    bm = bmesh.new()
    for i in range(6):
        add_box(bm, (.58, .012, .004), (0, -.03 - i * .08, .984))
    finish('OP_PedalFloorRibs', bm, M['dark_steel'], root)
    hazard('OP_DeckHazardFront', 1.56, .055, frame((0, -.838, .977), (1, 0, 0), (0, 1, 0)), root, M)
    for x in (-.79, .79):
        for y in (-.84, .84):
            box('OP_DeckBumper_%+.0f%+.0f' % (x * 10, y * 10), (x, y, .905), (.09, .09, .155), M['trim'], root, .018)
        box('OP_DeckSideBand_%+.0f' % (x * 10), (x * 1.041, 0, .90), (.004, 1.55, .045), M['panel'], root, .001)
    bolts('OP_DeckBolts', [(x, y, .974) for x in (-.70, -.35, .35, .70) for y in (-.80, .80)] + [(x, y, .974) for x in (-.77, .77) for y in (-.45, 0, .45)], M['steel'], root)
    for side, s in (('L', 1), ('R', -1)):
        cx = s * .575
        # --- pod skin: blue side panel with its function name, hazard nose, rear vents, bolts
        box('OP_PodSide_' + side, (s * .7475, -.29, 1.245), (.006, .78, .25), M['panel'], root, .002)
        label('OP_PodSideText_' + side, 'DRIVE' if s > 0 else 'BLADE', (s * .7515, -.29, 1.25), .085, M['ink'], root,
              (math.radians(90), 0, math.radians(90 * s)))
        hazard('OP_PodHazard_' + side, .27, .075, frame((cx, -.7615, 1.012), (1, 0, 0), (0, 0, 1)), root, M, period=.06)
        bm = bmesh.new()
        for k in range(5):
            add_box(bm, (.20, .006, .012), (cx, .183, 1.16 + k * .03))
        finish('OP_PodVents_' + side, bm, M['dark_steel'], root)
        bolts('OP_PodBolts_' + side, [(cx + dx, y, 1.4655) for dx in (-.11, .11) for y in (-.70, -.18, .12)], M['steel'], root, .006, .004)
        for k, (x0, x1) in enumerate(((s * .52, s * .55), (s * .64, s * .62))):
            pipe('OP_PodConduit_%s%d' % (side, k), [(x0, .19, 1.13 - k * .04), (x0, .27, 1.08 - k * .04), (x1, .36, .99), (x1, .44, .985)], .016, M['rubber'], root)
            cylinder('OP_PodGland_%s%d' % (side, k), (x0, .188, 1.13 - k * .04), .022, .012, M['steel'], root, 16, rot=(math.radians(90), 0, 0))
            cylinder('OP_DeckGland_%s%d' % (side, k), (x1, .45, .982), .024, .012, M['steel'], root, 16)
        # --- gate plate around the stick
        box('OP_GatePlate_' + side, (s * .50, 0, 1.4675), (.13, .13, .005), M['steel'], root, .002)
        slot = (.10, .018, .003) if s > 0 else (.018, .10, .003)
        box('OP_GateSlot_' + side, (s * .50, 0, 1.4705), slot, M['black'], root, .001)
        glyphs = [('F', (.555, .052)), ('N', (.50, .052)), ('R', (.445, .052))] if s > 0 else [('UP', (-.44, .045)), ('HOLD', (-.44, 0)), ('DN', (-.44, -.045))]
        for k, (text, (x, y)) in enumerate(glyphs):
            label('OP_GateText_%s%d' % (side, k), text, (x, y, 1.4705), .018 if s > 0 else .012, M['ink'], root, (0, 0, math.pi))
        # --- stick detail: collar, thumb button
        lever = bpy.data.objects['OP_Lever_' + side]
        lathe('OP_LeverCollar_' + side, [(.0, .098), (.024, .098), (.024, .107), (.0, .107)], M['steel'], lever)
        cylinder('OP_ThumbButton_' + side, (0, -.014, .202), .009, .007, M['trim'] if s > 0 else M['red'], lever, 16, rot=(math.radians(-25), 0, 0))
        # --- LED bar display: speed (left) / blade lift (right); Godot lights each segment
        box('OP_BarBezel_' + side, (cx, -.43, 1.469), (.075, .215, .008), M['black'], root, .002)
        for k in range(8):
            seg = empty('OP_Bar_%s%d' % (side, k), (cx, -.345 - k * .024, 1.4735), root, size=.01)
            box('OP_BarSeg_%s%d' % (side, k), (0, 0, 0), (.052, .016, .004), M['lamp_green'] if s > 0 else M['lamp_blue'], seg, .001)
        label('OP_BarText_' + side, 'SPEED' if s > 0 else 'LIFT', (cx, -.315, 1.4705), .016, M['ink'], root, (0, 0, math.pi))
        # --- pedal: hinge axle, blue anti-slip pads, toe lip, floor brackets
        pedal = bpy.data.objects['OP_Pedal_' + side]
        cylinder('OP_PedalAxle_' + side, (0, 0, 0), .018, .22, M['steel'], pedal, 16, rot=(0, math.radians(90), 0))
        for k in range(3):
            box('OP_PedalPad_%s%d' % (side, k), (0, -.035 - k * .07, .0325), (.17, .045, .005), M['panel'], pedal, .0015)
        box('OP_PedalToe_' + side, (0, -.236, .038), (.20, .012, .022), M['dark_steel'], pedal, .003)
        for dx in (-.115, .115):
            box('OP_PedalBracket_%s%+.0f' % (side, dx * 1000), (s * .15 + dx, -.14, 1.043), (.018, .06, .138), M['dark_steel'], root, .004)
    # --- key switch (left)
    lathe('OP_KeyBarrel', [(.0, 1.490), (.022, 1.490), (.022, 1.502), (.019, 1.506), (.0, 1.506)], M['steel'], root, (.585, .10, 0))
    key = bpy.data.objects['OP_Key']
    box('OP_KeyShank', (0, 0, .004), (.007, .0035, .016), M['key'], key, .0008)
    lathe('OP_KeyRing', [(.0, .038), (.006, .038), (.006, .046), (.0, .046)], M['steel'], key, (0, 0, 0), (math.radians(90), 0, 0), segments=16)
    # --- START under a flip guard (right)
    lathe('OP_StartHousing', [(.0, 1.490), (.030, 1.490), (.030, 1.505), (.0, 1.505)], M['black'], root, (-.585, .10, 0))
    guard = bpy.data.objects['OP_Guard']
    for dx in (-.047, .047):
        box('OP_GuardWall_%+.0f' % (dx * 1000), (dx, -.065, -.022), (.006, .13, .045), M['guard'], guard, .0015)
    box('OP_GuardFront', (0, -.127, -.022), (.10, .006, .045), M['guard'], guard, .0015)
    cylinder('OP_GuardHinge', (0, 0, 0), .006, .11, M['steel'], guard, 12, rot=(0, math.radians(90), 0))
    box('OP_GuardBracket', (-.585, .176, 1.515), (.12, .014, .05), M['dark_steel'], root, .003)
    # --- horn (left, inboard) and trim dial (right, inboard)
    lathe('OP_HornHousing', [(.0, 1.4655), (.036, 1.4655), (.036, 1.478), (.0, 1.478)], M['black'], root, (.47, .14, 0))
    dial = bpy.data.objects['OP_Dial']
    bm = bmesh.new()
    for k in range(18):
        a = k * math.tau / 18
        add_box(bm, (.004, .004, .044), (math.cos(a) * .029, math.sin(a) * .029, .036))
    finish('OP_DialKnurl', bm, M['dark_steel'], dial)
    box('OP_DialPointer', (0, -.016, .0695), (.004, .024, .0015), M['ink'], dial, .0005)
    bm = bmesh.new()
    for k in range(7):
        phi = math.radians(135 - 270 * k / 6)
        add_box(bm, (.003, .010, .0012), (0, 0, 0), Matrix.Translation((-.47 - math.sin(phi) * .045, .14 - math.cos(phi) * .045, 1.4665)) @ Matrix.Rotation(-phi, 4, 'Z'))
    finish('OP_DialScale', bm, M['ink'], root)
    # --- instrument dash: blue face plate, bezels, ticks, redline, labels, lamp bezels, nameplate
    face_up = Vector((0, -.47, .882)).normalized()
    face_n = Vector((0, .882, .47)).normalized()
    face_c = Vector((0, -.585, 1.32))
    plate = frame(face_c + face_n * .002, Vector((-1, 0, 0)), face_up)
    bm = bmesh.new()
    add_box(bm, (.78, .165, .004), matrix=plate)
    finish('OP_DashFace', bm, M['panel'], root)
    for name in ('Speed', 'RPM', 'Lift'):
        g = bpy.data.objects['OP_Gauge_' + name]
        r = g['radius']
        lathe('OP_GaugeBezel_' + name, [(r - .001, 0), (r + .010, 0), (r + .010, .008), (r + .004, .012), (r - .001, .012)], M['steel'], g, segments=48, closed=True)
        bm = bmesh.new()
        ticks(bm, r - .004, 21, .012, .0026, major_every=5)
        finish('OP_GaugeTicks_' + name, bm, M['ink'], g)
        bm = bmesh.new()
        ticks(bm, r - .004, 5, .010, .005, start=135 - 270 * .8, sweep=270 * .2, z=.0068)
        finish('OP_GaugeRedline_' + name, bm, M['redline'], g)
        label('OP_GaugeText_' + name, {'Speed': 'SPEED', 'RPM': 'RPM', 'Lift': 'LIFT'}[name], (0, -r * .42, .0068), r * .22, M['ink'], g)
        needle = bpy.data.objects['OP_Needle_' + name]
        cylinder('OP_NeedleHub_' + name, (0, 0, .0025), .008, .005, M['steel'], needle, 16)
    names = {'Power': 'PWR', 'Ready': 'RDY', 'Saw': 'SAW', 'Lift': 'LIFT', 'Warn': 'WARN'}
    for name, text in names.items():
        lamp = bpy.data.objects['OP_Lamp_' + name]
        lathe('OP_LampBezel_' + name, [(.018, -.0005), (.026, -.0005), (.026, .006), (.020, .009), (.018, .009)], M['steel'], lamp, segments=24, closed=True)
        label('OP_LampText_' + name, text, (lamp.location.x, -.732, 1.4305), .012, M['ink'], root, (0, 0, math.pi))
    for name in ('Fwd', 'Rev', 'Up', 'Down'):
        lamp = bpy.data.objects['OP_Lamp_' + name]
        lathe('OP_LampBezel_' + name, [(.011, 0), (.016, 0), (.016, .004), (.011, .005)], M['steel'], lamp, segments=20, closed=True)
    box('OP_NamePlate', (0, -.7625, 1.215), (.56, .004, .10), M['panel'], root, .002)
    label('OP_NameText', 'GODOT SAW', (0, -.765, 1.215), .066, M['ink'], root, (math.radians(90), 0, 0))
    hazard('OP_DashHazard', .80, .07, frame((0, -.7615, 1.03), (1, 0, 0), (0, 0, 1)), root, M, period=.06)
    bolts('OP_DashBolts', [(x, y, 1.43) for x in (-.37, .37) for y in (-.67, -.73)], M['steel'], root, .006, .004)
    # --- beacon bulb inside the dome; E-stop mushroom on the right pod nose (decor)
    dome = bpy.data.objects['OP_BeaconDome']
    lathe('OP_BeaconBulb', [(.0, .008), (.012, .010), (.014, .028), (.009, .040), (.0, .043)], M['lamp_amber'], dome, segments=16)
    lathe('OP_EStopBase', [(.0, 1.4655), (.042, 1.4655), (.042, 1.488), (.0, 1.488)], M['trim'], root, (-.575, -.64, 0))
    lathe('OP_EStopCap', [(.0, 1.488), (.016, 1.488), (.016, 1.500), (.038, 1.506), (.040, 1.516), (.030, 1.527), (.0, 1.530)], M['red'], root, (-.575, -.64, 0))
    bpy.context.view_layer.update()
    result.update(tread=n, objects=len(descendants(root)), reach=reach_report())


# ------------------------------------------------------------------ export
MOVING_PREFIX = ('OP_Lever_', 'OP_Pedal_', 'OP_Key', 'OP_Start', 'OP_Guard', 'OP_Horn', 'OP_Dial',
                 'OP_Needle_', 'OP_Beacon', 'OP_Lamp_', 'OP_Bar_', 'OP_Gauge_')

if STAGE == 'export':
    ws = scene()
    root = bpy.data.objects['ConsoleV3']
    saved_frame = ws.frame_current
    ws.frame_set(1)
    stale = bpy.data.scenes.get('ConsoleV3_Export')
    if stale:
        for o in list(stale.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.scenes.remove(stale)
    ex = bpy.data.scenes.new('ConsoleV3_Export')
    copies = {}
    for original in descendants(root):
        c = original.copy()
        c.animation_data_clear()
        if original.data is not None:
            c.data = original.data.copy()
        ex.collection.objects.link(c)
        copies[original] = c
    for original, c in copies.items():
        c.parent = copies.get(original.parent)
        c.matrix_parent_inverse = original.matrix_parent_inverse.copy()
        c.matrix_basis = original.matrix_basis.copy()
    # Rest pivots: previews may have left controls keyed away from rest.
    names = {o: o.name for o in copies}
    bpy.context.window.scene = ex
    for original in copies:
        original.name = 'SRC_' + names[original]
    for original, c in copies.items():
        c.name = names[original]
    bpy.context.view_layer.update()
    # Static geometry joins per parent and material; every pivot keeps its own node.
    groups = {}
    for o in list(ex.objects):
        if o.type in ('MESH', 'CURVE', 'FONT'):
            key = (o.parent, o.data.materials[0] if len(o.data.materials) else None)
            groups.setdefault(key, []).append(o)
    joined = []
    for (parent, mat), objs in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.convert(target='MESH')  # applies each object's own bevel stack
        if len(objs) > 1:
            bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        o.name = (parent.name if parent else 'ConsoleV3') + '_' + (mat.name if mat else 'Mesh')
        o.data.name = o.name
        joined.append(o.name)
    bpy.ops.object.select_all(action='SELECT')
    ex_root = next(o for o in ex.objects if o.name == 'ConsoleV3')
    ex_root.location = (0, 0, 0)
    bpy.ops.export_scene.gltf(filepath=CONSOLE_GLB, export_format='GLB', use_selection=True, use_active_scene=True,
                              export_animations=False, export_apply=True, export_yup=True, export_cameras=False,
                              export_lights=False, export_extras=False)
    tris = sum(len(p.vertices) - 2 for o in ex.objects if o.type == 'MESH' for p in o.data.polygons)
    report = {'objects': len(ex.objects), 'meshes': sum(o.type == 'MESH' for o in ex.objects), 'triangles': tris,
              'bytes': os.path.getsize(CONSOLE_GLB), 'materials': sorted({m.name for o in ex.objects if o.type == 'MESH' for m in o.data.materials if m})}
    bpy.context.window.scene = ws
    for o in list(ex.objects):
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if isinstance(data, bpy.types.Mesh) and data.users == 0:
            bpy.data.meshes.remove(data)
    bpy.data.scenes.remove(ex)
    for original, name in names.items():
        original.name = name
    ws.frame_set(saved_frame)
    with open(OUT + '/export.json', 'w') as fh:
        json.dump(report, fh, indent=2)
    result.update(report)

# ------------------------------------------------------------------ editable source (this scene only)
if STAGE == 'write_source':
    ws = scene()
    # A library write stores only this scene and what it uses, leaving the open file alone.
    bpy.data.libraries.write(SOURCE, {ws}, path_remap='RELATIVE_ALL', fake_user=True, compress=True)
    result.update(source=SOURCE, bytes=os.path.getsize(SOURCE))

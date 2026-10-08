"""AIQUIZ mascot "カモメ船長" (seagull captain), staged inside the live Blender (Higgsfield bridge).

    exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/build_mascot.py',
              encoding='utf-8').read(), {'mascot_stage': 'parts'})

Stages (run in order, one bridge call each; save the .blend between them):
  'parts'  editable parts in collection MASCOT_Parts (procedural materials), standing on the rig
  'skin'   HERO_Mascot: the parts merged into one mesh, weighted to the 16 DEF-* bones of 'Rig'
  'uv'     HERO_Mascot gets the UVBake atlas layout
  'bake'   Cycles bakes the procedural colour and ambient occlusion into ../mascot_albedo.png and
           HERO_Mascot switches to two materials (matte / gloss) that both read that texture
  'export' ../mascot_model.glb (Rig + HERO_Mascot, no animations)

The skeleton is the same 16-bone layout the pilot, saw operator and finale referee already
use (DEF-head / DEF-hips are both roots at z 0.796; arms hang off DEF-head). Front is -Y,
left (.L) is +X, metres, Z up. Each limb part is rigid on its bone; the round body and
everything on it blend from DEF-hips to DEF-head between z 0.74 and 0.88, so a nod bends
the body the way the old one did.
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix, Quaternion

ROOT = 'C:/AIQUIZ/AIQUIZ-Godot'
ASSET = ROOT + '/assets/characters/aiquiz_mascot'
STAGE = globals().get('mascot_stage', 'parts')
PARTS = 'MASCOT_Parts'
FINAL = 'MASCOT_Final'
TEXTURE = ASSET + '/mascot_albedo.png'
TEXTURE_SIZE = 2048

BODY_C = Vector((0.0, 0.0, 1.03))
# Parts whose material reads glossy in the game (visor, gold, eyes); everything else is matte.
GLOSS = ('MSC_Visor', 'MSC_Gold', 'MSC_Sclera', 'MSC_Iris', 'MSC_Pupil', 'MSC_Shine')


# ----------------------------------------------------------------------------- scene helpers

def coll(name, parent=None):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(c)
    return c


def _principled(m):
    m.use_nodes = True
    return next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def mat(name, color, rough=0.55, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    b = _principled(m)
    b.inputs['Base Color'].default_value = (*color, 1.0)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    m.diffuse_color = (*color, 1.0)
    return m


def _new_obj(name, bm, c, m, smooth=True):
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    if m is not None:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    c.objects.link(o)
    return o


# ----------------------------------------------------------------------------- geometry helpers

def blob(name, c, center, radii, m, rot=None, seg=32, rings=16, deform=None):
    """Ellipsoid; deform(u) -> Vector offset in local units for the unit-sphere point u."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    R = Vector(radii)
    q = rot if rot is not None else Quaternion()
    for v in bm.verts:
        u = v.co.normalized()
        local = Vector((u.x * R.x, u.y * R.y, u.z * R.z))
        if deform is not None:
            local += deform(u)
        v.co = Vector(center) + q @ local
    return _new_obj(name, bm, c, m)


def loft(name, c, pts, radii, m, up=(0, 0, 1), seg=16, closed=False, round_ends=True):
    """Tube through pts with elliptical sections (rx across, ry toward `up`); rounded or closed."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    up = Vector(up)
    frames = []
    for i in range(n):
        if closed:
            t = pts[(i + 1) % n] - pts[i - 1]
        elif i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        t.normalize()
        side = t.cross(up)
        if side.length < 1e-6:
            side = t.cross(Vector((1, 0, 0)))
        side.normalize()
        upv = side.cross(t).normalized()
        frames.append((pts[i], t, side, upv, radii[i][0], radii[i][1]))
    if round_ends and not closed:
        def cap(frame, sign):
            p, t, side, upv, rx, ry = frame
            r = 0.5 * (rx + ry)
            out = []
            for k in (1, 2, 3):
                a = math.radians(30 * k)
                out.append((p + t * sign * r * math.sin(a) * 0.9, t, side, upv, rx * math.cos(a), ry * math.cos(a)))
            return out
        frames = list(reversed(cap(frames[0], -1))) + frames + cap(frames[-1], 1)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    rings = []
    for (p, t, side, upv, rx, ry) in frames:
        ring = []
        for j in range(seg):
            a = 2 * math.pi * j / seg
            ring.append(bm.verts.new(p + side * (rx * math.cos(a)) + upv * (ry * math.sin(a))))
        rings.append(ring)
    count = len(rings)
    spans = count if closed else count - 1
    for i in range(spans):
        r0, r1 = rings[i], rings[(i + 1) % count]
        for j in range(seg):
            f = bm.faces.new((r0[j], r0[(j + 1) % seg], r1[(j + 1) % seg], r1[j]))
            for loop, (uu, vv) in zip(f.loops, ((j, i), (j + 1, i), (j + 1, i + 1), (j, i + 1))):
                loop[uv].uv = (uu / seg, vv / max(1, spans))
    if not closed:
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            f = bm.faces.new(list(reversed(ring)) if flip else ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return _new_obj(name, bm, c, m)


def feather(name, c, root, tip, width, m, normal=(0, 0, 1), thick=0.016, seg=10, bend=0.0, round_tip=False):
    """A tapered flat feather from root to tip, flat side facing `normal`; bend sags the middle.
    round_tip keeps the width to the end (a soft, rounded feather instead of a point)."""
    root, tip = Vector(root), Vector(tip)
    nrm = Vector(normal).normalized()
    profile = (0.45, 0.85, 1.0, 1.0, 0.97, 0.88, 0.62) if round_tip else (0.35, 0.80, 1.0, 0.96, 0.78, 0.48, 0.18)
    pts, radii = [], []
    for i, w in enumerate(profile):
        t = i / (len(profile) - 1)
        pts.append(root.lerp(tip, t) + nrm * (-bend * math.sin(math.pi * t)))
        radii.append((width * w * 0.5, thick * (0.6 + 0.4 * w) * 0.5))
    return loft(name, c, pts, radii, m, up=nrm, seg=seg)


# ----------------------------------------------------------------------------- body surface

def body_local(u):
    """Unit-sphere direction -> body surface relative to BODY_C (egg, cheek fluff, chest fluff)."""
    x, y, z = u
    below = max(0.0, -z)
    p = Vector((x * 0.55 * (1 + 0.045 * below), y * 0.52 * (1 + 0.04 * below), z * (0.56 if z > 0 else 0.53)))
    bump = 0.0
    for s in (1, -1):
        d = Vector((s * 0.62, -0.70, -0.36)).normalized()
        bump += 0.032 * math.exp(-((1 - u.dot(d)) / 0.035))
    d = Vector((0, -0.80, -0.60)).normalized()
    bump += 0.022 * math.exp(-((1 - u.dot(d)) / 0.05))
    return p + u * bump


def surf(u):
    u = Vector(u).normalized()
    return BODY_C + body_local(u)


def surf_normal(u):
    u = Vector(u).normalized()
    a = u.orthogonal().normalized()
    b = u.cross(a).normalized()
    e = 0.01
    p0 = surf(u)
    pa = surf(u + a * e)
    pb = surf(u + b * e)
    n = (pa - p0).cross(pb - p0).normalized()
    return n if n.dot(u) > 0 else -n


def facing(nrm):
    """Rotation taking local -Y (a part's front) onto nrm."""
    return Vector((0, -1, 0)).rotation_difference(Vector(nrm).normalized())


# ----------------------------------------------------------------------------- materials

def _socket(sockets, identifier):
    return next(s for s in sockets if s.identifier == identifier)


def body_material():
    m = bpy.data.materials.get('MSC_Body') or bpy.data.materials.new('MSC_Body')
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type not in ('OUTPUT_MATERIAL', 'BSDF_PRINCIPLED'):
            nt.nodes.remove(n)
    bsdf = _principled(m)
    bsdf.inputs['Roughness'].default_value = 0.62
    L = nt.links.new
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    tex = nt.nodes.new('ShaderNodeTexCoord')
    nsep = nt.nodes.new('ShaderNodeSeparateXYZ')
    L(geo.outputs['Normal'], nsep.inputs[0])
    psep = nt.nodes.new('ShaderNodeSeparateXYZ')
    L(tex.outputs['Object'], psep.inputs[0])

    def remap(src, a, b):
        r = nt.nodes.new('ShaderNodeMapRange')
        r.clamp = True
        r.inputs['From Min'].default_value = a
        r.inputs['From Max'].default_value = b
        L(src, r.inputs['Value'])
        return r.outputs['Result']

    def mul(a, b):
        n = nt.nodes.new('ShaderNodeMath')
        n.operation = 'MULTIPLY'
        L(a, n.inputs[0])
        if isinstance(b, float):
            n.inputs[1].default_value = b
        else:
            L(b, n.inputs[1])
        return n.outputs[0]

    def one_minus(a):
        n = nt.nodes.new('ShaderNodeMath')
        n.operation = 'SUBTRACT'
        n.inputs[0].default_value = 1.0
        L(a, n.inputs[1])
        return n.outputs[0]

    def mix(fac, a, b):
        n = nt.nodes.new('ShaderNodeMix')
        n.data_type = 'RGBA'
        L(fac, _socket(n.inputs, 'Factor_Float'))
        for value, ident in ((a, 'A_Color'), (b, 'B_Color')):
            if isinstance(value, tuple):
                _socket(n.inputs, ident).default_value = (*value, 1)
            else:
                L(value, _socket(n.inputs, ident))
        return _socket(n.outputs, 'Result_Color')

    # Gray mantle on the back below the white head, soft edge.
    back = remap(nsep.outputs['Y'], 0.10, 0.38)
    low = one_minus(remap(psep.outputs['Z'], 1.08, 1.26))
    mantle = mul(back, low)
    # Feather scallops on the mantle (subtle darker rows).
    wave = nt.nodes.new('ShaderNodeTexWave')
    wave.wave_type = 'BANDS'
    wave.bands_direction = 'Z'
    wave.wave_profile = 'SAW'
    wave.inputs['Scale'].default_value = 7.0
    wave.inputs['Distortion'].default_value = 3.0
    wave.inputs['Detail'].default_value = 1.0
    L(tex.outputs['Object'], wave.inputs['Vector'])
    scallop = mul(mul(remap(wave.outputs['Fac'], 0.80, 1.0), mantle), 0.10)
    base = mix(mantle, (0.97, 0.97, 0.96), (0.50, 0.55, 0.63))
    base = mix(scallop, base, (0.38, 0.41, 0.47))
    # Cheek blush.
    blush = None
    for s in (1, -1):
        d = nt.nodes.new('ShaderNodeVectorMath')
        d.operation = 'DISTANCE'
        L(tex.outputs['Object'], d.inputs[0])
        d.inputs[1].default_value = (s * 0.31, -0.425, 1.065)
        b = one_minus(remap(d.outputs['Value'], 0.025, 0.085))
        if blush is None:
            blush = b
        else:
            mx = nt.nodes.new('ShaderNodeMath')
            mx.operation = 'MAXIMUM'
            L(blush, mx.inputs[0])
            L(b, mx.inputs[1])
            blush = mx.outputs[0]
    base = mix(mul(blush, 0.75), base, (1.0, 0.56, 0.58))
    L(base, bsdf.inputs['Base Color'])
    m.diffuse_color = (0.97, 0.97, 0.96, 1)
    return m


def gradient_material(name, axis, a, b, ca, cb, rough=0.45):
    """Colour ca at object coordinate `axis`==a blending to cb at b."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type not in ('OUTPUT_MATERIAL', 'BSDF_PRINCIPLED'):
            nt.nodes.remove(n)
    bsdf = _principled(m)
    bsdf.inputs['Roughness'].default_value = rough
    tex = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(tex.outputs['Object'], sep.inputs[0])
    r = nt.nodes.new('ShaderNodeMapRange')
    r.clamp = True
    r.inputs['From Min'].default_value = a
    r.inputs['From Max'].default_value = b
    nt.links.new(sep.outputs[axis], r.inputs['Value'])
    mx = nt.nodes.new('ShaderNodeMix')
    mx.data_type = 'RGBA'
    nt.links.new(r.outputs['Result'], _socket(mx.inputs, 'Factor_Float'))
    _socket(mx.inputs, 'A_Color').default_value = (*ca, 1)
    _socket(mx.inputs, 'B_Color').default_value = (*cb, 1)
    nt.links.new(_socket(mx.outputs, 'Result_Color'), bsdf.inputs['Base Color'])
    m.diffuse_color = (*ca, 1)
    return m


# ----------------------------------------------------------------------------- the build

def build_parts():
    c = coll(PARTS)
    for o in list(c.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    M = {
        'body': body_material(),
        'feather': mat('MSC_Feather', (0.60, 0.64, 0.71), 0.6),
        'tip': mat('MSC_WingTip', (0.07, 0.08, 0.10), 0.5),
        'spot': mat('MSC_Spot', (0.97, 0.97, 0.96), 0.6),
        'tail': mat('MSC_Tail', (0.95, 0.95, 0.94), 0.6),
        'sclera': mat('MSC_Sclera', (0.98, 0.98, 0.98), 0.25),
        'iris': mat('MSC_Iris', (0.16, 0.10, 0.06), 0.3),
        'pupil': mat('MSC_Pupil', (0.02, 0.02, 0.03), 0.2),
        'shine': mat('MSC_Shine', (1.0, 1.0, 1.0), 0.1),
        'brow': mat('MSC_Brow', (0.33, 0.36, 0.42), 0.6),
        'beak': gradient_material('MSC_Beak', 'Y', -0.48, -0.74, (1.0, 0.82, 0.18), (1.0, 0.60, 0.10)),
        'gonys': mat('MSC_Gonys', (0.88, 0.12, 0.10), 0.45),
        'nostril': mat('MSC_Nostril', (0.45, 0.28, 0.06), 0.6),
        'leg': gradient_material('MSC_Leg', 'Z', 0.55, 0.02, (1.0, 0.62, 0.20), (1.0, 0.50, 0.12), 0.55),
        'claw': mat('MSC_Claw', (0.20, 0.16, 0.14), 0.4),
        'cap': mat('MSC_Cap', (0.96, 0.96, 0.95), 0.7),
        'navy': mat('MSC_Navy', (0.05, 0.09, 0.25), 0.55),
        'visor': mat('MSC_Visor', (0.02, 0.02, 0.03), 0.15),
        'gold': mat('MSC_Gold', (1.0, 0.74, 0.22), 0.3),
        'scarf': mat('MSC_Scarf', (0.10, 0.42, 0.92), 0.55),
    }
    # --- body
    blob('MSC_Body', c, BODY_C, (1, 1, 1), M['body'], seg=72, rings=36,
         deform=lambda u: body_local(u) - u)

    # --- eyes: sclera, iris, pupil, two highlights, upper lid in body colour
    for s, side in ((1, 'L'), (-1, 'R')):
        u = Vector((s * 0.35, -0.89, 0.27)).normalized()
        p = surf(u)
        n = surf_normal(u)
        q = facing(n)
        def at(x, fwd, z):
            return p + q @ Vector((x, -fwd - 0.016, z))
        # big dark eyes with two highlights, looking a touch toward the centre
        blob('MSC_Sclera.' + side, c, at(0, 0.0, 0), (0.086, 0.050, 0.106), M['sclera'], rot=q, seg=24, rings=12)
        blob('MSC_Iris.' + side, c, at(-s * 0.010, 0.040, -0.008), (0.068, 0.014, 0.080), M['iris'], rot=q, seg=20, rings=10)
        blob('MSC_Pupil.' + side, c, at(-s * 0.011, 0.050, -0.010), (0.044, 0.010, 0.053), M['pupil'], rot=q, seg=16, rings=8)
        blob('MSC_Shine.' + side, c, at(-s * 0.010 + 0.020, 0.058, 0.028), (0.020, 0.006, 0.024), M['shine'], rot=q, seg=10, rings=6)
        blob('MSC_Shine2.' + side, c, at(-s * 0.034, 0.057, -0.036), (0.010, 0.005, 0.011), M['shine'], rot=q, seg=8, rings=4)
        # thin dark lash line on the top rim of the white, with a small flick at the outer corner
        lash, lash_r = [], []
        for k in range(13):
            a = math.radians(28 + 124 * k / 12)
            x, z = 0.084 * math.cos(a), 0.103 * math.sin(a)
            fwd = 0.050 * math.sqrt(max(0.0, 1 - (x / 0.086) ** 2 - (z / 0.106) ** 2))
            outer = max(0.0, s * math.cos(a))
            lash.append(at(x, fwd + 0.003, z + 0.003 * outer))
            lash_r.append((0.0055 + 0.004 * outer * outer, 0.0055 + 0.004 * outer * outer))
        loft('MSC_Lash.' + side, c, lash, lash_r, M['pupil'], up=tuple(n), seg=8)
        # one soft brow feather, slightly arched, high above the eye
        a = surf(Vector((s * 0.15, -0.80, 0.56)))
        b = surf(Vector((s * 0.46, -0.72, 0.58)))
        nn = surf_normal(Vector((s * 0.30, -0.78, 0.56)))
        feather('MSC_Brow.' + side, c, a + nn * 0.010, b + nn * 0.010, 0.040, M['brow'], normal=nn, thick=0.014, seg=8, bend=-0.012)
        # cheek tufts: three small white feathers breaking the round outline
        for k, (dz, ln) in enumerate(((0.06, 0.10), (0.0, 0.13), (-0.06, 0.10))):
            u = Vector((s * 0.93, -0.30, (1.00 + dz - BODY_C.z) / 0.56)).normalized()
            root = surf(u) - surf_normal(u) * 0.03
            tip = root + (surf_normal(u) + Vector((0, 0.15, -0.35 + dz * 3))).normalized() * ln
            feather('MSC_CheekTuft%d.%s' % (k, side), c, root, tip, 0.06, M['tail'], normal=(0, -1, 0.2), thick=0.02, seg=8, round_tip=True)

    # --- beak: upper and lower bill, hooked tip, red gonys spot, nostrils
    up_pts = [(0, -0.47, 1.052), (0, -0.55, 1.054), (0, -0.62, 1.050), (0, -0.68, 1.040), (0, -0.718, 1.024), (0, -0.735, 1.000)]
    up_r = [(0.125, 0.066), (0.105, 0.056), (0.080, 0.046), (0.055, 0.036), (0.034, 0.028), (0.020, 0.020)]
    loft('MSC_Bill', c, up_pts, up_r, M['beak'], seg=20)
    lo_pts = [(0, -0.47, 1.000), (0, -0.56, 0.992), (0, -0.63, 0.986), (0, -0.675, 0.986)]
    lo_r = [(0.100, 0.036), (0.082, 0.031), (0.058, 0.025), (0.034, 0.018)]
    loft('MSC_BillLow', c, lo_pts, lo_r, M['beak'], seg=16)
    for s, side in ((1, 'L'), (-1, 'R')):
        blob('MSC_Nostril.' + side, c, (s * 0.032, -0.61, 1.083), (0.006, 0.020, 0.004), M['nostril'], seg=8, rings=4)

    # --- captain's cap
    hat = []
    hat.append(loft('MSC_HatBand', c, [(0, 0, 1.462), (0, 0, 1.512), (0, 0, 1.560)],
                    [(0.372, 0.360), (0.378, 0.366), (0.384, 0.372)], M['navy'], up=(0, 1, 0), seg=56, round_ends=False))
    hat.append(loft('MSC_HatWall', c, [(0, 0.004, 1.556), (0, 0.010, 1.600), (0, 0.016, 1.632)],
                    [(0.386, 0.374), (0.432, 0.414), (0.458, 0.438)], M['cap'], up=(0, 1, 0), seg=56, round_ends=False))
    hat.append(blob('MSC_HatTop', c, (0, 0.018, 1.640), (0.462, 0.442, 0.070), M['cap'], seg=56, rings=16,
                    deform=lambda u: Vector((0, 0, 0.035 * max(0.0, -u.y) * max(0.0, u.z)))))
    # glossy visor: polar shell in front of the band
    vb = bmesh.new()
    cols, rws, th = 24, 6, 0.014
    grid_top, grid_bot = [], []
    for i in range(rws + 1):
        rt, rb = [], []
        for j in range(cols + 1):
            ang = math.radians(-78 + 156 * j / cols)
            reach = 0.17 * max(0.0, math.cos(ang)) ** 0.8
            r = 0.372 + reach * i / rws
            x, y = r * math.sin(ang), -r * math.cos(ang)
            z = 1.478 - 0.30 * (r - 0.372) - 0.6 * (r - 0.372) ** 2
            rt.append(vb.verts.new((x * 1.0, y * 0.97, z)))
            rb.append(vb.verts.new((x * 1.0, y * 0.97, z - th)))
        grid_top.append(rt)
        grid_bot.append(rb)
    for i in range(rws):
        for j in range(cols):
            vb.faces.new((grid_top[i][j], grid_top[i][j + 1], grid_top[i + 1][j + 1], grid_top[i + 1][j]))
            vb.faces.new((grid_bot[i][j], grid_bot[i + 1][j], grid_bot[i + 1][j + 1], grid_bot[i][j + 1]))
    for j in range(cols):
        vb.faces.new((grid_top[rws][j], grid_top[rws][j + 1], grid_bot[rws][j + 1], grid_bot[rws][j]))
        vb.faces.new((grid_top[0][j + 1], grid_top[0][j], grid_bot[0][j], grid_bot[0][j + 1]))
    for i in range(rws):
        vb.faces.new((grid_top[i][0], grid_top[i + 1][0], grid_bot[i + 1][0], grid_bot[i][0]))
        vb.faces.new((grid_top[i + 1][cols], grid_top[i][cols], grid_bot[i][cols], grid_bot[i + 1][cols]))
    bmesh.ops.recalc_face_normals(vb, faces=vb.faces[:])
    hat.append(_new_obj('MSC_Visor', vb, c, M['visor']))
    # gold chin cords between two side buttons, and the buttons
    for k, z in enumerate((1.505, 1.523)):
        pts = []
        for j in range(17):
            ang = math.radians(-70 + 140 * j / 16)
            sag = 0.010 * math.cos(math.radians(90 * (j - 8) / 8)) if k == 0 else 0.006 * math.cos(math.radians(90 * (j - 8) / 8))
            pts.append((0.392 * math.sin(ang), -0.38 * math.cos(ang), z - sag))
        hat.append(loft('MSC_Cord%d' % k, c, pts, [(0.0075, 0.0075)] * len(pts), M['gold'], seg=8))
    for s, side in ((1, 'L'), (-1, 'R')):
        ang = math.radians(s * 72)
        hat.append(blob('MSC_Button.' + side, c, (0.40 * math.sin(ang), -0.39 * math.cos(ang), 1.515), (0.018, 0.018, 0.018), M['gold'], seg=12, rings=6))
    # badge: navy oval backing, gold anchor and laurel, built flat at the origin facing -Y and
    # then laid onto the flaring crown wall (it leans out about 40 degrees)
    badge = []
    bz, by = 0.0, 0.0
    badge.append(blob('MSC_BadgeBack', c, (0, by + 0.004, bz), (0.078, 0.010, 0.058), M['navy'], seg=24, rings=8))
    gy = by - 0.008
    badge.append(loft('MSC_AnchorShank', c, [(0, gy, bz + 0.040), (0, gy, bz - 0.036)], [(0.0055, 0.0055)] * 2, M['gold'], seg=8))
    ring_pts = [(0.011 * math.sin(math.radians(a)), gy, bz + 0.050 + 0.011 * math.cos(math.radians(a))) for a in range(0, 360, 30)]
    badge.append(loft('MSC_AnchorRing', c, ring_pts, [(0.004, 0.004)] * len(ring_pts), M['gold'], up=(0, 1, 0), seg=6, closed=True, round_ends=False))
    badge.append(loft('MSC_AnchorStock', c, [(-0.024, gy, bz + 0.026), (0.024, gy, bz + 0.026)], [(0.0045, 0.0045)] * 2, M['gold'], seg=8))
    arm_pts = [(0.034 * math.sin(math.radians(a)), gy, bz - 0.006 - 0.032 * math.cos(math.radians(a))) for a in range(-80, 81, 20)]
    badge.append(loft('MSC_AnchorArms', c, arm_pts, [(0.005, 0.005)] * len(arm_pts), M['gold'], up=(0, 1, 0), seg=8))
    for s, side in ((1, 'L'), (-1, 'R')):
        badge.append(blob('MSC_Fluke.' + side, c, (s * 0.034, gy, bz - 0.004), (0.009, 0.004, 0.011), M['gold'], seg=8, rings=4,
                          rot=Quaternion((0, 1, 0), math.radians(-s * 35))))
        # laurel: five leaves on an arc rising from under the anchor round each side
        for k in range(5):
            th = math.radians(-75 + 24 * k)
            lx, lz = s * 0.056 * math.cos(th), bz + 0.004 + 0.050 * math.sin(th)
            phi = math.atan2(-s * math.sin(th), math.cos(th))
            badge.append(blob('MSC_Leaf%d.%s' % (k, side), c, (lx, gy, lz), (0.0065, 0.003, 0.013), M['gold'], seg=8, rings=4,
                              rot=Quaternion((0, 1, 0), phi)))
    # lay the badge onto the front of the crown wall (normal forward-down, about 40 degrees)
    place = Matrix.Translation((0, -0.401, 1.596)) @ Matrix.Rotation(math.radians(40), 4, 'X') @ Matrix.Scale(0.75, 4)
    for o in badge:
        o.data.transform(place)
    hat.extend(badge)
    # a few white feathers peeking out under the back of the cap
    for k in range(3):
        x = (k - 1) * 0.07
        feather('MSC_Crest%d' % k, c, (x, 0.24, 1.45), (x * 1.6, 0.47, 1.50 + 0.02 * (1 - abs(k - 1))), 0.07, M['tail'],
                normal=(0, 0.3, 1), thick=0.02, seg=8, bend=-0.015)
    # set the cap back and a little to one side, around the band
    pivot = Vector((0, 0, 1.47))
    tilt = (Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-6), 4, 'Y') @ Matrix.Rotation(math.radians(-5), 4, 'X')
            @ Matrix.Translation(-pivot))
    for o in hat:
        o.data.transform(tilt)

    # --- neckerchief: ribbon round the neck, knot, two tails, triangle flap on the back
    ring_pts, zc = [], 0.838
    uz = (zc - BODY_C.z) / 0.53
    for a in range(0, 360, 10):
        ang = math.radians(a)
        u = Vector((math.sin(ang), -math.cos(ang), 0))
        u = (u * math.sqrt(max(0.0, 1 - uz * uz)) + Vector((0, 0, uz))).normalized()
        p = surf(u)
        ring_pts.append(p + (p - Vector((0, 0, p.z))).normalized() * 0.014)
    loft('MSC_Scarf', c, ring_pts, [(0.012, 0.030)] * len(ring_pts), M['scarf'], up=(0, 0, 1), seg=10, closed=True, round_ends=False)
    blob('MSC_Knot', c, (0, -0.538, 0.836), (0.062, 0.042, 0.052), M['scarf'], seg=16, rings=8)
    def chest(x, z, off):
        uz_ = (z - BODY_C.z) / 0.53
        ux_ = x / 0.56
        u_ = Vector((ux_, -math.sqrt(max(0.0, 1 - ux_ * ux_ - uz_ * uz_)), uz_)).normalized()
        return surf(u_) + surf_normal(u_) * off
    for s, side in ((1, 'L'), (-1, 'R')):
        tail_pts = [chest(s * (0.020 + 0.068 * t), 0.818 - 0.125 * t, 0.024 - 0.006 * t) for t in (0.0, 0.33, 0.66, 1.0)]
        loft('MSC_ScarfTail.' + side, c, tail_pts, [(0.030, 0.010), (0.037, 0.010), (0.044, 0.009), (0.050, 0.008)],
             M['scarf'], up=(0, -1, 0.3), seg=8)

    # --- tail: five white feathers fanned behind
    for k in range(5):
        x = (k - 2) * 0.055
        root = Vector((x * 0.6, 0.36, 0.80))
        tip = Vector((x * 1.9, 0.70, 0.68 + 0.012 * abs(k - 2)))
        feather('MSC_Tail%d' % k, c, root, tip, 0.11, M['tail'], normal=(0, 0.3, 1), thick=0.022, seg=10, bend=-0.02, round_tip=True)

    # --- wing-arms: feathered upper arm and forearm, trailing feathers, wingtip mitten
    for s, side in ((1, 'L'), (-1, 'R')):
        sh, el, wr = Vector((s * 0.47, 0.02, 0.852)), Vector((s * 0.649, 0.014, 0.727)), Vector((s * 0.760, 0.0, 0.647))
        loft('MSC_UpperArm.' + side, c, [sh, sh.lerp(el, 0.5), el], [(0.092, 0.074), (0.084, 0.068), (0.074, 0.060)], M['feather'], up=(0, 1, 0), seg=16)
        loft('MSC_Forearm.' + side, c, [el, el.lerp(wr, 0.5), wr], [(0.074, 0.060), (0.069, 0.056), (0.064, 0.052)], M['feather'], up=(0, 1, 0), seg=16)
        for k in range(5):
            a = sh.lerp(wr, 0.14 + 0.19 * k)
            feather('MSC_Trail%d.%s' % (k, side), c, a + Vector((0, 0.035, 0.01)), a + Vector((s * 0.02, 0.075, -0.085)), 0.098,
                    M['feather'], normal=(s * 0.8, 0, 0.6), thick=0.016, seg=8, round_tip=True)
        d = (Vector((s * 0.866, 0, 0.572)) - el).normalized()
        palm = Vector((s * 0.852, 0.0, 0.584))
        blob('MSC_Hand.' + side, c, palm, (0.090, 0.070, 0.088), M['feather'], seg=20, rings=10)
        # wingtip: four broad rounded feathers fanned like a mitten, black tips with a white spot
        for k, deg in enumerate((-42, -15, 12, 39)):
            dd = Quaternion((0, 1, 0), math.radians(-s * deg)) @ d
            root = palm + dd * 0.02
            tip = palm + dd * (0.225 - 0.018 * abs(k - 1.5))
            feather('MSC_Primary%d.%s' % (k, side), c, root, tip, 0.092, M['feather'], normal=(0, -1, 0), thick=0.030, seg=10, round_tip=True)
            # the outer third of each feather is black: a slightly fuller feather over the end
            feather('MSC_PrimaryTip%d.%s' % (k, side), c, root.lerp(tip, 0.55), tip + dd * 0.006, 0.094, M['tip'], normal=(0, -1, 0), thick=0.034, seg=10, round_tip=True)
            blob('MSC_Mirror%d.%s' % (k, side), c, root.lerp(tip, 0.80) + Vector((0, -0.018, 0)), (0.012, 0.004, 0.012), M['spot'], seg=8, rings=4)

    # --- legs and webbed feet
    for s, side in ((1, 'L'), (-1, 'R')):
        hip, knee, ankle = Vector((s * 0.186, 0.004, 0.600)), Vector((s * 0.186, -0.014, 0.384)), Vector((s * 0.186, 0.011, 0.150))
        loft('MSC_Thigh.' + side, c, [hip, hip.lerp(knee, 0.5), knee], [(0.064, 0.064), (0.058, 0.058), (0.054, 0.054)], M['leg'], seg=14)
        loft('MSC_Shin.' + side, c, [knee, knee.lerp(ankle, 0.5), ankle], [(0.054, 0.054), (0.047, 0.047), (0.046, 0.046)], M['leg'], seg=14)
        # fluffy white feathered thigh just under the body
        blob('MSC_ThighFluff.' + side, c, Vector((s * 0.190, 0.0, 0.520)), (0.098, 0.094, 0.090), M['tail'], seg=20, rings=10,
             deform=lambda u: Vector((0, 0, -0.018 * max(0.0, -u.z))))
        heel = Vector((s * 0.186, 0.0, 0.055))
        blob('MSC_Ankle.' + side, c, heel + Vector((0, 0, 0.016)), (0.066, 0.072, 0.064), M['leg'], seg=16, rings=8)
        blob('MSC_FootPad.' + side, c, Vector((s * 0.186, -0.07, 0.030)), (0.100, 0.120, 0.028), M['leg'], seg=16, rings=8)
        tips = []
        for k, deg in enumerate((-30, 0, 30)):
            a = math.radians(deg * s)
            root = Vector((s * 0.186, -0.06, 0.034))
            tip = root + Vector((math.sin(a) * 0.215, -math.cos(a) * 0.215, -0.012))
            tips.append(tip)
            loft('MSC_Toe%d.%s' % (k, side), c, [root, root.lerp(tip, 0.55) + Vector((0, 0, 0.010)), tip],
                 [(0.038, 0.030), (0.031, 0.025), (0.021, 0.018)], M['leg'], seg=10)
            blob('MSC_Claw%d.%s' % (k, side), c, tip + (tip - root).normalized() * 0.014 + Vector((0, 0, -0.004)),
                 (0.010, 0.016, 0.008), M['claw'], seg=8, rings=4, rot=Quaternion((0, 0, 1), -a))
        wb = bmesh.new()
        base = Vector((s * 0.186, -0.06, 0.024))
        for k in range(2):
            a0, a1 = tips[k], tips[k + 1]
            pts = [base, base.lerp(a0, 0.82), base.lerp(a0, 0.82).lerp(base.lerp(a1, 0.82), 0.5) + (a0 + a1 - base * 2).normalized() * 0.01, base.lerp(a1, 0.82)]
            top = [wb.verts.new(p + Vector((0, 0, 0.004))) for p in pts]
            bot = [wb.verts.new(p - Vector((0, 0, 0.004))) for p in pts]
            wb.faces.new(top)
            wb.faces.new(list(reversed(bot)))
            for i in range(4):
                wb.faces.new((top[i], bot[i], bot[(i + 1) % 4], top[(i + 1) % 4]))
        bmesh.ops.recalc_face_normals(wb, faces=wb.faces[:])
        _new_obj('MSC_Web.' + side, wb, c, M['leg'])
    return {'parts': len(c.objects)}


# ----------------------------------------------------------------------------- skinning

def bones_for(name):
    """Rigid limb weights by part name; None = body (height blend)."""
    base, _, side = name.partition('.')
    table = (
        (('MSC_UpperArm',), 'DEF-upper_arm'),
        (('MSC_Forearm', 'MSC_Trail'), 'DEF-forearm'),
        (('MSC_Hand', 'MSC_Primary', 'MSC_Mirror', 'MSC_Covert'), 'DEF-hand'),
        (('MSC_Thigh', 'MSC_ThighFluff'), 'DEF-thigh'),
        (('MSC_Shin',), 'DEF-shin'),
        (('MSC_Ankle', 'MSC_FootPad'), 'DEF-foot'),
        (('MSC_Toe', 'MSC_Claw', 'MSC_Web'), 'DEF-toe'),
    )
    if side in ('L', 'R'):
        for prefixes, bone in table:
            if base.startswith(prefixes):
                return {bone + '.' + side: 1.0}
    return None


def build_skin():
    rig = bpy.data.objects['Rig']
    src = bpy.data.collections[PARTS]
    final = coll(FINAL)
    if rig.name not in final.objects:
        final.objects.link(rig)
    old = bpy.data.objects.get('HERO_Mascot')
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    names = [b.name for b in rig.data.bones]
    index = {n: i for i, n in enumerate(names)}
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    uv_out = bm.loops.layers.uv.new('UVMap')
    mats = []
    for o in sorted(src.objects, key=lambda x: x.name):
        if o.type != 'MESH':
            continue
        fixed = bones_for(o.name)
        tmp = bmesh.new()
        tmp.from_mesh(o.data)
        tmp.transform(o.matrix_world)
        uv_in = tmp.loops.layers.uv.get('UVMap')
        remap = []
        for m in o.data.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        made = {}
        for v in tmp.verts:
            nv = bm.verts.new(v.co)
            if fixed:
                for g, w in fixed.items():
                    nv[deform][index[g]] = w
            else:
                t = min(1.0, max(0.0, (v.co.z - 0.74) / 0.14))
                t = t * t * (3 - 2 * t)
                if t > 0:
                    nv[deform][index['DEF-head']] = t
                if t < 1:
                    nv[deform][index['DEF-hips']] = 1 - t
            made[v] = nv
        for f in tmp.faces:
            try:
                nf = bm.faces.new([made[v] for v in f.verts])
            except ValueError:
                continue
            nf.smooth = f.smooth
            nf.material_index = remap[f.material_index] if remap else 0
            if uv_in is not None:
                for lo, li in zip(nf.loops, f.loops):
                    lo[uv_out].uv = li[uv_in].uv
        tmp.free()
    me = bpy.data.meshes.new('HERO_Mascot')
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new('HERO_Mascot', me)
    final.objects.link(ob)
    for n in names:
        ob.vertex_groups.new(name=n)
    ob.parent = rig
    ob.matrix_parent_inverse = rig.matrix_world.inverted()
    ob.modifiers.new('Armature', 'ARMATURE').object = rig
    unweighted = sum(1 for v in me.vertices if abs(sum(g.weight for g in v.groups) - 1.0) > 0.02)
    return {'verts': len(me.vertices), 'tris': sum(len(p.vertices) - 2 for p in me.polygons),
            'materials': len(mats), 'unweighted': unweighted}


# ----------------------------------------------------------------------------- bake

def _view3d_override():
    win = bpy.context.window
    for area in win.screen.areas:
        if area.type == 'VIEW_3D':
            region = next(r for r in area.regions if r.type == 'WINDOW')
            return {'window': win, 'area': area, 'region': region}
    raise RuntimeError('no 3D viewport')


def build_uv():
    ob = bpy.data.objects['HERO_Mascot']
    me = ob.data
    layer = me.uv_layers.get('UVBake') or me.uv_layers.new(name='UVBake')
    me.uv_layers.active = layer
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.hide_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    with bpy.context.temp_override(**_view3d_override(), active_object=ob, object=ob, selected_objects=[ob]):
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0, scale_to_bounds=True)
        bpy.ops.object.mode_set(mode='OBJECT')
    return {'uv_layers': [u.name for u in me.uv_layers], 'active': me.uv_layers.active.name}


def _bake_image(name):
    img = bpy.data.images.get(name)
    if img is None or tuple(img.size) != (TEXTURE_SIZE, TEXTURE_SIZE):
        if img is not None:
            bpy.data.images.remove(img)
        img = bpy.data.images.new(name, TEXTURE_SIZE, TEXTURE_SIZE, alpha=False, float_buffer=True)
    return img


def build_bake():
    import numpy as np
    ob = bpy.data.objects['HERO_Mascot']
    me = ob.data
    me.uv_layers.active = me.uv_layers['UVBake']
    scn = bpy.context.scene
    prev_engine = scn.render.engine
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = 64
    scn.cycles.use_denoising = False
    scn.render.bake.margin = 8
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    results = {}
    for kind, img_name in (('DIFFUSE', 'MSC_BakeColor'), ('AO', 'MSC_BakeAO')):
        img = _bake_image(img_name)
        for m in me.materials:
            nt = m.node_tree
            node = nt.nodes.get('BAKE_TARGET') or nt.nodes.new('ShaderNodeTexImage')
            node.name = 'BAKE_TARGET'
            node.image = img
            node.interpolation = 'Linear'
            for n in nt.nodes:
                n.select = False
            node.select = True
            nt.nodes.active = node
        if kind == 'DIFFUSE':
            bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, use_clear=True, margin=8)
        else:
            bpy.ops.object.bake(type='AO', use_clear=True, margin=8)
        results[kind] = img
    # colour x softened occlusion -> sRGB PNG
    col = np.array(results['DIFFUSE'].pixels[:], dtype=np.float32).reshape(-1, 4)
    ao = np.array(results['AO'].pixels[:], dtype=np.float32).reshape(-1, 4)[:, :1]
    shade = 0.42 + 0.58 * np.clip(ao, 0.0, 1.0) ** 0.8
    lin = np.clip(col[:, :3] * shade, 0.0, 1.0)
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
    out = bpy.data.images.get('MSC_Albedo')
    if out is not None:
        bpy.data.images.remove(out)
    out = bpy.data.images.new('MSC_Albedo', TEXTURE_SIZE, TEXTURE_SIZE, alpha=False)
    out.pixels.foreach_set(np.concatenate([srgb, np.ones((srgb.shape[0], 1), dtype=np.float32)], axis=1).ravel())
    out.filepath_raw = TEXTURE
    out.file_format = 'PNG'
    out.save()
    out.filepath = TEXTURE
    # two final materials reading the baked texture
    def final_mat(name, rough, metal):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        for n in list(nt.nodes):
            if n.type not in ('OUTPUT_MATERIAL', 'BSDF_PRINCIPLED'):
                nt.nodes.remove(n)
        b = _principled(m)
        b.inputs['Roughness'].default_value = rough
        b.inputs['Metallic'].default_value = metal
        uvn = nt.nodes.new('ShaderNodeUVMap')
        uvn.uv_map = 'UVBake'
        tx = nt.nodes.new('ShaderNodeTexImage')
        tx.image = out
        nt.links.new(uvn.outputs['UV'], tx.inputs['Vector'])
        nt.links.new(tx.outputs['Color'], b.inputs['Base Color'])
        return m
    matte = final_mat('MSC_Matte', 0.62, 0.0)
    gloss = final_mat('MSC_Gloss', 0.18, 0.0)
    gloss_index = [i for i, m in enumerate(me.materials) if m.name.startswith(GLOSS)]
    for p in me.polygons:
        p.material_index = 1 if p.material_index in gloss_index else 0
    me.materials.clear()
    me.materials.append(matte)
    me.materials.append(gloss)
    # the bake layout is the only UV the game needs
    for uvl in list(me.uv_layers):
        if uvl.name != 'UVBake':
            me.uv_layers.remove(uvl)
    scn.render.engine = prev_engine
    return {'texture': TEXTURE, 'gloss_faces': sum(1 for p in me.polygons if p.material_index == 1)}


def export_glb():
    rig = bpy.data.objects['Rig']
    hero = bpy.data.objects['HERO_Mascot']
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in (rig, hero):
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    path = ASSET + '/mascot_model.glb'
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_skins=True,
                              export_animations=False, export_morph=False, export_apply=False,
                              export_yup=True, export_cameras=False, export_lights=False,
                              export_image_format='AUTO')
    return {'glb': path, 'bytes': os.path.getsize(path)}


STAGES = {'parts': build_parts, 'skin': build_skin, 'uv': build_uv, 'bake': build_bake, 'export': export_glb}
if STAGE not in STAGES:
    raise ValueError('unknown mascot_stage ' + STAGE)
result = STAGES[STAGE]()

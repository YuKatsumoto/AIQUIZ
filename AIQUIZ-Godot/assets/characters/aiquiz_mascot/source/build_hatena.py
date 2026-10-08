"""ハテナ (the AIQUIZ quiz spirit) — high-quality parts on the 16-bone mascot rig.

The round body is the dot of an orange "?". Refined from the CONCEPT_A_Hatena blockout, at
the rig's rest proportions (bone heads read from 'Rig'): shoulder (±0.52, 0, 0.819), elbow
(±0.649, 0.014, 0.727), wrist (±0.76, 0, 0.647), thigh head (±0.186, 0.006, 0.536),
knee z 0.384, ankle (±0.186, 0.011, 0.178), toe from y -0.175.

Run inside the live Blender (Higgsfield bridge) with aiquiz_mascot.blend open:

    exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/build_hatena.py',
              encoding='utf-8').read(), {})

Rebuilds the collection HATENA_Parts (nothing else is touched): one object per part named
H_<Part>[.L|.R], which fit_hatena.py weights by part and joins into HERO_Mascot.
  body     an ellipsoid (a spherified cube, even quads) — the face parts are built on its
           analytic surface so they sit on it exactly
  face     domed glossy eyes with two highlights, a tube smile (no blush)
  crest    "?" as a slightly flattened stroke with a ball terminal and a collar ring
  arms     shoulder ball, tapered capsules, elbow ball, mitten hand with a thumb
  legs     hip ball, capsules, knee ball, sneaker (navy upper, white sole, white cuff)
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

COLL = 'HATENA_Parts'
C = Vector((0.0, 0.0, 1.03))          # body centre
R = Vector((0.56, 0.48, 0.55))        # body radii
SHARP = math.radians(40)

MATS = {  # name: (linear base colour, roughness, extra)
    'Hatena_Body': ((0.93, 0.91, 0.85), 0.48, {'Subsurface Weight': 0.08, 'Coat Weight': 0.0}),
    'Hatena_Orange': ((1.0, 0.42, 0.05), 0.32, {'Coat Weight': 0.25, 'Coat Roughness': 0.15}),
    'Hatena_Shoe': ((0.045, 0.075, 0.21), 0.5, {}),
    'Hatena_Sole': ((0.88, 0.88, 0.86), 0.55, {}),
    'Hatena_Eye': ((0.012, 0.012, 0.018), 0.1, {'Coat Weight': 0.6, 'Coat Roughness': 0.05}),
    'Hatena_Highlight': ((1.0, 1.0, 1.0), 0.25, {}),
    'Hatena_Cheek': ((1.0, 0.42, 0.47), 0.7, {}),
    'Hatena_Mouth': ((0.09, 0.025, 0.02), 0.35, {}),
}


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def material(name):
    col, rough, extra = MATS[name]
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*col, 1.0)
    bsdf.inputs['Roughness'].default_value = rough
    for k, v in extra.items():
        if k in bsdf.inputs:
            bsdf.inputs[k].default_value = v
    m.diffuse_color = (*col, 1.0)
    return m


def coll():
    c = bpy.data.collections.get(COLL)
    if c is None:
        c = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(c)
    for o in list(c.objects):
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)
    return c


def finish(bm, name, mat, c):
    """bmesh -> object: smooth shading, hard edges over SHARP."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > SHARP:
            e.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material(mat))
    ob = bpy.data.objects.new(name, me)
    c.objects.link(ob)
    return ob


# ---------------------------------------------------------------- body surface

def surf(d):
    """Point on the body ellipsoid in direction d from the centre."""
    d = Vector(d).normalized()
    k = 1.0 / math.sqrt((d.x / R.x) ** 2 + (d.y / R.y) ** 2 + (d.z / R.z) ** 2)
    return C + d * k


def surf_normal(p):
    q = p - C
    return Vector((q.x / R.x ** 2, q.y / R.y ** 2, q.z / R.z ** 2)).normalized()


def frame_at(p):
    n = surf_normal(p)
    t = Vector((0, 0, 1)).cross(n).normalized()
    return n, t, n.cross(t)


def body(c):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=20, use_grid_fill=True)
    for v in bm.verts:
        v.co = surf(v.co)
    return finish(bm, 'H_Body', 'Hatena_Body', c)


def decal(c, name, mat, centre_dir, ru, rv, rot=0.0, dome=0.006, base=0.0015, under=None, rings=10, seg=40):
    """An oval lens lying on the body (or, with under=(centre, ru, rv, dome, base, axes), on
    another decal): domed top, a short skirt sunk under the surface so no gap shows."""
    s = surf(centre_dir)
    n0, t0, b0 = frame_at(s)
    cr, sr = math.cos(rot), math.sin(rot)

    def place(u, v, lift):
        q = s + t0 * (u * cr - v * sr) + b0 * (u * sr + v * cr)
        p = surf(q - C)
        off = lift
        if under is not None:
            uc, uru, urv, udome, ubase, (ut, ub) = under
            du, dv = (p - uc).dot(ut) / uru, (p - uc).dot(ub) / urv
            off += ubase + udome * math.sqrt(max(0.0, 1.0 - du * du - dv * dv))
        return p + surf_normal(p) * off

    bm = bmesh.new()
    top = bm.verts.new(place(0, 0, base + dome))
    prev = None
    ring_list = []
    for i in range(1, rings + 1):
        r = i / rings
        h = base + dome * math.sqrt(max(0.0, 1.0 - r * r))
        ring_list.append([bm.verts.new(place(ru * r * math.cos(2 * math.pi * k / seg),
                                             rv * r * math.sin(2 * math.pi * k / seg), h)) for k in range(seg)])
    skirt = [bm.verts.new(place(ru * math.cos(2 * math.pi * k / seg), rv * math.sin(2 * math.pi * k / seg), -0.004))
             for k in range(seg)]
    bottom = bm.verts.new(place(0, 0, -0.004))
    for k in range(seg):
        k2 = (k + 1) % seg
        bm.faces.new((top, ring_list[0][k], ring_list[0][k2]))
        for i in range(rings - 1):
            a, b = ring_list[i], ring_list[i + 1]
            bm.faces.new((a[k], b[k], b[k2], a[k2]))
        bm.faces.new((ring_list[-1][k], skirt[k], skirt[k2], ring_list[-1][k2]))
        bm.faces.new((skirt[k2], skirt[k], bottom))
    ob = finish(bm, name, mat, c)
    return ob, (s, ru, rv, dome, base, (t0 * cr + b0 * sr, -t0 * sr + b0 * cr))


# ---------------------------------------------------------------- tubes and capsules

def frames_along(path):
    """Parallel-transport frames (tangent, normal, binormal) along a polyline."""
    tans = []
    for i in range(len(path)):
        a = path[max(0, i - 1)]
        b = path[min(len(path) - 1, i + 1)]
        tans.append((b - a).normalized())
    ref = Vector((0, 1, 0)) if abs(tans[0].y) < 0.9 else Vector((1, 0, 0))
    n = tans[0].cross(ref).normalized()
    out = []
    for t in tans:
        n = (n - t * n.dot(t)).normalized()
        out.append((t, n, t.cross(n)))
    return out


def tube(c, name, mat, path, rx, ry=None, rx_end=None, seg=24, cap0=True, cap1=True, cap_rings=6):
    """A swept elliptical tube (rx along the in-plane normal, ry along the binormal) with
    hemispherical end caps; rx tapers linearly to rx_end."""
    ry = ry or rx
    rx_end = rx_end or rx
    fr = frames_along(path)
    bm = bmesh.new()
    rings = []

    def ring(p, t, n, b, sx, sy):
        return [bm.verts.new(p + n * (sx * math.cos(2 * math.pi * k / seg)) + b * (sy * math.sin(2 * math.pi * k / seg)))
                for k in range(seg)]

    last = len(path) - 1
    scale = lambda i: (rx + (rx_end - rx) * i / max(1, last)) / rx
    pole0 = pole1 = None
    if cap0:
        t, n, b = fr[0]
        s0 = scale(0)
        for j in range(cap_rings - 1, 0, -1):
            a = (math.pi / 2) * j / cap_rings
            rings.append(ring(path[0] - t * (math.sin(a) * rx * s0), t, n, b, rx * s0 * math.cos(a), ry * s0 * math.cos(a)))
        pole0 = path[0] - t * (rx * s0)
    for i, p in enumerate(path):
        t, n, b = fr[i]
        rings.append(ring(p, t, n, b, rx * scale(i), ry * scale(i)))
    if cap1:
        t, n, b = fr[-1]
        s1 = scale(last)
        for j in range(1, cap_rings):
            a = (math.pi / 2) * j / cap_rings
            rings.append(ring(path[-1] + t * (math.sin(a) * rx * s1), t, n, b, rx * s1 * math.cos(a), ry * s1 * math.cos(a)))
        pole1 = path[-1] + t * (rx * s1)
    for i in range(len(rings) - 1):
        a, b2 = rings[i], rings[i + 1]
        for k in range(seg):
            k2 = (k + 1) % seg
            bm.faces.new((a[k], a[k2], b2[k2], b2[k]))
    # close each end on its pole (round cap) or on the ring centre (flat cap)
    for r, pole, flip in ((rings[0], pole0, True), (rings[-1], pole1, False)):
        ctr = bm.verts.new(pole if pole is not None else sum((v.co for v in r), Vector()) / len(r))
        for k in range(seg):
            k2 = (k + 1) % seg
            bm.faces.new((r[k2], r[k], ctr) if flip else (r[k], r[k2], ctr))
    return finish(bm, name, mat, c)


def capsule(c, name, mat, p0, p1, r0, r1=None, seg=24):
    p0, p1 = Vector(p0), Vector(p1)
    steps = 4
    path = [p0.lerp(p1, i / steps) for i in range(steps + 1)]
    return tube(c, name, mat, path, r0, r0, r1 or r0, seg=seg)


def ball(c, name, mat, centre, radii, seg=32, rings=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    rx, ry, rz = radii if isinstance(radii, (tuple, list)) else (radii, radii, radii)
    for v in bm.verts:
        v.co = Vector((v.co.x * rx, v.co.y * ry, v.co.z * rz)) + Vector(centre)
    return finish(bm, name, mat, c)


def torus(c, name, mat, centre, major, minor, seg=40, sides=12):
    bm = bmesh.new()
    verts = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(sides):
            b = 2 * math.pi * j / sides
            r = major + minor * math.cos(b)
            row.append(bm.verts.new(Vector(centre) + Vector((r * math.cos(a), r * math.sin(a), minor * math.sin(b)))))
        verts.append(row)
    for i in range(seg):
        for j in range(sides):
            a, b = verts[i], verts[(i + 1) % seg]
            bm.faces.new((a[j], b[j], b[(j + 1) % sides], a[(j + 1) % sides]))
    return finish(bm, name, mat, c)


def superbox(c, name, mat, centre, half, exps=(3.0, 3.0, 3.0), cuts=10, shape=None):
    """Rounded box: a subdivided cube pushed onto a superellipsoid."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    for v in bm.verts:
        d = v.co.normalized()
        p = Vector([math.copysign(abs(d[i]) ** (2.0 / exps[i]), d[i]) * half[i] for i in range(3)])
        # normalise onto the superellipsoid |x/a|^e + ... = 1
        f = sum(abs(p[i] / half[i]) ** exps[i] for i in range(3)) ** (-1.0 / 3.0)
        p = p * f
        if shape:
            p = shape(p)
        v.co = p + Vector(centre)
    return finish(bm, name, mat, c)


# ---------------------------------------------------------------- build

def build():
    c = coll()
    body(c)

    # face
    for s, side in ((1, 'L'), (-1, 'R')):
        eye, eye_frame = decal(c, 'H_Eye.' + side, 'Hatena_Eye', (s * 0.17, -0.445, 0.075), 0.06, 0.09,
                               dome=0.013, base=0.0012, rings=12, seg=48)
        s_e, ru, rv, dome, base, axes = eye_frame
        under = (s_e, ru, rv, dome, base, axes)
        # big highlight upper right, small one lower left (one light for both eyes)
        hp = s_e + axes[0] * 0.019 + axes[1] * 0.037
        decal(c, 'H_EyeHi.' + side, 'Hatena_Highlight', hp - C, 0.019, 0.024, dome=0.002, base=0.0008, under=under,
              rings=5, seg=24)
        hp2 = s_e + axes[0] * (-0.021) + axes[1] * (-0.038)
        decal(c, 'H_EyeHi2.' + side, 'Hatena_Highlight', hp2 - C, 0.009, 0.009, dome=0.0015, base=0.0008, under=under,
              rings=4, seg=16)

    # smile: a tube on the surface
    m0 = surf((0, -1.0, -0.06))
    n0, t0, b0 = frame_at(m0)
    path = []
    for i in range(17):
        u = -0.066 + 0.132 * i / 16
        v = 0.03 * (u / 0.066) ** 2 - 0.03
        p = surf(m0 + t0 * u + b0 * v - C)
        path.append(p + surf_normal(p) * 0.003)
    tube(c, 'H_Mouth', 'Hatena_Mouth', path, 0.0115, seg=12, cap_rings=4)

    # "?" crest in the x/z plane, read from the front: stem up out of the body, round the right,
    # over the top, ending lower left in a ball terminal
    cx, cz, r = 0.0, 1.835, 0.135
    p0 = Vector((0.0, 0.0, 1.50))
    a_join = math.radians(-40)
    p3 = Vector((cx + r * math.cos(a_join), 0.0, cz + r * math.sin(a_join)))
    tan3 = Vector((-math.sin(a_join), 0.0, math.cos(a_join)))
    p1 = p0 + Vector((0, 0, 0.09))
    p2 = p3 - tan3 * 0.07
    path = []
    for i in range(14):
        t = i / 14
        path.append(p0 * (1 - t) ** 3 + p1 * 3 * (1 - t) ** 2 * t + p2 * 3 * (1 - t) * t * t + p3 * t ** 3)
    a_end = math.radians(212)
    steps = 40
    for i in range(steps + 1):
        a = a_join + (a_end - a_join) * i / steps
        path.append(Vector((cx + r * math.cos(a), 0.0, cz + r * math.sin(a))))
    tube(c, 'H_Crest', 'Hatena_Orange', path, 0.067, 0.054, seg=28, cap0=False, cap1=True)
    end = path[-1]
    ball(c, 'H_CrestBall', 'Hatena_Orange', (end.x - 0.012, 0.0, end.z - 0.018), (0.082, 0.07, 0.082))
    torus(c, 'H_CrestCollar', 'Hatena_Orange', (0.0, 0.0, C.z + R.z - 0.008), 0.086, 0.024)

    # arms
    for s, side in ((1, 'L'), (-1, 'R')):
        sh = Vector((s * 0.52, 0.0, 0.819))
        el = Vector((s * 0.649, 0.014, 0.727))
        wr = Vector((s * 0.76, 0.0, 0.647))
        ball(c, 'H_Shoulder.' + side, 'Hatena_Orange', sh, 0.068, seg=24, rings=12)
        capsule(c, 'H_UpperArm.' + side, 'Hatena_Orange', sh, el, 0.056, 0.05)
        ball(c, 'H_Elbow.' + side, 'Hatena_Orange', el, 0.0505, seg=24, rings=12)
        capsule(c, 'H_Forearm.' + side, 'Hatena_Orange', el, wr, 0.05, 0.047)
        hand = Vector((s * 0.858, -0.004, 0.578))
        ball(c, 'H_Hand.' + side, 'Hatena_Orange', hand, (0.118, 0.105, 0.118))
        capsule(c, 'H_Thumb.' + side, 'Hatena_Orange', hand + Vector((-s * 0.03, -0.035, 0.03)),
                hand + Vector((-s * 0.075, -0.1, 0.105)), 0.05, 0.046, seg=20)

    # legs
    def toe_shape(p):
        # lower, slightly wider toe; rounder heel
        t = smooth(-0.04, -0.2, p.y)
        p = Vector((p.x * (1 + 0.05 * t), p.y, p.z))
        if p.z > -0.02:
            p.z = -0.02 + (p.z + 0.02) * (1 - 0.32 * t)
        return p

    for s, side in ((1, 'L'), (-1, 'R')):
        hip = Vector((s * 0.186, 0.006, 0.536))
        knee = Vector((s * 0.186, -0.014, 0.384))
        ankle = Vector((s * 0.186, 0.011, 0.178))
        ball(c, 'H_HipBall.' + side, 'Hatena_Orange', hip + Vector((0, 0, 0.01)), 0.076, seg=24, rings=12)
        capsule(c, 'H_Thigh.' + side, 'Hatena_Orange', hip + Vector((0, 0, 0.02)), knee, 0.074, 0.068)
        ball(c, 'H_Knee.' + side, 'Hatena_Orange', knee, 0.0685, seg=24, rings=12)
        capsule(c, 'H_Shin.' + side, 'Hatena_Orange', knee, ankle, 0.068, 0.062)
        superbox(c, 'H_Shoe.' + side, 'Hatena_Shoe', (s * 0.186, -0.07, 0.098), (0.122, 0.198, 0.07),
                 exps=(3.2, 2.6, 3.0), cuts=10, shape=toe_shape)
        superbox(c, 'H_Sole.' + side, 'Hatena_Sole', (s * 0.186, -0.07, 0.024), (0.13, 0.208, 0.024),
                 exps=(3.2, 2.6, 4.0), cuts=8)
        torus(c, 'H_Collar.' + side, 'Hatena_Sole', (s * 0.186, 0.008, 0.162), 0.085, 0.023, seg=32, sides=10)

    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in c.objects)
    return {'parts': sorted(o.name for o in c.objects), 'tris': tris}


result = build()

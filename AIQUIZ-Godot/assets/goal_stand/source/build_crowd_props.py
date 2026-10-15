"""Hand props for the crowd extras (author_crowd_extras.py), skinned 100% to one
bone each like build_props.py.

Each prop is modelled where it belongs in the clip that uses it (armature space,
character facing -Y) and then carried back to the bone's rest frame:
    rest_point = REST[bone] @ POSE[bone]^-1 @ posed_point
so it sits in the hand at that frame and follows the bone everywhere else.

GSP_Popcorn      striped bucket, left hand          (SPEC_Eat)
GSP_HotDog       bun, sausage, mustard, right hand  (SPEC_Eat at the mouth)
GSP_Phone        selfie phone, right hand           (SPEC_Selfie)
GSP_Binoculars   right hand, at the eyes            (SPEC_Binoculars)
GSP_Megaphone    left hand, at the mouth            (SPEC_Megaphone)
GSP_Drum         cheer drum on spine_01 + a stick in each hand (SPEC_Drum)
GSP_Towel        team towel, right hand             (SPEC_TowelSpin)
GSP_TowelNeck    the same towel round the neck while it rests (spine_03)
GSP_Keg          vendor's beer keg backpack, spine_03, with shoulder straps
GSP_Cup          vendor's beer cup, right hand      (SPEC_VendorWalk)
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

ax = {"AUTHOR": False}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/author_crowd_extras.py", encoding="utf-8").read(), ax)
A = type("A", (), ax)
P = A.P
G = A.G
SKIN, SHIRT, PANTS, HAIR, SHOES, DARK, ACCENT, WHITE, BLUSH, EGG, CARTON, WOOD = range(12)
POPCORN, RED, METAL, BUN = range(12, 16)
FIST = 0.06          # fist centre beyond the wrist along the hand's +Y


class Posed:
    """Maps armature-space geometry at one clip frame to `bone`'s rest frame."""

    def __init__(self, pose_fn, frame, bone):
        self.world = P.solve(pose_fn(frame))
        self.bone = bone
        self.to_rest = P.REST[bone] @ self.world[bone].inverted()

    def frame(self, bone=None):
        return self.world[bone or self.bone]

    def fist(self, bone=None):
        m = self.frame(bone)
        return m.translation + m.to_3x3().col[1].normalized() * FIST

    def axis(self, index, bone=None):
        return self.frame(bone).to_3x3().col[index].normalized()

    def place(self, verts, mb):
        bmesh.ops.transform(mb.bm, matrix=self.to_rest, verts=verts)
        return verts


def basis(y, z_hint):
    """Rotation whose +Y is `y` and +Z is as close as possible to `z_hint`."""
    y = Vector(y).normalized()
    x = y.cross(Vector(z_hint)).normalized()
    z = x.cross(y).normalized()
    return Matrix((x, y, z)).transposed()


def cone(mb, a, b, r1, r2, role, bone, segments=12):
    """Truncated cone from point a (radius r1) to point b (radius r2)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    m = Matrix.Translation((a + b) / 2.0) @ rot
    res = bmesh.ops.create_cone(mb.bm, cap_ends=True, cap_tris=False, segments=segments,
                                radius1=r1, radius2=r2, depth=d.length, matrix=m)
    verts = res["verts"]
    mb._tag(verts, {f for v in verts for f in v.link_faces}, role, bone)
    return verts


def stripes(mb, verts, role_a, role_b, axis):
    """Alternate the side faces of a cylinder between two roles (around `axis`)."""
    faces = sorted({f for v in verts for f in v.link_faces if abs(f.normal.dot(axis)) < 0.5},
                   key=lambda f: math.atan2(f.normal.y, f.normal.x))
    for i, f in enumerate(faces):
        uv = G.role_uv(role_a if i % 2 == 0 else role_b)
        for loop in f.loops:
            loop[mb.uv].uv = uv


def finish(mb, name, coll, palette):
    return G.MeshBuilder.finish(mb, name, coll, [palette], P.RIG)


def popcorn(coll, palette):
    mb = G.MeshBuilder()
    at = Posed(A.eat, 0, "hand_l")
    fist = at.fist()
    centre = Vector((fist.x - 0.075, fist.y - 0.03, fist.z + 0.03))
    up = Vector((0, 0, 1))
    bucket = cone(mb, centre - up * 0.09, centre + up * 0.09, 0.062, 0.085, WHITE, "hand_l", segments=12)
    stripes(mb, bucket, RED, WHITE, up)
    at.place(bucket, mb)
    for i in range(9):
        a = i * 2.4
        r = 0.045 * math.sqrt((i + 0.5) / 9.0)
        p = centre + up * (0.10 + 0.012 * (i % 3)) + Vector((math.cos(a) * r, math.sin(a) * r, 0))
        at.place(mb.box(p, (0.034, 0.032, 0.03), POPCORN, "hand_l"), mb)
    return finish(mb, "GSP_Popcorn", coll, palette)


def hot_dog(coll, palette):
    mb = G.MeshBuilder()
    at = Posed(A.eat, 30, "hand_r")
    fist = at.fist()
    centre = fist + Vector((0.02, -0.035, 0.04))
    along = Vector((1, 0, 0.12)).normalized()
    rot = basis(along, (0, -1, 0))
    at.place(mb.box(centre, (0.055, 0.19, 0.045), BUN, "hand_r", rot=rot), mb)
    at.place(mb.box(centre + Vector((0, -0.004, 0.026)), (0.032, 0.215, 0.03), RED, "hand_r", rot=rot), mb)
    at.place(mb.box(centre + Vector((0, -0.006, 0.043)), (0.012, 0.15, 0.006), POPCORN, "hand_r", rot=rot), mb)
    return finish(mb, "GSP_HotDog", coll, palette)


def phone(coll, palette):
    mb = G.MeshBuilder()
    at = Posed(A.selfie, 10, "hand_r")
    fist = at.fist()
    head = at.frame("Head").translation + Vector((0, -0.10, 0.13))
    normal = (head - fist).normalized()
    up = (Vector((0, 0, 1)) - normal * normal.z).normalized()
    centre = fist + up * 0.07 + normal * 0.035
    rot = basis(up, normal)
    at.place(mb.box(centre, (0.085, 0.17, 0.014), DARK, "hand_r", rot=rot), mb)
    at.place(mb.box(centre + normal * 0.0075, (0.072, 0.148, 0.002), WHITE, "hand_r", rot=rot), mb)
    return finish(mb, "GSP_Phone", coll, palette)


def binoculars(coll, palette):
    mb = G.MeshBuilder()
    at = Posed(A.binoculars, 0, "hand_r")
    eyes_z = at.frame("Head").translation.z + 0.145
    fists = (at.fist("hand_l") + at.fist("hand_r")) / 2.0
    for x in (-0.042, 0.042):
        a = Vector((x, -0.17, eyes_z))
        b = Vector((x, -0.31, eyes_z - 0.005))
        at.place(cone(mb, a, b, 0.028, 0.034, DARK, "hand_r", segments=10), mb)
        at.place(cone(mb, b, b + Vector((0, -0.012, 0)), 0.036, 0.036, METAL, "hand_r", segments=10), mb)
    at.place(mb.box(Vector((0, -0.23, eyes_z)), (0.05, 0.05, 0.03), DARK, "hand_r"), mb)
    # A short grip down to the fists so the binoculars read as held.
    at.place(mb.box(Vector((0, -0.25, (eyes_z + fists.z) / 2.0)), (0.10, 0.04, max(0.02, eyes_z - fists.z)), DARK, "hand_r"), mb)
    return finish(mb, "GSP_Binoculars", coll, palette)


def megaphone(coll, palette):
    mb = G.MeshBuilder()
    at = Posed(A.megaphone, 0, "hand_l")
    mouth = at.frame("Head").translation + Vector((0, -0.17, 0.055))
    tip = mouth + Vector((0.0, -0.30, 0.025))
    at.place(cone(mb, mouth, tip, 0.035, 0.105, WHITE, "hand_l", segments=12), mb)
    band_a = mouth.lerp(tip, 0.78)
    at.place(cone(mb, band_a, mouth.lerp(tip, 0.92), 0.093, 0.103, ACCENT, "hand_l", segments=12), mb)
    at.place(cone(mb, tip, tip + Vector((0, -0.01, 0)), 0.107, 0.107, RED, "hand_l", segments=12), mb)
    fist = at.fist()
    grip_top = mouth.lerp(tip, 0.35) + Vector((0, 0, -0.04))
    at.place(cone(mb, fist, grip_top, 0.016, 0.016, DARK, "hand_l", segments=6), mb)
    return finish(mb, "GSP_Megaphone", coll, palette)


DRUM_CENTRE = Vector((0.0, -0.36, 1.03))
DRUM_AXIS = Vector((0.0, -0.55, 0.84)).normalized()
DRUM_RADIUS = 0.165
DRUM_DEPTH = 0.15


def drum(coll, palette):
    mb = G.MeshBuilder()
    body = Posed(A.drum, 0, "spine_01")
    a = DRUM_CENTRE - DRUM_AXIS * DRUM_DEPTH / 2.0
    b = DRUM_CENTRE + DRUM_AXIS * DRUM_DEPTH / 2.0
    shell = cone(mb, a, b, DRUM_RADIUS, DRUM_RADIUS, WOOD, "spine_01", segments=14)
    body.place(shell, mb)
    body.place(cone(mb, b, b + DRUM_AXIS * 0.006, DRUM_RADIUS - 0.012, DRUM_RADIUS - 0.012, WHITE, "spine_01", segments=14), mb)
    body.place(cone(mb, DRUM_CENTRE - DRUM_AXIS * 0.02, DRUM_CENTRE + DRUM_AXIS * 0.02, DRUM_RADIUS + 0.006,
                    DRUM_RADIUS + 0.006, ACCENT, "spine_01", segments=14), mb)
    # Strap over the shoulders (on the drum's bone; it only has to read at a glance).
    for x in (-0.13, 0.13):
        top = Vector((x, -0.08, 1.45))
        bottom = DRUM_CENTRE + Vector((x * 1.1, 0.05, 0.10))
        d = top - bottom
        body.place(mb.box((top + bottom) / 2.0, (0.03, 0.012, d.length), DARK, "spine_01",
                          rot=Vector((0, 0, 1)).rotation_difference(d.normalized())), mb)
    # A stick in each hand, along the hand's +Y from the fist.
    for side in ("l", "r"):
        hold = Posed(A.drum, 0, "hand_" + side)
        fist = hold.fist()
        direction = hold.axis(1)
        hold.place(cone(mb, fist - direction * 0.03, fist + direction * 0.30, 0.011, 0.011, WOOD, "hand_" + side, segments=6), mb)
        tip = fist + direction * 0.30
        hold.place(mb.ellipsoid(tip, (0.02, 0.02, 0.02), WHITE, "hand_" + side, segments=8, rings=5), mb)
    return finish(mb, "GSP_Drum", coll, palette)


def towel(coll, palette):
    mb = G.MeshBuilder()
    at = Posed(A.towel_spin, 0, "hand_r")
    fist = at.fist()
    out = at.axis(2)                 # hand +Z: sweeps around as the hand spins
    up = at.axis(1)
    droop = (out - up * 0.25).normalized()
    centre = fist + droop * 0.30
    rot = basis(droop, up.cross(droop))      # width stays vertical while it sweeps round
    at.place(mb.box(centre, (0.16, 0.56, 0.018), ACCENT, "hand_r", rot=rot), mb)
    for t in (0.32, 0.42):
        at.place(mb.box(fist + droop * (0.04 + t), (0.165, 0.035, 0.022), WHITE, "hand_r", rot=rot), mb)
    return finish(mb, "GSP_Towel", coll, palette)


def towel_neck(coll, palette):
    """The towel fan's towel resting round the neck while it is not twirled (rest
    pose, spine_03): across the back of the neck, over both shoulders, down the chest."""
    mb = G.MeshBuilder()
    mb.box((0.0, 0.10, 1.50), (0.27, 0.05, 0.08), ACCENT, "spine_03")
    for x in (-0.09, 0.09):
        mb.box((x, -0.02, 1.505), (0.09, 0.23, 0.035), ACCENT, "spine_03")
        mb.box((x, -0.125, 1.33), (0.09, 0.025, 0.34), ACCENT, "spine_03")
        mb.box((x, -0.127, 1.20), (0.094, 0.026, 0.035), WHITE, "spine_03")
    return finish(mb, "GSP_TowelNeck", coll, palette)


def keg(coll, palette):
    mb = G.MeshBuilder()
    at = Posed(A.vendor_walk, 0, "spine_03")
    back = at.frame("spine_03").translation
    centre = Vector((0.0, back.y + 0.27, back.z - 0.12))
    up = Vector((0, 0, 1))
    at.place(cone(mb, centre - up * 0.24, centre + up * 0.24, 0.15, 0.15, METAL, "spine_03", segments=14), mb)
    for z in (-0.13, 0.13):
        at.place(cone(mb, centre + up * (z - 0.025), centre + up * (z + 0.025), 0.154, 0.154, ACCENT, "spine_03", segments=14), mb)
    at.place(cone(mb, centre + up * 0.24, centre + up * 0.30, 0.04, 0.03, DARK, "spine_03", segments=8), mb)
    for x in (-0.12, 0.12):
        at.place(mb.box(Vector((x, back.y - 0.03, back.z + 0.12)), (0.045, 0.30, 0.025), DARK, "spine_03"), mb)
        at.place(mb.box(Vector((x, back.y - 0.135, back.z - 0.05)), (0.045, 0.02, 0.32), DARK, "spine_03"), mb)
    return finish(mb, "GSP_Keg", coll, palette)


def cup(coll, palette):
    mb = G.MeshBuilder()
    at = Posed(A.vendor_walk, 0, "hand_r")
    fist = at.fist()
    up = Vector((0, 0, 1))
    base = fist + Vector((0.0, -0.03, 0.0)) - up * 0.04
    at.place(cone(mb, base, base + up * 0.12, 0.033, 0.042, WHITE, "hand_r", segments=10), mb)
    at.place(cone(mb, base + up * 0.115, base + up * 0.125, 0.039, 0.039, POPCORN, "hand_r", segments=10), mb)
    at.place(cone(mb, base + up * 0.125, base + up * 0.145, 0.040, 0.034, WHITE, "hand_r", segments=10), mb)
    return finish(mb, "GSP_Cup", coll, palette)


def build():
    G.scene()
    coll = G.collection("GS_Spectator")
    palette = G.palette_material()
    made = [popcorn(coll, palette), hot_dog(coll, palette), phone(coll, palette), binoculars(coll, palette),
            megaphone(coll, palette), drum(coll, palette), towel(coll, palette), towel_neck(coll, palette),
            keg(coll, palette), cup(coll, palette)]
    for obj in made:
        obj.hide_viewport = True
        obj.hide_render = True
    return {"props": [(o.name, len(o.data.vertices)) for o in made]}


result = build()

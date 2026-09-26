"""Hand props for the crowd, skinned 100% to one hand bone, plus loose projectile
meshes.  Hand frames at rest (T-pose): right hand X=+Z (up), Y=-X (along the arm),
Z=-Y (forward); left hand X=-Z, Y=+X, Z=-Y.  Sticks and the foam finger follow
the forearm (local +Y); the egg sits in the palm.
"""
import bpy
from mathutils import Matrix, Vector

ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
G = type("G", (), ns)
SKIN, SHIRT, PANTS, HAIR, SHOES, DARK, ACCENT, WHITE, BLUSH, EGG, CARTON, WOOD = range(12)
TEXTURES = G.SOURCE + "/textures/"

RIG = bpy.data.objects[G.RIG]


def hand_frame(side):
    bone = RIG.data.bones["hand_" + side]
    return bone.matrix_local.copy()          # columns: X, Y, Z axes; translation: wrist


def local_box(mb, frame, bone, center, size, role, uv_rect=None):
    rot = frame.to_3x3()
    mb.box(frame @ Vector(center), size, role, bone, rot=rot, uv_rect=uv_rect)


def sign_uv(mb, verts, frame):
    """Front (local +Z) face shows the whole image; everything else samples the
    board's own colour near its left edge."""
    inv = frame.inverted()
    faces = {f for v in verts for f in v.link_faces}
    local = {v: inv @ v.co for v in verts}
    xs = [p.x for p in local.values()]
    ys = [p.y for p in local.values()]
    for f in faces:
        normal = (inv.to_3x3() @ f.normal).normalized()
        for loop in f.loops:
            p = local[loop.vert]
            if normal.z > 0.9:
                loop[mb.uv].uv = ((p.x - min(xs)) / (max(xs) - min(xs)), (p.y - min(ys)) / (max(ys) - min(ys)))
            else:
                loop[mb.uv].uv = (0.04, 0.5)


def build():
    G.scene()
    coll = G.collection("GS_Spectator")
    loose = G.collection("GS_Loose")
    palette = G.palette_material()
    right, left = hand_frame("r"), hand_frame("l")
    made = []

    mb = G.MeshBuilder()
    mb.ellipsoid(right @ Vector((-0.045, 0.10, 0.0)), (0.05, 0.05, 0.05), EGG, "hand_r",
                 rot=right.to_3x3() @ Matrix.Diagonal((1.0, 1.3, 1.0)))
    made.append(G.MeshBuilder.finish(mb, "GSP_Egg", coll, [palette], RIG))

    mb = G.MeshBuilder()
    local_box(mb, left, "hand_l", (0.085, 0.03, 0.0), (0.065, 0.14, 0.26), CARTON)
    for z in (-0.08, 0.0, 0.08):
        mb.ellipsoid(left @ Vector((0.13, 0.03, z)), (0.035, 0.035, 0.035), EGG, "hand_l")
    made.append(G.MeshBuilder.finish(mb, "GSP_Carton", coll, [palette], RIG))

    mb = G.MeshBuilder()
    local_box(mb, right, "hand_r", (0.0, 0.075, 0.0), (0.17, 0.16, 0.19), ACCENT)
    local_box(mb, right, "hand_r", (0.03, 0.26, -0.02), (0.075, 0.25, 0.075), ACCENT)
    local_box(mb, right, "hand_r", (0.0, 0.11, -0.12), (0.06, 0.09, 0.06), ACCENT)
    local_box(mb, right, "hand_r", (0.0, 0.075, 0.097), (0.12, 0.10, 0.006), WHITE)
    made.append(G.MeshBuilder.finish(mb, "GSP_FoamFinger", coll, [palette], RIG))

    mb = G.MeshBuilder()
    local_box(mb, right, "hand_r", (0.0, 0.42, 0.0), (0.028, 1.06, 0.028), WOOD)
    local_box(mb, right, "hand_r", (-0.23, 0.80, 0.0), (0.42, 0.30, 0.012), ACCENT)
    local_box(mb, right, "hand_r", (-0.23, 0.80, 0.0), (0.10, 0.31, 0.014), WHITE)
    made.append(G.MeshBuilder.finish(mb, "GSP_Flag", coll, [palette], RIG))

    for key, image in (("P1", "sign_p1.png"), ("P2", "sign_p2.png"), ("Boo", "sign_boo.png")):
        mb = G.MeshBuilder()
        local_box(mb, right, "hand_r", (0.0, 0.34, 0.0), (0.03, 0.86, 0.03), WOOD)
        stick = G.MeshBuilder.finish(mb, "GSP_SignStick" + key, coll, [palette], RIG)
        mat = G.image_material("SPEC_Sign" + key, TEXTURES + image)
        mb = G.MeshBuilder()
        verts = mb.box(right @ Vector((0.0, 0.98, 0.015)), (0.62, 0.46, 0.025), 0, "hand_r",
                       rot=right.to_3x3())
        sign_uv(mb, verts, right)
        board = G.MeshBuilder.finish(mb, "GSP_Sign" + key, coll, [mat], RIG)
        made += [stick, board]

    # Loose meshes for the projectile and its splat (centred, not skinned).
    mb = G.MeshBuilder()
    mb.ellipsoid((0, 0, 0), (0.075, 0.075, 0.10), EGG, None, segments=14, rings=10)
    made.append(G.MeshBuilder.finish(mb, "GSP_EggProjectile", loose, [palette]))
    mb = G.MeshBuilder()
    mb.box((0, 0, 0), (0.07, 0.012, 0.05), EGG, None)
    made.append(G.MeshBuilder.finish(mb, "GSP_ShellShard", loose, [palette]))
    return {"props": [(o.name, len(o.data.vertices)) for o in made]}


result = build()

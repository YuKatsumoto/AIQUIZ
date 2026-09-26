"""Score Tower Finale — choreography, props, referee and cameras (60 fps, 0-11.2 s).

Run inside Blender after build_set.py:
    exec(open(path).read(), ns); ns["animate_all"]()
Every key is written from the timing tables below, so re-running replaces the
whole performance. All times are real ceremony seconds (0 = both players at goal).
"""
import bpy
import math
import sys
from mathutils import Vector, Quaternion, Euler, Matrix

SRC = "C:/AIQUIZ/AIQUIZ-Godot/assets/result_finale/source"
if SRC not in sys.path:
    sys.path.insert(0, SRC)
import importlib
import poses as P
import rig as R
importlib.reload(P)
importlib.reload(R)

SCENE = "AIQUIZ_ScoreTowerFinale"
FPS = 60
END = 11.2
LOOP_START = 9.6
COLLAR = 0.05
POP = 0.35
TOP = 2.60
LOSE_PREVIEW_RATIO = 0.45       # Blender preview only; Godot uses the real scores
CLIMB_START, CLIMB_END = 4.18, 6.30
VERDICT = 6.90

BEATS = {
    "cast_start": 2.0, "pad_pop": 2.34, "correct": 2.5, "hp": 3.3, "climb": 4.1,
    "climb_end": CLIMB_END, "hush": 6.3, "verdict": VERDICT, "crown_start": 7.30,
    "crown_land": 7.66, "cloud": 7.55, "rain": 7.9, "sink_start": 7.40, "sink_end": 8.80,
    "dance_start": 7.60, "kneel": 9.15, "final": 10.4, "loop_start": LOOP_START, "end": END,
}


def F(t):
    return t * FPS


_last_q = {}


def key_quat(ob, q, t, path="rotation_quaternion", group=None):
    k = ob.name + ":" + path
    prev = _last_q.get(k)
    if prev is not None and prev.dot(q) < 0.0:
        q = -q
    _last_q[k] = q.copy()
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = q
    ob.keyframe_insert(path, frame=F(t), group=group or ob.name)


def key_pbone_quat(pb, q, t):
    k = pb.id_data.name + ":" + pb.name
    prev = _last_q.get(k)
    if prev is not None and prev.dot(q) < 0.0:
        q = -q
    _last_q[k] = q.copy()
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = q
    pb.keyframe_insert("rotation_quaternion", frame=F(t), group=pb.name)


def clear(ob):
    if ob.animation_data:
        ob.animation_data_clear()


def smooth_all(ob):
    ad = ob.animation_data
    if not ad or not ad.action:
        return
    for fc in fcurves(ob):
        for p in fc.keyframe_points:
            p.interpolation = 'BEZIER'
            p.handle_left_type = p.handle_right_type = 'AUTO_CLAMPED'
        fc.update()


def fcurves(idblock):
    ad = idblock.animation_data
    if not ad or not ad.action:
        return []
    action = ad.action
    if hasattr(action, "layers") and len(action.layers):
        slot = ad.action_slot
        out = []
        for layer in action.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    if slot is None or cb.slot_handle == slot.handle:
                        out.extend(cb.fcurves)
        return out
    return list(action.fcurves)


# ------------------------------------------------------------------ players

def key_pose(prefix, pose, t, yaw=0.0, hop=0.0, dy=0.0):
    joints, root = R.resolve(pose, P.REST)
    for name, deg in joints.items():
        ob = bpy.data.objects.get(prefix + name)
        if ob is None:
            continue
        key_quat(ob, R.euler(deg).to_quaternion(), t, group=name)
    actor = bpy.data.objects[prefix + "Actor"]
    actor.location = (root[0], root[1] + dy, R.STAND_Z + root[2] + hop)
    actor.keyframe_insert("location", frame=F(t), group="Actor")
    key_quat(actor, Quaternion((0, 0, 1), math.radians(yaw + root[3])), t, group="Actor")


def shared_performance(prefix, mirrored):
    """Identical (mirrored) choreography for both players until the verdict."""
    def pose(p):
        return P.mirror(p) if mirrored else p
    s = -1.0 if mirrored else 1.0
    lag = 0.05 if mirrored else 0.0
    # Arrival: still facing up the course (+Y), then a hop-turn onto the pad.
    key_pose(prefix, P.STAND, 0.0, yaw=180 * s)
    key_pose(prefix, P.STAND, 2.00, yaw=180 * s)
    key_pose(prefix, P.CROUCH, 2.12 + lag, yaw=180 * s)
    key_pose(prefix, pose(P.V_AIR), 2.22 + lag, yaw=200 * s, hop=0.08)
    key_pose(prefix, P.merge(P.V_AIR, P.legs(20)), 2.30 + lag, yaw=270 * s, hop=0.34)
    key_pose(prefix, P.merge(P.V_AIR, P.legs(28)), 2.37 + lag, yaw=335 * s, hop=0.12)
    key_pose(prefix, P.CROUCH, 2.43 + lag, yaw=360 * s, hop=0.0)
    key_pose(prefix, P.READY, 2.62 + lag, yaw=360 * s)
    # Ready bob while the formula builds.
    t = 2.62
    dip = True
    while t < 4.0:
        t += 0.32
        key_pose(prefix, P.READY_DIP if dip else P.READY, t + lag, yaw=360 * s)
        dip = not dip
    key_pose(prefix, P.READY, 4.10 + lag, yaw=360 * s)
    # The tower lurches: arms out for balance, then pump fists as it climbs.
    key_pose(prefix, P.BALANCE, 4.24 + lag, yaw=360 * s)
    key_pose(prefix, P.BALANCE, 4.52 + lag, yaw=360 * s)
    key_pose(prefix, P.READY, 4.74 + lag, yaw=360 * s)
    seq = [(4.92, P.PUMP_R), (5.10, P.READY), (5.30, P.PUMP_L), (5.48, P.READY),
           (5.68, P.PUMP_R), (5.86, P.READY), (6.06, P.PUMP_L), (6.24, P.READY)]
    for tt, p in seq:
        key_pose(prefix, pose(p), tt + lag, yaw=360 * s)
    # Hush: hands clasped, trembling.
    key_pose(prefix, P.PRAY, 6.42 + lag, yaw=360 * s)
    key_pose(prefix, P.merge(P.PRAY, {"head_pivot": (20, 0, 3)}), 6.60 + lag, yaw=360 * s)
    key_pose(prefix, P.merge(P.PRAY, {"head_pivot": (18, 0, -3)}), 6.76 + lag, yaw=360 * s)
    key_pose(prefix, P.PRAY, VERDICT, yaw=360 * s)


def winner_performance(prefix):
    yaw = 360
    key_pose(prefix, P.CROUCH, 6.98, yaw=yaw)
    key_pose(prefix, P.merge(P.V_AIR, P.legs(8)), 7.08, yaw=yaw, hop=0.10)
    key_pose(prefix, P.V_AIR, 7.24, yaw=yaw, hop=0.74)
    key_pose(prefix, P.merge(P.V_AIR, P.legs(10)), 7.36, yaw=yaw, hop=0.18)
    key_pose(prefix, P.V_LAND, 7.43, yaw=yaw)
    key_pose(prefix, P.YES, 7.56, yaw=yaw)
    key_pose(prefix, P.merge(P.YES, {"head_pivot": (-18, 0, 10)}), 8.2, yaw=yaw)
    key_pose(prefix, P.YES, 9.6, yaw=yaw)
    key_pose(prefix, P.YES, END, yaw=yaw)


def loser_performance(prefix):
    # Mirrored actor: keep yaw continuous with the shared (negative) spin.
    yaw = -360
    shock = P.mirror(P.SHOCK)
    key_pose(prefix, shock, 7.00, yaw=yaw)
    key_pose(prefix, P.merge(shock, {"head_pivot": (-30, 0, 4)}), 7.12, yaw=yaw)
    key_pose(prefix, P.merge(shock, {"head_pivot": (-26, 0, -4)}), 7.24, yaw=yaw)
    key_pose(prefix, shock, 7.32, yaw=yaw)
    key_pose(prefix, P.SLUMP, 7.62, yaw=yaw)
    key_pose(prefix, P.merge(P.SLUMP, {"head_pivot": (44, 0, 0)}), 8.30, yaw=yaw)
    key_pose(prefix, P.SLUMP, 8.90, yaw=yaw)
    kneel = P.merge(P.SLUMP, P.legs(46), {"spine": (30, 0, 0)})
    key_pose(prefix, kneel, 9.15, yaw=yaw)
    key_pose(prefix, P.ORZ, 9.40, yaw=yaw)
    t, a = LOOP_START, True
    while t <= END + 1e-6:
        key_pose(prefix, P.SOB_A if a else P.SOB_B, t, yaw=yaw)
        a = not a
        t = round(t + 0.2, 4)


# ------------------------------------------------------------------ towers

def climb_progress(t):
    u = min(max((t - CLIMB_START) / (CLIMB_END - CLIMB_START), 0.0), 1.0)
    # cycloid ease: gentle start, steady middle for the count, gentle arrival
    return u - math.sin(math.tau * u) / math.tau


def animate_towers():
    w = bpy.data.objects["TWR_W_Lift"]
    l = bpy.data.objects["TWR_L_Lift"]
    for ob in (w, l):
        clear(ob)
    stop = POP + (TOP - POP) * LOSE_PREVIEW_RATIO

    def key(ob, t, z, interp='BEZIER'):
        ob.location = (0.0, 0.0, z)
        ob.keyframe_insert("location", index=2, frame=F(t), group="Lift")

    for ob in (w, l):
        key(ob, 0.0, COLLAR)
        key(ob, 2.34, COLLAR)
        key(ob, 2.44, POP + 0.07)
        key(ob, 2.52, POP - 0.03)
        key(ob, 2.60, POP)
        key(ob, 4.10, POP)
        key(ob, CLIMB_START, POP - 0.04)
    # The climb is sampled so the curve is exact (Godot reads it as progress).
    steps = 24
    stopped = None
    for i in range(1, steps + 1):
        t = CLIMB_START + (CLIMB_END - CLIMB_START) * i / steps
        z = POP + (TOP - POP) * climb_progress(t)
        key(w, t, z)
        if stopped is None:
            if z >= stop:
                stopped = t
                key(l, t, stop + 0.05)
            else:
                key(l, t, z)
    key(w, CLIMB_END + 0.07, TOP + 0.06)
    key(w, CLIMB_END + 0.17, TOP)
    key(w, END, TOP)
    key(l, stopped + 0.08, stop)
    key(l, 7.40, stop)
    key(l, 8.80, COLLAR)
    key(l, 8.86, COLLAR + 0.04)
    key(l, 8.94, COLLAR)
    key(l, END, COLLAR)
    for ob in (w, l):
        smooth_all(ob)
    # Linear through the sampled climb so height follows the count exactly.
    for fc in fcurves(w):
        for p in fc.keyframe_points:
            if F(CLIMB_START) < p.co.x < F(CLIMB_END):
                p.interpolation = 'LINEAR'
    return stopped


# ------------------------------------------------------------------ props

def animate_crown():
    crown = bpy.data.objects["PRP_Crown"]
    clear(crown)
    mount = bpy.data.objects["WIN_hat_mount"]
    crown.parent = mount
    crown.matrix_parent_inverse.identity()
    crown.rotation_mode = 'QUATERNION'

    def key(t, z, yaw=0.0, tilt=(0.0, 0.0), scale=1.0):
        crown.location = (0.0, 0.0, z)
        crown.scale = (scale, scale, scale)
        crown.keyframe_insert("location", frame=F(t), group="Crown")
        crown.keyframe_insert("scale", frame=F(t), group="Crown")
        q = Euler((math.radians(tilt[0]), math.radians(tilt[1]), math.radians(yaw)), 'XYZ').to_quaternion()
        key_quat(crown, q, t, group="Crown")

    key(0.0, 1.9, scale=0.0)
    key(7.28, 1.9, yaw=-40, scale=0.0)
    key(7.34, 1.72, yaw=-10, scale=1.1)
    key(7.42, 1.48, yaw=40, scale=1.0)
    key(7.52, 1.0, yaw=130)
    key(7.60, 0.48, yaw=230)
    key(7.66, 0.0, yaw=360 - 20, tilt=(6, 0))
    key(7.74, 0.10, yaw=360 - 8, tilt=(-5, 3))
    key(7.82, 0.0, yaw=360, tilt=(3, -2))
    key(7.94, 0.02, yaw=360, tilt=(-2, 1))
    key(8.06, 0.0, yaw=360)
    key(END, 0.0, yaw=360)
    smooth_all(crown)
    # accelerate like a falling object: linear into the landing
    for fc in fcurves(crown):
        for p in fc.keyframe_points:
            if F(7.42) <= p.co.x < F(7.66) and fc.data_path == "location":
                p.interpolation = 'QUAD'
                p.easing = 'EASE_IN'
    for fc in fcurves(crown):
        if fc.data_path == "scale":
            for p in fc.keyframe_points:
                if p.co.x <= F(7.28):
                    p.interpolation = 'CONSTANT'


def animate_cloud():
    cloud = bpy.data.objects["PRP_Cloud"]
    clear(cloud)
    lift = bpy.data.objects["TWR_L_Lift"]
    cloud.parent = lift
    cloud.matrix_parent_inverse.identity()
    cloud.rotation_mode = 'QUATERNION'

    def key(t, x, z, scale, roll=0.0):
        cloud.location = (x, 0.25, z)
        cloud.scale = (scale, scale, scale)
        cloud.keyframe_insert("location", frame=F(t), group="Cloud")
        cloud.keyframe_insert("scale", frame=F(t), group="Cloud")
        key_quat(cloud, Quaternion((0, 1, 0), math.radians(roll)), t, group="Cloud")

    key(0.0, 0.0, 3.05, 0.0)
    key(7.55, 0.0, 3.05, 0.0)
    key(7.66, 0.0, 3.08, 1.18)
    key(7.76, 0.0, 3.02, 0.95)
    key(7.86, 0.0, 3.05, 1.0)
    key(8.40, 0.07, 3.03, 1.0, 3)
    key(8.95, -0.05, 3.06, 1.0, -2)
    key(9.30, 0.0, 2.40, 1.0)
    key(LOOP_START, 0.0, 1.70, 1.0)
    key(10.0, 0.04, 1.75, 1.0, 2)
    key(10.4, 0.0, 1.70, 1.0)
    key(10.8, -0.04, 1.75, 1.0, -2)
    key(END, 0.0, 1.70, 1.0)
    smooth_all(cloud)
    for fc in fcurves(cloud):
        if fc.data_path == "scale":
            for p in fc.keyframe_points:
                if p.co.x <= F(7.55):
                    p.interpolation = 'CONSTANT'


# ------------------------------------------------------------------ referee

REF_ARMS = {"R": ("DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R"),
            "L": ("DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L")}


def _posed_rest_basis(rig, pb):
    """Armature-space basis the bone would have with identity local rotation."""
    if pb.parent is None:
        return pb.bone.matrix_local.to_3x3()
    return pb.parent.matrix.to_3x3() @ (pb.parent.bone.matrix_local.to_3x3().inverted() @ pb.bone.matrix_local.to_3x3())


def aim_bone(rig, pb, world_dir, twist=0.0):
    arm_dir = rig.matrix_world.to_3x3().inverted() @ Vector(world_dir).normalized()
    basis = _posed_rest_basis(rig, pb)
    local = basis.inverted() @ arm_dir
    q = Vector((0, 1, 0)).rotation_difference(local.normalized())
    if twist:
        q = q @ Quaternion((0, 1, 0), math.radians(twist))
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = q
    bpy.context.view_layer.update()
    return q


# The Godot plush is one blob: its face lives on the same mesh as the body, weighted
# to DEF-head and DEF-hips. Bending those bones (or squashing the rig) warps the face,
# so the body only ever moves rigidly: hops, turns and leans key the rig object and
# every body/leg bone stays at rest. Only the stubby arms bend.
BODY_BONES = ("DEF-head", "DEF-hips", "DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "DEF-toe.L",
              "DEF-thigh.R", "DEF-shin.R", "DEF-foot.R", "DEF-toe.R")
MAX_TILT = 8.0


def referee_key(rig, t, *, hop=0.0, turn=0.0, tilt=(0.0, 0.0),
                r_arm=(-0.7, -0.15, 0.7), l_arm=(0.75, -0.1, -0.6), r_bend=4.0, l_bend=10.0):
    """One referee pose. tilt = (lean back(-)/forward(+), sideways roll) in degrees for the
    whole rigid plush. The flag continues the right arm, so r_arm is the flag direction."""
    lean = max(-MAX_TILT, min(MAX_TILT, tilt[0]))
    roll = max(-MAX_TILT, min(MAX_TILT, tilt[1]))
    rig.location = (0.0, 1.0, hop)
    rig.rotation_mode = 'XYZ'
    rig.rotation_euler = (math.radians(lean), math.radians(roll), math.radians(turn))
    rig.scale = (1.0, 1.0, 1.0)
    rig.keyframe_insert("location", frame=F(t), group="Root")
    rig.keyframe_insert("rotation_euler", frame=F(t), group="Root")
    pbs = rig.pose.bones
    for pb in pbs:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()
    aim_bone(rig, pbs["DEF-upper_arm.R"], r_arm)
    pbs["DEF-forearm.R"].rotation_quaternion = Quaternion((1, 0, 0), math.radians(-r_bend))
    aim_bone(rig, pbs["DEF-upper_arm.L"], l_arm)
    pbs["DEF-forearm.L"].rotation_quaternion = Quaternion((1, 0, 0), math.radians(-l_bend))
    bpy.context.view_layer.update()
    for pb in pbs:
        key_pbone_quat(pb, pb.rotation_quaternion.copy(), t)


def referee_performance(rig, draw):
    rig.animation_data_clear()
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    k = lambda t, **kw: referee_key(rig, t, **kw)
    wait = dict(r_arm=(-0.72, -0.18, 0.66), l_arm=(0.75, -0.1, -0.6))
    # Waiting at the goal: a gentle rigid rock from side to side.
    for i, t in enumerate([0.0, 0.6, 1.2, 1.8]):
        k(t, tilt=(0, 3 if i % 2 else -3), **wait)
    k(2.10, **wait)
    k(2.30, hop=0.22, tilt=(-3, 0), r_arm=(-0.45, -0.12, 0.88), l_arm=(0.8, -0.2, 0.4))
    k(2.46, **wait)
    k(2.60, **wait)
    # Watch each player as the formula builds (whole-body turns).
    k(2.95, turn=-16, **wait)
    k(3.45, turn=16, **wait)
    k(3.95, **wait)
    # Towers climb: lean back a little to look up, turning between them.
    climb = dict(r_arm=(-0.6, -0.12, 0.8), l_arm=(0.85, -0.2, 0.1))
    k(4.20, tilt=(-4, 0), **climb)
    k(4.75, turn=-20, tilt=(-6, 0), **climb)
    k(5.35, turn=20, tilt=(-7, 0), **climb)
    k(5.95, turn=-8, tilt=(-8, 0), **climb)
    # Hush: flag straight up, a nervous rigid tremble.
    hush = dict(r_arm=(-0.08, -0.1, 1.0), l_arm=(0.85, -0.25, -0.35), r_bend=0)
    k(6.36, tilt=(-4, 0), **hush)
    k(6.60, tilt=(-4, 2), **hush)
    k(6.76, tilt=(-4, -2), **hush)
    k(6.88, tilt=(-3, 0), **hush)
    if not draw:
        point = dict(r_arm=(-0.9, -0.32, 0.3), l_arm=(0.8, -0.2, 0.25), r_bend=0)
        k(7.00, hop=0.26, turn=-24, tilt=(-3, 0), **point)
        k(7.16, hop=0.06, turn=-26, tilt=(-4, 0), **point)
        k(7.24, turn=-26, tilt=(-4, 0), **point)
        k(7.40, turn=-24, tilt=(-4, 0), **point)
        wave_a = dict(r_arm=(-0.78, -0.12, 0.62), l_arm=(0.75, -0.2, 0.55), r_bend=6)
        wave_b = dict(r_arm=(-0.05, -0.12, 1.0), l_arm=(0.85, -0.2, 0.3), r_bend=10)
        turn = -14
    else:
        both = dict(r_arm=(-0.35, -0.1, 0.95), l_arm=(0.45, -0.1, 0.9), r_bend=4, l_bend=6)
        k(7.00, hop=0.26, tilt=(-3, 0), **both)
        k(7.24, tilt=(-3, 0), **both)
        wave_a = dict(both, r_arm=(-0.75, -0.1, 0.66))
        wave_b = dict(both, r_arm=(0.1, -0.1, 1.0))
        turn = 0
    t, a = 7.70, True
    while t < LOOP_START - 1e-6:
        hop = 0.18 if abs(t - 8.10) < 0.01 or abs(t - 8.90) < 0.01 else 0.0
        k(t, turn=turn, hop=hop, tilt=(-2, 2 if a else -2), **(wave_a if a else wave_b))
        a = not a
        t = round(t + 0.4, 4)
    t, a = LOOP_START, True
    while t <= END + 1e-6:
        k(t, turn=turn, tilt=(-2, 2 if a else -2), **(wave_a if a else wave_b))
        a = not a
        t = round(t + 0.4, 4)
    smooth_all(rig)
    return rig.animation_data.action


# ------------------------------------------------------------------ cameras

def key_camera(cam, t, eye, target, vfov, roll=0.0):
    cam.location = eye
    q = (Vector(target) - Vector(eye)).to_track_quat('-Z', 'Y')
    if roll:
        q = q @ Quaternion((0, 0, 1), math.radians(roll))
    cam.keyframe_insert("location", frame=F(t), group="Camera")
    key_quat(cam, q, t, group="Camera")
    cam.data.lens = 12.0 / math.tan(math.radians(vfov) / 2)
    cam.data.keyframe_insert("lens", frame=F(t))


SHARED_CAMERA = [
    # Symmetric (x = 0) until the verdict, aimed low so the players stand above
    # the After Effects score cards that occupy the bottom quarter of the frame.
    (0.0, (0.0, -10.6, 3.2), (0.0, 0.6, 1.3), 40),
    (2.0, (0.0, -8.6, 2.5), (0.0, 0.3, 1.25), 40),
    (4.1, (0.0, -8.2, 2.6), (0.0, 0.2, 1.5), 40),
    (6.3, (0.0, -9.4, 4.2), (0.0, 0.2, 2.75), 40),
    (6.9, (0.0, -8.9, 4.1), (0.0, 0.2, 2.8), 38),
]
WIN_CAMERA = [
    (7.20, (-1.9, -6.6, 4.3), (-2.0, 0.0, 4.1), 34),
    (8.6, (-0.6, -7.0, 2.6), (-1.2, 0.2, 3.3), 42),
    (10.4, (0.4, -7.8, 1.2), (-0.4, 0.3, 2.35), 46),
    (END, (0.4, -7.8, 1.2), (-0.4, 0.3, 2.35), 46),
]
DRAW_CAMERA = [
    (7.4, (0.0, -11.2, 5.2), (0.0, 0.2, 3.7), 42),
    (10.4, (0.0, -9.6, 3.1), (0.0, 0.3, 3.6), 44),
    (END, (0.0, -9.6, 3.1), (0.0, 0.3, 3.6), 44),
]


def animate_cameras():
    for name, tail in (("CAM_FinaleWin", WIN_CAMERA), ("CAM_FinaleDraw", DRAW_CAMERA)):
        cam = bpy.data.objects[name]
        clear(cam)
        if cam.data.animation_data:
            cam.data.animation_data_clear()
        for t, eye, target, vfov in SHARED_CAMERA + tail:
            key_camera(cam, t, eye, target, vfov)
        smooth_all(cam)
        for fc in fcurves(cam.data):
            for p in fc.keyframe_points:
                p.interpolation = 'BEZIER'
                p.handle_left_type = p.handle_right_type = 'AUTO_CLAMPED'


# ------------------------------------------------------------------ all

def markers():
    s = bpy.data.scenes[SCENE]
    s.timeline_markers.clear()
    for name, t in BEATS.items():
        s.timeline_markers.new(name, frame=int(round(F(t))))


def animate_all(draw_referee=False):
    _last_q.clear()
    s = bpy.data.scenes[SCENE]
    bpy.context.window.scene = s
    s.frame_start, s.frame_end = 0, int(F(END))
    for ob in s.objects:
        if ob.name.startswith(("WIN_", "LOSE_")):
            clear(ob)
    stopped = animate_towers()
    R.attach_actor("WIN_", "TWR_W_Lift")
    R.attach_actor("LOSE_", "TWR_L_Lift")
    shared_performance("WIN_", False)
    shared_performance("LOSE_", True)
    winner_performance("WIN_")
    loser_performance("LOSE_")
    for ob in s.objects:
        if ob.name.startswith(("WIN_", "LOSE_")):
            smooth_all(ob)
    animate_crown()
    animate_cloud()
    rig = bpy.data.objects["RIG_Referee"]
    for stale in ("REF_FinaleWin", "REF_FinaleDraw"):
        if bpy.data.actions.get(stale) is not None:
            bpy.data.actions.remove(bpy.data.actions[stale])
    win_action = referee_performance(rig, draw=False)
    win_action.name = "REF_FinaleWin"
    win_action.use_fake_user = True
    draw_action = referee_performance(rig, draw=True)
    draw_action.name = "REF_FinaleDraw"
    draw_action.use_fake_user = True
    rig.animation_data.action = draw_action if draw_referee else win_action
    animate_cameras()
    markers()
    s.camera = bpy.data.objects["CAM_FinaleDraw" if draw_referee else "CAM_FinaleWin"]
    s.frame_set(int(F(7.8)))
    return {"lose_stop_time": stopped, "frames": int(F(END))}

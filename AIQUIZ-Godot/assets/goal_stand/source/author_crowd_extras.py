"""Extra crowd clips keyed on RIG_Spectator (30 fps), on top of author_actions.py.

Every clip is upper-body readable, so the seated side stands (SeatedSpectatorKit)
can play it with their own seated legs as well.

SPEC_Gasp        startled, leaning back, hands up by the face          30 f loop
SPEC_Doze        dozing off on the feet, head drooping and jerking up  90 f loop
SPEC_WakeUp      jolted awake, arms flung out, looking around          36 f once
SPEC_Eat         popcorn bucket on the belly, hand to the mouth        60 f loop
SPEC_HighFiveL   high five with the neighbour on the left (+X)         30 f loop
SPEC_HighFiveR   ... on the right (-X), mirrored                       30 f loop
SPEC_ShoulderL   arm around the left neighbour, swaying together       60 f loop
SPEC_ShoulderR   ... around the right neighbour (same sway direction)  60 f loop
SPEC_Selfie      phone held up and out, peace sign, head tilt          60 f loop
SPEC_Binoculars  binoculars at the eyes, slowly panning                90 f loop
SPEC_Megaphone   megaphone at the mouth, fist pumping on the beat      30 f loop
SPEC_Drum        cheer drum on the belly, sticks alternating           30 f loop
SPEC_ChantClap   overhead clap on the beat (follows the leaders)       30 f loop
SPEC_StandWave   the stadium wave: rise, arms up, settle               40 f loop
SPEC_TowelSpin   team towel twirled over the head                      32 f loop
SPEC_CarryKid    a child on the shoulders, hands on its shins          30 f loop
SPEC_KidRide     the child up there, cheering (root = seat on the neck) 24 f loop
SPEC_KidSit      the child resting its hands on the carrier's head     60 f loop
SPEC_VendorWalk  beer vendor walking (UAL Walk_Loop legs), cup up      40 f loop
SPEC_VendorCall  beer vendor calling out with a cup raised             45 f loop

The leaders' beat (Megaphone, Drum, ChantClap) is 0.5 s: hits on frames 0 and 15.
Pair clips meet their neighbour 0.92 m away (goal stand spacing and side stand seats).

    ns = {"AUTHOR": False}; exec(open(".../author_crowd_extras.py", encoding="utf-8").read(), ns)
defines the pose functions without baking (build_crowd_props.py places props with them).
"""
import math

import bpy
from mathutils import Quaternion, Vector

pl = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/pose_lib.py", encoding="utf-8").read(), pl)
P = type("P", (), pl)
G = P.G
TAU = math.tau
PELVIS = P.head("pelvis")          # (0, 0.05, 0.917)
ANKLE = {s: P.head("foot_" + s) for s in ("l", "r")}
SIDE = {"l": 1.0, "r": -1.0}
NEIGHBOUR = 0.92                   # seat / standing slot spacing
BEAT = 15                          # frames per leader beat (0.5 s)
KID_SCALE = 0.62


def smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


def ramp(f, a, b):
    return smooth((f - a) / float(b - a))


def stance(spec, pelvis_offset=(0, 0, 0), ankles=None, width=0.02):
    spec["pelvis"] = dict(spec.get("pelvis", {}), loc=PELVIS + Vector(pelvis_offset))
    for s in ("l", "r"):
        target = ANKLE[s] + Vector((SIDE[s] * width, 0, 0))
        if ankles and s in ankles:
            target = target + Vector(ankles[s])
        P.leg_ik(spec, s, target)
    return spec


def relaxed_arm(spec, s, swing=0.0):
    x = SIDE[s]
    P.arm_ik(spec, s, Vector((x * 0.25, 0.04 + swing, 0.93)), Vector((x * 0.2, 1.0, 0.0)))


def shoulder(spec, s):
    return P.solve(spec)["upperarm_" + s].translation


def arm(spec, s, target, pole):
    P.arm_ik(spec, s, Vector(target), Vector(pole))


def mirror_x(v, m):
    return Vector((v[0] * m, v[1], v[2]))


# ---------------------------------------------------------------- reactions

def gasp(f):
    p = f / 30.0
    tremble = math.sin(TAU * 4.0 * p)
    spec = {
        "spine_01": {"delta": P.rot_x(-0.09)},
        "spine_03": {"delta": P.rot_x(-0.12)},
        "neck_01": {"delta": P.rot_x(-0.04)},
        "Head": {"delta": P.rot_x(-0.10 + 0.025 * tremble)},
    }
    stance(spec, (0, 0.05, -0.025 + 0.006 * tremble), width=0.05)
    for s in ("l", "r"):
        x = SIDE[s]
        arm(spec, s, (x * 0.19, -0.24, 1.60 + 0.012 * tremble), (x, 0.4, -1.0))
        spec["hand_" + s] = {"dir": Vector((x * 0.25, -0.15, 1.0))}
    return spec


def doze_droop(p):
    """Head pitch: slow droop, a jerk back up, settle (seamless at p = 0 / 1)."""
    if p < 0.70:
        return 0.12 + 0.50 * smooth(p / 0.70)
    if p < 0.75:
        return 0.62 - 0.67 * smooth((p - 0.70) / 0.05)
    return -0.05 + 0.17 * smooth((p - 0.75) / 0.25)


def folded_arms(spec, bob=0.0):
    arm(spec, "l", (-0.09, -0.215, 1.20 + bob), (1.0, 0.3, -0.6))
    arm(spec, "r", (0.10, -0.19, 1.15 + bob), (-1.0, 0.3, -0.6))


def doze(f):
    p = f / 90.0
    droop = doze_droop(p)
    slump = max(0.0, droop - 0.12) / 0.5
    breath = 0.008 * math.sin(TAU * 2.0 * p)
    spec = {
        "spine_01": {"delta": P.rot_x(0.04 + 0.06 * slump)},
        "spine_03": {"delta": P.rot_x(0.05 + 0.07 * slump)},
        "neck_01": {"delta": P.rot_x(0.12 * slump)},
        "Head": {"delta": P.rot_x(droop) @ P.rot_y(0.10 * slump)},
    }
    stance(spec, (0, 0, -0.012 + breath - 0.015 * slump))
    folded_arms(spec, breath)
    return spec


def wake_up(f):
    # 0..4 still asleep, 4..9 jolt, 9..26 look around, 26..36 settle to idle.
    jolt = ramp(f, 4, 9) * (1.0 - ramp(f, 22, 34))
    asleep = 1.0 - ramp(f, 3, 7)
    look = math.sin(TAU * (f - 9) / 17.0) if 9 <= f <= 26 else 0.0
    hop = 0.05 * math.sin(math.pi * min(1.0, max(0.0, (f - 4) / 8.0)))
    spec = {
        "spine_01": {"delta": P.rot_x(0.10 * asleep - 0.06 * jolt)},
        "spine_03": {"delta": P.rot_x(0.12 * asleep - 0.08 * jolt) @ P.rot_z(0.18 * look)},
        "neck_01": {"delta": P.rot_x(0.10 * asleep)},
        "Head": {"delta": P.rot_x(0.55 * asleep - 0.20 * jolt) @ P.rot_z(0.45 * look)},
    }
    stance(spec, (0, 0.02 * jolt, -0.02 * asleep + hop), width=0.02 + 0.04 * jolt)
    for s in ("l", "r"):
        x = SIDE[s]
        folded = Vector((-x * 0.095, -0.20, 1.18))
        flung = Vector((x * 0.50, -0.20, 1.52))
        rest = Vector((x * 0.25, 0.04, 0.93))
        if f < 9:
            target = folded.lerp(flung, ramp(f, 4, 9))
        elif f < 26:
            target = flung.lerp(Vector((x * 0.40, -0.18, 1.30)), ramp(f, 9, 26))
        else:
            target = Vector((x * 0.40, -0.18, 1.30)).lerp(rest, ramp(f, 26, 36))
        arm(spec, s, target, (x, 0.5, -0.6 if f < 26 else 0.0))
    return spec


def eat(f):
    p = f / 60.0
    chew = math.sin(TAU * 6.0 * p) * (ramp(f, 26, 30) - ramp(f, 46, 52))
    spec = {
        "spine_03": {"delta": P.rot_x(0.05)},
        "Head": {"delta": P.rot_x(0.06 + 0.03 * chew - 0.08 * (ramp(f, 22, 28) - ramp(f, 38, 46)))},
    }
    stance(spec, (0, 0, -0.01 + 0.004 * chew))
    # Left hand holds the bucket on the belly.
    arm(spec, "l", (0.13, -0.25, 1.09), (1.0, 0.5, -0.5))
    dip = Vector((0.03, -0.31, 1.18))
    mouth = Vector((-0.03, -0.25, 1.54))
    rest = Vector((-0.13, -0.22, 1.12))
    if f < 12:
        target = rest.lerp(dip, ramp(f, 0, 12))
    elif f < 26:
        target = dip.lerp(mouth, ramp(f, 12, 26))
    elif f < 40:
        target = mouth + Vector((0, 0, 0.01 * chew))
    else:
        target = mouth.lerp(rest, ramp(f, 40, 58))
    arm(spec, "r", target, (-1.0, 0.4, -0.8))
    spec["hand_r"] = {"dir": Vector((0.25, -0.1, 1.0)) if 14 <= f <= 44 else Vector((0.3, -0.6, 0.2))}
    return spec


# ---------------------------------------------------------------- pairs

def high_five(m):
    """m = +1: the left neighbour (+X) with the left hand; -1: mirrored."""
    hand = "l" if m > 0 else "r"
    free = "r" if m > 0 else "l"

    def pose(f):
        contact = math.exp(-((f - 10) / 3.0) ** 2)
        hop = 0.05 * math.exp(-((f - 11) / 4.0) ** 2)
        lean = 0.10 * contact
        spec = {
            "spine_03": {"delta": P.rot_y(m * lean) @ P.rot_x(-0.05)},
            "Head": {"delta": P.rot_z(m * 0.25) @ P.rot_x(-0.12)},
        }
        stance(spec, (m * 0.03 * contact, 0, -0.01 + hop))
        wind = Vector((0.27, 0.06, 1.78))
        meet = Vector((NEIGHBOUR / 2.0 - 0.07, -0.10, 1.90))
        pump = Vector((0.26, -0.16, 1.40))
        if f < 6:
            target = wind
        elif f < 10:
            target = wind.lerp(meet, ramp(f, 6, 10))
        elif f < 15:
            target = meet - Vector((0.03, 0, 0.02)) * ramp(f, 10, 15)
        elif f < 22:
            target = (meet - Vector((0.03, 0, 0.02))).lerp(pump, ramp(f, 15, 22))
        else:
            target = pump.lerp(wind, ramp(f, 22, 30))
        arm(spec, hand, mirror_x(target, m), (m * 1.0, 0.3, -0.5))
        spec["hand_" + hand] = {"dir": Vector((m * 0.45, -0.1, 1.0))}
        bob = 0.05 * math.sin(TAU * f / 15.0)
        arm(spec, free, mirror_x((-0.30, -0.14, 1.78 + bob), m), (-m * 1.0, 0.2, -0.6))
        return spec
    return pose


def shoulder_pair(m):
    """Arm around the neighbour on side m; both partners sway the same world way."""
    hand = "l" if m > 0 else "r"
    free = "r" if m > 0 else "l"

    def pose(f):
        p = f / 60.0
        sway = math.sin(TAU * p)
        beat = max(0.0, math.sin(TAU * 2.0 * p))
        spec = {
            "spine_01": {"delta": P.rot_y(0.05 * sway)},
            "spine_03": {"delta": P.rot_y(0.07 * sway) @ P.rot_x(-0.04)},
            "Head": {"delta": P.rot_y(0.10 * sway) @ P.rot_x(-0.10)},
        }
        stance(spec, (0.035 * sway, 0, -0.012 + 0.01 * beat))
        # The wrist rests behind the partner's near shoulder; the two arms cross at
        # different depths so they do not meet head on.
        reach = Vector((m * (NEIGHBOUR - 0.23) + 0.035 * sway * 1.6, 0.10 if m > 0 else 0.17, 1.53 if m > 0 else 1.48))
        arm(spec, hand, reach, (m * 0.2, 1.0, 0.6))
        spec["hand_" + hand] = {"dir": Vector((m * 1.0, 0.1, -0.35))}
        arm(spec, free, mirror_x((-0.28, -0.16, 1.50 + 0.30 * beat), m), (-m * 1.0, 0.2, -0.6))
        return spec
    return pose


# ---------------------------------------------------------------- personalities

def selfie(f):
    p = f / 60.0
    side = 1.0 if f < 30 else -1.0
    settle = ramp(f % 30, 0, 6)
    bob = 0.015 * math.sin(TAU * 2.0 * p)
    spec = {
        "spine_03": {"delta": P.rot_y(-0.08 * settle * side) @ P.rot_z(-0.10)},
        "neck_01": {"delta": P.rot_x(-0.06)},
        "Head": {"delta": P.rot_z(-0.28) @ P.rot_y(-0.16 * side * settle) @ P.rot_x(-0.18)},
    }
    stance(spec, (0.01 * side * settle, 0, -0.01 + bob))
    arm(spec, "r", (-0.36, -0.44, 1.84 + bob), (-1.0, 0.2, -0.5))
    spec["hand_r"] = {"dir": Vector((-0.30, -0.55, 0.78))}
    arm(spec, "l", (0.21, -0.20, 1.62 + bob), (1.0, 0.2, -1.0))
    spec["hand_l"] = {"dir": Vector((0.05, -0.15, 1.0))}
    return spec


def binocular_pan(f):
    p = f / 90.0
    return 0.32 * math.sin(TAU * p) + 0.06 * math.sin(TAU * 3.0 * p)


def binoculars(f):
    pan = binocular_pan(f)
    q = P.rot_z(pan)
    spec = {
        "spine_02": {"delta": P.rot_z(pan * 0.35)},
        "spine_03": {"delta": P.rot_z(pan * 0.45) @ P.rot_x(-0.03)},
        "Head": {"delta": P.rot_z(pan * 0.20) @ P.rot_x(-0.05)},
    }
    stance(spec, (0, 0, -0.008))
    pivot = Vector((0, 0, 1.30))
    for s in ("l", "r"):
        x = SIDE[s]
        target = pivot + q @ (Vector((x * 0.075, -0.27, 1.585)) - pivot)
        arm(spec, s, target, q @ Vector((x * 1.0, 0.3, -0.8)))
        spec["hand_" + s] = {"dir": q @ Vector((-x * 0.10, -0.25, 1.0))}
    return spec


def megaphone(f):
    k = (f % BEAT) / float(BEAT)
    pump = math.exp(-((k - 0.18) / 0.16) ** 2)
    bounce = -0.025 * math.exp(-((k - 0.05) / 0.12) ** 2)
    spec = {
        "spine_01": {"delta": P.rot_x(0.05)},
        "spine_03": {"delta": P.rot_x(0.04 - 0.05 * pump)},
        "Head": {"delta": P.rot_x(-0.04)},
    }
    stance(spec, (0, 0, -0.01 + bounce), width=0.06)
    arm(spec, "l", (0.07, -0.30, 1.56), (1.0, 0.2, -1.0))
    spec["hand_l"] = {"dir": Vector((-0.55, -0.35, 0.75))}
    arm(spec, "r", Vector((-0.27, -0.12, 1.42)).lerp(Vector((-0.20, -0.16, 1.97)), pump), (-1.0, 0.3, -0.6))
    return spec


def drum_strike(f, offset):
    """0 raised .. 1 on the drum head: a fast strike then a rebound."""
    k = ((f - offset) % (2 * BEAT)) / float(2 * BEAT)
    if k < 0.08:
        return 1.0 - k / 0.08 * 0.15
    if k < 0.30:
        return 0.85 * (1.0 - smooth((k - 0.08) / 0.22))
    if k < 0.86:
        return 0.0
    return smooth((k - 0.86) / 0.14)


def drum(f):
    spec = {
        "spine_01": {"delta": P.rot_x(0.06)},
        "spine_03": {"delta": P.rot_x(0.05)},
        "Head": {"delta": P.rot_x(0.05)},
    }
    hit_r, hit_l = drum_strike(f, 0), drum_strike(f, BEAT)
    stance(spec, (0, 0, -0.015 - 0.012 * max(hit_r, hit_l)), width=0.06)
    for s, hit in (("r", hit_r), ("l", hit_l)):
        x = SIDE[s]
        raised = Vector((x * 0.17, -0.20, 1.42))
        down = Vector((x * 0.10, -0.25, 1.22))
        arm(spec, s, raised.lerp(down, hit), (x, 0.4, -0.6))
        spec["hand_" + s] = {"dir": Vector((-x * 0.25, -0.75, -0.25 - 0.45 * hit))}
    return spec


def chant_clap(f):
    k = (f % BEAT) / float(BEAT)
    open_amount = math.sin(math.pi * k) ** 0.6
    spec = {
        "spine_03": {"delta": P.rot_x(-0.05)},
        "Head": {"delta": P.rot_x(-0.12)},
    }
    stance(spec, (0, 0, -0.012 - 0.018 * (1.0 - open_amount)))
    for s in ("l", "r"):
        x = SIDE[s]
        arm(spec, s, (x * (0.075 + 0.17 * open_amount), -0.13, 1.92 - 0.04 * open_amount), (x, 0.3, -0.6))
        spec["hand_" + s] = {"dir": Vector((-x * 0.35 * (1.0 - open_amount), -0.1, 1.0))}
    return spec


def stand_wave_rise(f):
    """0 seated / relaxed .. 1 fully up; the seated kit uses the same curve."""
    return ramp(f, 4, 14) * (1.0 - ramp(f, 26, 38))


def stand_wave(f):
    up = stand_wave_rise(f)
    prep = math.exp(-((f - 3) / 2.5) ** 2)
    hop = 0.055 * math.exp(-((f - 17) / 3.5) ** 2)
    flutter = 0.04 * math.sin(TAU * f / 8.0) * up
    spec = {
        "spine_01": {"delta": P.rot_x(0.08 * prep - 0.05 * up)},
        "spine_03": {"delta": P.rot_x(-0.08 * up)},
        "Head": {"delta": P.rot_x(-0.15 * up)},
    }
    stance(spec, (0, 0, -0.04 * prep + hop))
    for s in ("l", "r"):
        x = SIDE[s]
        rest = Vector((x * 0.25, 0.04, 0.93))
        top = Vector((x * (0.20 + flutter), -0.06, 2.06))
        arm(spec, s, rest.lerp(top, up), (x, 0.5, -0.4 + 0.4 * (1.0 - up)))
    return spec


def towel_spin(f):
    p = f / 32.0
    theta = TAU * 2.0 * p
    bounce = 0.02 * math.sin(TAU * 4.0 * p)
    spec = {
        "spine_03": {"delta": P.rot_y(-0.05) @ P.rot_x(-0.05)},
        "Head": {"delta": P.rot_x(-0.14)},
    }
    stance(spec, (0, 0, -0.01 + bounce))
    centre = Vector((-0.24, -0.06, 1.98))
    arm(spec, "r", centre + Vector((0.06 * math.cos(theta), 0.06 * math.sin(theta), 0)), (-1.0, 0.3, -0.5))
    up_q = Vector((-1, 0, 0)).rotation_difference(Vector((0, 0, 1))) @ P.REST["hand_r"].to_quaternion()
    spec["hand_r"] = {"rot": Quaternion((0, 0, 1), -theta) @ up_q}
    arm(spec, "l", (0.27, -0.14, 1.55 + 0.20 * max(0.0, math.sin(TAU * 2.0 * p))), (1.0, 0.3, -0.6))
    return spec


# ---------------------------------------------------------------- shoulder ride

def carry_kid(f):
    p = f / 30.0
    bob = 0.012 * math.sin(TAU * 2.0 * p)
    spec = {
        "spine_03": {"delta": P.rot_x(-0.03)},
        "neck_01": {"delta": P.rot_x(0.06)},
        "Head": {"delta": P.rot_x(-0.02)},
    }
    stance(spec, (0, 0, -0.02 + bob), width=0.06)
    for s in ("l", "r"):
        x = SIDE[s]
        arm(spec, s, (x * 0.29, -0.16, 1.27 + 0.5 * bob), (x, 0.2, -1.0))
        spec["hand_" + s] = {"dir": Vector((-x * 0.25, -0.3, 1.0))}
    return spec


KID_HIP = Vector((0.0, 0.02, 0.10))      # kid pelvis above its root (the seat on the neck)
## Where the kid's root sits in the carrier's rest space (behind the neck, on the
## shoulders); Godot's GoalStand uses the same point and KID_SCALE.
KID_SEAT = Vector((0.0, 0.19, 1.47))


def kid_legs(spec, kick=0.0):
    spec["pelvis"] = dict(spec.get("pelvis", {}), loc=KID_HIP)
    for s in ("l", "r"):
        x = SIDE[s]
        spec["thigh_" + s] = {"dir": Vector((x * 0.55, -0.80, -0.22))}
        spec["calf_" + s] = {"dir": Vector((x * 0.30, -0.45 + 0.12 * kick * x, -1.0))}
        spec["foot_" + s] = {"dir": Vector((0.0, -1.0, -0.25))}
    return spec


def kid_ride(f):
    p = f / 24.0
    wave = math.sin(TAU * p)
    spec = {
        "spine_01": {"delta": P.rot_y(0.06 * wave)},
        "spine_03": {"delta": P.rot_x(-0.08)},
        "Head": {"delta": P.rot_x(-0.18) @ P.rot_y(0.10 * wave)},
    }
    kid_legs(spec, wave)
    for s in ("l", "r"):
        x = SIDE[s]
        lift = 0.08 * math.sin(TAU * p + (0.0 if s == "l" else math.pi))
        arm(spec, s, Vector((x * 0.36, -0.10, 1.95 + lift)) - Vector((0, 0, PELVIS.z - KID_HIP.z)),
            (x, 0.4, -0.3))
    return spec


def kid_sit(f):
    p = f / 60.0
    look = 0.20 * math.sin(TAU * p)
    spec = {
        "spine_01": {"delta": P.rot_x(0.14)},
        "spine_03": {"delta": P.rot_x(0.10)},
        "Head": {"delta": P.rot_z(look) @ P.rot_x(-0.05)},
    }
    kid_legs(spec, 0.25 * math.sin(TAU * 2.0 * p))
    for s in ("l", "r"):
        x = SIDE[s]
        arm(spec, s, Vector((x * 0.16, -0.40, 0.45)), (x, 0.6, -0.2))
        spec["hand_" + s] = {"dir": Vector((-x * 0.3, -0.6, -0.4))}
    return spec


# ---------------------------------------------------------------- beer vendor

_WALK = []


def _walk_pose(f):
    """Armature-space rotations of UAL Walk_Loop (40 f) for the legs and spine."""
    if not _WALK:
        rig = P.RIG
        sc = G.scene()
        ad = rig.animation_data or rig.animation_data_create()
        act = bpy.data.actions["Walk_Loop"]
        ad.action = act
        if len(act.slots):
            ad.action_slot = act.slots[0]
        first, last = (int(round(v)) for v in act.frame_range)
        for frame in range(first, last):
            sc.frame_set(frame)
            pose = {}
            for name in P.ORDER:
                pb = rig.pose.bones[name]
                pose[name] = (pb.matrix.to_quaternion(), pb.matrix.translation.copy())
            _WALK.append(pose)
        ad.action = None
        for pb in rig.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
    return _WALK[f % len(_WALK)]


def vendor_walk(f):
    walk = _walk_pose(f)
    spec = {}
    for name in ("pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r",
                 "spine_01", "spine_02", "neck_01"):
        spec[name] = {"rot": walk[name][0]}
    spec["pelvis"]["loc"] = walk["pelvis"][1]
    spec["spine_03"] = {"rot": walk["spine_03"][0] @ P.rot_x(0.05)}
    spec["Head"] = {"rot": walk["Head"][0]}
    bob = walk["pelvis"][1].z - PELVIS.z
    arm(spec, "r", (-0.22, -0.30, 1.22 + 0.5 * bob), (-1.0, 0.2, -0.8))
    spec["hand_r"] = {"dir": Vector((0.1, -0.35, 1.0))}
    arm(spec, "l", (0.13, -0.13, 1.33 + 0.5 * bob), (1.0, 0.4, -0.6))
    return spec


def vendor_call(f):
    p = f / 45.0
    turn = 0.30 * math.sin(TAU * p)
    lift = 0.04 * math.sin(TAU * 2.0 * p)
    spec = {
        "spine_03": {"delta": P.rot_z(turn * 0.5) @ P.rot_x(-0.04)},
        "Head": {"delta": P.rot_z(turn * 0.6) @ P.rot_x(-0.10)},
    }
    stance(spec, (0, 0, -0.01), width=0.05)
    q = P.rot_z(turn * 0.5)
    pivot = Vector((0, 0, 1.30))
    arm(spec, "l", pivot + q @ (Vector((0.10, -0.23, 1.58)) - pivot), q @ Vector((1.0, 0.2, -1.0)))
    spec["hand_l"] = {"dir": q @ Vector((-0.6, -0.4, 0.6))}
    arm(spec, "r", pivot + q @ (Vector((-0.30, -0.24, 1.70 + lift)) - pivot), q @ Vector((-1.0, 0.2, -0.6)))
    spec["hand_r"] = {"dir": q @ Vector((0.1, -0.3, 1.0))}
    return spec


# ---------------------------------------------------------------- baking

def bake_once(action_name, frames, pose_fn):
    """Non-looping clip: frames + 1 samples, the last one is the real end pose."""
    action = G.new_action(action_name, P.RIG)
    samples = [P.local_pose(P.solve(pose_fn(f))) for f in range(frames + 1)]
    curves = G.ensure_fcurves(action, P.RIG, P.ORDER, with_location=("pelvis",))
    G.write_keys(curves, samples)
    P.RIG.animation_data.action = None
    return action


CLIPS = [
    ("SPEC_Gasp", 30, gasp, True),
    ("SPEC_Doze", 90, doze, True),
    ("SPEC_WakeUp", 36, wake_up, False),
    ("SPEC_Eat", 60, eat, True),
    ("SPEC_HighFiveL", 30, high_five(1.0), True),
    ("SPEC_HighFiveR", 30, high_five(-1.0), True),
    ("SPEC_ShoulderL", 60, shoulder_pair(1.0), True),
    ("SPEC_ShoulderR", 60, shoulder_pair(-1.0), True),
    ("SPEC_Selfie", 60, selfie, True),
    ("SPEC_Binoculars", 90, binoculars, True),
    ("SPEC_Megaphone", 30, megaphone, True),
    ("SPEC_Drum", 30, drum, True),
    ("SPEC_ChantClap", 30, chant_clap, True),
    ("SPEC_StandWave", 40, stand_wave, True),
    ("SPEC_TowelSpin", 32, towel_spin, True),
    ("SPEC_CarryKid", 30, carry_kid, True),
    ("SPEC_KidRide", 24, kid_ride, True),
    ("SPEC_KidSit", 60, kid_sit, True),
    ("SPEC_VendorWalk", 40, vendor_walk, True),
    ("SPEC_VendorCall", 45, vendor_call, True),
]
ONE_SHOT = {name for name, _frames, _fn, loop in CLIPS if not loop}


def author_all():
    made = {}
    _walk_pose(0)   # samples Walk_Loop before any new action is bound to the rig
    for name, frames, fn, loop in CLIPS:
        action = P.bake(name, frames, fn) if loop else bake_once(name, frames, fn)
        made[name] = [round(v, 1) for v in action.frame_range]
    return made


if globals().get("AUTHOR", True):
    result = author_all()

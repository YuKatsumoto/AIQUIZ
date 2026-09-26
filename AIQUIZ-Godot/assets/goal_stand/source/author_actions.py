"""Original crowd reactions keyed on RIG_Spectator (30 fps, seamless loops).

SPEC_Cheer       jump with fists up (winner's fans)          24 f
SPEC_Clap        fast clapping (goal arrivals)               16 f
SPEC_Rage        stomping, both fists shaking (hotheads)     20 f
SPEC_Despair     hands on head, shaking it (loser's fans)    60 f
SPEC_Wave        big overhead wave (fans calling out)        30 f
SPEC_Anticipate  hands clasped under the chin, nervous bob   16 f
SPEC_PointLaugh  pointing at the loser, laughing             24 f
SPEC_SignUp      sign / flag held high on the right hand     24 f
"""
import math

from mathutils import Vector

pl = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/pose_lib.py", encoding="utf-8").read(), pl)
P = type("P", (), pl)
TAU = math.tau
PELVIS = P.head("pelvis")          # (0, 0.05, 0.917)
ANKLE = {s: P.head("foot_" + s) for s in ("l", "r")}
SIDE = {"l": 1.0, "r": -1.0}


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


def cheer(f):
    p = f / 24.0
    h = 0.05 + 0.11 * math.cos(TAU * (p - 0.45))          # -0.06 .. +0.16
    crouch = max(0.0, -h) / 0.06
    air = max(0.0, h)
    spec = {
        "spine_01": {"delta": P.rot_x(0.08 * crouch)},
        "spine_03": {"delta": P.rot_x(-0.10 * air / 0.16)},
        "neck_01": {"delta": P.rot_x(-0.10)},
        "Head": {"delta": P.rot_x(-0.14)},
    }
    tuck = air / 0.16
    stance(spec, (0, 0.02 * crouch, h), {s: (0, 0.05 * tuck, air + 0.07 * tuck) for s in ("l", "r")})
    reach = 0.40 + 0.14 * (h + 0.06) / 0.22
    for s in ("l", "r"):
        x = SIDE[s]
        wobble = 0.04 * math.sin(TAU * (2.0 * p + (0.0 if s == "l" else 0.25)))
        direction = Vector((x * (0.40 + wobble), -0.14, 0.90)).normalized()
        P.arm_ik(spec, s, shoulder(spec, s) + direction * reach, Vector((x, 0.4, -0.2)))
    return spec


def clap(f):
    k = (f % 8) / 8.0
    open_amount = math.sin(math.pi * k) ** 0.7
    spec = {
        "spine_01": {"delta": P.rot_x(0.04)},
        "spine_03": {"delta": P.rot_x(0.04)},
        "Head": {"delta": P.rot_x(0.07 * (1.0 - open_amount) - 0.04)},
    }
    stance(spec, (0, 0, -0.015 - 0.02 * (1.0 - open_amount)))
    for s in ("l", "r"):
        x = SIDE[s]
        target = Vector((x * (0.125 + 0.14 * open_amount), -0.27, 1.30 + 0.03 * open_amount))
        P.arm_ik(spec, s, target, Vector((x, 0.3, -1.0)))
    return spec


def rage(f):
    p = f / 20.0
    lift_l = 0.13 * max(0.0, math.sin(TAU * p)) ** 1.3
    lift_r = 0.13 * max(0.0, -math.sin(TAU * p)) ** 1.3
    impact = math.exp(-((p % 0.5) / 0.07))
    shake = math.sin(TAU * 2.0 * p)
    spec = {
        "spine_01": {"delta": P.rot_x(0.12)},
        "spine_03": {"delta": P.rot_z(0.07 * shake) @ P.rot_x(0.10)},
        "neck_01": {"delta": P.rot_x(-0.05)},
        "Head": {"delta": P.rot_x(-0.10) @ P.rot_z(-0.05 * shake)},
    }
    stance(spec, (0.015 * shake, 0.0, -0.045 - 0.035 * impact),
           {"l": (0, 0.02, lift_l), "r": (0, 0.02, lift_r)}, width=0.05)
    for s in ("l", "r"):
        x = SIDE[s]
        bob = 0.07 * math.sin(TAU * (3.0 * p + (0.0 if s == "l" else 0.5)))
        P.arm_ik(spec, s, Vector((x * 0.26, -0.36, 1.58 + bob)), Vector((x, 0.2, -0.8)))
    return spec


def despair(f):
    p = f / 60.0
    spec = {
        "spine_01": {"delta": P.rot_x(0.14)},
        "spine_03": {"delta": P.rot_x(0.14)},
        "neck_01": {"delta": P.rot_x(0.10)},
        "Head": {"delta": P.rot_z(0.30 * math.sin(TAU * 2.0 * p)) @ P.rot_x(0.12)},
    }
    stance(spec, (0.02 * math.sin(TAU * p), 0.0, -0.05))
    world = P.solve(spec)
    head_m = world["Head"]
    turn = head_m.to_quaternion() @ P.REST["Head"].to_quaternion().inverted()
    for s in ("l", "r"):
        x = SIDE[s]
        target = head_m.translation + turn @ Vector((x * 0.20, 0.0, 0.16))
        P.arm_ik(spec, s, target, Vector((x, 0.4, 0.3)))
    return spec


def wave(f):
    p = f / 30.0
    sway = math.sin(TAU * p)
    spec = {
        "spine_03": {"delta": P.rot_y(-0.06 * sway)},
        "Head": {"delta": P.rot_z(0.08 * sway) @ P.rot_x(-0.08)},
    }
    stance(spec, (0.02 * sway, 0, 0))
    P.arm_ik(spec, "r", Vector((-0.30 + 0.17 * sway, -0.10, 1.98)), Vector((-1.0, 0.2, -0.3)))
    relaxed_arm(spec, "l", 0.02 * sway)
    return spec


def anticipate(f):
    p = f / 16.0
    bob = math.sin(TAU * 2.0 * p)
    spec = {
        "spine_03": {"delta": P.rot_x(0.06)},
        "Head": {"delta": P.rot_x(0.04) @ P.rot_z(0.03 * bob)},
    }
    stance(spec, (0, 0, -0.02 + 0.012 * bob))
    for s in ("l", "r"):
        x = SIDE[s]
        P.arm_ik(spec, s, Vector((x * 0.045, -0.22, 1.53 + 0.01 * bob)), Vector((x, 0.5, -1.0)))
    return spec


def point_laugh(f):
    p = f / 24.0
    laugh = math.sin(TAU * 3.0 * p)
    spec = {
        "spine_01": {"delta": P.rot_x(-0.04 + 0.03 * laugh)},
        "spine_03": {"delta": P.rot_x(-0.06 + 0.04 * laugh)},
        "Head": {"delta": P.rot_x(-0.20 + 0.05 * laugh)},
    }
    stance(spec, (0, 0, -0.015 + 0.012 * laugh))
    P.arm_ik(spec, "r", shoulder(spec, "r") + Vector((0.05, -0.52, -0.08 + 0.02 * laugh)), Vector((-1.0, 0.0, -0.4)))
    P.arm_ik(spec, "l", Vector((0.10, -0.17, 1.10 + 0.01 * laugh)), Vector((1.0, 0.6, 0.0)))
    return spec


def sign_up(f):
    p = f / 24.0
    pump = math.sin(TAU * p)
    spec = {
        "spine_03": {"delta": P.rot_y(0.05 * pump)},
        "Head": {"delta": P.rot_x(-0.10)},
    }
    stance(spec, (0.012 * pump, 0, -0.01 + 0.012 * abs(pump)))
    P.arm_ik(spec, "r", Vector((-0.20 + 0.03 * pump, -0.12, 1.92 + 0.07 * pump)), Vector((-1.0, 0.3, -0.4)))
    # Keep the hand's forearm axis (+Y) upright so the stick stands straight.
    spec["hand_r"] = {"dir": Vector((0.06 * pump, -0.05, 1.0))}
    P.arm_ik(spec, "l", Vector((0.20, 0.02, 1.02)), Vector((1.0, 0.4, 0.0)))
    return spec


CLIPS = [
    ("SPEC_Cheer", 24, cheer),
    ("SPEC_Clap", 16, clap),
    ("SPEC_Rage", 20, rage),
    ("SPEC_Despair", 60, despair),
    ("SPEC_Wave", 30, wave),
    ("SPEC_Anticipate", 16, anticipate),
    ("SPEC_PointLaugh", 24, point_laugh),
    ("SPEC_SignUp", 24, sign_up),
]


def author_all():
    made = {}
    for name, frames, fn in CLIPS:
        action = P.bake(name, frames, fn)
        made[name] = [round(v, 1) for v in action.frame_range]
    return made


result = author_all()

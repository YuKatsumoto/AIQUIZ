"""Pose library for the block players (Blender local Euler XYZ, degrees).

The block rig mirrors Godot's EmoteBlockmanPreview hierarchy. The player faces -Y.
Axis notes (Blender local): +X on pelvis/spine/head leans forward; shoulders hang -Z,
X<0 swings an arm forward/up, Y>0 swings the l_ (-X side) arm outward. Knees bend with
X>0. Fingers curl toward the palm with X<0.
Joints omitted from a pose sit at their recorded rest values.
"""
import math

BODY = ["pelvis", "spine", "neck", "head_pivot",
        "l_shoulder", "l_elbow", "l_wrist", "r_shoulder", "r_elbow", "r_wrist",
        "l_hip", "l_knee", "l_ankle", "r_hip", "r_knee", "r_ankle"]
FINGERS = ["index", "middle", "ring", "pinky"]
REST = {"l_shoulder": (0.0, 6.0, 0.0), "r_shoulder": (0.0, -6.0, 0.0)}


def mirror(pose):
    """Swap sides; a mirror across X negates Y and Z rotations."""
    out = {}
    for key, value in pose.items():
        if key in ("fist", "fist_l", "fist_r", "dx", "dy", "dz", "yaw"):
            continue
        name = key
        if key.startswith("l_"):
            name = "r_" + key[2:]
        elif key.startswith("r_"):
            name = "l_" + key[2:]
        out[name] = (value[0], -value[1], -value[2])
    for key in ("dx", "yaw"):
        if key in pose:
            out[key] = -pose[key]
    for key in ("dy", "dz", "fist"):
        if key in pose:
            out[key] = pose[key]
    if "fist_l" in pose:
        out["fist_r"] = pose["fist_l"]
    if "fist_r" in pose:
        out["fist_l"] = pose["fist_r"]
    return out


def sym(**half):
    """Build a symmetric pose from l_ joints plus centre joints."""
    pose = dict(half)
    for key, value in half.items():
        if key.startswith("l_"):
            pose["r_" + key[2:]] = (value[0], -value[1], -value[2])
    return pose


def legs(bend, dz=None):
    """Knees bent with feet flat: hip -b, knee 2b, ankle -b."""
    drop = 0.9 - 0.9 * math.cos(math.radians(bend))
    out = {"l_hip": (-bend, 0, 0), "l_knee": (2 * bend, 0, 0), "l_ankle": (-bend, 0, 0),
           "r_hip": (-bend, 0, 0), "r_knee": (2 * bend, 0, 0), "r_ankle": (-bend, 0, 0),
           "dz": -drop if dz is None else dz}
    return out


def merge(*parts, **extra):
    out = {}
    for p in parts:
        out.update(p)
    out.update(extra)
    return out


STAND = merge({"fist": 0.15})
READY = merge(legs(12), sym(pelvis=(6, 0, 0), spine=(4, 0, 0), head_pivot=(-8, 0, 0),
                            l_shoulder=(-48, 10, 0), l_elbow=(-82, 0, 34)), fist=1.0)
READY_DIP = merge(READY, legs(18))
BALANCE = merge(legs(22), sym(spine=(-4, 0, 0), head_pivot=(20, 0, 0),
                              l_shoulder=(-12, 78, 0), l_elbow=(-22, 0, 0), l_wrist=(0, 0, 10)), fist=0.1)
PUMP_R = merge(legs(12), {"pelvis": (4, 0, 0), "spine": (-6, 0, -5), "head_pivot": (-16, 0, 4),
                          "r_shoulder": (-165, -10, 0), "r_elbow": (-30, 0, 0),
                          "l_shoulder": (-48, 10, 0), "l_elbow": (-82, 0, 34)}, fist=1.0)
PUMP_L = mirror(PUMP_R)
PUMP_L.update(legs(12))
PUMP_L["fist"] = 1.0
PRAY = merge(legs(10), sym(pelvis=(4, 0, 0), spine=(8, 0, 0), head_pivot=(16, 0, 0),
                           l_shoulder=(-58, -16, 0), l_elbow=(-70, 0, 78)), fist=0.35)
CROUCH = merge(legs(40), sym(pelvis=(10, 0, 0), spine=(16, 0, 0), head_pivot=(-4, 0, 0),
                             l_shoulder=(38, 12, 0), l_elbow=(-20, 0, 0)), fist=0.9)
V_AIR = merge(sym(spine=(-10, 0, 0), head_pivot=(-24, 0, 0),
                  l_shoulder=(-8, 152, 0), l_elbow=(-12, 0, 0),
                  l_hip=(-38, 4, 0), l_knee=(66, 0, 0), l_ankle=(22, 0, 0)), fist=1.0, dz=0.0)
V_LAND = merge(legs(32), sym(spine=(6, 0, 0), head_pivot=(-10, 0, 0),
                             l_shoulder=(-8, 148, 0), l_elbow=(-16, 0, 0)), fist=1.0)
YES = merge({"pelvis": (0, 0, 0), "spine": (-9, 5, 0), "head_pivot": (-14, 0, 8),
             "r_shoulder": (-8, -152, 0), "r_elbow": (-10, 0, 0),
             "l_shoulder": (-22, 30, -10), "l_elbow": (-112, 0, 0),
             "l_hip": (-4, 9, 0), "r_hip": (-4, -9, 0), "l_knee": (8, 0, 0), "r_knee": (8, 0, 0),
             "l_ankle": (-4, -9, 0), "r_ankle": (-4, 9, 0)}, fist=1.0, dz=-0.01)
SHOCK = merge(sym(pelvis=(-4, 0, 0), spine=(-14, 0, 0), head_pivot=(-28, 0, 0),
                  l_shoulder=(-40, 100, 0), l_elbow=(-62, 0, 0), l_wrist=(0, 0, 0),
                  l_hip=(10, 0, 0), l_knee=(14, 0, 0), l_ankle=(-24, 0, 0)), fist=0.0, dz=0.05, dy=0.10)
SLUMP = merge(legs(14), sym(pelvis=(8, 0, 0), spine=(22, 0, 0), head_pivot=(38, 0, 0),
                            l_shoulder=(-26, 4, 0), l_elbow=(-12, 0, 0)), fist=0.3)
ORZ = merge(sym(pelvis=(70, 0, 0), spine=(8, 0, 0), head_pivot=(34, 0, 0),
                l_shoulder=(-118, 12, 0), l_elbow=(-6, 0, 0), l_wrist=(-40, 0, 0),
                l_hip=(-70, 3, 0), l_knee=(92, 0, 0), l_ankle=(58, 0, 0)), fist=0.1, dz=-0.49, dy=0.30)
SOB_A = merge(ORZ, {"spine": (10, 0, 3), "head_pivot": (38, 0, 4)})
SOB_B = merge(ORZ, {"spine": (6, 0, -3), "head_pivot": (30, 0, -4)})

LIBRARY = {name: value for name, value in globals().items() if name.isupper() and isinstance(value, dict)}

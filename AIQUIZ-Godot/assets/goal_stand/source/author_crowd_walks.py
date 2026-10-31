"""The side stands' walking crowd clips (docs/crowd_sim.md, step 3) on RIG_Spectator (30 fps).

From Quaternius UAL (CC0), the whole body:
SPEC_Walk        Walk_Loop: walking, arms swinging                       loop
SPEC_Run         Jog_Fwd_Loop: hurrying back to the seat (goal race)      loop
SPEC_StandUp     Sitting_Exit: getting up from the seat                   once
SPEC_SitDown     Sitting_Enter: sitting down                              once
SPEC_Buy         Interact: reaching to the kiosk window and taking it     once
Authored here (IK, pose_lib, upper body readable seated like the crowd extras):
SPEC_RaiseHand   an arm up, waving to call the vendor                     30 f loop
SPEC_PassItemL   turning to the left neighbour (+X), reaching over, back  30 f once
SPEC_PassItemR   ... to the right neighbour (-X)                          30 f once
SPEC_VendorHand  the beer vendor holding a cup out to the end of a row    30 f once

The seated side stands' kit lifts its seated hips while getting up and sitting
down along `rise` [up from, up to, down from, down to] (seconds), measured here
from the clip's pelvis height. The walks must stay in place (the game moves the
walker); their `ground_speed` (m/s at speed 1) is the planted foot's speed. Both
are stored on the actions; export_goal_stand.py writes them to goal_stand_clips.json.

Run in the live Blender with goal_stand_crowd.blend open, then export the spectator
(export_goal_stand.py with EXPORT_ONLY = ["spectator"]).
"""
import math

import bpy
from mathutils import Vector

SRC = "C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/"
ex = {"AUTHOR": False}
exec(open(SRC + "author_crowd_extras.py", encoding="utf-8").read(), ex)
X = type("X", (), ex)
P = X.P
G = X.G
ub = {"BAKE": False}
exec(open(SRC + "bake_ual.py", encoding="utf-8").read(), ub)
U = type("U", (), ub)

UAL = [
    ("Walk_Loop", "SPEC_Walk"),
    ("Jog_Fwd_Loop", "SPEC_Run"),
    ("Sitting_Exit", "SPEC_StandUp"),
    ("Sitting_Enter", "SPEC_SitDown"),
    ("Interact", "SPEC_Buy"),
]
WALKS = ("SPEC_Walk", "SPEC_Run")
SIDE = X.SIDE
TAU = math.tau


# ---------------------------------------------------------------- authored

def raise_hand(f):
    p = f / 30.0
    wave = math.sin(TAU * p)
    spec = {
        "spine_03": {"delta": P.rot_y(-0.06) @ P.rot_x(-0.03)},
        "Head": {"delta": P.rot_x(-0.12) @ P.rot_z(0.08)},
    }
    X.stance(spec)
    X.arm(spec, "r", (-0.30 + 0.07 * wave, -0.12, 2.02), (-1.0, 0.3, -0.4))
    spec["hand_r"] = {"dir": Vector((-0.25 * wave, -0.1, 1.0))}
    X.arm(spec, "l", (0.20, -0.22, 1.00), (1.0, 0.4, -0.6))
    return spec


def pass_item(m):
    """m +1: the left neighbour (+X), -1: the right one."""
    near, far = ("l", "r") if m > 0 else ("r", "l")

    def pose(f):
        reach = math.sin(math.pi * min(1.0, f / 30.0))
        spec = {
            "spine_01": {"delta": P.rot_z(0.18 * m * reach)},
            "spine_03": {"delta": P.rot_z(0.22 * m * reach) @ P.rot_x(0.06 * reach)},
            "Head": {"delta": P.rot_z(0.30 * m * reach)},
        }
        X.stance(spec)
        lap = Vector((SIDE[near] * 0.20, -0.22, 1.00))
        X.arm(spec, near, lap.lerp(Vector((m * 0.55, -0.22, 1.18)), reach), (SIDE[near], 0.4, -0.6))
        spec["hand_" + near] = {"dir": Vector((m * 0.8, -0.3, 0.2 + 0.3 * reach))}
        lap = Vector((SIDE[far] * 0.12, -0.26, 1.02))
        X.arm(spec, far, lap.lerp(Vector((m * 0.38, -0.26, 1.15)), reach), (SIDE[far], 0.4, -0.6))
        return spec
    return pose


def vendor_hand(f):
    reach = math.sin(math.pi * min(1.0, f / 30.0))
    spec = {
        "spine_01": {"delta": P.rot_x(0.10 * reach)},
        "spine_03": {"delta": P.rot_x(0.12 * reach)},
        "Head": {"delta": P.rot_x(0.10 * reach)},
    }
    X.stance(spec, (0, 0, -0.03 * reach), width=0.05)
    X.arm(spec, "r", Vector((-0.22, -0.30, 1.22)).lerp(Vector((-0.12, -0.62, 1.05)), reach), (-1.0, 0.2, -0.8))
    spec["hand_r"] = {"dir": Vector((0.1, -0.35, 1.0))}
    X.arm(spec, "l", (0.13, -0.13, 1.33), (1.0, 0.4, -0.6))
    return spec


AUTHORED = [
    ("SPEC_RaiseHand", 30, raise_hand, True),
    ("SPEC_PassItemL", 30, pass_item(1.0), False),
    ("SPEC_PassItemR", 30, pass_item(-1.0), False),
    ("SPEC_VendorHand", 30, vendor_hand, False),
]


# ---------------------------------------------------------------- measuring

def _samples(action, bones):
    """Armature-space heads of `bones` on every frame of `action`."""
    rig = P.RIG
    sc = G.scene()
    ad = rig.animation_data or rig.animation_data_create()
    ad.action = action
    if len(action.slots):
        ad.action_slot = action.slots[0]
    first, last = (int(round(v)) for v in action.frame_range)
    out = []
    for frame in range(first, last + 1):
        sc.frame_set(frame)
        out.append({b: rig.pose.bones[b].head.copy() for b in bones})
    ad.action = None
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    return out


def measure_rise(action, rising):
    """[up from, up to, down from, down to] seconds from the pelvis height (10% / 90%)."""
    z = [s["pelvis"].z for s in _samples(action, ["pelvis"])]
    low, high = min(z), max(z)
    k = [(v - low) / max(1e-6, high - low) for v in z]
    def first(test):
        return next(i for i, v in enumerate(k) if test(v)) / G.FPS
    if rising:
        return [round(first(lambda v: v >= 0.1), 4), round(first(lambda v: v >= 0.9), 4), 99.0, 100.0]
    return [-2.0, -1.0, round(first(lambda v: v <= 0.9), 4), round(first(lambda v: v <= 0.1), 4)]


def measure_walk(action):
    """Ground speed (the planted foot's backward speed, m/s) and the hips' drift over the loop."""
    s = _samples(action, ["pelvis", "foot_l", "foot_r"])
    speeds = []
    for i in range(len(s) - 1):
        foot = "foot_l" if s[i]["foot_l"].z < s[i]["foot_r"].z else "foot_r"
        # The rig faces -Y: a planted foot slides towards +Y.
        speeds.append((s[i + 1][foot].y - s[i][foot].y) * G.FPS)
    speeds.sort()
    drift = (s[-1]["pelvis"] - s[0]["pelvis"]).length
    return round(speeds[len(speeds) // 2], 4), round(drift, 4)


# ---------------------------------------------------------------- baking

def author_all():
    made = {}
    for source, target in UAL:
        if source not in bpy.data.actions:
            made[target] = {"missing": source}
            continue
        info = U.bake_clip(source, target)
        action = bpy.data.actions[target]
        if target in WALKS:
            speed, drift = measure_walk(action)
            action["ground_speed"] = speed
            info.update({"ground_speed": speed, "pelvis_drift": drift})
        elif target in ("SPEC_StandUp", "SPEC_SitDown"):
            action["rise"] = measure_rise(action, target == "SPEC_StandUp")
            info["rise"] = list(action["rise"])
        made[target] = info
    for name, frames, fn, loop in AUTHORED:
        action = P.bake(name, frames, fn) if loop else X.bake_once(name, frames, fn)
        made[name] = {"frames": frames, "loop": loop, "range": [round(v, 1) for v in action.frame_range]}
    return made


if globals().get("AUTHOR", True):
    result = author_all()

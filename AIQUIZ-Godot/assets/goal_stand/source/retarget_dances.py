"""Retarget the game's own emote dances (Mixamo FBX in assets/animations) onto
RIG_Spectator so dancing spectators use exactly the moves players can equip.

Both skeletons rest in the same T-pose facing -Y, so each bone takes the source's
world-space rotation change from rest:  R_target = (R_src(t) * R_src_rest^-1) * R_target_rest.
Hip travel is scaled by leg height, then its slow drift is removed (spectators
stay on their step) while sway and bounce survive.

    rd = {}; exec(open(".../retarget_dances.py", encoding="utf-8").read(), rd)
    rd["retarget"]("Ymca Dance.fbx", "SPEC_Dance_YMCA")
"""
import math

import bpy
from mathutils import Vector

pl = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/pose_lib.py", encoding="utf-8").read(), pl)
P = type("P", (), pl)
G = P.G
ANIMATIONS = "C:/AIQUIZ/AIQUIZ-Godot/assets/animations/"

MAP = {
    "Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03",
    "Neck": "neck_01", "Head": "Head",
    "LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
    "RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
    "LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
    "RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
}
DRIFT_WINDOW = 45        # frames (1.5 s) of hip travel averaged away
DRIFT_LIMIT = 0.16       # metres of remaining sway allowed on a step
MAX_FRAMES = 16 * 30


def _import(fbx_name):
    sc = G.scene()
    src = G.collection("GS_Source")
    bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children[src.name]
    before_objects = set(bpy.data.objects)
    before_actions = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=ANIMATIONS + fbx_name)
    objects = [o for o in bpy.data.objects if o not in before_objects]
    actions = [a for a in bpy.data.actions if a not in before_actions]
    arm = next(o for o in objects if o.type == "ARMATURE")
    for obj in objects:
        if obj is not arm:
            bpy.data.objects.remove(obj, do_unlink=True)
    action = arm.animation_data.action if arm.animation_data and arm.animation_data.action else actions[0]
    return arm, action, actions


def _bone_map(arm):
    found = {}
    for bone in arm.data.bones:
        short = bone.name.split(":")[-1]
        if short in MAP:
            found[short] = bone.name
    return found


def retarget(fbx_name, action_name, start=None, end=None):
    sc = G.scene()
    rig = P.RIG
    arm, src_action, imported = _import(fbx_name)
    names = _bone_map(arm)
    first, last = (int(v) for v in src_action.frame_range)
    if start is not None:
        first = max(first, start)
    if end is not None:
        last = min(last, end)
    last = min(last, first + MAX_FRAMES)
    rest_src = {s: (arm.matrix_world @ arm.data.bones[n].matrix_local) for s, n in names.items()}
    rest_q = {s: m.to_quaternion() for s, m in rest_src.items()}
    hips_rest = rest_src["Hips"].translation
    scale = P.head("pelvis").z / hips_rest.z
    rotations = []
    hips = []
    for frame in range(first, last + 1):
        sc.frame_set(frame)
        pose = {}
        for short, name in names.items():
            m = arm.matrix_world @ arm.pose.bones[name].matrix
            pose[short] = (m.to_quaternion() @ rest_q[short].inverted()).normalized()
            if short == "Hips":
                hips.append((m.translation - hips_rest) * scale)
        rotations.append(pose)
    # Remove slow travel, keep sway: subtract a centred moving average, then clamp.
    n = len(hips)
    cleaned = []
    for i in range(n):
        lo, hi = max(0, i - DRIFT_WINDOW // 2), min(n, i + DRIFT_WINDOW // 2 + 1)
        avg = sum((hips[k] for k in range(lo, hi)), Vector()) / (hi - lo)
        offset = hips[i].copy()
        offset.x = max(-DRIFT_LIMIT, min(DRIFT_LIMIT, offset.x - avg.x))
        offset.y = max(-DRIFT_LIMIT, min(DRIFT_LIMIT, offset.y - avg.y))
        cleaned.append(offset)
    samples = []
    for pose, offset in zip(rotations, cleaned):
        spec = {}
        for short, delta in pose.items():
            target = MAP[short]
            spec[target] = {"rot": (delta @ P.REST[target].to_quaternion()).normalized()}
        spec["pelvis"]["loc"] = P.head("pelvis") + offset
        samples.append(P.local_pose(P.solve(spec)))
    action = G.new_action(action_name, rig)
    curves = G.ensure_fcurves(action, rig, P.ORDER, with_location=("pelvis",))
    G.write_keys(curves, samples)
    rig.animation_data.action = None
    # Drop the probe import (armature + its imported actions).
    data = arm.data
    bpy.data.objects.remove(arm, do_unlink=True)
    if data.users == 0:
        bpy.data.armatures.remove(data)
    for act in imported:
        if act.users == 0:
            bpy.data.actions.remove(act)
    lowest = min(min(s["pelvis"][1].z for s in samples), 0.0)
    return {"action": action_name, "frames": len(samples), "seconds": round(len(samples) / G.FPS, 2),
            "bones": len(names), "hip_scale": round(scale, 3), "pelvis_min_dz": round(lowest, 3)}

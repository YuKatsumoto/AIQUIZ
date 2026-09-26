"""Bake the Quaternius UAL clips the crowd uses into SPEC_* actions on RIG_Spectator
(kept bones only, 30 fps) and measure the egg release of the overhand throw.
"""
import json

import bpy
from mathutils import Vector

pl = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/pose_lib.py", encoding="utf-8").read(), pl)
P = type("P", (), pl)
G = P.G

CLIPS = [
    ("Idle_Loop", "SPEC_Idle"),
    ("Idle_Talking_Loop", "SPEC_Talk"),
    ("Idle_TalkingPhone_Loop", "SPEC_Phone"),
    ("Idle_FoldArms_Loop", "SPEC_FoldArms"),
    ("Idle_No_Loop", "SPEC_ShakeHead"),
    ("Yes", "SPEC_Nod"),
    ("Idle_Torch_Loop", "SPEC_HoldUp"),
    ("OverhandThrow", "SPEC_Throw"),
    ("Dance_Loop", "SPEC_DanceBounce"),
    ("Idle_Rail_Call", "SPEC_Shout"),
]


def bake_clip(source_name, target_name):
    sc = G.scene()
    rig = P.RIG
    src = bpy.data.actions[source_name]
    ad = rig.animation_data or rig.animation_data_create()
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    ad.action = src
    if len(src.slots):
        ad.action_slot = src.slots[0]
    first, last = (int(round(v)) for v in src.frame_range)
    samples = []
    hand = []
    for frame in range(first, last + 1):
        sc.frame_set(frame)
        pose = {}
        for name in P.ORDER:
            pb = rig.pose.bones[name]
            pose[name] = (pb.rotation_quaternion.copy().normalized(), pb.location.copy())
        samples.append(pose)
        hand.append((rig.matrix_world @ rig.pose.bones["hand_r"].head).copy())
    root_moves = any((s["root"][0].angle > 1e-4 or s["root"][1].length > 1e-4) for s in samples)
    ad.action = None
    action = G.new_action(target_name, rig)
    locs = ("pelvis", "root") if root_moves else ("pelvis",)
    bones = P.ORDER if root_moves else [b for b in P.ORDER if b != "root"]
    curves = G.ensure_fcurves(action, rig, bones, with_location=locs)
    G.write_keys(curves, samples)
    rig.animation_data.action = None
    info = {"frames": len(samples), "seconds": round((len(samples) - 1) / G.FPS, 3), "root_moves": root_moves}
    if target_name == "SPEC_Throw":
        # Release = fastest forward (-Y) hand speed; also report where the hand is.
        speeds = [(hand[i - 1].y - hand[i].y) for i in range(1, len(hand))]
        release = max(range(len(speeds)), key=lambda i: speeds[i]) + 1
        info.update({"release_frame": release, "release_time": round(release / G.FPS, 3),
                     "release_hand": [round(v, 3) for v in hand[release]]})
    return info


def bake_all():
    out = {}
    for source, target in CLIPS:
        out[target] = bake_clip(source, target)
    return out


result = bake_all()

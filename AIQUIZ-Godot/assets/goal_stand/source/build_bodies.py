"""Block-style spectators skinned rigidly to RIG_Spectator (T-pose rest, facing -Y).

Every box belongs 100% to one bone, so no pose can shear a face. Colour lives in
UV.x as a palette role; Godot tints each spectator per instance. One mesh per
hairstyle keeps a spectator at one draw call (+ an optional prop).
"""
import math

import bpy
from mathutils import Euler, Quaternion

ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
G = type("G", (), ns)
SKIN, SHIRT, PANTS, HAIR, SHOES, DARK, ACCENT, WHITE, BLUSH, EGG, CARTON, WOOD = range(12)

HAIRSTYLES = ["Short", "Long", "Cap", "Afro", "Bald", "Bun", "Headband"]
ANGRY_BROWS = {"Headband", "Bald"}


def body(mb, style):
    box = mb.box
    # Torso, three stacked shirt blocks so every spine bone carries its own slice.
    box((0, 0.02, 0.95), (0.36, 0.23, 0.20), PANTS, "pelvis")
    box((0, 0.015, 1.10), (0.35, 0.22, 0.18), SHIRT, "spine_01")
    box((0, 0.015, 1.24), (0.37, 0.23, 0.16), SHIRT, "spine_02")
    box((0, 0.02, 1.39), (0.41, 0.25, 0.20), SHIRT, "spine_03")
    box((0, -0.101, 1.37), (0.17, 0.012, 0.13), ACCENT, "spine_03")   # team badge
    box((0, 0.01, 1.53), (0.12, 0.12, 0.10), SKIN, "neck_01")
    # Head and face (front is -Y).
    box((0, 0.0, 1.70), (0.30, 0.28, 0.30), SKIN, "Head")
    for side in (-1.0, 1.0):
        box((side * 0.065, -0.145, 1.715), (0.042, 0.02, 0.062), DARK, "Head")
        box((side * 0.10, -0.143, 1.652), (0.05, 0.014, 0.024), BLUSH, "Head")
        brow_rot = None
        if style in ANGRY_BROWS:
            brow_rot = Euler((0.0, -side * math.radians(22.0), 0.0)).to_quaternion()
        box((side * 0.065, -0.147, 1.778), (0.075, 0.02, 0.02), DARK, "Head", rot=brow_rot)
    box((0, -0.145, 1.622), (0.085, 0.02, 0.024), DARK, "Head")
    # Arms: short sleeve, bare forearm, fist.
    for side, s in ((1.0, "l"), (-1.0, "r")):
        box((side * 0.30, 0.065, 1.441), (0.23, 0.145, 0.145), SHIRT, "upperarm_" + s)
        box((side * 0.44, 0.065, 1.441), (0.07, 0.115, 0.115), SKIN, "upperarm_" + s)
        box((side * 0.60, 0.065, 1.441), (0.29, 0.11, 0.11), SKIN, "lowerarm_" + s)
        box((side * 0.80, 0.065, 1.44), (0.13, 0.10, 0.125), SKIN, "hand_" + s)
        box((side * 0.095, 0.0, 0.73), (0.165, 0.18, 0.43), PANTS, "thigh_" + s)
        box((side * 0.095, 0.015, 0.33), (0.145, 0.155, 0.45), PANTS, "calf_" + s)
        box((side * 0.095, -0.03, 0.06), (0.15, 0.22, 0.12), SHOES, "foot_" + s)
        box((side * 0.095, -0.19, 0.045), (0.145, 0.12, 0.09), SHOES, "ball_" + s)
    hair(mb, style)


def hair(mb, style):
    box = mb.box
    top = lambda: box((0, 0.005, 1.87), (0.32, 0.30, 0.06), HAIR, "Head")
    back = lambda h=0.22, z=1.75: box((0, 0.125, z), (0.32, 0.06, h), HAIR, "Head")
    if style in ("Short", "Headband"):
        top(); back()
        for side in (-1.0, 1.0):
            box((side * 0.155, 0.04, 1.775), (0.03, 0.20, 0.14), HAIR, "Head")
        box((-0.045, -0.145, 1.826), (0.22, 0.03, 0.07), HAIR, "Head")
        if style == "Headband":
            box((0, 0.0, 1.805), (0.318, 0.298, 0.042), ACCENT, "Head")
            box((0.04, 0.155, 1.79), (0.05, 0.03, 0.10), ACCENT, "Head", rot=Euler((0, 0.5, 0)).to_quaternion())
    elif style == "Long":
        top()
        box((0, 0.13, 1.64), (0.34, 0.07, 0.44), HAIR, "Head")
        for side in (-1.0, 1.0):
            box((side * 0.16, 0.03, 1.69), (0.035, 0.22, 0.32), HAIR, "Head")
        box((0, -0.145, 1.83), (0.31, 0.03, 0.07), HAIR, "Head")
    elif style == "Cap":
        box((0, 0.01, 1.885), (0.325, 0.305, 0.08), ACCENT, "Head")
        box((0, -0.215, 1.853), (0.29, 0.16, 0.022), ACCENT, "Head")
        box((0, 0.012, 1.93), (0.05, 0.05, 0.02), WHITE, "Head")
        back(0.16, 1.77)
    elif style == "Afro":
        box((0, 0.03, 1.91), (0.44, 0.42, 0.26), HAIR, "Head")
        for side in (-1.0, 1.0):
            box((side * 0.195, 0.04, 1.76), (0.09, 0.36, 0.17), HAIR, "Head")
    elif style == "Bald":
        for side in (-1.0, 1.0):
            box((side * 0.156, 0.05, 1.745), (0.03, 0.15, 0.09), HAIR, "Head")
        box((0, -0.13, 1.585), (0.31, 0.06, 0.09), HAIR, "Head")
        box((0, -0.155, 1.646), (0.15, 0.03, 0.03), HAIR, "Head")
    elif style == "Bun":
        top(); back()
        for side in (-1.0, 1.0):
            box((side * 0.155, 0.04, 1.76), (0.03, 0.20, 0.17), HAIR, "Head")
            box((side * 0.09, -0.145, 1.83), (0.12, 0.03, 0.06), HAIR, "Head")
        box((0, 0.06, 1.955), (0.15, 0.15, 0.11), HAIR, "Head")


def build():
    sc = G.scene()
    rig = bpy.data.objects[G.RIG]
    coll = G.collection("GS_Spectator")
    mat = G.palette_material()
    made = []
    for style in HAIRSTYLES:
        mb = G.MeshBuilder()
        body(mb, style)
        obj = G.MeshBuilder.finish(mb, "SPEC_Body_" + style, coll, [mat], rig)
        obj.hide_viewport = style != "Short"
        obj.hide_render = style != "Short"
        made.append((obj.name, len(obj.data.vertices), len(obj.data.polygons)))
    return made


result = build()

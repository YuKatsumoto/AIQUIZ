"""Tiny pose solver for RIG_Spectator: absolute armature-space targets -> local keys.

A pose is a dict {bone: spec}. spec keys:
  "dir":   armature-space direction for the bone's Y axis (swing from the parented rest)
  "delta": Quaternion applied in armature space on top of the parented rest
  "rot":   absolute armature-space Quaternion
  "loc":   armature-space head position (pelvis / root only)
Two-bone IK helpers turn hand/ankle targets into "dir" specs. Character faces -Y,
its left is +X, up is +Z.
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
G = type("G", (), ns)

RIG = bpy.data.objects[G.RIG]
REST = {b.name: b.matrix_local.copy() for b in RIG.data.bones}
PARENT = {b.name: (b.parent.name if b.parent else None) for b in RIG.data.bones}
ORDER = [b for b in G.KEEP_BONES if b in REST]
IDENTITY = Matrix.Identity(4)


def head(name):
    return REST[name].translation.copy()


def length(a, b):
    return (head(b) - head(a)).length


ARM = {s: (length("upperarm_" + s, "lowerarm_" + s), length("lowerarm_" + s, "hand_" + s)) for s in ("l", "r")}
LEG = {s: (length("thigh_" + s, "calf_" + s), length("calf_" + s, "foot_" + s)) for s in ("l", "r")}


def solve(spec):
    """Return {bone: armature-space Matrix} for every kept bone."""
    world = {}
    for name in ORDER:
        parent = PARENT[name]
        pm = world[parent] if parent else IDENTITY
        prest = REST[parent] if parent else IDENTITY
        default = pm @ prest.inverted() @ REST[name]
        s = spec.get(name, {})
        q = default.to_quaternion()
        if "rot" in s:
            q = s["rot"]
        if "delta" in s:
            q = s["delta"] @ q
        if "dir" in s:
            y = q @ Vector((0, 1, 0))
            q = y.rotation_difference(Vector(s["dir"]).normalized()) @ q
        loc = Vector(s["loc"]) if "loc" in s else default.translation
        world[name] = Matrix.LocRotScale(loc, q, Vector((1, 1, 1)))
    return world


def local_pose(world):
    """{bone: (Quaternion, Vector)} matrix_basis rotation/location per bone."""
    out = {}
    for name in ORDER:
        parent = PARENT[name]
        pm = world[parent] if parent else IDENTITY
        prest = REST[parent] if parent else IDENTITY
        basis = (pm @ prest.inverted() @ REST[name]).inverted() @ world[name]
        loc, rot, _scale = basis.decompose()
        out[name] = (rot.normalized(), loc)
    return out


def two_bone(root, target, l1, l2, pole):
    root, target, pole = Vector(root), Vector(target), Vector(pole)
    to = target - root
    d = min(max(to.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    axis = to.normalized()
    cos_a = (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    perp = pole - axis * pole.dot(axis)
    if perp.length < 1e-5:
        perp = axis.orthogonal()
    perp.normalize()
    joint = root + axis * (l1 * cos_a) + perp * (l1 * sin_a)
    end = root + axis * d
    return (joint - root).normalized(), (end - joint).normalized()


def arm_ik(spec, side, hand_target, pole):
    """Needs the torso already posed: solve once for the shoulder, then again."""
    world = solve(spec)
    shoulder = world["upperarm_" + side].translation
    l1, l2 = ARM[side]
    upper, lower = two_bone(shoulder, hand_target, l1, l2, pole)
    spec["upperarm_" + side] = {"dir": upper}
    spec["lowerarm_" + side] = {"dir": lower}
    return spec


def leg_ik(spec, side, ankle_target, pole=(0, -1, 0.05), flat=True):
    world = solve(spec)
    hip = world["thigh_" + side].translation
    l1, l2 = LEG[side]
    upper, lower = two_bone(hip, ankle_target, l1, l2, Vector(pole) + Vector((0.0, 0.0, 0.0)))
    spec["thigh_" + side] = {"dir": upper}
    spec["calf_" + side] = {"dir": lower}
    if flat:
        spec["foot_" + side] = {"rot": REST["foot_" + side].to_quaternion()}
    return spec


def rot_x(angle):
    return Quaternion((1, 0, 0), angle)


def rot_y(angle):
    return Quaternion((0, 1, 0), angle)


def rot_z(angle):
    return Quaternion((0, 0, 1), angle)


def bake(action_name, frames, pose_fn):
    """pose_fn(frame) -> spec. Writes a looping-friendly action of `frames` frames
    (frame `frames` repeats frame 0 so Godot's loop has no seam)."""
    action = G.new_action(action_name, RIG)
    samples = []
    for f in range(frames + 1):
        samples.append(local_pose(solve(pose_fn(f % frames if f < frames else 0))))
    curves = G.ensure_fcurves(action, RIG, ORDER, with_location=("pelvis",))
    G.write_keys(curves, samples)
    RIG.animation_data.action = None
    return action

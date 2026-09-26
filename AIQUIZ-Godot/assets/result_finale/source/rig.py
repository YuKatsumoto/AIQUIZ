"""Pose application for the block players. Used by animate_finale.py.

Actors are parented to their tower lift (TWR_W_Lift / TWR_L_Lift), so the Actor
track exports relative to the platform top and Godot can ride any tower height.
"""
import bpy
import math
from mathutils import Euler, Quaternion

STAND_Z = 1.32   # Actor origin above the surface the feet stand on


def euler(deg):
    return Euler(tuple(math.radians(v) for v in deg), 'XYZ')


def attach_actor(prefix, lift_name):
    actor = bpy.data.objects[prefix + "Actor"]
    lift = bpy.data.objects[lift_name]
    actor.parent = lift
    actor.matrix_parent_inverse.identity()
    actor.rotation_mode = 'QUATERNION'
    actor.location = (0.0, 0.0, STAND_Z)
    actor.rotation_quaternion = (1, 0, 0, 0)
    return actor


def finger_rotations(side, fist):
    out = {}
    for finger in ("index", "middle", "ring", "pinky"):
        out["%s_%s_prox" % (side, finger)] = (-88 * fist, 0, 0)
        out["%s_%s_mid" % (side, finger)] = (-96 * fist, 0, 0)
        out["%s_%s_dist" % (side, finger)] = (-64 * fist, 0, 0)
    sign = 1 if side == "l" else -1
    out["%s_thumb_prox" % side] = (-30 * fist, 0, sign * 38 * fist)
    out["%s_thumb_dist" % side] = (-42 * fist, 0, 0)
    return out


def resolve(pose, rest):
    """Full joint->Euler(deg) map and root offsets for a pose dict."""
    from poses import BODY
    joints = {}
    for j in BODY:
        joints[j] = pose.get(j, rest.get(j, (0.0, 0.0, 0.0)))
    fist_l = pose.get("fist_l", pose.get("fist", 0.15))
    fist_r = pose.get("fist_r", pose.get("fist", 0.15))
    joints.update(finger_rotations("l", fist_l))
    joints.update(finger_rotations("r", fist_r))
    root = (pose.get("dx", 0.0), pose.get("dy", 0.0), pose.get("dz", 0.0), pose.get("yaw", 0.0))
    return joints, root


def apply_pose(prefix, pose, rest, base=(0.0, 0.0, STAND_Z), yaw=0.0, hop=0.0, frame=None):
    joints, root = resolve(pose, rest)
    for name, deg in joints.items():
        ob = bpy.data.objects.get(prefix + name)
        if ob is None:
            continue
        ob.rotation_mode = 'QUATERNION'
        ob.rotation_quaternion = euler(deg).to_quaternion()
        if frame is not None:
            ob.keyframe_insert("rotation_quaternion", frame=frame, group=name)
    actor = bpy.data.objects[prefix + "Actor"]
    actor.location = (base[0] + root[0], base[1] + root[1], base[2] + root[2] + hop)
    actor.rotation_quaternion = Quaternion((0, 0, 1), math.radians(yaw + root[3]))
    if frame is not None:
        actor.keyframe_insert("location", frame=frame, group="Actor")
        actor.keyframe_insert("rotation_quaternion", frame=frame, group="Actor")

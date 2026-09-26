"""Rebuild only the referee's bat and body swing in the editable Blender scene.

The timing follows the MLB Josh Donaldson batting demonstration: load, lower
body turn, delayed hands, contact, and a complete follow-through. The plush's
short arms require a single-hand grip; the opposite arm balances the turn.
"""

import math

import bpy
from mathutils import Matrix, Vector


def _key_object(obj, property_name, samples):
    for seconds, value in samples:
        setattr(obj, property_name, value)
        obj.keyframe_insert(data_path=property_name, frame=round(seconds * 60), group=obj.name)


def _key_bone(rig, bone_name, samples):
    bone = rig.pose.bones[bone_name]
    bone.rotation_mode = 'XYZ'
    for seconds, degrees in samples:
        bone.rotation_euler = tuple(math.radians(v) for v in degrees)
        bone.keyframe_insert('rotation_euler', frame=round(seconds * 60), group=bone_name)


def _smooth(action):
    if action is None:
        return
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in strip.channelbags:
                for curve in channelbag.fcurves:
                    for point in curve.keyframe_points:
                        point.interpolation = 'BEZIER'
                        point.handle_left_type = 'AUTO_CLAMPED'
                        point.handle_right_type = 'AUTO_CLAMPED'


def apply_referee_swing():
    scene = bpy.data.scenes['AIQUIZ_RefereeFinish_v2']
    rig = bpy.data.objects['RIG_Referee']
    bat = bpy.data.objects['PRP_Bat']
    left_grip = bpy.data.objects['CTRL_Grip_L']
    for obj in (rig, bat, left_grip, bpy.data.objects['CONTACT_Barrel']):
        if obj.name not in scene.objects:
            raise RuntimeError('%s is outside the result scene' % obj.name)

    # Existing actor and camera actions are deliberately untouched.
    rig.animation_data_clear()
    bat.animation_data_clear()
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    left = rig.pose.bones['DEF-hand.L']
    if not left.constraints or left.constraints[0].type != 'IK':
        raise RuntimeError('The original left-hand bat IK is missing')
    left_grip.location = (0, 0, 0)
    left.constraints[0].target = left_grip
    left.constraints[0].use_stretch = False
    for constraint in list(rig.pose.bones['DEF-hand.R'].constraints):
        rig.pose.bones['DEF-hand.R'].constraints.remove(constraint)

    # The grip stays within the plush's reach. Keep the authored impact pose
    # at 8.45 s so the existing sound, VFX and loser launch stay synchronized.
    _key_object(bat, 'location', [
        (0, (.73, -.18, .55)), (7.33, (.73, -.18, .55)),
        (7.60, (.70, -.12, .61)), (7.95, (.59, .12, .83)),
        (8.18, (.53, .22, .94)), (8.28, (.53, .22, .94)),
        (8.35, (.58, .15, .92)), (8.40, (.63, -.03, .85)),
        (8.45, (.67, -.18, .79)), (8.55, (.67, -.18, .79)),
        (8.72, (.60, -.20, .79)), (9.10, (.69, -.18, .63)),
        (9.55, (.73, -.18, .55)), (11.47, (.73, -.18, .55)),
        (12.667, (.73, -.18, .55)),
    ])
    # The barrel coils behind the head in depth. It passes in front of the
    # body only after the hips turn, then arcs upward through the finish.
    directions = [
        (0, (.22, 0, 1)), (7.33, (.22, 0, 1)),
        (7.60, (-.12, .32, 1)), (7.95, (-.38, .36, .87)),
        (8.18, (-.55, .34, .80)), (8.28, (-.55, .34, .80)),
        (8.35, (-.20, .48, .87)), (8.40, (.65, .48, .52)),
        (8.45, (1.27, .18, .36)), (8.55, (1.27, .18, .36)),
        (8.72, (.35, -.35, 1)), (9.10, (.36, -.12, .93)),
        (9.55, (.22, 0, 1)), (11.47, (.22, 0, 1)),
        (12.667, (.22, 0, 1)),
    ]
    bat.rotation_mode = 'QUATERNION'
    previous = None
    rotations = []
    for seconds, direction in directions:
        quaternion = Vector(direction).to_track_quat('X', 'Z')
        if previous is not None and previous.dot(quaternion) < 0:
            quaternion.negate()
        rotations.append((seconds, quaternion.copy()))
        previous = quaternion
    _key_object(bat, 'rotation_quaternion', rotations)

    # His lower half starts the turn before the head and hands. Both feet
    # remain near their planted position; the short limbs retain their length.
    _key_bone(rig, 'DEF-hips', [
        (0, (0, 0, 0)), (7.33, (0, 0, 0)),
        (7.95, (0, 7, 0)), (8.18, (0, 14, 0)),
        (8.28, (0, -3, 0)), (8.35, (0, -14, 0)),
        (8.40, (0, -20, 0)), (8.45, (0, -24, 0)),
        (8.55, (0, -24, 0)), (8.72, (0, -28, 0)),
        (9.10, (0, -8, 0)), (9.55, (0, 0, 0)),
        (11.47, (0, 0, 0)),
    ])
    _key_bone(rig, 'DEF-head', [
        (0, (0, 0, 0)), (7.33, (0, 0, 0)),
        (7.95, (0, -11, 3)), (8.18, (0, -17, 4)),
        (8.28, (0, -17, 4)), (8.35, (0, -7, 2)),
        (8.40, (0, 9, -2)), (8.45, (0, 20, -4)),
        (8.55, (0, 20, -4)), (8.72, (0, 24, -3)),
        (9.10, (0, 8, 0)), (9.55, (0, -2, 0)),
        (11.47, (0, -2, 0)),
    ])
    _key_bone(rig, 'DEF-upper_arm.R', [
        (0, (0, 0, 0)), (7.33, (0, 0, 0)),
        (7.95, (0, 0, -24)), (8.18, (0, 0, -30)),
        (8.28, (0, 0, -30)), (8.40, (0, 0, -12)),
        (8.45, (0, 0, 8)), (8.55, (0, 0, 8)),
        (8.72, (0, 0, 20)), (9.10, (0, 0, -10)),
        (9.55, (0, 0, -28)), (11.47, (0, 0, -28)),
    ])
    _key_bone(rig, 'DEF-forearm.R', [
        (0, (0, 0, 0)), (7.33, (0, 0, 0)),
        (7.95, (15, 0, -15)), (8.28, (15, 0, -15)),
        (8.45, (0, 0, 12)), (8.55, (0, 0, 12)),
        (8.72, (0, 0, 16)), (9.55, (15, 0, -25)),
        (11.47, (15, 0, -25)),
    ])
    _smooth(rig.animation_data.action)
    _smooth(bat.animation_data.action)
    scene.frame_set(507)
    return {'scene': scene.name, 'impact_frame': 507, 'grip': 'CTRL_Grip_L',
            'modified': ['RIG_Referee', 'PRP_Bat']}

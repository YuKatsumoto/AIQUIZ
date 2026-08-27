"""Build the authored ghost-to-shark mount animation assets.

Run with Blender 5.1 or newer:
    blender --background --python build_ghost_shark_mount.py

The character action is intentionally in-place.  Godot owns the variable world
space flight path while this clip supplies the full-body performance.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
ANIMATION_DIR = ROOT / "assets" / "animations"
SOURCE_DIR = ANIMATION_DIR / "source"
Y_BOT_FBX = ANIMATION_DIR / "Y Bot.fbx"
HEROIC_BLEND = SOURCE_DIR / "ghost_shark_mount_sequence.blend"
HEROIC_FBX = ANIMATION_DIR / "Ghost Shark Mount.fbx"
SHARK_BLEND = ROOT / "assets" / "shark" / "source" / "shark_swim_with_jaw.blend"
SHARK_GLB = ROOT / "assets" / "shark" / "shark_swim.glb"
PREVIEW_DIR = ROOT / ".fennara" / "blender" / "ghost_shark_mount"

FPS = 30
FRAME_START = 1
FRAME_END = 120
PREVIEW_FRAMES = (1, 12, 30, 48, 72, 84, 102, 120)


def _remove_numbered_backup(blend_path: Path) -> None:
    backup_path = blend_path.with_name(blend_path.name + "1")
    if backup_path.exists():
        backup_path.unlink()


def _bone(armature: bpy.types.Object, suffix: str) -> bpy.types.PoseBone:
    for pose_bone in armature.pose.bones:
        normalized = pose_bone.name.replace("mixamorig:", "").split(":")[-1]
        if normalized == suffix or normalized.endswith("_" + suffix):
            return pose_bone
    raise RuntimeError(f"Missing Mixamo bone: {suffix}")


def _set_pose_key(
    armature: bpy.types.Object,
    frame: int,
    rotations: dict[str, tuple[float, float, float]],
    hips_location: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> None:
    bpy.context.scene.frame_set(frame)
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)

    hips = _bone(armature, "Hips")
    hips.location = hips_location
    for suffix, degrees in rotations.items():
        pose_bone = _bone(armature, suffix)
        pose_bone.rotation_euler = tuple(math.radians(value) for value in degrees)

    controlled = (
        "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
        "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
        "RightShoulder", "RightArm", "RightForeArm", "RightHand",
        "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
        "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
        "LeftHandThumb1", "LeftHandIndex1", "LeftHandMiddle1",
        "LeftHandRing1", "LeftHandPinky1", "RightHandThumb1",
        "RightHandIndex1", "RightHandMiddle1", "RightHandRing1",
        "RightHandPinky1",
    )
    for suffix in controlled:
        pose_bone = _bone(armature, suffix)
        pose_bone.keyframe_insert("rotation_euler", frame=frame, group=suffix)
        if suffix == "Hips":
            pose_bone.keyframe_insert("location", frame=frame, group=suffix)


def _heroic_poses() -> list[tuple[int, dict[str, tuple[float, float, float]], tuple[float, float, float]]]:
    # The beats match the Godot sequence instead of being a generic float loop:
    # extraction -> awareness -> committed flight -> contact brace -> compression
    # -> rebound -> a stable riding silhouette.  Deliberate left/right offsets
    # keep the ghost alive without turning the motion into random limb noise.
    return [
        (1, {
            "Hips": (14, -7, -6), "Spine": (20, 0, 0), "Spine1": (16, 0, 0),
            "Spine2": (12, 0, 0), "Neck": (-15, 0, 0), "Head": (-18, 4, 0),
            "LeftArm": (20, -10, -24), "RightArm": (14, 8, 20),
            "LeftForeArm": (22, 8, -18), "RightForeArm": (28, -6, 20),
            "LeftUpLeg": (-18, 5, -10), "RightUpLeg": (-10, -4, 7),
            "LeftLeg": (24, 0, 0), "RightLeg": (16, 0, 0),
        }, (0.0, 0.0, -0.10)),
        (10, {
            "Hips": (1, -11, -8), "Spine": (28, 0, 0), "Spine1": (22, 0, 0),
            "Spine2": (17, 0, 0), "Neck": (-17, 0, 0), "Head": (-22, 7, 0),
            "LeftArm": (34, -20, -34), "RightArm": (28, 15, 28),
            "LeftForeArm": (38, 5, -25), "RightForeArm": (30, -4, 23),
            "LeftUpLeg": (-25, 6, -13), "RightUpLeg": (-18, -5, 9),
            "LeftLeg": (34, 0, 0), "RightLeg": (24, 0, 0),
        }, (0.0, 0.0, 0.18)),
        (22, {
            "Hips": (-12, -5, -3), "Spine": (10, 0, 0), "Spine1": (6, 0, 0),
            "Spine2": (2, 0, 0), "Neck": (-3, 0, 0), "Head": (-5, 2, 0),
            "LeftArm": (54, -32, -42), "RightArm": (48, 27, 37),
            "LeftForeArm": (22, 0, -14), "RightForeArm": (20, 0, 14),
            "LeftUpLeg": (-8, 4, -7), "RightUpLeg": (-6, -4, 6),
            "LeftLeg": (12, 0, 0), "RightLeg": (10, 0, 0),
        }, (0.0, 0.0, 0.36)),
        (30, {
            "Hips": (-20, 0, 0), "Spine": (-4, 0, 0), "Spine1": (-8, 0, 0),
            "Spine2": (-10, 0, 0), "Neck": (8, 0, 0), "Head": (10, 0, 0),
            "LeftArm": (78, -34, -45), "RightArm": (70, 31, 42),
            "LeftForeArm": (8, 0, -6), "RightForeArm": (12, 0, 8),
            "LeftHand": (-12, 6, -5), "RightHand": (-12, -6, 5),
            "LeftUpLeg": (8, 4, -5), "RightUpLeg": (5, -4, 4),
            "LeftLeg": (8, 0, 0), "RightLeg": (5, 0, 0),
        }, (0.0, 0.0, 0.42)),
        (48, {
            "Hips": (-30, 5, -4), "Spine": (-15, -3, 2), "Spine1": (-14, -3, 2),
            "Spine2": (-11, -2, 1), "Neck": (12, 2, 0), "Head": (15, 4, -2),
            "LeftArm": (92, -34, -38), "RightArm": (82, 32, 38),
            "LeftForeArm": (10, 0, -7), "RightForeArm": (18, 2, 11),
            "LeftHand": (-14, 8, -6), "RightHand": (-10, -8, 6),
            "LeftUpLeg": (12, 5, -7), "RightUpLeg": (7, -5, 6),
            "LeftLeg": (9, 0, 0), "RightLeg": (5, 0, 0),
        }, (0.0, 0.0, 0.48)),
        (64, {
            "Hips": (-31, -5, 4), "Spine": (-16, 3, -2), "Spine1": (-14, 3, -2),
            "Spine2": (-11, 2, -1), "Neck": (11, -3, 0), "Head": (13, -5, 2),
            "LeftArm": (84, -30, -34), "RightArm": (96, 36, 43),
            "LeftForeArm": (17, -2, -10), "RightForeArm": (8, 0, 6),
            "LeftHand": (-10, 8, -5), "RightHand": (-16, -8, 8),
            "LeftUpLeg": (9, 5, -5), "RightUpLeg": (17, -7, 9),
            "LeftLeg": (5, 0, 0), "RightLeg": (13, 0, 0),
        }, (0.0, 0.0, 0.44)),
        (76, {
            "Hips": (-14, 0, 0), "Spine": (-5, 0, 0), "Spine1": (-7, 0, 0),
            "Spine2": (-5, 0, 0), "Neck": (5, 0, 0), "Head": (6, 0, 0),
            "LeftArm": (72, -34, -39), "RightArm": (74, 34, 39),
            "LeftForeArm": (30, 0, -15), "RightForeArm": (30, 0, 15),
            "LeftHand": (-20, 10, -10), "RightHand": (-20, -10, 10),
            "LeftUpLeg": (30, 13, -18), "RightUpLeg": (26, -13, 18),
            "LeftLeg": (46, 0, 0), "RightLeg": (40, 0, 0),
        }, (0.0, 0.0, 0.28)),
        (78, {
            "Hips": (-10, 0, 0), "Spine": (2, 0, 0), "Spine1": (2, 0, 0),
            "Spine2": (-3, 0, 0), "Neck": (5, 0, 0), "Head": (4, 0, 0),
            "LeftArm": (58, -38, -42), "RightArm": (62, 38, 42),
            "LeftForeArm": (44, 0, -20), "RightForeArm": (38, 0, 20),
            "LeftHand": (-24, 12, -12), "RightHand": (-24, -12, 12),
            "LeftUpLeg": (42, 20, -25), "RightUpLeg": (18, -12, 18),
            "LeftLeg": (62, 0, 0), "RightLeg": (38, 0, 0),
            "LeftFoot": (-20, 0, 0), "RightFoot": (-12, 0, 0),
        }, (0.0, 0.0, 0.20)),
        (84, {
            "Hips": (12, 0, 0), "Spine": (18, 0, 0), "Spine1": (14, 0, 0),
            "Spine2": (8, 0, 0), "Neck": (-6, 0, 0), "Head": (-8, 0, 0),
            "LeftArm": (52, -24, -25), "RightArm": (54, 24, 25),
            "LeftForeArm": (54, 0, -20), "RightForeArm": (52, 0, 20),
            "LeftHand": (-20, 10, -12), "RightHand": (-20, -10, 12),
            "LeftUpLeg": (62, 24, -32), "RightUpLeg": (58, -24, 32),
            "LeftLeg": (82, 0, 0), "RightLeg": (78, 0, 0),
            "LeftFoot": (-28, 0, 0), "RightFoot": (-28, 0, 0),
        }, (0.0, 0.0, -0.08)),
        (94, {
            "Hips": (25, 0, 0), "Spine": (28, 0, 0), "Spine1": (23, 0, 0),
            "Spine2": (14, 0, 0), "Neck": (-12, 0, 0), "Head": (-14, 0, 0),
            "LeftArm": (44, -18, -20), "RightArm": (46, 18, 20),
            "LeftForeArm": (48, 0, -18), "RightForeArm": (46, 0, 18),
            "LeftHand": (-18, 8, -10), "RightHand": (-18, -8, 10),
            "LeftUpLeg": (72, 26, -34), "RightUpLeg": (68, -26, 34),
            "LeftLeg": (96, 0, 0), "RightLeg": (92, 0, 0),
            "LeftFoot": (-34, 0, 0), "RightFoot": (-34, 0, 0),
        }, (0.0, 0.0, -0.18)),
        (104, {
            "Hips": (7, 0, 0), "Spine": (7, 0, 0), "Spine1": (6, 0, 0),
            "Spine2": (3, 0, 0), "Neck": (-2, 0, 0), "Head": (-3, 0, 0),
            "LeftArm": (50, -20, -22), "RightArm": (50, 20, 22),
            "LeftForeArm": (50, 0, -19), "RightForeArm": (50, 0, 19),
            "LeftHand": (-19, 9, -11), "RightHand": (-19, -9, 11),
            "LeftUpLeg": (64, 24, -32), "RightUpLeg": (64, -24, 32),
            "LeftLeg": (88, 0, 0), "RightLeg": (88, 0, 0),
            "LeftFoot": (-30, 0, 0), "RightFoot": (-30, 0, 0),
        }, (0.0, 0.0, 0.04)),
        (120, {
            "Hips": (4, 0, 0), "Spine": (-1, 0, 0), "Spine1": (-2, 0, 0),
            "Spine2": (-3, 0, 0), "Neck": (3, 0, 0), "Head": (4, 0, 0),
            "LeftArm": (48, -19, -21), "RightArm": (48, 19, 21),
            "LeftForeArm": (52, 0, -20), "RightForeArm": (52, 0, 20),
            "LeftHand": (-20, 9, -12), "RightHand": (-20, -9, 12),
            "LeftUpLeg": (60, 23, -30), "RightUpLeg": (60, -23, 30),
            "LeftLeg": (84, 0, 0), "RightLeg": (84, 0, 0),
            "LeftFoot": (-28, 0, 0), "RightFoot": (-28, 0, 0),
        }, (0.0, 0.0, 0.02)),
    ]


def _set_bezier_interpolation(action: bpy.types.Action) -> None:
    # Blender 5.1 actions may be layered.  Keyframe points are reached through
    # channel bags when the legacy fcurves collection is unavailable.
    curves = []
    if hasattr(action, "fcurves"):
        curves.extend(action.fcurves)
    else:
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    try:
                        bag = strip.channelbag(slot)
                    except Exception:
                        bag = None
                    if bag is not None:
                        curves.extend(bag.fcurves)
    for curve in curves:
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"
            # AUTO keeps a continuous tangent through intermediate acting
            # poses. AUTO_CLAMPED made every authored beat feel like a tiny
            # arrival and restart once the clip was slowed down in Godot.
            point.handle_left_type = "AUTO"
            point.handle_right_type = "AUTO"


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _prepare_preview(armature: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("GhostMountPreviewWorld")
    scene.world.color = (0.008, 0.015, 0.035)

    bpy.ops.object.light_add(type="AREA", location=(3.5, -4.5, 5.5))
    key = bpy.context.object
    key.data.energy = 950.0
    key.data.shape = "DISK"
    key.data.size = 5.0
    key.data.color = (0.42, 0.78, 1.0)
    _look_at(key, Vector((0.0, 0.0, 1.0)))

    bpy.ops.object.light_add(type="AREA", location=(-4.0, 1.5, 3.0))
    fill = bpy.context.object
    fill.data.energy = 700.0
    fill.data.size = 4.0
    fill.data.color = (1.0, 0.30, 0.12)
    _look_at(fill, Vector((0.0, 0.0, 1.0)))

    bpy.ops.object.camera_add(location=(4.8, -7.5, 3.25))
    camera = bpy.context.object
    camera.data.lens = 58.0
    _look_at(camera, Vector((0.0, 0.0, 1.05)))
    scene.camera = camera

    bpy.ops.mesh.primitive_plane_add(size=18.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.object
    material = bpy.data.materials.new("PreviewFloor")
    material.diffuse_color = (0.012, 0.025, 0.055, 1.0)
    plane.data.materials.append(material)

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for frame in PREVIEW_FRAMES:
        scene.frame_set(frame)
        scene.render.filepath = str(PREVIEW_DIR / f"heroic_{frame:03d}.png")
        bpy.ops.render.render(write_still=True)


def _build_character_action() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Factory reset restores Blender's default numbered-backup preference.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.import_scene.fbx(filepath=str(Y_BOT_FBX))
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    armature.name = "GhostMountRig"
    armature.animation_data_create()
    if armature.animation_data.action is not None:
        armature.animation_data.action = None
    action = bpy.data.actions.new("GhostMountHeroic")
    armature.animation_data.action = action

    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = FRAME_START
    scene.frame_end = FRAME_END
    for frame, rotations, hips_location in _heroic_poses():
        _set_pose_key(armature, frame, rotations, hips_location)
    _set_bezier_interpolation(action)

    _prepare_preview(armature)
    bpy.ops.wm.save_as_mainfile(filepath=str(HEROIC_BLEND))
    _remove_numbered_backup(HEROIC_BLEND)

    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.fbx(
        filepath=str(HEROIC_FBX),
        use_selection=True,
        object_types={"ARMATURE"},
        apply_unit_scale=True,
        add_leaf_bones=False,
        bake_anim=True,
        bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False,
        bake_anim_force_startend_keying=True,
        bake_anim_step=1.0,
        bake_anim_simplify_factor=0.0,
    )


def _key_shark_action(
    armature: bpy.types.Object,
    name: str,
    keys: list[tuple[int, dict[str, tuple[float, float, float]]]],
    frame_end: int,
) -> bpy.types.Action:
    existing = bpy.data.actions.get(name)
    if existing is not None:
        bpy.data.actions.remove(existing, do_unlink=True)
    action = bpy.data.actions.new(name)
    armature.animation_data_create()
    armature.animation_data.action = action
    for frame, rotations in keys:
        bpy.context.scene.frame_set(frame)
        for pose_bone in armature.pose.bones:
            pose_bone.rotation_mode = "XYZ"
            pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        for bone_name, degrees in rotations.items():
            pose_bone = armature.pose.bones.get(bone_name)
            if pose_bone is None:
                raise RuntimeError(f"Missing shark bone: {bone_name}")
            pose_bone.rotation_euler = tuple(math.radians(value) for value in degrees)
        for bone_name in ("root", "body_01", "body_02", "tail_01", "tail_02", "tail_03", "jaw"):
            armature.pose.bones[bone_name].keyframe_insert("rotation_euler", frame=frame, group=bone_name)
    action.frame_start = 1
    action.frame_end = frame_end
    _set_bezier_interpolation(action)
    return action


def _build_shark_actions() -> None:
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.open_mainfile(filepath=str(SHARK_BLEND))
    scene = bpy.context.scene
    scene.render.fps = FPS
    armature = bpy.data.objects.get("shark_armature")
    if armature is None:
        raise RuntimeError("shark_armature not found")
    armature.animation_data_create()
    if armature.animation_data.action is not None:
        armature.animation_data.action.name = "SharkSwim"
    while armature.animation_data.nla_tracks:
        armature.animation_data.nla_tracks.remove(armature.animation_data.nla_tracks[0])

    rendezvous = _key_shark_action(armature, "GhostRendezvousIdle", [
        (1, {"body_01": (0, -1, -3), "body_02": (0, 1, 5), "tail_01": (0, 1, -10), "tail_02": (0, 0, 15), "tail_03": (0, 0, -20)}),
        (10, {"root": (0, 2, 0), "body_01": (0, 2, 1), "body_02": (0, -2, -2), "tail_01": (0, -1, 5), "tail_02": (0, 0, -8), "tail_03": (0, 0, 11), "jaw": (0, 2, 0)}),
        (20, {"root": (0, -2, 0), "body_01": (0, 1, 3), "body_02": (0, -1, -5), "tail_01": (0, -1, 10), "tail_02": (0, 0, -15), "tail_03": (0, 0, 20), "jaw": (0, 3, 0)}),
        (30, {"body_01": (0, -1, -3), "body_02": (0, 1, 5), "tail_01": (0, 1, -10), "tail_02": (0, 0, 15), "tail_03": (0, 0, -20)}),
    ], 30)
    receive = _key_shark_action(armature, "GhostMountReceive", [
        (1, {"body_01": (0, 0, 0), "body_02": (0, 0, 0), "tail_01": (0, 0, 0), "tail_02": (0, 0, 0), "tail_03": (0, 0, 0), "jaw": (0, 0, 0)}),
        (6, {"root": (0, 7, 0), "body_01": (0, -11, -4), "body_02": (0, -8, 7), "tail_01": (0, 5, -12), "tail_02": (0, 4, 18), "tail_03": (0, 2, -24), "jaw": (0, 7, 0)}),
        (12, {"root": (0, -5, 0), "body_01": (0, 8, 4), "body_02": (0, 6, -6), "tail_01": (0, -5, 11), "tail_02": (0, -4, -16), "tail_03": (0, -2, 21), "jaw": (0, 10, 0)}),
        (20, {"root": (0, 3, 0), "body_01": (0, -5, -2), "body_02": (0, -4, 4), "tail_01": (0, 3, -7), "tail_02": (0, 2, 11), "tail_03": (0, 1, -14), "jaw": (0, 3, 0)}),
        (29, {"root": (0, -1, 0), "body_01": (0, 2, 1), "body_02": (0, 1, -2), "tail_01": (0, -1, 4), "tail_02": (0, -1, -6), "tail_03": (0, 0, 8), "jaw": (0, 1, 0)}),
        (36, {"root": (0, 0, 0), "body_01": (0, 0, 0), "body_02": (0, 0, 0), "tail_01": (0, 0, 0), "tail_02": (0, 0, 0), "tail_03": (0, 0, 0), "jaw": (0, 0, 0)}),
    ], 36)
    departure = _key_shark_action(armature, "GhostDeparture", [
        (1, {"root": (0, -4, 0), "body_01": (0, 8, 4), "body_02": (0, 6, -7), "tail_01": (0, -4, 13), "tail_02": (0, -3, -19), "tail_03": (0, -2, 25), "jaw": (0, 2, 0)}),
        (7, {"root": (0, -8, 0), "body_01": (0, 12, 6), "body_02": (0, 9, -10), "tail_01": (0, -7, 18), "tail_02": (0, -5, -27), "tail_03": (0, -3, 34), "jaw": (0, 1, 0)}),
        (14, {"root": (0, 9, 0), "body_01": (0, -14, -7), "body_02": (0, -10, 11), "tail_01": (0, 8, -20), "tail_02": (0, 6, 29), "tail_03": (0, 3, -37), "jaw": (0, 8, 0)}),
        (24, {"root": (0, 3, 0), "body_01": (0, -5, -3), "body_02": (0, -4, 5), "tail_01": (0, 4, -11), "tail_02": (0, 3, 16), "tail_03": (0, 2, -21), "jaw": (0, 5, 0)}),
        (38, {"root": (0, -2, 0), "body_01": (0, 3, 2), "body_02": (0, 2, -3), "tail_01": (0, -2, 8), "tail_02": (0, -2, -12), "tail_03": (0, -1, 16), "jaw": (0, 2, 0)}),
        (54, {"body_01": (0, -2, -3), "body_02": (0, 2, 4), "tail_01": (0, 2, -9), "tail_02": (0, 1, 13), "tail_03": (0, 1, -18), "jaw": (0, 1, 0)}),
        (66, {"body_01": (0, 0, 0), "body_02": (0, 0, 0), "tail_01": (0, 0, 0), "tail_02": (0, 0, 0), "tail_03": (0, 0, 0), "jaw": (0, 0, 0)}),
    ], 66)

    # A named authored socket is exported as a normal node and replaces the
    # previous bounds-derived seat guess in Godot.
    socket = bpy.data.objects.get("GhostMountSocket")
    if socket is None:
        socket = bpy.data.objects.new("GhostMountSocket", None)
        bpy.context.scene.collection.objects.link(socket)
    socket.empty_display_type = "ARROWS"
    socket.empty_display_size = 0.35
    socket.parent = armature
    socket.parent_type = "BONE"
    socket.parent_bone = "body_01"
    socket.location = (0.18, 0.0, 1.12)
    socket.rotation_euler = (0.0, 0.0, 0.0)

    # Put one action on each NLA track. Blender 5.1's glTF exporter otherwise
    # filters compatible-but-inactive actions too aggressively for this rig.
    armature.animation_data.action = None
    while armature.animation_data.nla_tracks:
        armature.animation_data.nla_tracks.remove(armature.animation_data.nla_tracks[0])
    for action in (bpy.data.actions.get("SharkSwim"), rendezvous, receive, departure):
        if action is None:
            continue
        track = armature.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_start), action)
        strip.name = action.name
    scene.frame_start = 1
    scene.frame_end = 120
    bpy.ops.wm.save_as_mainfile(filepath=str(SHARK_BLEND))
    _remove_numbered_backup(SHARK_BLEND)
    bpy.ops.export_scene.gltf(
        filepath=str(SHARK_GLB),
        export_format="GLB",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_merge_animation="NLA_TRACK",
        export_force_sampling=True,
        export_frame_range=False,
        export_apply=False,
        export_yup=True,
    )


def main() -> None:
    # Keep regeneration deterministic and avoid committing Blender's numbered
    # backup copies beside the authored source files.
    bpy.context.preferences.filepaths.save_version = 0
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    _build_character_action()
    _build_shark_actions()
    print(f"Built {HEROIC_BLEND}")
    print(f"Built {HEROIC_FBX}")
    print(f"Updated {SHARK_BLEND}")
    print(f"Updated {SHARK_GLB}")


if __name__ == "__main__":
    main()

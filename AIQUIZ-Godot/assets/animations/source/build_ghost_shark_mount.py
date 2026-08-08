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
from mathutils import Matrix, Vector
from mathutils.geometry import barycentric_transform


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
PREVIEW_FRAMES = (1, 14, 30, 44, 60, 66, 72, 82, 120)
GODOT_PROCEDURAL_BASE_Y = -1.2
SADDLE_PREFIX = "SharkSaddle_"


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
    # One readable action per beat: wake -> launch -> flight -> reach -> impact
    # -> settle.  The Mixamo hips translation is expressed in the imported
    # bone's centimetre-like local space (local Y maps to Blender world Z).
    # Contact keys compensate for Godot's procedural BASE_Y offset so the FBX
    # hold lands at the verified seat height instead of popping or sinking.
    return [
        (1, {
            "Hips": (8, 0, 0), "Spine": (22, 0, 0), "Spine1": (18, 0, 0),
            "Spine2": (12, 0, 0), "Neck": (-14, 0, 0), "Head": (-20, 3, 0),
            "LeftArm": (64, -20, -32), "RightArm": (64, 20, 32),
            "LeftForeArm": (26, 0, -14), "RightForeArm": (26, 0, 14),
            "LeftUpLeg": (-12, 3, -5), "RightUpLeg": (-12, -3, 5),
            "LeftLeg": (18, 0, 0), "RightLeg": (18, 0, 0),
        }, (0.0, 0.0, 0.0)),
        (14, {
            "Hips": (4, 0, 0), "Spine": (10, 0, 0), "Spine1": (8, 0, 0),
            "Spine2": (5, 0, 0), "Neck": (-5, 0, 0), "Head": (-7, 2, 0),
            "LeftArm": (60, -24, -34), "RightArm": (60, 24, 34),
            "LeftForeArm": (24, 0, -14), "RightForeArm": (24, 0, 14),
            "LeftUpLeg": (-10, 3, -4), "RightUpLeg": (-10, -3, 4),
            "LeftLeg": (16, 0, 0), "RightLeg": (16, 0, 0),
        }, (0.0, 6.0, 0.0)),
        (30, {
            "Hips": (20, 0, 0), "Spine": (14, 0, 0), "Spine1": (10, 0, 0),
            "Spine2": (8, 0, 0), "Neck": (-8, 0, 0), "Head": (-5, 0, 0),
            "LeftArm": (72, -30, -38), "RightArm": (72, 30, 38),
            "LeftForeArm": (10, 0, -6), "RightForeArm": (10, 0, 6),
            "LeftHand": (-8, 4, -4), "RightHand": (-8, -4, 4),
            "LeftUpLeg": (-14, 3, 4), "RightUpLeg": (-14, -3, -4),
            "LeftLeg": (18, 0, 0), "RightLeg": (18, 0, 0),
        }, (0.0, 12.0, 0.0)),
        (44, {
            "Hips": (22, 0, 0), "Spine": (15, 0, 0), "Spine1": (11, 0, 0),
            "Spine2": (8, 0, 0), "Neck": (-8, 0, 0), "Head": (-4, 0, 0),
            "LeftArm": (82, -34, -42), "RightArm": (82, 34, 42),
            "LeftForeArm": (12, 0, -7), "RightForeArm": (12, 0, 7),
            "LeftHand": (-8, 4, -4), "RightHand": (-8, -4, 4),
            "LeftUpLeg": (-10, 3, 5), "RightUpLeg": (-10, -3, -5),
            "LeftLeg": (14, 0, 0), "RightLeg": (14, 0, 0),
        }, (0.0, 14.0, 0.0)),
        (54, {
            "Hips": (20, 0, 0), "Spine": (14, 0, 0), "Spine1": (10, 0, 0),
            "Spine2": (7, 0, 0), "Neck": (-7, 0, 0), "Head": (-3, 0, 0),
            "LeftArm": (84, -35, -43), "RightArm": (80, 33, 41),
            "LeftForeArm": (13, 0, -8), "RightForeArm": (10, 0, 6),
            "LeftHand": (-7, 4, -4), "RightHand": (-7, -4, 4),
            "LeftUpLeg": (-12, 3, 6), "RightUpLeg": (-9, -3, -5),
            "LeftLeg": (16, 0, 0), "RightLeg": (13, 0, 0),
        }, (0.0, 12.0, 0.0)),
        (60, {
            "Hips": (10, 0, 0), "Spine": (8, 0, 0), "Spine1": (6, 0, 0),
            "Spine2": (4, 0, 0), "Neck": (-4, 0, 0), "Head": (-2, 0, 0),
            "LeftArm": (68, -35, -40), "RightArm": (68, 35, 40),
            "LeftForeArm": (26, 0, -10), "RightForeArm": (26, 0, 10),
            "LeftHand": (-8, 4, -5), "RightHand": (-8, -4, 5),
            "LeftUpLeg": (12, 4, 14), "RightUpLeg": (12, -4, -14),
            "LeftLeg": (-28, 0, 0), "RightLeg": (-28, 0, 0),
            "LeftFoot": (12, 0, 0), "RightFoot": (12, 0, 0),
        }, (0.0, 6.0, 0.0)),
        (66, {
            "Hips": (4, 0, 0), "Spine": (6, 0, 0), "Spine1": (4, 0, 0),
            "Spine2": (2, 0, 0), "Neck": (-3, 0, 0), "Head": (-2, 0, 0),
            "LeftArm": (86, -41, -44), "RightArm": (86, 41, 44),
            "LeftForeArm": (32, 0, -10), "RightForeArm": (32, 0, 10),
            "LeftHand": (-8, 4, -5), "RightHand": (-8, -4, 5),
            "LeftUpLeg": (45, 7, 32), "RightUpLeg": (45, -7, -32),
            "LeftLeg": (-70, 0, 0), "RightLeg": (-70, 0, 0),
            "LeftFoot": (24, 0, 0), "RightFoot": (24, 0, 0),
        }, (0.0, 16.0, 0.0)),
        (72, {
            "Hips": (12, 0, 0), "Spine": (15, 0, 0), "Spine1": (11, 0, 0),
            "Spine2": (7, 0, 0), "Neck": (-10, 0, 0), "Head": (-12, 0, 0),
            "LeftArm": (95, -46, -46), "RightArm": (95, 46, 46),
            "LeftForeArm": (38, 0, -11), "RightForeArm": (38, 0, 11),
            "LeftHand": (-10, 5, -6), "RightHand": (-10, -5, 6),
            "LeftUpLeg": (58, 9, 44), "RightUpLeg": (58, -9, -44),
            "LeftLeg": (-92, 0, 0), "RightLeg": (-92, 0, 0),
            "LeftFoot": (34, 0, 0), "RightFoot": (34, 0, 0),
        }, (0.0, 20.0, 0.0)),
        (82, {
            "Hips": (0, 0, 0), "Spine": (4, 0, 0), "Spine1": (3, 0, 0),
            "Spine2": (1, 0, 0), "Neck": (-1, 0, 0), "Head": (1, 0, 0),
            "LeftArm": (88, -43, -44), "RightArm": (88, 43, 44),
            "LeftForeArm": (34, 0, -10), "RightForeArm": (34, 0, 10),
            "LeftHand": (-8, 4, -5), "RightHand": (-8, -4, 5),
            "LeftUpLeg": (55, 8, 40), "RightUpLeg": (55, -8, -40),
            "LeftLeg": (-85, 0, 0), "RightLeg": (-85, 0, 0),
            "LeftFoot": (30, 0, 0), "RightFoot": (30, 0, 0),
        }, (0.0, 30.0, 0.0)),
        (94, {
            "Hips": (2, 0, 0), "Spine": (8, 0, 0), "Spine1": (4, 0, 0),
            "Spine2": (0, 0, 0), "Neck": (-3, 0, 0), "Head": (0, 0, 0),
            "LeftArm": (90, -45, -45), "RightArm": (90, 45, 45),
            "LeftForeArm": (35, 0, -10), "RightForeArm": (35, 0, 10),
            "LeftHand": (-8, 4, -5), "RightHand": (-8, -4, 5),
            "LeftUpLeg": (55, 8, 42), "RightUpLeg": (55, -8, -42),
            "LeftLeg": (-85, 0, 0), "RightLeg": (-85, 0, 0),
            "LeftFoot": (30, 0, 0), "RightFoot": (30, 0, 0),
        }, (0.0, 24.0, 0.0)),
        (120, {
            "Hips": (2, 0, 0), "Spine": (8, 0, 0), "Spine1": (4, 0, 0),
            "Spine2": (0, 0, 0), "Neck": (-3, 0, 0), "Head": (0, 0, 0),
            "LeftArm": (90, -45, -45), "RightArm": (90, 45, 45),
            "LeftForeArm": (35, 0, -10), "RightForeArm": (35, 0, 10),
            "LeftHand": (-8, 4, -5), "RightHand": (-8, -4, 5),
            "LeftUpLeg": (55, 8, 42), "RightUpLeg": (55, -8, -42),
            "LeftLeg": (-85, 0, 0), "RightLeg": (-85, 0, 0),
            "LeftFoot": (30, 0, 0), "RightFoot": (30, 0, 0),
        }, (0.0, 25.0, 0.0)),
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
            # Each key is an intentional silhouette.  Clamped handles retain
            # smooth motion without overshooting into crossed limbs between
            # the reach, impact, and seated poses.
            point.handle_left_type = "AUTO_CLAMPED"
            point.handle_right_type = "AUTO_CLAMPED"


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _saddle_material(
    name: str,
    color: tuple[float, float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.55,
) -> bpy.types.Material:
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    # Blender localizes default node names (for example, the Japanese UI calls
    # this node "プリンシプルBSDF"), so identify it by type instead of name.
    shader = next(
        (node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"),
        None,
    )
    if shader is not None:
        shader.inputs["Base Color"].default_value = color
        shader.inputs["Metallic"].default_value = metallic
        shader.inputs["Roughness"].default_value = roughness
    return material


def _finish_saddle_mesh(
    obj: bpy.types.Object,
    armature: bpy.types.Object,
    source_mesh: bpy.types.Object,
    material: bpy.types.Material,
    bevel_width: float,
    rigid_attachment: bool = True,
    rigid_reference: tuple[float, float, float] | None = None,
) -> bpy.types.Object:
    """Bake a prop and copy the shark's local deformation weights onto it."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if bevel_width > 0.0:
        bevel = obj.modifiers.new("LowPolyBevel", "BEVEL")
        bevel.width = bevel_width
        bevel.segments = 2
        bevel.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=bevel.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    obj.data.materials.append(material)

    source_groups = {group.index: group.name for group in source_mesh.vertex_groups}
    deform_group_names = {bone.name for bone in armature.data.bones}
    object_to_source = source_mesh.matrix_world.inverted() @ obj.matrix_world
    depsgraph = bpy.context.evaluated_depsgraph_get()

    def surface_weights(point: Vector) -> dict[str, float]:
        hit, closest, _normal, face_index = source_mesh.closest_point_on_mesh(
            point, distance=100.0, depsgraph=depsgraph
        )
        if not hit:
            return {}
        polygon = source_mesh.data.polygons[face_index]
        source_vertices = [source_mesh.data.vertices[index] for index in polygon.vertices]
        if len(source_vertices) != 3:
            raise RuntimeError("The shark attachment surface must be triangulated")
        barycentric = barycentric_transform(
            closest,
            source_vertices[0].co, source_vertices[1].co, source_vertices[2].co,
            Vector((1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)),
            Vector((0.0, 0.0, 1.0)),
        )
        coefficients = [max(0.0, component) for component in barycentric]
        coefficient_total = sum(coefficients)
        if coefficient_total <= 0.0:
            return {}
        coefficients = [component / coefficient_total for component in coefficients]
        weights: dict[str, float] = {}
        for source_vertex, coefficient in zip(source_vertices, coefficients):
            for membership in source_vertex.groups:
                group_name = source_groups.get(membership.group)
                if group_name in deform_group_names:
                    weights[group_name] = (
                        weights.get(group_name, 0.0) + membership.weight * coefficient
                    )
        weight_total = sum(weights.values())
        if weight_total > 0.0:
            weights = {name: weight / weight_total for name, weight in weights.items()}
        return weights

    shared_weights: dict[str, float] | None = None
    if rigid_attachment:
        if rigid_reference is None:
            reference = sum((vertex.co for vertex in obj.data.vertices), Vector())
            reference /= max(1, len(obj.data.vertices))
            reference = object_to_source @ reference
        else:
            reference = source_mesh.matrix_world.inverted() @ Vector(rigid_reference)
        shared_weights = surface_weights(reference)

    destination_groups: dict[str, bpy.types.VertexGroup] = {}
    for vertex in obj.data.vertices:
        if shared_weights is None:
            weights = surface_weights(object_to_source @ vertex.co)
        else:
            weights = shared_weights
        for group_name, weight in weights.items():
            if weight <= 0.0:
                continue
            group = destination_groups.get(group_name)
            if group is None:
                group = obj.vertex_groups.new(name=group_name)
                destination_groups[group_name] = group
            group.add([vertex.index], weight, "REPLACE")

    if not destination_groups:
        raise RuntimeError(f"Could not transfer shark deformation weights to {obj.name}")
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    modifier = obj.modifiers.new("SharkBodyAttachment", "ARMATURE")
    modifier.object = armature
    obj["shark_saddle_accessory"] = True
    return obj


def _saddle_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    armature: bpy.types.Object,
    source_mesh: bpy.types.Object,
    material: bpy.types.Material,
    bevel_width: float,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    return _finish_saddle_mesh(obj, armature, source_mesh, material, bevel_width)


def _shark_surface_z(
    source_mesh: bpy.types.Object,
    x: float,
    y: float,
) -> float:
    """Raycast the rest-pose shark and return its upper surface in world space."""
    inverse = source_mesh.matrix_world.inverted()
    origin = inverse @ Vector((x, y, 2.5))
    direction = (inverse.to_3x3() @ Vector((0.0, 0.0, -1.0))).normalized()
    hit, location, _normal, _face = source_mesh.ray_cast(
        origin, direction, depsgraph=bpy.context.evaluated_depsgraph_get()
    )
    if not hit:
        raise RuntimeError(f"No shark surface below saddle sample ({x:.3f}, {y:.3f})")
    return (source_mesh.matrix_world @ location).z


def _saddle_conformed_layer(
    name: str,
    stations: list[tuple[float, float]],
    surface_offset: float,
    thickness: float,
    armature: bpy.types.Object,
    source_mesh: bpy.types.Object,
    material: bpy.types.Material,
    lateral_steps: int = 9,
) -> bpy.types.Object:
    """Build a layered saddle whose underside follows the shark vertex surface."""
    if lateral_steps < 3:
        raise ValueError("A conformed saddle layer needs at least three lateral samples")
    x_count = len(stations)
    layer_count = x_count * lateral_steps
    vertices: list[tuple[float, float, float]] = []
    for x, half_width in stations:
        for lateral_index in range(lateral_steps):
            factor = -1.0 + 2.0 * lateral_index / (lateral_steps - 1)
            y = half_width * factor
            surface_z = _shark_surface_z(source_mesh, x, y)
            vertices.append((x, y, surface_z + surface_offset))
    vertices += [(x, y, z + thickness) for x, y, z in vertices]

    faces: list[tuple[int, ...]] = []
    for x_index in range(x_count - 1):
        for y_index in range(lateral_steps - 1):
            a = x_index * lateral_steps + y_index
            b = a + 1
            c = a + lateral_steps + 1
            d = a + lateral_steps
            faces.append((d, c, b, a))
            faces.append((a + layer_count, b + layer_count,
                          c + layer_count, d + layer_count))
    for x_index in range(x_count - 1):
        left = x_index * lateral_steps
        next_left = left + lateral_steps
        faces.append((left, left + layer_count,
                      next_left + layer_count, next_left))
        right = left + lateral_steps - 1
        next_right = right + lateral_steps
        faces.append((next_right, next_right + layer_count,
                      right + layer_count, right))
    for y_index in range(lateral_steps - 1):
        rear = y_index
        faces.append((rear, rear + 1, rear + 1 + layer_count,
                      rear + layer_count))
        front = (x_count - 1) * lateral_steps + y_index
        faces.append((front + 1, front, front + layer_count,
                      front + 1 + layer_count))

    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return _finish_saddle_mesh(
        obj, armature, source_mesh, material, 0.0, rigid_attachment=False
    )


def _saddle_bar(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    armature: bpy.types.Object,
    source_mesh: bpy.types.Object,
    material: bpy.types.Material,
    vertices: int = 8,
    rigid_reference: tuple[float, float, float] = (1.48, 0.0, 0.45),
) -> bpy.types.Object:
    point_a = Vector(start)
    point_b = Vector(end)
    direction = point_b - point_a
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=direction.length,
        location=(point_a + point_b) * 0.5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return _finish_saddle_mesh(
        obj, armature, source_mesh, material, 0.012,
        rigid_attachment=True, rigid_reference=rigid_reference,
    )


def _build_shark_saddle(armature: bpy.types.Object) -> list[bpy.types.Object]:
    """Create a compact saddle and reachable handlebar at GhostMountSocket."""
    for obj in list(bpy.data.objects):
        if obj.name.startswith(SADDLE_PREFIX) or obj.get("shark_saddle_accessory"):
            bpy.data.objects.remove(obj, do_unlink=True)

    source_mesh = max(
        (
            obj for obj in bpy.data.objects
            if obj.type == "MESH" and not obj.name.startswith(SADDLE_PREFIX)
            and any(modifier.type == "ARMATURE" for modifier in obj.modifiers)
        ),
        key=lambda obj: len(obj.data.vertices),
    )
    old_pose_position = armature.data.pose_position
    armature.data.pose_position = "REST"
    bpy.context.view_layer.update()

    leather = _saddle_material(
        "M_SharkSaddle_Leather", (0.16, 0.026, 0.008, 1.0), roughness=0.62
    )
    cushion = _saddle_material(
        "M_SharkSaddle_Cushion", (0.34, 0.065, 0.014, 1.0), roughness=0.52
    )
    trim = _saddle_material(
        "M_SharkSaddle_Trim", (0.72, 0.22, 0.025, 1.0), metallic=0.30, roughness=0.32
    )
    metal = _saddle_material(
        "M_SharkSaddle_Metal", (0.035, 0.055, 0.075, 1.0), metallic=0.78, roughness=0.24
    )
    grip = _saddle_material(
        "M_SharkSaddle_Grip", (0.12, 0.025, 0.012, 1.0), roughness=0.72
    )

    created: list[bpy.types.Object] = []
    # Each layer is raycast onto the rest-pose shark mesh. The wide underlay
    # wraps down both sides, while the rear edge begins after the dorsal fin.
    created.append(_saddle_conformed_layer(
        f"{SADDLE_PREFIX}Trim",
        [(1.10, 0.28), (1.18, 0.48), (1.40, 0.56),
         (1.62, 0.50), (1.78, 0.32)],
        0.008, 0.035, armature, source_mesh, trim,
    ))
    created.append(_saddle_conformed_layer(
        f"{SADDLE_PREFIX}Pad",
        [(1.12, 0.25), (1.20, 0.44), (1.40, 0.50),
         (1.60, 0.45), (1.74, 0.29)],
        0.044, 0.070, armature, source_mesh, leather,
    ))
    created.append(_saddle_conformed_layer(
        f"{SADDLE_PREFIX}Seat",
        [(1.16, 0.17), (1.23, 0.30), (1.40, 0.34),
         (1.55, 0.29), (1.64, 0.18)],
        0.112, 0.055, armature, source_mesh, cushion,
    ))
    created.append(_saddle_box(
        f"{SADDLE_PREFIX}Cantle", (1.105, 0.0, 0.675), (0.12, 0.50, 0.18),
        armature, source_mesh, cushion, 0.050,
        (0.0, math.radians(-10.0), 0.0),
    ))

    # The final rider-pose wrists are transformed back through the authored
    # GhostMountSocket so both grip centers meet the palms in preview/runtime.
    # The bar is intentionally slanted in shark bind space: the mount socket's
    # orientation turns it into a level bar in the rider's local view.
    created.append(_saddle_bar(
        f"{SADDLE_PREFIX}HandlePost_L", (1.45, 0.28, 0.44), (1.49, 0.25, 0.70),
        0.045, armature, source_mesh, metal,
    ))
    created.append(_saddle_bar(
        f"{SADDLE_PREFIX}HandlePost_R", (1.47, -0.28, 0.44), (1.516, -0.17, 0.791),
        0.045, armature, source_mesh, metal,
    ))
    created.append(_saddle_bar(
        f"{SADDLE_PREFIX}HandleBar", (1.516, -0.17, 0.791), (1.49, 0.25, 0.70),
        0.050, armature, source_mesh, metal,
    ))
    created.append(_saddle_bar(
        f"{SADDLE_PREFIX}Grip_L", (1.49, 0.25, 0.70), (1.47, 0.42, 0.666),
        0.078, armature, source_mesh, grip,
    ))
    created.append(_saddle_bar(
        f"{SADDLE_PREFIX}Grip_R", (1.516, -0.17, 0.791), (1.528, -0.34, 0.825),
        0.078, armature, source_mesh, grip,
    ))
    created.append(_saddle_bar(
        f"{SADDLE_PREFIX}Collar_L", (1.492, 0.225, 0.705), (1.488, 0.275, 0.695),
        0.072, armature, source_mesh, trim,
    ))
    created.append(_saddle_bar(
        f"{SADDLE_PREFIX}Collar_R", (1.514, -0.145, 0.786), (1.518, -0.195, 0.796),
        0.072, armature, source_mesh, trim,
    ))
    armature.data.pose_position = old_pose_position
    bpy.context.view_layer.update()
    return created


def _add_shark_mount_preview() -> list[bpy.types.Object]:
    """Align the shark to the rider using the same base offset as Godot."""
    with bpy.data.libraries.load(str(SHARK_BLEND), link=False) as (source, target):
        # Append the authored shark scene as one unit. Mesh names can change
        # when the GLB is round-tripped (for example SK_Shark.001/Icosphere),
        # while the armature and socket hierarchy remains authoritative.
        target.objects = list(source.objects)
    imported = [obj for obj in target.objects if obj is not None]
    for obj in imported:
        if not obj.users_collection:
            bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    socket = next((obj for obj in imported if obj.name.startswith("GhostMountSocket")), None)
    if socket is None:
        raise RuntimeError("GhostMountSocket was not found in the shark preview GLB")

    # Godot's procedural rider subtracts BASE_Y from imported bone heights.
    # Raising only the preview shark by the inverse offset makes the Mixamo
    # reference body show the same contact height without contaminating export.
    socket_to_preview = (
        Matrix.Translation(Vector((0.0, 0.0, -GODOT_PROCEDURAL_BASE_Y)))
        @ socket.matrix_world.inverted()
    )
    for obj in imported:
        if obj.parent is None:
            obj.matrix_world = socket_to_preview @ obj.matrix_world
        obj["ghost_mount_preview"] = True
    bpy.context.view_layer.update()
    return imported


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

    bpy.ops.object.camera_add(location=(3.6, -5.4, 3.6))
    camera = bpy.context.object
    camera.data.lens = 58.0
    _look_at(camera, Vector((0.0, 0.0, 1.25)))
    scene.camera = camera

    shark_preview = _add_shark_mount_preview()

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for frame in PREVIEW_FRAMES:
        scene.frame_set(frame)
        # Frame 66 is the live controller's mount handoff, so review the
        # straddle against the shark from that exact first-contact key onward.
        show_shark = frame >= 66
        for obj in shark_preview:
            obj.hide_render = not show_shark
        if show_shark:
            camera.location = (3.6, -5.4, 3.6)
            _look_at(camera, Vector((0.0, 0.0, 1.25)))
        else:
            camera.location = (3.4, -5.2, 2.5)
            _look_at(camera, Vector((0.0, 0.0, 0.85)))
        scene.render.filepath = str(PREVIEW_DIR / f"heroic_{frame:03d}.png")
        bpy.ops.render.render(write_still=True)
    for obj in shark_preview:
        obj.hide_render = False
    scene.frame_set(FRAME_END)


def _build_character_action() -> None:
    # Start from Blender's factory-empty scene without resetting persistent
    # user preferences; this also works through the MCP safety sandbox.
    bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
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
    # Seat the rider on the shoulder/back transition, just ahead of the main
    # dorsal fin.  The previous local Y=0 placed the exported socket at X=2.0
    # in shark space, visibly on top of the head/gills.
    socket.location = (0.0, 0.75, 1.12)
    socket.rotation_euler = (0.0, 0.0, 0.0)

    _build_shark_saddle(armature)

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

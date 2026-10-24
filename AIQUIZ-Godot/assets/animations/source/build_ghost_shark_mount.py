"""Build the GOSTRIDER ghost shark assets: saddle, mount socket and shark clips.

Run inside the live Blender session (Higgsfield connector), not headless:
    ns = {"__name__": "ghost_mount_build", "__file__": r"<this file>"}
    exec(open(r"<this file>", encoding="utf-8").read(), ns)
    ns["main"]()

It opens assets/shark/source/shark_swim_with_jaw.blend, rebuilds the saddle,
the GhostMountSocket and the ghost-ride shark actions, saves the .blend and
exports assets/shark/shark_swim.glb.  The rider's own performance is authored on
an exact replica of the in-game block character in
assets/animations/source/ghost_rider/build_ghost_rider_performance.py, which
reads this saddle's grips and footrests as its IK targets.
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
SHARK_BLEND = ROOT / "assets" / "shark" / "source" / "shark_swim_with_jaw.blend"
SHARK_GLB = ROOT / "assets" / "shark" / "shark_swim.glb"

FPS = 30
SADDLE_PREFIX = "SharkSaddle_"
## Bone that carries GhostMountSocket and every rigid saddle part (seat area of the body).
SADDLE_RIGID_BONE = "body_02"


def _remove_numbered_backup(blend_path: Path) -> None:
    backup_path = blend_path.with_name(blend_path.name + "1")
    if backup_path.exists():
        backup_path.unlink()


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
    # Operators name new meshes in the UI language; keep exported names stable.
    obj.data.name = f"{obj.name}_Mesh"
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
    if rigid_attachment and SADDLE_RIGID_BONE in deform_group_names:
        # Rigid props ride one bone, the same one GhostMountSocket follows, so the
        # rider's palms and soles stay on the grips and footrests while the body bends.
        shared_weights = {SADDLE_RIGID_BONE: 1.0}
    elif rigid_attachment:
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
    for mesh in list(bpy.data.meshes):
        if mesh.name.startswith(SADDLE_PREFIX) and mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    # The skinned shark body of THIS armature (preview copies such as
    # BitePreview_Shark live outside the view layer and have no evaluated mesh).
    view_layer_objects = bpy.context.view_layer.objects
    source_mesh = max(
        (
            obj for obj in bpy.data.objects
            if obj.type == "MESH" and not obj.name.startswith(SADDLE_PREFIX)
            and obj.name in view_layer_objects
            and any(
                modifier.type == "ARMATURE" and modifier.object == armature
                for modifier in obj.modifiers
            )
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
    # The GOSTRIDER rider (assets/animations/source/ghost_rider) sits at
    # RIDER_SCALE 0.70 of these shark units in a forward-leaning jet-ski stance:
    # butt on the rear of a long seat, both palms on one level, symmetric
    # handlebar, and both soles on footrests that stand out from the flanks.
    # Each layer is raycast onto the rest-pose shark mesh. The wide underlay
    # wraps down both sides, while the rear edge begins after the dorsal fin.
    created.append(_saddle_conformed_layer(
        f"{SADDLE_PREFIX}Trim",
        [(1.02, 0.26), (1.10, 0.50), (1.30, 0.58),
         (1.52, 0.55), (1.70, 0.40), (1.78, 0.20)],
        0.008, 0.035, armature, source_mesh, trim,
    ))
    created.append(_saddle_conformed_layer(
        f"{SADDLE_PREFIX}Pad",
        [(1.04, 0.24), (1.12, 0.46), (1.30, 0.52),
         (1.50, 0.50), (1.67, 0.37), (1.75, 0.18)],
        0.044, 0.070, armature, source_mesh, leather,
    ))
    created.append(_saddle_conformed_layer(
        f"{SADDLE_PREFIX}Seat",
        [(1.07, 0.18), (1.13, 0.32), (1.26, 0.37),
         (1.42, 0.33), (1.56, 0.23), (1.64, 0.13)],
        0.112, 0.058, armature, source_mesh, cushion,
    ))
    created.append(_saddle_box(
        f"{SADDLE_PREFIX}Cantle", (1.055, 0.0, 0.705), (0.11, 0.50, 0.20),
        armature, source_mesh, cushion, 0.045,
        (0.0, math.radians(-12.0), 0.0),
    ))
    created.append(_saddle_box(
        f"{SADDLE_PREFIX}Fairing", (1.685, 0.0, 0.595), (0.17, 0.26, 0.13),
        armature, source_mesh, trim, 0.035,
        (0.0, math.radians(18.0), 0.0),
    ))

    # One stem and a level, symmetric bar. The grips sit where the rider's IK
    # palms land in the hold pose: (1.74, +-0.36, 0.88) in rest shark space.
    bar_reference = (1.66, 0.0, 0.47)
    created.append(_saddle_bar(
        f"{SADDLE_PREFIX}HandleStem", (1.66, 0.0, 0.56), (1.732, 0.0, 0.87),
        0.040, armature, source_mesh, metal, rigid_reference=bar_reference,
    ))
    created.append(_saddle_bar(
        f"{SADDLE_PREFIX}HandleBar", (1.74, -0.27, 0.88), (1.74, 0.27, 0.88),
        0.032, armature, source_mesh, metal, rigid_reference=bar_reference,
    ))
    created.append(_saddle_box(
        f"{SADDLE_PREFIX}HandleClamp", (1.737, 0.0, 0.877), (0.085, 0.13, 0.075),
        armature, source_mesh, trim, 0.018,
    ))
    for side, sign in (("L", 1.0), ("R", -1.0)):
        created.append(_saddle_bar(
            f"{SADDLE_PREFIX}Grip_{side}", (1.74, sign * 0.262, 0.88), (1.74, sign * 0.458, 0.88),
            0.050, armature, source_mesh, grip, rigid_reference=bar_reference,
        ))
        created.append(_saddle_bar(
            f"{SADDLE_PREFIX}Collar_{side}", (1.74, sign * 0.250, 0.88), (1.74, sign * 0.268, 0.88),
            0.058, armature, source_mesh, trim, rigid_reference=bar_reference,
        ))
        created.append(_saddle_bar(
            f"{SADDLE_PREFIX}BarEnd_{side}", (1.74, sign * 0.455, 0.88), (1.74, sign * 0.482, 0.88),
            0.058, armature, source_mesh, trim, rigid_reference=bar_reference,
        ))
        # Footrest: a step plate with an outer lip on a short bracket.
        peg_reference = (1.46, sign * 0.42, 0.22)
        created.append(_saddle_bar(
            f"{SADDLE_PREFIX}FootBracket_{side}", (1.46, sign * 0.40, 0.14), (1.46, sign * 0.60, 0.192),
            0.030, armature, source_mesh, metal, rigid_reference=peg_reference,
        ))
        created.append(_saddle_box(
            f"{SADDLE_PREFIX}Footrest_{side}", (1.46, sign * 0.585, 0.21), (0.30, 0.34, 0.035),
            armature, source_mesh, metal, 0.012,
        ))
        created.append(_saddle_box(
            f"{SADDLE_PREFIX}FootLip_{side}", (1.46, sign * 0.742, 0.235), (0.30, 0.03, 0.06),
            armature, source_mesh, trim, 0.010,
        ))
    armature.data.pose_position = old_pose_position
    bpy.context.view_layer.update()
    return created


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
        for bone_name in ("root", "body_01", "body_02", "tail_01", "tail_02", "tail_03"):
            armature.pose.bones[bone_name].keyframe_insert("rotation_euler", frame=frame, group=bone_name)
    # Same convention as rebuild_shark_animation.py: Godot drives the jaw, and
    # explicit neutral head/fin keys prevent stale poses after a clip switch.
    for bone_name in ("head", "pectoral.L", "pectoral.R"):
        pose_bone = armature.pose.bones.get(bone_name)
        if pose_bone is None:
            continue
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.keyframe_insert("rotation_euler", frame=keys[0][0], group=bone_name)
        pose_bone.keyframe_insert("rotation_euler", frame=frame_end, group=bone_name)
    action.frame_start = 1
    action.frame_end = frame_end
    action.use_fake_user = True
    _set_bezier_interpolation(action)
    return action


def _build_shark_actions(open_file: bool = True) -> None:
    """open_file=False builds into the already-open shark .blend (the live
    session opens it in a separate call so operators get a fresh UI context)."""
    bpy.context.preferences.filepaths.save_version = 0
    if open_file:
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
    # Shark bones: X bends the body behind a joint up (+) / down (-), Z swings it
    # toward starboard (+) / port (-).  The rider rides body_02 (see SADDLE_RIGID_BONE).
    # Played at 1.0x from the rider's first contact: the back gives under the
    # landing, the tail kicks up, then two decaying side wiggles settle it.
    receive = _key_shark_action(armature, "GhostMountReceive", [
        (1, {}),
        (3, {"body_01": (5, 0, 0), "body_02": (7, 0, 0), "tail_01": (8, 0, 0), "tail_02": (6, 0, 0), "tail_03": (4, 0, 0)}),
        (7, {"body_01": (-3, 0, 3), "body_02": (-4, 0, -4), "tail_01": (-6, 0, 10), "tail_02": (-4, 0, -14), "tail_03": (-3, 0, 18)}),
        (12, {"body_01": (2, 0, -3), "body_02": (2, 0, 3), "tail_01": (3, 0, -8), "tail_02": (2, 0, 10), "tail_03": (1, 0, -14)}),
        (18, {"body_01": (0, 0, 1), "body_02": (0, 0, -1), "tail_01": (0, 0, 4), "tail_02": (0, 0, -6), "tail_03": (0, 0, 8)}),
        (26, {"tail_01": (0, 0, -2), "tail_02": (0, 0, 2), "tail_03": (0, 0, -3)}),
        (36, {}),
    ], 36)
    # BEAM_REVEAL (3.59 s): brace, a full-body shudder when the pillar fires at
    # 0.20 s, a sustained power tremor while it stands, calm while the camera
    # shake decays, then strong tail strokes through the 1.40 s vertical ascent.
    beam_keys: list[tuple[int, dict[str, tuple[float, float, float]]]] = [
        (1, {}),
        (5, {"body_01": (3, 0, 0), "tail_01": (-4, 0, 0)}),
        (8, {"body_01": (-7, 0, 4), "body_02": (-5, 0, -6), "tail_01": (8, 0, 14), "tail_02": (6, 0, -18), "tail_03": (4, 0, 24)}),
        (11, {"body_01": (-5, 0, -4), "body_02": (-4, 0, 5), "tail_01": (6, 0, -12), "tail_02": (5, 0, 16), "tail_03": (3, 0, -22)}),
    ]
    tremor = 1.0
    for index, frame in enumerate(range(14, 53, 3)):
        side = 1.0 if index % 2 == 0 else -1.0
        tremor = 1.0 - 0.5 * (frame - 14) / 38.0
        beam_keys.append((frame, {
            "body_01": (-5, 0, 1.5 * side * tremor),
            "body_02": (-3, 0, -3 * side * tremor),
            "tail_01": (4, 0, 8 * side * tremor),
            "tail_02": (3, 0, -10 * side * tremor),
            "tail_03": (2, 0, 12 * side * tremor),
        }))
    beam_keys += [
        (56, {"body_01": (-2, 0, 0), "tail_01": (1, 0, 2), "tail_02": (0, 0, -3), "tail_03": (0, 0, 4)}),
        (66, {}),
    ]
    for index, frame in enumerate(range(72, 108, 6)):
        side = 1.0 if index % 2 == 0 else -1.0
        beam_keys.append((frame, {
            "body_01": (-2, 0, -4 * side),
            "body_02": (0, 0, 6 * side),
            "tail_01": (0, 0, -14 * side),
            "tail_02": (0, 0, 20 * side),
            "tail_03": (0, 0, -28 * side),
        }))
    beam_keys.append((108, {}))
    beam_power = _key_shark_action(armature, "GhostBeamPower", beam_keys, 108)
    departure = _key_shark_action(armature, "GhostDeparture", [
        (1, {"root": (0, -4, 0), "body_01": (0, 8, 4), "body_02": (0, 6, -7), "tail_01": (0, -4, 13), "tail_02": (0, -3, -19), "tail_03": (0, -2, 25), "jaw": (0, 2, 0)}),
        (7, {"root": (0, -8, 0), "body_01": (0, 12, 6), "body_02": (0, 9, -10), "tail_01": (0, -7, 18), "tail_02": (0, -5, -27), "tail_03": (0, -3, 34), "jaw": (0, 1, 0)}),
        (14, {"root": (0, 9, 0), "body_01": (0, -14, -7), "body_02": (0, -10, 11), "tail_01": (0, 8, -20), "tail_02": (0, 6, 29), "tail_03": (0, 3, -37), "jaw": (0, 8, 0)}),
        (24, {"root": (0, 3, 0), "body_01": (0, -5, -3), "body_02": (0, -4, 5), "tail_01": (0, 4, -11), "tail_02": (0, 3, 16), "tail_03": (0, 2, -21), "jaw": (0, 5, 0)}),
        (38, {"root": (0, -2, 0), "body_01": (0, 3, 2), "body_02": (0, 2, -3), "tail_01": (0, -2, 8), "tail_02": (0, -2, -12), "tail_03": (0, -1, 16), "jaw": (0, 2, 0)}),
        (54, {"body_01": (0, -2, -3), "body_02": (0, 2, 4), "tail_01": (0, 2, -9), "tail_02": (0, 1, 13), "tail_03": (0, 1, -18), "jaw": (0, 1, 0)}),
        (66, {"body_01": (0, 0, 0), "body_02": (0, 0, 0), "tail_01": (0, 0, 0), "tail_02": (0, 0, 0), "tail_03": (0, 0, 0), "jaw": (0, 0, 0)}),
    ], 66)
    # SharkSwim and SharkBite belong to rebuild_shark_animation.py; keep them as they are.
    if bpy.data.actions.get("SharkBite") is None:
        raise RuntimeError("SharkBite is missing; run rebuild_shark_animation.py first")

    # A named authored socket is exported as a normal node and replaces the
    # previous bounds-derived seat guess in Godot.
    socket = bpy.data.objects.get("GhostMountSocket")
    if socket is None:
        socket = bpy.data.objects.new("GhostMountSocket", None)
        bpy.context.scene.collection.objects.link(socket)
    socket.empty_display_type = "ARROWS"
    socket.empty_display_size = 0.35
    # Seat the rider on the shoulder/back transition, just ahead of the main
    # dorsal fin, at rest (1.25, 0, 0.72) with the same axes as before
    # (+X port, -Y toward the head, +Z up).  The socket rides the seat-area bone
    # (SADDLE_RIGID_BONE) like the rigid grips and footrests, so the GOSTRIDER
    # rider keeps its contacts while the shark bends.
    old_pose_position = armature.data.pose_position
    armature.data.pose_position = "REST"
    bpy.context.view_layer.update()
    socket.parent = armature
    socket.parent_type = "BONE"
    socket.parent_bone = SADDLE_RIGID_BONE
    socket.rotation_mode = "XYZ"
    bpy.context.view_layer.update()
    socket.matrix_world = (
        Matrix.Translation(Vector((1.25, 0.0, 0.72)))
        @ Matrix.Rotation(math.radians(90.0), 4, "Z")
    )
    bpy.context.view_layer.update()
    armature.data.pose_position = old_pose_position

    _build_shark_saddle(armature)

    # Put one action on each NLA track. Blender 5.1's glTF exporter otherwise
    # filters compatible-but-inactive actions too aggressively for this rig.
    armature.animation_data.action = None
    while armature.animation_data.nla_tracks:
        armature.animation_data.nla_tracks.remove(armature.animation_data.nla_tracks[0])
    for action in (
        bpy.data.actions.get("SharkSwim"), rendezvous, receive, beam_power, departure,
        bpy.data.actions.get("SharkBite"),
    ):
        if action is None:
            continue
        track = armature.animation_data.nla_tracks.new()
        track.name = action.name
        # Like rebuild_shark_animation.py: the swim loop and the bite start at
        # time zero (no one-frame hold); the ghost clips keep their timing.
        start = 0 if action.name in ("SharkSwim", "SharkBite") else int(action.frame_start)
        strip = track.strips.new(action.name, start, action)
        strip.name = action.name
        strip.extrapolation = "NOTHING"
    scene.frame_start = 1
    scene.frame_end = 120
    # Export exactly like rebuild_shark_animation.py: the rig and its children
    # (mesh, saddle, GhostMountSocket) of the active scene only.
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    selected = [armature] + [obj for obj in scene.objects if obj.parent == armature]
    visibility = {obj: (obj.hide_get(), obj.hide_render) for obj in selected}
    for obj in selected:
        obj.hide_set(False)
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(SHARK_GLB),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_animations=True,
        export_skins=True,
        export_animation_mode="NLA_TRACKS",
        export_merge_animation="NLA_TRACK",
        export_force_sampling=True,
        export_frame_range=False,
        export_apply=False,
        export_yup=True,
    )
    for obj, (hidden, hidden_render) in visibility.items():
        obj.hide_set(hidden)
        obj.hide_render = hidden_render
    # The saved source plays one action, with no overlapping NLA tracks.
    while armature.animation_data.nla_tracks:
        armature.animation_data.nla_tracks.remove(armature.animation_data.nla_tracks[0])
    armature.animation_data.action = bpy.data.actions.get("SharkSwim")
    scene.frame_start, scene.frame_end = 1, 48
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(SHARK_BLEND))
    _remove_numbered_backup(SHARK_BLEND)


def main() -> None:
    # Keep regeneration deterministic and avoid committing Blender's numbered
    # backup copies beside the authored source files.
    bpy.context.preferences.filepaths.save_version = 0
    _build_shark_actions()
    print(f"Updated {SHARK_BLEND}")
    print(f"Updated {SHARK_GLB}")


if __name__ == "__main__":
    main()

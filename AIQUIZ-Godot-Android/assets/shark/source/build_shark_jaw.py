"""Rebuild the shark GLB with a rigged jaw while preserving the swim action.

Run with Blender 5.x:
  blender --background --factory-startup --python build_shark_jaw.py

The script imports ../shark_swim.glb, adds a jaw bone and weights the lower
front of the existing mesh, saves an editable .blend source, then exports the
runtime GLB in place.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy


SOURCE_DIR = Path(__file__).resolve().parent
SHARK_DIR = SOURCE_DIR.parent
GLB_PATH = SHARK_DIR / "shark_swim.glb"
BLEND_PATH = SOURCE_DIR / "shark_swim_with_jaw.blend"
JAW_BONE_NAME = "jaw"


def _clear_scene() -> None:
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def _find_rig() -> tuple[bpy.types.Object, bpy.types.Object]:
    armature = next((obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"), None)
    mesh = next(
        (
            obj
            for obj in bpy.context.scene.objects
            if obj.type == "MESH" and any(mod.type == "ARMATURE" for mod in obj.modifiers)
        ),
        None,
    )
    if armature is None or mesh is None:
        raise RuntimeError("Imported shark rig or skinned mesh was not found")
    return armature, mesh


def _ensure_jaw_bone(armature: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bones = armature.data.edit_bones
    jaw = bones.get(JAW_BONE_NAME)
    if jaw is None:
        jaw = bones.new(JAW_BONE_NAME)
    # Shark local axes: +X points toward the nose, +Z points upward.
    jaw.head = (3.18, 0.0, -0.34)
    jaw.tail = (4.28, 0.0, -0.34)
    jaw.parent = bones.get("root")
    jaw.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")


def _jaw_weight(co) -> float:
    """Return a smooth lower-jaw weight for one rest-pose vertex."""
    if co.x <= 3.08:
        return 0.0
    # The threshold follows the mouth line toward the nose. It excludes the
    # upper snout and blends into the cheek at the hinge to avoid a hard seam.
    mouth_line = -0.37 + (co.x - 3.08) * 0.085
    if co.z >= mouth_line:
        return 0.0
    front = min(max((co.x - 3.08) / 0.46, 0.0), 1.0)
    below = min(max((mouth_line - co.z) / 0.18, 0.0), 1.0)
    return min(front * below, 1.0)


def _assign_jaw_weights(mesh: bpy.types.Object) -> int:
    group = mesh.vertex_groups.get(JAW_BONE_NAME) or mesh.vertex_groups.new(name=JAW_BONE_NAME)
    assigned = 0
    for vertex in mesh.data.vertices:
        weight = _jaw_weight(vertex.co)
        if weight <= 0.001:
            continue
        # Keep normalized deformation: scale the original body weights down
        # by the jaw contribution, then assign the remainder to the jaw.
        existing = [(item.group, item.weight) for item in vertex.groups if item.group != group.index]
        for group_index, old_weight in existing:
            mesh.vertex_groups[group_index].add([vertex.index], old_weight * (1.0 - weight), "REPLACE")
        group.add([vertex.index], weight, "REPLACE")
        assigned += 1
    if assigned < 24:
        raise RuntimeError(f"Jaw selection was unexpectedly small: {assigned} vertices")
    return assigned


def _add_preview_pose(armature: bpy.types.Object) -> None:
    """Store a reusable authoring pose; Godot drives the bone procedurally."""
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    jaw = armature.pose.bones.get(JAW_BONE_NAME)
    if jaw is None:
        raise RuntimeError("Jaw pose bone was not created")
    jaw.rotation_mode = "XYZ"
    jaw.rotation_euler.y = math.radians(0.0)
    jaw["arcade_open_angle_degrees"] = 28.0
    bpy.ops.object.mode_set(mode="OBJECT")


def _save_and_export(armature: bpy.types.Object, mesh: bpy.types.Object) -> None:
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_skins=True,
        export_animations=True,
        export_yup=True,
    )


def main() -> None:
    if not GLB_PATH.exists():
        raise FileNotFoundError(GLB_PATH)
    _clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(GLB_PATH))
    armature, mesh = _find_rig()
    _ensure_jaw_bone(armature)
    assigned = _assign_jaw_weights(mesh)
    _add_preview_pose(armature)
    _save_and_export(armature, mesh)
    print(f"SHARK_JAW_BUILD_OK jaw_vertices={assigned} blend={BLEND_PATH} glb={GLB_PATH}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"SHARK_JAW_BUILD_FAILED: {exc}", file=sys.stderr)
        raise

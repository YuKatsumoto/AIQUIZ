"""Inspect and build a lightweight grandstand GLB with Blender.

Run with:
  blender --background --factory-startup --python optimize_grandstand.py -- \
    --input path/to/source.glb --output path/to/optimized.glb
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

import bpy


DECIMATE_RATIOS = {
    "Grandstand_Aisle_Steps": 0.50,
    "Grandstand_Architectural_Lights": 0.65,
    "Grandstand_Concrete_Structure": 0.55,
    "Grandstand_Glass": 1.00,
    "Grandstand_Primary_Steel": 0.50,
    "Grandstand_Railings": 0.35,
    "Grandstand_Roof": 0.80,
    "Grandstand_Seats_LOD0": 0.06,
    "Grandstand_Secondary_Steel": 0.35,
    "Grandstand_Signage": 1.00,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--inspect-only", action="store_true")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])


def mesh_report(label: str) -> None:
    print(f"GRANDSTAND_MESH_REPORT {label}")
    total_vertices = 0
    total_triangles = 0
    for obj in sorted(
        (item for item in bpy.context.scene.objects if item.type == "MESH"),
        key=lambda item: item.name,
    ):
        mesh = obj.data
        mesh.calc_loop_triangles()
        vertex_count = len(mesh.vertices)
        triangle_count = len(mesh.loop_triangles)
        total_vertices += vertex_count
        total_triangles += triangle_count
        dimensions = tuple(round(value, 3) for value in obj.dimensions)
        print(
            f"{obj.name}: vertices={vertex_count} triangles={triangle_count} "
            f"materials={len(mesh.materials)} dimensions={dimensions}"
        )
    print(f"TOTAL vertices={total_vertices} triangles={total_triangles}")


def optimize_meshes() -> None:
    for obj in sorted(
        (item for item in bpy.context.scene.objects if item.type == "MESH"),
        key=lambda item: item.name,
    ):
        ratio = DECIMATE_RATIOS.get(obj.name, 1.0)
        if ratio >= 0.999:
            print(f"KEEP {obj.name}: ratio={ratio:.2f}")
            continue

        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        modifier = obj.modifiers.new(name="MobileLOD_Decimate", type="DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = ratio
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
        print(f"DECIMATE {obj.name}: ratio={ratio:.2f}")


def export_glb(output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output_path.resolve()),
        export_format="GLB",
        export_apply=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    print(f"EXPORTED {output_path.resolve()}")


def main() -> None:
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.input.resolve()))
    mesh_report("SOURCE")
    if args.inspect_only:
        return
    if args.output is None:
        raise SystemExit("--output is required unless --inspect-only is used")
    optimize_meshes()
    mesh_report("OPTIMIZED")
    export_glb(args.output)


if __name__ == "__main__":
    main()

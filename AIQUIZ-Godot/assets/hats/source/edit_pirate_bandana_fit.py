"""Reshape only the pirate hat's head band from a round profile to a square one."""

import math
from pathlib import Path

import bpy


PROJECT_ROOT = Path(r"C:\AIQUIZ\AIQUIZ-Godot")
SOURCE_GLB = PROJECT_ROOT / "assets" / "hats" / "source" / "pirate_hat_original.glb"
OUTPUT_BLEND = PROJECT_ROOT / "assets" / "hats" / "source" / "pirate_hat_bandana_square_fit.blend"
OUTPUT_GLB = PROJECT_ROOT / "assets" / "hats" / "pirate_hat.glb"

# In the original Poly model, these are the 96 faces making up the red band
# around the head. The knot and hanging cloth use separate face ranges and are
# deliberately left unchanged.
BAND_POLYGON_FIRST = 424
BAND_POLYGON_LAST = 519
EXPECTED_POLYGON_COUNT = 584
EXPECTED_BAND_FACE_COUNT = 96


def square_project_xy(x: float, y: float) -> tuple[float, float]:
    """Project a circular horizontal profile onto an equal-half-width square."""
    radius = math.hypot(x, y)
    if radius < 1.0e-6:
        return x, y
    unit_x = x / radius
    unit_y = y / radius
    scale = 1.0 / max(abs(unit_x), abs(unit_y))
    return x * scale, y * scale


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE_GLB))

mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if len(mesh_objects) != 1:
    raise RuntimeError(f"Expected one mesh object, found {len(mesh_objects)}")

pirate_hat = mesh_objects[0]
mesh = pirate_hat.data
if len(mesh.polygons) != EXPECTED_POLYGON_COUNT:
    raise RuntimeError(
        f"Unexpected pirate-hat topology: {len(mesh.polygons)} polygons; "
        f"expected {EXPECTED_POLYGON_COUNT}"
    )

band_polygons = [
    polygon
    for polygon in mesh.polygons
    if BAND_POLYGON_FIRST <= polygon.index <= BAND_POLYGON_LAST
]
if len(band_polygons) != EXPECTED_BAND_FACE_COUNT:
    raise RuntimeError(
        f"Expected {EXPECTED_BAND_FACE_COUNT} band faces, found {len(band_polygons)}"
    )

band_vertex_indices = {
    vertex_index
    for polygon in band_polygons
    for vertex_index in polygon.vertices
}

before_max_x = max(abs(mesh.vertices[index].co.x) for index in band_vertex_indices)
before_max_y = max(abs(mesh.vertices[index].co.y) for index in band_vertex_indices)

for vertex_index in band_vertex_indices:
    vertex = mesh.vertices[vertex_index]
    vertex.co.x, vertex.co.y = square_project_xy(vertex.co.x, vertex.co.y)

mesh.update()
after_max_x = max(abs(mesh.vertices[index].co.x) for index in band_vertex_indices)
after_max_y = max(abs(mesh.vertices[index].co.y) for index in band_vertex_indices)

pirate_hat.name = "PirateHat_BandanaSquareFit"
mesh.name = "PirateHat_BandanaSquareFit_Mesh"
pirate_hat["aiquiz_edit"] = "Square-fit red head band; knot and tails unchanged"
pirate_hat["aiquiz_band_faces"] = f"{BAND_POLYGON_FIRST}-{BAND_POLYGON_LAST}"

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
bpy.ops.object.select_all(action="SELECT")
bpy.context.view_layer.objects.active = pirate_hat
bpy.ops.export_scene.gltf(
    filepath=str(OUTPUT_GLB),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)

print(
    "PIRATE_BANDANA_SQUARE_FIT_OK "
    f"faces={len(band_polygons)} vertices={len(band_vertex_indices)} "
    f"before_half_extents=({before_max_x:.6f},{before_max_y:.6f}) "
    f"after_half_extents=({after_max_x:.6f},{after_max_y:.6f}) "
    f"blend={OUTPUT_BLEND} glb={OUTPUT_GLB}"
)

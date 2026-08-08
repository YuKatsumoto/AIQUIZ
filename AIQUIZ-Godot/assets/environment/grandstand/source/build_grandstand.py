"""Build the original AIQUIZ ocean grandstand and export a game-ready GLB.

Run inside Blender. The script is deterministic and keeps the editable .blend,
the exported GLB, embedded PBR textures, and two review renders in the project.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector


SCRIPT_DIR = Path(__file__).resolve().parent
ASSET_DIR = SCRIPT_DIR.parent
TEXTURE_DIR = SCRIPT_DIR / "textures"
PREVIEW_DIR = SCRIPT_DIR / "previews"
BLEND_PATH = SCRIPT_DIR / "aiquiz_ocean_grandstand.blend"
GLB_PATH = ASSET_DIR / "aiquiz_ocean_grandstand.glb"

TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

for datablocks in (
    bpy.data.objects,
    bpy.data.meshes,
    bpy.data.curves,
    bpy.data.materials,
    bpy.data.cameras,
    bpy.data.lights,
):
    for datablock in list(datablocks):
        datablocks.remove(datablock, do_unlink=True)

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.look = "AgX - Medium High Contrast"


def new_collection(name: str) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    scene.collection.children.link(collection)
    return collection


export_collection = new_collection("AIQUIZ_Grandstand_EXPORT")
preview_collection = new_collection("AIQUIZ_Grandstand_PREVIEW")


def move_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)


def principled_material(
    name: str,
    color: tuple[float, float, float, float],
    *,
    metallic: float = 0.0,
    roughness: float = 0.5,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
    alpha: float = 1.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = color
    nodes = material.node_tree.nodes
    shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if "Alpha" in shader.inputs:
        shader.inputs["Alpha"].default_value = alpha
    if emission is not None:
        emission_socket = shader.inputs.get("Emission Color") or shader.inputs.get("Emission")
        strength_socket = shader.inputs.get("Emission Strength")
        if emission_socket:
            emission_socket.default_value = emission
        if strength_socket:
            strength_socket.default_value = emission_strength
    if alpha < 1.0:
        material.diffuse_color = (*color[:3], alpha)
        if hasattr(material, "surface_render_method"):
            material.surface_render_method = "DITHERED"
        elif hasattr(material, "blend_method"):
            material.blend_method = "BLEND"
        material.use_transparency_overlap = False
    return material


def generate_concrete_textures() -> tuple[Path, Path, Path]:
    size = 1024
    rng = np.random.default_rng(7302026)
    fine = rng.normal(0.0, 1.0, (size, size)).astype(np.float32)
    coarse_small = rng.normal(0.0, 1.0, (64, 64)).astype(np.float32)
    coarse = np.repeat(np.repeat(coarse_small, size // 64, axis=0), size // 64, axis=1)
    medium_small = rng.normal(0.0, 1.0, (256, 256)).astype(np.float32)
    medium = np.repeat(np.repeat(medium_small, 4, axis=0), 4, axis=1)
    height = coarse * 0.50 + medium * 0.30 + fine * 0.20
    height = (height - height.min()) / max(1e-6, height.max() - height.min())
    streak = np.sin(np.linspace(0.0, math.tau * 9.0, size, dtype=np.float32))[:, None]
    height = np.clip(height * 0.90 + streak * 0.018, 0.0, 1.0)

    base = np.zeros((size, size, 4), dtype=np.float32)
    gray = np.clip(0.43 + (height - 0.5) * 0.18, 0.25, 0.62)
    base[..., 0] = gray * 0.98
    base[..., 1] = gray
    base[..., 2] = gray * 1.03
    base[..., 3] = 1.0

    rough = np.zeros_like(base)
    rough_gray = np.clip(0.72 + (height - 0.5) * 0.20, 0.52, 0.92)
    rough[..., :3] = rough_gray[..., None]
    rough[..., 3] = 1.0

    grad_y, grad_x = np.gradient(height)
    normal = np.zeros_like(base)
    normal[..., 0] = np.clip(0.5 - grad_x * 4.0, 0.0, 1.0)
    normal[..., 1] = np.clip(0.5 - grad_y * 4.0, 0.0, 1.0)
    normal[..., 2] = 1.0
    normal[..., 3] = 1.0

    outputs = []
    for filename, pixels in (
        ("grandstand_concrete_basecolor.png", base),
        ("grandstand_concrete_roughness.png", rough),
        ("grandstand_concrete_normal.png", normal),
    ):
        path = TEXTURE_DIR / filename
        image = bpy.data.images.new(filename, width=size, height=size, alpha=True)
        image.pixels.foreach_set(pixels.ravel())
        image.filepath_raw = str(path)
        image.file_format = "PNG"
        image.save()
        bpy.data.images.remove(image)
        outputs.append(path)
    return tuple(outputs)


def textured_concrete_material() -> bpy.types.Material:
    base_path, roughness_path, normal_path = generate_concrete_textures()
    material = bpy.data.materials.new("Concrete_PBR")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 0.76

    tex_base = nodes.new("ShaderNodeTexImage")
    tex_base.name = "Concrete Base Color"
    tex_base.image = bpy.data.images.load(str(base_path), check_existing=True)
    links.new(tex_base.outputs["Color"], shader.inputs["Base Color"])

    tex_rough = nodes.new("ShaderNodeTexImage")
    tex_rough.name = "Concrete Roughness"
    tex_rough.image = bpy.data.images.load(str(roughness_path), check_existing=True)
    tex_rough.image.colorspace_settings.name = "Non-Color"
    links.new(tex_rough.outputs["Color"], shader.inputs["Roughness"])

    tex_normal = nodes.new("ShaderNodeTexImage")
    tex_normal.name = "Concrete Normal"
    tex_normal.image = bpy.data.images.load(str(normal_path), check_existing=True)
    tex_normal.image.colorspace_settings.name = "Non-Color"
    normal_node = nodes.new("ShaderNodeNormalMap")
    normal_node.inputs["Strength"].default_value = 0.28
    links.new(tex_normal.outputs["Color"], normal_node.inputs["Color"])
    links.new(normal_node.outputs["Normal"], shader.inputs["Normal"])
    return material


concrete = textured_concrete_material()
concrete_light = principled_material("Concrete_Light", (0.62, 0.65, 0.69, 1.0), roughness=0.74)
steel = principled_material("Steel_Anthracite", (0.055, 0.072, 0.095, 1.0), metallic=0.88, roughness=0.25)
steel_secondary = principled_material("Steel_Secondary", (0.14, 0.18, 0.24, 1.0), metallic=0.76, roughness=0.31)
aluminum = principled_material("Brushed_Aluminum", (0.48, 0.55, 0.62, 1.0), metallic=0.92, roughness=0.23)
roof_material = principled_material("Roof_Pearl", (0.72, 0.79, 0.86, 1.0), metallic=0.58, roughness=0.28)
glass = principled_material("Booth_Glass", (0.055, 0.22, 0.32, 0.34), metallic=0.08, roughness=0.10, alpha=0.34)
interior = principled_material("Booth_Interior", (0.025, 0.035, 0.055, 1.0), metallic=0.16, roughness=0.42)
seat_blue = principled_material("Seat_Ocean_Blue", (0.015, 0.25, 0.78, 1.0), metallic=0.06, roughness=0.29)
seat_cyan = principled_material("Seat_Electric_Cyan", (0.015, 0.72, 0.88, 1.0), metallic=0.04, roughness=0.27)
seat_violet = principled_material("Seat_Violet", (0.30, 0.07, 0.78, 1.0), metallic=0.05, roughness=0.30)
seat_gold = principled_material("Seat_Champion_Gold", (0.96, 0.49, 0.045, 1.0), metallic=0.14, roughness=0.30)
sign_blue = principled_material("Sign_Blue", (0.01, 0.12, 0.42, 1.0), metallic=0.25, roughness=0.28)
sign_cyan = principled_material(
    "Sign_Cyan_Emission",
    (0.0, 0.74, 1.0, 1.0),
    metallic=0.08,
    roughness=0.20,
    emission=(0.0, 0.40, 1.0, 1.0),
    emission_strength=4.0,
)
light_material = principled_material(
    "Architectural_Light",
    (0.78, 0.93, 1.0, 1.0),
    roughness=0.17,
    emission=(0.45, 0.82, 1.0, 1.0),
    emission_strength=7.0,
)
subtitle_material = principled_material(
    "Subtitle_Silver_Emission",
    (0.62, 0.78, 0.94, 1.0),
    metallic=0.42,
    roughness=0.24,
    emission=(0.18, 0.46, 0.86, 1.0),
    emission_strength=1.25,
)
rubber = principled_material("Rubber_Dark", (0.012, 0.016, 0.022, 1.0), roughness=0.72)


def add_box(
    name: str,
    location: tuple[float, float, float],
    size: tuple[float, float, float],
    material: bpy.types.Material,
    *,
    bevel: float = 0.0,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    collection: bpy.types.Collection = export_collection,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Edge Softening", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.materials.append(material)
    move_to_collection(obj, collection)
    return obj


def add_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material: bpy.types.Material,
    *,
    vertices: int = 16,
    collection: bpy.types.Collection = export_collection,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(material)
    move_to_collection(obj, collection)
    return obj


def add_beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    thickness: float,
    material: bpy.types.Material,
    *,
    collection: bpy.types.Collection = export_collection,
) -> bpy.types.Object:
    p0 = Vector(start)
    p1 = Vector(end)
    delta = p1 - p0
    obj = add_box(name, tuple((p0 + p1) * 0.5), (thickness, thickness, delta.length), material, bevel=thickness * 0.12, collection=collection)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
    return obj


root = bpy.data.objects.new("AIQUIZ_Ocean_Grandstand", None)
root["asset_role"] = "ocean_grandstand"
root["design"] = "original_aiquiz_2026"
export_collection.objects.link(root)

# The nominal gameplay conveyor is 160 m long. Every longitudinal architectural
# element shares this datum so the grandstand and conveyor terminate together.
CONVEYOR_LENGTH = 160.0
HALF_LENGTH = CONVEYOR_LENGTH * 0.5
STRUCTURE_EDGE = HALF_LENGTH - 0.25
SEAT_EDGE = HALF_LENGTH - 2.5
ROOF_CENTER_X = 7.60
ROOF_CENTER_Z = 13.72
ROOF_SLOPE = 0.115


def roof_center_z(x: float) -> float:
    return ROOF_CENTER_Z + (x - ROOF_CENTER_X) * ROOF_SLOPE


root["nominal_conveyor_length_m"] = CONVEYOR_LENGTH

groups: dict[str, list[bpy.types.Object]] = {
    "concrete": [],
    "light_concrete": [],
    "steel": [],
    "secondary_steel": [],
    "aluminum": [],
    "roof": [],
    "glass": [],
    "interior": [],
    "signs": [],
    "lights": [],
    "rubber": [],
}


def grouped(group: str, obj: bpy.types.Object) -> bpy.types.Object:
    groups[group].append(obj)
    return obj


# Ocean foundation and structural deck. Piers, pile caps, longitudinal X-bracing,
# raker beams, and roof frames all share the same 16 m structural grid.
frame_positions = [float(y) for y in range(-72, 73, 16)]
grouped("concrete", add_box("Foundation_Deck", (8.0, 0.0, -0.30), (18.0, CONVEYOR_LENGTH, 0.60), concrete, bevel=0.12))
grouped("steel", add_box("Foundation_Front_Girder", (0.0, 0.0, -0.85), (0.55, CONVEYOR_LENGTH, 1.10), steel, bevel=0.08))
grouped("steel", add_box("Foundation_Rear_Girder", (16.0, 0.0, -0.85), (0.55, CONVEYOR_LENGTH, 1.10), steel, bevel=0.08))
for end_index, y in enumerate((-STRUCTURE_EDGE, STRUCTURE_EDGE)):
    grouped("steel", add_box(f"Foundation_End_Girder_{end_index}", (8.0, y, -0.85), (16.5, 0.55, 1.10), steel, bevel=0.08))

for frame_index, y in enumerate(frame_positions):
    for x_index, x in enumerate((1.5, 7.8, 14.3)):
        grouped("concrete", add_cylinder(f"Ocean_Pier_{x_index}_{frame_index}", (x, y, -5.15), 0.48, 9.7, concrete, vertices=20))
        grouped("steel", add_box(f"Pier_Cap_{x_index}_{frame_index}", (x, y, -0.72), (1.45, 2.3, 0.42), steel, bevel=0.08))

    # The seating rake terminates on the deck at the front and on the rear frame.
    grouped("steel", add_beam(f"Bowl_Raker_{frame_index}", (0.30, y, -0.02), (14.75, y, 7.42), 0.30, steel))
    for support_index, x in enumerate((4.8, 9.6, 14.4)):
        raker_z = -0.02 + (x - 0.30) / (14.75 - 0.30) * (7.42 + 0.02)
        grouped("steel", add_beam(f"Raker_Post_{frame_index}_{support_index}", (x, y, -0.02), (x, y, raker_z), 0.24, steel))
        grouped("secondary_steel", add_box(f"Raker_Gusset_{frame_index}_{support_index}", (x, y, raker_z), (0.68, 0.18, 0.58), steel_secondary, bevel=0.035))

for bay_index in range(len(frame_positions) - 1):
    y0 = frame_positions[bay_index]
    y1 = frame_positions[bay_index + 1]
    for x_index, x in enumerate((1.5, 14.3)):
        grouped("secondary_steel", add_beam(f"Pier_XBrace_A_{bay_index}_{x_index}", (x, y0, -4.9), (x, y1, -1.0), 0.18, steel_secondary))
        grouped("secondary_steel", add_beam(f"Pier_XBrace_B_{bay_index}_{x_index}", (x, y0, -1.0), (x, y1, -4.9), 0.18, steel_secondary))
    grouped("secondary_steel", add_beam(f"Foundation_Longitudinal_{bay_index}", (7.8, y0, -1.02), (7.8, y1, -1.02), 0.22, steel_secondary))

# Terraced concrete bowl, split around seven full-height aisles.
aisles = (-60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0)
aisle_half_width = 1.05
segments: list[tuple[float, float]] = []
cursor = -STRUCTURE_EDGE
for aisle in aisles:
    segments.append((cursor, aisle - aisle_half_width))
    cursor = aisle + aisle_half_width
segments.append((cursor, STRUCTURE_EDGE))

row_count = 10
row_pitch = 1.17
rise = 0.72
front_x = 1.35
for row in range(row_count):
    row_x = front_x + row * row_pitch
    top_z = 0.45 + row * rise
    back_x = 14.25
    for segment_index, (y0, y1) in enumerate(segments):
        if y1 <= y0:
            continue
        grouped(
            "concrete",
            add_box(
                f"Terrace_R{row:02d}_S{segment_index:02d}",
                ((row_x + back_x) * 0.5, (y0 + y1) * 0.5, top_z * 0.5 - 0.02),
                (back_x - row_x, y1 - y0, top_z),
                concrete,
                bevel=0.025,
            ),
        )
    for aisle_index, aisle in enumerate(aisles):
        grouped(
            "light_concrete",
            add_box(
                f"Aisle_Step_R{row:02d}_A{aisle_index:02d}",
                (row_x - row_pitch * 0.5, aisle, top_z * 0.5),
                (row_pitch, aisle_half_width * 1.78, top_z),
                concrete_light,
                bevel=0.018,
            ),
        )

grouped("concrete", add_box("Front_Concourse", (0.45, 0.0, 0.16), (2.8, CONVEYOR_LENGTH, 0.32), concrete, bevel=0.08))
grouped("concrete", add_box("Rear_Concourse", (15.25, 0.0, 3.65), (2.2, CONVEYOR_LENGTH, 7.30), concrete, bevel=0.09))
grouped("concrete", add_box("Rear_Parapet", (16.30, 0.0, 8.0), (0.35, CONVEYOR_LENGTH, 1.35), concrete, bevel=0.07))
for end_index, y in enumerate((-STRUCTURE_EDGE, STRUCTURE_EDGE)):
    grouped("concrete", add_box(f"Bowl_End_Wall_{end_index}", (8.05, y, 3.68), (16.1, 0.32, 7.36), concrete, bevel=0.065))

# Build a beveled chair from three reusable templates, then combine every seat into one mesh.
def beveled_template(name: str, size: tuple[float, float, float], bevel: float) -> tuple[list[Vector], list[tuple[int, ...]]]:
    bpy.ops.mesh.primitive_cube_add()
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = obj.modifiers.new("Template_Bevel", "BEVEL")
    modifier.width = bevel
    modifier.segments = 2
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    vertices = [vertex.co.copy() for vertex in obj.data.vertices]
    faces = [tuple(poly.vertices) for poly in obj.data.polygons]
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.meshes.remove(mesh, do_unlink=True)
    return vertices, faces


cushion_template = beveled_template("Seat_Cushion_Template", (0.62, 0.68, 0.13), 0.055)
back_template = beveled_template("Seat_Back_Template", (0.13, 0.70, 0.78), 0.055)
post_template = beveled_template("Seat_Post_Template", (0.11, 0.13, 0.58), 0.018)
foot_template = beveled_template("Seat_Foot_Template", (0.30, 0.22, 0.08), 0.018)

seat_vertices: list[tuple[float, float, float]] = []
seat_faces: list[tuple[int, ...]] = []
seat_material_indices: list[int] = []


def append_template(
    template: tuple[list[Vector], list[tuple[int, ...]]],
    matrix: Matrix,
    material_index: int,
) -> None:
    start_index = len(seat_vertices)
    vertices, faces = template
    seat_vertices.extend(tuple(matrix @ vertex) for vertex in vertices)
    for face in faces:
        seat_faces.append(tuple(start_index + index for index in face))
        seat_material_indices.append(material_index)


seat_count = 0
seat_materials = (seat_blue, seat_cyan, seat_violet, seat_gold, steel)
for row in range(row_count):
    row_x = front_x + row * row_pitch
    platform_z = 0.45 + row * rise
    y = -SEAT_EDGE
    while y <= SEAT_EDGE:
        if any(abs(y - aisle) < aisle_half_width + 0.44 for aisle in aisles):
            y += 0.92
            continue
        section = int((y + HALF_LENGTH) // 20.0)
        color_index = (section + row // 2) % 3
        if (row in (0, 5, 9) and int(round(y / 0.92)) % 13 == 0):
            color_index = 3
        cushion_matrix = Matrix.Translation(Vector((row_x, y, platform_z + 0.48)))
        back_matrix = Matrix.Translation(Vector((row_x + 0.36, y, platform_z + 0.88))) @ Matrix.Rotation(math.radians(8.0), 4, "Y")
        post_matrix = Matrix.Translation(Vector((row_x + 0.30, y, platform_z + 0.28)))
        foot_matrix = Matrix.Translation(Vector((row_x + 0.27, y, platform_z + 0.06)))
        append_template(cushion_template, cushion_matrix, color_index)
        append_template(back_template, back_matrix, color_index)
        append_template(post_template, post_matrix, 4)
        append_template(foot_template, foot_matrix, 4)
        seat_count += 1
        y += 0.92

seat_mesh = bpy.data.meshes.new("Grandstand_Seats_Mesh")
seat_mesh.from_pydata(seat_vertices, [], seat_faces)
seat_mesh.update()
seat_obj = bpy.data.objects.new("Grandstand_Seats_LOD0", seat_mesh)
export_collection.objects.link(seat_obj)
for material in seat_materials:
    seat_mesh.materials.append(material)
for polygon, material_index in zip(seat_mesh.polygons, seat_material_indices):
    polygon.material_index = material_index
seat_obj["seat_count"] = seat_count

# Front guardrail and aisle handrails.
for height in (0.72, 1.18):
    grouped("aluminum", add_beam(f"Front_Rail_{height}", (-0.65, -STRUCTURE_EDGE, height), (-0.65, STRUCTURE_EDGE, height), 0.075, aluminum))
for y in np.arange(-STRUCTURE_EDGE, STRUCTURE_EDGE + 0.01, 4.0):
    grouped("aluminum", add_beam(f"Front_Rail_Post_{y:.1f}", (-0.65, float(y), 0.20), (-0.65, float(y), 1.25), 0.075, aluminum))
for aisle_index, aisle in enumerate(aisles):
    for side in (-0.72, 0.72):
        y = aisle + side
        grouped("aluminum", add_beam(f"Aisle_Rail_{aisle_index}_{side}", (0.85, y, 0.98), (12.4, y, 8.05), 0.065, aluminum))
        for row in (0, 3, 6, 9):
            x = front_x + row * row_pitch - 0.2
            z = 0.78 + row * rise
            grouped("aluminum", add_beam(f"Aisle_Post_{aisle_index}_{side}_{row}", (x, y, z - 0.72), (x, y, z + 0.32), 0.06, aluminum))

# The central broadcast booth was deliberately removed: this grandstand is now
# open above the seating, without a glazed upper room or its supporting frame.

# Rear service-gallery rails physically connect the booth, rear concourse, and end walls.
for height in (8.00, 8.58):
    grouped("aluminum", add_beam(f"Rear_Service_Rail_{height}", (16.55, -STRUCTURE_EDGE, height), (16.55, STRUCTURE_EDGE, height), 0.075, aluminum))
for y in np.arange(-STRUCTURE_EDGE, STRUCTURE_EDGE + 0.01, 4.0):
    grouped("aluminum", add_beam(f"Rear_Service_Post_{y:.1f}", (16.55, float(y), 7.30), (16.55, float(y), 8.64), 0.075, aluminum))

# Roof canopy. Every chord, web, post, purlin, and gusset terminates at an exact
# shared node; there are no decorative members floating below the roof skin.
roof_angle = -math.atan(ROOF_SLOPE)
for panel_index, y in enumerate(np.arange(-76.0, 76.01, 8.0)):
    grouped("roof", add_box(f"Roof_Panel_{panel_index:02d}", (ROOF_CENTER_X, float(y), ROOF_CENTER_Z), (18.0, 7.96, 0.30), roof_material, bevel=0.055, rotation=(0.0, roof_angle, 0.0)))

truss_x = (-0.90, 3.15, 7.20, 11.25, 15.30)
top_nodes = [(x, roof_center_z(x) - 0.22) for x in truss_x]
bottom_nodes = [
    (x, z - (0.62 + (x - truss_x[0]) / (truss_x[-1] - truss_x[0]) * 0.72))
    for x, z in top_nodes
]

for frame_index, y in enumerate(frame_positions):
    column_top = top_nodes[-1]
    grouped("steel", add_beam(f"Rear_Column_{frame_index}", (column_top[0], y, 7.36), (column_top[0], y, column_top[1]), 0.48, steel))
    grouped("steel", add_box(f"Column_Base_Plate_{frame_index}", (column_top[0], y, 7.38), (0.92, 0.92, 0.14), steel, bevel=0.035))
    for bolt_index, (dx, dy) in enumerate(((-0.30, -0.30), (-0.30, 0.30), (0.30, -0.30), (0.30, 0.30))):
        grouped("aluminum", add_cylinder(f"Column_Anchor_{frame_index}_{bolt_index}", (column_top[0] + dx, y + dy, 7.53), 0.055, 0.24, aluminum, vertices=10))

    for node_index in range(len(top_nodes) - 1):
        tx0, tz0 = top_nodes[node_index]
        tx1, tz1 = top_nodes[node_index + 1]
        bx0, bz0 = bottom_nodes[node_index]
        bx1, bz1 = bottom_nodes[node_index + 1]
        grouped("steel", add_beam(f"Roof_Top_Chord_{frame_index}_{node_index}", (tx0, y, tz0), (tx1, y, tz1), 0.23, steel))
        grouped("secondary_steel", add_beam(f"Roof_Lower_Chord_{frame_index}_{node_index}", (bx0, y, bz0), (bx1, y, bz1), 0.18, steel_secondary))
        if node_index % 2 == 0:
            grouped("secondary_steel", add_beam(f"Roof_Web_{frame_index}_{node_index}", (tx0, y, tz0), (bx1, y, bz1), 0.145, steel_secondary))
        else:
            grouped("secondary_steel", add_beam(f"Roof_Web_{frame_index}_{node_index}", (bx0, y, bz0), (tx1, y, tz1), 0.145, steel_secondary))

    for node_index, ((tx, tz), (bx, bz)) in enumerate(zip(top_nodes, bottom_nodes)):
        grouped("secondary_steel", add_beam(f"Roof_Vertical_{frame_index}_{node_index}", (tx, y, tz), (bx, y, bz), 0.13, steel_secondary))
        grouped("secondary_steel", add_box(f"Roof_Top_Gusset_{frame_index}_{node_index}", (tx, y, tz), (0.62, 0.16, 0.48), steel_secondary, bevel=0.035))
        grouped("secondary_steel", add_box(f"Roof_Bottom_Gusset_{frame_index}_{node_index}", (bx, y, bz), (0.56, 0.16, 0.44), steel_secondary, bevel=0.035))

# Purlins sit directly against the roof underside and intersect every top-chord node.
for purlin_index, (x, z) in enumerate(top_nodes):
    grouped("steel", add_beam(f"Roof_Purlin_{purlin_index}", (x, -STRUCTURE_EDGE, z), (x, STRUCTURE_EDGE, z), 0.18, steel))

front_fascia_x = -1.22
rear_fascia_x = 16.02
grouped("roof", add_box("Roof_Front_Gutter", (front_fascia_x, 0.0, roof_center_z(front_fascia_x)), (0.34, CONVEYOR_LENGTH, 0.54), roof_material, bevel=0.055))
grouped("roof", add_box("Roof_Rear_Flashing", (rear_fascia_x, 0.0, roof_center_z(rear_fascia_x)), (0.32, CONVEYOR_LENGTH, 0.48), roof_material, bevel=0.050))
for end_index, y in enumerate((-STRUCTURE_EDGE, STRUCTURE_EDGE)):
    grouped("aluminum", add_beam(f"Roof_Downpipe_{end_index}", (front_fascia_x, y, 7.45), (front_fascia_x, y, roof_center_z(front_fascia_x)), 0.12, aluminum))

for z in (9.2, 12.5):
    grouped("secondary_steel", add_beam(f"Rear_Cross_Beam_{z}", (15.30, -STRUCTURE_EDGE, z), (15.30, STRUCTURE_EDGE, z), 0.24, steel_secondary))
for strip_index, x in enumerate((1.0, 5.2, 9.4, 13.6)):
    grouped("lights", add_box(f"Roof_Light_Strip_{strip_index}", (x, 0.0, roof_center_z(x) - 0.34), (0.10, CONVEYOR_LENGTH - 4.0, 0.08), light_material, bevel=0.025, rotation=(0.0, roof_angle, 0.0)))

# Side wind screens, rear vertical fins, and front advertising fascia.
for y in (-STRUCTURE_EDGE, STRUCTURE_EDGE):
    grouped("glass", add_box(f"Side_Windscreen_{y}", (7.0, y, 7.2), (13.5, 0.12, 7.8), glass, bevel=0.03))
    for x in (0.5, 4.8, 9.1, 13.4):
        grouped("steel", add_box(f"Side_Screen_Frame_{y}_{x}", (x, y, 7.0), (0.15, 0.20, 8.2), steel, bevel=0.025))
for y in np.arange(-78.0, 78.1, 3.0):
    grouped("secondary_steel", add_box(f"Rear_Fin_{y:.1f}", (16.52, float(y), 10.15), (0.18, 0.24, 4.6), steel_secondary, bevel=0.035))
for board_index, y in enumerate(np.arange(-70.0, 70.1, 14.0)):
    board_mat = sign_blue if board_index % 2 == 0 else seat_violet
    grouped("signs", add_box(f"Sponsor_Board_{board_index}", (-0.92, float(y), 0.62), (0.18, 13.2, 1.05), board_mat, bevel=0.08))
    grouped("lights", add_box(f"Sponsor_Light_{board_index}", (-1.03, float(y), 1.11), (0.06, 12.4, 0.055), sign_cyan, bevel=0.02))


def add_text(name: str, text: str, location: tuple[float, float, float], size: float, material: bpy.types.Material) -> bpy.types.Object:
    curve = bpy.data.curves.new(name + "_Curve", "FONT")
    curve.body = text
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = size
    curve.extrude = 0.035
    curve.bevel_depth = 0.018
    curve.bevel_resolution = 3
    obj = bpy.data.objects.new(name, curve)
    export_collection.objects.link(obj)
    # Local X -> world -Y, local Y -> world Z, local Z -> world -X.
    # This stays right-handed and reads correctly from the course side.
    obj.matrix_world = Matrix(
        (
            (0.0, 0.0, -1.0, location[0]),
            (-1.0, 0.0, 0.0, location[1]),
            (0.0, 1.0, 0.0, location[2]),
            (0.0, 0.0, 0.0, 1.0),
        )
    )
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return obj


# No front title/signage: the user-facing upper booth and its AIQUIZ ARENA sign
# were removed together.

# Join same-material architectural parts to minimize Godot nodes and draw submission.
def join_group(group_name: str, output_name: str) -> bpy.types.Object | None:
    objects = [obj for obj in groups[group_name] if obj and obj.name in bpy.data.objects]
    if not objects:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result_obj = bpy.context.active_object
    result_obj.name = output_name
    return result_obj


joined_objects = [
    join_group("concrete", "Grandstand_Concrete_Structure"),
    join_group("light_concrete", "Grandstand_Aisle_Steps"),
    join_group("steel", "Grandstand_Primary_Steel"),
    join_group("secondary_steel", "Grandstand_Secondary_Steel"),
    join_group("aluminum", "Grandstand_Railings"),
    join_group("roof", "Grandstand_Roof"),
    join_group("glass", "Grandstand_Glass"),
    join_group("interior", "Grandstand_Booth_Interior"),
    join_group("signs", "Grandstand_Signage"),
    join_group("lights", "Grandstand_Architectural_Lights"),
]

for obj in [seat_obj] + [item for item in joined_objects if item is not None]:
    obj.parent = root
    obj["lod"] = 0
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = False

# A compact second-level silhouette for future range switching in Godot.
lod1_parts = [
    add_box("LOD1_Bowl", (8.0, 0.0, 3.65), (16.0, CONVEYOR_LENGTH, 7.3), concrete, bevel=0.10),
    add_box("LOD1_Roof", (ROOF_CENTER_X, 0.0, ROOF_CENTER_Z), (18.0, CONVEYOR_LENGTH, 0.32), roof_material, bevel=0.06, rotation=(0.0, roof_angle, 0.0)),
]
for obj in lod1_parts:
    obj.parent = root
    obj.hide_render = True
    obj.hide_viewport = True
    obj["lod"] = 1

# Export only LOD0 asset geometry. LOD1 remains in the editable source for later range tuning.
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for obj in root.children:
    if int(obj.get("lod", 0)) == 0:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
bpy.context.view_layer.objects.active = root

bpy.ops.export_scene.gltf(
    filepath=str(GLB_PATH),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_texcoords=True,
    export_normals=True,
    export_tangents=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
)

# Presentation context is source-only and never exported.
ocean_mat = principled_material("Preview_Ocean", (0.006, 0.18, 0.34, 1.0), metallic=0.20, roughness=0.18)
course_mat = principled_material("Preview_Course", (0.045, 0.055, 0.075, 1.0), metallic=0.25, roughness=0.48)
add_box("Preview_Ocean", (-6.0, 0.0, -9.35), (100.0, 170.0, 0.25), ocean_mat, bevel=0.0, collection=preview_collection)
add_box("Preview_Course", (-17.0, 0.0, -0.20), (12.0, CONVEYOR_LENGTH, 0.40), course_mat, bevel=0.12, collection=preview_collection)
for y in np.arange(-76.0, 76.1, 8.0):
    add_box(f"Preview_Course_Stripe_{y}", (-17.0, float(y), 0.025), (11.4, 0.10, 0.03), sign_cyan, collection=preview_collection)

world = scene.world or bpy.data.worlds.new("AIQUIZ_Grandstand_World")
scene.world = world
world.use_nodes = True
world_nodes = world.node_tree.nodes
world_background = next(node for node in world_nodes if node.type == "BACKGROUND")
world_background.inputs["Color"].default_value = (0.035, 0.085, 0.18, 1.0)
world_background.inputs["Strength"].default_value = 0.42

bpy.ops.object.light_add(type="SUN", location=(-20.0, -30.0, 35.0))
sun = bpy.context.active_object
sun.name = "Preview_Sun"
sun.data.energy = 3.0
sun.data.color = (0.88, 0.94, 1.0)
sun.rotation_euler = (math.radians(28.0), math.radians(-22.0), math.radians(-32.0))
move_to_collection(sun, preview_collection)
for light_name, location, energy, color, size in (
    ("Preview_Key", (-24.0, -25.0, 24.0), 2400.0, (0.56, 0.78, 1.0), 15.0),
    ("Preview_Fill", (-8.0, 48.0, 16.0), 1700.0, (0.35, 0.58, 1.0), 12.0),
    ("Preview_Rim", (22.0, -25.0, 18.0), 2100.0, (0.35, 0.68, 1.0), 10.0),
):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.active_object
    light.name = light_name
    light.data.energy = energy
    light.data.color = color
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = (math.radians(25.0), 0.0, math.radians(135.0))
    move_to_collection(light, preview_collection)


def render_camera(name: str, location: tuple[float, float, float], target: tuple[float, float, float], lens: float, output: Path) -> None:
    camera_data = bpy.data.cameras.new(name + "_Data")
    camera = bpy.data.objects.new(name, camera_data)
    preview_collection.objects.link(camera)
    camera.location = location
    camera.data.lens = lens
    camera.data.sensor_width = 36.0
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


for obj in lod1_parts:
    obj.hide_render = True
for obj in root.children:
    if int(obj.get("lod", 0)) == 0:
        obj.hide_render = False

render_camera(
    "Hero_Camera",
    (-31.0, -47.0, 15.5),
    (7.0, 0.0, 5.2),
    46.0,
    PREVIEW_DIR / "aiquiz_grandstand_hero.png",
)
render_camera(
    "Detail_Camera",
    (-18.0, -18.0, 11.0),
    (10.0, 0.0, 9.0),
    50.0,
    PREVIEW_DIR / "aiquiz_grandstand_booth_detail.png",
)
render_camera(
    "Structure_Camera",
    (-6.0, -42.0, 11.7),
    (7.2, -24.0, 12.6),
    52.0,
    PREVIEW_DIR / "aiquiz_grandstand_roof_connections.png",
)

scene["aiquiz_grandstand_seat_count"] = seat_count
scene["aiquiz_grandstand_dimensions_m"] = "18 x 160 x 24.5 including ocean piers"
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

result = {
    "blend": str(BLEND_PATH),
    "glb": str(GLB_PATH),
    "seat_count": seat_count,
    "exported_objects": 1 + sum(1 for obj in root.children if int(obj.get("lod", 0)) == 0),
    "hero_preview": str(PREVIEW_DIR / "aiquiz_grandstand_hero.png"),
    "detail_preview": str(PREVIEW_DIR / "aiquiz_grandstand_booth_detail.png"),
    "structure_preview": str(PREVIEW_DIR / "aiquiz_grandstand_roof_connections.png"),
}

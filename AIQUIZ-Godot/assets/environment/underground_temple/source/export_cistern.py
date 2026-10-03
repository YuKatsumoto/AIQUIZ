"""Export cistern modules (GLB), update cistern_layout.json and the Godot .import presets.

LIVE Blender only:

    ns = {"__name__": "cistern_export"}
    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/export_cistern.py",
              encoding="utf-8").read(), ns)
    ns["export_module"]("A")        # -> cistern_bay_a.glb (+ layout entry, + .import presets)

Object names "<TAG>|CIS_*" are renamed to "CIS_*" for the duration of the export, so every GLB
carries the contract node names. Materials go out as named placeholders (Godot builds its own
shaders by name, see README). Vertex colour COLOR_0 and both UV sets (TEXCOORD_0 = UV0 tiling,
TEXCOORD_1 = UV2 lightmap) are exported.
"""
import json
import math
import os
import struct

import bpy
from mathutils import Vector

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/cistern_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)

LAYOUT = C.ROOT + "/cistern_layout.json"
CACHE_BAKE = os.path.join(os.environ.get("TEMP", "C:/Temp"), "aiquiz_cistern_bake")

MODULES = {
    "A": "cistern_bay_a", "B": "cistern_bay_b", "C": "cistern_bay_c", "O": "cistern_bay_opening",
    "U": "cistern_end_upstream", "D": "cistern_end_downstream",
}
PLACEMENT = {
    "A": "bay: module-local z -7.5..7.5, place at world z = 15 k (k = -1..13, k != 0), y = FLOOR_Y",
    "B": "bay: module-local z -7.5..7.5, place at world z = 15 k (k = -1..13, k != 0), y = FLOOR_Y",
    "C": "bay: module-local z -7.5..7.5, place at world z = 15 k (k = -1..13, k != 0), y = FLOOR_Y",
    "O": "bay k = 0: place at world z = 0, y = FLOOR_Y",
    "U": "authored in world z (-30.6..-22.5, tunnel to -45): place at origin (z = 0), y = FLOOR_Y",
    "D": "authored in world z (202.5..211.2): place at origin (z = 0), y = FLOOR_Y",
}
GODOT_LIGHT = {
    # suggested real-light values for the characters (static meshes are lightmapped)
    "Flood": {"type": "SpotLight3D", "godot_energy": 6.0, "range": 30.0, "spot_angle_deg": 58.0, "spot_attenuation": 0.9},
    "Amber": {"type": "OmniLight3D", "godot_energy": 1.2, "range": 9.0},
    "Window": {"type": "SpotLight3D", "godot_energy": 2.5, "range": 10.0, "spot_angle_deg": 70.0, "spot_attenuation": 1.0},
}


def _layer_col(lc, name):
    if lc.collection.name == name:
        return lc
    for ch in lc.children:
        r = _layer_col(ch, name)
        if r is not None:
            return r
    return None


def _include(tag):
    vl = bpy.context.view_layer
    lc = _layer_col(vl.layer_collection, "CIS_" + tag)
    lc.exclude = False


def export_objects(tag):
    col = bpy.data.collections["CIS_" + tag]
    out = []
    for o in col.all_objects:
        if o.type == "MESH" or (o.type == "EMPTY" and "|CIS_" in o.name):
            out.append(o)
    return out


def _gltf(path):
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
        export_apply=True, export_yup=True, export_texcoords=True, export_normals=True,
        export_tangents=False, export_materials="VIEWPORT", export_extras=False,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False,
        export_cameras=False, export_lights=False, export_animations=False,
    )


def glb_info(path):
    with open(path, "rb") as fh:
        data = fh.read()
    length = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + length].decode("utf-8"))
    attrs = set()
    for m in js.get("meshes", []):
        for p in m["primitives"]:
            attrs.update(p["attributes"].keys())
    return {"nodes": [n.get("name") for n in js.get("nodes", [])],
            "materials": [m.get("name") for m in js.get("materials", [])],
            "attributes": sorted(attrs), "bytes": len(data)}


def export_module(tag):
    name = MODULES[tag]
    _include(tag)
    objs = export_objects(tag)
    renamed = []
    try:
        for o in objs:
            clean = o.name.split("|", 1)[1]
            renamed.append((o, o.name, o.data.name if o.type == "MESH" else None))
        for o, old, mold in renamed:
            o.name = old.split("|", 1)[1]
            if mold is not None:
                o.data.name = mold.split("|", 1)[1]
        for o, old, mold in renamed:
            if o.name != old.split("|", 1)[1]:
                raise RuntimeError("name clash on export: %s -> %s" % (old, o.name))
        vl = bpy.context.view_layer
        for o in vl.objects:
            if o.select_get():
                o.select_set(False)
        for o in objs:
            o.hide_set(False)
            o.select_set(True)
        vl.objects.active = objs[0]
        for o in objs:
            if o.type == "MESH":
                me = o.data
                if me.color_attributes.get("Color") is not None:
                    me.color_attributes.active_color = me.color_attributes["Color"]
        path = "%s/%s.glb" % (C.ROOT, name)
        _gltf(path)
    finally:
        for o, old, mold in renamed:
            o.name = old
            if mold is not None:
                o.data.name = mold
    info = glb_info(path)
    entry = layout_entry(tag)
    update_layout(name, entry)
    write_glb_import(name)
    return {"glb": path, "nodes": len(info["nodes"]), "materials": info["materials"], "attributes": info["attributes"],
            "bytes": info["bytes"], "triangles": entry["triangles"]}


# ------------------------------------------------------------------ layout json
def _round(v, n=4):
    return [round(float(x), n) for x in v]


def layout_entry(tag):
    name = MODULES[tag]
    col = bpy.data.collections["CIS_" + tag]
    tris = {}
    for o in col.all_objects:
        if o.type == "MESH":
            tris[o.name.split("|", 1)[1]] = C.tri_count(o)
    lights = []
    for o in sorted(col.all_objects, key=lambda x: x.name):
        if o.type == "EMPTY" and "|CIS_Light_" in o.name:
            node = o.name.split("|", 1)[1]
            kind = node.split("_")[2]
            ldata = bpy.data.objects.get(o.name.replace("|CIS_Light_", "|LGT_"))
            pos = C.b2g(o.matrix_world.translation)
            fwd = C.b2g(o.matrix_world.to_3x3() @ Vector((0.0, 1.0, 0.0)))
            entry = {"node": node, "kind": kind, "position": _round(pos), "direction": _round(fwd.normalized()),
                     "kelvin": {"Flood": C.FLOOD_K, "Amber": C.AMBER_K, "Window": C.WINDOW_K}[kind]}
            if ldata is not None:
                entry["color_linear"] = _round(ldata.data.color, 4)
                entry["blender_power_w"] = round(ldata.data.energy, 2)
                if ldata.data.type == "SPOT":
                    entry["blender_spot_size_deg"] = round(math.degrees(ldata.data.spot_size), 1)
                    entry["blender_spot_blend"] = round(ldata.data.spot_blend, 3)
            entry.update(GODOT_LIGHT[kind])
            lights.append(entry)
    meta_path = os.path.join(CACHE_BAKE, "%s_meta.json" % tag)
    lm = {}
    if os.path.exists(meta_path):
        with open(meta_path) as fh:
            meta = json.load(fh)
        lm = {"lightmap": "textures/%s_light.png" % name, "light_max": round(meta["light_max"], 6),
              "lightmap_size": meta["size"][0], "light_clipped_fraction": round(meta.get("clipped_fraction", 0.0), 5)}
    special = {}
    for o in col.all_objects:
        n = o.name.split("|", 1)[1] if "|" in o.name else o.name
        if n in ("CIS_InflowGate", "CIS_Hatch_L", "CIS_Hatch_R"):
            special[n] = {"origin": _round(C.b2g(o.matrix_world.translation))}
    extra = col.get("cis_extra")
    out = {"file": "%s.glb" % name, "placement": PLACEMENT[tag], "triangles": tris, "triangles_total": sum(tris.values()),
           "lights": lights}
    out.update(lm)
    if special:
        out["moving_nodes"] = special
    if extra:
        out.update(json.loads(extra))
    return out


def base_layout():
    return {
        "units": "metres, Godot axes (Y up, flood flows toward +Z); module floor at y = 0 (Godot places modules at y = SuddenDeathLayout.FLOOR_Y)",
        "contract": "docs/sudden_death_m3_interface.md",
        "hall": {
            "half_width": C.HALF_W, "ceiling_y": C.CEIL_Y, "slab_top_y": C.SLAB_TOP, "corridor_half_width": C.CORR_X,
            "bay_length": C.BAY, "pillar_x": list(C.PILLAR_X), "pillar_size": [2.0, C.CEIL_Y, 7.0], "pillar_local_z": [C.PILLAR_Z0, C.PILLAR_Z1],
            "pillar_chamfer": C.CHAMFER, "cold_joints_y": list(C.COLD_JOINTS), "kicker_y": C.KICKER,
            "transverse_beam": {"z": list(C.TB_Z), "bottom_y": C.TB_BOTTOM, "haunch": list(C.TB_HAUNCH)},
            "longitudinal_beam": {"bottom_y": C.LB_BOTTOM, "haunch": list(C.LB_HAUNCH)},
            "drain_channels_abs_x": list(C.CH_X), "drain_channel_depth": C.CH_DEPTH,
            "corridor_railing_abs_x": C.PILLAR_X[0], "flood_mount": {"abs_x": C.CORR_X, "y": C.FLOOD_Y, "z": C.FLOOD_Z},
            "opening": {"center": [0.0, 0.0], "radius": C.OPENING_R, "rim_y": [C.CEIL_Y, C.SLAB_TOP]},
            "waterline_y": 1.5,
        },
        "uv0_metres_per_unit": {
            "CIS_Concrete": C.S_CONCRETE, "CIS_Floor": C.S_FLOOR, "CIS_SteelPaint": C.S_STEEL, "CIS_Galvanized": C.S_GALV,
            "CIS_Grate": C.S_GRATE, "CIS_Hazard": C.S_HAZARD, "CIS_Interior": C.S_CONCRETE,
            "note": "concrete/floor tiles are 3.75 m (= 15 m / 4: seamless across modules; 4 x 2 form panels of 0.9375 x 1.875 m)",
        },
        "lightmap_encoding": {
            "uv": "UV2 (glTF TEXCOORD_1), per module, non-overlapping",
            "rgb": "pow(texel, 2.2) * light_max = E * grime, E = Cycles diffuse bake (direct + indirect, white Lambertian, scene-linear, review exposure 0, AgX)",
            "alpha": "ambient occlusion (1 m)",
            "note": "the per-module dirt (waterline band, runoff streaks, efflorescence, rust runs, ceiling damp) is multiplied into RGB; sample without source_color",
        },
        "vertex_color": {
            "CIS_Floor": "COLOR_0: R puddle potential, G damp, B silt (see README recipe with floor_wet.png)",
            "CIS_SteelPaint": "COLOR_0: paint tint (multiply albedo.rgb where albedo.a = 1)",
            "other": "white",
        },
        "review_grading": {"view_transform": "AgX", "exposure": 0.0, "white_balance_kelvin": 5000.0},
        "modules": {},
    }


def update_layout(name, entry):
    data = base_layout()
    if os.path.exists(LAYOUT):
        with open(LAYOUT, encoding="utf-8") as fh:
            old = json.load(fh)
        data["modules"] = old.get("modules", {})
        for k in ("decals",):
            if k in old:
                data[k] = old[k]
    data["modules"][name] = entry
    with open(LAYOUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
    return LAYOUT


# ------------------------------------------------------------------ Godot import presets
GLB_IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=0
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=true
skins/use_named_skins=true
animation/import=false
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={}
gltf/naming_version=2
gltf/embedded_image_handling=1
"""

TEX_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality={hq}
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border={fix}
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def _write_if_missing(path, text):
    """Write a fresh preset; keep an existing .import (Godot owns its uid / remap section)."""
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            old = fh.read()
        if "[params]" in old:
            head = old.split("[params]")[0]
            body = text.split("[params]")[1]
            text = head + "[params]" + body
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def write_glb_import(name):
    _write_if_missing("%s/%s.glb.import" % (C.ROOT, name), GLB_IMPORT)


def write_texture_imports():
    done = []
    for fn in sorted(os.listdir(C.TEXTURES)):
        if not fn.endswith(".png"):
            continue
        normal = 1 if fn.endswith("_normal.png") else 2
        fix = "true" if fn in ("grate_albedo.png", "cistern_decals.png") else "false"
        hq = "true"
        if normal == 1:
            hq = "false"
        _write_if_missing("%s/%s.import" % (C.TEXTURES, fn), TEX_IMPORT.format(hq=hq, normal=normal, fix=fix))
        done.append(fn)
    return done

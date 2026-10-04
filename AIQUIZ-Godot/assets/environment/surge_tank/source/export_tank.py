"""Export the surge tank modules (GLB), write tank_layout.json and the Godot .import presets.

LIVE Blender only:

    ns = {"__name__": "tank_export"}
    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/export_tank.py", encoding="utf-8").read(), ns)
    ns["export_module"]("K04")      # -> tank_line_04.glb (+ .import preset)
    ns["write_layout"]()            # survey, modules, light maps, light_max, lights -> tank_layout.json

Object names "<TAG>|TK_*" are renamed to "TK_*" for the duration of the export, so every GLB carries
clean node names. Materials go out as named placeholders (Godot builds its own shaders by name).
Both UV sets go out: TEXCOORD_0 = UV0 (tiling), TEXCOORD_1 = UV2 (light map); COLOR_0 = paint tint.
"""
import json
import math
import os
import shutil
import struct
import tempfile

import bpy
from mathutils import Vector

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/tank_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)

LAYOUT = C.ROOT + "/tank_layout.json"
CACHE_BAKE = os.path.join(tempfile.gettempdir(), "aiquiz_tank_bake")
MODULES = dict([("K%02d" % k, "tank_line_%02d" % k) for k in range(C.LINES)]
               + [("P", "tank_end_pump"), ("S", "tank_end_shaft"), ("Q", "tank_shaft1"), ("T", "tank_stairs")])
CONTENT = {
    "P": "pump end: gate face (z = 132.8), five dividing walls, four intake channels, transverse beam before line 0",
    "S": "shaft-side end: end wall (z = -38.6) with two 10 m openings, passage to shaft No.1, fence, blocks",
    "Q": "shaft No.1: wall, roof with daylight opening, stair tower, pipes, ring catwalk, floods",
    "T": "visitor access: door portal in the -x side wall, walkway over the shelf, steel stair, exit light, bollards",
}


def content(tag):
    if tag.startswith("K"):
        k = int(tag[1:])
        return "pillar line %d (z = %.1f): pillars, coffers, transverse beam at z = %.1f with its lamps, floor, slopes, shelves, walls" % (
            k, C.line_z(k), C.line_z(k) - C.LINE_PITCH * 0.5)
    return CONTENT[tag]
GODOT_LIGHT = {
    # suggested real-light values (characters only; the hall is light-mapped and takes only their specular)
    "Bay": {"type": "SpotLight3D", "godot_energy": 9.0, "range": 26.0, "spot_angle_deg": 62.0, "spot_attenuation": 1.2},
    "Wall": {"type": "SpotLight3D", "godot_energy": 4.0, "range": 16.0, "spot_angle_deg": 55.0, "spot_attenuation": 1.2},
    "Strip": {"type": "OmniLight3D", "godot_energy": 1.5, "range": 6.0},
    "Shaft": {"type": "SpotLight3D", "godot_energy": 6.0, "range": 60.0, "spot_angle_deg": 35.0, "spot_attenuation": 1.0},
    "Sky": {"type": "SpotLight3D", "godot_energy": 4.0, "range": 80.0, "spot_angle_deg": 30.0, "spot_attenuation": 1.0},
    "Exit": {"type": "OmniLight3D", "godot_energy": 0.6, "range": 7.0},
}
KELVIN = {"Bay": C.LAMP_K, "Wall": C.WALL_LAMP_K, "Strip": C.WALL_LAMP_K, "Shaft": 5200.0, "Sky": 6500.0, "Exit": 0.0}


def _layer_col(lc, name):
    if lc.collection.name == name:
        return lc
    for ch in lc.children:
        r = _layer_col(ch, name)
        if r is not None:
            return r
    return None


def _set_excluded(name, excluded):
    lc = _layer_col(bpy.context.view_layer.layer_collection, name)
    if lc is not None:
        lc.exclude = excluded


def export_objects(tag):
    col = bpy.data.collections["TK_" + tag]
    return [o for o in col.all_objects if o.type == "MESH" or (o.type == "EMPTY" and "|TK_" in o.name)]


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
    return {"nodes": [n.get("name") for n in js.get("nodes", [])], "materials": [m.get("name") for m in js.get("materials", [])],
            "attributes": sorted(attrs), "bytes": len(data)}


def export_module(tag):
    name = MODULES[tag]
    objs = export_objects(tag)
    renamed = []
    path = "%s/%s.glb" % (C.ROOT, name)
    try:
        for o in objs:
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
                if me.uv_layers.get("UVMap") is not None:
                    me.uv_layers["UVMap"].active_render = True
        _gltf(path)
    finally:
        for o, old, mold in renamed:
            o.name = old
            if mold is not None:
                o.data.name = mold
    info = glb_info(path)
    write_glb_import(name)
    return {"glb": path, "nodes": len(info["nodes"]), "materials": info["materials"], "attributes": info["attributes"], "bytes": info["bytes"]}


# ------------------------------------------------------------------ layout json
def _round(v, n=4):
    return [round(float(x), n) for x in v]


def module_lights(tag):
    col = bpy.data.collections["TK_" + tag]
    lights = []
    for o in sorted(col.all_objects, key=lambda x: x.name):
        if o.type == "EMPTY" and "|TK_Light_" in o.name:
            node = o.name.split("|", 1)[1]
            kind = o.get("tk_kind") or node.split("_")[2]
            ldata = bpy.data.objects.get(o.name.replace("|TK_Light_", "|LGT_"))
            pos = C.b2g(o.matrix_basis.translation)
            fwd = C.b2g(o.matrix_basis.to_3x3() @ Vector((0.0, 1.0, 0.0)))
            entry = {"node": node, "kind": kind, "position": _round(pos), "direction": _round(fwd.normalized()), "kelvin": KELVIN[kind]}
            if ldata is not None:
                entry["color_linear"] = _round(ldata.data.color, 4)
                entry["blender_power_w"] = round(ldata.data.energy, 2)
                if ldata.data.type == "SPOT":
                    entry["blender_spot_size_deg"] = round(math.degrees(ldata.data.spot_size), 1)
                    entry["blender_spot_blend"] = round(ldata.data.spot_blend, 3)
            entry.update(GODOT_LIGHT[kind])
            lights.append(entry)
    return lights


def module_triangles(tag):
    col = bpy.data.collections["TK_" + tag]
    tris = {}
    for o in col.all_objects:
        if o.type == "MESH":
            tris[o.name.split("|", 1)[1]] = C.tri_count(o)
    return tris


def _meta(unit):
    path = os.path.join(CACHE_BAKE, "%s_meta.json" % unit)
    if not os.path.exists(path):
        return None
    with open(path) as fh:
        return json.load(fh)


def write_layout():
    data = {
        "units": "metres, Godot axes (Y up); x = -v across the tank (side walls at +-35.5), z = 132.8 - u along it "
                 "(u from the pump gate face); trench floor at y = 0 (Godot places the modules at y = SuddenDeathLayout.FLOOR_Y)",
        "survey": "docs/surge_tank_reproduction.md",
        "hall": {
            "inner_half_width": C.INNER_HALF, "z_pump_gate": C.Z_PUMP, "z_end_wall": C.z_of(C.END_U), "height": C.H,
            "chamfer_z": C.z_of(C.CHAMFER_U0), "end_half_width": C.END_HALF,
            "line_z": [C.line_z(k) for k in range(C.LINES)], "line_pitch": C.LINE_PITCH,
            "transverse_beam_z": [C.line_z(k) - C.LINE_PITCH * 0.5 for k in range(-1, C.LINES)],
            "rows_x": [-v for v in C.ROWS],
            "pillars": [{"x": x, "z": z, "v": v, "line": k, "on_shelf": C.on_shelf(v, C.line_u(k))} for (x, z, v, k) in C.pillars()],
            "pillar": {"length": 2.0 * C.PIL_HALF_LEN, "width": 2.0 * C.PIL_R, "end_radius": C.PIL_R, "head_y": C.PIL_HEAD_Y,
                       "flare_y": C.FLARE_Y, "flare_out": C.FLARE_OUT},
            "trench": {"shelf_y": C.SHELF_Y, "slope_run": C.SLOPE_RUN,
                       "crest_half_width": [{"z": C.z_of(u), "half": C.crest(u)} for u in (0.0,) + tuple(C.TRENCH_U) + (C.END_U,)]},
            "beam_soffit_y": C.BEAM_Y, "transverse_beam_width": C.TB_W, "pillar_head_beam_half_width": C.LB_HALF_W,
            "haunch": C.HAUNCH, "wall_fillet": C.WALL_FILLET, "catwalk_y": C.CATWALK_Y, "catwalk_width": C.CATWALK_W,
            "pump_end": {"dividing_walls_x": [-v for v in C.PIERS_V], "wall_half": C.PIER_HALF, "tip_z": C.z_of(C.PIER_TIP_U),
                         "channels_x": [-v for v in C.CHANNELS_V], "channel_half": C.CHANNEL_HALF, "chamber_depth": C.CHANNEL_DEPTH},
            "shaft_end": {"openings_half": C.OPEN_HALF, "pier_half": C.OPEN_PIER_HALF, "opening_top": C.OPEN_TOP},
            "shaft1": {"radius": C.SHAFT_R, "centre_z": C.z_of(C.SHAFT_CENTRE_U), "top_y": C.SHAFT_TOP, "bottom_y": C.SHAFT_BOTTOM},
        },
        "uv0_metres_per_unit": {"TK_Concrete": C.S_CONCRETE, "TK_Floor": C.S_FLOOR, "TK_Steel": C.S_STEEL, "TK_Paint": C.S_STEEL,
                                "TK_Galv": C.S_GALV, "TK_Grate": C.S_GRATE,
                                "note": "walls, ceiling and floor are world-projected in Godot; pillars, dividing walls and the shaft wall use UV0 (wrapped round)"},
        "lightmap_encoding": {
            "uv": "UV2 (glTF TEXCOORD_1), one atlas per module",
            "rgb": "pow(texel, 2.2) * light_max = E * grime, E = Cycles diffuse bake (direct + indirect, white Lambertian, scene-linear, exposure 0)",
            "alpha": "ambient occlusion (1 m)",
        },
        "modules": {},
        "instances": [],
    }
    for tag, name in MODULES.items():
        data["modules"][name] = {"file": "%s.glb" % name, "content": content(tag), "placement": "hall coordinates: place at the origin",
                                 "triangles": module_triangles(tag), "lights": module_lights(tag)}
        data["modules"][name]["triangles_total"] = sum(data["modules"][name]["triangles"].values())
        meta = _meta(tag)
        entry = {"unit": tag, "module": name, "z": 0.0}
        if tag.startswith("K"):
            entry["line"] = int(tag[1:])
        if meta:
            entry.update({"lightmap": "textures/%s_light.png" % name, "light_max": round(meta["light_max"], 6),
                          "lightmap_size": meta["size"][0], "light_clipped_fraction": round(meta.get("clipped_fraction", 0.0), 5)})
        data["instances"].append(entry)
    with open(LAYOUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1, ensure_ascii=False)
    return {"layout": LAYOUT, "instances": len(data["instances"])}


# ------------------------------------------------------------------ tiling textures + Godot import presets
SHARED_TEXTURES = ("concrete_albedo", "concrete_normal", "concrete_orm", "floor_albedo", "floor_normal", "floor_orm", "floor_wet",
                   "steel_albedo", "steel_normal", "steel_orm", "galv_albedo", "galv_normal", "galv_orm",
                   "grate_albedo", "grate_normal", "grate_orm", "detail_normal")


def copy_shared_textures():
    """The tiling PBR sets come from the underground_temple delivery (self-authored in Blender)."""
    done = []
    for n in SHARED_TEXTURES:
        src = "%s/%s.png" % (C.OLD_TEXTURES, n)
        dst = "%s/%s.png" % (C.TEXTURES, n)
        if os.path.exists(src) and not os.path.exists(dst):
            shutil.copyfile(src, dst)
            done.append(n)
    return done


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
meshes/generate_lods=false
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


def _write_preset(path, text):
    """Write the preset; keep Godot's own [remap] head (uid, paths) of an existing .import."""
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            old = fh.read()
        if "[params]" in old:
            text = old.split("[params]")[0] + "[params]" + text.split("[params]")[1]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def write_glb_import(name):
    _write_preset("%s/%s.glb.import" % (C.ROOT, name), GLB_IMPORT)


def write_texture_imports():
    done = []
    for fn in sorted(os.listdir(C.TEXTURES)):
        if not fn.endswith(".png"):
            continue
        normal = 1 if fn.endswith("_normal.png") else 2
        fix = "true" if fn in ("grate_albedo.png",) else "false"
        hq = "false" if normal == 1 else "true"
        _write_preset("%s/%s.import" % (C.TEXTURES, fn), TEX_IMPORT.format(hq=hq, normal=normal, fix=fix))
        done.append(fn)
    return done

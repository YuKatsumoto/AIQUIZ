"""Export the shaft-descent GLBs and layout JSON from the LIVE Blender session.

    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/shaft_descent/source/export_shaft.py",
              encoding="utf-8").read(), {"__name__": "__main__"})

shaft_tile.glb   one 5 m ring: SHD_Tile_Wall (UV0 = baked textures), _Rails, _Galv, _Cables,
                 _LampBody, _LampGlass. Godot stacks 12 of them with MultiMeshes.
shaft_deck.glb   SHD_Deck_Root: grating, hazard band, frame, pad plates, metal, 4 WireAnchor empties.
shaft_mouth.glb  SHD_Mouth_Root: collar, liner, blade pocket, SHD_Blade_0..7 (origins = pivots),
                 SHD_Beacon_0..3 with _Lens and _Reflector children (beam = local +X).
shaft_sign.glb   SHD_Sign_Root: blank board facing Godot -Z, TextAnchor empty on the face.
Materials are exported as named placeholders; Godot assigns its own shaders by name.
"""
import json
import math

import bpy

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/shaft_descent/source/shaft_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)


def _select(objects):
    bpy.context.view_layer.update()
    for obj in bpy.context.scene.objects:
        if obj.select_get():
            obj.select_set(False)
    for obj in objects:
        obj.hide_viewport = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def _gltf(path):
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
        export_apply=True, export_yup=True, export_texcoords=True, export_normals=True,
        export_tangents=False, export_materials="PLACEHOLDER", export_extras=False,
        export_cameras=False, export_lights=False, export_animations=False,
    )


def _export_root(root_name, path):
    root = bpy.data.objects[root_name]
    saved = (root.location.copy(), root.rotation_euler.copy())
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    objs = [root] + list(root.children_recursive)
    try:
        _select(objs)
        _gltf(path)
    finally:
        root.location, root.rotation_euler = saved
    return len(objs)


def layout():
    """Godot-space numbers the ShaftDescent script relies on (Y up, metres)."""
    def gpos(psi, r, y):
        a = math.radians(psi)
        return [round(r * math.cos(a), 4), round(y, 4), round(r * math.sin(a), 4)]

    return {
        "units": "metres, Godot axes (Y up); azimuth psi from +X toward +Z",
        "tile": {
            "height": C.TILE_H, "inner_radius": C.R, "form_joint_y": list(C.JOINT_Z),
            "lamp_psi": list(C.LAMP_PSI), "lamp_light_y": C.LAMP_Z, "lamp_axis_radius": C.LAMP_R,
            "lamp_light_positions": [gpos(p, C.LAMP_R, C.LAMP_Z) for p in C.LAMP_PSI],
            "rail_psi": list(C.RAIL_PSI), "rail_inner_flange_radius": 6.58,
            "pipes_psi": [p["psi"] for p in C.PIPES], "ladder_psi": C.LADDER_PSI,
            "cable_tray_psi": C.TRAY_PSI, "conduit_y": C.CONDUIT_Z, "sign_psi": C.SIGN_PSI,
            "innermost_prop_radius": 6.08,
        },
        "deck": {
            "radius": C.DECK_RADIUS, "grating_radius": C.GRATING_RADIUS, "depth": C.DECK_DEPTH,
            "top_y": 0.0, "pad_x": C.PAD_X, "pad_plate_radius": C.PAD_PLATE_R,
            "wire_anchors": [gpos(p, C.ANCHOR_R, C.ANCHOR_TOP) for p in C.ANCHOR_PSI],
            "guide_shoe_reach": 6.62, "guide_shoe_top_y": -0.06,
        },
        "mouth": {
            "collar_inner": C.COLLAR_IN, "collar_outer": C.COLLAR_OUT, "top_y": 0.0,
            "iris_inner": C.IRIS_IN, "iris_blades": C.IRIS_BLADES,
            "iris_open": "each blade folds down 92 deg about the tangent through its pivot (hinge r 7.10, y -0.045) into the wall pocket behind the concrete; nothing passes r 7.6 above ground",
            "collar_top_y": C.COLLAR_PROUD,
            "beacon_psi": list(C.BEACON_PSI), "beacon_radius": C.BEACON_R, "beacon_lens_y": 0.21,
        },
        "sign": {"board_size": [1.5, 0.75], "face_offset": 0.124, "faces": "-Z (toward the shaft axis)"},
    }


def main():
    out = {}
    tile = [o for o in bpy.data.collections["SHD_Tile"].objects if o.type == "MESH"]
    _select(tile)
    _gltf(C.ROOT + "/shaft_tile.glb")
    out["tile"] = len(tile)
    out["deck"] = _export_root("SHD_Deck_Root", C.ROOT + "/shaft_deck.glb")
    out["mouth"] = _export_root("SHD_Mouth_Root", C.ROOT + "/shaft_mouth.glb")
    out["sign"] = _export_root("SHD_Sign_Root", C.ROOT + "/shaft_sign.glb")
    tris = {}
    for col_name in ("SHD_Tile", "SHD_Deck", "SHD_Mouth", "SHD_Sign"):
        total = 0
        for obj in bpy.data.collections[col_name].all_objects:
            if obj.type == "MESH":
                obj.data.calc_loop_triangles()
                total += len(obj.data.loop_triangles)
        tris[col_name] = total
    data = layout()
    data["triangles"] = tris
    with open(C.ROOT + "/shaft_descent_layout.json", "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    out["triangles"] = tris
    return out


if __name__ == "__main__":
    result = main()

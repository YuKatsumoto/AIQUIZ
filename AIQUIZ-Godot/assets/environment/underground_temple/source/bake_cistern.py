"""UV2 atlas + baked lighting of one cistern module (LIVE Blender, Cycles on the GPU).

    ns = {"__name__": "cistern_bake"}
    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/bake_cistern.py",
              encoding="utf-8").read(), ns)
    ns["unwrap"]("A")             # UVMap_LM (2nd UV = Godot UV2): non-overlapping atlas
    ns["bake"]("A", "LIGHT")      # diffuse direct + indirect of all static lights, bake stack
    ns["bake"]("A", "AO")
    ns["bake"]("A", "GRIME")      # per-module dirt multiplier (materials_cistern.py)
    ns["denoise"]("A")            # OIDN (compositor Denoise node) on the light bake
    ns["pack"]("A")               # -> textures/<module>_light.png, light_max -> cache json

Bake stack: a bay is baked as the middle of three copies of itself (instances at z = +-15 m,
lights included), so the light of the neighbouring floods is in the map; the ends are baked
with one bay (cistern_bay_a) attached. Intermediate float arrays live in
%TEMP%/aiquiz_cistern_bake.

Encoding (same as assets/environment/shaft_descent): RGB = ((E * grime) / light_max)^(1/2.2),
where E is the Cycles diffuse bake (outgoing radiance of a white Lambertian surface, direct +
indirect, scene-linear, AgX exposure 0 in the review renders) and grime the per-module dirt
multiplier; A = ambient occlusion (1 m distance).
"""
import json
import math
import os
import tempfile
import time

import bpy
import numpy as np

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/cistern_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)

CACHE = os.path.join(tempfile.gettempdir(), "aiquiz_cistern_bake")
LM_UV = "UVMap_LM"

MODULES = {
    "A": "cistern_bay_a", "B": "cistern_bay_b", "C": "cistern_bay_c", "O": "cistern_bay_opening",
    "U": "cistern_end_upstream", "D": "cistern_end_downstream",
}
SIZE = {"A": 2048, "B": 2048, "C": 2048, "O": 2048, "U": 2048, "D": 2048}
# lightmap texel budget for small props relative to architecture
PROP_DENSITY = {"steel": 0.45, "galv": 0.35, "grate": 0.5, "lens": 0.3, "amber": 0.3, "hazard": 0.7,
                "sign": 0.8, "glass": 0.6, "interior": 0.6, "dark": 0.2, "shell": 1.0, "floor": 1.0}


def _cache(name):
    os.makedirs(CACHE, exist_ok=True)
    return os.path.join(CACHE, name)


def _gpu():
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    bpy.context.scene.cycles.device = "GPU"


def _layer_col(lc, name):
    if lc.collection.name == name:
        return lc
    for ch in lc.children:
        r = _layer_col(ch, name)
        if r is not None:
            return r
    return None


def module_meshes(tag):
    col = bpy.data.collections["CIS_" + tag]
    return [o for o in col.objects if o.type == "MESH"]


def _view3d_override():
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                for region in area.regions:
                    if region.type == "WINDOW":
                        return {"window": win, "area": area, "region": region, "screen": win.screen}
    return None


def _include_only(tags, review=False):
    """Include the given module collections in the view layer; exclude the other modules."""
    vl = bpy.context.view_layer
    for c in bpy.data.collections:
        if not c.name.startswith("CIS_"):
            continue
        lc = _layer_col(vl.layer_collection, c.name)
        if lc is None:
            continue
        if c.name == "CIS_Review":
            lc.exclude = not review
        elif c.name == "CIS_TexBake":
            lc.exclude = True
        elif c.name == "CIS_Bake":
            lc.exclude = False
        else:
            lc.exclude = c.name[4:] not in tags
            c.hide_render = False
            c.hide_viewport = False


def _select(objs):
    vl = bpy.context.view_layer
    for o in vl.objects:
        if o.select_get():
            o.select_set(False)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    vl.objects.active = objs[0]


# ------------------------------------------------------------------ UV2 atlas
def unwrap(tag, angle=66.0):
    t = time.time()
    _include_only([tag])
    objs = module_meshes(tag)
    for o in objs:
        me = o.data
        while len(me.uv_layers) > 2:
            me.uv_layers.remove(me.uv_layers[-1])
        lm = me.uv_layers.get(LM_UV) or me.uv_layers.new(name=LM_UV)
        me.uv_layers.active = lm
        me.uv_layers["UVMap"].active_render = True
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    _select(objs)
    ov = _view3d_override()
    ctx = bpy.context.temp_override(**ov) if ov else None

    def run(fn, **kw):
        if ctx is not None:
            with bpy.context.temp_override(**ov):
                return fn(**kw)
        return fn(**kw)

    run(bpy.ops.object.mode_set, mode="EDIT")
    run(bpy.ops.mesh.select_all, action="SELECT")
    run(bpy.ops.uv.smart_project, angle_limit=math.radians(angle), island_margin=0.0, area_weight=0.0,
        correct_aspect=True, scale_to_bounds=False)
    run(bpy.ops.uv.select_all, action="SELECT")
    run(bpy.ops.uv.average_islands_scale)
    run(bpy.ops.object.mode_set, mode="OBJECT")
    # lower texel density on the small hardware
    for o in objs:
        k = PROP_DENSITY.get(o.get("cis_part", "shell"), 1.0)
        if abs(k - 1.0) > 1e-6:
            uv = o.data.uv_layers[LM_UV].data
            arr = np.empty(len(uv) * 2, np.float32)
            uv.foreach_get("uv", arr)
            arr *= k
            uv.foreach_set("uv", arr)
    _select(objs)
    run(bpy.ops.object.mode_set, mode="EDIT")
    run(bpy.ops.mesh.select_all, action="SELECT")
    run(bpy.ops.uv.select_all, action="SELECT")
    size = SIZE[tag]
    run(bpy.ops.uv.pack_islands, udim_source="CLOSEST_UDIM", rotate=True, rotate_method="AXIS_ALIGNED",
        scale=True, merge_overlap=False, margin_method="FRACTION", margin=6.0 / size, shape_method="CONCAVE")
    run(bpy.ops.object.mode_set, mode="OBJECT")
    for o in objs:
        o.data.uv_layers.active = o.data.uv_layers[LM_UV]
        o.data.uv_layers["UVMap"].active_render = True
    # texel size estimate: total world area vs covered UV area
    world_area, uv_area = 0.0, 0.0
    for o in objs:
        me = o.data
        uvl = me.uv_layers[LM_UV].data
        for poly in me.polygons:
            world_area += poly.area
            pts = [uvl[li].uv for li in poly.loop_indices]
            a = 0.0
            for i in range(len(pts)):
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % len(pts)]
                a += x0 * y1 - x1 * y0
            uv_area += abs(a) * 0.5
    shell = [o for o in objs if o.get("cis_part") == "shell"][0]
    sa, su = 0.0, 0.0
    uvl = shell.data.uv_layers[LM_UV].data
    for poly in shell.data.polygons:
        sa += poly.area
        pts = [uvl[li].uv for li in poly.loop_indices]
        a = 0.0
        for i in range(len(pts)):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % len(pts)]
            a += x0 * y1 - x1 * y0
        su += abs(a) * 0.5
    texel = math.sqrt(sa / max(1e-9, su * size * size))
    return {"module": MODULES[tag], "objects": len(objs), "uv_coverage": round(uv_area, 3),
            "architecture_texel_m": round(texel, 4), "secs": round(time.time() - t, 1)}


# ------------------------------------------------------------------ bake stack
def _stack(tag):
    col = C.collection("CIS_Bake")
    for o in list(col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    made = []
    if tag in ("A", "B", "C", "O"):
        for dz in (-15.0, 15.0):
            e = bpy.data.objects.new("BAKE_Inst_%+d" % dz, None)
            e.instance_type = "COLLECTION"
            e.instance_collection = bpy.data.collections["CIS_" + tag]
            e.location = C.g2b((0.0, 0.0, dz))
            col.objects.link(e)
            made.append(e)
    else:
        dz = -15.0 if tag == "U" else 195.0
        e = bpy.data.objects.new("BAKE_Inst_bay", None)
        e.instance_type = "COLLECTION"
        e.instance_collection = bpy.data.collections["CIS_A"]
        e.location = C.g2b((0.0, 0.0, dz))
        col.objects.link(e)
        made.append(e)
    return made


def _image(name, w, h):
    img = bpy.data.images.get(name)
    if img is not None and (img.size[0] != w or img.size[1] != h):
        bpy.data.images.remove(img)
        img = None
    if img is None:
        img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    return img


def _materials(objs):
    mats = []
    for o in objs:
        for m in o.data.materials:
            if m is not None and m not in mats:
                mats.append(m)
    return mats


def bake(tag, what, samples=None, size=None):
    """what: LIGHT (diffuse direct+indirect), AO or GRIME."""
    t = time.time()
    _gpu()
    sc = bpy.context.scene
    size = size or SIZE[tag]
    _include_only([tag])
    stack = _stack(tag)
    fog = bpy.data.objects.get("REV_Fog")
    if fog is not None:
        fog.hide_render = True
    objs = module_meshes(tag)
    for o in objs:
        o.data.uv_layers.active = o.data.uv_layers[LM_UV]
    img = _image("CIS_LMBake", size, size)
    mats = _materials(objs)
    for m in mats:
        n = m.node_tree.nodes.get("BAKE_TARGET")
        n.image = img
        m.node_tree.nodes.active = n
    _select(objs)
    sc.render.engine = "CYCLES"
    sc.cycles.use_denoising = False
    sc.render.bake.margin = 12
    sc.render.bake.target = "IMAGE_TEXTURES"
    sc.cycles.max_bounces = 8
    sc.cycles.diffuse_bounces = 4
    sc.cycles.glossy_bounces = 2
    sc.cycles.transparent_max_bounces = 8
    # no caustics through the mirror puddles (fireflies), clamp stray indirect samples
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.blur_glossy = 1.0
    sc.cycles.sample_clamp_indirect = 3.0
    old_mode = None
    mats_ns = {"__name__": "cistern_mats_bake"}
    exec(open(C.SOURCE + "/materials_cistern.py", encoding="utf-8").read(), mats_ns)
    try:
        if what == "LIGHT":
            sc.cycles.samples = samples or 1024
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"}, margin=12, use_clear=True)
        elif what == "AO":
            sc.cycles.samples = samples or 256
            sc.world.light_settings.distance = 1.0
            bpy.ops.object.bake(type="AO", margin=12, use_clear=True)
        elif what == "GRIME":
            sc.cycles.samples = samples or 16
            mats_ns["set_bake_mode"](1)
            bpy.ops.object.bake(type="EMIT", margin=12, use_clear=True)
        arr = np.empty(size * size * 4, np.float32)
        img.pixels.foreach_get(arr)
        arr = arr.reshape(size, size, 4)
    finally:
        mats_ns["set_bake_mode"](0)
        for m in mats:
            m.node_tree.nodes["BAKE_TARGET"].image = None
        for e in stack:
            bpy.data.objects.remove(e, do_unlink=True)
        for o in objs:
            o.data.uv_layers.active = o.data.uv_layers[LM_UV]
        bpy.context.view_layer.update()
    np.save(_cache("%s_%s.npy" % (tag, what.lower())), arr[:, :, :3].copy())
    lum = arr[:, :, :3].mean(axis=2)
    return {"module": MODULES[tag], "what": what, "secs": round(time.time() - t, 1),
            "mean": round(float(lum.mean()), 5), "p99": round(float(np.percentile(lum, 99)), 5), "max": round(float(lum.max()), 4)}


# ------------------------------------------------------------------ denoise (OIDN via the compositor)
def _oidn(arr, albedo=None, label="dn"):
    """Denoise an HxWx3 float array with Blender's compositor Denoise node (OpenImageDenoise)."""
    h, w, _ = arr.shape
    src = bpy.data.images.get("CIS_DN_In") or bpy.data.images.new("CIS_DN_In", w, h, alpha=True, float_buffer=True)
    if src.size[0] != w or src.size[1] != h:
        src.scale(w, h)
    src.colorspace_settings.name = "Non-Color"
    src.pixels.foreach_set(np.dstack([arr, np.ones((h, w), np.float32)]).astype(np.float32).ravel())
    src.update()
    sc = bpy.data.scenes.get("CIS_Denoise") or bpy.data.scenes.new("CIS_Denoise")
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.use_compositing = True
    sc.render.use_sequencer = False
    sc.view_settings.view_transform = "Standard"
    sc.display_settings.display_device = "sRGB"
    try:
        sc.view_settings.view_transform = "Raw"
    except Exception:
        pass
    if sc.camera is None:
        cd = bpy.data.cameras.new("CIS_DN_Cam")
        co = bpy.data.objects.new("CIS_DN_Cam", cd)
        sc.collection.objects.link(co)
        sc.camera = co
    # compositor node group (Blender 5.x) or legacy node_tree
    tree = None
    if hasattr(sc, "compositing_node_group"):
        tree = bpy.data.node_groups.get("CIS_DN_Comp")
        if tree is None:
            tree = bpy.data.node_groups.new("CIS_DN_Comp", "CompositorNodeTree")
            tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        sc.compositing_node_group = tree
        tree.nodes.clear()
        out = tree.nodes.new("NodeGroupOutput")
        out_sock = out.inputs[0]
    else:
        sc.use_nodes = True
        tree = sc.node_tree
        tree.nodes.clear()
        out = tree.nodes.new("CompositorNodeComposite")
        out_sock = out.inputs[0]
    im = tree.nodes.new("CompositorNodeImage")
    im.image = src
    dn = tree.nodes.new("CompositorNodeDenoise")
    try:
        dn.prefilter = "ACCURATE"
    except Exception:
        pass
    try:
        dn.use_hdr = True
    except Exception:
        pass
    tree.links.new(im.outputs["Image"], dn.inputs["Image"])
    if albedo is not None:
        alb = bpy.data.images.get("CIS_DN_Alb") or bpy.data.images.new("CIS_DN_Alb", w, h, alpha=True, float_buffer=True)
        if alb.size[0] != w or alb.size[1] != h:
            alb.scale(w, h)
        alb.colorspace_settings.name = "Non-Color"
        alb.pixels.foreach_set(np.dstack([albedo, np.ones((h, w), np.float32)]).astype(np.float32).ravel())
        ia = tree.nodes.new("CompositorNodeImage")
        ia.image = alb
        tree.links.new(ia.outputs["Image"], dn.inputs["Albedo"])
    tree.links.new(dn.outputs["Image"], out_sock)
    path = _cache("%s_oidn.exr" % label)
    sc.render.image_settings.file_format = "OPEN_EXR"
    sc.render.image_settings.color_depth = "32"
    sc.render.filepath = path
    win = bpy.context.window or bpy.context.window_manager.windows[0]
    prev = win.scene
    try:
        win.scene = sc
        with bpy.context.temp_override(window=win, scene=sc):
            bpy.ops.render.render(write_still=True, scene=sc.name)
    finally:
        win.scene = prev
    res = bpy.data.images.load(path, check_existing=False)
    res.colorspace_settings.name = "Non-Color"
    out_arr = np.empty(w * h * 4, np.float32)
    res.pixels.foreach_get(out_arr)
    bpy.data.images.remove(res)
    return out_arr.reshape(h, w, 4)[:, :, :3].copy()


def denoise(tag):
    t = time.time()
    light = np.load(_cache("%s_light.npy" % tag))
    # guide with the AO so contact shadows survive
    ao = np.load(_cache("%s_ao.npy" % tag)) if os.path.exists(_cache("%s_ao.npy" % tag)) else None
    dn = _oidn(light, albedo=ao, label=tag)
    np.save(_cache("%s_light_dn.npy" % tag), dn)
    return {"module": MODULES[tag], "secs": round(time.time() - t, 1),
            "noise_removed_rms": round(float(np.sqrt(((light - dn) ** 2).mean())), 6), "mean": round(float(dn.mean()), 5)}


# ------------------------------------------------------------------ pack
def save_png(name, rgba, path):
    h, w, ch = rgba.shape
    img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.clip(rgba, 0.0, 1.0).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def pack(tag, percentile=99.5, headroom=1.25):
    t = time.time()
    name = MODULES[tag]
    lf = _cache("%s_light_dn.npy" % tag)
    light = np.load(lf if os.path.exists(lf) else _cache("%s_light.npy" % tag))
    grime = np.load(_cache("%s_grime.npy" % tag))
    ao = np.load(_cache("%s_ao.npy" % tag))[:, :, 0]
    lm = np.maximum(light, 0.0) * np.clip(grime, 0.0, 2.0)
    lum = lm.max(axis=2)
    # the hottest texels (inside the luminaires, the pillar face right at a flood) clip
    lmax = headroom * float(np.percentile(lum[lum > 1e-6], percentile)) if (lum > 1e-6).any() else 1.0
    enc = np.power(np.clip(lm / lmax, 0.0, 1.0), 1.0 / 2.2)
    rgba = np.dstack([enc, np.clip(ao, 0.0, 1.0)])
    path = "%s/%s_light.png" % (C.TEXTURES, name)
    save_png("CIS_PackLM", rgba, path)
    meta = {"module": name, "light_max": lmax, "size": list(lm.shape[:2]), "percentile": percentile, "headroom": headroom,
            "clipped_fraction": float((lum > lmax).mean()),
            "mean_encoded": float(enc.mean()), "ao_mean": float(ao.mean())}
    with open(_cache("%s_meta.json" % tag), "w") as fh:
        json.dump(meta, fh)
    meta["secs"] = round(time.time() - t, 1)
    meta["file"] = path
    return meta

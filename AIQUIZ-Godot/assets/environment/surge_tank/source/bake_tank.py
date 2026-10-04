"""UV2 atlas + baked lighting of the surge tank (LIVE Blender, Cycles on the GPU).

    ns = {"__name__": "tank_bake"}
    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/bake_tank.py", encoding="utf-8").read(), ns)
    ns["unwrap"]("K03")            # UVMap_LM (2nd UV = Godot UV2) of a module: K00..K10, P, S, Q, T
    ns["bake"]("K03", "LIGHT")     # every module is its own bake unit
    ns["bake"]("K03", "AO"); ns["bake"]("K03", "GRIME")
    ns["denoise"]("K03")           # OIDN (compositor Denoise node) on the light bake
    ns["pack"]("K03")              # -> textures/tank_line_03_light.png, light_max -> cache json

The whole tank is in the scene for every bake (all slices, both ends, the shaft and the stairs), so every
unit gets the light of its real neighbours and the daylight of shaft No.1; only the unit's own objects are
selected.

Encoding: RGB = ((E * grime) / light_max)^(1/2.2), E the Cycles diffuse bake (outgoing radiance of a
white Lambertian surface, direct + indirect, scene-linear, exposure 0), grime the dirt multiplier of
materials_tank.py; A = ambient occlusion (1 m).
"""
import json
import math
import os
import tempfile
import time

import bpy
import numpy as np

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/tank_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)

CACHE = os.path.join(tempfile.gettempdir(), "aiquiz_tank_bake")
# A queued job stops at its next step while this file exists (jobs.py runs each step from a fresh exec).
CANCEL_FLAG = os.path.join(tempfile.gettempdir(), "aiquiz_tank_jobs", "CANCEL")
if os.path.exists(CANCEL_FLAG):
    raise RuntimeError("cancelled by %s" % CANCEL_FLAG)
LM_UV = "UVMap_LM"
SIZE = {"P": 2048, "S": 2048, "Q": 2048, "T": 1024}       # K00..K10: 2048
PROP_DENSITY = {"steel": 0.4, "galv": 0.3, "grate": 0.45, "lens": 0.25, "dark": 0.15, "shell": 1.0, "floor": 1.0}
# lower architecture density on the shaft walls (far away, bright, plain)
MODULE_SHELL_DENSITY = {"Q": 0.55}


def unit_type(unit):
    return unit


def unit_size(unit):
    return SIZE.get(unit, 2048)


def unit_name(unit):
    if unit.startswith("K"):
        return "tank_line_%02d" % int(unit[1:])
    return {"S": "tank_end_shaft", "Q": "tank_shaft1", "P": "tank_end_pump", "T": "tank_stairs"}[unit]


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


def _set_excluded(name, excluded):
    lc = _layer_col(bpy.context.view_layer.layer_collection, name)
    if lc is not None:
        lc.exclude = excluded


def unit_meshes(unit):
    return [o for o in bpy.data.collections["TK_" + unit].objects if o.type == "MESH"]


def type_meshes(typ):
    return [o for o in bpy.data.collections["TK_" + typ].objects if o.type == "MESH"]


def _view3d_override():
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                for region in area.regions:
                    if region.type == "WINDOW":
                        return {"window": win, "area": area, "region": region, "screen": win.screen}
    return None


def _select(objs):
    vl = bpy.context.view_layer
    for o in vl.objects:
        if o.select_get():
            o.select_set(False)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    vl.objects.active = objs[0]


def _hall_mode():
    """Every module in, the default collection out. Parents first: (re)including a parent layer collection
    resets the exclude flag of its children."""
    _set_excluded("TK_Modules", False)
    for unit in units():
        _set_excluded("TK_" + unit, False)
    _set_excluded("Collection", True)
    vl = bpy.context.view_layer
    stray = [o.name for o in vl.objects if o.name.startswith(("E|", "O|")) or o.name.split("|")[0] in ("K11",)]
    if stray:
        raise RuntimeError("objects of the first build still in the view layer: %s" % stray[:4])


# ------------------------------------------------------------------ UV2 atlas
def unwrap(typ, angle=66.0):
    t = time.time()
    _hall_mode()
    objs = type_meshes(typ)
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

    def run(fn, **kw):
        if ov is not None:
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
    for o in objs:
        part = o.get("tk_part", "shell")
        k = PROP_DENSITY.get(part, 1.0)
        if part == "shell":
            k *= MODULE_SHELL_DENSITY.get(typ, 1.0)
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
    size = unit_size(typ)
    run(bpy.ops.uv.pack_islands, udim_source="CLOSEST_UDIM", rotate=True, rotate_method="AXIS_ALIGNED",
        scale=True, merge_overlap=False, margin_method="FRACTION", margin=6.0 / size, shape_method="CONCAVE")
    run(bpy.ops.object.mode_set, mode="OBJECT")
    for o in objs:
        o.data.uv_layers.active = o.data.uv_layers[LM_UV]
        o.data.uv_layers["UVMap"].active_render = True
    # architecture texel size
    shell = [o for o in objs if o.get("tk_part") == "shell"][0]
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
    return {"type": typ, "objects": len(objs), "architecture_texel_m": round(texel, 4), "secs": round(time.time() - t, 1)}


# ------------------------------------------------------------------ bakes
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


def bake(unit, what, samples=None):
    """what: LIGHT (diffuse direct+indirect), AO or GRIME."""
    t = time.time()
    _gpu()
    sc = bpy.context.scene
    size = unit_size(unit)
    _hall_mode()
    objs = unit_meshes(unit)
    for o in objs:
        o.data.uv_layers.active = o.data.uv_layers[LM_UV]
    img = _image("TK_LMBake", size, size)
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
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.blur_glossy = 1.0
    sc.cycles.sample_clamp_indirect = 4.0
    mats_ns = {"__name__": "tank_mats_bake"}
    exec(open(C.SOURCE + "/materials_tank.py", encoding="utf-8").read(), mats_ns)
    try:
        if what == "LIGHT":
            sc.cycles.samples = samples or 384
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"}, margin=12, use_clear=True)
        elif what == "AO":
            sc.cycles.samples = samples or 128
            sc.world.light_settings.distance = 1.0
            bpy.ops.object.bake(type="AO", margin=12, use_clear=True)
        elif what == "GRIME":
            sc.cycles.samples = samples or 8
            mats_ns["set_bake_mode"](1)
            bpy.ops.object.bake(type="EMIT", margin=12, use_clear=True)
        arr = np.empty(size * size * 4, np.float32)
        img.pixels.foreach_get(arr)
        arr = arr.reshape(size, size, 4)
    finally:
        mats_ns["set_bake_mode"](0)
        for m in mats:
            m.node_tree.nodes["BAKE_TARGET"].image = None
        bpy.context.view_layer.update()
    np.save(_cache("%s_%s.npy" % (unit, what.lower())), arr[:, :, :3].copy())
    lum = arr[:, :, :3].mean(axis=2)
    return {"unit": unit, "what": what, "secs": round(time.time() - t, 1),
            "mean": round(float(lum.mean()), 5), "p99": round(float(np.percentile(lum, 99)), 5), "max": round(float(lum.max()), 4)}


# ------------------------------------------------------------------ denoise (OIDN via the compositor)
def _oidn(arr, albedo=None, label="dn"):
    """Denoise an HxWx3 float array with Blender's compositor Denoise node (OpenImageDenoise)."""
    h, w, _ = arr.shape
    src = bpy.data.images.get("TK_DN_In")
    if src is not None and (src.size[0] != w or src.size[1] != h):
        bpy.data.images.remove(src)
        src = None
    if src is None:
        src = bpy.data.images.new("TK_DN_In", w, h, alpha=True, float_buffer=True)
    src.colorspace_settings.name = "Non-Color"
    src.pixels.foreach_set(np.dstack([arr, np.ones((h, w), np.float32)]).astype(np.float32).ravel())
    src.update()
    sc = bpy.data.scenes.get("TK_Denoise") or bpy.data.scenes.new("TK_Denoise")
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.use_compositing = True
    sc.render.use_sequencer = False
    sc.display_settings.display_device = "sRGB"
    try:
        sc.view_settings.view_transform = "Raw"
    except Exception:
        sc.view_settings.view_transform = "Standard"
    if sc.camera is None:
        cd = bpy.data.cameras.new("TK_DN_Cam")
        co = bpy.data.objects.new("TK_DN_Cam", cd)
        sc.collection.objects.link(co)
        sc.camera = co
    tree = None
    if hasattr(sc, "compositing_node_group"):
        tree = bpy.data.node_groups.get("TK_DN_Comp")
        if tree is None:
            tree = bpy.data.node_groups.new("TK_DN_Comp", "CompositorNodeTree")
            tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        sc.compositing_node_group = tree
        tree.nodes.clear()
        out = tree.nodes.new("NodeGroupOutput")
        out_sock = out.inputs[0]
        # a render layer node must exist or Blender skips the render (blender-volatile)
        rl = tree.nodes.new("CompositorNodeRLayers")
        rl.scene = sc
    else:
        sc.use_nodes = True
        tree = sc.node_tree
        tree.nodes.clear()
        out = tree.nodes.new("CompositorNodeComposite")
        out_sock = out.inputs[0]
    im = tree.nodes.new("CompositorNodeImage")
    im.image = src
    dn = tree.nodes.new("CompositorNodeDenoise")
    for attr, val in (("prefilter", "ACCURATE"), ("use_hdr", True)):
        try:
            setattr(dn, attr, val)
        except Exception:
            pass
    tree.links.new(im.outputs["Image"], dn.inputs["Image"])
    if albedo is not None:
        alb = bpy.data.images.get("TK_DN_Alb")
        if alb is not None and (alb.size[0] != w or alb.size[1] != h):
            bpy.data.images.remove(alb)
            alb = None
        if alb is None:
            alb = bpy.data.images.new("TK_DN_Alb", w, h, alpha=True, float_buffer=True)
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


def denoise(unit):
    t = time.time()
    light = np.load(_cache("%s_light.npy" % unit))
    ao = np.load(_cache("%s_ao.npy" % unit)) if os.path.exists(_cache("%s_ao.npy" % unit)) else None
    dn = _oidn(light, albedo=ao, label=unit)
    if not np.isfinite(dn).all() or float(dn.mean()) < 1e-7 < float(light.mean()):
        raise RuntimeError("denoise produced an empty image for %s" % unit)
    np.save(_cache("%s_light_dn.npy" % unit), dn)
    return {"unit": unit, "secs": round(time.time() - t, 1),
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


def pack(unit, percentile=99.5, headroom=1.25):
    t = time.time()
    name = unit_name(unit)
    lf = _cache("%s_light_dn.npy" % unit)
    light = np.load(lf if os.path.exists(lf) else _cache("%s_light.npy" % unit))
    grime = np.load(_cache("%s_grime.npy" % unit))
    ao = np.load(_cache("%s_ao.npy" % unit))[:, :, 0]
    lm = np.maximum(light, 0.0) * np.clip(grime, 0.0, 2.0)
    lum = lm.max(axis=2)
    lmax = headroom * float(np.percentile(lum[lum > 1e-6], percentile)) if (lum > 1e-6).any() else 1.0
    enc = np.power(np.clip(lm / lmax, 0.0, 1.0), 1.0 / 2.2)
    rgba = np.dstack([enc, np.clip(ao, 0.0, 1.0)])
    path = "%s/%s_light.png" % (C.TEXTURES, name)
    save_png("TK_PackLM", rgba, path)
    meta = {"unit": unit, "name": name, "light_max": lmax, "size": list(lm.shape[:2]), "percentile": percentile,
            "headroom": headroom, "clipped_fraction": float((lum > lmax).mean()),
            "mean_encoded": float(enc.mean()), "ao_mean": float(ao.mean())}
    with open(_cache("%s_meta.json" % unit), "w") as fh:
        json.dump(meta, fh)
    meta["secs"] = round(time.time() - t, 1)
    meta["file"] = path
    return meta


def units():
    return ["K%02d" % k for k in range(C.LINES)] + ["P", "S", "Q", "T"]

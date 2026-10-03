"""Bake and pack the shaft concrete textures in the LIVE Blender (Cycles on the GPU).

Run step by step through bl_execute after build_shaft.py, one step per call so no
single connector call runs long:

    ns = {}
    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/shaft_descent/source/bake_shaft.py",
              encoding="utf-8").read(), ns)
    ns["bake_mask"](1)            # 1 height, 2 tone, 3 wet, 4 efflorescence, 5 rust (8192 x 1024)
    ns["bake_detail"]()           # 1 m tileable micro relief (1024^2)
    ns["bake_light"]("DIRECT")    # lamp light of 5 stacked tiles onto the centre wall
    ns["bake_light"]("INDIRECT")
    ns["calibrate"]()             # baked value of the same lamp at 2 m, normal incidence
    ns["pack"]()                  # -> textures/*.png + textures/shaft_bake.json

Intermediate float arrays live in %TEMP%/aiquiz_shaft_bake (not in the repo).

Outputs (all tile seamlessly: 2*pi around, 5 m vertically):
  shaft_wall_masks.png   R tone (linear albedo), G wetness, B efflorescence, A rust bleed
  shaft_wall_normal.png  RGB tangent normal (OpenGL, +V up), A cavity occlusion
  shaft_wall_light.png   lamp irradiance of the centre tile of a 5-tile stack, gamma 2.2
                         encoded, white lamps; Godot multiplies by light_max / C
  shaft_concrete_detail_normal.png  1 m x 1 m micro normal for close-ups
"""
import json
import math
import os
import tempfile
import time

import bpy
import numpy as np

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/shaft_descent/source/shaft_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)

CACHE = os.path.join(tempfile.gettempdir(), "aiquiz_shaft_bake")
MASK_W, MASK_H = 8192, 1024
LIGHT_W, LIGHT_H = 2048, 512
INDIRECT_W, INDIRECT_H = 1024, 256
DETAIL = 1024
WALL_V_LENGTH = 5.060307756402823     # profile length of the wall (grooves included)
LAMP_POWER = 60.0
HIDE_FOR_BAKE = ("SHD_Deck", "SHD_Mouth", "SHD_Sign", "SHD_Aux", "SHD_Review")


def _cache(name):
    os.makedirs(CACHE, exist_ok=True)
    return os.path.join(CACHE, name)


def _gpu():
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prev = prefs.compute_device_type
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    bpy.context.scene.cycles.device = "GPU"
    return prev


def _restore_gpu(prev):
    bpy.context.preferences.addons["cycles"].preferences.compute_device_type = prev


def _image(name, w, h):
    img = bpy.data.images.get(name)
    if img is not None and (img.size[0] != w or img.size[1] != h):
        bpy.data.images.remove(img)
        img = None
    if img is None:
        img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    return img


def _select_only(obj):
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        if o is not None and o.select_get():
            o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _hide(names, hidden):
    for n in names:
        col = bpy.data.collections.get(n)
        if col is not None:
            col.hide_render = hidden


def _bake(obj, mat, img, kind, pass_filter, samples, margin):
    node = mat.node_tree.nodes["BAKE_TARGET"]
    node.image = img
    mat.node_tree.nodes.active = node
    _select_only(obj)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.bake.margin = margin
    sc.render.bake.target = "IMAGE_TEXTURES"
    if kind == "EMIT":
        bpy.ops.object.bake(type="EMIT", margin=margin, use_clear=True)
    else:
        bpy.ops.object.bake(type="DIFFUSE", pass_filter=pass_filter, margin=margin, use_clear=True)
    arr = np.empty(img.size[0] * img.size[1] * 4, np.float32)
    img.pixels.foreach_get(arr)
    node.image = None
    return arr.reshape(img.size[1], img.size[0], 4)


def bake_mask(sel):
    prev = _gpu()
    t = time.time()
    mat = bpy.data.materials["SHD_Concrete"]
    sel_node = mat.node_tree.nodes["BAKE_SEL"]
    sel_node.outputs[0].default_value = float(sel)
    _hide(HIDE_FOR_BAKE, True)
    try:
        arr = _bake(bpy.data.objects["SHD_Tile_Wall"], mat, _image("SHD_BakeMask", MASK_W, MASK_H), "EMIT", None, 4, 8)
    finally:
        sel_node.outputs[0].default_value = 0.0
        _hide(HIDE_FOR_BAKE, False)
        _restore_gpu(prev)
    ch = arr[:, :, 0].copy()
    np.save(_cache("mask_%d.npy" % sel), ch)
    return {"sel": sel, "secs": round(time.time() - t, 1), "min": float(ch.min()), "max": float(ch.max()), "mean": float(ch.mean())}


def bake_detail():
    prev = _gpu()
    t = time.time()
    plane = bpy.data.objects["SHD_DetailBakePlane"]
    plane.hide_render = False
    try:
        arr = _bake(plane, bpy.data.materials["SHD_ConcreteDetail"], _image("SHD_BakeDetail", DETAIL, DETAIL), "EMIT", None, 4, 0)
    finally:
        plane.hide_render = True
        _restore_gpu(prev)
    ch = arr[:, :, 0].copy()
    np.save(_cache("detail.npy"), ch)
    return {"secs": round(time.time() - t, 1), "min": float(ch.min()), "max": float(ch.max())}


def _glass_objects():
    return [o for o in bpy.data.objects if o.name.startswith("SHD_Tile_LampGlass")]


def bake_light(component):
    """Lamp irradiance on the centre wall from the 20 lamps of the 5-tile stack (white light)."""
    prev = _gpu()
    t = time.time()
    lights = list(bpy.data.collections["SHD_Lights"].objects)
    old = [(o.data.color[:], o.data.energy) for o in lights]
    for o in lights:
        o.data.color = (1.0, 1.0, 1.0)
        o.data.energy = LAMP_POWER
        o.data.shadow_soft_size = 0.06
    glass = _glass_objects()
    for o in glass:
        o.visible_shadow = False
        o.visible_diffuse = False
        o.visible_glossy = False
    _hide(HIDE_FOR_BAKE, True)
    mat = bpy.data.materials["SHD_Concrete"]
    try:
        if component == "DIRECT":
            img = _image("SHD_BakeLight", LIGHT_W, LIGHT_H)
            arr = _bake(bpy.data.objects["SHD_Tile_Wall"], mat, img, "DIFFUSE", {"DIRECT"}, 384, 16)
        else:
            img = _image("SHD_BakeLightIndirect", INDIRECT_W, INDIRECT_H)
            arr = _bake(bpy.data.objects["SHD_Tile_Wall"], mat, img, "DIFFUSE", {"INDIRECT"}, 1024, 16)
    finally:
        for o, (c, e) in zip(lights, old):
            o.data.color = c
            o.data.energy = e
        for o in glass:
            o.visible_shadow = True
            o.visible_diffuse = True
            o.visible_glossy = True
        _hide(HIDE_FOR_BAKE, False)
        _restore_gpu(prev)
    lum = arr[:, :, :3].mean(axis=2)
    np.save(_cache("light_%s.npy" % component.lower()), lum)
    return {"component": component, "secs": round(time.time() - t, 1), "max": float(lum.max()), "mean": float(lum.mean())}


def calibrate():
    """Baked DIFFUSE DIRECT value of one LAMP_POWER point light at 2 m, normal incidence.

    Godot's analytic lamp term is C * cos(theta) / d^2 in the same units as the bake.
    """
    prev = _gpu()
    sc = bpy.context.scene
    col = C.collection("SHD_Calib")
    C.clear_collection(col)
    mesh = bpy.data.meshes.new("SHD_CalibPlane")
    mesh.from_pydata([(-0.5, -0.5, 0), (0.5, -0.5, 0), (0.5, 0.5, 0), (-0.5, 0.5, 0)], [], [(0, 1, 2, 3)])
    mesh.uv_layers.new(name="UVMap")
    for i, loop in enumerate(mesh.loops):
        co = mesh.vertices[loop.vertex_index].co
        mesh.uv_layers[0].data[i].uv = (co.x + 0.5, co.y + 0.5)
    mat = bpy.data.materials.get("SHD_CalibMat") or bpy.data.materials.new("SHD_CalibMat")
    nb = C.NB(mat)
    bsdf = nb.node("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1.0)
    out = nb.node("ShaderNodeOutputMaterial")
    nb.nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    img_node = nb.node("ShaderNodeTexImage")
    img_node.name = "BAKE_TARGET"
    mesh.materials.append(mat)
    plane = bpy.data.objects.new("SHD_CalibPlane", mesh)
    plane.location = (400.0, 0.0, 0.0)
    col.objects.link(plane)
    ldata = bpy.data.lights.new("SHD_CalibLight", "POINT")
    ldata.energy = LAMP_POWER
    ldata.color = (1.0, 1.0, 1.0)
    ldata.shadow_soft_size = 0.06
    light = bpy.data.objects.new("SHD_CalibLight", ldata)
    light.location = (400.0, 0.0, 2.0)
    col.objects.link(light)
    _hide(HIDE_FOR_BAKE, True)
    try:
        arr = _bake(plane, mat, _image("SHD_BakeCalib", 64, 64), "DIFFUSE", {"DIRECT"}, 256, 0)
    finally:
        _hide(HIDE_FOR_BAKE, False)
        _restore_gpu(prev)
        C.clear_collection(col)
        bpy.data.collections.remove(col)
        bpy.data.materials.remove(mat)
    centre = float(arr[28:36, 28:36, :3].mean())
    value = {"V_at_2m": centre, "C": centre * 4.0, "lamp_power_w": LAMP_POWER}
    with open(_cache("calib.json"), "w") as fh:
        json.dump(value, fh)
    return value


# ------------------------------------------------------------------ packing
def _gauss_wrap(a, sigma_x, sigma_y):
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (math.pi ** 2) * ((fx * sigma_x) ** 2 + (fy * sigma_y) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def _normal(h, px_u, px_v, strength=1.0):
    dhdx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2.0 * px_u)
    dhdy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / (2.0 * px_v)
    n = np.stack([-dhdx * strength, -dhdy * strength, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n


def _save_png(name, rgba, path):
    h, w, _ = rgba.shape
    img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.clip(rgba, 0.0, 1.0).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def _upsample(a, w, h):
    """Bilinear, wrap-around resize (the textures tile both ways)."""
    sh, sw = a.shape
    ys = (np.arange(h) + 0.5) * sh / h - 0.5
    xs = (np.arange(w) + 0.5) * sw / w - 0.5
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    y0m, y1m = y0 % sh, (y0 + 1) % sh
    x0m, x1m = x0 % sw, (x0 + 1) % sw
    a00 = a[y0m][:, x0m]
    a01 = a[y0m][:, x1m]
    a10 = a[y1m][:, x0m]
    a11 = a[y1m][:, x1m]
    return (a00 * (1 - fx) * (1 - fy) + a01 * fx * (1 - fy) + a10 * (1 - fx) * fy + a11 * fx * fy).astype(np.float32)


def pack():
    t = time.time()
    os.makedirs(C.TEXTURES, exist_ok=True)
    report = {}
    # --- masks + normal
    h = (np.load(_cache("mask_1.npy")) - 0.5) / 10.0
    tone, wet, effl, rust = (np.load(_cache("mask_%d.npy" % i)) for i in (2, 3, 4, 5))
    px_u = C.TAU * C.R / MASK_W
    px_v = WALL_V_LENGTH / MASK_H
    n = _normal(h, px_u, px_v)
    cav = h - _gauss_wrap(h, 6.0, 6.0)
    ao = np.clip(1.0 + cav * 30.0, 0.25, 1.0)
    _save_png("SHD_PackNormal", np.dstack([n * 0.5 + 0.5, ao]), C.TEXTURES + "/shaft_wall_normal.png")
    _save_png("SHD_PackMasks", np.dstack([tone, wet, effl, rust]), C.TEXTURES + "/shaft_wall_masks.png")
    report["tone_mean"] = float(tone.mean())
    report["wet_mean"] = float(wet.mean())
    report["effl_mean"] = float(effl.mean())
    report["rust_mean"] = float(rust.mean())
    # --- light
    direct = np.load(_cache("light_direct.npy"))
    indirect = np.load(_cache("light_indirect.npy"))
    indirect = _gauss_wrap(indirect, 2.0, 2.0)
    indirect = _upsample(indirect, LIGHT_W, LIGHT_H)
    direct = _gauss_wrap(direct, 0.6, 0.6)
    light = np.maximum(direct + indirect, 0.0)
    lmax = float(np.percentile(light, 99.97))
    enc = np.clip(light / lmax, 0.0, 1.0) ** (1.0 / 2.2)
    _save_png("SHD_PackLight", np.dstack([enc, enc, enc, np.ones_like(enc)]), C.TEXTURES + "/shaft_wall_light.png")
    # --- detail
    d = (np.load(_cache("detail.npy")) - 0.5) / 100.0
    dn = _normal(d, 1.0 / DETAIL, 1.0 / DETAIL)
    _save_png("SHD_PackDetail", np.dstack([dn * 0.5 + 0.5, np.ones_like(d)]), C.TEXTURES + "/shaft_concrete_detail_normal.png")
    with open(_cache("calib.json")) as fh:
        calib = json.load(fh)
    meta = {
        "generator": "assets/environment/shaft_descent/source/bake_shaft.py",
        "wall_texture_size": [MASK_W, MASK_H],
        "light_texture_size": [LIGHT_W, LIGHT_H],
        "wall_v_length_m": WALL_V_LENGTH,
        "light_encoding": "value = (irradiance / light_max) ^ (1 / 2.2)",
        "light_max": lmax,
        "lamp_C": calib["C"],
        "light_max_over_C": lmax / calib["C"],
        "indirect_share": float(indirect.mean() / max(1e-6, light.mean())),
        "lamp_power_w": LAMP_POWER,
        "stats": report,
    }
    with open(C.TEXTURES + "/shaft_bake.json", "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)
    meta["secs"] = round(time.time() - t, 1)
    return meta

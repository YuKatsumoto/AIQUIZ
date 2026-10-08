"""小道具の実写の材質（lsb_pbr の手続き的な LSP_ 材質）を画像に焼き、glTF で運べる材質（LSX_<名前>）に差し替える。

1 つのオブジェクトにつき:
  finalize(): 修正子（面取りなど）を確定し、30° より鋭い辺をシャープにして滑らかに表示（法線は glTF に入る）
  unwrap():   UV（obj["lsb_uv"] == "keep" なら作ってあるものを使う。それ以外はスマート UV 投影と詰め込み）
  bake():     Cycles（GPU）で 基本色（DIFFUSE の COLOR）・粗さ・金属度（LSB_METAL を放射で）・法線（接空間）・AO を焼き、
              基本色に AO の陰りを少し掛け、ORM（R = AO、G = 粗さ、B = 金属度）と法線の画像を source/baked/ に書く
  apply():    画像を使う材質 LSX_<名前> を 1 つ作って全面に割り当てる（元の LSP_ 材質の名前は obj["lsb_src"] に残す）
画像の大きさは obj["lsb_res"]（[幅, 高さ]）か、表面積から（1 m² あたり BAKE_PPM² 画素、256〜2048 の 2 の累乗）。
AO は小道具だけで焼く（動く人物は隠す）。
"""
from __future__ import annotations

import math
import time
from pathlib import Path

import bpy
import numpy as np

HERE = Path(__file__).resolve().parent
BAKED = HERE.parent / "baked"
BAKE_PPM = 360.0
MARGIN = 16
AO_DISTANCE = 0.12
AO_IN_ALBEDO = 0.35
SAMPLES = {"color": 16, "rough": 16, "metal": 4, "normal": 16, "ao": 64}


# ------------------------------------------------------------------ context helpers

def _gpu(scene):
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
        scene.cycles.device = "GPU"
    except Exception:
        scene.cycles.device = "CPU"


def _view3d_override():
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                for region in area.regions:
                    if region.type == "WINDOW":
                        return {"window": win, "area": area, "region": region, "screen": win.screen}
    return None


def _run(fn, **kw):
    ov = _view3d_override()
    if ov is not None:
        with bpy.context.temp_override(**ov):
            return fn(**kw)
    return fn(**kw)


def _select_only(obj):
    vl = bpy.context.view_layer
    for o in vl.objects:
        if o.select_get():
            o.select_set(False)
    obj.hide_set(False)
    obj.select_set(True)
    vl.objects.active = obj


# ------------------------------------------------------------------ mesh

def finalize(obj, sharp_angle=30.0):
    """修正子を確定してメッシュを作り直す（ビルダーは毎回作り直すので壊してよい）。"""
    if obj.modifiers:
        dg = bpy.context.evaluated_depsgraph_get()
        ev = obj.evaluated_get(dg)
        new = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
        old = obj.data
        obj.modifiers.clear()
        obj.data = new
        new.name = old.name
        if old.users == 0:
            bpy.data.meshes.remove(old)
    me = obj.data
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(sharp_angle))
    except AttributeError:
        pass
    return len(me.polygons)


SEGMENT = 0.6        # 長い部品はこの間隔で切って UV の島を短くする（細長い島は詰められない）
LONG_OBJECT = 1.0    # この大きさを超える部品だけ切る
SEAM_ANGLE = 35.0    # これより鋭い辺は UV の切れ目


def _segment_long(obj):
    """長い部品を、X・Y・Z の各方向に SEGMENT ごとの平面で切り、切り口と鋭い辺を UV の切れ目にする。"""
    import bmesh
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    cuts = 0
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    for axis in range(3):
        span = hi[axis] - lo[axis]
        if span <= SEGMENT * 1.2:
            continue
        count = int(span / SEGMENT)
        step = span / (count + 1)
        normal = [0.0, 0.0, 0.0]
        normal[axis] = 1.0
        for k in range(1, count + 1):
            co = [0.0, 0.0, 0.0]
            co[axis] = lo[axis] + step * k
            geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
            res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=normal, dist=1e-5,
                                         clear_inner=False, clear_outer=False)
            for e in res["geom_cut"]:
                if isinstance(e, bmesh.types.BMEdge):
                    e.seam = True
                    cuts += 1
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(SEAM_ANGLE):
            e.seam = True
    bm.to_mesh(me)
    bm.free()
    me.update()
    return cuts


def unwrap(obj, angle=60.0, margin=0.004):
    me = obj.data
    if obj.get("lsb_uv") == "keep" and me.uv_layers:
        return "keep"
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    dims = obj.dimensions
    long_part = max(dims) > LONG_OBJECT
    if long_part:
        _segment_long(obj)
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        _run(bpy.ops.object.mode_set, mode="OBJECT")
    _select_only(obj)
    _run(bpy.ops.object.mode_set, mode="EDIT")
    _run(bpy.ops.mesh.select_all, action="SELECT")
    if long_part:
        _run(bpy.ops.uv.unwrap, method="CONFORMAL", fill_holes=True, correct_aspect=True, margin=margin)
    else:
        _run(bpy.ops.uv.smart_project, angle_limit=math.radians(angle), island_margin=margin, area_weight=0.0,
             correct_aspect=True, scale_to_bounds=False)
    _run(bpy.ops.uv.select_all, action="SELECT")
    _run(bpy.ops.uv.average_islands_scale)
    _run(bpy.ops.uv.pack_islands, rotate=True, scale=True, margin_method="FRACTION", margin=margin,
         shape_method="CONCAVE")
    _run(bpy.ops.object.mode_set, mode="OBJECT")
    return "segmented" if long_part else "smart"


def uv_fill(obj) -> float:
    """UV の島が画像の何割を覆っているか（詰め方の目安）。"""
    uv = obj.data.uv_layers.active.data
    total = 0.0
    for p in obj.data.polygons:
        pts = [uv[i].uv for i in p.loop_indices]
        a = 0.0
        for i in range(len(pts)):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % len(pts)]
            a += x0 * y1 - x1 * y0
        total += abs(a) * 0.5
    return total


def surface_area(obj) -> float:
    return sum(p.area for p in obj.data.polygons)


def resolution(obj):
    if "lsb_res" in obj:
        w, h = obj["lsb_res"]
        return int(w), int(h)
    side = math.sqrt(max(surface_area(obj), 1e-6)) * BAKE_PPM
    size = 256
    while size < side and size < 2048:
        size *= 2
    return size, size


# ------------------------------------------------------------------ bake

def _image(name, w, h, non_color=True):
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, w, h, alpha=False, float_buffer=True)
    img.colorspace_settings.name = "Non-Color" if non_color else "Linear Rec.709"
    return img


def _materials(obj):
    return [m for m in obj.data.materials if m is not None]


def _targets(obj, img):
    for m in _materials(obj):
        nt = m.node_tree
        node = nt.nodes.get("BAKE_TARGET")
        if node is None:
            node = nt.nodes.new("ShaderNodeTexImage")
            node.name = "BAKE_TARGET"
            node.location = (900, 400)
        node.image = img
        nt.nodes.active = node


def _metal_mode(obj, on: bool):
    for m in _materials(obj):
        nt = m.node_tree
        metal = nt.nodes.get("LSB_METAL")
        emit = nt.nodes.get("BAKE_EMIT")
        switch = nt.nodes.get("BAKE_SWITCH")
        if metal is None or emit is None or switch is None:
            continue
        for link in list(emit.inputs["Color"].links):
            nt.links.remove(link)
        if on:
            nt.links.new(metal.outputs[0], emit.inputs["Color"])
            emit.inputs["Strength"].default_value = 1.0
            switch.outputs[0].default_value = 1.0
        else:
            switch.outputs[0].default_value = 0.0


def _read(img):
    w, h = img.size
    arr = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(arr)
    return arr.reshape(h, w, 4)


def _to_srgb(lin):
    lin = np.clip(lin, 0.0, 1.0)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1.0 / 2.4) - 0.055)


def _save(arr_rgb, path: Path, name: str, srgb: bool):
    h, w = arr_rgb.shape[:2]
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, w, h, alpha=False)
    rgba = np.concatenate([arr_rgb, np.ones((h, w, 1), np.float32)], axis=2)
    img.pixels.foreach_set(np.ascontiguousarray(rgba, dtype=np.float32).ravel())
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    out = bpy.data.images.load(str(path), check_existing=False)
    out.name = name
    out.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    return out


def bake(obj, hide_names=()) -> dict:
    t0 = time.time()
    scene = bpy.context.scene
    prev_engine = scene.render.engine
    scene.render.engine = "CYCLES"
    _gpu(scene)
    scene.cycles.use_denoising = False
    scene.render.bake.margin = MARGIN
    scene.render.bake.target = "IMAGE_TEXTURES"
    scene.render.bake.use_selected_to_active = False
    hidden = []
    for o in scene.objects:
        if o.name in hide_names or (o.type in ("MESH", "ARMATURE") and o.name.startswith(("HERO_", "RIG_"))):
            if not o.hide_render:
                o.hide_render = True
                hidden.append(o)
    w, h = resolution(obj)
    obj.data.uv_layers.active = obj.data.uv_layers["UVMap"]
    _select_only(obj)
    imgs = {}
    try:
        for key, kind, kwargs in (
                ("color", "DIFFUSE", {"pass_filter": {"COLOR"}}),
                ("rough", "ROUGHNESS", {}),
                ("normal", "NORMAL", {"normal_space": "TANGENT"}),
                ("ao", "AO", {}),
                ("metal", "EMIT", {})):
            img = _image(f"LSB_tmp_{key}", w, h)
            _targets(obj, img)
            scene.cycles.samples = SAMPLES[key]
            if key == "ao":
                scene.world.light_settings.distance = AO_DISTANCE
            if key == "metal":
                _metal_mode(obj, True)
            try:
                _run(bpy.ops.object.bake, type=kind, margin=MARGIN, use_clear=True, **kwargs)
            finally:
                if key == "metal":
                    _metal_mode(obj, False)
            imgs[key] = _read(img)
            bpy.data.images.remove(img)
    finally:
        for m in _materials(obj):
            node = m.node_tree.nodes.get("BAKE_TARGET")
            if node is not None:
                m.node_tree.nodes.remove(node)
        for o in hidden:
            o.hide_render = False
        scene.render.engine = prev_engine
    color = imgs["color"][:, :, :3]
    ao = np.clip(imgs["ao"][:, :, 0], 0.0, 1.0)
    rough = np.clip(imgs["rough"][:, :, 0], 0.0, 1.0)
    metal = np.clip(imgs["metal"][:, :, 0], 0.0, 1.0)
    albedo = color * (1.0 - AO_IN_ALBEDO * (1.0 - ao))[..., None]
    orm = np.stack([ao, rough, metal], axis=2)
    normal = np.clip(imgs["normal"][:, :, :3], 0.0, 1.0)
    BAKED.mkdir(parents=True, exist_ok=True)
    stem = obj.name
    images = {
        "albedo": _save(_to_srgb(albedo).astype(np.float32), BAKED / f"{stem}_albedo.png", f"LSX_{stem}_albedo", True),
        "orm": _save(orm.astype(np.float32), BAKED / f"{stem}_orm.png", f"LSX_{stem}_orm", False),
        "normal": _save(normal.astype(np.float32), BAKED / f"{stem}_normal.png", f"LSX_{stem}_normal", False),
    }
    obj["lsb_baked"] = [w, h]
    return {"object": obj.name, "size": [w, h], "secs": round(time.time() - t0, 1),
            "albedo_mean": round(float(color.mean()), 3), "rough_mean": round(float(rough.mean()), 3),
            "metal_max": round(float(metal.max()), 3), "ao_mean": round(float(ao.mean()), 3), "images": images}


# ------------------------------------------------------------------ export material

def _gltf_output_group():
    """glTF の遮蔽（occlusion）を書き出すための「glTF Material Output」ノードグループ。"""
    name = "glTF Material Output"
    group = bpy.data.node_groups.get(name)
    if group is not None:
        return group
    group = bpy.data.node_groups.new(name, "ShaderNodeTree")
    group.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    group.interface.new_socket("Thickness", in_out="INPUT", socket_type="NodeSocketFloat")
    group.nodes.new("NodeGroupInput")
    return group


def apply(obj, images: dict):
    name = "LSX_" + obj.name
    old = bpy.data.materials.get(name)
    if old is not None:
        bpy.data.materials.remove(old)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    alb = nt.nodes.new("ShaderNodeTexImage")
    alb.image = images["albedo"]
    alb.location = (-700, 300)
    orm = nt.nodes.new("ShaderNodeTexImage")
    orm.image = images["orm"]
    orm.location = (-700, 0)
    nrm = nt.nodes.new("ShaderNodeTexImage")
    nrm.image = images["normal"]
    nrm.location = (-700, -300)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-400, 0)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-400, -300)
    nt.links.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(orm.outputs["Color"], sep.inputs[0])
    nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
    nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    group = nt.nodes.new("ShaderNodeGroup")
    group.node_tree = _gltf_output_group()
    group.location = (-100, -500)
    nt.links.new(sep.outputs[0], group.inputs["Occlusion"])
    src = [mm.name for mm in obj.data.materials if mm is not None]
    obj["lsb_src"] = src
    # 元の面ごとの材質の番号を面の属性に残す（焼き直しで戻せるように）
    me = obj.data
    attr = me.attributes.get("lsb_mat") or me.attributes.new("lsb_mat", "INT", "FACE")
    attr.data.foreach_set("value", [p.material_index for p in me.polygons])
    obj.data.materials.clear()
    obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = 0
    return m


def process(obj, hide_names=()) -> dict:
    """1 つのオブジェクトを最後まで: 確定 → UV → 焼き → 差し替え。"""
    if obj.get("lsb_src"):
        return {"object": obj.name, "skipped": "already baked"}
    t0 = time.time()
    tris = finalize(obj)
    t1 = time.time()
    uv = unwrap(obj)
    fill = uv_fill(obj)
    t2 = time.time()
    info = bake(obj, hide_names)
    t3 = time.time()
    apply(obj, info.pop("images"))
    info.update({"faces": tris, "uv": uv, "uv_fill": round(fill, 3),
                 "t_finalize": round(t1 - t0, 1), "t_unwrap": round(t2 - t1, 1), "t_bake": round(t3 - t2, 1),
                 "t_apply": round(time.time() - t3, 1)})
    return info

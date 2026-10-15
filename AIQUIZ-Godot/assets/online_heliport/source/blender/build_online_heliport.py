"""AIQUIZ ONLINE HELIPORT（オンライン対戦メニューの 3D 背景）のビルダー。v2：パッド 1 つと乗り込めるヘリ。

ユーザーが開いているライブの Blender で動かす（Higgsfield の Blender 連携 bl_execute から runpy）。
シーン `OHP_OnlineHeliport` だけを作り直す（ほかのシーンには触れない）。やること：
  1. テクスチャ（ohp_textures）と材質
  2. 部品（ohp_parts）を `OHP_EXPORT` に組み立て、頂点色へ AO・水際の汚れ・ムラを焼く（スタジアムの aqs_wear）
  3. 確認用の参照（海・乗り込めるヘリ・キャラの仮置き・メニューの街）、カメラ（演出の定数から）、太陽、吹き流しの揺れ
  4. 検算（寸法・ローターの当たり・三角形数・材質・画像）と build_report.json
  5. GLB（Godot のワールド座標、原点に置くだけ）と配置 JSON の書き出し
  6. 確認レンダー（source/previews と artifacts/online_heliport/blender）と .blend の保存
最後の行 `OHP_BUILD {...}` の all_checks_pass が合格の印。

  import runpy, sys
  for n in [m for m in sys.modules if m.startswith(("ohp_", "aqs_"))]: del sys.modules[n]
  sys.argv = ["blender", "--"]      # レンダーを省くなら ["blender", "--", "--no-render"]、保存しないなら "--no-save"
  runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/online_heliport/source/blender/build_online_heliport.py", run_name="__main__")
"""
from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import ohp_common as K  # noqa: E402
import ohp_parts as P  # noqa: E402
import ohp_textures as T  # noqa: E402
from aqs_geom import Materials, collection, create_object, flat_material, image_material, vertex_colour_material  # noqa: E402
import aqs_wear  # noqa: E402

T0 = time.time()
LOG: list[str] = []
KEEP_REF = ("REF_Heli", "REF_City")


def log(msg):
    LOG.append(msg)
    print("[OHP]", msg)


# --- シーン ----------------------------------------------------------------------------
def _keep(ob) -> bool:
    top = ob
    while top.parent is not None:
        top = top.parent
    return top.name in KEEP_REF


def reset_scene():
    sc = bpy.data.scenes.get(K.SCENE_NAME) or bpy.data.scenes.new(K.SCENE_NAME)
    bpy.context.window.scene = sc
    for ob in list(sc.objects):
        if _keep(ob):
            continue
        if all(s == sc for s in ob.users_scene):
            data = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if data is not None and getattr(data, "users", 1) == 0:
                for coll in (bpy.data.meshes, bpy.data.cameras, bpy.data.lights, bpy.data.curves):
                    if data.name in coll and coll[data.name] == data:
                        coll.remove(data)
                        break
    for coll in list(sc.collection.children_recursive):
        if coll.name.startswith(("OHP_", "REF_", "CAMERAS", "LIGHTING")) and not coll.objects and not coll.children:
            bpy.data.collections.remove(coll)
    for _ in range(2):
        for mat in list(bpy.data.materials):
            if mat.users == 0 and (mat.name.startswith(("OHP_", "REF_")) or mat.name in ("AQS_Painted", "AQS_NightGlow")):
                bpy.data.materials.remove(mat)
        for me in list(bpy.data.meshes):
            if me.users == 0:
                bpy.data.meshes.remove(me)
        for img in list(bpy.data.images):
            if img.users == 0 and img.name.startswith("ohp_"):
                bpy.data.images.remove(img)
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.render.fps = 24
    sc.frame_start, sc.frame_end = 1, 96
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    return sc


# --- 材質 ------------------------------------------------------------------------------
def materials(tex) -> Materials:
    for path in tex.values():
        img = bpy.data.images.get(Path(path).name)
        if img is not None:
            img.reload()          # 描き直した画像を読み直す
    mats = Materials()
    mats.add("deck", image_material("OHP_PadDeck", Path(tex["pad"]), roughness=0.78))
    net = image_material("OHP_Net", Path(tex["net"]), roughness=0.9)
    nt = net.node_tree
    img_node = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    nt.links.new(img_node.outputs["Alpha"], bsdf.inputs["Alpha"])
    net.use_backface_culling = False
    for attr, value in (("blend_method", "CLIP"), ("surface_render_method", "DITHERED")):
        try:
            setattr(net, attr, value)
        except Exception:
            pass
    mats.add("net", net)
    mats.add("lamp", vertex_colour_material("OHP_PadLamp", 0.3, emission=1.6))
    flagm = vertex_colour_material("OHP_Flag", 0.8)
    flagm.use_backface_culling = False
    mats.add("flag", flagm)
    return mats


# --- 組み立て ----------------------------------------------------------------------------
def build_parts(mats, export):
    objs = {}
    pad = P.pad(K.PAD, None)
    objs["OHP_Pad"] = create_object("OHP_Pad", pad["body"], mats, export)
    objs["OHP_Pad_Lamps"] = create_object("OHP_Pad_Lamps", pad["lamps"], mats, export)
    props, pivots = P.props()
    objs["OHP_Props"] = create_object("OHP_Props", props, mats, export)
    objs["OHP_Windsock"] = create_object("OHP_Windsock", P.windsock(), mats, export, location=pivots["windsock"])
    objs["OHP_FlagA"] = create_object("OHP_FlagA", P.flag(K.C["orange"], K.C["white"]), mats, export, location=pivots["flag_0"])
    objs["OHP_FlagB"] = create_object("OHP_FlagB", P.flag(K.C["blue"], K.C["white"]), mats, export, location=pivots["flag_1"])
    # 旗と吹き流しは同じ風下へ流す（Blender の Z 回り。吹き流しはパッドの外を向く）
    wind = math.radians(K.WIND_DEG)
    objs["OHP_FlagA"].rotation_euler = (0.0, 0.0, wind + math.radians(-4))
    objs["OHP_FlagB"].rotation_euler = (0.0, 0.0, wind + math.radians(6))
    objs["OHP_Windsock"].rotation_euler = (0.0, 0.0, wind)
    info = {"lamp_count": pad["lamp_count"], "lamps": pad["lamp_points"], **pivots}
    return objs, info


def bake(objs):
    """頂点色へ AO・水際の汚れ・ムラ（塗装の面だけ。原点が単位行列のものだけ）。"""
    groups = {"OHP_Pad": ("OHP_Props",), "OHP_Props": ("OHP_Pad",)}
    stats = []
    for name, extra in groups.items():
        t = time.time()
        st = aqs_wear.bake_wear(objs[name], K.SEA_Y, extra=[objs[e] for e in extra],
                                params={"noise_period": 5.0, "dirt_scale_m": 1.4})
        st["seconds"] = round(time.time() - t, 1)
        stats.append(st)
        log(f"wear {name}: {st.get('mean_multiplier_visible_up_side')} ({st['seconds']} s)")
    return stats


# --- 確認用の参照 --------------------------------------------------------------------------
def _import_glb(path: Path, root_name: str, coll):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new(root_name, None)
    coll.objects.link(root)
    for o in new:
        if o.parent is None or o.parent not in new:
            o.parent = root
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
    return root


def references(sc, mats):
    ref = collection("REF_Review")
    # 海（確認用の材質）
    bpy.ops.mesh.primitive_plane_add(size=4000.0, location=(0, -150, K.SEA_Y))
    sea = bpy.context.active_object
    sea.name = "REF_Sea"
    for c in list(sea.users_collection):
        c.objects.unlink(sea)
    ref.objects.link(sea)
    mat = bpy.data.materials.get("REF_Sea") or bpy.data.materials.new("REF_Sea")
    if mat.node_tree is None:
        mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (0.012, 0.09, 0.14, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.12
    if not any(n.type == "BUMP" for n in nt.nodes):
        tc = nt.nodes.new("ShaderNodeTexCoord")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 0.35
        noise.inputs["Detail"].default_value = 6.0
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.18
        nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
        nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    sea.data.materials.append(mat)
    # 乗り込めるヘリ（読み直さずに使い回す）。原点＝ローター軸、デッキの上 skid_drop
    heli = bpy.data.objects.get("REF_Heli")
    if heli is None:
        heli = _import_glb(K.HELI_GLB, "REF_Heli", ref)
    for o in [heli, *heli.children_recursive]:
        if ref.name not in [c.name for c in o.users_collection]:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            ref.objects.link(o)
        if o.name.startswith("MK_") or o.type == "EMPTY" and o is not heli:
            o.hide_render = True
    heli.location = K.g2b(K.PAD[0], K.DECK_Y + K.HELI_SKID_DROP, K.PAD[1])
    heli.rotation_mode = "XYZ"
    heli.rotation_euler = (0.0, 0.0, math.radians(K.HELI_YAW_DEG))
    # キャラの仮置き（自分＝オレンジ、待つ位置。カメラの方を向く）
    me_obj = create_object("REF_PlayerMe", P.player_proxy(K.C["orange"]), mats, ref,
                           location=tuple(K.g2b(K.IDLE_SPOT[0], K.DECK_Y, K.IDLE_SPOT[1])))
    cam_pos = K.CAMERAS["CAM_Idle"][0]
    d = Vector((cam_pos[0] - K.IDLE_SPOT[0], -(cam_pos[2] - K.IDLE_SPOT[1])))
    me_obj.rotation_euler.z = math.atan2(d.x, -d.y)
    # メニューの街（読み直さずに使い回す）
    city = bpy.data.objects.get("REF_City")
    if city is None and K.CITY_GLB.exists():
        city = _import_glb(K.CITY_GLB, "REF_City", ref)
    if city is not None:
        place = K.city_placement()
        city.location = K.g2b(*place["position"])
        city.rotation_mode = "XYZ"
        city.rotation_euler = (city.rotation_euler.x if abs(city.rotation_euler.x) > 1e-3 else 0.0, 0.0, place["yaw"])
    for o in [o for o in ref.all_objects]:
        o.hide_select = o.name.startswith("REF_City")
    return {"heli": heli, "city": city}


def cameras_and_light(sc):
    cams = collection("CAMERAS")
    out = {}
    for name, (pos, target, fov) in K.CAMERAS.items():
        data = bpy.data.cameras.new(name)
        data.sensor_fit = "VERTICAL"
        data.lens = data.sensor_height / 2 / math.tan(math.radians(fov) / 2)
        data.clip_start = 0.1
        data.clip_end = 6000.0
        ob = bpy.data.objects.new(name, data)
        cams.objects.link(ob)
        p = K.g2b(*pos)
        t = K.g2b(*target)
        ob.location = p
        ob.rotation_euler = (t - p).to_track_quat("-Z", "Y").to_euler()
        out[name] = ob
    sc.camera = out["CAM_Idle"]
    # 太陽（ゲームの昼：WeatherCycle の向き。太陽はワールドの (0.285, 0.866, -0.411) の方）
    lights = collection("LIGHTING")
    sun_data = bpy.data.lights.new("LGT_Sun", "SUN")
    sun_data.energy = 3.6
    sun_data.angle = math.radians(1.5)
    sun_data.color = (1.0, 0.97, 0.92)
    sun = bpy.data.objects.new("LGT_Sun", sun_data)
    lights.objects.link(sun)
    to_sun = K.g2b(0.285386, 0.866025, -0.410555).normalized()
    sun.rotation_euler = to_sun.to_track_quat("Z", "Y").to_euler()
    world = bpy.data.worlds.get("OHP_World") or bpy.data.worlds.new("OHP_World")
    world.use_nodes = True
    wn = world.node_tree
    wn.nodes.clear()
    tc = wn.nodes.new("ShaderNodeTexCoord")
    sep = wn.nodes.new("ShaderNodeSeparateXYZ")
    ramp = wn.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.62, 0.74, 0.86, 1.0)
    ramp.color_ramp.elements[1].position = 0.45
    ramp.color_ramp.elements[1].color = (0.20, 0.42, 0.75, 1.0)
    bg = wn.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 1.0
    out_node = wn.nodes.new("ShaderNodeOutputWorld")
    wn.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    wn.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    wn.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    wn.links.new(bg.outputs["Background"], out_node.inputs["Surface"])
    sc.world = world
    return out


def motion(objs):
    """確認用の動き：吹き流しの揺れ（±6°）。"""
    sock = objs["OHP_Windsock"]
    base = sock.rotation_euler.z
    for f, a in ((1, 0.0), (25, 6.0), (49, 0.0), (73, -6.0), (97, 0.0)):
        sock.rotation_euler.z = base + math.radians(a)
        sock.keyframe_insert("rotation_euler", index=2, frame=f)
    sock.rotation_euler.z = base


# --- 検算 --------------------------------------------------------------------------------
def checks(objs, info, tex):
    res = []

    def add(name, ok, detail=""):
        res.append({"check": name, "pass": bool(ok), "detail": detail})

    export = bpy.data.collections["OHP_EXPORT"]
    names = [o.name for o in export.objects]
    add("export_names_unique", len(names) == len(set(names)) and all("." not in n for n in names), ", ".join(sorted(names)))
    tris = {}
    for o in export.objects:
        o.data.calc_loop_triangles()
        tris[o.name] = len(o.data.loop_triangles)
    total = sum(tris.values())
    add("triangles_total_le_30k", total <= 30000, f"{total} {tris}")
    # 床の上面がデッキの高さ
    me = objs["OHP_Pad"].data
    idx = [i for i, m in enumerate(me.materials) if m and m.name == "OHP_PadDeck"]
    zs = [me.vertices[v].co.z for p in me.polygons if p.material_index in idx for v in p.vertices]
    top = (round(min(zs), 4), round(max(zs), 4)) if zs else None
    add("deck_top_level", top is not None and abs(top[0] - K.DECK_Y) < 1e-4 and abs(top[1] - K.DECK_Y) < 1e-4, str(top))
    # ローターの当たり：背の高い物（柱の根元から先端までの線）がローターの円の外、尾の回転翼からも離れる
    cx, cy = K.gxz(K.PAD)
    clear = K.HELI_ROTOR_R + 0.5
    wind = Vector((math.cos(math.radians(K.WIND_DEG)), math.sin(math.radians(K.WIND_DEG))))
    tall = [("windsock", Vector(info["windsock"][:2]), 2.5)] + [(f"flag{i}", Vector(info[f"flag_{i}"][:2]), 1.8) for i in range(2)]
    tall += [(f"flood{i}", Vector(K.gxz(K.h2g_xz(*p))), 0.6) for i, p in enumerate(K.H_FLOODS)]

    def seg_dist(c, a, reach):
        b = a + wind * reach
        ab = b - a
        t = max(0.0, min(1.0, (c - a).dot(ab) / max(ab.length_squared, 1e-9)))
        return (a + ab * t - c).length

    centre = Vector((cx, cy))
    tail = Vector(K.gxz(K.h2g_xz(K.HELI_TAIL_ROTOR[0], K.HELI_TAIL_ROTOR[2])))
    worst = [(label, round(seg_dist(centre, a, reach), 2)) for label, a, reach in tall]
    tail_gap = [(label, round(seg_dist(tail, a, reach) - K.HELI_TAIL_ROTOR_R, 2)) for label, a, reach in tall]
    add("rotor_clearance", all(d >= clear for _, d in worst) and all(d >= 1.0 for _, d in tail_gap), f"need {clear}: {worst}; tail {tail_gap}")
    low = [(f"monitor{i}", K.gxz(K.h2g_xz(*p))) for i, p in enumerate(K.H_MONITORS)]
    low += [(f"cabinet{i}", K.gxz(K.h2g_xz(p[0], p[1]))) for i, p in enumerate(K.H_CABINETS)]
    low += [(f"buoy{i}", K.gxz(K.h2g_xz(*p))) for i, p in enumerate(K.H_BUOYS)]
    ap = K.PAD_FLAT / 2 - K.PAD_RIM_W
    on_deck = [(label, round(math.hypot(p[0] - cx, p[1] - cy), 2)) for label, p in low]
    add("props_on_deck_outside_rotor", all(clear <= r <= ap - 0.3 for _, r in on_deck), f"{on_deck} (deck {ap - 0.3})")
    # 待つ位置・カメラがパッドの上、または外（デッキの中）
    sx, sy = K.gxz(K.IDLE_SPOT)
    add("idle_spot_on_deck", math.hypot(sx - cx, sy - cy) <= ap - 0.5, str(K.IDLE_SPOT))
    add("windsock_pivot_on_pole_top", (objs["OHP_Windsock"].location - Vector(info["windsock"])).length < 1e-4,
        str(tuple(round(v, 3) for v in objs["OHP_Windsock"].location)))
    # 材質と画像
    allowed = {"AQS_Painted", "AQS_NightGlow", "OHP_PadDeck", "OHP_Net", "OHP_PadLamp", "OHP_Flag"}
    used = {m.name for o in export.objects for m in o.data.materials if m}
    add("materials_allowed", used <= allowed and all("." not in m for m in used), ", ".join(sorted(used)))
    imgs = [n.image for m in bpy.data.materials if m.name in used and m.node_tree for n in m.node_tree.nodes
            if n.type == "TEX_IMAGE" and n.image]
    add("images_resolved", all(Path(bpy.path.abspath(i.filepath)).exists() and i.size[0] > 0 for i in imgs),
        ", ".join(f"{i.name} {tuple(i.size)}" for i in imgs))
    add("lamps_16", info["lamp_count"] == 16, str(info["lamp_count"]))
    return res, total, tris


# --- 書き出し ------------------------------------------------------------------------------
def export_glb(sc):
    sc.frame_set(1)
    export = bpy.data.collections["OHP_EXPORT"]
    for o in sc.objects:
        o.select_set(False)
    for o in export.objects:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = export.objects[0]
    bpy.ops.export_scene.gltf(filepath=str(K.GLB), export_format="GLB", use_selection=True, use_active_scene=True,
                              export_apply=True, export_yup=True, export_animations=False, export_cameras=False,
                              export_lights=False, export_extras=False, export_vertex_color="ACTIVE",
                              export_image_format="AUTO", export_materials="EXPORT")
    for o in export.objects:
        o.select_set(False)
    return K.GLB.stat().st_size


def write_layout(objs, info, tris):
    def g(v):
        return list(K.b2g(v))

    cams = {}
    for name, (pos, target, fov) in K.CAMERAS.items():
        cams[name] = {"position": [round(v, 4) for v in pos], "target": [round(v, 4) for v in target],
                      "rotation_deg": list(K.camera_rotation_deg(pos, target)), "fov": fov}
    place = K.city_placement()
    layout = {
        "version": 2,
        "about": "AIQUIZ ONLINE HELIPORT v2（パッド 1 つ）。座標は Godot（オンラインメニューの 3D ワールド）。build_online_heliport.py が書き出す。"
                 "カメラは演出の定数（online_staging_timeline.gd、ヘリの座標）をこのパッドの上に置いたもの（確認用）",
        "deck_y": K.DECK_Y, "sea_y": K.SEA_Y,
        "pad": {"center": [K.PAD[0], K.DECK_Y, K.PAD[1]], "apothem": K.PAD_FLAT / 2, "lamp_count": info["lamp_count"]},
        "helicopter": {"position": [K.PAD[0], K.DECK_Y + K.HELI_SKID_DROP, K.PAD[1]], "yaw_deg": K.HELI_YAW_DEG,
                       "skid_drop": K.HELI_SKID_DROP, "rotor_radius": K.HELI_ROTOR_R,
                       "ground": [K.PAD[0], K.DECK_Y, K.PAD[1]]},
        "spots": {"idle": [K.IDLE_SPOT[0], K.DECK_Y, K.IDLE_SPOT[1]]},
        "pivots": {"windsock": g(objs["OHP_Windsock"].location), "windsock_yaw_deg": round(math.degrees(objs["OHP_Windsock"].rotation_euler.z), 3),
                   "flag_a": g(objs["OHP_FlagA"].location), "flag_b": g(objs["OHP_FlagB"].location)},
        "cameras": cams,
        "city": {"position": list(place["position"]), "yaw_deg": round(math.degrees(place["yaw"]), 4)},
        "objects": sorted(tris.keys()),
        "triangles": tris,
        "materials": {
            "AQS_Painted": "頂点色の塗装（AiquizStadiumMaterials.painted）", "AQS_NightGlow": "夜の灯（AiquizStadiumMaterials.glow）",
            "OHP_PadDeck": "パッドの床（画像）", "OHP_PadLamp": "縁の灯。UV2.x = 灯の番号 / lamp_count（追いかける光）",
            "OHP_Net": "網。アルファで切り抜く・両面", "OHP_Flag": "旗。UV2.x = 竿からの距離の割合（揺れの重み）・両面",
        },
    }
    K.LAYOUT_JSON.write_text(json.dumps(layout, ensure_ascii=False, indent=2), encoding="utf-8")
    return layout


def render_previews(sc, cams):
    K.PREVIEW.mkdir(parents=True, exist_ok=True)
    K.EVIDENCE.mkdir(parents=True, exist_ok=True)
    for old in K.PREVIEW.glob("cam_*.png"):
        old.unlink()
    out = []
    sc.frame_set(1)
    for name in ("CAM_Idle", "CAM_Board", "CAM_Cockpit", "CAM_PadLow", "CAM_Overview"):
        sc.camera = cams[name]
        for folder in (K.PREVIEW, K.EVIDENCE):
            sc.render.filepath = str(folder / f"{name.lower()}.png")
            bpy.ops.render.render(write_still=True)
        out.append(str(K.EVIDENCE / f"{name.lower()}.png"))
    sc.camera = cams["CAM_Idle"]
    return out


def main():
    sc = reset_scene()
    tex = T.build_all()
    log(f"textures {list(tex)}")
    mats = materials(tex)
    export = collection("OHP_EXPORT")
    objs, info = build_parts(mats, export)
    log(f"parts {len(objs)}")
    wear = bake(objs)
    references(sc, mats)
    cams = cameras_and_light(sc)
    motion(objs)
    res, total, tris = checks(objs, info, tex)
    size = export_glb(sc)
    write_layout(objs, info, tris)
    renders = render_previews(sc, cams) if K.DO_RENDER else []
    report = {"built": time.strftime("%Y-%m-%d %H:%M:%S"), "seconds": round(time.time() - T0, 1), "checks": res,
              "all_checks_pass": all(r["pass"] for r in res), "triangles": total, "glb_bytes": size, "renders": renders,
              "wear": wear, "log": LOG}
    K.REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if K.DO_SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=str(K.BLEND))
    summary = {"all_checks_pass": report["all_checks_pass"], "failed": [r for r in res if not r["pass"]], "triangles": total,
               "glb_bytes": size, "seconds": report["seconds"], "renders": renders}
    print("OHP_BUILD " + json.dumps(summary, ensure_ascii=False))
    return summary


if __name__ == "__main__":
    RESULT = main()

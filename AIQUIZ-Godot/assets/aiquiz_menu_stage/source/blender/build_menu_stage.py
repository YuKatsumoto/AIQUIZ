"""AIQUIZ HARBOR LAUNCH（メインメニュー専用ステージ）のビルダー。

ユーザーが開いているライブの Blender で動かす（Higgsfield の Blender 連携 bl_execute から runpy）。
シーン `AIQUIZ_MenuStage` だけを作り直す（ユーザーの他のシーンには触れない）。やること：
  1. 材質と部品（発進デッキ・背景の壁・LED・看板・デッキの照明塔・ヤシ・旗。走路の外装は ams_common.KEEP_PIER_FASCIA のときだけ。
     走路の脇の杭・奥の歩道・照明塔と、デッキから走路への橋は 2026-09-30 に外した）
  2. 確認用の参照（ベルト・壁・キャラの仮置き、保守船、街、海、太陽）とカメラ
  3. GLB（メニューのワールド座標、原点に置くだけ）と配置 JSON の書き出し。メニューの街の GLB の観覧車は、脚と乗り場・
     回る輪（原点＝軸）・ゴンドラ 24 台（原点＝吊り点）の別々のノード（Godot が輪を回し、ゴンドラを動かす）
  4. 検算（寸法・他の演出との干渉・三角形数・材質・観覧車が 1 周回っても当たらないか）と build_report.json
  5. 確認レンダー（source/previews、artifacts/aiquiz_menu_stage/blender。観覧車は止まった姿勢と 20° 回した姿勢）と .blend の複製保存
最後の行 `AMS_BUILD {...}` の all_checks_pass が合格の印。

  import runpy, sys
  for n in [m for m in sys.modules if m.startswith(("ams_", "aqs_geom"))]: del sys.modules[n]
  sys.argv = ["blender", "--"]      # レンダーを省くなら ["blender", "--", "--no-render"]
  runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/aiquiz_menu_stage/source/blender/build_menu_stage.py", run_name="__main__")
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import ams_common as K  # noqa: E402
import ams_parts as P  # noqa: E402
import ams_waterfront as W  # noqa: E402
from aqs_geom import (Materials, collection, create_object, flat_material, image_material,  # noqa: E402
                      vertex_colour_material)

T0 = time.time()
LOG: list[str] = []


def log(msg):
    LOG.append(msg)
    print("[AMS]", msg)


# --- シーン ------------------------------------------------------------------------
def reset_scene():
    sc = bpy.data.scenes.get(K.SCENE_NAME) or bpy.data.scenes.new(K.SCENE_NAME)
    bpy.context.window.scene = sc
    # このシーンのコレクションとオブジェクトだけを消す（参照の街と保守船は残して再利用：読み直すと画像が重複して .blend が膨らむ）
    def keep(ob):
        return ob.name == "AQS_BG_City" or ob.name.startswith("REF_VSL_")
    for coll in list(sc.collection.children_recursive):
        for ob in list(coll.objects):
            if keep(ob):
                continue
            if len(ob.users_collection) <= 1 and all(s == sc for s in ob.users_scene):
                data = ob.data
                bpy.data.objects.remove(ob, do_unlink=True)
                if data is not None and getattr(data, "users", 1) == 0:
                    if isinstance(data, bpy.types.Mesh):
                        bpy.data.meshes.remove(data)
                    elif isinstance(data, bpy.types.Camera):
                        bpy.data.cameras.remove(data)
                    elif isinstance(data, bpy.types.Light):
                        bpy.data.lights.remove(data)
    for ob in list(sc.collection.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in list(sc.collection.children_recursive):
        if coll.name.startswith(("AMS_", "REF_", "CAMERAS", "LIGHTING", "PROXY_")) and not coll.objects and not coll.children:
            bpy.data.collections.remove(coll)
    # このビルダーの材質（使われなくなったもの）を消して作り直す（ノードが重なっていかないように）
    for mat in list(bpy.data.materials):
        if (mat.name.startswith(("AMS_", "REF_", "PX_")) or mat.name == "AQS_Painted") and mat.users == 0:
            bpy.data.materials.remove(mat)
    for img in list(bpy.data.images):
        if (img.name in ("led_idle.png", "sign_aiquiz.png", "paving.png") or img.name.startswith("harbor_facade_")) and img.users == 0:
            bpy.data.images.remove(img)
    # 参照の保守船と配置検討の仮置きの残り（使われていないものだけ。ユーザーの他のデータには触れない）
    for _ in range(3):
        for me in list(bpy.data.meshes):
            if me.users == 0 and me.name.startswith(("VSL_", "PX_", "REF_", "AMS_")):
                bpy.data.meshes.remove(me)
        for mat in list(bpy.data.materials):
            if mat.users == 0 and mat.name.startswith(("Vessel", "VSL_", "PX_", "REF_")):
                bpy.data.materials.remove(mat)
        for img in list(bpy.data.images):
            if img.users == 0 and img.name.startswith(("Vessel", "VSL_")):
                bpy.data.images.remove(img)
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "Standard"
    sc.render.fps = 24
    sc.frame_start, sc.frame_end = 1, 96
    return sc


def materials() -> Materials:
    mats = Materials()   # AQS_Painted / AQS_NightGlow（ゲームの共有材質の名前）
    lamp = vertex_colour_material("AMS_Lamp", 0.35, emission=2.2)
    mats.add("lamp", lamp)
    glass = bpy.data.materials.get("AMS_Glass") or bpy.data.materials.new("AMS_Glass")
    if glass.node_tree is None:        # Blender 5 の新しい材質は最初からノードを持つ
        glass.use_nodes = True
    bsdf = next(n for n in glass.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.62, 0.84, 0.92, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.08
    bsdf.inputs["Alpha"].default_value = 0.32
    for attr, value in (("blend_method", "BLEND"), ("surface_render_method", "BLENDED")):
        try:
            setattr(glass, attr, value)
        except Exception:
            pass
    glass.use_backface_culling = True
    mats.add("glass", glass)
    mats.add("led", image_material("AMS_LedScreen", K.TEX / "led_idle.png", emission=1.4, roughness=0.3))
    mats.add("sign", image_material("AMS_Sign", K.TEX / "sign_aiquiz.png", emission=0.25, roughness=0.45))
    mats.add("paving", image_material("AMS_Paving", K.TEX / "paving.png", roughness=0.8, vertex_tint=True))
    mats.add("pennant", vertex_colour_material("AMS_Pennant", 0.8))
    mats.add("foliage", vertex_colour_material("AMS_Foliage", 0.75))
    return mats


# --- 部品 ------------------------------------------------------------------------
def build_parts(mats: Materials, coll):
    """ステージの部品。2026-09-30：走路の脇の白い丸杭（AMS_Piles）・奥の歩道とガラスの手すりと琥珀の灯（AMS_RunwayEdge）・
    照明塔（AMS_LightTowers）・発進デッキから走路への橋を外し、ディスプレイのステージ（発進デッキとその上）だけを残した。
    ベルトの箱の側面の白い外装（AMS_PierFascia）は K.KEEP_PIER_FASCIA = True で戻る。"""
    objs = {}
    info = {}
    deck, deck_info = P.launch_deck()
    info["deck"] = deck_info
    if K.KEEP_PIER_FASCIA:
        fascia = P.pier_fascia(-1)
        fascia.extend(P.pier_fascia(1))
        objs["AMS_PierFascia"] = create_object("AMS_PierFascia", fascia, mats, coll)
    objs["AMS_LaunchDeck"] = create_object("AMS_LaunchDeck", deck, mats, coll)
    wall, led, sign, back_info = P.backdrop()
    objs["AMS_Backdrop"] = create_object("AMS_Backdrop", wall, mats, coll)
    objs["AMS_LedScreen"] = create_object("AMS_LedScreen", led, mats, coll)
    objs["AMS_Sign"] = create_object("AMS_Sign", sign, mats, coll)
    dtowers, tops = P.deck_towers()
    objs["AMS_DeckTowers"] = create_object("AMS_DeckTowers", dtowers, mats, coll)
    trunks, leaves = P.palms()
    objs["AMS_Palms"] = create_object("AMS_Palms", trunks, mats, coll)
    objs["AMS_PalmLeaves"] = create_object("AMS_PalmLeaves", leaves, mats, coll)
    objs["AMS_Pennants"] = create_object("AMS_Pennants", P.pennants(tops, back_info["sign_top_local"]), mats, coll)
    info["backdrop"] = back_info
    info["tower_tops"] = [tuple(t) for t in tops]        # デッキの照明塔の頂（旗の起点）
    info["meshes"] = list(objs)
    return objs, info


# --- 参照（書き出さない） -------------------------------------------------------------
def ref_material(name, rgba):
    return flat_material(name, rgba, roughness=0.7)


def build_reference(sc):
    ref = collection("REF_MenuDemo", sc.collection)
    from aqs_geom import Mesh
    belt = ref_material("REF_Belt", (0.13, 0.135, 0.14, 1))
    frame = ref_material("REF_Frame", (0.09, 0.10, 0.11, 1))
    wall = ref_material("REF_Wall", (0.2, 0.2, 0.2, 1))
    doors = {"blue": ref_material("REF_DoorBlue", (0.02, 0.25, 0.75, 1)), "red": ref_material("REF_DoorRed", (0.55, 0.02, 0.03, 1)),
             "panel": ref_material("REF_QPanel", (0.08, 0.08, 0.09, 1))}
    chars = {"P1": ref_material("REF_P1", (0.9, 0.3, 0.05, 1)), "P2": ref_material("REF_P2", (0.05, 0.4, 0.8, 1))}

    class _M:
        def __init__(self, mat):
            self.by_key = {"paint": mat}

    def box(name, lo_g, hi_g, mat):
        m = Mesh()
        (x0, y0, z0), (x1, y1, z1) = lo_g, hi_g
        m.box_lohi(P.gv(x0, y0, z0), P.gv(x1, y1, z1), (1, 1, 1, 1))
        return create_object(name, m, _M(mat), ref)

    box("REF_Belt", (-K.BELT_HALF, K.SEA_Y - 2, K.BELT_Z0), (K.BELT_HALF, K.DECK_Y, K.BELT_Z1), belt)
    for s in (-1, 1):
        box(f"REF_Frame{'L' if s < 0 else 'R'}", (s * (K.BELT_HALF - K.FRAME_W), K.FRAME_BOTTOM, K.BELT_Z0 - 1.2),
            (s * K.BELT_HALF, K.FRAME_TOP, K.BELT_Z1 + 1.2), frame)
    for i, z in enumerate((-12.0, -42.0, -72.0)):
        box(f"REF_Wall{i}", (-12, K.DECK_Y, z - 0.3), (12, K.DECK_Y + 5.2, z + 0.3), wall)
        box(f"REF_Wall{i}_DoorL", (1.7, K.DECK_Y, z + 0.31), (5.3, K.DECK_Y + 2.38, z + 0.35), doors["blue"])
        box(f"REF_Wall{i}_DoorR", (-5.3, K.DECK_Y, z + 0.31), (-1.7, K.DECK_Y + 2.38, z + 0.35), doors["red"])
        box(f"REF_Wall{i}_Q", (-4.5, K.DECK_Y + 2.6, z + 0.31), (4.5, K.DECK_Y + 4.4, z + 0.35), doors["panel"])
    for name, x in (("P1", K.PLAYER_X[0]), ("P2", K.PLAYER_X[1])):
        box(f"REF_{name}", (x - 0.35, K.DECK_Y, -0.25), (x + 0.35, K.DECK_Y + 1.8, 0.25), chars[name])
    # 海
    sea = Mesh()
    s = 3000.0
    sea.add_face([(-s, -s, K.SEA_Y), (s, -s, K.SEA_Y), (s, s, K.SEA_Y), (-s, s, K.SEA_Y)], (1, 1, 1, 1))
    seam = flat_material("REF_Sea", (0.04, 0.40, 0.50, 1.0), roughness=0.25)
    create_object("REF_Sea", sea, _M(seam), ref)
    # 保守船（のこぎりの台車を運ぶ船、メニューの停泊位置）
    vessel_path = K.ROOT / "assets" / "hazards" / "saw_service_vessel.glb"
    kept = [ob for ob in bpy.data.objects if ob.name.startswith("REF_VSL_")]
    for ob in kept:
        for c in list(ob.users_collection):
            if c != ref:
                c.objects.unlink(ob)
        if ob.name not in ref.objects:
            ref.objects.link(ob)
    if vessel_path.exists() and not kept:
        before = set(bpy.data.objects.keys())
        bpy.ops.import_scene.gltf(filepath=str(vessel_path))
        new = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - before]
        for ob in new:
            for c in list(ob.users_collection):
                c.objects.unlink(ob)
            ref.objects.link(ob)
            ob.name = "REF_VSL_" + ob.name
        for ob in new:
            if ob.parent is None:
                ob.location = P.gv(0.0, K.DECK_Y, 11.15)
    # 街（スタジアムの .blend から）
    city = bpy.data.objects.get("AQS_BG_City")
    if city is None:
        with bpy.data.libraries.load(str(K.STADIUM_BLEND), link=False) as (src, dst):
            dst.objects = ["AQS_BG_City"]
        city = bpy.data.objects["AQS_BG_City"]
    refc = collection("REF_City", sc.collection)
    for c in list(city.users_collection):
        if c != refc:
            c.objects.unlink(city)
    if city.name not in refc.objects:
        refc.objects.link(city)
    place = K.city_placement()
    city.matrix_world = Matrix.Translation(K.g2b(*place["position"])) @ Matrix.Rotation(place["yaw"], 4, "Z")
    return place


# --- メニューの街（ビル群の手前を作り直す） ---------------------------------------------------
FRONT_BAND_Y = 231.0          # これより手前（街のローカル +y）の島：護岸・砂浜・並木
FRONT_ROWS_Y = 137.0          # これより手前で地面（z 4.5）から立つ箱：窓のない低い街並み


def trim_city(src, coll):
    """街の複製から、手前の低い箱（とその屋上の設備）・護岸・砂浜・並木を取り除く。ams_waterfront が作り直す。
    メッシュは面の島（頂点を共有する面のつながり）ごとに判定する。返り値：(オブジェクト, 残した建物の足もと, 消した面の数)"""
    import bmesh
    me = src.data.copy()
    me.name = "AMS_City"
    bm = bmesh.new()
    bm.from_mesh(me)
    parent = list(range(len(bm.verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for f in bm.faces:
        r0 = find(f.verts[0].index)
        for v in f.verts[1:]:
            r = find(v.index)
            if r != r0:
                parent[r] = r0
    islands = {}
    for f in bm.faces:
        islands.setdefault(find(f.verts[0].index), []).append(f)
    boxes = {}
    for k, faces in islands.items():
        cos = [v.co for f in faces for v in f.verts]
        boxes[k] = (min(c.x for c in cos), max(c.x for c in cos), min(c.y for c in cos), max(c.y for c in cos),
                    min(c.z for c in cos), max(c.z for c in cos))
    kill, fronts = set(), []
    for k, (x0, x1, y0, y1, z0, z1) in boxes.items():
        if y0 >= FRONT_BAND_Y:
            kill.add(k)
        elif y0 >= FRONT_ROWS_Y and abs(z0 - W.GROUND) < 0.01:
            kill.add(k)
            fronts.append((x0, x1, y0, y1, z1))
    for k, (x0, x1, y0, y1, z0, z1) in boxes.items():       # 屋上の設備（消した箱の上面に載るもの）
        if k in kill or y0 < FRONT_ROWS_Y:
            continue
        if any(x0 >= a0 - 0.05 and x1 <= a1 + 0.05 and y0 >= b0 - 0.05 and y1 <= b1 + 0.05 and abs(z0 - top) < 0.05
               for a0, a1, b0, b1, top in fronts):
            kill.add(k)
    dead = [f for k in kill for f in islands[k]]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("AMS_City", me)
    coll.objects.link(ob)
    ob.matrix_world = src.matrix_world.copy()
    avoid = [(x0, x1, y0, y1) for k, (x0, x1, y0, y1, z0, z1) in boxes.items()
             if k not in kill and y1 > 100.0 and (x1 - x0) < 200.0 and z1 - z0 > 5.0]
    return ob, avoid, len(dead), len(fronts)


RESTYLE_STYLES = ("mansion", "tile", "loggia", "punched", "ribbon", "brick", "flat")


def restyle_midrise(ob, seed=11, share=0.65):
    """残した街の中層ビル（高さ 105m 未満・間口 50m 未満、手前寄り）の外壁を、住宅の型の画像に貼り替える。
    どれも同じ事務所の格子だった手前の中層が、マンション・タイル・ロッジア・不規則な窓などに変わる。
    スタジアムの外壁と同じ 8 スパン × 8 階の UV なので、そのまま貼れる。高層（象徴のビル）はそのまま。"""
    import bmesh
    import random as _random
    rnd = _random.Random(seed)
    me = ob.data
    for style in RESTYLE_STYLES:
        mat = bpy.data.materials[f"AMS_Facade_{style.capitalize()}"]
        if mat.name not in [m.name for m in me.materials]:
            me.materials.append(mat)
    index = {m.name: i for i, m in enumerate(me.materials)}
    facade = {i for i, m in enumerate(me.materials) if m.name.startswith("AQS_CityFacade_")}
    bm = bmesh.new()
    bm.from_mesh(me)
    parent = list(range(len(bm.verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for f in bm.faces:
        r0 = find(f.verts[0].index)
        for v in f.verts[1:]:
            r = find(v.index)
            if r != r0:
                parent[r] = r0
    islands = {}
    for f in bm.faces:
        islands.setdefault(find(f.verts[0].index), []).append(f)
    changed = {}
    for k in sorted(islands, key=lambda key: min(f.index for f in islands[key])):
        faces = islands[k]
        if not any(f.material_index in facade for f in faces):
            continue
        cos = [v.co for f in faces for v in f.verts]
        x0, x1 = min(c.x for c in cos), max(c.x for c in cos)
        y0, y1 = min(c.y for c in cos), max(c.y for c in cos)
        z1 = max(c.z for c in cos)
        if z1 >= 105.0 or y1 < -200.0 or x1 - x0 > 50.0 or y1 - y0 > 50.0:
            continue
        if rnd.random() >= share:
            continue
        # 高い棟に不規則な窓・レンガを貼ると窓が多すぎてうるさいので、60m を超える棟は落ち着いた型だけ
        style = rnd.choice(RESTYLE_STYLES if z1 <= 60.0 else ("mansion", "tile", "ribbon", "flat", "loggia"))
        target = index[f"AMS_Facade_{style.capitalize()}"]
        for f in faces:
            if f.material_index in facade:
                f.material_index = target
        changed[style] = changed.get(style, 0) + 1
    bm.to_mesh(me)
    bm.free()
    return changed


def build_city(sc):
    coll = collection("AMS_CITY_EXPORT", sc.collection)
    src = bpy.data.objects["AQS_BG_City"]
    city, avoid, removed, boxes_removed = trim_city(src, coll)
    src.hide_render = True
    src.hide_viewport = True

    class _Mats:
        by_key = {
            "paint": bpy.data.materials["AQS_BG_Painted"],
            "night": bpy.data.materials["AQS_NightGlow"],
        }
    for style in W.FACADE_STYLES:
        _Mats.by_key[style] = image_material(f"AMS_Facade_{style.capitalize()}", K.TEX / f"harbor_facade_{style}.png", roughness=0.3,
                                             vertex_tint=True, night_path=K.TEX / f"harbor_facade_{style}_night.png")
    restyled = restyle_midrise(city)
    parts, winfo = W.build(avoid=avoid)
    origins = winfo.pop("origins")          # 観覧車の輪（軸）とゴンドラ（吊り点）の原点（街のローカル）
    winfo["restyled_midrise"] = restyled
    objs = {"AMS_City": city}
    for name, mesh in parts.items():
        ob = create_object(name, mesh, _Mats, coll)
        ob.matrix_world = src.matrix_world @ Matrix.Translation(origins.get(name, (0.0, 0.0, 0.0)))
        objs[name] = ob
    info = {"removed_faces": removed, "removed_boxes": boxes_removed, "avoid": len(avoid), **winfo}
    log(f"city: removed {removed} faces ({boxes_removed} boxes), waterfront {winfo['district']['buildings']} buildings "
        f"{winfo['district']['types']}, {winfo['boats']} boats, Ferris wheel {len(origins) - 1} gondolas")
    return objs, info, origins


def export_city_glb(objs, origins):
    """街の部品を街のローカル座標で書き出す（行列を単位に。観覧車の輪とゴンドラは原点の平行移動だけ残す：
    glTF の別々のノードになり、Godot はその原点で輪を回し、ゴンドラを動かす）。Godot は配置 JSON の city の位置・向きに置く。"""
    saved = {n: ob.matrix_world.copy() for n, ob in objs.items()}
    try:
        for n, ob in objs.items():
            ob.matrix_world = Matrix.Translation(origins.get(n, (0.0, 0.0, 0.0)))
        for scene in bpy.data.scenes:
            for vl in scene.view_layers:
                for ob in scene.objects:
                    try:
                        ob.select_set(False, view_layer=vl)
                    except Exception:
                        pass
        for ob in objs.values():
            ob.select_set(True)
        bpy.context.view_layer.objects.active = objs["AMS_City"]
        bpy.ops.export_scene.gltf(
            filepath=str(K.CITY_GLB), export_format="GLB", use_selection=True, use_active_scene=True, export_apply=True, export_yup=True,
            export_animations=False, export_cameras=False, export_lights=False, export_extras=False,
            export_vertex_color="ACTIVE", export_image_format="AUTO", export_materials="EXPORT",
        )
        bpy.ops.object.select_all(action="DESELECT")
    finally:
        for n, ob in objs.items():
            ob.matrix_world = saved[n]
    return K.CITY_GLB


def edge_samples(me, step=0.25):
    """メッシュの辺を step ごとに刻んだ点（オブジェクトのローカル、numpy の (n, 3)）。頂点だけだと長い棒の途中を見落とす。"""
    import numpy as np
    co = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3).astype(np.float64)
    ed = np.empty(len(me.edges) * 2, dtype=np.int32)
    me.edges.foreach_get("vertices", ed)
    ed = ed.reshape(-1, 2)
    a, b = co[ed[:, 0]], co[ed[:, 1]]
    k = np.maximum(1, np.ceil(np.linalg.norm(b - a, axis=1) / step)).astype(np.int64)
    idx = np.repeat(np.arange(len(ed)), k + 1)
    start = np.repeat(np.cumsum(k + 1) - (k + 1), k + 1)
    t = (np.arange(idx.size) - start) / np.repeat(k, k + 1)
    return a[idx] + (b[idx] - a[idx]) * t[:, None]


def surface_samples(me, step=0.4):
    """面の中も step ごとに刻んだ点（乗り場の床・屋根のような大きな面の中まで）。多角形を扇に三角形へ分け、重心座標の格子で。"""
    import numpy as np
    grids = {}
    out = []
    for poly in me.polygons:
        vs = [np.array(me.vertices[i].co[:], dtype=np.float64) for i in poly.vertices]
        for j in range(1, len(vs) - 1):
            a, b, c = vs[0], vs[j], vs[j + 1]
            n = max(1, min(64, math.ceil(max(np.linalg.norm(b - a), np.linalg.norm(c - a), np.linalg.norm(c - b)) / step)))
            if n not in grids:
                uu, vv = np.meshgrid(np.arange(n + 1), np.arange(n + 1), indexing="ij")
                keep = uu + vv <= n
                grids[n] = (uu[keep] / n, vv[keep] / n)
            u, v = grids[n]
            out.append(a + np.outer(u, b - a) + np.outer(v, c - a))
    return np.concatenate(out) if out else np.zeros((0, 3))


def wheel_checks(objs, origins):
    """観覧車（脚と乗り場・回る輪・ゴンドラ 24）が別々の部品で、1 周回しても当たらないか。回す角度を刻まず、式で 1 周ぶんを調べる。
    座標は軸の中心からの街のローカル（x、y＝軸の向き、z）。ゴンドラの箱はゴンドラのメッシュ（原点＝吊り点）から。
    - 輪とゴンドラ：輪から見ると、ゴンドラの箱は吊り点のまわりを 1 回転する。y が箱の範囲の輪の点で、吊り点からの距離が
      箱の最短〜最長に入るものがないこと（吊り具より上の吊り棒は除く）
    - 脚・乗り場とゴンドラ：ゴンドラは向きを変えずに吊り点の円（半径 R）を回る。脚の点から箱を引いた範囲が、その円に掛からないこと
    - 輪と脚・乗り場：輪は軸まわりに回るので、(軸からの距離, y) の 0.25m の格子で重ならないこと（輪のハブを貫く軸そのものは除く）
    - ゴンドラどうし：隣の吊り点の間隔が箱の対角より長いこと（向きを変えずに同じ円を回るので、間隔は変わらない）"""
    import numpy as np
    res = []

    def check(name, ok, detail=""):
        res.append({"name": name, "pass": bool(ok), "detail": detail})

    names = [f"AMS_FerrisGondola_{i:02d}" for i in range(W.WHEEL_GONDOLAS)]
    need = ["AMS_FerrisWheelStand", "AMS_FerrisWheelRim", *names]
    missing = [n for n in need if n not in objs]
    check("Ferris wheel = stand + turning rim + %d gondolas (separate objects)" % W.WHEEL_GONDOLAS,
          not missing and "AMS_FerrisWheel" not in objs, f"missing {missing}" if missing else "")
    if missing:
        return res
    axle = np.array((W.WHEEL_X, W.WHEEL_Y, W.WHEEL_HUB_Z))
    rim_origin = np.array(origins["AMS_FerrisWheelRim"])
    hang = np.array([origins[n] for n in names]) - axle                     # 吊り点（軸の中心から）
    radius = np.hypot(hang[:, 0], hang[:, 2])
    check("wheel origins: rim on the axle, gondolas on the hang circle",
          np.allclose(rim_origin, axle, atol=1e-4) and np.allclose(radius, W.WHEEL_R, atol=1e-3) and np.allclose(hang[:, 1], 0.0, atol=1e-4),
          f"rim {np.round(rim_origin - axle, 4).tolist()}, hang radius {radius.min():.3f}..{radius.max():.3f}")
    rim_pts = edge_samples(objs["AMS_FerrisWheelRim"].data)                 # 輪の原点＝軸の中心
    mid = rim_pts[np.abs(rim_pts[:, 1]) < 0.3]
    bar = np.min(np.hypot(mid[:, None, 0] - hang[None, :, 0], mid[:, None, 2] - hang[None, :, 2]), axis=0) if len(mid) else np.full(len(hang), 1e9)
    check("every gondola hangs from a pivot bar of the rim", float(bar.max()) < 0.25, f"max {bar.max():.3f} m")
    # ゴンドラの箱（全体と、吊り具の下の本体）
    gco = np.concatenate([np.array([v.co[:] for v in objs[n].data.vertices]) for n in names])
    body = gco[gco[:, 2] < -1.0]
    gx0, gx1, gy0, gy1, gz0, gz1 = gco[:, 0].min(), gco[:, 0].max(), gco[:, 1].min(), gco[:, 1].max(), gco[:, 2].min(), gco[:, 2].max()
    bz1 = body[:, 2].max()
    m = 0.05
    near = math.hypot(min(max(0.0, gx0), gx1), min(max(0.0, gz0), bz1))
    far = max(math.hypot(x, z) for x in (gx0, gx1) for z in (gz0, bz1))
    band = rim_pts[(rim_pts[:, 1] > gy0 - m) & (rim_pts[:, 1] < gy1 + m)]
    dist = np.hypot(band[:, None, 0] - hang[None, :, 0], band[:, None, 2] - hang[None, :, 2])
    hits = int(np.count_nonzero((dist > near - m) & (dist < far + m)))
    check("gondolas turn clear of the rim (full turn)", hits == 0, f"{hits} rim points; gondola body {near:.2f}..{far:.2f} m from the hang point")
    stand = surface_samples(objs["AMS_FerrisWheelStand"].data) - axle       # 脚の原点＝街の原点
    sb = stand[(stand[:, 1] > gy0 - m) & (stand[:, 1] < gy1 + m)]
    lox, hix = sb[:, 0] - gx1 - m, sb[:, 0] - gx0 + m
    loz, hiz = sb[:, 2] - gz1 - m, sb[:, 2] - gz0 + m
    dmin = np.hypot(np.clip(0.0, lox, hix), np.clip(0.0, loz, hiz))
    dmax = np.hypot(np.maximum(np.abs(lox), np.abs(hix)), np.maximum(np.abs(loz), np.abs(hiz)))
    hits = int(np.count_nonzero((dmin <= W.WHEEL_R) & (dmax >= W.WHEEL_R)))
    lowest = W.WHEEL_HUB_Z - W.WHEEL_R + gz0 - W.GROUND
    check("gondolas turn clear of the stand and the platform", hits == 0, f"{hits} stand points; lowest gondola floor {lowest:.2f} m above ground")
    cell = 0.25

    def keys(p):
        return (np.floor(np.hypot(p[:, 0], p[:, 2]) / cell).astype(np.int64) * 100000
                + np.floor(p[:, 1] / cell).astype(np.int64) + 50000)
    rim_key = keys(rim_pts)
    occupied = np.unique(np.concatenate([rim_key + dr * 100000 + dy for dr in (-1, 0, 1) for dy in (-1, 0, 1)]))
    outer = stand[np.hypot(stand[:, 0], stand[:, 2]) > 1.0]
    clash = int(np.count_nonzero(np.isin(keys(outer), occupied)))
    check("rim turns clear of the stand (legs, bearings, platform)", clash == 0, f"{clash} stand points")
    ang = np.sort(np.arctan2(hang[:, 2], hang[:, 0]))
    step = float(np.min(np.diff(np.concatenate([ang, ang[:1] + 2 * math.pi]))))
    chord = 2 * W.WHEEL_R * math.sin(step / 2)
    diag = math.hypot(gx1 - gx0, gz1 - gz0)
    check("gondolas never touch each other", chord > diag + 2 * m, f"hang spacing {chord:.2f} m, gondola {diag:.2f} m")
    return res


def pose_ferris_wheel(objs, origins, angle_deg):
    """観覧車を angle_deg だけ回した姿勢にする（確認レンダー用。GLB の書き出しの後に使い、返り値の行列で戻す）。
    正の角度はメニューのカメラ（輪の正面、+y の側）から見て時計回り＝軸（+y）の右ねじで負の回転。Godot と同じ向き。
    輪は軸まわりに回し、ゴンドラは向きを変えずに吊り点を回す。"""
    city = objs["AMS_City"].matrix_world
    ax = Vector((W.WHEEL_X, W.WHEEL_Y, W.WHEEL_HUB_Z))
    rot = Matrix.Rotation(math.radians(-angle_deg), 4, "Y")
    saved = {n: objs[n].matrix_world.copy() for n in origins}
    objs["AMS_FerrisWheelRim"].matrix_world = city @ Matrix.Translation(ax) @ rot
    for n, o in origins.items():
        if n.startswith("AMS_FerrisGondola_"):
            objs[n].matrix_world = city @ Matrix.Translation(ax + rot.to_3x3() @ (Vector(o) - ax))
    return saved


def city_checks(objs, info, origins):
    res = []

    def check(name, ok, detail=""):
        res.append({"name": name, "pass": bool(ok), "detail": detail})

    tris = {n: sum(len(p.vertices) - 2 for p in ob.data.polygons) for n, ob in objs.items()}
    total = sum(tris.values())
    check("city triangles <= 120000", total <= 120000, f"{total}")
    check("front band trimmed (boxes, sea wall, tree row)", info["removed_boxes"] >= 80 and info["removed_faces"] > 500,
          f"{info['removed_boxes']} boxes, {info['removed_faces']} faces")
    city = objs["AMS_City"].data
    # 土地の前面・斜めの縁（大きな面、新しい護岸の裏）は残る
    left = sum(1 for p in city.polygons if p.center.y > FRONT_BAND_Y and p.center.z < 12.0 and p.area < 2000.0)
    check("no old sea wall / tree row left", left == 0, f"{left} faces")
    mats = sorted({m.name for ob in objs.values() for m in ob.data.materials})
    check("every building type is used", set(info["district"]["types"]) == set(W.BUILDERS), sorted(info["district"]["types"]))
    check("city materials are backdrop materials", all(n == "AQS_BG_Painted" or n == "AQS_NightGlow" or n.startswith(("AQS_CityFacade_", "AMS_Facade_"))
                                                       for n in mats), ", ".join(mats))
    # 岸辺の街がカメラから 600m より遠い（ステージの演出の場所に掛からない）
    cam = Vector(K.g2b(*K.CAMERA["position"]))
    near = min((ob.matrix_world @ v.co - cam).length for n, ob in objs.items() if n != "AMS_City" for v in ob.data.vertices)
    check("waterfront farther than 600 m from the menu camera", near > 600.0, f"{near:.0f} m")
    res.extend(wheel_checks(objs, origins))
    return res, tris, mats


def build_lights_world(sc):
    lc = collection("LIGHTING_Review", sc.collection)
    sun = bpy.data.lights.new("LGT_Sun", "SUN")
    sun.energy = 3.4
    sun.angle = math.radians(1.2)
    ob = bpy.data.objects.new("LGT_Sun", sun)
    lc.objects.link(ob)
    # カメラの左後ろ上から（仰角 45°）：メニューのカメラは Blender +Y を向く
    ob.rotation_euler = (math.radians(45), 0.0, math.radians(-160))
    w = bpy.data.worlds.get("AMS_World") or bpy.data.worlds.new("AMS_World")
    if w.node_tree is None:
        w.use_nodes = True
    nt = w.node_tree
    bg = next((n for n in nt.nodes if n.type == "BACKGROUND"), None) or nt.nodes.new("ShaderNodeBackground")
    out = next((n for n in nt.nodes if n.type == "OUTPUT_WORLD"), None) or nt.nodes.new("ShaderNodeOutputWorld")
    if not out.inputs["Surface"].is_linked:
        nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    bg.inputs[0].default_value = (0.50, 0.72, 0.92, 1)
    bg.inputs[1].default_value = 1.1
    sc.world = w


def camera(sc, name, pos_g, forward_g=None, target_g=None, fov=K.CAM_FOV, coll=None, clip_start=0.05):
    cd = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, cd)
    (coll or collection("CAMERAS", sc.collection)).objects.link(cam)
    p = K.g2b(*pos_g)
    if target_g is not None:
        t = K.g2b(*target_g)
        d = (t - p).normalized()
    else:
        f = forward_g
        d = Vector((f[0], -f[2], f[1])).normalized()
    cam.location = p
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cd.sensor_fit = "VERTICAL"
    cd.angle_y = math.radians(fov)
    cd.clip_start = clip_start   # 遠くを見るカメラは大きく（Blender の奥行きの精度は近い端で決まる）
    cd.clip_end = 6000.0
    return cam


def build_cameras(sc, info):
    cams = {}
    cams["CAM_Menu"] = camera(sc, "CAM_Menu", K.CAMERA["position"], forward_g=tuple(K.camera_basis_forward(K.CAMERA["rotation_deg"])))
    cams["CAM_MenuOld"] = camera(sc, "CAM_MenuOld", K.OLD_CAM_POS, forward_g=tuple(K.camera_basis_forward(K.OLD_CAM_ROT)))
    dc = K.DECK_C
    frame = info["deck"]["frame"]
    front = frame @ Vector((-2.0, -26.0, 4.0))
    look = frame @ Vector((0.0, 3.0, 4.2))
    cams["CAM_Deck"] = camera(sc, "CAM_Deck", (front.x, front.z, -front.y), target_g=(look.x, look.z, -look.y), fov=40.0)
    cams["CAM_Top"] = camera(sc, "CAM_Top", (8.0, 170.0, -40.0), target_g=(8.0, 0.0, -40.1), fov=50.0)
    cams["CAM_Runway"] = camera(sc, "CAM_Runway", (-24.0, 3.0, -2.0), target_g=(-12.0, -2.0, -40.0), fov=45.0)
    # 岸辺の街：メニューのカメラの位置から望遠（画面の中央の観覧車のあたり）と、海の上の近景（Codex の下絵と同じ位置）
    cm = bpy.data.objects["AQS_BG_City"].matrix_world

    def city_g(x, y, z):
        v = cm @ Vector((x, y, z))
        return (v.x, v.z, -v.y)
    cams["CAM_Waterfront"] = camera(sc, "CAM_Waterfront", K.CAMERA["position"], target_g=city_g(40.0, 236.0, 22.0), fov=9.0, clip_start=2.0)
    cams["CAM_WaterfrontLeft"] = camera(sc, "CAM_WaterfrontLeft", K.CAMERA["position"], target_g=city_g(400.0, 236.0, 20.0), fov=9.0, clip_start=2.0)
    cams["CAM_WaterfrontA"] = camera(sc, "CAM_WaterfrontA", city_g(230.0, 560.0, 16.0), target_g=city_g(230.0, 150.0, 40.0), fov=50.0, clip_start=5.0)
    cams["CAM_WaterfrontB"] = camera(sc, "CAM_WaterfrontB", city_g(-150.0, 560.0, 16.0), target_g=city_g(-150.0, 150.0, 40.0), fov=50.0, clip_start=5.0)
    # 観覧車：メニューのカメラの位置から望遠（止まった姿勢と、回した姿勢の 2 枚を撮る）
    cams["CAM_FerrisWheel"] = camera(sc, "CAM_FerrisWheel", K.CAMERA["position"], target_g=city_g(W.WHEEL_X, W.WHEEL_Y, W.WHEEL_HUB_Z - 3.0),
                                     fov=6.5, clip_start=2.0)
    sc.camera = cams["CAM_Menu"]
    return cams


# --- 書き出し -----------------------------------------------------------------------
def export_glb(objs):
    # ほかのシーン（ユーザーの Scene）で選ばれているものが混ざらないよう、全シーンの選択を外す
    for scene in bpy.data.scenes:
        for vl in scene.view_layers:
            for ob in scene.objects:
                try:
                    ob.select_set(False, view_layer=vl)
                except Exception:
                    pass
    for ob in objs.values():
        ob.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(objs.values()))
    K.GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(K.GLB), export_format="GLB", use_selection=True, use_active_scene=True, export_apply=True, export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False, export_extras=False,
        export_vertex_color="ACTIVE", export_image_format="AUTO", export_materials="EXPORT",
    )
    bpy.ops.object.select_all(action="DESELECT")
    return K.GLB


def write_layout(info, place, city_info=None):
    frame = info["deck"]["frame"]
    def g(v):
        return [round(v.x, 3), round(v.z, 3), round(-v.y, 3)]
    sign_c = frame @ Vector((0.0, P.BACK_Y, P.SIGN_Z0 + P.SIGN_H / 2))
    led_c = frame @ Vector((0.0, P.BACK_Y, P.LED_Z0 + P.LED_H / 2))
    pads = {k: g(frame @ Vector((v[0], v[1], 0.0))) for k, v in info["deck"]["pads"].items()}
    axle = [round(W.WHEEL_X, 3), round(W.WHEEL_Y, 3), round(W.WHEEL_HUB_Z, 3)]
    data = {
        "note": "メニューのワールド（Godot）座標。GLB はこの座標で作ってあるので原点に置くだけ。街（aiquiz_menu_city.glb、街のローカル座標）は city の位置・向きで置く。",
        "glb": "res://assets/aiquiz_menu_stage/aiquiz_menu_stage.glb",
        "stage_meshes": list(info["meshes"]),
        "stage_note": "2026-09-30：走路の脇の白い丸杭・奥の歩道・ガラスの手すり・琥珀の灯・照明塔と、発進デッキから走路への橋を外した（ディスプレイのステージだけ）。"
                      "ベルトの箱の側面の白い外装（AMS_PierFascia）はビルダーの KEEP_PIER_FASCIA で戻せる（そのとき stage_meshes に入る）",
        "camera": {"position": list(K.CAMERA["position"]), "rotation_degrees": list(K.CAMERA["rotation_deg"]), "fov": K.CAMERA["fov"],
                   "old_rotation_degrees": list(K.OLD_CAM_ROT)},
        "city": {"glb": "res://assets/aiquiz_menu_stage/aiquiz_menu_city.glb",
                 "made_from": "スタジアムの遠景の AQS_BG_City の複製から手前の低い箱・護岸・並木を除き（AMS_City）、岸辺の街（AMS_City*）と"
                              "観覧車（AMS_FerrisWheelStand・AMS_FerrisWheelRim・AMS_FerrisGondola_00〜23）を足したもの",
                 "position": [round(c, 3) for c in place["position"]], "yaw_deg": round(math.degrees(place["yaw"]), 3),
                 "bearing_from_camera_deg": K.CITY_BEARING, "distance_from_camera": K.CITY_DISTANCE,
                 "waterfront": {"wheel_center_local": axle,
                                "wheel_radius": W.WHEEL_R,
                                "wheel_axle_local": axle,
                                "wheel_axis_local": [float(c) for c in W.WHEEL_AXIS],
                                "wheel_hang_radius": W.WHEEL_R,
                                "wheel_gondolas": W.WHEEL_GONDOLAS,
                                "wheel_nodes": {"stand": "AMS_FerrisWheelStand", "rim": "AMS_FerrisWheelRim",
                                                "gondola_prefix": "AMS_FerrisGondola_"},
                                "wheel_note": "Blender の街のローカル（x, y, z）。Godot の街のローカルでは (x, z, -y)。輪（原点＝軸の中心）を軸まわりに回し、"
                                              "ゴンドラ（原点＝吊り点、止まっている姿勢で軸から半径 wheel_hang_radius）は向きを変えずに原点を輪と同じだけ回す。"
                                              "軸の向き（+y）は輪の正面・メニューのカメラの側",
                                "quay_y_local": W.QUAY_Y, "ground_z_local": W.GROUND,
                                "buildings": (city_info or {}).get("district", {}).get("buildings"), "boats": (city_info or {}).get("boats")}},
        "launch_deck": {"center": [K.DECK_C[0], K.WALK_TOP, K.DECK_C[1]], "radius": K.DECK_R,
                        "yaw_deg": round(math.degrees(info["deck"]["yaw"]), 3), "pads": pads},
        "sign_center": g(sign_c), "led_center": g(led_c),
        "led_size": [P.LED_W, P.LED_H], "sign_size": [P.SIGN_W, P.SIGN_H],
        "tower_tops": [g(Vector(t)) for t in info["tower_tops"]],
        "keep_clear": {
            "belt": {"x": [-K.BELT_EDGE, K.BELT_EDGE], "z": [K.BELT_Z0, K.BELT_Z1], "note": "ベルトの上と側枠には何も置かない"},
            "runway_sides": {"abs_x": K.RUNWAY_SIDE_CLEAR_X, "z": [K.BELT_Z0, K.BELT_Z1],
                             "note": "走路の脇（|x| < %.0f）には外装（AMS_PierFascia、戻したときだけ）のほかに何も置かない" % K.RUNWAY_SIDE_CLEAR_X},
            "saw_zone": {"z": list(K.SAW_ZONE_Z), "stowed_blades_abs_x": list(K.SAW_STOW_X),
                         "note": "のこぎりの台車・操縦席のデッキ・収納した刃が動く所。外装は操縦席のデッキの下（y ≤ %.2f）だけ" % K.FASCIA_TOP},
            "helicopter": {"pickups": [list(p) for p in K.PICKUPS], "hover_height": K.PICKUP_HOVER, "rotor_radius": K.HELI_ROTOR_R},
        },
        "materials": {
            "AQS_Painted": "頂点色（ゲームの共有材質 aiquiz_stadium_materials.gd に差し替え）",
            "AMS_Lamp": "昼も光る灯（頂点色を発光）",
            "AMS_Glass": "ガラスの手すり（半透明）",
            "AMS_LedScreen": "LED（Godot で shaders/aiquiz_menu_led.gdshader に差し替え、UV 0..1）",
            "AMS_Sign": "看板（画像、少し発光）",
            "AMS_Paving": "舗装（画像×頂点色、平面投影の UV：3m で 1 周期）",
            "AMS_Pennant": "旗・吹き流し（Godot で揺れのシェーダー、UV2.x = 重み）",
            "AMS_Foliage": "ヤシの葉（Godot で揺れのシェーダー、UV2.x = 重み）",
        },
    }
    K.LAYOUT_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    return data


# --- 検算 ------------------------------------------------------------------------
def world_verts(ob):
    mw = ob.matrix_world
    for v in ob.data.vertices:
        w = mw @ v.co
        yield (w.x, w.z, -w.y)      # Godot


def checks(objs, info):
    res = []

    def check(name, ok, detail=""):
        res.append({"name": name, "pass": bool(ok), "detail": detail})

    tris = {n: sum(len(p.vertices) - 2 for p in ob.data.polygons) for n, ob in objs.items()}
    total = sum(tris.values())
    check("triangles <= 60000", total <= 60000, f"{total}")
    mat_names = sorted({m.name for ob in objs.values() for m in ob.data.materials})
    check("materials <= 9", len(mat_names) <= 9, ", ".join(mat_names))
    check("no .001 names", not any("." in n for n in list(objs) + mat_names), "")
    # ベルトの上（|x| < 12.24 かつ y > -2.2、z がベルトの範囲）に何もない
    over_belt = 0
    saw = 0
    heli = 0
    below_fascia_near = 0
    runway_sides = 0
    for n, ob in objs.items():
        for (x, y, z) in world_verts(ob):
            if abs(x) < K.BELT_EDGE - 0.005 and y > K.SEA_Y - 1.0 and K.BELT_Z0 - 2 < z < K.BELT_Z1 + 2:
                over_belt += 1
            # 走路の脇：杭・歩道・照明塔・橋を外したので、外装のほかに何もない（2026-09-30）
            if n != "AMS_PierFascia" and abs(x) < K.RUNWAY_SIDE_CLEAR_X and K.BELT_Z0 - 2 < z < K.BELT_Z1 + 2:
                runway_sides += 1
            if K.SAW_ZONE_Z[0] < z < K.SAW_ZONE_Z[1] and K.SAW_STOW_X[0] - 0.05 < abs(x) < K.SAW_STOW_X[1] + 0.3 and -6.0 < y < 4.0:
                saw += 1
            if K.SAW_ZONE_Z[0] < z < K.SAW_ZONE_Z[1] and abs(x) < K.SAW_STOW_X[0] and y > K.FASCIA_TOP + 0.01:
                below_fascia_near += 1
            # ヘリ：回収点の真上（ホバー 10.2m ± ローター半径）と、奥へのブーストの通り道（x -14..10、高さ 7m 以上、z < 10）
            if -14.0 < x < 10.0 and y > K.DECK_Y + 7.0 and -150 < z < 12:
                heli += 1
    check("nothing over the belt", over_belt == 0, f"{over_belt} verts")
    check("saw stow zone clear", saw == 0, f"{saw} verts")
    check("near zone only under the operator deck", below_fascia_near == 0, f"{below_fascia_near} verts")
    check("helicopter corridor clear", heli == 0, f"{heli} verts")
    check("runway sides clear (no piles, walkways, light towers or bridge)", runway_sides == 0, f"{runway_sides} verts")
    # デッキの寸法
    frame = info["deck"]["frame"]
    c = frame @ Vector((0, 0, 0))
    check("deck centre", abs(c.x - K.DECK_C[0]) < 1e-3 and abs(-c.y - K.DECK_C[1]) < 1e-3, f"{c.x:.2f}, {-c.y:.2f}")
    # 看板と LED がカメラへ向いている（法線とカメラ方向の内積 > 0.9）
    cam = Vector(K.g2b(*K.CAMERA["position"]))
    for n in ("AMS_Sign", "AMS_LedScreen"):
        ob = objs[n]
        p = ob.data.polygons[0]
        nrm = (ob.matrix_world.to_3x3() @ p.normal).normalized()
        ctr = ob.matrix_world @ p.center
        d = (cam - ctr).normalized()
        check(f"{n} faces the camera", nrm.dot(d) > 0.85, f"dot {nrm.dot(d):.3f}")
    # 面の向き（外向き）：閉じた部品の体積が正
    for n in ("AMS_LaunchDeck", "AMS_Backdrop"):
        ob = objs[n]
        me = ob.data
        vol = 0.0
        for poly in me.polygons:
            vs = [me.vertices[i].co for i in poly.vertices]
            for k in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[k].cross(vs[k + 1])) / 6.0
        check(f"{n} outward normals (signed volume > 0)", vol > 0, f"{vol:.1f}")
    return res, tris, mat_names


# --- レンダー ---------------------------------------------------------------------
def render(sc, cam, path, res=(1920, 1080), samples=48):
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    try:
        sc.eevee.taa_render_samples = samples
    except Exception:
        pass
    sc.render.filepath = str(path)
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True, scene=sc.name)
    return str(path)


def main():
    sc = reset_scene()
    mats = materials()
    ex = collection("AMS_EXPORT", sc.collection)
    objs, info = build_parts(mats, ex)
    place = build_reference(sc)
    city_objs, city_info, city_origins = build_city(sc)
    build_lights_world(sc)
    cams = build_cameras(sc, info)
    glb = export_glb(objs)
    city_glb = export_city_glb(city_objs, city_origins)
    layout = write_layout(info, place, city_info)
    res, tris, mat_names = checks(objs, info)
    city_res, city_tris, city_mats = city_checks(city_objs, city_info, city_origins)
    res.extend(city_res)
    renders = {}
    if K.DO_RENDER:
        K.PREVIEW.mkdir(parents=True, exist_ok=True)
        K.EVIDENCE.mkdir(parents=True, exist_ok=True)
        for name in ("CAM_Menu", "CAM_Deck", "CAM_Top", "CAM_Runway", "CAM_MenuOld"):
            renders[name] = render(sc, cams[name], K.EVIDENCE / f"{name.lower()}.png")
        for name in ("CAM_Waterfront", "CAM_WaterfrontLeft", "CAM_WaterfrontA", "CAM_WaterfrontB"):
            res_px = (1920, 1080) if name.endswith(("A", "B")) else (1920, 820)
            renders[name] = render(sc, cams[name], K.EVIDENCE / f"{name.lower()}.png", res=res_px)
        # 観覧車：止まった姿勢と、20° 回した姿勢（輪は軸まわり、ゴンドラは向きを変えずに移動）。撮ったら元の姿勢に戻す
        renders["CAM_FerrisWheel"] = render(sc, cams["CAM_FerrisWheel"], K.EVIDENCE / "cam_ferriswheel.png")
        saved = pose_ferris_wheel(city_objs, city_origins, 20.0)
        try:
            renders["CAM_FerrisWheel_turned"] = render(sc, cams["CAM_FerrisWheel"], K.EVIDENCE / "cam_ferriswheel_turned.png")
        finally:
            for n, mw in saved.items():
                city_objs[n].matrix_world = mw
        sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
        sc.camera = cams["CAM_Menu"]
    report = {
        "built": time.strftime("%Y-%m-%d %H:%M:%S"),
        "seconds": round(time.time() - T0, 1),
        "glb": str(glb.relative_to(K.ROOT)).replace("\\", "/"),
        "glb_sha256": hashlib.sha256(glb.read_bytes()).hexdigest(),
        "triangles": tris, "triangles_total": sum(tris.values()),
        "materials": mat_names,
        "city_glb": str(city_glb.relative_to(K.ROOT)).replace("\\", "/"),
        "city_glb_sha256": hashlib.sha256(city_glb.read_bytes()).hexdigest(),
        "city_triangles": city_tris, "city_triangles_total": sum(city_tris.values()),
        "city_materials": city_mats,
        "city": {k: v for k, v in city_info.items() if k != "district"} | {"buildings": city_info["district"]["buildings"],
                                                                           "building_types": city_info["district"]["types"]},
        "checks": res,
        "renders": renders,
        "layout": str(K.LAYOUT_JSON.relative_to(K.ROOT)).replace("\\", "/"),
    }
    all_pass = all(r["pass"] for r in res)
    report["all_checks_pass"] = all_pass
    K.REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    # .blend は複製で保存する（開いているファイルの保存先は変えない）
    try:
        bpy.ops.wm.save_as_mainfile(filepath=str(K.BLEND), copy=True, compress=True)
        report["blend"] = str(K.BLEND.relative_to(K.ROOT)).replace("\\", "/")
    except Exception as exc:  # noqa: BLE001
        report["blend_error"] = str(exc)
    summary = {"all_checks_pass": all_pass, "triangles": report["triangles_total"], "materials": len(mat_names),
               "city_triangles": report["city_triangles_total"], "city_materials": len(city_mats),
               "failed": [r["name"] + " (" + r["detail"] + ")" for r in res if not r["pass"]], "seconds": report["seconds"]}
    print("AMS_BUILD " + json.dumps(summary, ensure_ascii=False))
    return summary


if __name__ == "__main__":
    RESULT = main()

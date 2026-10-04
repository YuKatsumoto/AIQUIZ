"""AIQUIZ STADIUM を Blender で組み立て、書き出し、確認レンダーまで行う決定的なビルダー（v2）。

    ユーザーのライブ Blender 上で実行する（Higgsfield の Blender 連携 bl_execute 経由、手順は ../../README.md の「作り直し」）。
    引数は sys.argv = ["blender", "--", "--no-render"] のように "--" の後ろに渡す（--no-render / --only-renders a,b）。

寸法はすべて ../dimensions.json と ../game_constants.json から読む（Scene Passport: SCENE_PASSPORT.md）。
開いているシーンを空にしてから、次を作る：

- シーン AIQUIZ_Stadium_Modules：書き出す部品。スタンド・帆・ゲート・ゴール観客席は原点に、遠景はワールドの位置に置く
- シーン AIQUIZ_Stadium_Layout：部品をゲームの座標どおりに並べた確認用。床（ベルトコンベア）と問題壁はゲームの形をそのまま写した参照物
- assets/aiquiz_stadium/*.glb と座席・配置の JSON、source/blender/aiquiz_stadium.blend
- 確認レンダー（ゲームのカメラ、原本の空撮に近いカメラ、夕暮れ・夜、部品ごと）と build_report.json

座標：Blender は Z 上。Godot = (X, Z, -Y)。コースは Godot +Z = Blender -Y へ進む。
v2 の変更：帆を原本の形（スタンドを横切る三角帆・半透明・ふくらみ）に作り直して別メッシュに、遠景（島・街・ヨット）を
原本の配置で作り直し、床はゲームのベルトコンベアのまま（走路の下の杭は床の箱に隠れるので作らない）。
"""
from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import aqs_geom as AG  # noqa: E402
import aqs_review as RV  # noqa: E402
import aqs_wear as WR  # noqa: E402
from aqs_backdrop import city, far_sea, island, sailboat  # noqa: E402
from aqs_common import (ASSET, BG, BLEND, DECK_Y, DO_RENDER, DO_WEAR, EVIDENCE, GG, GOAL_STAND_OFFSET, GOAL_Z, GS, LH, ONLY,  # noqa: E402
                        OCEAN_CENTER_Z, OCEAN_HALF, PREVIEW, ROOT, SEA_Y, SR, SRC, ST, TEX, bearing_pos, facing_yaw, g2b,
                        in_ocean)
from aqs_parts import build_goal_gate, build_goal_stand, build_lighthouse, build_stand_block  # noqa: E402
from aqs_sails import sail_rig  # noqa: E402


def reset():
    """開いているファイルのデータを消して空にする。ファイルは読み直さない（Blender 連携の bl_execute の中で読み直すと、
    実行中のコンテキストが古いまま残って glTF の書き出しが失敗する。read_factory_settings はユーザー設定まで戻す）。"""
    scene = bpy.context.window.scene if bpy.context.window else bpy.data.scenes[0]
    for other in list(bpy.data.scenes):
        if other != scene:
            bpy.data.scenes.remove(other)
    for blocks in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.cameras, bpy.data.lights,
                   bpy.data.worlds, bpy.data.collections, bpy.data.actions, bpy.data.node_groups, bpy.data.curves,
                   bpy.data.textures):
        for block in list(blocks):
            blocks.remove(block)
    scene.world = None
    scene.name = "AIQUIZ_Stadium_Modules"
    scene.unit_settings.system = "METRIC"
    return scene


def weld(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def mesh_stats(obj):
    me = obj.data
    me.calc_loop_triangles()
    bm = bmesh.new()
    bm.from_mesh(me)
    nm = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = [min(c[i] for c in corners) for i in range(3)]
    hi = [max(c[i] for c in corners) for i in range(3)]
    return {"triangles": len(me.loop_triangles), "vertices": len(me.vertices), "materials": [m.name for m in me.materials],
            "non_manifold_edges": nm, "bounds_blender": [[round(v, 3) for v in lo], [round(v, 3) for v in hi]]}


def export_glb(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, use_active_scene=True, export_apply=True,
                              export_yup=True, export_animations=False, export_cameras=False, export_lights=False,
                              export_extras=False, export_vertex_color="ACTIVE",
                              export_active_vertex_color_when_no_material=True, export_image_format="AUTO")
    bpy.ops.object.select_all(action="DESELECT")
    return {"file": str(path.relative_to(ROOT)).replace("\\", "/"), "bytes": path.stat().st_size}


def make_materials():
    mats = AG.Materials()
    mats.add("goal_board", AG.image_material("AQS_GoalBoard", TEX / "goal_board.png", emission=0.25))
    mats.add("lh_sign", AG.image_material("AQS_LighthouseSign", TEX / "lighthouse_sign.png", emission=0.15))
    mats.add("header", AG.image_material("GS_SBHeaderSign", TEX / "lighthouse_sign.png", emission=0.2))
    mats.add("screen", AG.flat_material("GS_ScoreboardScreen", (0.02, 0.03, 0.025, 1.0), 0.25))
    mats.add("booth", AG.image_material("AQS_BoothScreen", TEX / "booth_screen.png", emission=1.2, roughness=0.3))
    fabric = AG.image_material("AQS_SailFabric", TEX / "sail_fabric.png", roughness=0.85, vertex_tint=True)
    fabric.use_backface_culling = False            # 帆の布だけは両面（glTF doubleSided=true）
    mats.add("sail", fabric)
    # 遠景（島・街）の頂点色と沖の海。Godot では遠景のシェーダー（距離のかすみ）に差し替える
    mats.add("bg", AG.vertex_colour_material("AQS_BG_Painted", 0.88))
    mats.add("sea", AG.vertex_colour_material("AQS_BG_Sea", 1.0))
    for k in ("a", "b", "c", "d", "e"):
        mats.add(f"city_{k}", AG.image_material(f"AQS_CityFacade_{k.upper()}", TEX / f"city_facade_{k}.png", roughness=0.3,
                                                 vertex_tint=True, night_path=TEX / f"city_facade_{k}_night.png"), night_ratio=0.5)
    return mats


def wet_test(gx, gz, yaw_deg, margin=25.0):
    """部品の座標 (x, y) → place_world と同じ向きに回した位置が、ゲームの海の板の下（縁から margin 内側）か。"""
    c, s = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))

    def wet(lx, ly):
        bx, by = gx + lx * c - ly * s, -gz + lx * s + ly * c
        return in_ocean(bx, -by, margin)
    return wet


def place_world(obj, gpos, yaw_deg):
    obj.location = g2b(*gpos)
    obj.rotation_euler = (0, 0, math.radians(yaw_deg))


def build_all():
    t0 = time.time()
    scene = reset()
    mats = make_materials()
    report = {"version": 2, "modules": {}, "exports": [], "checks": [], "wear": {}}
    parts = {}

    # 1 スタンドのブロック（帆なし）
    coll = AG.collection("AQS_EXPORT_StandBlocks")
    blocks, stand_objs = {}, {}
    for kind, name in (("bay", "AQS_Stand_Bay"), ("cap_start", "AQS_Stand_CapStart"), ("cap_end", "AQS_Stand_CapEnd")):
        mesh, seats, own_aisle = build_stand_block(kind)
        o = AG.create_object(name, mesh, mats, coll)
        weld(o)
        if DO_WEAR:
            report["wear"][name] = WR.bake_wear(o, SEA_Y, WR.STAND_TILES[kind])        # 水面は局所座標の −9.2（ブロックの原点は Godot の Y=0）
        stand_objs[kind] = o
        st = mesh_stats(o)
        blocks[kind] = {"node": name, "seats": seats, "aisle_z": [-10.0] if own_aisle else [], "triangles": st["triangles"]}
        report["modules"][name] = st
    blocks["bay_pergola"] = dict(blocks["bay"])   # 既存スクリプトの「3 つ目ごとのパーゴラ」枠は標準ブロックで埋める
    parts["stand"] = stand_objs

    # 2 帆（左右別。どちらも Godot の +Z へふくらむ）
    coll = AG.collection("AQS_EXPORT_SailRigs")
    for key, name, sign in (("sail_R", "AQS_SailRig_R", -1.0), ("sail_L", "AQS_SailRig_L", 1.0)):
        o = AG.create_object(name, sail_rig(SR, sign), mats, coll)
        weld(o)
        parts[key] = o
        report["modules"][name] = mesh_stats(o)

    # 3 ゲート
    coll = AG.collection("AQS_EXPORT_GoalGate")
    o = AG.create_object("AQS_GoalGate", build_goal_gate(), mats, coll)
    weld(o)
    if DO_WEAR:
        # 原点は床の上面（Godot の Y=-1.2）なので、水面は局所座標の SEA_Y − DECK_Y
        report["wear"][o.name] = WR.bake_wear(o, SEA_Y - DECK_Y)
    parts["gate"] = o
    report["modules"][o.name] = mesh_stats(o)

    # 4 ゴール観客席
    coll = AG.collection("AQS_EXPORT_GoalStand")
    s_mesh, b_mesh = build_goal_stand()
    o1 = AG.create_object("GS_Stand", s_mesh, mats, coll)
    o2 = AG.create_object("GS_Scoreboard", b_mesh, mats, coll)
    for o in (o1, o2):
        weld(o)
        report["modules"][o.name] = mesh_stats(o)
    if DO_WEAR:
        # スタンド本体と電光掲示板は同じ局所座標（原点は床の上面）。互いの影を落とす
        report["wear"][o1.name] = WR.bake_wear(o1, SEA_Y - DECK_Y, extra=(o2,))
        report["wear"][o2.name] = WR.bake_wear(o2, SEA_Y - DECK_Y, extra=(o1,))
    parts["goal_stand"] = [o1, o2]

    # 5 遠景（灯台・島・街・ヨット）：ワールドの位置に置いて書き出す
    coll = AG.collection("AQS_EXPORT_Backdrop")
    bg = []
    lh = AG.create_object("AQS_Lighthouse", build_lighthouse(), mats, coll)
    place_world(lh, (LH["position_world_xz"][0], SEA_Y, LH["position_world_xz"][1]), LH["yaw_deg"])
    bg.append(lh)
    for k, spec in enumerate(BG["islands"]):
        gx, gy, gz = bearing_pos(spec["bearing_deg"], spec["distance"])
        yaw = facing_yaw(gx, gz)
        # 海の中の浅瀬と白波は、ゲームの海の板が上にある所だけ（外では空の下半分に砂が見えてしまう）
        wet = wet_test(gx, gz, yaw)
        mesh = island(spec, 11 + k, wet)
        o = AG.create_object(spec["name"], mesh, mats, coll)
        o["aqs_shelf"] = wet(0.0, 0.0)
        o["aqs_shelf_faces"] = mesh.shelf_faces
        place_world(o, (gx, gy, gz), yaw)
        bg.append(o)
    cs = BG["city"]
    o = AG.create_object(cs["name"], city(cs), mats, coll)
    gx, gy, gz = bearing_pos(cs["bearing_deg"], cs["distance"])
    place_world(o, (gx, gy, gz), facing_yaw(gx, gz))
    bg.append(o)
    # 沖の海：ゲームの海の板の外側（街と遠い小島はその外に立つ）を、カメラの far まで埋める
    sea_center = g2b(0.0, SEA_Y, OCEAN_CENTER_Z)
    o = AG.create_object("AQS_BG_FarSea", far_sea((sea_center.x, sea_center.y), OCEAN_HALF, 5300.0, SEA_Y - 0.3), mats, coll)
    bg.append(o)
    for k, spec in enumerate(BG["sailboats"]):
        o = AG.create_object(spec["name"], sailboat(spec["length"], spec["sail"], seed=50 + k), mats, coll)
        gx, gy, gz = bearing_pos(spec["bearing_deg"], spec["distance"], SEA_Y + 0.3)
        place_world(o, (gx, gy, gz), spec["heading_deg"])
        bg.append(o)
    for o in bg:
        weld(o)
        report["modules"][o.name] = mesh_stats(o)
    parts["backdrop"] = bg

    # --- 書き出し
    out = (("aiquiz_stadium_stand_blocks.glb", list(stand_objs.values())),
           ("aiquiz_stadium_sail_rigs.glb", [parts["sail_R"], parts["sail_L"]]),
           ("aiquiz_stadium_goal_gate.glb", [parts["gate"]]),
           ("aiquiz_stadium_goal_stand.glb", parts["goal_stand"]),
           ("aiquiz_stadium_backdrop.glb", bg))
    for fname, objs in out:
        report["exports"].append(export_glb(objs, ASSET / fname))
    seat_layout = {"block_length": ST["block_length"], "seat_rows": ST["rows"]["count"],
                   "note": "Godot block space: x away from the course, y up, z along it. The aisle of a block is on its -Z edge. Same schema as santorini_terrace_modules.json (bay_pergola reuses the bay block).",
                   "blocks": blocks, "pergola_every": 3,
                   "sail_rig": {"right": "AQS_SailRig_R", "left": "AQS_SailRig_L", "on": ["bay", "bay_pergola"],
                                "note": "Add one rig per bay block in the same block transform. R for the +X stand (unrotated), L for the -X stand (rotated PI). Both billow toward +Z."}}
    (ASSET / "aiquiz_stadium_stand_blocks.json").write_text(json.dumps(seat_layout, indent=1), encoding="utf-8")
    placements = {
        "note": "Godot world coordinates. Stands: |x| 28, left side rotated PI, 20 m blocks from the floor back end. The backdrop GLB is authored in world space (instance it at the stage origin).",
        "goal_gate": {"node": "AQS_GoalGate", "origin": "goal line centre on the belt top (y -1.2)", "replaces": "game_world.gd の金色の柱と梁・GOAL の Label3D（市松の線は残す）"},
        "goal_stand": {"file": "aiquiz_stadium_goal_stand.glb", "contract": "goal_stand.glb と同じ：GS_Stand / GS_Scoreboard、LED 面の材質名 GS_ScoreboardScreen（UV 0..1）、goal_stand_layout.json はそのまま"},
        "backdrop": {o.name: {"position": [round(o.location.x, 2), round(o.location.z, 2), round(-o.location.y, 2)],
                              "yaw_deg": round(math.degrees(o.rotation_euler.z), 2)} for o in bg},
        "materials": {"AQS_SailFabric": "両面・半透明（Godot は帆のシェーダー：UV2.x の重みで風に揺らし、backlight で透かす）",
                      "AQS_Painted / AQS_NightGlow / AQS_BoothScreen / AQS_CityFacade_*": "vertex_color_use_as_albedo を入れる。NightGlow と CityFacade の夜の発光は昼夜の切り替えで"},
    }
    (ASSET / "aiquiz_stadium_layout.json").write_text(json.dumps(placements, ensure_ascii=False, indent=1), encoding="utf-8")

    report["checks"] = run_checks(parts, blocks)
    report["build_seconds_modules"] = round(time.time() - t0, 1)
    layout = RV.build_layout_scene(parts, mats, {k: v["seats"] for k, v in blocks.items()})
    report["layout_scene"] = layout.name
    return scene, layout, mats, report, parts


def run_checks(parts, blocks):
    checks = []

    def chk(name, ok, detail):
        checks.append({"item": name, "pass": bool(ok), "detail": detail})

    for kind, o in parts["stand"].items():
        st = mesh_stats(o)
        lo, hi = st["bounds_blender"]
        chk(f"{o.name}: 内側面 |x|≥27.2", 28 + lo[0] >= 27.2 - 1e-3, f"world |x| min {28 + lo[0]:.3f}")
        chk(f"{o.name}: 三角形 15k 以下", st["triangles"] <= 15000, st["triangles"])
        chk(f"{o.name}: 杭の下端 -17.2", abs(lo[2] - (-17.2)) < 1e-3, lo[2])
        chk(f"{o.name}: 座席 114", len(blocks[kind]["seats"]) == 114, len(blocks[kind]["seats"]))
        chk(f"{o.name}: 材質 4 種以内", len(st["materials"]) <= 4, st["materials"])
        chk(f"{o.name}: 高さ（ヘリの開始 Y13.7 より 1m 以上低い）", hi[2] < 13.7 - 1.0, f"top {hi[2]:.2f}")
    for key in ("sail_R", "sail_L"):
        o = parts[key]
        st = mesh_stats(o)
        lo, hi = st["bounds_blender"]
        me = o.data
        fab = [i for i, m_ in enumerate(me.materials) if m_.name == "AQS_SailFabric"][0]
        uv2 = me.uv_layers.get("UV2")
        zs = [me.vertices[me.loops[li].vertex_index].co.z for p in me.polygons if p.material_index == fab for li in p.loop_indices]
        ws = [uv2.data[li].uv.x for p in me.polygons if p.material_index == fab for li in p.loop_indices]
        chk(f"{o.name}: 走路側の端 |x|≥28.5（海落下カメラの通り道 |x|<27.2 より 1.3m 外）", 28 + lo[0] >= 28.5 - 1e-3, round(28 + lo[0], 3))
        chk(f"{o.name}: 帆の最も低い所が観客の頭（約 3.9）より 1.5m 以上上", min(zs) >= 3.9 + 1.5, round(min(zs), 3))
        chk(f"{o.name}: 揺れの重み UV2.x（縁 0・中央 ≈1）", uv2 is not None and min(ws) == 0.0 and max(ws) > 0.9, [round(min(ws), 3), round(max(ws), 3)])
        chk(f"{o.name}: 三角形 1.5k 以下", st["triangles"] <= 1500, st["triangles"])
        chk(f"{o.name}: 高さ（マストの頂を越えない）", hi[2] <= ST["mast"]["top_z"] + 0.01, round(hi[2], 3))
    bulge = {k: sum(v.co.y for v in parts[k].data.vertices) / len(parts[k].data.vertices) for k in ("sail_R", "sail_L")}
    chk("帆：右（ブロック座標 -Y）と左（+Y）でふくらむ向きが逆＝どちらもゴール側", bulge["sail_R"] < 0 < bulge["sail_L"], {k: round(v, 3) for k, v in bulge.items()})
    mats_all = {m_.name: m_ for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith("REF_") for m_ in o.data.materials}
    single = {n: m_.use_backface_culling for n, m_ in mats_all.items()}
    chk("材質：帆の布だけ両面、ほかは片面", single.get("AQS_SailFabric") is False and all(v for n, v in single.items() if n != "AQS_SailFabric"),
        sorted(n for n, v in single.items() if not v))
    gate = parts["gate"]
    lo, hi = mesh_stats(gate)["bounds_blender"]
    chk("GOAL ゲート: 走路の幅（|x|≤12.0）に収まる", max(abs(lo[0]), abs(hi[0])) <= 12.0 + 1e-3, [lo[0], hi[0]])
    chk("GOAL ゲート: 梁の下 5.0m", abs(GG["clear_height"] - 5.0) < 1e-6, GG["clear_height"])
    gs_stand, gs_board = parts["goal_stand"]
    screen_mat = [m.name for m in gs_board.data.materials]
    chk("ゴール観客席: LED 面の材質 GS_ScoreboardScreen", "GS_ScoreboardScreen" in screen_mat, screen_mat)
    me = gs_board.data
    idx = [i for i, m in enumerate(me.materials) if m.name == "GS_ScoreboardScreen"][0]
    uvs, area, normal = [], 0.0, (0, 0, 0)
    for p in me.polygons:
        if p.material_index == idx:
            uvs = [tuple(round(v, 3) for v in me.uv_layers["UVMap"].data[li].uv) for li in p.loop_indices]
            area = p.area
            normal = tuple(round(v, 3) for v in p.normal)
    chk("ゴール観客席: LED 面 11.2×4.8、-Y 向き、UV 0..1", abs(area - 11.2 * 4.8) < 0.05 and normal[1] < -0.99 and sorted(uvs) == [(0, 0), (0, 1), (1, 0), (1, 1)],
        {"area": round(area, 3), "normal": normal, "uv": uvs})
    lo, hi = mesh_stats(gs_stand)["bounds_blender"]
    chk("ゴール観客席: デッキ幅 26.6・杭の下端が海底 -129.2", abs((hi[0] - lo[0]) - 26.6) < 0.05 and abs(lo[2] + DECK_Y - (-129.2)) < 1e-3,
        [round(hi[0] - lo[0], 3), round(lo[2] + DECK_Y, 3)])
    lh = next(o for o in parts["backdrop"] if o.name == "AQS_Lighthouse")
    me = lh.data
    sign_idx = [i for i, m_ in enumerate(me.materials) if m_.name == "AQS_LighthouseSign"][0]
    sp = next(p_ for p_ in me.polygons if p_.material_index == sign_idx)
    nrm = lh.matrix_world.to_3x3() @ sp.normal
    to_start = -lh.location.copy()
    to_start.z = 0
    ang = math.degrees(nrm.to_2d().angle(to_start.to_2d().normalized()))
    chk("灯台: 看板がスタート地点を向く（ずれ 2° 以内）", ang < 2.0, round(ang, 2))
    lo, hi = mesh_stats(lh)["bounds_blender"]
    chk("灯台: 全高 ≒ 寸法表", abs(hi[2] - SEA_Y - LH["resolved"]["dome_top_above_water"]) < 0.5, round(hi[2] - SEA_Y, 2))
    far = BG["camera_far"]
    worst, worst_name = 0.0, ""
    for o in parts["backdrop"]:
        if o.name == "AQS_BG_FarSea":             # 沖の海はわざと far まで伸ばす（外は描かれないだけ）
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            d = math.hypot(w.x, w.y - 9.0)          # 2P カメラ（Godot z -9 ＝ Blender y +9）から
            if d > worst:
                worst, worst_name = d, o.name
    chk("遠景: すべてゲームのカメラの far（5000m）の内側（沖の海を除く）", worst < far, [round(worst, 1), worst_name])
    sea = next(o for o in parts["backdrop"] if o.name == "AQS_BG_FarSea")
    me = sea.data
    # 内側の縁の頂点は、海の板の縁から 2m 内側（四角形の辺の上）。それより内側に頂点がない
    deep_inside = sum(1 for v in me.vertices if in_ocean(v.co.x, -v.co.y, 2.5))
    edge = [v for v in me.vertices if in_ocean(v.co.x, -v.co.y, 1.5)]
    on_edge = all(abs(max(abs(v.co.x) - OCEAN_HALF[0], abs(-v.co.y - OCEAN_CENTER_Z) - OCEAN_HALF[1]) + 2.0) < 0.01 for v in edge)
    st = mesh_stats(sea)
    chk("沖の海: 上向きの面だけ・内側の縁が海の板の縁に沿う（2m 重ね）・水面の 0.3m 下",
        deep_inside == 0 and on_edge and len(edge) > 0 and all(p.normal.z > 0.99 for p in me.polygons)
        and abs(st["bounds_blender"][1][2] - (SEA_Y - 0.3)) < 1e-3,
        {"faces": len(me.polygons), "edge_vertices": len(edge), "deep_inside": deep_inside, "triangles": st["triangles"]})
    cityo = next(o for o in parts["backdrop"] if o.name == BG["city"]["name"])
    lo, hi = mesh_stats(cityo)["bounds_blender"]
    chk("街: いちばん高いビル ≒ 寸法表（原本のように水平線から大きく立つ）", abs((hi[2] - SEA_Y) - BG["city"]["tallest"] - 30) < 25, round(hi[2] - SEA_Y, 1))
    for o in parts["backdrop"]:
        if o.name.startswith("AQS_BG_Island") or o.name.startswith("AQS_BG_Islet"):
            st = mesh_stats(o)
            spec = next(s for s in BG["islands"] if s["name"] == o.name)
            chk(f"{o.name}: 三角形 60k 以下・高さ ≒ 寸法表", st["triangles"] <= 60000 and (st["bounds_blender"][1][2] - SEA_Y) < spec["height"] * 1.6,
                [st["triangles"], round(st["bounds_blender"][1][2] - SEA_Y, 1)])
            low = st["bounds_blender"][0][2] - SEA_Y
            shelf = o["aqs_shelf_faces"]
            chk(f"{o.name}: 海の中の地形は水際の岩の底（-8m）より浅い（ゲームの海越しに崖が見えない）", low > -8.0, round(low, 1))
            if o["aqs_shelf"]:
                chk(f"{o.name}: 海の板の内側なので浅瀬の棚がある", shelf > 150, shelf)
            else:
                chk(f"{o.name}: 海の板の外なので浅瀬を作らない", shelf == 0, shelf)
    st = mesh_stats(cityo)
    chk("街: 三角形 40k 以下", st["triangles"] <= 40000, st["triangles"])
    total = sum(mesh_stats(o)["triangles"] for o in parts["backdrop"])
    chk("遠景: 三角形の合計 180k 以下", total <= 180000, total)
    return checks


def main():
    t0 = time.time()
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    modules_scene, layout, mats, report, parts = build_all()
    renders = {}
    if DO_RENDER:
        renders.update(RV.module_renders(modules_scene, parts, parts["stand"]))
        shots = [("day", "CAM_2P", "layout_2p_day"), ("day", "CAM_1P", "layout_1p_day"), ("day", "CAM_Master", "layout_master_day"),
                 ("day", "CAM_SailClose", "layout_sail_close_day"), ("day", "CAM_City", "layout_city_day"),
                 ("day", "CAM_Goal", "layout_goal_day"), ("day", "CAM_Water", "layout_water_day"), ("day", "CAM_Overview", "layout_overview_day"),
                 ("day", "CAM_Lighthouse", "layout_lighthouse_day"), ("day", "CAM_Finale", "layout_finale_day"),
                 ("day", "CAM_IslandL", "layout_island_left_day"), ("day", "CAM_IslandR", "layout_island_right_day"),
                 ("dusk", "CAM_City", "layout_city_dusk"), ("night", "CAM_City", "layout_city_night"),
                 ("dusk", "CAM_1P", "layout_1p_dusk"), ("dusk", "CAM_2P", "layout_2p_dusk"),
                 ("night", "CAM_1P", "layout_1p_night"), ("night", "CAM_2P", "layout_2p_night")]
        for mood, cam, name in shots:
            if ONLY and name not in ONLY:
                continue
            RV.set_mood(layout, mats, mood)
            renders[name] = RV.render(layout, cam, EVIDENCE / f"{name}.png", frame=1)
        RV.set_mood(layout, mats, "day")
        if not ONLY or "flyover" in ONLY:
            for f in (1, 60, 120):
                renders[f"flyover_{f:03d}"] = RV.render(layout, "CAM_Flyover", EVIDENCE / f"flyover_{f:03d}.png", frame=f)
        layout.frame_set(1)
        layout.camera = bpy.data.objects["CAM_2P"]
    else:
        RV.set_mood(layout, mats, "day")
    keep = ["layout_2p_day", "layout_1p_day", "layout_master_day", "layout_sail_close_day", "layout_city_day", "layout_goal_day",
            "layout_water_day", "layout_2p_dusk", "layout_2p_night", "layout_finale_day", "layout_island_left_day",
            "layout_island_right_day", "layout_city_dusk", "layout_city_night", "module_stand_bay", "module_sail_rig",
            "module_goal_stand", "module_island_lush", "module_island_rocky", "module_city"]
    previews = []
    for old in PREVIEW.glob("*.jpg"):
        old.unlink()                 # 前の版のプレビューは消して、今の版だけを残す
    for name in keep:
        if name not in renders:
            continue
        img = bpy.data.images.load(renders[name])
        dst = PREVIEW / f"{name}.jpg"
        bpy.context.scene.render.image_settings.file_format = "JPEG"
        bpy.context.scene.render.image_settings.quality = 84
        img.save_render(str(dst), scene=bpy.context.scene)
        bpy.context.scene.render.image_settings.file_format = "PNG"
        bpy.data.images.remove(img)
        previews.append(str(dst.relative_to(ROOT)).replace("\\", "/"))
    report["previews"] = previews
    fly = bpy.data.objects["CAM_Flyover"]
    samples = {f: RV.evaluated_location(layout, fly, f) for f in (1, 10, 60, 110, 120)}
    layout.frame_set(1)
    moved = samples[1] != samples[60] != samples[120]
    rest = samples[110] == samples[120] and samples[1] == samples[10]
    end_ok = (Vector(samples[120]) - g2b(0, 4.5, -9)).length < 1e-3
    report["motion"] = {"samples_blender": samples, "moves": moved, "holds_at_start_and_end": rest, "ends_at_2p_camera": end_ok}
    report["renders"] = {k: str(Path(v).relative_to(ROOT)).replace("\\", "/") for k, v in renders.items()}
    report["blend"] = str(BLEND.relative_to(ROOT)).replace("\\", "/")
    report["seconds_total"] = round(time.time() - t0, 1)
    report["all_checks_pass"] = all(c["pass"] for c in report["checks"]) and moved and rest and end_ok
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True, relative_remap=True)
    (SRC / "build_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    print("AQS_BUILD " + json.dumps({"all_checks_pass": report["all_checks_pass"], "seconds": report["seconds_total"],
                                     "failed": [c for c in report["checks"] if not c["pass"]]}, ensure_ascii=False), flush=True)


main()

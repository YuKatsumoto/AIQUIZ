"""乗り込めるヘリ（helicopter_boarding.glb）を作る。

ユーザーが開いているライブの Blender で動かす（Higgsfield の Blender 連携 bl_execute から runpy）。ヘッドレスでは動かさない。
  import runpy, sys
  sys.argv = ["blender", "--"]            # 省略可。"--no-render" "--no-save" "--no-bake" "--no-export" を足せる
  runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/vehicles/helicopter_boarding/source/blender/build_helicopter_boarding.py", run_name="__main__")

数値は source/heli_pilot_spec.json（設計図 artifacts/heli_blueprint が書き出す写し）。形は hb_shell.py（胴体）と hb_parts.py（ほかの部品）。
出力：
  assets/vehicles/helicopter_boarding/helicopter_boarding.glb         ゲームで使うヘリ
  assets/vehicles/helicopter_boarding/helicopter_boarding_layout.json  マーカー・回る部品の軸・ドアのヒンジ
  source/previews/hb_*.png                                             確認レンダー
  source/build_report.json                                             三角形の数・部品・チェック
  source/blender/helicopter_boarding.blend                             （AGENTS.md：作業したら保存する）
"""
from __future__ import annotations

import importlib
import json
import math
import sys
import time
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
for p in (HERE, ROOT / "assets" / "aiquiz_stadium" / "source" / "blender"):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))

import hb_common  # noqa: E402
import hb_shell  # noqa: E402
import hb_parts  # noqa: E402
import aqs_wear  # noqa: E402

for _m in (hb_common, hb_shell, hb_parts, aqs_wear):
    importlib.reload(_m)
K = hb_common
from hb_common import D, GMesh, P, basis_g2b, collection, create_object, empty, make_materials, set_pivot  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_RENDER = "--no-render" not in ARGS
DO_SAVE = "--no-save" not in ARGS
DO_BAKE = "--no-bake" not in ARGS
DO_EXPORT = "--no-export" not in ARGS

SPEC = K.SPEC
EXPORT_COLL = "HB_EXPORT"
REF_COLL = "REF_Review"
BAKE_MATERIALS = ("BodyPaint", "Trim", "Interior", "Floor", "SeatFabric", "DashDark", "Charcoal", "Rubber", "DropHatchInterior")
WEAR_PARAMS = {"ao_radius": 0.55, "ao_strength": 0.40, "ao_rays": 24, "wide_radius": 2.2, "wide_strength": 0.10,
               "dirt_strength": 0.0, "noise_amp": 0.02, "noise_period": 3.0, "floor": 0.58, "ray_lift": 0.02}
FPS = 24
JET_NOZZLE_OPEN_SCALE = 1.35   # 羽根を広げたときの縮尺（Godot の x・y）


# ---------------------------------------------------------------- シーン

def setup_scene():
    sc = bpy.context.scene
    if sc.name != K.SCENE_NAME:
        existing = bpy.data.scenes.get(K.SCENE_NAME)
        if existing is not None:
            bpy.context.window.scene = existing
            sc = existing
        else:
            sc.name = K.SCENE_NAME
    sc.unit_settings.system = "METRIC"
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 1, 150
    # 作り直し：このビルダーのコレクションの中身だけ消す
    for name in (EXPORT_COLL, REF_COLL, "CAMERAS", "LIGHTING"):
        coll = bpy.data.collections.get(name)
        if coll is None:
            continue
        for obj in list(coll.all_objects):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data is not None and getattr(data, "users", 1) == 0:
                if isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
                elif isinstance(data, bpy.types.Camera):
                    bpy.data.cameras.remove(data)
                elif isinstance(data, bpy.types.Light):
                    bpy.data.lights.remove(data)
    for obj in [o for o in sc.collection.objects if o.type in ("MESH", "CAMERA", "LIGHT")]:
        bpy.data.objects.remove(obj, do_unlink=True)   # 空のファイルの既定の物（Cube など）
    return sc


# ---------------------------------------------------------------- 組み立て

def build(mats):
    exp = collection(EXPORT_COLL)
    root = empty("HelicopterRoot", exp, (0, 0, 0), display="ARROWS", size=1.0)
    shell, shell_stats, zs = hb_shell.build_shell()
    meshes: dict[str, GMesh] = {}

    def add(name, *parts):
        m = meshes.setdefault(name, GMesh())
        for part in parts:
            if part is not None:
                m.extend(part)

    add("Body", shell.get("Body"), hb_parts.build_mast_fairing())
    tail_body, tail_rotor, tail_hub = hb_parts.build_tail()
    add("Body", tail_body)
    add("Windows", shell.get("Windows"))
    add("Door_L", shell.get("Door_L"))
    add("Door_R", shell.get("Door_R"))
    dash, screens = hb_parts.build_dash()
    add("Interior", hb_parts.build_interior(), dash)
    add("DashScreens", screens)
    add("Seat_L", hb_parts.build_seat(-1))
    add("Seat_R", hb_parts.build_seat(1))
    add("Booster_R", hb_parts.build_booster())
    add("Belt_L", hb_parts.build_belt_left())
    add("Belt_R", hb_parts.build_belt_right(SPEC["hatena"]["root"]))
    for name, spec in zip(("Yoke_L", "Yoke_R"), SPEC["yokes"]):
        add(name, hb_parts.build_yoke(spec))
    add("FrameAndSkids", hb_parts.build_skids())
    add("Step_L", hb_parts.build_step())
    main_rotor, hub = hb_parts.build_main_rotor()
    add("MainRotor", main_rotor)
    add("TailRotor", tail_rotor)
    well, frame = hb_parts.build_bay()
    add("DropBayInterior", well)
    add("DropBayFrame", frame)
    leaf_l, hinge_l = hb_parts.build_hatch_leaf(-1)
    leaf_r, hinge_r = hb_parts.build_hatch_leaf(1)
    add("DropHatchLeft", leaf_l)
    add("DropHatchRight", leaf_r)
    for name, m in hb_parts.build_lights().items():
        add(name, m)
    jet_pivots = {}
    for side, tag in ((-1, "L"), (1, "R")):
        pod, nozzle, glow, mount, piv = hb_parts.build_jet(side)
        add(f"JetPod_{tag}", pod)
        add(f"JetNozzle_{tag}", nozzle)
        add(f"JetGlow_{tag}", glow)
        add("FrameAndSkids", mount)
        jet_pivots[tag] = piv
    objs = {}
    for name, m in meshes.items():
        objs[name] = create_object(name, m, mats, exp, parent=root)
    pivots = {
        "MainRotor": (P(hub), None),
        "TailRotor": (P(tail_hub), None),
        "DropHatchLeft": (P(hinge_l), None),
        "DropHatchRight": (P(hinge_r), None),
    }
    for side in ("L", "R"):
        p0, p1 = (Vector(v) for v in door_hinge(side))
        pivots[f"Door_{side}"] = (P(p0), basis_g2b(door_basis_g(p0, p1)))
        piv = jet_pivots[side]
        pivots[f"JetPod_{side}"] = (P(piv["pod"]), None)
        pivots[f"JetNozzle_{side}"] = (P(piv["nozzle"]), None)
        pivots[f"JetGlow_{side}"] = (P(piv["glow"]), None)
    JET_PIVOTS.clear()
    JET_PIVOTS.update(jet_pivots)
    return root, objs, pivots, shell_stats


# ジェットのポッド（hb_parts.build_jet）の目印。build() が入れ、stow_jets() と write_layout() が使う
JET_PIVOTS: dict = {}


def jet_stow_basis(side: str, amount: float = 1.0) -> Matrix:
    """ポッドを下へたたむ回転（Blender の座標）。Godot のヒンジの軸（+Z）回り：右は負、左は正の角度で下がる。"""
    sign = 1.0 if side == "L" else -1.0
    return basis_g2b(Matrix.Rotation(sign * math.radians(hb_parts.JET["stow_deg"]) * amount, 3, "Z"))


def stow_jets(objs):
    """羽根・光をポッドの子にし（原点はそのまま）、ポッドをふだんの形（たたんだ向き）へ回す。"""
    for side in ("L", "R"):
        pod = objs[f"JetPod_{side}"]
        for child in (objs[f"JetNozzle_{side}"], objs[f"JetGlow_{side}"]):
            world = child.matrix_world.copy()
            child.parent = pod
            child.matrix_parent_inverse = pod.matrix_world.inverted()
            child.matrix_world = world
        pod.matrix_basis = pod.matrix_basis @ jet_stow_basis(side).to_4x4()
    bpy.context.view_layer.update()


def door_hinge(side):
    hinge = SPEC["door"]["hinge_L"]
    sx = 1 if side == "L" else -1
    return [(sx * h[0], h[1], h[2]) for h in hinge]


def door_basis_g(p0: Vector, p1: Vector) -> Matrix:
    """ドアの向き（Godot の座標）：ローカル +Z がヒンジの線（前 → 後ろ）、+X が機体の +X。"""
    ez = (p1 - p0).normalized()
    ex = Vector((1, 0, 0))
    ex = (ex - ez * ex.dot(ez)).normalized()
    ey = ez.cross(ex)
    return Matrix((ex, ey, ez)).transposed()


def bake(objs):
    stats = []
    meshes = [o for o in objs.values() if o.type == "MESH"]
    for obj in meshes:
        if not any(m is not None and m.name in BAKE_MATERIALS for m in obj.data.materials):
            continue
        extra = [o for o in meshes if o is not obj and o.name not in ("Windows",)]
        st = aqs_wear.bake_wear(obj, -100.0, extra=extra, params=WEAR_PARAMS, materials=BAKE_MATERIALS)
        stats.append(st)
    return stats


def apply_pivots(objs, pivots):
    for name, (pivot, rot) in pivots.items():
        set_pivot(objs[name], pivot, rot)


# ---------------------------------------------------------------- マーカー

def build_markers(root):
    exp = bpy.data.collections[EXPORT_COLL]
    holder = empty("Markers", exp, (0, 0, 0), parent=root, size=0.1)
    out = {}
    for name, m in SPEC["markers"].items():
        x, y, z = m["model"]
        obj = empty(name, exp, (x, -z, y), parent=holder, display="SINGLE_ARROW" if m.get("yaw") is not None else "SPHERE", size=0.22)
        obj.rotation_euler = (0.0, 0.0, math.radians(m["yaw"] or 0.0))
        out[name] = obj
    return out


# ---------------------------------------------------------------- 確認用（書き出さない）

def build_refs(mats):
    ref = collection(REF_COLL)
    mat = bpy.data.materials.get("REF_VertexColor") or bpy.data.materials.new("REF_VertexColor")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.6
    objs = {}
    if not K.REFS_PATH.exists():
        return objs    # 設計図のフォルダがない環境では、確認用の人物なしで作る
    data = json.loads(K.REFS_PATH.read_text(encoding="utf-8"))
    for r in data["refs"]:
        name = r["name"]
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(P(v)) for v in r["verts"]], [], r["faces"])
        me.materials.append(mat)
        col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        for poly, c in zip(me.polygons, r["colors"]):
            poly.use_smooth = name.startswith("REF_Hatena")
            for li in poly.loop_indices:
                col.data[li].color = (*K.lin(c)[:3], 1.0)
        me.update()
        obj = bpy.data.objects.new(name, me)
        ref.objects.link(obj)
        objs[name] = obj
    ground = bpy.data.meshes.new("REF_Ground")
    s = 14.0
    z = -K.ORIGIN_Y
    ground.from_pydata([(-s, -s, z), (s, -s, z), (s, s, z), (-s, s, z)], [], [(0, 1, 2, 3)])
    gmat = bpy.data.materials.get("REF_Deck") or bpy.data.materials.new("REF_Deck")
    gmat.use_nodes = True
    gnt = gmat.node_tree
    gnt.nodes.clear()
    gout = gnt.nodes.new("ShaderNodeOutputMaterial")
    gbsdf = gnt.nodes.new("ShaderNodeBsdfPrincipled")
    gnt.links.new(gbsdf.outputs["BSDF"], gout.inputs["Surface"])
    gbsdf.inputs["Base Color"].default_value = K.hexcol("#59636B")
    gbsdf.inputs["Roughness"].default_value = 0.9
    ground.materials.append(gmat)
    g = bpy.data.objects.new("REF_Ground", ground)
    ref.objects.link(g)
    objs["REF_Ground"] = g
    return objs


def look_at(obj, target_b: Vector):
    d = target_b - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


CAMERAS = {
    # 名前: (位置 Godot, 注視点 Godot, 焦点距離 mm, 正投影の幅)
    "CAM_Hero": ((-7.6, 4.4, -8.4), (0.0, 1.9, -0.6), 38, None),
    "CAM_Front": ((0.0, 2.55, -10.5), (0.0, 2.15, -1.3), 55, None),
    "CAM_Board": ((-6.4, 1.55, -3.4), (-1.3, 1.65, -1.3), 30, None),
    "CAM_Cabin": ((0.0, 2.75, 0.95), (0.0, 1.85, -2.0), 22, None),
    "CAM_SideOrtho": ((-16.0, 2.2, 1.7), (0.0, 2.2, 1.7), 50, 13.5),
    "CAM_JetRear": ((6.2, 4.6, 9.6), (0.0, 2.6, 0.6), 34, None),
}


def build_cameras_lights():
    cams = collection("CAMERAS")
    lights = collection("LIGHTING")
    out = {}
    for name, (pos, tgt, lens, ortho) in CAMERAS.items():
        cd = bpy.data.cameras.new(name)
        cd.lens = lens
        cd.clip_start = 0.05
        if ortho:
            cd.type = "ORTHO"
            cd.ortho_scale = ortho
        cam = bpy.data.objects.new(name, cd)
        cams.objects.link(cam)
        cam.location = P(pos)
        look_at(cam, P(tgt))
        out[name] = cam
    sun_d = bpy.data.lights.new("LGT_Sun", "SUN")
    sun_d.energy = 3.2
    sun_d.angle = math.radians(2.5)
    sun = bpy.data.objects.new("LGT_Sun", sun_d)
    lights.objects.link(sun)
    sun.location = P(-6, 12, -8)
    look_at(sun, P(0, 0, 0))
    world = bpy.data.worlds.get("HB_World") or bpy.data.worlds.new("HB_World")
    world.use_nodes = True
    wnt = world.node_tree
    bg = wnt.nodes.get("Background")
    if bg is None:
        wnt.nodes.clear()
        wout = wnt.nodes.new("ShaderNodeOutputWorld")
        bg = wnt.nodes.new("ShaderNodeBackground")
        bg.name = "Background"
        wnt.links.new(bg.outputs["Background"], wout.inputs["Surface"])
    bg.inputs["Color"].default_value = (0.42, 0.62, 0.86, 1.0)
    bg.inputs["Strength"].default_value = 0.85
    bpy.context.scene.world = world
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.view_settings.view_transform = "Standard"
    try:
        sc.eevee.taa_render_samples = 48
    except AttributeError:
        pass
    sc.camera = out["CAM_Hero"]
    return out


# ---------------------------------------------------------------- 確認用の動き（書き出さない。ゲームでは Godot が動かす）

def door_local(obj, rest_basis_b: Matrix, angle_g: float):
    """ドアをヒンジ（Godot のローカル +Z）のまわりに angle_g だけ回した向き。"""
    return rest_basis_b @ basis_g2b(Matrix.Rotation(angle_g, 3, "Z"))


def preview_animation(objs, pivots):
    sc = bpy.context.scene
    for side, sign in (("L", -1.0), ("R", 1.0)):
        obj = objs[f"Door_{side}"]
        rest = pivots[f"Door_{side}"][1]
        obj.rotation_mode = "QUATERNION"
        obj.animation_data_clear()
        keys = [(1, 0.0), (16, 1.0), (64, 1.0), (79, 0.0)] if side == "L" else [(1, 0.0)]
        for frame, t in keys:
            obj.rotation_quaternion = door_local(obj, rest, sign * math.radians(SPEC["door"]["open_deg"]) * t).to_quaternion()
            obj.keyframe_insert("rotation_quaternion", frame=frame)
    rotor = objs["MainRotor"]
    rotor.animation_data_clear()
    rotor.rotation_mode = "XYZ"
    for frame, ang in ((1, 0.0), (84, 0.0), (150, math.radians(720))):
        rotor.rotation_euler = (0, 0, ang)
        rotor.keyframe_insert("rotation_euler", frame=frame)
    tail = objs["TailRotor"]
    tail.animation_data_clear()
    for frame, ang in ((1, 0.0), (84, 0.0), (150, math.radians(1080))):
        tail.rotation_euler = (ang, 0, 0)
        tail.keyframe_insert("rotation_euler", frame=frame)
    # ジェット：90 → 108 で翼を上げ、100 → 114 で羽根を広げる（ゲームでは Godot が動かす）
    for side in ("L", "R"):
        pod = objs[f"JetPod_{side}"]
        pod.animation_data_clear()
        pod.rotation_mode = "QUATERNION"
        rest = pod.matrix_basis.to_3x3() @ jet_stow_basis(side).inverted()
        for frame, t in ((1, 0.0), (90, 0.0), (108, 1.0), (150, 1.0)):
            pod.rotation_quaternion = (rest @ jet_stow_basis(side, 1.0 - t)).to_quaternion()
            pod.keyframe_insert("rotation_quaternion", frame=frame)
        noz = objs[f"JetNozzle_{side}"]
        noz.animation_data_clear()
        for frame, k in ((1, 1.0), (100, 1.0), (114, JET_NOZZLE_OPEN_SCALE), (150, JET_NOZZLE_OPEN_SCALE)):
            noz.scale = (k, 1.0, k)   # Blender の x・z ＝ Godot の x・y（ポッドの軸に直交）
            noz.keyframe_insert("scale", frame=frame)
    for obj in (objs["Door_L"], rotor, tail):
        for fc in obj.animation_data.action.fcurves if hasattr(obj.animation_data.action, "fcurves") else []:
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
    sc.frame_set(1)


# ---------------------------------------------------------------- 書き出し

def export_glb(root):
    bpy.ops.object.select_all(action="DESELECT")
    targets = [root] + list(root.children_recursive)
    for obj in targets:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    K.GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(K.GLB), export_format="GLB", use_selection=True, use_active_scene=True,
                              export_apply=True, export_yup=True, export_animations=False, export_cameras=False,
                              export_lights=False, export_extras=False, export_vertex_color="ACTIVE",
                              export_image_format="AUTO", export_materials="EXPORT")
    return K.GLB.stat().st_size


def b2g(v: Vector):
    """Blender の座標 → Godot のモデル座標（GLB の座標）。"""
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def jet_layout():
    """ジェットブーストの約束（Godot のモデル座標）。ポッドのふだんの形は stow_deg だけ下へたたんだ向き。"""
    J = hb_parts.JET
    pods = {}
    for side, sign in (("L", -1.0), ("R", 1.0)):
        piv = JET_PIVOTS[side]
        pod = piv["pod"]
        pods[f"JetPod_{side}"] = {
            "pivot": b2g(P(pod)),
            "axis_local": [0, 0, 1],
            "deploy_deg": sign * J["stow_deg"],   # rest * Basis(axis, deploy_deg) で翼が水平
            "nozzle": f"JetNozzle_{side}",
            "glow": f"JetGlow_{side}",
            # ポッドのローカル（広げた向き）での噴射口の出口。炎はここからローカル +Z へ
            "nozzle_exit_local": [round(piv["exit"].x - pod.x, 4), round(piv["exit"].y - pod.y, 4), round(piv["exit"].z - pod.z, 4)],
        }
    return {"pods": pods, "nozzle_open_scale": JET_NOZZLE_OPEN_SCALE, "stow_deg": J["stow_deg"], "pod_radius": J["pod_r"],
            "note": "発進の溜め：翼を上げる → 羽根を広げる → 奥の光を強める → 点火（nozzle_exit_local から +Z）"}


def write_layout(objs, pivots, markers):
    door = {}
    for side, sign in (("L", -1.0), ("R", 1.0)):
        p0, p1 = (Vector(v) for v in door_hinge(side))
        door[f"Door_{side}"] = {"pivot": b2g(P(p0)), "hinge_end": b2g(P(p1)), "axis_local": [0, 0, 1],
                                "open_deg": sign * SPEC["door"]["open_deg"], "open_seconds": 0.6, "close_seconds": 0.6}
    layout = {
        "version": 1,
        "units": "Godot model space (m). 機首 -Z。原点＝ローター軸 × 地面から skid_drop",
        "skid_drop": K.ORIGIN_Y,
        "main_rotor": {"node": "MainRotor", "pivot": b2g(objs["MainRotor"].matrix_world.translation), "axis_local": [0, 1, 0], "park_deg": SPEC["rotor"]["park_deg"]},
        "tail_rotor": {"node": "TailRotor", "pivot": b2g(objs["TailRotor"].matrix_world.translation), "axis_local": [1, 0, 0]},
        "doors": door,
        "hatches": {"DropHatchLeft": {"pivot": b2g(objs["DropHatchLeft"].matrix_world.translation), "axis_local": [0, 0, 1], "open_deg": -SPEC["hatch"]["open_deg"]},
                    "DropHatchRight": {"pivot": b2g(objs["DropHatchRight"].matrix_world.translation), "axis_local": [0, 0, 1], "open_deg": SPEC["hatch"]["open_deg"]}},
        "toggles": {"Belt_L": "座ったら表示（ふだん非表示）", "Belt_R": "ハテナが座っている間は表示", "Beacon": "点滅", "Booster_R": "ハテナが右の席のとき表示（座席のかさ上げ。ジェットではない）"},
        "jet_boost": jet_layout(),
        "tint_material": "BodyPaint",
        "glass_material": "Windows",
        "markers": {name: {"position": m["model"], "yaw_deg": m.get("yaw"), "note": m["note"]} for name, m in SPEC["markers"].items()},
        "hatena": {"root": b2g(P(SPEC["hatena"]["root"])), "scale": 1.0, "yaw_deg": 180},
        "yokes": {"Yoke_L": {"grip_l": b2g(P(SPEC["yokes"][0]["grip_l"])), "grip_r": b2g(P(SPEC["yokes"][0]["grip_r"]))},
                  "Yoke_R": {"grip_l": b2g(P(SPEC["yokes"][1]["grip_l"])), "grip_r": b2g(P(SPEC["yokes"][1]["grip_r"]))}},
        "spec_source": "artifacts/heli_blueprint/heli_pilot_spec.json",
    }
    K.LAYOUT_JSON.write_text(json.dumps(layout, ensure_ascii=False, indent=1), encoding="utf-8")
    return layout


# ---------------------------------------------------------------- 確認

def triangles(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    me = ev.to_mesh()
    n = sum(len(p.vertices) - 2 for p in me.polygons)
    ev.to_mesh_clear()
    return n


def checks(root, objs, pivots):
    rows = []

    def add(name, ok, detail=""):
        rows.append({"check": name, "ok": bool(ok), "detail": detail})

    names = [o.name for o in [root] + list(root.children_recursive)]
    add("名前に .001 がない", all("." not in n for n in names), "")
    required = ["Body", "Windows", "Door_L", "Door_R", "MainRotor", "TailRotor", "DropHatchLeft", "DropHatchRight", "FrameAndSkids",
                "Interior", "Seat_L", "Seat_R", "Yoke_L", "Yoke_R", "Belt_L", "Belt_R", "Step_L", "Booster_R", "Beacon",
                "JetPod_L", "JetPod_R", "JetNozzle_L", "JetNozzle_R", "JetGlow_L", "JetGlow_R"]
    add("必要なノードがそろう", all(n in names for n in required), ", ".join(n for n in required if n not in names))
    add("マーカーがそろう", all(n in names for n in SPEC["markers"]), "")
    tris = {o.name: triangles(o) for o in objs.values()}
    total = sum(tris.values())
    add("三角形の合計", total <= 14000, f"{total}")
    mats = sorted({m.name for o in objs.values() for m in o.data.materials if m is not None})
    add("色替えの材質 BodyPaint がある", "BodyPaint" in mats, ", ".join(mats))
    add("ガラスの材質 Windows がある", "Windows" in mats, "")
    for name in ("Door_L", "Door_R", "MainRotor", "TailRotor", "DropHatchLeft", "DropHatchRight", "JetPod_L", "JetPod_R"):
        want = pivots[name][0]
        got = objs[name].matrix_world.translation
        add(f"{name} の原点", (got - want).length < 1e-4, f"{b2g(got)}")
    # ドアの向き：ローカル -Y（Blender）＝ Godot のローカル +Z がヒンジの線
    p0, p1 = (Vector(v) for v in door_hinge("L"))
    axis_b = D(p1 - p0).normalized()
    local_z_b = (objs["Door_L"].matrix_world.to_3x3() @ Vector((0, -1, 0))).normalized()
    add("Door_L のヒンジの向き", (axis_b - local_z_b).length < 1e-4, "")
    clear = jet_clearance()
    add("たたんだポッドが胴体に入らない", clear["inside"] == 0, f"{clear}")
    add("広げたポッドがローターの円の下", clear["deployed_top"] < SPEC["rotor"]["hub_y"] - 0.35, f"{clear['deployed_top']:.3f}")
    body_dims = objs["Body"].dimensions
    add("胴体の幅（設計 3.64）", abs(body_dims.x - SPEC["overall"]["width_body"]) < 0.08, f"{body_dims.x:.3f}")
    return rows, tris, total


def jet_clearance():
    """たたんだ形・広げた形のポッドの外板の点が胴体（外形）の中に入らないか。Godot の座標で数える。"""
    J = hb_parts.JET
    inside = 0
    min_gap = 9.0
    top = 0.0
    for sgn in (-1.0, 1.0):
        h = hb_parts.jet_hinge(int(sgn))
        a = hb_parts.jet_axis(int(sgn))
        for stowed in (True, False):
            ang = (-sgn * math.radians(J["stow_deg"])) if stowed else 0.0
            rot = Matrix.Rotation(ang, 3, "Z")
            for i in range(21):
                z = -0.28 + i * 0.1
                for k in range(16):
                    t = 2 * math.pi * k / 16
                    p = Vector((a.x + J["pod_r"] * math.cos(t), a.y + J["pod_r"] * math.sin(t), z))
                    q = rot @ (p - Vector((h.x, h.y, z))) + Vector((h.x, h.y, z))
                    if not stowed:
                        top = max(top, q.y)
                    if q.z < K.BP["z"][0] or q.z > K.BP["z"][-1]:
                        continue
                    pr = K.body_params(q.z)
                    if not (pr["bottom"] < q.y < pr["top"]):
                        continue
                    w = K.section_extent(q.z, y=q.y)
                    gap = abs(q.x) - w
                    min_gap = min(min_gap, gap)
                    if gap < 0:
                        inside += 1
    return {"inside": inside, "min_gap": round(min_gap, 3), "deployed_top": round(top, 3)}


def render_views(cams, refs):
    out = {}
    sc = bpy.context.scene
    K.PREVIEW.mkdir(parents=True, exist_ok=True)
    shots = [
        ("CAM_Hero", 16, ["REF_Hatena_Wave", "REF_Player_Step", "REF_Ground"]),
        ("CAM_Front", 1, ["REF_Hatena_Seated", "REF_Player_Driving"]),
        ("CAM_Board", 16, ["REF_Hatena_Wave", "REF_Player_Step", "REF_Ground"]),
        ("CAM_Cabin", 1, ["REF_Hatena_Seated", "REF_Player_Driving"]),
        ("CAM_SideOrtho", 1, ["REF_Ground", "REF_Player_Idle"]),
        ("CAM_Hero", 1, ["REF_Ground"]),
        ("CAM_Hero", 120, ["REF_Ground"]),        # ジェットを広げた形
        ("CAM_JetRear", 1, ["REF_Ground"]),       # 後ろから（たたんだ形）
        ("CAM_JetRear", 120, ["REF_Ground"]),     # 後ろから（広げた形）
    ]
    for i, (cam, frame, show) in enumerate(shots):
        for name, obj in refs.items():
            hide = name not in show
            obj.hide_render = hide
            obj.hide_viewport = hide
        sc.camera = cams[cam]
        sc.frame_set(frame)
        path = K.PREVIEW / f"hb_{i + 1:02d}_{cam[4:].lower()}_f{frame}.png"
        sc.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        out[path.name] = str(path)
    sc.frame_set(1)
    sc.camera = cams["CAM_Hero"]
    for name, obj in refs.items():
        show = name in ("REF_Hatena_Seated", "REF_Player_Driving", "REF_Ground")
        obj.hide_render = not show
        obj.hide_viewport = not show
    return out


def main():
    t0 = time.time()
    sc = setup_scene()
    mats = make_materials()
    root, objs, pivots, shell_stats = build(mats)
    bake_stats = bake(objs) if DO_BAKE else []
    apply_pivots(objs, pivots)
    stow_jets(objs)
    markers = build_markers(root)
    refs = build_refs(mats)
    cams = build_cameras_lights()
    preview_animation(objs, pivots)
    sc.frame_set(1)
    size = export_glb(root) if DO_EXPORT else 0
    layout = write_layout(objs, pivots, markers)
    rows, tris, total = checks(root, objs, pivots)
    renders = render_views(cams, refs) if DO_RENDER else {}
    report = {"seconds": round(time.time() - t0, 1), "glb": str(K.GLB), "glb_bytes": size, "triangles_total": total,
              "triangles": tris, "shell": shell_stats, "checks": rows, "bake": bake_stats, "renders": renders}
    K.REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    if DO_SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=str(K.BLEND))
    return {"seconds": report["seconds"], "triangles_total": total, "glb_bytes": size,
            "failed_checks": [r for r in rows if not r["ok"]], "renders": list(renders), "shell": shell_stats}


if __name__ == "__main__":
    RESULT = main()
    print("HB_BUILD", json.dumps(RESULT, ensure_ascii=False))

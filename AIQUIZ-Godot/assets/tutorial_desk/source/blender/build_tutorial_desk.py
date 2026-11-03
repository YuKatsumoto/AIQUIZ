"""机のセット（ローカル2Pの説明画面の始め・実写）を、ライブの Blender に組み立てる。

計画：docs/new_tutorial/desk_intro/plan.md、作る物の一覧：docs/new_tutorial/desk_intro/scene_passport.md
長さはメートル、Z が上。原点は机の手前の縁の真ん中の床で、+Y が机（奥の壁）の方向、+X が見る人の右。
キーボードは Godot のキー配列（key_layout.json。tools/tutorial_desk/export_key_layout.gd で書き出す）と同じ並び。

ライブの Blender（Higgsfield の Blender 連携の bl_execute）で実行する。ヘッドレスでは動かさない。
    import runpy
    ns = runpy.run_path(r"G:/AIQUIZ-Main/AIQUIZ-Godot/assets/tutorial_desk/source/blender/build_tutorial_desk.py")
    result = ns["build"]("blockout")   # 箱だけの配置とカメラ（構図の確認用）
    result = ns["build"]("detail")     # 作り込み・材質・光
TD_ で始まるコレクションの中身だけを作り直す（ほかの物には触れない）。材質は名前で使い回す。
"""
import json
import math
import random
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[4]
LAYOUT = ROOT / "assets/tutorial_desk/source/key_layout.json"
FONT_PATH = ROOT / "resources/fonts/NotoSansJP-Medium.otf"
SCREEN_IMAGE = ROOT / "docs/new_tutorial/desk_intro/refs/game_screen.jpg"
MASCOT_GLB = ROOT / "assets/characters/aiquiz_mascot/mascot_model.glb"

# 部屋（内側の寸法）。D1 で奥の壁が画面の幅の 8 割ほどに見える広さ
ROOM_W = 4.2
WALL_Y = 0.80
ROOM_FRONT_Y = -4.2
ROOM_H = 2.5
# 机（天板の上面の高さが DESK_H）
DESK_W, DESK_D, DESK_H, DESK_T = 1.60, 0.75, 0.72, 0.025
# モニター（27 型 16:9）。画面の中心（y は画面の手前の面）。D5 で画面とキーボードが近く見えるよう、低めの台で手前寄り
SCREEN_W, SCREEN_H = 0.5977, 0.3362
SCREEN_CENTER = Vector((0.0, 0.40, 1.03))
BEZEL_SIDE, BEZEL_TOP, BEZEL_CHIN, PANEL_DEPTH = 0.004, 0.004, 0.014, 0.012
# キーボード。キーの間隔 19.05mm（2D の配列表の 31 が 1 キー分、行は 29 ずつ下がる）
PITCH = 0.01905
KB_CENTER_Y = 0.20
KB_TILT = math.radians(3.0)
KB_MARGIN = 0.012
KB_CASE_H = 0.018
KB_RIM = 0.004
KB_PLATE_Z = 0.012
CAP_H = 0.0075
CAP_GAP = 0.00125
CAP_BASE_Z = 0.0172
# 椅子（座った位置）。D1 では CHAIR_Y_D1 まで引いてある（動きは段階4）。
# 1 台のキーボードを分け合うので、2 人とも机に寄って内側に座る（腕がキーに届く位置）
CHAIR_X = 0.30
CHAIR_Y = -0.40
CHAIR_Y_D1 = -0.70

COLLECTIONS = ("TD_Room", "TD_Desk", "TD_Keyboard", "TD_Chairs", "TD_Proxy", "TD_Cameras", "TD_Lights")
# Godot のノード名に使えない文字を含むキーの名前（キーの id はカスタムプロパティ key_id に残す）
KEY_NAMES = {"←": "Left", "→": "Right", "↑": "Up", "↓": "Down", "\\": "Backslash", ";": "Semicolon",
             "'": "Quote", ",": "Comma", ".": "Period", "/": "Slash", "-": "Minus", "=": "Equal",
             "[": "BracketL", "]": "BracketR"}
LEGENDS = {"Back": "Backspace", "Caps": "Caps Lock", "ShiftL": "Shift", "ShiftR": "Shift", "CtrlL": "Ctrl",
           "CtrlR": "Ctrl", "AltL": "Alt", "AltR": "Alt", "Space": "", "Win": "Win"}
# 説明画面の配色（ローカル2P）。TutorialKeyboard.get_key_player() と同じ組み合わせ
P1_KEYS = ("W", "A", "S", "D", "Space", "1", "2", "3")
P2_KEYS = ("←", "→", "↑", "↓", "CtrlR", "8", "9", "0")

_MATS = {}
_FONT = None


# ---------- 入口 ----------

def build(stage="detail"):
    """stage = "blockout"（箱と仮の体とカメラ）か "detail"（作り込み・材質・光）。"""
    random.seed(7)
    _MATS.clear()
    colls = reset()
    setup_scene()
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    if stage == "blockout":
        made = build_blockout(colls, layout)
    else:
        made = build_detail(colls, layout)
    cams = build_cameras(colls["TD_Cameras"])
    bpy.context.scene.camera = cams["CAM_D5"]
    counts = {name: len(colls[name].all_objects) for name in COLLECTIONS}
    return {"stage": stage, "objects": counts, "made": made}


def reset():
    """TD_ のコレクションを用意し、中の物（とそのデータ）を消す。"""
    scene_root = bpy.context.scene.collection
    colls = {}
    for name in COLLECTIONS:
        coll = bpy.data.collections.get(name) or bpy.data.collections.new(name)
        if coll.name not in scene_root.children:
            scene_root.children.link(coll)
        for obj in list(coll.all_objects):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data is not None and data.users == 0:
                _remove_data(data)
        colls[name] = coll
    return colls


def _remove_data(data):
    for kind, pool in ((bpy.types.Mesh, "meshes"), (bpy.types.Curve, "curves"), (bpy.types.Camera, "cameras"),
                       (bpy.types.Light, "lights"), (bpy.types.Armature, "armatures")):
        if isinstance(data, kind):
            getattr(bpy.data, pool).remove(data)
            return


def setup_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "CYCLES"
    scene.cycles.device = "GPU"
    scene.cycles.samples = 128
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 150
    scene.view_settings.view_transform = "AgX"
    for look in ("AgX - Medium High Contrast", "Medium High Contrast"):
        try:
            scene.view_settings.look = look
            break
        except TypeError:
            continue
    scene.view_settings.exposure = 0.0
    world = scene.world or bpy.data.worlds.new("TD_World")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    # 新しいノードの名前は UI の言語に訳される（日本語では「背景」）ので、名前ではなく種類で探す
    background = world_background(world) or nt.nodes.new("ShaderNodeBackground")
    output = next((n for n in nt.nodes if n.type == "OUTPUT_WORLD"), None) or nt.nodes.new("ShaderNodeOutputWorld")
    if not output.inputs["Surface"].is_linked:
        nt.links.new(background.outputs["Background"], output.inputs["Surface"])
    background.inputs["Color"].default_value = (0.0025, 0.0035, 0.007, 1.0)
    background.inputs["Strength"].default_value = 1.0


def world_background(world):
    return next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)


# ---------- 箱だけの配置（構図の確認用） ----------

def build_blockout(colls, layout):
    room, desk_c, kb_c, chairs, proxy = (colls[n] for n in ("TD_Room", "TD_Desk", "TD_Keyboard", "TD_Chairs", "TD_Proxy"))
    gray = flat_mat("MAT_Block_Gray", (0.5, 0.5, 0.5))
    dark = flat_mat("MAT_Block_Dark", (0.08, 0.08, 0.09))
    screen = flat_mat("MAT_Block_Screen", (0.3, 0.6, 0.9))
    build_room_shell(room, gray, gray, gray)
    box("PRP_Desk_Top", (DESK_W, DESK_D, DESK_T), (0, DESK_D / 2, DESK_H - DESK_T / 2), desk_c, gray)
    for sx in (-1, 1):
        for y in (0.06, DESK_D - 0.06):
            box(f"PRP_Desk_Leg_{'L' if sx < 0 else 'R'}{'F' if y < 0.3 else 'B'}", (0.05, 0.05, DESK_H - DESK_T),
                (sx * (DESK_W / 2 - 0.06), y, (DESK_H - DESK_T) / 2), desk_c, dark)
    panel_w, panel_h = SCREEN_W + 2 * BEZEL_SIDE, SCREEN_H + BEZEL_TOP + BEZEL_CHIN
    box("PRP_Monitor", (panel_w, PANEL_DEPTH, panel_h), (0, SCREEN_CENTER.y + PANEL_DEPTH / 2, SCREEN_CENTER.z - (BEZEL_CHIN - BEZEL_TOP) / 2), desk_c, dark)
    plane("PRP_Monitor_Screen", (SCREEN_W, SCREEN_H), (0, SCREEN_CENTER.y - 0.0005, SCREEN_CENTER.z), desk_c, screen, rot=(math.pi / 2, 0, 0))
    box("PRP_Monitor_Neck", (0.05, 0.03, 0.36), (0, 0.50, DESK_H + 0.18), desk_c, dark)
    box("PRP_Monitor_Base", (0.24, 0.17, 0.008), (0, 0.48, DESK_H + 0.004), desk_c, dark)
    kb_root, keys = build_keyboard_layout_only(kb_c, layout, gray, dark)
    cylinder("PRP_DeskLamp", 0.07, 0.5, (-0.70, 0.56, DESK_H + 0.25), desk_c, dark)
    sphere("PRP_Figure_Hatena", 0.05, (0.53, 0.42, DESK_H + 0.07), desk_c, gray)
    box("PRP_Shelf", (0.70, 0.22, 0.022), (1.25, WALL_Y - 0.11, 1.62), room, gray)
    for name, x in (("PRP_Chair_P1", -CHAIR_X), ("PRP_Chair_P2", CHAIR_X)):
        box(name + "_Seat", (0.52, 0.50, 0.10), (x, CHAIR_Y, 0.44), chairs, dark)
        box(name + "_Back", (0.50, 0.10, 0.72), (x, CHAIR_Y - 0.27, 0.85), chairs, dark, rot=(math.radians(9), 0, 0))
        cylinder(name + "_Lift", 0.03, 0.40, (x, CHAIR_Y, 0.20), chairs, dark)
    build_proxies(proxy, keys)
    return {"keys": len(keys), "keyboard_root": kb_root.name}


def build_keyboard_layout_only(coll, layout, cap_mat, case_mat):
    root = keyboard_root(coll)
    w, d = keyboard_size(layout)
    case = box("HERO_Keyboard_Case", (w, d, KB_CASE_H), (0, d / 2, KB_CASE_H / 2), coll, case_mat, parent=root)
    keys = {}
    for spec in layout["keys"]:
        x, y, units, _row = key_local(spec, layout, d)
        cap = box(key_name("KEY_", spec["id"]), (units * PITCH - CAP_GAP, PITCH - CAP_GAP, CAP_H),
                  (x, y, CAP_BASE_Z + CAP_H / 2), coll, cap_mat, parent=root)
        cap["key_id"] = spec["id"]
        keys[spec["id"]] = cap
    return root, keys


# ---------- 作り込み ----------

def build_detail(colls, layout):
    room, desk_c, kb_c, chairs, proxy, lights = (colls[n] for n in ("TD_Room", "TD_Desk", "TD_Keyboard", "TD_Chairs", "TD_Proxy", "TD_Lights"))
    build_room_shell(room, mat_oak_floor(), mat_wall_paint(), mat_ceiling())
    build_baseboards(room)
    build_desk(desk_c)
    build_monitor(desk_c)
    root, keys = build_keyboard(kb_c, layout)
    build_keyboard_cable(desk_c)
    build_lamp(desk_c, lights)
    figure = build_figure(desk_c)
    build_shelf(room)
    for name, x in (("PRP_Chair_P1", -CHAIR_X), ("PRP_Chair_P2", CHAIR_X)):
        build_chair(chairs, name, x, CHAIR_Y)
    build_proxies(proxy, keys)
    build_lights(lights)
    return {"keys": len(keys), "keyboard_root": root.name, "figure": figure}


def build_room_shell(coll, floor_mat, wall_mat, ceiling_mat):
    depth = WALL_Y - ROOM_FRONT_Y
    mid_y = (WALL_Y + ROOM_FRONT_Y) / 2
    box("ENV_Floor", (ROOM_W, depth, 0.02), (0, mid_y, -0.01), coll, floor_mat)
    t = 0.1
    box("ENV_Wall_Back", (ROOM_W + 2 * t, t, ROOM_H), (0, WALL_Y + t / 2, ROOM_H / 2), coll, wall_mat)
    box("ENV_Wall_Front", (ROOM_W + 2 * t, t, ROOM_H), (0, ROOM_FRONT_Y - t / 2, ROOM_H / 2), coll, wall_mat)
    box("ENV_Wall_Left", (t, depth, ROOM_H), (-ROOM_W / 2 - t / 2, mid_y, ROOM_H / 2), coll, wall_mat)
    box("ENV_Wall_Right", (t, depth, ROOM_H), (ROOM_W / 2 + t / 2, mid_y, ROOM_H / 2), coll, wall_mat)
    box("ENV_Ceiling", (ROOM_W + 2 * t, depth + 2 * t, t), (0, mid_y, ROOM_H + t / 2), coll, ceiling_mat)


def build_baseboards(coll):
    paint = mat_principled("MAT_Baseboard", (0.016, 0.024, 0.05), 0.45)
    depth = WALL_Y - ROOM_FRONT_Y
    mid_y = (WALL_Y + ROOM_FRONT_Y) / 2
    h, t = 0.08, 0.012
    box("ENV_Baseboard_Back", (ROOM_W, t, h), (0, WALL_Y - t / 2, h / 2), coll, paint, bevel=0.002)
    box("ENV_Baseboard_Left", (t, depth, h), (-ROOM_W / 2 + t / 2, mid_y, h / 2), coll, paint, bevel=0.002)
    box("ENV_Baseboard_Right", (t, depth, h), (ROOM_W / 2 - t / 2, mid_y, h / 2), coll, paint, bevel=0.002)


def build_desk(coll):
    walnut = mat_walnut()
    steel = mat_black_steel()
    top = box("PRP_Desk_Top", (DESK_W, DESK_D, DESK_T), (0, DESK_D / 2, DESK_H - DESK_T / 2), coll, walnut, bevel=0.003)
    leg_h = DESK_H - DESK_T
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        x = sx * (DESK_W / 2 - 0.07)
        for y, tag in ((0.07, "F"), (DESK_D - 0.07, "B")):
            box(f"PRP_Desk_Leg_{side}{tag}", (0.05, 0.05, leg_h), (x, y, leg_h / 2), coll, steel, bevel=0.003, parent=top)
        box(f"PRP_Desk_Rail_{side}", (0.03, DESK_D - 0.19, 0.05), (x, DESK_D / 2, leg_h - 0.03), coll, steel, bevel=0.002, parent=top)
    box("PRP_Desk_Rail_Back", (DESK_W - 0.19, 0.03, 0.06), (0, DESK_D - 0.07, leg_h - 0.035), coll, steel, bevel=0.002, parent=top)
    # 子は天板の原点からの位置に直す（box は世界の位置で置くので、親の位置を引く）
    for child in top.children:
        child.location -= top.location
    return top


def build_monitor(coll):
    plastic = mat_principled("MAT_MonitorPlastic", (0.012, 0.012, 0.013), 0.42)
    back_mat = mat_principled("MAT_MonitorBack", (0.02, 0.02, 0.022), 0.55)
    panel_w, panel_h = SCREEN_W + 2 * BEZEL_SIDE, SCREEN_H + BEZEL_TOP + BEZEL_CHIN
    center_z = SCREEN_CENTER.z - (BEZEL_CHIN - BEZEL_TOP) / 2
    front_y = SCREEN_CENTER.y + 0.0005
    root = empty("PRP_Monitor", (0, front_y, center_z), coll, 0.15)
    # 板は XY 平面で作り、+Z（手前）を -Y へ向ける（rot x = 90°）。手前の面がローカルの z = 0。
    panel = loft("PRP_Monitor_Panel", [(panel_w, panel_h, 0.006, -PANEL_DEPTH), (panel_w, panel_h, 0.006, -0.0008),
                                        (panel_w - 0.0012, panel_h - 0.0012, 0.0055, 0.0)], coll, plastic, parent=root)
    panel.rotation_euler = (math.pi / 2, 0, 0)
    housing = loft("PRP_Monitor_Housing", [(0.40, 0.25, 0.03, -PANEL_DEPTH - 0.034), (0.43, 0.27, 0.035, -PANEL_DEPTH)],
                   coll, back_mat, parent=root, cap_top=False)
    housing.rotation_euler = (math.pi / 2, 0, 0)
    housing.location = (0, 0, 0.01)
    screen = plane("PRP_Monitor_Screen", (SCREEN_W, SCREEN_H), (0, -0.0003, SCREEN_CENTER.z - center_z), coll, mat_screen(),
                   rot=(math.pi / 2, 0, 0), parent=root)
    led = box("PRP_Monitor_BiasLED", (0.36, 0.006, 0.008), (0, PANEL_DEPTH + 0.036, 0.11), coll, mat_emission("MAT_BiasLED", (0.12, 0.35, 1.0), 25.0), parent=root)
    neck_top = center_z + 0.01
    neck_h = neck_top - DESK_H - 0.01
    box("PRP_Monitor_Neck", (0.052, 0.026, neck_h), (0, PANEL_DEPTH + 0.046, (DESK_H + 0.01 + neck_top) / 2 - center_z), coll, back_mat, bevel=0.006, parent=root)
    base = loft("PRP_Monitor_Base", [(0.25, 0.18, 0.06, 0.0), (0.25, 0.18, 0.06, 0.006), (0.246, 0.176, 0.058, 0.008)], coll, back_mat)
    base.location = (0, front_y + 0.045, DESK_H)
    return {"panel": panel.name, "screen": screen.name, "led": led.name}


def build_keyboard(coll, layout):
    case_mat = mat_aluminium()
    cap_mat = mat_keycap()
    root = keyboard_root(coll)
    w, d = keyboard_size(layout)
    inner_w, inner_d = w - 2 * KB_RIM, d - 2 * KB_RIM
    case = loft("HERO_Keyboard_Case", [
        (w, d, 0.006, 0.0), (w, d, 0.006, KB_CASE_H - 0.001), (w - 0.0014, d - 0.0014, 0.0053, KB_CASE_H),
        (inner_w, inner_d, 0.003, KB_CASE_H), (inner_w, inner_d, 0.003, KB_PLATE_Z)], coll, case_mat, parent=root)
    # 断面は中心で作るので、手前の縁が原点（キーの並びの基準）に来るよう奥へずらす
    case.location = (0, d / 2, 0)
    for sx in (-1, 1):
        box(f"HERO_Keyboard_Foot_{'L' if sx < 0 else 'R'}", (0.04, 0.012, 0.007),
            (sx * (w / 2 - 0.04), d - 0.012, -0.0035), coll, mat_principled("MAT_RubberFoot", (0.01, 0.01, 0.01), 0.8), parent=root)
    # 強すぎる発光は AgX で白に寄るので、色が残る強さにとどめる
    glow = {1: mat_emission("MAT_Glow_P1", (1.0, 0.33, 0.04), 4.0), 2: mat_emission("MAT_Glow_P2", (0.12, 0.6, 1.0), 4.0),
            0: mat_emission("MAT_Glow_Idle", (0.75, 0.82, 1.0), 0.6)}
    legend_mats = {1: mat_legend("MAT_Legend_P1", (1.0, 0.38, 0.05), 5.0), 2: mat_legend("MAT_Legend_P2", (0.15, 0.65, 1.0), 5.0),
                   0: mat_legend("MAT_Legend_Idle", (0.8, 0.85, 1.0), 1.6)}
    keys = {}
    for spec in layout["keys"]:
        key_id = spec["id"]
        player = 1 if key_id in P1_KEYS else 2 if key_id in P2_KEYS else 0
        x, y, units, row = key_local(spec, layout, d)
        cap_w, cap_d = units * PITCH - CAP_GAP, PITCH - CAP_GAP
        inset = 0.0028
        cap = loft(key_name("KEY_", key_id), [
            (cap_w, cap_d, 0.0012, 0.0), (cap_w - 0.0006, cap_d - 0.0006, 0.0013, 0.0016),
            (cap_w - 2 * inset + 0.0006, cap_d - 2 * inset + 0.0006, 0.0022, CAP_H - 0.0006),
            (cap_w - 2 * inset, cap_d - 2 * inset, 0.0018, CAP_H)], coll, cap_mat, parent=root)
        cap.location = (x, y, CAP_BASE_Z)
        cap["key_id"] = key_id
        cap["player"] = player
        cap["row"] = row
        keys[key_id] = cap
        plate = plane(key_name("GLOW_", key_id), (cap_w + 0.0042, cap_d + 0.0042), (x, y, KB_PLATE_Z + 0.0002), coll, glow[player], parent=root)
        plate["key_id"] = key_id
        text = LEGENDS.get(key_id, spec["label"])
        if text:
            # Noto Sans JP は同じ指定でも英字が小さく出る（字の高さが指定の約 0.26 倍）ので、その分だけ大きく指定する
            size = (0.0095 if key_id in P2_KEYS[:4] else 0.0128) if len(text) == 1 else 0.0072
            leg = legend(key_name("LEG_", key_id), text, size, coll, legend_mats[player], cap, (0, 0, CAP_H + 0.00002))
            leg["key_id"] = key_id
    # 矢印の上の空き（数字〜上の段の右端）に、音量のつまみと小さな表示灯
    knob_x = keys["↓"].location.x
    knob_y = d / 2 + (2 - 0.55) * PITCH
    cylinder("HERO_Keyboard_KnobBase", 0.0115, 0.002, (knob_x, knob_y, KB_CASE_H + 0.001), coll, mat_principled("MAT_KnobRing", (0.01, 0.01, 0.01), 0.6), parent=root)
    cylinder("HERO_Keyboard_Knob", 0.0095, 0.012, (knob_x, knob_y, KB_CASE_H + 0.008), coll, mat_knob(), segments=48, parent=root)
    for i in range(3):
        box(f"HERO_Keyboard_Indicator_{i}", (0.0022, 0.0012, 0.0004), (knob_x - 0.006 + i * 0.006, knob_y - 0.022, KB_CASE_H + 0.0002),
            coll, mat_emission("MAT_Indicator", (0.7, 0.85, 1.0), 2.0), parent=root)
    return root, keys


def build_keyboard_cable(coll):
    rubber = mat_principled("MAT_Cable", (0.008, 0.008, 0.009), 0.55)
    points = [(0.0, KB_CENTER_Y + 0.062, DESK_H + 0.012), (0.01, 0.30, DESK_H + 0.003), (0.06, 0.44, DESK_H + 0.003),
              (0.10, 0.60, DESK_H + 0.003), (0.11, DESK_D - 0.01, DESK_H + 0.002), (0.11, DESK_D + 0.02, DESK_H - 0.08),
              (0.10, DESK_D + 0.03, 0.30)]
    curve = bpy.data.curves.new("PRP_KeyboardCable", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.0018
    curve.bevel_resolution = 3
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1.0)
    spline.use_endpoint_u = True
    spline.order_u = 4
    curve.materials.append(rubber)
    obj = bpy.data.objects.new("PRP_KeyboardCable", curve)
    coll.objects.link(obj)
    return obj


def build_lamp(coll, lights):
    steel = mat_black_steel()
    inner = mat_principled("MAT_LampInner", (0.45, 0.43, 0.40), 0.5)
    base_c = Vector((-0.70, 0.56, DESK_H))
    pivot = base_c + Vector((0, 0, 0.04))
    elbow = Vector((-0.66, 0.66, 1.15))
    head = Vector((-0.47, 0.50, 1.22))
    # 光の輪はキーボードの左半分と、その左の机に落とす（D5 で 2 人の頭のあいだから見える所）
    target = Vector((-0.10, 0.28, DESK_H))
    root = empty("PRP_DeskLamp", base_c, coll, 0.1)
    parts = [
        cylinder("PRP_DeskLamp_Base", 0.07, 0.022, base_c + Vector((0, 0, 0.011)), coll, steel, segments=48),
        cylinder("PRP_DeskLamp_Pivot", 0.012, 0.03, pivot, coll, steel),
        rod("PRP_DeskLamp_ArmLower", pivot, elbow, 0.0055, coll, steel),
        sphere("PRP_DeskLamp_Elbow", 0.011, elbow, coll, steel),
        rod("PRP_DeskLamp_ArmUpper", elbow, head, 0.0055, coll, steel),
        sphere("PRP_DeskLamp_HeadJoint", 0.011, head, coll, steel),
    ]
    axis = (target - head).normalized()
    shade_back = head + axis * 0.02
    shade = cone_between("PRP_DeskLamp_Shade", shade_back, shade_back + axis * 0.14, 0.03, 0.075, coll, steel)
    shade.data.materials.append(inner)
    # 筒の内側の面（ローカルの軸へ向く面）に内側の材質を当てる
    for poly in shade.data.polygons:
        radial = Vector((poly.center.x, poly.center.y, 0.0))
        poly.material_index = 1 if radial.dot(poly.normal) < 0 else 0
    bulb_c = head + axis * 0.07
    bulb = sphere("PRP_DeskLamp_Bulb", 0.022, bulb_c, coll, mat_emission("MAT_LampBulb", (1.0, 0.72, 0.45), 40.0))
    # 光る電球の面がスポットライトの光をふさがないように（影を落とさない）
    bulb.visible_shadow = False
    parts += [shade, bulb]
    adopt(root, parts)
    lamp = light("LGT_key_lamp", "SPOT", bulb_c + axis * 0.03, lights, 90.0, kelvin(3000), target=target,
                 spot_size=math.radians(120), spot_blend=0.6, shadow_soft_size=0.018)
    lamp["purpose"] = "structural key: warm pool on the desk's left half and the keyboard"
    return root


def build_figure(coll):
    """ゲームのハテナ（mascot_model.glb）を 12cm の置物にする。読み込めなければ球で代わりを置く。"""
    root = empty("PRP_Figure_Hatena", (0.53, 0.42, DESK_H), coll, 0.05)
    root.rotation_euler = (0, 0, math.radians(-25))
    if not MASCOT_GLB.exists():
        sphere("PRP_Figure_Hatena_Stand", 0.05, (0.53, 0.42, DESK_H + 0.06), coll, mat_vinyl("MAT_Vinyl_White", (0.85, 0.85, 0.82)))
        return "missing"
    # 前に読み込んだ材質が残っていると、名前に .001 が付いて増えていくので、使われていないものを先に消す
    for mat in list(bpy.data.materials):
        if mat.name.startswith("Hatena_") and mat.users == 0:
            bpy.data.materials.remove(mat)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(MASCOT_GLB))
    imported = [o for o in bpy.data.objects if o not in before]
    # glb に紛れている材質のない形（ICO球）は、ハテナの体を隠すので外す
    for obj in [o for o in imported if o.type == "MESH" and not o.material_slots]:
        imported.remove(obj)
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        _remove_data(data)
    for obj in imported:
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        coll.objects.link(obj)
        if obj.type == "MESH":
            obj.name = "PRP_Figure_Hatena_Body"
        elif obj.type == "ARMATURE":
            obj.name = "PRP_Figure_Hatena_Rig"
    tops = [o for o in imported if o.parent is None]
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in imported if o.type == "MESH" for c in o.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    scale = 0.12 / max(hi.z - lo.z, 1e-6)
    offset = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for obj in tops:
        obj.parent = root
        obj.location = (obj.location - offset) * scale
        obj.scale = obj.scale * scale
    for obj in imported:
        if obj.type == "MESH":
            for slot in obj.material_slots:
                vinylize(slot.material)
    return {"imported": len(imported), "source_height": round(hi.z - lo.z, 4)}


def build_shelf(coll):
    walnut = mat_walnut()
    steel = mat_black_steel()
    shelf = box("PRP_Shelf", (0.70, 0.22, 0.022), (1.25, WALL_Y - 0.11, 1.62), coll, walnut, bevel=0.002)
    for x in (1.02, 1.48):
        box(f"PRP_Shelf_Bracket_{'L' if x < 1.2 else 'R'}", (0.012, 0.16, 0.05), (x, WALL_Y - 0.08, 1.585), coll, steel)
    colors = [(0.08, 0.06, 0.05), (0.12, 0.04, 0.03), (0.05, 0.07, 0.1), (0.15, 0.13, 0.1), (0.06, 0.08, 0.06), (0.2, 0.17, 0.12), (0.04, 0.04, 0.05)]
    x = 1.36
    for i, color in enumerate(colors):
        t = random.uniform(0.022, 0.04)
        h = random.uniform(0.19, 0.26)
        box(f"PRP_Book_{i}", (t, 0.16, h), (x + t / 2, WALL_Y - 0.12, 1.631 + h / 2), coll, mat_principled(f"MAT_Book_{i}", color, 0.7), bevel=0.0015)
        x += t + 0.002
    pot = cylinder("PRP_Plant_Pot", 0.06, 0.09, (1.06, WALL_Y - 0.11, 1.631 + 0.045), coll, mat_principled("MAT_Pot", (0.18, 0.06, 0.035), 0.8), radius2=0.05)
    leaf = mat_leaf()
    for i in range(36):
        hang = i >= 18
        a = random.uniform(0, math.tau)
        r = random.uniform(0.02, 0.09)
        z = (1.64 - random.uniform(0.02, 0.38)) if hang else (1.72 + random.uniform(0.0, 0.10))
        y = WALL_Y - 0.11 + (random.uniform(-0.12, -0.02) if hang else math.sin(a) * r)
        loc = (1.06 + math.cos(a) * r * (0.6 if hang else 1.0), y, z)
        ob = sphere(f"PRP_Plant_Leaf_{i:02d}", 1.0, loc, coll, leaf, segments=10, rings=6)
        ob.scale = (0.03, 0.013, 0.005)
        ob.rotation_euler = (random.uniform(-0.6, 0.6), random.uniform(-0.6, 0.6), a)
    return shelf.name


def build_chair(coll, name, x, y):
    """ゲーミングチェア。原点は昇降の柱の下の床。座面は +Y（机）を向く。"""
    leather = mat_leather()
    plastic = mat_principled("MAT_ChairPlastic", (0.012, 0.012, 0.013), 0.5)
    chrome = mat_metal("MAT_Chrome", (0.75, 0.75, 0.76), 0.12)
    hole = mat_principled("MAT_ChairHole", (0.002, 0.002, 0.002), 0.9)
    root = empty(name, (x, y, 0), coll, 0.25)

    def part(fn, part_name, *args, **kw):
        ob = fn(f"{name}_{part_name}", *args, coll, **kw)
        ob.parent = root
        return ob

    part(cylinder_local, "Hub", 0.045, 0.07, (0, 0, 0.11), plastic)
    for i in range(5):
        a = math.radians(90 + i * 72)
        arm = part(box_local, f"BaseArm{i}", (0.29, 0.05, 0.032), (math.cos(a) * 0.17, math.sin(a) * 0.17, 0.095), plastic, bevel=0.008)
        arm.rotation_euler = (0, math.radians(4), a)
        cx, cy = math.cos(a) * 0.31, math.sin(a) * 0.31
        part(box_local, f"CasterFork{i}", (0.03, 0.045, 0.03), (cx, cy, 0.068), plastic, bevel=0.006)
        for side in (-1, 1):
            wheel = part(cylinder_local, f"Caster{i}_{'A' if side < 0 else 'B'}", 0.027, 0.018,
                         (cx + math.cos(a + math.pi / 2) * side * 0.011, cy + math.sin(a + math.pi / 2) * side * 0.011, 0.027), plastic)
            wheel.rotation_euler = (math.pi / 2, 0, a + math.pi / 2)
    part(cylinder_local, "LiftSleeve", 0.032, 0.17, (0, 0, 0.22), plastic, radius2=0.026)
    part(cylinder_local, "LiftPiston", 0.014, 0.12, (0, 0, 0.34), chrome)
    part(box_local, "Mechanism", (0.24, 0.26, 0.05), (0, 0, 0.40), plastic, bevel=0.008)
    part(box_local, "Seat", (0.50, 0.50, 0.085), (0, 0.02, 0.44), leather, bevel=0.035)
    for side in (-1, 1):
        bolster = part(box_local, f"SeatBolster{'L' if side < 0 else 'R'}", (0.075, 0.44, 0.05), (side * 0.215, 0.02, 0.485), leather, bevel=0.024)
        bolster.rotation_euler = (0, side * 0.28, 0)
    back = empty(f"{name}_BackPivot", (0, -0.24, 0.47), coll, 0.05)
    back.parent = root
    back.location = (0, -0.24, 0.47)
    back.rotation_euler = (math.radians(9), 0, 0)

    def back_part(fn, part_name, *args, **kw):
        ob = fn(f"{name}_{part_name}", *args, coll, **kw)
        ob.parent = back
        return ob

    # 背もたれの上端は床から約 1.2m（座った人の頭が上に出る高さ）
    back_part(box_local, "Back", (0.44, 0.10, 0.68), (0, 0, 0.40), leather, bevel=0.042)
    back_part(box_local, "BackShell", (0.42, 0.03, 0.62), (0, -0.055, 0.39), plastic, bevel=0.02)
    for side in (-1, 1):
        tag = "L" if side < 0 else "R"
        wing = back_part(box_local, f"Wing{tag}", (0.08, 0.13, 0.42), (side * 0.235, 0.03, 0.32), leather, bevel=0.035)
        wing.rotation_euler = (0, 0, side * -0.35)
        shoulder = back_part(box_local, f"Shoulder{tag}", (0.09, 0.115, 0.20), (side * 0.235, 0.015, 0.60), leather, bevel=0.035)
        shoulder.rotation_euler = (0, side * 0.12, side * -0.2)
        back_part(box_local, f"StrapHole{tag}", (0.062, 0.122, 0.03), (side * 0.11, 0.0, 0.62), hole, bevel=0.012)
        post = part(box_local, f"ArmPost{tag}", (0.04, 0.07, 0.20), (side * 0.285, -0.02, 0.53), plastic, bevel=0.008)
        part(box_local, f"ArmBracket{tag}", (0.12, 0.05, 0.02), (side * 0.205, -0.02, 0.41), plastic, bevel=0.005)
        part(box_local, f"ArmPad{tag}", (0.09, 0.26, 0.032), (side * 0.285, 0.0, 0.645), leather, bevel=0.013)
    back_part(box_local, "Headrest", (0.25, 0.08, 0.11), (0, 0.075, 0.66), leather, bevel=0.035)
    return root


def build_proxies(coll, keys):
    """人の仮の体（段階3で差し替える）。座って、手をキーボードに置いた姿。"""
    orange = mat_principled("MAT_Proxy_P1", (0.8, 0.22, 0.03), 0.8)
    blue = mat_principled("MAT_Proxy_P2", (0.25, 0.48, 0.8), 0.8)
    skin = mat_principled("MAT_Proxy_Skin", (0.55, 0.36, 0.27), 0.6)
    cap = mat_principled("MAT_Proxy_Cap", (0.05, 0.05, 0.055), 0.7)
    bpy.context.view_layer.update()

    def key_world(key_id, dy=0.0):
        cap_obj = keys[key_id]
        return cap_obj.matrix_world @ Vector((0, 0, 0.02)) + Vector((0, dy, 0))

    # 1 台のキーボードを分け合うので、2 人とも真ん中へ少し寄って前かがみになる
    for tag, px, mat in (("P1", -0.31, orange), ("P2", 0.31, blue)):
        hip = Vector((px, CHAIR_Y + 0.06, 0.53))
        chest = Vector((px * 0.85, CHAIR_Y + 0.20, 1.02))
        head = Vector((px * 0.76, CHAIR_Y + 0.24, 1.22))
        capsule(f"PROXY_{tag}_Torso", hip, chest, 0.16, coll, mat)
        sphere(f"PROXY_{tag}_Head", 0.10, head, coll, skin)
        if tag == "P1":
            dome = sphere("PROXY_P1_Cap", 0.106, head + Vector((0, 0, 0.012)), coll, cap)
            dome.scale = (1.0, 1.0, 0.85)
            box("PROXY_P1_CapBrim", (0.17, 0.09, 0.012), tuple(head + Vector((0, 0.11, 0.035))), coll, cap)
        else:
            hood = sphere("PROXY_P2_Hood", 0.128, head + Vector((0, -0.02, 0.015)), coll, mat)
            hood.scale = (1.0, 1.05, 1.08)
        for knee_side in (-1, 1):
            knee = Vector((px + knee_side * 0.1, CHAIR_Y + 0.46, 0.53))
            capsule(f"PROXY_{tag}_Thigh{knee_side:+d}", hip + Vector((knee_side * 0.1, 0, 0)), knee, 0.075, coll, mat)
            capsule(f"PROXY_{tag}_Shin{knee_side:+d}", knee, Vector((knee.x, knee.y + 0.04, 0.06)), 0.055, coll, mat)
        shoulders = {s: chest + Vector((s * 0.19, 0.0, 0.03)) for s in (-1, 1)}
        if tag == "P1":
            hands = {-1: key_world("S", -0.035), 1: Vector((px + 0.08, CHAIR_Y + 0.35, 0.60))}
        else:
            hands = {1: key_world("↓", -0.035), -1: key_world("9", -0.03)}
        for s in (-1, 1):
            hand = hands[s]
            # 肘は肩の下・少し前・少し外（腕が上からキーボードにかぶさらないように）
            elbow = shoulders[s] + Vector((s * 0.05, 0.16, -0.25))
            capsule(f"PROXY_{tag}_UpperArm{s:+d}", shoulders[s], elbow, 0.05, coll, mat)
            capsule(f"PROXY_{tag}_Forearm{s:+d}", elbow, hand, 0.04, coll, mat)
            hand_ob = sphere(f"PROXY_{tag}_Hand{s:+d}", 0.045, hand, coll, skin)
            hand_ob.scale = (0.9, 1.15, 0.45)


def build_lights(coll):
    screen = light("LGT_practical_screen", "AREA", SCREEN_CENTER + Vector((0, -0.01, 0)), coll, 7.0, (0.9, 0.95, 1.0),
                   rot=(-math.pi / 2, 0, 0), shape="RECTANGLE", size=SCREEN_W, size_y=SCREEN_H)
    screen["purpose"] = "monitor light: cool rim on the players, front fill on the keyboard"
    bias = light("LGT_practical_bias", "AREA", Vector((0, SCREEN_CENTER.y + 0.07, SCREEN_CENTER.z + 0.06)), coll, 6.0, (0.12, 0.38, 1.0),
                 rot=(math.pi / 2, 0, 0), shape="RECTANGLE", size=0.42, size_y=0.18)
    bias["purpose"] = "bias LED halo on the back wall"
    room = light("LGT_fill_room", "AREA", Vector((0.0, -1.6, ROOM_H - 0.05)), coll, 15.0, (0.55, 0.65, 1.0),
                 rot=(0, 0, 0), shape="RECTANGLE", size=1.6, size_y=1.6)
    room["purpose"] = "very weak night ambience so the floor and chair backs keep form"
    return [screen.name, bias.name, room.name]


def build_cameras(coll):
    focus = empty("EMP_Focus_Keyboard", (0, KB_CENTER_Y, DESK_H + 0.025), coll, 0.02)
    screen_c = SCREEN_CENTER
    # D5 は説明画面の基準の構図：2 人の頭のすぐ上・少し後ろから、50mm でキーボードを見下ろす（頭と肩は左右の端に入る）
    cams = {
        "CAM_D1": camera("CAM_D1", 30, (0, -3.1, 1.72), (0, 0.15, 0.82), coll),
        "CAM_D2": camera("CAM_D2", 35, (0, -2.6, 1.62), (0, 0.18, 0.84), coll),
        "CAM_D3": camera("CAM_D3", 40, (0, -1.65, 1.58), (0, 0.25, 0.88), coll),
        "CAM_D5": camera("CAM_D5", 45, (0, -0.98, 1.74), (0, 0.27, 0.82), coll, focus=focus, fstop=4.0),
        "CAM_D7": camera("CAM_D7", 40, (0, -0.45, 1.36), tuple(screen_c), coll),
        "CAM_D8": camera("CAM_D8", 35, (0, screen_c.y - 0.42, screen_c.z), tuple(screen_c), coll),
        # 作り込みの確認用（絵コンテのコマではない）
        "CAM_CheckKeyboard": camera("CAM_CheckKeyboard", 50, (0, KB_CENTER_Y - 0.48, 1.05), (0, KB_CENTER_Y + 0.01, DESK_H + 0.02), coll),
        "CAM_CheckFigure": camera("CAM_CheckFigure", 60, (0.33, 0.02, 0.92), (0.53, 0.42, DESK_H + 0.06), coll),
    }
    return cams


# ---------- キーボードの寸法 ----------

def keyboard_size(layout):
    w = (layout["right"] - layout["left"]) / layout["pitch"] * PITCH + 2 * KB_MARGIN
    d = 5 * PITCH + 2 * KB_MARGIN
    return w, d


def key_local(spec, layout, case_d):
    units = (spec["w"] + 3.0) / layout["pitch"]
    center_px = (layout["left"] + layout["right"]) * 0.5
    row = int(round((spec["y"] - layout["row_top"]) / layout["row_step"]))
    x = (spec["x"] + spec["w"] * 0.5 - center_px) / layout["pitch"] * PITCH
    y = case_d * 0.5 + (2 - row) * PITCH
    return x, y, units, row


def keyboard_root(coll):
    """キーボードの原点は手前の下の縁の真ん中。奥を上げて傾ける。"""
    _w, d = 0.0, 5 * PITCH + 2 * KB_MARGIN
    root = empty("HERO_Keyboard", (0, KB_CENTER_Y - d / 2, DESK_H), coll, 0.05)
    root.rotation_euler = (KB_TILT, 0, 0)
    return root


def key_name(prefix, key_id):
    return prefix + KEY_NAMES.get(key_id, key_id)


# ---------- 形の部品 ----------

def link(obj, coll, parent=None):
    coll.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def mesh_object(name, bm, coll, mat=None, parent=None, smooth=True):
    if smooth:
        for face in bm.faces:
            face.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if mat is not None:
        me.materials.append(mat)
    return link(bpy.data.objects.new(name, me), coll, parent)


def add_bevel(obj, width, segments=3):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.harden_normals = True
    return mod


def box(name, size, loc, coll, mat, bevel=0.0, segments=3, parent=None, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    obj = mesh_object(name, bm, coll, mat, parent, smooth=bevel > 0)
    obj.location = loc
    obj.rotation_euler = rot
    if bevel > 0:
        add_bevel(obj, bevel, segments)
    return obj


def box_local(name, size, loc, mat, coll, bevel=0.0, segments=3):
    return box(name, size, loc, coll, mat, bevel=bevel, segments=segments)


def cylinder(name, radius, depth, loc, coll, mat, segments=32, rot=(0, 0, 0), parent=None, radius2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    for face in bm.faces:
        face.smooth = abs(face.normal.z) < 0.99
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if mat is not None:
        me.materials.append(mat)
    obj = link(bpy.data.objects.new(name, me), coll, parent)
    obj.location = loc
    obj.rotation_euler = rot
    return obj


def adopt(root, children):
    """世界の位置で作った物を、その位置のまま root の子にする。"""
    bpy.context.view_layer.update()
    inverse = root.matrix_world.inverted()
    for child in children:
        child.parent = root
        child.matrix_parent_inverse = inverse


def cylinder_local(name, radius, depth, loc, mat, coll, radius2=None, segments=32):
    return cylinder(name, radius, depth, loc, coll, mat, segments=segments, radius2=radius2)


def sphere(name, radius, loc, coll, mat, segments=32, rings=16, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    obj = mesh_object(name, bm, coll, mat, parent, smooth=True)
    obj.location = loc
    return obj


def plane(name, size, loc, coll, mat, rot=(0, 0, 0), parent=None):
    bm = bmesh.new()
    # calc_uvs は UV の層が先にないと何も書かない（画面の絵が 1 色になる）
    bm.loops.layers.uv.new("UVMap")
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5, calc_uvs=True)
    bmesh.ops.scale(bm, vec=Vector((size[0], size[1], 1.0)), verts=bm.verts)
    obj = mesh_object(name, bm, coll, mat, parent, smooth=False)
    obj.location = loc
    obj.rotation_euler = rot
    return obj


def rounded_ring(w, d, r, z, steps=6):
    r = max(min(r, w / 2 - 1e-5, d / 2 - 1e-5), 0.0002)
    pts = []
    for cx, cy, start in ((w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180), (w / 2 - r, -d / 2 + r, 270)):
        for i in range(steps + 1):
            a = math.radians(start + i * 90 / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
    return pts


def loft(name, profiles, coll, mat, parent=None, cap_top=True, cap_bottom=True, steps=6):
    """角を丸めた四角の断面（幅, 奥行き, 角の半径, 高さ）を下から順につないだ形。"""
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in rounded_ring(w, d, r, z, steps)] for (w, d, r, z) in profiles]
    n = len(rings[0])
    for lower, upper in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    if cap_bottom:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for face in bm.faces:
        face.smooth = abs(face.normal.z) < 0.98
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if mat is not None:
        me.materials.append(mat)
    return link(bpy.data.objects.new(name, me), coll, parent)


def rod(name, p0, p1, radius, coll, mat):
    """2 点を結ぶ丸棒（世界の座標で置く）。"""
    p0, p1 = Vector(p0), Vector(p1)
    obj = cylinder(name, radius, (p1 - p0).length, (p0 + p1) / 2, coll, mat, segments=16)
    obj.rotation_euler = (p1 - p0).to_track_quat("Z", "Y").to_euler()
    return obj


def cone_between(name, p0, p1, r0, r1, coll, mat):
    """p0（半径 r0）から p1（半径 r1）へ開く、口の開いた筒（両側の面を持つ。世界の座標で置く）。"""
    p0, p1 = Vector(p0), Vector(p1)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, cap_tris=False, segments=40, radius1=r0, radius2=r1, depth=(p1 - p0).length)
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.0012)
    for face in bm.faces:
        face.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = link(bpy.data.objects.new(name, me), coll)
    obj.location = (p0 + p1) / 2
    obj.rotation_euler = (p1 - p0).to_track_quat("Z", "Y").to_euler()
    return obj


def capsule(name, p0, p1, radius, coll, mat):
    p0, p1 = Vector(p0), Vector(p1)
    obj = cylinder(name, radius, max((p1 - p0).length, 0.001), (p0 + p1) / 2, coll, mat, segments=20)
    obj.rotation_euler = (p1 - p0).to_track_quat("Z", "Y").to_euler()
    for i, point in enumerate((p0, p1)):
        sphere(f"{name}_End{i}", radius, point, coll, mat, segments=20, rings=10)
    return obj


def empty(name, loc, coll, size=0.1):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = size
    obj.location = loc
    return link(obj, coll)


def legend(name, text, size, coll, mat, parent, loc):
    global _FONT
    if _FONT is None:
        _FONT = bpy.data.fonts.load(str(FONT_PATH), check_existing=True)
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = text
    cu.font = _FONT
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = 0.00008
    cu.materials.append(mat)
    obj = link(bpy.data.objects.new(name, cu), coll, parent)
    obj.location = loc
    return obj


def camera(name, lens, loc, target, coll, focus=None, fstop=None):
    cam = bpy.data.cameras.new(name)
    cam.lens = lens
    cam.sensor_width = 36.0
    cam.sensor_fit = "HORIZONTAL"
    cam.clip_start = 0.02
    cam.clip_end = 60.0
    obj = link(bpy.data.objects.new(name, cam), coll)
    obj.location = loc
    obj.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    if focus is not None:
        cam.dof.use_dof = True
        cam.dof.focus_object = focus
        cam.dof.aperture_fstop = fstop or 2.8
    return obj


def light(name, kind, loc, coll, energy, color, rot=None, target=None, **props):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color[:3]
    for key, value in props.items():
        setattr(data, key, value)
    obj = link(bpy.data.objects.new(name, data), coll)
    obj.location = loc
    if target is not None:
        obj.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    elif rot is not None:
        obj.rotation_euler = rot
    return obj


def kelvin(k):
    """色温度のおおよその RGB（線形）。"""
    table = {2700: (1.0, 0.62, 0.32), 3000: (1.0, 0.68, 0.40), 4000: (1.0, 0.80, 0.62), 6500: (0.95, 0.97, 1.0)}
    return table.get(k, (1.0, 1.0, 1.0))


# ---------- 材質 ----------

def _material(name):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (700, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (400, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    _MATS[name] = mat
    return mat, nt, bsdf


def flat_mat(name, color):
    mat, _nt, bsdf = _material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.8
    mat.diffuse_color = (*color, 1.0)
    return mat


def mat_principled(name, color, roughness, metallic=0.0):
    if name in _MATS:
        return _MATS[name]
    mat, _nt, bsdf = _material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (*color, 1.0)
    return mat


def mat_metal(name, color, roughness):
    return mat_principled(name, color, roughness, 1.0)


def _coords(nt, scale=(1, 1, 1), rotation=(0, 0, 0), kind="Object"):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = scale
    mp.inputs["Rotation"].default_value = rotation
    nt.links.new(tc.outputs[kind], mp.inputs["Vector"])
    return mp.outputs["Vector"]


def _noise(nt, vector, scale, detail=6.0, roughness=0.55, distortion=0.0):
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = detail
    noise.inputs["Roughness"].default_value = roughness
    noise.inputs["Distortion"].default_value = distortion
    nt.links.new(vector, noise.inputs["Vector"])
    return noise.outputs["Fac"]


def _ramp(nt, fac, stops):
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    elements = ramp.color_ramp.elements
    while len(elements) < len(stops):
        elements.new(0.5)
    for element, (pos, color) in zip(elements, stops):
        element.position = pos
        element.color = (*color, 1.0) if len(color) == 3 else color
    nt.links.new(fac, ramp.inputs["Fac"])
    return ramp.outputs["Color"]


def _range(nt, value, lo, hi, from_lo=0.0, from_hi=1.0):
    node = nt.nodes.new("ShaderNodeMapRange")
    node.inputs["From Min"].default_value = from_lo
    node.inputs["From Max"].default_value = from_hi
    node.inputs["To Min"].default_value = lo
    node.inputs["To Max"].default_value = hi
    nt.links.new(value, node.inputs["Value"])
    return node.outputs["Result"]


def _bump(nt, height, strength, distance, bsdf, invert=False):
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    bump.inputs["Distance"].default_value = distance
    bump.invert = invert
    nt.links.new(height, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return bump


def mat_walnut():
    if "MAT_Walnut" in _MATS:
        return _MATS["MAT_Walnut"]
    mat, nt, bsdf = _material("MAT_Walnut")
    grain = _noise(nt, _coords(nt, (1.2, 45.0, 45.0)), 1.4, detail=10.0, roughness=0.62, distortion=0.4)
    pores = _noise(nt, _coords(nt, (8.0, 900.0, 900.0)), 1.0, detail=2.0)
    color = _ramp(nt, grain, [(0.30, (0.030, 0.015, 0.008)), (0.52, (0.075, 0.040, 0.020)), (0.72, (0.150, 0.085, 0.042))])
    nt.links.new(color, bsdf.inputs["Base Color"])
    nt.links.new(_range(nt, grain, 0.30, 0.42), bsdf.inputs["Roughness"])
    _bump(nt, pores, 0.06, 0.0003, bsdf)
    bsdf.inputs["Coat Weight"].default_value = 0.3
    bsdf.inputs["Coat Roughness"].default_value = 0.18
    mat.diffuse_color = (0.08, 0.045, 0.022, 1.0)
    return mat


def mat_oak_floor():
    mat, nt, bsdf = _material("MAT_OakFloor")
    vec = _coords(nt, rotation=(0, 0, math.pi / 2))
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.37
    brick.offset_frequency = 1
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.0012
    brick.inputs["Mortar Smooth"].default_value = 0.3
    brick.inputs["Bias"].default_value = 0.0
    brick.inputs["Brick Width"].default_value = 1.2
    brick.inputs["Row Height"].default_value = 0.19
    brick.inputs["Color1"].default_value = (0.055, 0.032, 0.018, 1.0)
    brick.inputs["Color2"].default_value = (0.105, 0.062, 0.035, 1.0)
    brick.inputs["Mortar"].default_value = (0.01, 0.006, 0.004, 1.0)
    nt.links.new(vec, brick.inputs["Vector"])
    grain = _noise(nt, _coords(nt, (45.0, 1.5, 45.0)), 1.6, detail=8.0, roughness=0.6, distortion=0.5)
    grain_tone = _ramp(nt, grain, [(0.3, (0.65, 0.65, 0.65)), (0.7, (1.35, 1.35, 1.35))])
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    nt.links.new(brick.outputs["Color"], mul.inputs[0])
    nt.links.new(grain_tone, mul.inputs[1])
    nt.links.new(mul.outputs["Vector"], bsdf.inputs["Base Color"])
    nt.links.new(_range(nt, brick.outputs["Fac"], 0.38, 0.75), bsdf.inputs["Roughness"])
    _bump(nt, brick.outputs["Fac"], 0.35, 0.0015, bsdf, invert=True)
    bsdf.inputs["Coat Weight"].default_value = 0.15
    bsdf.inputs["Coat Roughness"].default_value = 0.25
    mat.diffuse_color = (0.08, 0.05, 0.03, 1.0)
    return mat


def mat_wall_paint():
    mat, nt, bsdf = _material("MAT_WallPaint")
    bsdf.inputs["Base Color"].default_value = (0.020, 0.032, 0.075, 1.0)
    peel = _noise(nt, _coords(nt), 260.0, detail=2.0)
    nt.links.new(_range(nt, peel, 0.78, 0.88), bsdf.inputs["Roughness"])
    _bump(nt, peel, 0.025, 0.0004, bsdf)
    mat.diffuse_color = (0.02, 0.032, 0.075, 1.0)
    return mat


def mat_ceiling():
    return mat_principled("MAT_Ceiling", (0.02, 0.024, 0.035), 0.9)


def mat_black_steel():
    if "MAT_BlackSteel" in _MATS:
        return _MATS["MAT_BlackSteel"]
    mat, nt, bsdf = _material("MAT_BlackSteel")
    bsdf.inputs["Base Color"].default_value = (0.016, 0.016, 0.017, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.35
    speck = _noise(nt, _coords(nt), 1500.0, detail=1.0)
    nt.links.new(_range(nt, speck, 0.38, 0.52), bsdf.inputs["Roughness"])
    _bump(nt, speck, 0.04, 0.0002, bsdf)
    mat.diffuse_color = (0.016, 0.016, 0.017, 1.0)
    return mat


def mat_aluminium():
    mat, nt, bsdf = _material("MAT_KeyboardAluminium")
    bsdf.inputs["Base Color"].default_value = (0.035, 0.035, 0.04, 1.0)
    bsdf.inputs["Metallic"].default_value = 1.0
    brushed = _noise(nt, _coords(nt, (1.0, 400.0, 400.0)), 2.0, detail=3.0)
    nt.links.new(_range(nt, brushed, 0.28, 0.38), bsdf.inputs["Roughness"])
    mat.diffuse_color = (0.035, 0.035, 0.04, 1.0)
    return mat


def mat_knob():
    mat, nt, bsdf = _material("MAT_Knob")
    bsdf.inputs["Base Color"].default_value = (0.05, 0.05, 0.055, 1.0)
    bsdf.inputs["Metallic"].default_value = 1.0
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = 40.0
    nt.links.new(_coords(nt), wave.inputs["Vector"])
    nt.links.new(_range(nt, wave.outputs["Fac"], 0.22, 0.4), bsdf.inputs["Roughness"])
    mat.diffuse_color = (0.05, 0.05, 0.055, 1.0)
    return mat


def mat_keycap():
    mat, nt, bsdf = _material("MAT_KeycapPBT")
    bsdf.inputs["Base Color"].default_value = (0.011, 0.011, 0.012, 1.0)
    grit = _noise(nt, _coords(nt), 6000.0, detail=1.0)
    nt.links.new(_range(nt, grit, 0.62, 0.74), bsdf.inputs["Roughness"])
    _bump(nt, grit, 0.06, 0.00005, bsdf)
    mat.diffuse_color = (0.011, 0.011, 0.012, 1.0)
    return mat


def mat_legend(name, color, strength):
    mat, _nt, bsdf = _material(name)
    bsdf.inputs["Base Color"].default_value = (0.12, 0.12, 0.13, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.45
    bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    mat.diffuse_color = (*color, 1.0)
    return mat


def mat_emission(name, color, strength):
    if name in _MATS:
        return _MATS[name]
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (*color, 1.0)
    emit.inputs["Strength"].default_value = strength
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    mat.diffuse_color = (*color, 1.0)
    _MATS[name] = mat
    return mat


def mat_screen():
    mat, nt, bsdf = _material("MAT_MonitorScreen")
    bsdf.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.12
    image = nt.nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(str(SCREEN_IMAGE), check_existing=True)
    image.image.colorspace_settings.name = "sRGB"
    uv = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(uv.outputs["UV"], image.inputs["Vector"])
    nt.links.new(image.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    mat.diffuse_color = (0.3, 0.55, 0.8, 1.0)
    return mat


def mat_leather():
    if "MAT_LeatherPU" in _MATS:
        return _MATS["MAT_LeatherPU"]
    mat, nt, bsdf = _material("MAT_LeatherPU")
    bsdf.inputs["Base Color"].default_value = (0.016, 0.016, 0.018, 1.0)
    voronoi = nt.nodes.new("ShaderNodeTexVoronoi")
    voronoi.inputs["Scale"].default_value = 700.0
    nt.links.new(_coords(nt), voronoi.inputs["Vector"])
    nt.links.new(_range(nt, voronoi.outputs["Distance"], 0.36, 0.5), bsdf.inputs["Roughness"])
    _bump(nt, voronoi.outputs["Distance"], 0.12, 0.0003, bsdf)
    bsdf.inputs["Sheen Weight"].default_value = 0.15
    mat.diffuse_color = (0.016, 0.016, 0.018, 1.0)
    return mat


def mat_leaf():
    mat, _nt, bsdf = _material("MAT_Leaf")
    bsdf.inputs["Base Color"].default_value = (0.025, 0.07, 0.02, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.45
    bsdf.inputs["Subsurface Weight"].default_value = 0.15
    mat.diffuse_color = (0.025, 0.07, 0.02, 1.0)
    return mat


def mat_vinyl(name, color):
    mat, _nt, bsdf = _material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.2
    bsdf.inputs["Coat Weight"].default_value = 0.35
    mat.diffuse_color = (*color, 1.0)
    return mat


def vinylize(mat):
    """読み込んだハテナの材質を、つやのあるソフビの置物に寄せる（色はそのまま）。"""
    if mat is None or not mat.use_nodes:
        return
    for node in mat.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            if not node.inputs["Roughness"].is_linked:
                node.inputs["Roughness"].default_value = 0.22
            node.inputs["Coat Weight"].default_value = 0.35
            node.inputs["Coat Roughness"].default_value = 0.08

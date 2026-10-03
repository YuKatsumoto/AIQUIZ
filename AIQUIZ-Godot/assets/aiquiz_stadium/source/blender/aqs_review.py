"""配置確認シーン：部品をゲームの座標どおりに並べ、ゲームそのままの床（ベルトコンベア）と問題壁を置いて撮る。

床と問題壁はゲームの形をそのまま写した参照物（REF_*）で、書き出さない。
- 床：stage_environment.gd の Floor（幅 24、上面 -1.2 から海底までの箱）・側枠・レール・ローラー。上面はベルトの縞
  （conveyor_belt_floor.gdshader の色と周期）
- 問題壁：quiz_wall.gd の灰色の壁（幅 23.8）と 4 つの色付きの扉、問題文の板
"""
from __future__ import annotations

import math
import random

import bpy
from mathutils import Vector

import aqs_geom as AG
from aqs_common import (BG, C, CAM, DECK_Y, EVIDENCE, FLOOR_WIDTH, GOAL_STAND_OFFSET, GOAL_Z, HAZE, LH, ONLY, SEA_Y, ST,
                        bearing_pos, g2b)
from aqs_geom import Mesh, hexcol, mix, shade, srgb_to_linear

NBLOCKS = 19
BACK_Z = -12.5


def godot_rgb(r, g, b, a=1.0):
    """Godot の Color（sRGB）→ Blender の頂点色（線形）。"""
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), a)


def place(coll, src, name, gpos, yaw_deg=0.0):
    o = bpy.data.objects.new(name, src.data)
    o.location = g2b(*gpos)
    o.rotation_euler = (0, 0, math.radians(yaw_deg))
    coll.objects.link(o)
    return o


def block_kind(i, side):
    if side > 0:
        return "cap_end" if i == 0 else ("cap_start" if i == NBLOCKS - 1 else "bay")
    return "cap_start" if i == 0 else ("cap_end" if i == NBLOCKS - 1 else "bay")


def world_gradient(world, top, horizon, strength=1.0, sun_dir=None, sun_col=None):
    if world.node_tree is None:
        world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = horizon
    ramp.color_ramp.elements[1].position = 0.45
    ramp.color_ramp.elements[1].color = top
    col = ramp.outputs["Color"]
    if sun_dir is not None:
        # 太陽のまわりの明るいかさ（原本の空の光）
        dot = nt.nodes.new("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        dot.inputs[1].default_value = sun_dir
        nt.links.new(tc.outputs["Generated"], dot.inputs[0])
        pw = nt.nodes.new("ShaderNodeMath")
        pw.operation = "POWER"
        clampn = nt.nodes.new("ShaderNodeMath")
        clampn.operation = "MAXIMUM"
        clampn.inputs[1].default_value = 0.0
        nt.links.new(dot.outputs["Value"], clampn.inputs[0])
        nt.links.new(clampn.outputs[0], pw.inputs[0])
        pw.inputs[1].default_value = 24.0
        add = nt.nodes.new("ShaderNodeMix")
        add.data_type = "RGBA"
        add.blend_type = "ADD"
        nt.links.new(pw.outputs[0], add.inputs[0])
        nt.links.new(col, add.inputs[6])
        add.inputs[7].default_value = sun_col or (1.0, 0.95, 0.85, 1.0)
        col = add.outputs[2]
    nt.links.new(col, bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def make_camera(coll, name, eye_g, target_g, fov_v_deg):
    cam = bpy.data.cameras.new(name)
    cam.sensor_fit = "VERTICAL"
    cam.angle = math.radians(fov_v_deg)
    cam.clip_start = 0.1
    cam.clip_end = 20000
    o = bpy.data.objects.new(name, cam)
    eye, tgt = g2b(*eye_g), g2b(*target_g)
    o.location = eye
    o.rotation_euler = (tgt - eye).to_track_quat("-Z", "Y").to_euler()
    coll.objects.link(o)
    return o


# --- ゲームの床（ベルトコンベア） ------------------------------------------------
def belt_material():
    mat = bpy.data.materials.new("REF_ConveyorBelt")
    nt, bsdf = AG._principled(mat)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    # 縞：sin(z × 0.22 × 12)（z は Godot。Blender では -Y）
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = -0.22 * 12.0
    nt.links.new(sep.outputs["Y"], mul.inputs[0])
    sn = nt.nodes.new("ShaderNodeMath")
    sn.operation = "SINE"
    nt.links.new(mul.outputs[0], sn.inputs[0])
    st = nt.nodes.new("ShaderNodeMapRange")
    st.inputs[1].default_value, st.inputs[2].default_value = -0.08, 0.08
    nt.links.new(sn.outputs[0], st.inputs[0])
    stripe = nt.nodes.new("ShaderNodeMix")
    stripe.data_type = "RGBA"
    stripe.inputs[6].default_value = godot_rgb(0.40, 0.41, 0.42)
    stripe.inputs[7].default_value = godot_rgb(0.34, 0.345, 0.35)
    nt.links.new(st.outputs[0], stripe.inputs[0])
    # 縁（|x| 11.15〜12.0）は暗い色
    ab = nt.nodes.new("ShaderNodeMath")
    ab.operation = "ABSOLUTE"
    nt.links.new(sep.outputs["X"], ab.inputs[0])
    rim = nt.nodes.new("ShaderNodeMapRange")
    rim.inputs[1].default_value, rim.inputs[2].default_value = 11.1, 11.2
    nt.links.new(ab.outputs[0], rim.inputs[0])
    rimmix = nt.nodes.new("ShaderNodeMix")
    rimmix.data_type = "RGBA"
    nt.links.new(rim.outputs[0], rimmix.inputs[0])
    nt.links.new(stripe.outputs[2], rimmix.inputs[6])
    rimmix.inputs[7].default_value = godot_rgb(0.26, 0.265, 0.27)
    # 上面以外（側面）は側面の色
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sepn = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sepn.inputs[0])
    top = nt.nodes.new("ShaderNodeMapRange")
    top.inputs[1].default_value, top.inputs[2].default_value = 0.55, 0.85
    nt.links.new(sepn.outputs["Z"], top.inputs[0])
    side = nt.nodes.new("ShaderNodeMix")
    side.data_type = "RGBA"
    nt.links.new(top.outputs[0], side.inputs[0])
    side.inputs[6].default_value = godot_rgb(0.33, 0.34, 0.35)
    nt.links.new(rimmix.outputs[2], side.inputs[7])
    nt.links.new(side.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.78
    bsdf.inputs["Metallic"].default_value = 0.12
    return mat


def build_conveyor(ref, mats, front_z):
    m = Mesh()
    hw = FLOOR_WIDTH / 2
    y_back, y_front = -BACK_Z, -front_z
    m.box_lohi((-hw, y_front, -45.0), (hw, y_back, 0.0), (1, 1, 1, 1), "belt")
    steel, support = godot_rgb(0.64, 0.68, 0.71), godot_rgb(0.16, 0.18, 0.21)
    frame = godot_rgb(0.30, 0.31, 0.33)
    for sgn in (-1, 1):
        # 側枠：0.24×1.05、上端は床の上 0.08、両端に 1.2 はみ出す
        fx = sgn * (hw - 0.12)
        m.box_lohi((fx - 0.12, y_front - 1.2, 0.08 - 1.05), (fx + 0.12, y_back + 1.2, 0.08), frame)
        # レール（conveyor_rails.gd：頭 0.16×0.04、腹 0.06×0.12、台 0.24×0.06、中心 |x| 11.86）
        rx = sgn * 11.86
        m.box_lohi((rx - 0.08, y_front, 0.22), (rx + 0.08, y_back, 0.26), steel)
        m.box_lohi((rx - 0.03, y_front, 0.10), (rx + 0.03, y_back, 0.22), steel)
        m.box_lohi((rx - 0.12, y_front, 0.04), (rx + 0.12, y_back, 0.10), support)
    obj = AG.create_object("REF_ConveyorFloor", m, mats, ref)
    obj.location = (0, 0, DECK_Y)
    # ローラー（半径 0.48、長さ 23.4、上端が床の上面）
    for name, z in (("REF_RollerBack", BACK_Z), ("REF_RollerFront", front_z)):
        rm = Mesh()
        n = 32
        r = 0.48
        ring0 = [(-11.7, r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)]
        ring1 = [(11.7, p[1], p[2]) for p in ring0]
        for i in range(n):
            j = (i + 1) % n
            stripe = i % 4 < 2
            rm.add_face([ring0[i], ring0[j], ring1[j], ring1[i]], godot_rgb(0.40, 0.41, 0.42) if stripe else godot_rgb(0.34, 0.345, 0.35), smooth=True)
        rm.add_face(list(ring1), godot_rgb(0.3, 0.31, 0.32))
        rm.add_face(list(reversed(ring0)), godot_rgb(0.3, 0.31, 0.32))
        ro = AG.create_object(name, rm, mats, ref)
        ro.location = g2b(0.0, DECK_Y - r, z)


def build_quiz_wall(ref, mats, wall_z):
    """quiz_wall.gd の 4 択の壁（灰色の壁・色付きの扉・問題文の板）。壁の原点は y=0。"""
    m = Mesh()
    grey = godot_rgb(0.50, 0.50, 0.50)
    total = FLOOR_WIDTH - 0.2
    half_d = 0.55
    door_top, door_bottom, wall_bottom, wall_top = 2.38, -2.02, -3.15, 4.55
    y0, y1 = -half_d, half_d
    m.box_lohi((-total / 2, y0, door_top), (total / 2, y1, wall_top), grey)
    m.box_lohi((-total / 2, y0, wall_bottom), (total / 2, y1, door_bottom), grey)
    xs = [-5.8, -1.95, 1.95, 5.8]
    edges = [-total / 2] + [e for x in xs for e in (x - 1.45, x + 1.45)] + [total / 2]
    for a, b in zip(edges[0::2], edges[1::2]):
        if b > a:
            m.box_lohi((a, y0, door_bottom), (b, y1, door_top), grey)
    cols = [godot_rgb(0.10, 0.55, 0.95), godot_rgb(0.15, 0.75, 0.30), godot_rgb(0.95, 0.60, 0.10), godot_rgb(0.90, 0.15, 0.15)]
    for x, c in zip(xs, cols):
        m.box_lohi((x - 1.45, -0.6, -2.02), (x + 1.45, 0.6, 2.38), c)
    # 問題文の板（プレイヤー側＝Godot の -Z＝Blender の +Y）
    m.box_lohi((-9.2, y1, 2.72), (9.2, y1 + 0.03, 4.38), godot_rgb(0.60, 0.60, 0.60), faces=["+y"])
    m.box_lohi((-9.0, y1 + 0.03, 2.82), (9.0, y1 + 0.05, 4.28), godot_rgb(0.35, 0.35, 0.35), faces=["+y"])
    for k in range(3):                      # 白い文字の代わりの帯
        m.box_lohi((-5.5 + k * 4.1, y1 + 0.05, 3.3), (-2.5 + k * 4.1, y1 + 0.06, 3.8), (0.9, 0.9, 0.9, 1), faces=["+y"])
    obj = AG.create_object("REF_QuizWall", m, mats, ref)
    obj.location = g2b(0.0, 0.0, wall_z)


def haze_review_material(src_mat):
    """確認用の遠景の材質：元の材質の結果を、カメラからの距離で空の地平線の色（HazeColor）へ寄せる。
    ゲームの遠景シェーダー（aiquiz_backdrop.gdshader の FOG）と同じ式。書き出す材質は変えない。"""
    mat = src_mat.copy()
    mat.name = src_mat.name + "_Review"
    nt = mat.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    surface = out.inputs["Surface"].links[0].from_socket

    def math_node(op, a, b=None):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = op
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                nt.links.new(v, n.inputs[i])
        return n.outputs[0]

    cam = nt.nodes.new("ShaderNodeCameraData")
    dist = math_node("EXPONENT", math_node("MULTIPLY", cam.outputs["View Distance"], -1.0 / HAZE["distance"]))
    amount = math_node("SUBTRACT", 1.0, dist)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    hmap = nt.nodes.new("ShaderNodeMapRange")          # 0→1 に写してから引く（To Min > To Max の clamp は 0 に潰れる）
    hmap.interpolation_type = "SMOOTHSTEP"
    hmap.clamp = True
    nt.links.new(sep.outputs["Z"], hmap.inputs["Value"])
    hmap.inputs["From Min"].default_value = SEA_Y
    hmap.inputs["From Max"].default_value = SEA_Y + HAZE["height"]
    clear = math_node("SUBTRACT", 1.0, math_node("MULTIPLY", hmap.outputs["Result"], HAZE["height_clear"]))
    amount = math_node("MINIMUM", math_node("MULTIPLY", amount, clear), HAZE["max"])
    wet = nt.nodes.new("ShaderNodeMapRange")           # 水面下（浅瀬）はかすませない
    wet.interpolation_type = "SMOOTHSTEP"
    wet.clamp = True
    nt.links.new(sep.outputs["Z"], wet.inputs["Value"])
    wet.inputs["From Min"].default_value = SEA_Y - 1.2
    wet.inputs["From Max"].default_value = SEA_Y + 0.2
    amount = math_node("MULTIPLY", amount, wet.outputs["Result"])
    rgb = nt.nodes.new("ShaderNodeRGB")
    rgb.name = "HazeColor"
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(rgb.outputs["Color"], emit.inputs["Color"])
    strength = nt.nodes.new("ShaderNodeValue")
    strength.name = "HazeStrength"
    strength.outputs[0].default_value = 1.0
    nt.links.new(strength.outputs[0], emit.inputs["Strength"])
    mixs = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(amount, mixs.inputs[0])
    nt.links.new(surface, mixs.inputs[1])
    nt.links.new(emit.outputs["Emission"], mixs.inputs[2])
    nt.links.new(mixs.outputs[0], out.inputs["Surface"])
    return mat


def set_haze(colour, strength):
    for mat in bpy.data.materials:
        if mat.node_tree is None:
            continue
        rgb = mat.node_tree.nodes.get("HazeColor")
        if rgb is not None:
            rgb.outputs[0].default_value = colour
            mat.node_tree.nodes["HazeStrength"].outputs[0].default_value = strength


def build_layout_scene(parts, mats, seats_by_kind):
    layout = bpy.data.scenes.new("AIQUIZ_Stadium_Layout")
    layout.unit_settings.system = "METRIC"
    root = layout.collection
    coll = bpy.data.collections.new("AQS_REVIEW_Layout")
    root.children.link(coll)
    stand = parts["stand"]
    # 帆の一式はゲームで置かない（2026-09-28 のユーザー指示）ので、確認シーンにも並べない
    for i in range(NBLOCKS):
        zc = BACK_Z + 20 * (i + 0.5)
        for side, x, yaw in ((1, 28.0, 0.0), (-1, -28.0, 180.0)):
            kind = block_kind(i, side)
            place(coll, stand[kind], f"{'R' if side > 0 else 'L'}_{i:02d}", (x, 0, zc), yaw)
    place(coll, parts["gate"], "Gate", (0, DECK_Y, GOAL_Z), 0)
    for o in parts["goal_stand"]:
        place(coll, o, "Goal_" + o.name, (0, DECK_Y, GOAL_Z + GOAL_STAND_OFFSET), 180)
    # 遠景は部品シーンでワールドの位置に置いてある。島と街はゲームと同じく距離でかすむ確認用の材質を重ね（object リンク）、
    # 灯台とヨットはそのまま共有する
    review = {}
    for o in parts["backdrop"]:
        keys = {m_.name for m_ in o.data.materials}
        if not any(k == "AQS_BG_Painted" or k.startswith("AQS_CityFacade") for k in keys):
            coll.objects.link(o)
            continue
        r = bpy.data.objects.new("REV_" + o.name, o.data)
        r.matrix_world = o.matrix_world
        coll.objects.link(r)
        for slot in r.material_slots:
            src = slot.material
            if src is None:
                continue
            if src.name not in review:
                review[src.name] = haze_review_material(src)
                key = next((k for k, v in mats.by_key.items() if v == src), None)
                if key is not None:
                    mats.add("review_" + key, review[src.name], night_ratio=mats.night_ratio.get(key))
            slot.link = "OBJECT"
            slot.material = review[src.name]
    ref = bpy.data.collections.new("AQS_REVIEW_Reference")
    root.children.link(ref)
    mats.add("belt", belt_material())
    build_conveyor(ref, mats, GOAL_Z + 20.0)
    build_quiz_wall(ref, mats, 22.0 + 60.0)
    pm = Mesh()
    for x, col in ((3.0, C["orange"]), (-3.0, C["blue"])):
        pm.box((x, 0, 0.45), (0.5, 0.3, 0.9), hexcol("#2E4A8C"))
        pm.box((x, 0, 1.2), (0.6, 0.35, 0.6), col)
        pm.box((x, 0, 1.75), (0.45, 0.45, 0.45), hexcol("#E8B98F"))
    po = AG.create_object("REF_Players", pm, mats, ref)
    po.location = (0, 0, DECK_Y)
    sea = bpy.data.meshes.new("REF_Sea")
    sea.from_pydata([(-9000, -14000, 0), (9000, -14000, 0), (9000, 4000, 0), (-9000, 4000, 0)], [], [(0, 1, 2, 3)])
    seao = bpy.data.objects.new("REF_Sea", sea)
    seao.location = (0, 0, SEA_Y)
    ref.objects.link(seao)
    smat = bpy.data.materials.new("REF_SeaMat")
    nt, bsdf = AG._principled(smat)
    bsdf.inputs["Base Color"].default_value = hexcol("#13B6C9")
    bsdf.inputs["Roughness"].default_value = 0.12
    bsdf.inputs["IOR"].default_value = 1.33
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.45
    noise.inputs["Detail"].default_value = 8.0
    tcs = nt.nodes.new("ShaderNodeTexCoord")
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.2
    nt.links.new(tcs.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    sea.materials.append(smat)
    # 観客の仮置き（確認用、書き出さない）：右スタンド（Godot +X、画面左）＝P1 オレンジ、左＝P2 青
    cm = Mesh()
    rnd = random.Random(7)
    team = {1: [hexcol("#F28C33"), hexcol("#E8742A"), hexcol("#F6A04E")], -1: [hexcol("#3A8EDB"), hexcol("#2F74C4"), hexcol("#5AA6E6")]}
    skin = [hexcol("#E8B98F"), hexcol("#C98E62"), hexcol("#F1CFA6"), hexcol("#8D5B3C")]
    for i in range(NBLOCKS):
        zc = BACK_Z + 20 * (i + 0.5)
        for side in (1, -1):
            for sx, sy_up, sz, row in seats_by_kind[block_kind(i, side)]:
                if rnd.random() > 0.8:
                    continue
                lx, ly = sx, -sz
                wx, wy = (28 + lx, -zc + ly) if side > 0 else (-28 - lx, -zc - ly)
                cm.box((wx, wy, sy_up + 0.28), (0.34, 0.42, 0.5), rnd.choice(team[side]))
                cm.box((wx - side * 0.02, wy, sy_up + 0.72), (0.3, 0.3, 0.3), rnd.choice(skin))
    AG.create_object("REF_Crowd", cm, mats, ref)
    lg = bpy.data.collections.new("AQS_REVIEW_Lights")
    root.children.link(lg)
    sun = bpy.data.lights.new("LGT_Sun", "SUN")
    sun.energy = 3.4
    sun.angle = math.radians(1.5)
    so = bpy.data.objects.new("LGT_Sun", sun)
    lg.objects.link(so)
    layout.world = bpy.data.worlds.new("AQS_World")
    cams = bpy.data.collections.new("AQS_REVIEW_Cameras")
    root.children.link(cams)
    e2 = CAM["TWO_PLAYER_EYE_Y"]["value"]
    make_camera(cams, "CAM_2P", (0, e2, -CAM["TWO_PLAYER_CAMERA_BACK"]["value"]), (0, CAM["TWO_PLAYER_LOOK_Y"]["value"], CAM["TWO_PLAYER_LOOK_AHEAD"]["value"]), CAM["TWO_PLAYER_FOV"]["value"])
    feet = (3.0, DECK_Y, 0.0)
    focus = (feet[0], feet[1] + CAM["THIRD_PERSON_FOCUS_HEIGHT"]["value"], feet[2])
    make_camera(cams, "CAM_1P", (focus[0], focus[1] + CAM["THIRD_PERSON_BASE_HEIGHT"]["value"], focus[2] - CAM["THIRD_PERSON_DISTANCE"]["value"]),
                (focus[0], focus[1], focus[2] + 8.0), CAM["THIRD_PERSON_FOV"]["value"])
    make_camera(cams, "CAM_Goal", (0, e2, GOAL_Z - 40 - 9), (0, 1.0, GOAL_Z - 40 + 8), 50)
    make_camera(cams, "CAM_Water", (20, -5.5, -8), (19, -6.5, 30), 60)
    make_camera(cams, "CAM_Overview", (0, 38, -45), (0, -2, 110), 55)
    make_camera(cams, "CAM_Master", (0, 62, -70), (0, 0, 150), 52)                 # 原本の空撮に近い高さと角度
    make_camera(cams, "CAM_SailClose", (18, 9, 40), (33, 8.5, 52), 55)             # 帆を走路から見上げる
    make_camera(cams, "CAM_City", (0, 6, -9), (620, 120, 4190), 12)                 # 街の望遠
    for cam_name, idx in (("CAM_IslandL", 0), ("CAM_IslandR", 2)):                  # 左右の大きな島の望遠
        spec = BG["islands"][idx]
        gx, _gy, gz = bearing_pos(spec["bearing_deg"], spec["distance"])
        make_camera(cams, cam_name, (0, 6, -9), (gx, SEA_Y + spec["height"] * 0.35, gz), 11)
    make_camera(cams, "CAM_Lighthouse", (-150, 12, 470), (-240, 30, 600), 40)
    make_camera(cams, "CAM_Finale", (0, 1.6, GOAL_Z + GOAL_STAND_OFFSET - 11), (0, 5.5, GOAL_Z + GOAL_STAND_OFFSET + 4), 46)
    fly = make_camera(cams, "CAM_Flyover", (0, 38, -45), (0, -2, 110), 55)
    target = bpy.data.objects.new("CAM_Flyover_Target", None)
    cams.objects.link(target)
    tr = fly.constraints.new("TRACK_TO")
    tr.target = target
    tr.track_axis = "TRACK_NEGATIVE_Z"
    tr.up_axis = "UP_Y"
    for frame, eye, tgt in ((10, (0, 38, -45), (0, -2, 110)), (110, (0, e2, -9), (0, 1, 8))):
        fly.location = g2b(*eye)
        target.location = g2b(*tgt)
        fly.keyframe_insert("location", frame=frame)
        target.keyframe_insert("location", frame=frame)
    fly.data.lens_unit = "FOV"
    fly.data.sensor_fit = "VERTICAL"
    fly.data.angle = math.radians(55)
    fly.data.keyframe_insert("lens", frame=10)
    fly.data.angle = math.radians(50)
    fly.data.keyframe_insert("lens", frame=110)
    layout.frame_start, layout.frame_end = 1, 120
    layout.render.fps = 24
    layout.camera = bpy.data.objects["CAM_2P"]
    setup_render(layout)
    return layout


def setup_render(scene):
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"      # 頂点色（sRGB のパレット）をそのまま出す
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    ev = scene.eevee
    for attr, val in (("taa_render_samples", 64), ("use_raytracing", True), ("use_shadows", True),
                      ("shadow_ray_count", 2), ("shadow_step_count", 8)):
        if hasattr(ev, attr):
            try:
                setattr(ev, attr, val)
            except Exception:
                pass


def use_scene(scene):
    win = bpy.context.window
    if win is not None and win.scene != scene:
        win.scene = scene


def evaluated_location(scene, obj, frame):
    use_scene(scene)
    scene.frame_set(frame)
    dg = bpy.context.evaluated_depsgraph_get()
    return [round(v, 3) for v in obj.evaluated_get(dg).matrix_world.translation]


def render(scene, camera_name, path, frame=None):
    use_scene(scene)
    scene.camera = bpy.data.objects[camera_name]
    if frame is not None:
        scene.frame_set(frame)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True, scene=scene.name)
    return str(path)


def sun_vector(elev_deg, az_deg):
    """太陽へ向かう向き（Blender）。az はコースの前（-Y）から左（+X）へ測る。"""
    e, a = math.radians(elev_deg), math.radians(az_deg)
    return Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))


def set_mood(scene, mats, mood):
    sun = bpy.data.objects["LGT_Sun"]
    world = scene.world
    if mood == "day":
        # ゲームの太陽：前方（ゴール側）の上から、少し右（stage_environment.gd の DirectionalLight3D -50°, -20°）
        sv = sun_vector(50, -20)
        world_gradient(world, hexcol("#3F9CE2"), hexcol("#D2ECF8"), 0.8, tuple(sv), (0.9, 0.85, 0.7, 1.0))
        sun.data.energy, sun.data.color = 3.3, (1.0, 0.96, 0.9)
        mats.set_night(0.0)
        set_haze(hexcol("#D2ECF8"), 0.8)
    elif mood == "dusk":
        sv = sun_vector(8, -15)
        world_gradient(world, hexcol("#7C79BD"), hexcol("#F8A56A"), 0.8, tuple(sv), (1.4, 0.7, 0.35, 1.0))
        sun.data.energy, sun.data.color = 1.8, (1.0, 0.64, 0.4)
        mats.set_night(3.0)
        set_haze(hexcol("#F8A56A"), 0.8)
    else:
        sv = sun_vector(40, 30)
        world_gradient(world, hexcol("#0E1B40"), hexcol("#284476"), 0.55)
        sun.data.energy, sun.data.color = 0.3, (0.62, 0.72, 1.0)
        mats.set_night(6.0)
        set_haze(hexcol("#284476"), 0.55)
    sun.rotation_euler = (-sv).to_track_quat("-Z", "Y").to_euler()


def module_renders(modules_scene, parts, stand_objs):
    """部品ごとの確認レンダー（部品シーンで、ほかの部品を隠して撮る）。"""
    setup_render(modules_scene)
    world = bpy.data.worlds.new("AQS_World_Studio")
    modules_scene.world = world
    world_gradient(world, hexcol("#C9D2DA"), hexcol("#E9ECEE"), 1.0)
    sun = bpy.data.lights.new("LGT_StudioSun", "SUN")
    sun.energy = 3.0
    so = bpy.data.objects.new("LGT_StudioSun", sun)
    so.rotation_euler = (math.radians(45), 0, math.radians(-40))
    modules_scene.collection.objects.link(so)
    cams = AG.collection("AQS_REVIEW_ModuleCameras", modules_scene.collection)
    bay_rig = [stand_objs["bay"]]            # 帆はゲームで置かないので、ブロックだけを撮る
    lush = next(o for o in parts["backdrop"] if o.name == "AQS_BG_IslandLush")
    rocky = next(o for o in parts["backdrop"] if o.name == "AQS_BG_IslandRocky")
    city = next(o for o in parts["backdrop"] if o.name == "AQS_BG_City")
    shots = {
        "module_stand_bay": (bay_rig, (-18, 40, 16), (4, 0, 5), 38),
        "module_stand_bay_course": (bay_rig, (-26, 10, 5), (5, -2, 6), 45),
        "module_sail_rig": ([parts["sail_R"]], (-6, 12, 7), (5, 0, 8.5), 55),
        "module_stand_cap_end": ([stand_objs["cap_end"]], (-16, -30, 14), (5, 4, 1), 38),
        "module_goal_gate": ([parts["gate"]], (-12, 26, 5), (0, 0, 3.2), 40),
        "module_goal_stand": (parts["goal_stand"], (-16, -30, 10), (0, 3.5, 5), 45),
        "module_island_lush": ([lush], tuple(lush.matrix_world @ Vector((0, 900, 180))), tuple(lush.matrix_world @ Vector((0, 0, 30))), 40),
        "module_island_rocky": ([rocky], tuple(rocky.matrix_world @ Vector((-150, 820, 150))), tuple(rocky.matrix_world @ Vector((0, 0, 35))), 40),
        "module_city": ([city], tuple(city.matrix_world @ Vector((0, 1500, 260))), tuple(city.matrix_world @ Vector((0, 0, 120))), 38),
    }
    results = {}
    allobj = [o for o in modules_scene.objects if o.type == "MESH"]
    for name, (objs, eye_b, tgt_b, fov) in shots.items():
        if ONLY and name not in ONLY:
            continue
        for o in allobj:
            o.hide_render = o not in objs
        cam = bpy.data.cameras.new("CAM_" + name)
        cam.sensor_fit = "VERTICAL"
        cam.angle = math.radians(fov)
        cam.clip_end = 20000
        co = bpy.data.objects.new("CAM_" + name, cam)
        co.location = Vector(eye_b)
        co.rotation_euler = (Vector(tgt_b) - Vector(eye_b)).to_track_quat("-Z", "Y").to_euler()
        cams.objects.link(co)
        results[name] = render(modules_scene, co.name, EVIDENCE / f"{name}.png")
    for o in allobj:
        o.hide_render = False
    return results

"""黒板まわりの小道具（実写版、docs/lecture_hall_plan.md の 1a）。

座標・寸法は Godot のセットのローカル（x 横, y 高さ, z 奥行き。黒板は z = 8.6、カメラ側が -z）で書き、_b() / S() で
Blender（x, -z, y）に写す。黒板の正面は Godot -z = Blender +Y。見る人の右は Godot / Blender の -X。

動く部品（Godot が動かす）はそれぞれ別オブジェクトで、原点を動きの基準に置く:
- PRP_BoardPanel_F / _B: 上下スライドの前後 2 枚（原点 = 下端の中央）。黒板面 PRP_BoardSurface_F / _B は子
  （第 3 段階のキャンバスが材質を差し替える）。F は下（0.62〜2.40 m）、B は上（2.32〜4.10 m）にいて、入れ替わる。
- チョーク・黒板消し・マグネット（B の子）・時計の針（原点 = 時計の中心）。
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import lsb_chalkart as CA
import lsb_label as LB
import lsb_pbr as P
from lsb_common import MeshBuilder, g2b

# 小物の実物に対する大きさ（ゴドーくんの手に合わせる）
SMALL = 1.8

BOARD_Z = 8.6
PANEL_W = 7.6
PANEL_H = 1.78
PANEL_T = 0.04
TRIM = 0.035
F_BOTTOM = 0.62
B_BOTTOM = 2.32
SLIDE = 1.70
F_Z = BOARD_Z - 0.045      # 前のパネルの面の中心（奥行き）
B_Z = BOARD_Z + 0.03       # 後ろのパネル
POST_X = 4.12
POST_TOP = 4.66
TRAY_Y = 0.55              # チョーク受けの底の高さ
TRAY_Z0 = BOARD_Z - 0.215  # チョーク受けの手前の縁
TRAY_Z1 = BOARD_Z - 0.075
CLOCK_C = (0.0, 5.02, BOARD_Z - 0.02)
CLOCK_R = 0.30
CART_POS = (-4.75, 7.45)
RACK_POS = (4.72, 8.15)

RX = Matrix.Rotation(math.radians(90.0), 3, "X")
RY = Matrix.Rotation(math.radians(90.0), 3, "Y")


def _b(x, y, z):
    return g2b(x, y, z)


def S(w, h, d):
    return (w, d, h)


# ------------------------------------------------------------------ object helpers

def set_origin(obj, pivot_godot):
    """メッシュをずらして原点を pivot（Godot 座標）へ。"""
    p = _b(*pivot_godot)
    obj.data.transform(Matrix.Translation(-p))
    obj.location = p
    return obj


def parent_keep(child, parent):
    """子のワールド位置を保ったまま親にする（親の原点からの相対で置く）。"""
    # 作ったばかりの親は matrix_world がまだ更新されていないので、親の基本の行列（親の親はない）で計算する
    world = child.matrix_basis.copy()
    child.parent = parent
    child.matrix_parent_inverse = Matrix.Identity(4)
    child.matrix_basis = parent.matrix_basis.inverted() @ world


def assign(obj, *materials):
    """MeshBuilder は palette_material を割り当てる。ここで LSP_ 材質に差し替える（同じ順）。"""
    obj.data.materials.clear()
    for m in materials:
        obj.data.materials.append(m)
    return obj


def mb_build(mb: MeshBuilder, col, materials: dict, bevel=0.0, segments=2):
    """MeshBuilder の材質名 → LSP_ 材質の辞書で差し替えて組み立てる。"""
    return mb.build(col, bevel=bevel, bevel_segments=segments, material_map=materials)


def plane_uv(obj, axis_u: Vector, axis_v: Vector, origin: Vector, w: float, h: float):
    """平らな面に明示の UV（u = axis_u 方向に w で 0→1、v = axis_v 方向に h で 0→1）。"""
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co + (obj.location if obj.parent is None else Vector())
        rel = co - origin
        uv.data[loop.index].uv = (rel.dot(axis_u) / w, rel.dot(axis_v) / h)
    obj["lsb_uv"] = "keep"


# ------------------------------------------------------------------ materials of the board group

def materials(labels: dict):
    M = {}
    # 陽極酸化のサテン仕上げ（暗いホールで真っ黒に映らないよう、粗く、金属度は 0.85）
    M["alu"] = P.aluminum("Alu_Frame", "#C5C9CD", 0.46, "X", anodized=True)
    M["tray"] = P.aluminum("Alu_Tray", "#C5C9CD", 0.5, "X", anodized=True, dust=1.0)
    M["alu_v"] = P.aluminum("Alu_Post", "#BFC3C8", 0.46, "Z", anodized=True)
    M["steel"] = P.powder_coat("Steel_Stand", "#3B4046", 0.5, 0.7)
    M["rubber"] = P.rubber("Rubber")
    M["cap"] = P.plastic("Plastic_Cap", "#5A5F66", 0.42)
    M["back"] = P.powder_coat("Board_Back", "#6B7076", 0.6, 0.2)
    M["chalk_white"] = P.chalk("Chalk_White", "#F1EFE6")
    M["chalk_yellow"] = P.chalk("Chalk_Yellow", "#F2D35E")
    M["chalk_red"] = P.chalk("Chalk_Red", "#E9727C")
    M["chalk_blue"] = P.chalk("Chalk_Blue", "#79A7E0")
    M["felt"] = P.felt("Felt_Eraser", "#5D6E86")
    M["eraser_back"] = P.plastic("Eraser_Back", "#1F2C46", 0.35)
    M["box"] = P.paper("ChalkBox", "#F4F0E2", 0.7, labels["chalk_box"], labels["chalk_box_plane"], 1.4)
    M["box_in"] = P.paper("ChalkBox_Inside", "#C9BC9C", 0.85)
    M["cleaner"] = P.plastic("Cleaner_Body", "#D9D3C4", 0.45, 0.6, labels["cleaner"], labels["cleaner_plane"])
    M["cleaner_dark"] = P.plastic("Cleaner_Dark", "#2A2D31", 0.5)
    M["brush"] = P.felt("Cleaner_Brush", "#2F3134", (0.0, 0.0, 1.0))
    M["switch_red"] = P.plastic("Switch_Red", "#C62828", 0.3)
    M["cord"] = P.rubber("Cord", "#E8E6E0")
    M["cart"] = P.powder_coat("Cart", "#9AA2AA", 0.45, 0.5)
    M["clock_case"] = P.plastic("Clock_Case", "#2B2E33", 0.3, 0.3)
    M["clock_face"] = P.painted_print("Clock_Face", labels["clock_face"], labels["clock_plane"], "#FAFAF7", 0.35)
    M["hand_black"] = P.plastic("Clock_Hand", "#16181B", 0.4, 0.0)
    M["hand_red"] = P.plastic("Clock_Second", "#D32F2F", 0.35, 0.0)
    M["magnet_red"] = P.magnet("Magnet_Red", "#D84B4B")
    M["magnet_blue"] = P.magnet("Magnet_Blue", "#3F7FD0")
    M["magnet_yellow"] = P.magnet("Magnet_Yellow", "#F2C230")
    M["magnet_green"] = P.magnet("Magnet_Green", "#43A35B")
    M["magnet_white"] = P.magnet("Magnet_White", "#F2F2EE")
    M["tool_yellow"] = P.plastic("Tool_Yellow", "#EFCB4E", 0.32, 0.7)
    M["tool_knob"] = P.plastic("Tool_Knob", "#1E2125", 0.3)
    M["tool_print"] = {k: P.plastic(f"Tool_{k}", "#EFCB4E", 0.32, 0.7, labels[k], labels[k + "_plane"])
                       for k in ("set45", "set60", "protractor", "ruler")}
    M["pegboard"] = P.paper("Pegboard", "#B79B74", 0.75, labels["pegboard"], labels["pegboard_plane"], 0.8)
    M["poster"] = P.paper("Poster", "#FBFAF5", 0.6, labels["poster"], labels["poster_plane"], 0.6)
    M["wire"] = P.aluminum("Wire_Hook", "#B4B8BC", 0.35, "Z")
    return M


def board_surface_material(name, art_path, origin_godot_viewer_left_bottom):
    """黒板面の材質: 画像の u は見る人の左→右（Blender -X）、v は下→上（Blender +Z）。"""
    o = _b(*origin_godot_viewer_left_bottom)
    plane = {"origin": tuple(o), "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0),
             "u_len": PANEL_W - 2 * TRIM, "v_len": PANEL_H - 2 * TRIM}
    return P.enamel_board(name, art_path, plane)


# ------------------------------------------------------------------ labels（印刷物）

def make_labels():
    """印刷物の画像を描き、材質の planar() に渡す平面も返す（平面は Blender 座標・ワールド）。"""
    out = {}
    # チョーク箱の正面（Godot -z を向く面）
    bx, by, bz = 0.0, 0.0, 0.0  # 位置は build 時に決まるので、正面の平面は build_chalk_box が上書きする
    c = LB.Canvas("chalk_box_front", 1024, 512, bg="#F4F0E2")
    c.rect(0, 0, 1024, 70, "#1F6E4A")
    c.rect(0, 442, 1024, 70, "#1F6E4A")
    c.text(512, 300, "ダストレス チョーク", 92, "#1B2A22", align="center")
    c.text(512, 170, "白  72本入", 70, "#C0392B", align="center")
    c.text(512, 100, "学校用  炭酸カルシウム製", 34, "#3A4A40", align="center", weight="medium")
    out["chalk_box"] = c.save()
    c = LB.Canvas("cleaner_front", 1024, 512, bg="#D9D3C4")
    c.text(64, 380, "黒板ふきクリーナー", 58, "#2A2D31")
    c.text(64, 310, "CL-200  100V 50/60Hz", 34, "#55595F", weight="medium")
    c.rect(64, 280, 560, 5, "#2A2D31")
    c.text(64, 120, "電源", 36, "#2A2D31", weight="medium")
    for i in range(8):
        c.rect(700 + i * 36, 70, 18, 260, "#3A3D42")
    out["cleaner"] = c.save()
    # 時計の文字盤（512×512、中心が文字盤の中心）
    c = LB.Canvas("clock_face", 1024, 1024, bg="#FAFAF7")
    cx = cy = 512
    for i in range(60):
        a = math.pi * 0.5 - math.tau * i / 60.0
        r0 = 470 if i % 5 else 430
        w = 7 if i % 5 else 16
        c.line(cx + r0 * math.cos(a), cy + r0 * math.sin(a), cx + 492 * math.cos(a), cy + 492 * math.sin(a), w,
               "#16181B")
    for h in range(1, 13):
        a = math.pi * 0.5 - math.tau * h / 12.0
        c.text(cx + 365 * math.cos(a), cy + 365 * math.sin(a), str(h), 104, "#16181B", align="center",
               valign="center", weight="semibold")
    c.text(cx, cy - 210, "QUARTZ", 34, "#55595F", align="center", weight="medium")
    c.text(cx, cy + 170, "GODOT", 40, "#2E6FBF", align="center", weight="bold")
    out["clock_face"] = c.save()
    # 教具の目盛り（三角定規 45°、30-60°、分度器、1 m 定規）。画像は道具の外形の正方形に合わせる
    for key, kind in (("set45", "set45"), ("set60", "set60"), ("protractor", "protractor"), ("ruler", "ruler")):
        out[key] = _tool_label(key, kind)
    c = LB.Canvas("pegboard", 1024, 1024, bg="#B79B74")
    for i in range(16):
        for j in range(16):
            c.circle(32 + i * 64, 32 + j * 64, 9, "#3B2E22", segments=24)
    out["pegboard"] = c.save()
    c = LB.Canvas("safety_poster", 1024, 1400, bg="#FBFAF5")
    c.rect(0, 1220, 1024, 180, "#C62828")
    c.text(512, 1270, "安全第一", 130, "#FFFFFF", align="center")
    c.poly([(512, 1120), (232, 640), (792, 640)], "#F2C230")
    c.poly([(512, 1060), (300, 680), (724, 680)], "#FBFAF5")
    c.poly([(512, 1030), (330, 700), (694, 700)], "#F2C230")
    c.rect(490, 790, 44, 190, "#16181B")
    c.circle(512, 740, 26, "#16181B")
    c.text(512, 470, "刃に近づかない", 92, "#16181B", align="center")
    c.text(512, 350, "跳ぶときは刃の真上で", 64, "#16181B", align="center", weight="medium")
    c.text(512, 260, "停止中もヘルメット着用", 64, "#16181B", align="center", weight="medium")
    c.rect(0, 0, 1024, 150, "#16181B")
    for i in range(8):
        c.rect(-60 + i * 160, 0, 80, 150, "#F2C230", angle_deg=-30, cx=-20 + i * 160, cy=75)
    out["poster"] = c.save()
    return out


def _tool_label(name, kind):
    size = {"set60": (592, 1024), "ruler": (2048, 128)}.get(kind, (1024, 1024))
    c = LB.Canvas(f"tool_{name}", size[0], size[1], bg=(0, 0, 0, 0))
    ink = "#1A1C1F"
    if kind == "set45":
        # 直角が左下、脚 0.40 m = 1024 px。縁に沿って目盛り（1 cm ごと、5・10 で長く）、数字は 10 ごと
        for i in range(0, 39):
            x = 14 + i * 25.6
            ln = 60 if i % 10 == 0 else (40 if i % 5 == 0 else 24)
            c.line(x, 18, x, 18 + ln, 3, ink)
            if i % 10 == 0 and i:
                c.text(x, 90, str(i), 34, ink, align="center", weight="medium")
        c.text(260, 330, "45°", 56, ink, weight="semibold")
    elif kind == "set60":
        # 短い脚（横 0.30 m = 592 px）に沿って cm の目盛り、長い脚（縦）に沿っても
        px_cm = 592.0 / 30.0
        for i in range(0, 29):
            x = 12 + i * px_cm
            ln = 50 if i % 10 == 0 else (34 if i % 5 == 0 else 20)
            c.line(x, 14, x, 14 + ln, 3, ink)
            if i % 10 == 0 and i:
                c.text(x, 78, str(i), 30, ink, align="center", weight="medium")
        for i in range(0, 50):
            y = 12 + i * px_cm
            ln = 50 if i % 10 == 0 else (34 if i % 5 == 0 else 20)
            c.line(14, y, 14 + ln, y, 3, ink)
            if i % 10 == 0 and i:
                c.text(84, y, str(i), 30, ink, valign="center", weight="medium")
        c.text(330, 120, "30°", 44, ink, weight="semibold")
        c.text(70, 800, "60°", 44, ink, weight="semibold")
    elif kind == "protractor":
        cx, cy = 512, 40
        for d in range(0, 181):
            a = math.radians(d)
            r0 = 470 if d % 10 == 0 else (482 if d % 5 == 0 else 492)
            c.line(cx + r0 * math.cos(a), cy + r0 * math.sin(a), cx + 505 * math.cos(a), cy + 505 * math.sin(a),
                   3 if d % 5 else 4, ink)
            if d % 10 == 0:
                c.text(cx + 430 * math.cos(a), cy + 430 * math.sin(a), str(d), 26, ink, align="center",
                       valign="center", weight="medium", angle_deg=d - 90)
        c.line(cx - 40, cy, cx + 40, cy, 3, ink)
        c.line(cx, cy, cx, cy + 40, 3, ink)
    elif kind == "ruler":
        # u = 長さ（2048 px = 90 cm）、v = 幅（128 px）。目盛りは見る人の左の縁（v = 1）から
        px_cm = 2048.0 / 90.0
        for i in range(0, 90):
            x = 6 + i * px_cm
            ln = 56 if i % 10 == 0 else (40 if i % 5 == 0 else 24)
            c.line(x, 128 - ln, x, 128, 3, ink)
            if i % 10 == 0 and i:
                c.text(x, 30, str(i), 34, ink, align="center", weight="semibold", angle_deg=0)
    return c.save()


# ------------------------------------------------------------------ geometry

def _caster(mb, x, z, mat_wheel, mat_steel):
    """キャスター: 取付板、回転のフォーク、車輪。"""
    mb.box(S(0.09, 0.012, 0.09), _b(x, 0.118, z), mat_steel)
    mb.box(S(0.012, 0.07, 0.05), _b(x - 0.03, 0.08, z), mat_steel)
    mb.box(S(0.012, 0.07, 0.05), _b(x + 0.03, 0.08, z), mat_steel)
    mb.cylinder(0.042, 0.035, _b(x, 0.042, z), mat_wheel, rotation=RY, segments=20)
    mb.cylinder(0.012, 0.075, _b(x, 0.042, z), mat_steel, rotation=RY, segments=10)


def build_stand(col, M):
    """支柱 2 本（中にパネルのレール）、脚とキャスター、下の横桟、上の横桟と時計の腕木、チョーク受け。"""
    mb = MeshBuilder("PRP_Blackboard")
    for sx in (-1.0, 1.0):
        x = sx * POST_X
        mb.box(S(0.16, POST_TOP - 0.13, 0.13), _b(x, 0.13 + (POST_TOP - 0.13) * 0.5, BOARD_Z), "post")
        # パネルのレール（支柱の内側の溝の縁）
        for dz in (-0.07, 0.0, 0.07):
            mb.box(S(0.03, POST_TOP - 0.6, 0.012), _b(x - sx * 0.09, 0.45 + (POST_TOP - 0.6) * 0.5, BOARD_Z + dz),
                   "alu_v")
        # 脚（奥行き方向）とキャスター
        mb.box(S(0.12, 0.08, 1.12), _b(x, 0.16, BOARD_Z), "steel")
        for sz in (-1.0, 1.0):
            _caster(mb, x, BOARD_Z + sz * 0.48, "rubber", "steel")
            mb.box(S(0.13, 0.03, 0.06), _b(x, 0.215, BOARD_Z + sz * 0.53), "cap")
        # 上の端のふた
        mb.box(S(0.17, 0.03, 0.14), _b(x, POST_TOP + 0.015, BOARD_Z), "cap")
    # 下の横桟と上の横桟
    mb.box(S(POST_X * 2 - 0.16, 0.07, 0.06), _b(0.0, 0.3, BOARD_Z + 0.05), "steel")
    mb.box(S(POST_X * 2 - 0.16, 0.1, 0.13), _b(0.0, POST_TOP - 0.05, BOARD_Z), "alu")
    # 時計の腕木
    mb.box(S(0.08, CLOCK_C[1] - POST_TOP - 0.05 + CLOCK_R * 0.2, 0.05),
           _b(0.0, POST_TOP + (CLOCK_C[1] - POST_TOP) * 0.5, BOARD_Z), "steel")
    # チョーク受け（アルミの押し出し: 底、手前の立ち上がり、奥の取付の立ち上がり）と両端の樹脂のふた
    tw = POST_X * 2 - 0.2
    depth = TRAY_Z1 - TRAY_Z0
    zc = (TRAY_Z0 + TRAY_Z1) * 0.5
    mb.box(S(tw, 0.012, depth), _b(0.0, TRAY_Y, zc), "tray")
    mb.box(S(tw, 0.022, 0.01), _b(0.0, TRAY_Y + 0.011, TRAY_Z0 + 0.005), "alu")
    mb.box(S(tw, 0.075, 0.012), _b(0.0, TRAY_Y + 0.031, TRAY_Z1), "alu")
    mb.box(S(tw, 0.005, 0.016), _b(0.0, TRAY_Y + 0.0245, TRAY_Z0 + 0.003), "alu")
    for sx in (-1.0, 1.0):
        mb.box(S(0.02, 0.07, depth + 0.012), _b(sx * (tw * 0.5 + 0.01), TRAY_Y + 0.03, zc), "cap")
    mats = {"post": M["steel"], "alu_v": M["alu_v"], "steel": M["steel"], "rubber": M["rubber"], "cap": M["cap"],
            "alu": M["alu"], "tray": M["tray"]}
    obj = mb_build(mb, col, mats, bevel=0.004, segments=2)
    obj["lsb_res"] = [2048, 2048]
    return obj


def build_panel(col, M, tag, bottom_y, z_face, art_path):
    """パネル（アルミの縁と裏板）。原点は下端の中央。黒板面は子の PRP_BoardSurface_<tag>。"""
    mb = MeshBuilder(f"PRP_BoardPanel_{tag}")
    w, h = PANEL_W, PANEL_H
    cy = bottom_y + h * 0.5
    zb = z_face + 0.02
    mb.box(S(w - 0.02, h - 0.02, 0.02), _b(0.0, cy, zb), "back")
    for sy in (-1.0, 1.0):
        mb.box(S(w, TRIM, PANEL_T), _b(0.0, cy + sy * (h - TRIM) * 0.5, z_face + 0.008), "alu")
    for sx in (-1.0, 1.0):
        mb.box(S(TRIM, h, PANEL_T), _b(sx * (w - TRIM) * 0.5, cy, z_face + 0.008), "alu")
    # 引き手（上下の縁の中央）
    mb.box(S(0.32, 0.024, 0.03), _b(0.0, bottom_y + 0.012, z_face - 0.018), "cap")
    mb.box(S(0.32, 0.024, 0.03), _b(0.0, bottom_y + h - 0.012, z_face - 0.018), "cap")
    panel = mb_build(mb, col, {"back": M["back"], "alu": M["alu"], "cap": M["cap"]}, bevel=0.003)
    panel["lsb_res"] = [2048, 1024]
    set_origin(panel, (0.0, bottom_y, z_face))
    # 黒板面: 縁の内側の 1 枚の四角（面は Blender +Y を向く）
    fw, fh = w - 2 * TRIM, h - 2 * TRIM
    me = bpy.data.meshes.new(f"PRP_BoardSurface_{tag}")
    bm = bmesh.new()
    corners = [_b(fw * 0.5, bottom_y + TRIM, z_face - 0.004), _b(-fw * 0.5, bottom_y + TRIM, z_face - 0.004),
               _b(-fw * 0.5, bottom_y + TRIM + fh, z_face - 0.004), _b(fw * 0.5, bottom_y + TRIM + fh, z_face - 0.004)]
    vs = [bm.verts.new(c) for c in corners]
    bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    face = bm.faces[0]
    face.normal_update()
    if face.normal.y < 0.0:
        face.normal_flip()
    bm.to_mesh(me)
    bm.free()
    surf = bpy.data.objects.new(f"PRP_BoardSurface_{tag}", me)
    col.objects.link(surf)
    origin_vl = (fw * 0.5, bottom_y + TRIM, z_face)  # 見る人の左下（Godot +x 側）
    surf.data.materials.append(board_surface_material(f"Board_{tag}", art_path, origin_vl))
    plane_uv(surf, Vector((-1.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0)), _b(*origin_vl), fw, fh)
    surf["lsb_res"] = [4096, 1024]
    parent_keep(surf, panel)
    return panel, surf


def board_art(tag):
    """パネルの面のチョーク画（u = 見る人の左から）。どちらも前の授業の消し残しだけ（右端の刃とジャンプの図は、
    授業の中で先生が描く: lessons/lesson_03.json）。"""
    fw, fh = PANEL_W - 2 * TRIM, PANEL_H - 2 * TRIM
    b = CA.Board(fw, fh, 520.0, seed=11 if tag == "F" else 23)
    if tag == "F":
        CA.ghosts(b, 31, lines=3, area=(0.25, 0.3, 4.6, 1.1))
        b.dust(0.10, 0.10)
    else:
        CA.ghosts(b, 47, lines=3, area=(0.3, 0.25, 6.6, 1.15))
        b.smear(fw * 0.5, fh * 0.5, fw * 0.95, fh * 0.9, 0.02, seed=77)
    path = LB.LABELS / f"board_art_{tag}.png"
    LB.LABELS.mkdir(parents=True, exist_ok=True)
    LB.save_png(b.rgba(), path, f"board_art_{tag}")
    return str(path)


CHALK_R = 0.0055 * SMALL  # 実物の直径 11 mm


def _chalk_bm(length, tip="new", seed=0):
    """チョーク 1 本（+X 方向に長い、少し先細り）。tip: new（角が丸い）/ worn（書いて丸く減った先）/
    broken（斜めに折れた）。"""
    r0 = CHALK_R
    r1 = r0 * 0.93
    bm = bmesh.new()
    rings = 14
    seg = 16
    rng = random.Random(seed)
    verts = []
    for i in range(rings + 1):
        t = i / rings
        x = -length * 0.5 + length * t
        r = r0 + (r1 - r0) * t
        k = 1.0
        if tip == "worn" and t > 0.78:
            u = (t - 0.78) / 0.22
            k = math.sqrt(max(0.0, 1.0 - (u ** 1.6) * 0.85))
        if t < 0.05 or (tip == "new" and t > 0.95):
            k = min(k, 0.93 + 0.07 * (1.0 if 0.05 <= t <= 0.95 else 0.0))
        ring = []
        for j in range(seg):
            a = math.tau * j / seg
            rr = r * k
            xx = x
            if tip == "broken" and t == 1.0:
                xx += math.cos(a) * r * 0.55 + rng.uniform(-0.002, 0.002)
            ring.append(bm.verts.new((xx, rr * math.cos(a), rr * math.sin(a))))
        verts.append(ring)
    for i in range(rings):
        for j in range(seg):
            a, b2 = verts[i][j], verts[i][(j + 1) % seg]
            c, d = verts[i + 1][(j + 1) % seg], verts[i + 1][j]
            bm.faces.new((a, b2, c, d))
    bm.faces.new(list(reversed(verts[0])))
    end = bm.faces.new(verts[-1])
    if tip == "worn":
        # 先の丸み: 端の面を少し押し出してつぶす
        res = bmesh.ops.extrude_face_region(bm, geom=[end])
        top = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
        for v in top:
            v.co.x += r0 * 0.25
            v.co.y *= 0.55
            v.co.z *= 0.55
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_chalks(col, M):
    """チョーク受けの上: 白 3（新品・使いかけ・短い）、黄 2、赤 1、青 1、折れた白の 2 片。各 1 オブジェクト（原点 = 中心）。"""
    specs = [
        # 先生が書く場所（黒板の左側）の手元、チョーク箱の隣に並べる（Godot の進行役がここから取って持ち替える）
        ("White_0", "chalk_white", 0.115, "new", 3.03),
        ("White_1", "chalk_white", 0.085, "worn", 2.89),
        ("White_2", "chalk_white", 0.048, "worn", 2.79),
        ("Yellow_0", "chalk_yellow", 0.112, "new", 2.64),
        ("Yellow_1", "chalk_yellow", 0.07, "worn", 2.51),
        ("Red_0", "chalk_red", 0.096, "worn", 2.37),
        ("Blue_0", "chalk_blue", 0.105, "new", 2.23),
        ("Broken_0", "chalk_white", 0.04, "broken", 1.62),
        ("Broken_1", "chalk_white", 0.031, "broken", 1.69),
    ]
    out = []
    zc = (TRAY_Z0 + TRAY_Z1) * 0.5 - 0.01
    rng = random.Random(5)
    for k, (tag, mat_key, length, tip, x) in enumerate(specs):
        bm = _chalk_bm(length, tip=tip, seed=k)
        r = CHALK_R
        yaw = math.radians(rng.uniform(-12.0, 12.0) + (90.0 if tag.startswith("Broken") else 0.0) * 0.3)
        roll = rng.uniform(0.0, math.tau)
        rot = Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(roll, 4, "X")
        bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
        me = bpy.data.meshes.new(f"PRP_Chalk_{tag}")
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(f"PRP_Chalk_{tag}", me)
        col.objects.link(obj)
        obj.location = _b(x, TRAY_Y + 0.006 + r, zc + rng.uniform(-0.015, 0.015))
        obj.data.materials.append(M[mat_key])
        obj["lsb_res"] = [256, 256]
        obj["lsb_chalk"] = mat_key.split("_")[1]
        out.append(obj)
    return out


def build_chalk_box(col, M, labels):
    """チョーク箱（紙箱、ふたが奥へ開いている、中に白いチョークの頭が 3 列）。チョーク受けの左端（見る人の左）。"""
    x, zc = 3.35, (TRAY_Z0 + TRAY_Z1) * 0.5
    w, h, d = 0.20, 0.07, 0.11
    y0 = TRAY_Y + 0.006
    mb = MeshBuilder("PRP_ChalkBox")
    t = 0.003
    mb.box(S(w, t, d), _b(x, y0 + t * 0.5, zc), "box")
    mb.box(S(w, h, t), _b(x, y0 + h * 0.5, zc - d * 0.5 + t * 0.5), "box")
    mb.box(S(w, h, t), _b(x, y0 + h * 0.5, zc + d * 0.5 - t * 0.5), "box")
    for sx in (-1.0, 1.0):
        mb.box(S(t, h, d), _b(x + sx * (w * 0.5 - t * 0.5), y0 + h * 0.5, zc), "box")
    # ふた（奥の縁で 110° 開く）。閉じたふたは蝶番から手前（Blender +Y）へ伸びる → X まわりに 110° 回す
    hinge = _b(x, y0 + h, zc + d * 0.5)
    lid = Matrix.Rotation(math.radians(110.0), 3, "X")
    center = hinge + lid @ Vector((0.0, d * 0.5, 0.0))
    mb.box((w + 0.002, d, t), center, "box", rotation=lid)
    # 中: 仕切りの底とチョークの頭（3 列 × 8）
    mb.box(S(w - 2 * t, 0.002, d - 2 * t), _b(x, y0 + h - 0.018, zc), "box_in")
    for row in range(3):
        for col_i in range(8):
            cx = x - w * 0.5 + 0.017 + col_i * 0.0237
            cz = zc - d * 0.5 + 0.022 + row * 0.033
            mb.cylinder(0.0098, 0.05, _b(cx, y0 + h - 0.02, cz), "chalk", segments=12)
    obj = mb_build(mb, col, {"box": M["box"], "box_in": M["box_in"], "chalk": M["chalk_white"]}, bevel=0.0008)
    obj["lsb_res"] = [1024, 1024]
    return obj


def chalk_box_plane():
    x, zc = 3.35, (TRAY_Z0 + TRAY_Z1) * 0.5
    w, h, d = 0.20, 0.07, 0.11
    y0 = TRAY_Y + 0.006
    origin = _b(x + w * 0.5, y0, zc - d * 0.5)
    return {"origin": tuple(origin), "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0), "u_len": w, "v_len": h}


def _eraser(col, M, name, at, yaw_deg, upside=False):
    """黒板消し: 樹脂の背（持ち手のくぼみ）と、重ねたフェルト。原点 = フェルトの底の中心。"""
    L, W, Hf, Hb = 0.12 * SMALL, 0.05 * SMALL, 0.016 * SMALL, 0.014 * SMALL
    mb = MeshBuilder(name)
    mb.box(S(L, Hf, W), _b(0.0, Hf * 0.5, 0.0), "felt")
    mb.box(S(L + 0.004, Hb, W + 0.004), _b(0.0, Hf + Hb * 0.5, 0.0), "back")
    mb.box(S(L * 0.62, 0.006, W * 0.55), _b(0.0, Hf + Hb + 0.003, 0.0), "back")
    for sx in (-1.0, 1.0):
        mb.box(S(0.012, 0.004, W * 0.7), _b(sx * L * 0.36, Hf + Hb + 0.002, 0.0), "back")
    obj = mb_build(mb, col, {"felt": M["felt"], "back": M["eraser_back"]}, bevel=0.0025, segments=3)
    obj.location = _b(*at)
    obj.rotation_euler = (math.pi if upside else 0.0, 0.0, math.radians(yaw_deg))
    obj["lsb_res"] = [512, 512]
    return obj


def build_erasers(col, M):
    tray = (0.9, TRAY_Y + 0.006, (TRAY_Z0 + TRAY_Z1) * 0.5)
    e0 = _eraser(col, M, "PRP_Eraser_0", tray, 3.0)
    cx, cz = CART_POS
    # クリーナーの天面（0.78 + 0.22）の差し込み口の脇に置く
    e1 = _eraser(col, M, "PRP_Eraser_1", (cx - 0.06, 0.78 + 0.22 + 0.001, cz - 0.075), -4.0)
    return [e0, e1]


def build_cleaner(col, M):
    """黒板消しクリーナーと台車。台車 0.6×0.45、高さ 0.78（天板）。クリーナーは天板の上。"""
    cx, cz = CART_POS
    out = []
    mb = MeshBuilder("PRP_CleanerCart")
    top = 0.78
    for y in (0.22, top):
        mb.box(S(0.6, 0.025, 0.45), _b(cx, y - 0.0125, cz), "cart")
        for sz in (-1.0, 1.0):
            mb.box(S(0.6, 0.03, 0.012), _b(cx, y + 0.012, cz + sz * 0.219), "cart")
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            mb.cylinder(0.014, top - 0.07, _b(cx + sx * 0.28, 0.07 + (top - 0.07) * 0.5, cz + sz * 0.205), "cart",
                        segments=12)
            mb.cylinder(0.03, 0.03, _b(cx + sx * 0.27, 0.03, cz + sz * 0.19), "rubber", rotation=RY, segments=16)
            mb.box(S(0.012, 0.05, 0.035), _b(cx + sx * 0.27, 0.05, cz + sz * 0.19), "cart")
    out.append(mb_build(mb, col, {"cart": M["cart"], "rubber": M["rubber"]}, bevel=0.003))
    out[-1]["lsb_res"] = [1024, 1024]
    mb = MeshBuilder("PRP_EraserCleaner")
    w, d, h = 0.36, 0.24, 0.22
    x0, z0, y0 = cx - 0.06, cz, top
    mb.box(S(w, h, d), _b(x0, y0 + h * 0.5, z0), "body")
    # 上面の差し込み口と回転ブラシ、手前の操作部
    mb.box(S(w * 0.72, 0.012, d * 0.42), _b(x0, y0 + h + 0.004, z0 + 0.01), "dark")
    mb.cylinder(0.028, w * 0.66, _b(x0, y0 + h - 0.01, z0 + 0.01), "brush", rotation=RY, segments=20)
    # 電源スイッチ（ラベルの「電源」の右、左下）
    mb.box(S(0.04, 0.025, 0.012), _b(x0 + w * 0.22, y0 + h * 0.25, z0 - d * 0.5 - 0.004), "red")
    mb.box(S(0.05, 0.035, 0.008), _b(x0 + w * 0.22, y0 + h * 0.25, z0 - d * 0.5 - 0.001), "dark")
    # 足（ゴム）
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            mb.cylinder(0.012, 0.008, _b(x0 + sx * (w * 0.5 - 0.03), y0 + 0.002, z0 + sz * (d * 0.5 - 0.03)), "dark",
                        segments=12)
    obj = mb_build(mb, col, {"body": M["cleaner"], "dark": M["cleaner_dark"], "brush": M["brush"],
                             "red": M["switch_red"]}, bevel=0.012, segments=4)
    obj["lsb_res"] = [1024, 1024]
    out.append(obj)
    # 電源コード: 背面から天板の縁を越えて床へ、床で輪を描く
    pts = [(x0 + w * 0.4, y0 + 0.05, z0 + d * 0.5), (x0 + w * 0.45, y0 + 0.02, z0 + d * 0.5 + 0.08),
           (cx + 0.28, top - 0.02, cz + 0.26), (cx + 0.31, 0.4, cz + 0.3), (cx + 0.34, 0.02, cz + 0.36),
           (cx + 0.6, 0.012, cz + 0.42), (cx + 0.75, 0.012, cz + 0.2), (cx + 0.6, 0.012, cz + 0.05),
           (cx + 0.9, 0.012, cz - 0.1)]
    curve = bpy.data.curves.new("PRP_CleanerCord", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.006
    curve.bevel_resolution = 3
    sp = curve.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for p, q in zip(sp.points, pts):
        v = _b(*q)
        p.co = (v.x, v.y, v.z, 1.0)
    sp.order_u = 4
    sp.use_endpoint_u = True
    sp.resolution_u = 16
    cord_obj = bpy.data.objects.new("PRP_CleanerCord_curve", curve)
    col.objects.link(cord_obj)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(cord_obj.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(cord_obj)
    bpy.data.curves.remove(curve)
    me.name = "PRP_CleanerCord"
    cord = bpy.data.objects.new("PRP_CleanerCord", me)
    col.objects.link(cord)
    cord.data.materials.clear()
    cord.data.materials.append(M["cord"])
    cord["lsb_res"] = [256, 256]
    out.append(cord)
    return out


def cleaner_plane():
    cx, cz = CART_POS
    w, d, h = 0.36, 0.24, 0.22
    x0, z0, y0 = cx - 0.06, cz, 0.78
    origin = _b(x0 + w * 0.5, y0, z0 - d * 0.5)
    return {"origin": tuple(origin), "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0), "u_len": w, "v_len": h}


def build_magnets(col, M, panel_b):
    """マグネット 5 個（後ろのパネル B の面、B の子）。ドーム形の樹脂。"""
    out = []
    spots = [(2.9, 1.42, "red"), (2.6, 1.42, "blue"), (-1.2, 1.3, "yellow"), (-3.1, 0.35, "green"),
             (-2.85, 0.35, "white")]
    for k, (x, v, color) in enumerate(spots):
        mb = MeshBuilder(f"PRP_Magnet_{k}")
        r = 0.022 * SMALL
        zf = B_Z - 0.004  # 後ろのパネルの黒板面
        y = B_BOTTOM + TRIM + v
        mb.cylinder(r, 0.006, _b(x, y, zf - 0.003), "m", rotation=RX, segments=28)
        mb.sphere(r * 0.98, _b(x, y, zf - 0.006), "m", scale=(1.0, 0.32, 1.0), segments=28, rings=12)
        obj = mb_build(mb, col, {"m": M[f"magnet_{color}"]}, bevel=0.0)
        set_origin(obj, (x, y, zf))
        obj["lsb_res"] = [256, 256]
        parent_keep(obj, panel_b)
        out.append(obj)
    return out


def build_clock(col, M):
    """壁掛け時計: 黒い樹脂の枠、白い文字盤（文字は画像）、針 3 本（原点 = 中心、Godot が回す）。"""
    cx, cy, cz = CLOCK_C
    mb = MeshBuilder("PRP_Clock")
    mb.torus(CLOCK_R, 0.028, _b(cx, cy, cz - 0.02), "case", rotation=RX, segments=64, rings=14)
    mb.cylinder(CLOCK_R + 0.01, 0.05, _b(cx, cy, cz + 0.012), "case", rotation=RX, segments=64)
    mb.cylinder(CLOCK_R - 0.006, 0.004, _b(cx, cy, cz - 0.018), "face", rotation=RX, segments=64)
    obj = mb_build(mb, col, {"case": M["clock_case"], "face": M["clock_face"]}, bevel=0.0)
    obj["lsb_res"] = [1024, 1024]
    hands = [obj]
    for tag, length, width, back, mat_key, dz in (("H", 0.17, 0.018, 0.04, "hand_black", 0.026),
                                                  ("M", 0.25, 0.012, 0.05, "hand_black", 0.030),
                                                  ("S", 0.27, 0.004, 0.07, "hand_red", 0.034)):
        mb = MeshBuilder(f"PRP_ClockHand_{tag}")
        y_mid = (length - back) * 0.5
        mb.box(S(width, length + back, 0.003), _b(cx, cy + y_mid, cz - dz), "hand")
        mb.cylinder(width * 0.9 + 0.006, 0.004, _b(cx, cy, cz - dz), "hand", rotation=RX, segments=20)
        if tag == "S":
            mb.cylinder(0.012, 0.003, _b(cx, cy - back + 0.01, cz - dz), "hand", rotation=RX, segments=16)
        h = mb_build(mb, col, {"hand": M[mat_key]}, bevel=0.0)
        set_origin(h, (cx, cy, cz - dz))
        h["lsb_res"] = [256, 256]
        hands.append(h)
    return hands


def clock_plane():
    cx, cy, cz = CLOCK_C
    r = CLOCK_R - 0.006
    origin = _b(cx + r, cy - r, cz)
    return {"origin": tuple(origin), "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0), "u_len": 2 * r,
            "v_len": 2 * r}


# 教具ラックの配置（ラックの中心からの Godot の x、+ が見る人の左）と大きさ
RACK_W = 0.94
RACK_H = 2.1
POSTER_W = 0.70
POSTER_H = 0.70 * 1400.0 / 1024.0
TOOLS = {
    # key: (左下の角 / 中心の x, y, 大きさ)
    "set45": (0.36, 0.64, (0.40, 0.40)),
    "set60": (0.10, 0.66, (0.30, 0.52)),
    "protractor": (-0.02, 0.24, 0.24),
    "ruler": (0.42, 0.20, (0.9, 0.06)),
}


def rack_face_z():
    return RACK_POS[1] - 0.006 - 0.02


def build_tool_rack(col, M):
    """教具ラック（キャスター付きの有孔ボード）: 上に安全ポスター、下に黒板用の三角定規 2 枚・分度器・90 cm 定規・コンパス。"""
    x, z = RACK_POS
    out = []
    mb = MeshBuilder("PRP_ToolRack")
    w, h = RACK_W, RACK_H
    for sx in (-1.0, 1.0):
        mb.box(S(0.04, h, 0.04), _b(x + sx * (w * 0.5 - 0.02), 0.12 + h * 0.5, z), "steel")
        mb.box(S(0.06, 0.04, 0.5), _b(x + sx * (w * 0.5 - 0.02), 0.1, z), "steel")
        for sz in (-1.0, 1.0):
            _caster(mb, x + sx * (w * 0.5 - 0.02), z + sz * 0.2, "rubber", "steel")
    mb.box(S(w - 0.08, 0.04, 0.04), _b(x, 0.12 + h - 0.02, z), "steel")
    mb.box(S(w - 0.08, h - 0.2, 0.012), _b(x, 0.12 + 0.1 + (h - 0.2) * 0.5, z), "peg")
    py = 0.12 + h - 0.08 - POSTER_H * 0.5
    mb.box(S(POSTER_W, POSTER_H, 0.004), _b(x, py, z - 0.008), "poster")
    # ポスターを留めるクリップと、教具を掛けるフック（針金）
    for sx in (-1.0, 1.0):
        mb.box(S(0.05, 0.03, 0.012), _b(x + sx * POSTER_W * 0.42, py + POSTER_H * 0.5 - 0.01, z - 0.014), "steel")
    for hx, hy in ((0.16, 1.06), (-0.05, 1.20), (-0.02, 0.50), (0.45, 1.12), (-0.36, 1.06)):
        mb.cylinder_between(_b(x + hx, hy, z - 0.006), _b(x + hx, hy + 0.012, z - 0.07), 0.004, "wire", segments=8)
    rack = mb_build(mb, col, {"steel": M["steel"], "rubber": M["rubber"], "peg": M["pegboard"],
                              "poster": M["poster"], "wire": M["wire"]}, bevel=0.003)
    rack["lsb_res"] = [2048, 2048]
    out.append(rack)
    fz = rack_face_z()
    ax, ay, (la, lb) = TOOLS["set45"]
    out.append(_set_square(col, M, "PRP_SetSquare_45", "set45", x + ax, ay, fz, la, lb))
    ax, ay, (la, lb) = TOOLS["set60"]
    out.append(_set_square(col, M, "PRP_SetSquare_60", "set60", x + ax, ay, fz - 0.012, la, lb))
    cx_, cy_, r = TOOLS["protractor"]
    out.append(_protractor(col, M, x + cx_, cy_, fz, r))
    ax, ay, (length, width) = TOOLS["ruler"]
    out.append(_ruler(col, M, x + ax, ay, fz - 0.006, length, width))
    out.append(_compass(col, M, x - 0.36, 0.26, fz - 0.02))
    return out


def tool_planes():
    """教具の目盛りの画像の平面（Blender、見る人の右 = -X）。"""
    x, _ = RACK_POS
    fz = rack_face_z()
    planes = {}
    for key in ("set45", "set60"):
        ax, ay, (la, lb) = TOOLS[key]
        planes[key] = {"origin": tuple(_b(x + ax, ay, fz)), "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0),
                       "u_len": la, "v_len": lb}
    cx_, cy_, r = TOOLS["protractor"]
    span = 2.0 * r * 512.0 / 505.0
    planes["protractor"] = {"origin": tuple(_b(x + cx_ + span * 0.5, cy_ - span * 40.0 / 1024.0, fz)),
                            "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0), "u_len": span, "v_len": span}
    ax, ay, (length, width) = TOOLS["ruler"]
    planes["ruler"] = {"origin": tuple(_b(x + ax, ay, fz)), "u_axis": (0.0, 0.0, 1.0), "v_axis": (-1.0, 0.0, 0.0),
                       "u_len": length, "v_len": width}
    planes["poster"] = {"origin": tuple(_b(x + POSTER_W * 0.5, 0.12 + RACK_H - 0.08 - POSTER_H, RACK_POS[1])),
                        "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0), "u_len": POSTER_W, "v_len": POSTER_H}
    planes["pegboard"] = {"origin": tuple(_b(x + 0.45, 0.22, RACK_POS[1])), "u_axis": (-1.0, 0.0, 0.0),
                          "v_axis": (0.0, 0.0, 1.0), "u_len": 0.5, "v_len": 0.5}
    return planes


def _tool_obj(col, name, bm, M, key):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    obj.data.materials.append(M["tool_print"][key])
    obj.data.materials.append(M["tool_knob"])
    obj["lsb_res"] = [1024, 1024]
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = 0.0025
    mod.segments = 2
    mod.limit_method = "ANGLE"
    return obj


def _prism_bm(bm, outline, hole, thickness, y_face):
    """Blender の XZ 平面の外形（と穴）を、カメラ側の面 y_face から奥（Blender -Y）へ thickness 押し出した板。
    点は Blender の (x, z)。面は triangle_fill（穴のある領域も埋まる）で張ってから押し出す。"""
    edges = []
    for loop in [outline] + ([hole] if hole else []):
        vs = [bm.verts.new((px, y_face, pz)) for px, pz in loop]
        for i in range(len(vs)):
            edges.append(bm.edges.new((vs[i], vs[(i + 1) % len(vs)])))
    res = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=edges, normal=(0.0, 1.0, 0.0))
    faces = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)]
    ext = bmesh.ops.extrude_face_region(bm, geom=faces)
    moved = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0.0, -thickness, 0.0), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def _set_square(col, M, name, key, x, y, z, leg_a, leg_b):
    """三角定規（直角が見る人の左下）。中に相似の三角の穴。つまみ（黒い円筒）。"""
    bm = bmesh.new()
    p = _b(x, y, z)
    # 見る人の右 = Blender -X
    outline = [(p.x, p.z), (p.x - leg_a, p.z), (p.x, p.z + leg_b)]
    cxg = (outline[0][0] + outline[1][0] + outline[2][0]) / 3.0
    czg = (outline[0][1] + outline[1][1] + outline[2][1]) / 3.0
    hole = [(cxg + (px - cxg) * 0.45, czg + (pz - czg) * 0.45) for px, pz in outline]
    _prism_bm(bm, outline, hole, 0.008, p.y)
    for f in bm.faces:
        f.material_index = 0
    # つまみ
    knob = bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.022, radius2=0.018, depth=0.04)
    for v in knob["verts"]:
        v.co = Matrix.Rotation(math.radians(-90.0), 3, "X") @ v.co
        v.co += Vector((outline[0][0] + (cxg - outline[0][0]) * 0.33, p.y + 0.02,
                        outline[0][1] + (czg - outline[0][1]) * 0.33))
    for f in {f for v in knob["verts"] for f in v.link_faces}:
        f.material_index = 1
    obj = _tool_obj(col, name, bm, M, key)
    return obj


def _protractor(col, M, x, y, z, r):
    bm = bmesh.new()
    p = _b(x, y, z)
    n = 48
    outline = [(p.x + r * math.cos(math.pi * i / n), p.z + r * math.sin(math.pi * i / n)) for i in range(n + 1)]
    ri = r * 0.55
    hole = [(p.x + ri * math.cos(math.pi * i / n), p.z + 0.03 + ri * math.sin(math.pi * i / n)) for i in range(n + 1)]
    _prism_bm(bm, outline, hole, 0.008, p.y)
    for f in bm.faces:
        f.material_index = 0
    knob = bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.02, radius2=0.017, depth=0.04)
    for v in knob["verts"]:
        v.co = Matrix.Rotation(math.radians(-90.0), 3, "X") @ v.co
        v.co += Vector((p.x, p.y + 0.02, p.z + r * 0.78))
    for f in {f for v in knob["verts"] for f in v.link_faces}:
        f.material_index = 1
    return _tool_obj(col, "PRP_Protractor", bm, M, "protractor")


def _ruler(col, M, x, y, z, length, w=0.06):
    """90 cm 定規（縦に掛ける。見る人の左の縁が x）。"""
    bm = bmesh.new()
    p = _b(x, y, z)
    outline = [(p.x, p.z), (p.x - w, p.z), (p.x - w, p.z + length), (p.x, p.z + length)]
    _prism_bm(bm, outline, None, 0.01, p.y)
    for f in bm.faces:
        f.material_index = 0
    for dz in (0.25, 0.75):
        knob = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.016, radius2=0.013, depth=0.035)
        for v in knob["verts"]:
            v.co = Matrix.Rotation(math.radians(-90.0), 3, "X") @ v.co
            v.co += Vector((p.x - w * 0.5, p.y + 0.02, p.z + length * dz))
        for f in {f for v in knob["verts"] for f in v.link_faces}:
            f.material_index = 1
    return _tool_obj(col, "PRP_Ruler", bm, M, "ruler")


def _compass(col, M, x, y, z):
    """黒板用コンパス: 頭のつまみ、2 本の脚（片方はゴムの吸盤、片方はチョークのはさみ）、開き具合の固定ねじ。"""
    mb = MeshBuilder("PRP_Compass")
    head = (x, y + 0.72, z)
    left = (x + 0.16, y, z)
    right = (x - 0.16, y + 0.02, z)
    mb.cylinder_between(_b(*head), _b(*left), 0.016, "arm", segments=12)
    mb.cylinder_between(_b(*head), _b(*right), 0.016, "arm", segments=12)
    mb.cylinder(0.035, 0.05, _b(head[0], head[1], head[2] - 0.01), "knob", rotation=RX, segments=20)
    mb.cylinder(0.018, 0.06, _b(head[0], head[1] + 0.06, head[2] - 0.01), "knob", segments=16)
    mb.cylinder(0.03, 0.02, _b(left[0], left[1] + 0.005, left[2]), "rubber", segments=20)
    mb.box(S(0.035, 0.06, 0.035), _b(right[0], right[1] + 0.04, right[2]), "knob")
    mb.cylinder(0.0105, 0.07, _b(right[0], right[1] - 0.005, right[2]), "chalk", segments=12)
    mb.cylinder_between(_b(x + 0.08, y + 0.36, z), _b(x - 0.08, y + 0.37, z), 0.006, "wire", segments=8)
    obj = mb_build(mb, col, {"arm": M["tool_yellow"], "knob": M["tool_knob"], "rubber": M["rubber"],
                             "chalk": M["chalk_white"], "wire": M["wire"]}, bevel=0.002)
    obj["lsb_res"] = [512, 512]
    return obj


# ------------------------------------------------------------------ all

def build(col):
    labels = make_labels()
    labels["chalk_box_plane"] = chalk_box_plane()
    labels["cleaner_plane"] = cleaner_plane()
    labels["clock_plane"] = clock_plane()
    for key, plane in tool_planes().items():
        labels[key + "_plane"] = plane
    M = materials(labels)
    objs = [build_stand(col, M)]
    art_f = board_art("F")
    art_b = board_art("B")
    panel_f, surf_f = build_panel(col, M, "F", F_BOTTOM, F_Z, art_f)
    panel_b, surf_b = build_panel(col, M, "B", B_BOTTOM, B_Z, art_b)
    objs += [panel_f, surf_f, panel_b, surf_b]
    objs += build_chalks(col, M)
    objs.append(build_chalk_box(col, M, labels))
    objs += build_erasers(col, M)
    objs += build_cleaner(col, M)
    objs += build_magnets(col, M, panel_b)
    objs += build_clock(col, M)
    objs += build_tool_rack(col, M)
    return objs

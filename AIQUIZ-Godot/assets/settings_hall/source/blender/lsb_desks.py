"""生徒の机まわりの小道具（実写版、docs/lecture_hall_plan.md の 1c）。

学習机 3 台（鋼のパイプの脚、木目の天板と ABS の縁、天板の下の道具入れ、横のかばん掛け）と丸椅子 3 脚、
机の上: ノート（開いた見開き。めくるページは別オブジェクトで原点 = 綴じ）、鉛筆、消しゴム（紙のスリーブ）と消しカス、
鉛筆削り、蛍光ペン、筆箱、生徒の教科書。居眠りの生徒の机には連結チップソーの模型。
机の位置・高さは今のまま（lsb_props: DESK_XS、DESK_Z、STOOL_Z、STOOL_TOP）。生徒は Godot -z を向いて座る
（黒板が -z ではなく +z なので注意: 生徒は +z（黒板）を向く。ノートは生徒から読める向き = 紙の上が黒板側 = Blender -Y）。
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import lsb_label as LB
import lsb_pbr as P
from lsb_board import RX, RY, S, _b, mb_build, parent_keep, set_origin
from lsb_common import MeshBuilder
from lsb_props import DESK_XS, DESK_Z, STOOL_TOP, STOOL_Z

TOP_Y = 0.725          # 天板の上面
TOP_W, TOP_D, TOP_T = 1.1, 0.6, 0.022
NOTE_W, NOTE_H = 0.179 * 1.8 * 0.6, 0.252 * 1.8 * 0.6   # B5 のノート（片ページ）


def _student_frame(x):
    """机の上の点: 生徒から見て u = 右（生徒は +z を向くので右 = Godot -x）、v = 奥（+z）。原点 = 天板の手前の縁の中央。"""
    def at(u, v, h=0.0):
        return (x - u, TOP_Y + h, DESK_Z - TOP_D * 0.5 + v)
    return at


# ------------------------------------------------------------------ labels

def make_labels():
    out = {}
    rng = random.Random(4)
    sentences = ["連結チップソー　8 枚", "1 分間に 90 回転", "刃の半径 1.45 m", "観察は 2 m 以上はなれる",
                 "跳ぶのは刃が来る 0.3 秒前", "★テストに出る", "回転数 × 歯の数 = ?", "台車の進む向きに立たない"]
    for k in range(3):
        c = LB.Canvas(f"notebook_spread_{k}", 1448, 1024, bg="#FBFBF6")
        for i in range(26):
            y = 960 - i * 36
            c.rect(30, y, 690, 2, "#9EC1E0")
            c.rect(728, y, 690, 2, "#9EC1E0")
        c.rect(722, 0, 4, 1024, "#D8D8D0")
        c.rect(120, 0, 2, 1024, "#E8A0A0")
        c.rect(848, 0, 2, 1024, "#E8A0A0")
        c.text(140, 970, "10/4　第 3 講", 28, "#4A4A4A", weight="regular")
        lines = list(sentences)
        rng.shuffle(lines)
        n = 9 if k == 0 else (5 if k == 1 else 2)
        for i in range(n):
            c.text(140 + rng.randint(0, 20), 920 - i * 72, lines[i % len(lines)], 30, "#3E3E3E", weight="regular")
        if k == 0:
            for j in range(8):
                c.ring(900 + j * 62, 760, 20, 24, "#3E3E3E", segments=32)
            c.rect(880, 720, 520, 3, "#3E3E3E")
            c.text(870, 860, "ばん書のうつし", 26, "#3E3E3E", weight="regular")
            c.rect(1200, 560, 180, 24, "#FFF176AA")
        if k == 2:
            # 居眠り: 途中で線がよれて下へ流れる
            for j in range(18):
                c.line(160 + j * 22, 760 - j * j * 1.4, 182 + j * 22, 760 - (j + 1) * (j + 1) * 1.4, 3, "#5A5A5A")
        out[f"notebook_{k}"] = c.save()
    c = LB.Canvas("eraser_sleeve", 512, 256, bg="#2F6BB5")
    c.rect(0, 0, 512, 60, "#1A1A1A")
    c.rect(0, 196, 512, 60, "#F4F4F4")
    c.text(256, 110, "PLASTIC ERASER", 44, "#F4F4F4", align="center")
    out["eraser_sleeve"] = c.save()
    c = LB.Canvas("student_textbook", 724, 1024, bg="#3C8A5E")
    c.rect(0, 700, 724, 324, "#F4F1E6")
    c.text(362, 860, "連結チップソー", 64, "#1E3A2A", align="center")
    c.text(362, 770, "入門 ワークブック", 40, "#1E3A2A", align="center", weight="medium")
    c.text(362, 120, "なまえ　ゴドー", 34, "#F4F1E6", align="center", weight="medium")
    out["student_textbook"] = c.save()
    c = LB.Canvas("pencil_stamp", 1024, 64, bg=(0, 0, 0, 0))
    c.text(200, 18, "HB  GODOT PENCIL", 34, "#D4AF37", weight="bold")
    out["pencil_stamp"] = c.save()
    return out


# ------------------------------------------------------------------ materials

def materials(labels):
    M = {}
    M["top"] = P.wood("Desk_Top", "#D7B98C", "#B8915E", 5.0, "X", 0.42, varnish=0.25, worn=0.25)
    M["edge"] = P.plastic("Desk_Edge", "#C9A574", 0.35, 0.5)
    M["frame"] = P.powder_coat("Desk_Frame", "#C9C6BC", 0.45, 0.8)
    M["tray"] = P.powder_coat("Desk_Tray", "#8E949A", 0.5, 0.5)
    M["rubber"] = P.rubber("Desk_Rubber", "#2A2B2D")
    M["seat"] = P.wood("Stool_Seat", "#C8A06C", "#A27845", 7.0, "X", 0.4, varnish=0.3, worn=0.35)
    M["seat_edge"] = P.plastic("Stool_SeatEdge", "#5B4632", 0.4)
    M["stool_frame"] = P.powder_coat("Stool_Frame", "#3E444B", 0.45, 0.8)
    M["pages"] = P.paper("Notebook_Pages", "#FBFBF6", 0.8, None, None, 1.0)
    M["note_cover"] = [P.plastic(f"Notebook_Cover_{k}", c, 0.4, 0.4)
                       for k, c in enumerate(("#E7A33C", "#5B9BD5", "#7CB342"))]
    M["pencil_wood"] = P.wood("Pencil_Wood", "#E8C79A", "#D4AE7C", 30.0, "X", 0.6)
    M["pencil_paint"] = [P.plastic(f"Pencil_Paint_{k}", c, 0.22, 0.2)
                         for k, c in enumerate(("#2E7D32", "#F9A825", "#1565C0"))]
    M["graphite"] = P.aluminum("Graphite", "#3A3C3F", 0.45, "X")
    M["eraser"] = P.plastic("Eraser_Rubber", "#F7F7F2", 0.65, 0.2)
    M["crumb"] = P.plastic("Eraser_Crumb", "#E9E6DC", 0.7, 0.0)
    M["sharpener"] = P.aluminum("Sharpener", "#B7BCC2", 0.28, "X")
    M["blade"] = P.aluminum("Sharpener_Blade", "#8E9399", 0.15, "Y")
    M["hl_body"] = P.plastic("Highlighter_Body", "#F2E64A", 0.3, 0.2)
    M["hl_cap"] = P.plastic("Highlighter_Cap", "#D4C51E", 0.3, 0.2)
    M["case"] = P.cloth("PencilCase_Cloth", "#2C3E63", 1600.0)
    M["zip"] = P.aluminum("PencilCase_Zip", "#B9BDC2", 0.3, "X")
    M["model_base"] = P.wood("Model_Base", "#6B4A2E", "#4E331E", 9.0, "X", 0.4, varnish=0.5)
    M["model_blade"] = P.aluminum("Model_Blade", "#C3C8CE", 0.2, "X")
    M["model_frame"] = P.powder_coat("Model_Frame", "#E0A82E", 0.4, 0.3)
    return M


# ------------------------------------------------------------------ desks and stools

def build_desk(col, M, i, x):
    """学習机: 鋼の角パイプの脚 4 本と横桟、天板（木目 + ABS の縁）、天板の下の道具入れ（鋼板の箱）、かばん掛け。"""
    mb = MeshBuilder(f"PRP_Desk_{i}")
    z = DESK_Z
    leg_h = TOP_Y - TOP_T
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            px, pz = x + sx * (TOP_W * 0.5 - 0.05), z + sz * (TOP_D * 0.5 - 0.05)
            mb.box(S(0.028, leg_h - 0.02, 0.028), _b(px, 0.02 + (leg_h - 0.02) * 0.5, pz), "frame")
            mb.cylinder(0.018, 0.02, _b(px, 0.01, pz), "rubber", segments=16)
        mb.box(S(0.022, 0.022, TOP_D - 0.1), _b(x + sx * (TOP_W * 0.5 - 0.05), 0.16, z), "frame")
    mb.box(S(TOP_W - 0.1, 0.022, 0.022), _b(x, 0.16, z + TOP_D * 0.5 - 0.05), "frame")
    # 天板の下の枠
    for sz in (-1.0, 1.0):
        mb.box(S(TOP_W - 0.08, 0.04, 0.02), _b(x, leg_h - 0.02, z + sz * (TOP_D * 0.5 - 0.04)), "frame")
    # 道具入れ（生徒側が開いた箱）: 底・奥・両側
    ty = leg_h - 0.12
    mb.box(S(TOP_W - 0.16, 0.008, TOP_D - 0.14), _b(x, ty, z + 0.02), "tray")
    mb.box(S(TOP_W - 0.16, 0.1, 0.008), _b(x, ty + 0.05, z + TOP_D * 0.5 - 0.07), "tray")
    for sx in (-1.0, 1.0):
        mb.box(S(0.008, 0.1, TOP_D - 0.14), _b(x + sx * (TOP_W * 0.5 - 0.08), ty + 0.05, z + 0.02), "tray")
    # 天板と縁
    mb.box(S(TOP_W - 0.012, TOP_T, TOP_D - 0.012), _b(x, TOP_Y - TOP_T * 0.5, z), "top")
    for sz in (-1.0, 1.0):
        mb.box(S(TOP_W, TOP_T, 0.006), _b(x, TOP_Y - TOP_T * 0.5, z + sz * (TOP_D * 0.5 - 0.003)), "edge")
    for sx in (-1.0, 1.0):
        mb.box(S(0.006, TOP_T, TOP_D), _b(x + sx * (TOP_W * 0.5 - 0.003), TOP_Y - TOP_T * 0.5, z), "edge")
    # かばん掛け（右の脚の外、生徒から見て右 = Godot -x）
    hx = x - TOP_W * 0.5 - 0.01
    mb.cylinder_between(_b(hx, leg_h - 0.06, z - 0.05), _b(hx - 0.04, leg_h - 0.06, z - 0.05), 0.006, "frame", segments=10)
    mb.cylinder_between(_b(hx - 0.04, leg_h - 0.06, z - 0.05), _b(hx - 0.045, leg_h - 0.03, z - 0.05), 0.006, "frame",
                        segments=10)
    obj = mb_build(mb, col, {"frame": M["frame"], "rubber": M["rubber"], "tray": M["tray"], "top": M["top"],
                             "edge": M["edge"]}, bevel=0.003)
    obj["lsb_res"] = [2048, 2048]
    return obj


def build_stool(col, M, i, x):
    """丸椅子: 合板の座面（縁は樹脂）、4 本脚（鋼のパイプ、少し外へ開く）、足のせの輪、ゴムの足。"""
    mb = MeshBuilder(f"PRP_Stool_{i}")
    z = STOOL_Z
    mb.cylinder(0.225, 0.03, _b(x, STOOL_TOP - 0.015, z), "seat", segments=48)
    mb.torus(0.225, 0.016, _b(x, STOOL_TOP - 0.016, z), "edge", segments=48, rings=10)
    mb.cylinder(0.16, 0.02, _b(x, STOOL_TOP - 0.04, z), "frame", segments=32)
    for k in range(4):
        a = math.tau * (k + 0.5) / 4.0
        top = _b(x + math.cos(a) * 0.13, STOOL_TOP - 0.05, z + math.sin(a) * 0.13)
        bottom = _b(x + math.cos(a) * 0.2, 0.02, z + math.sin(a) * 0.2)
        mb.cylinder_between(bottom, top, 0.013, "frame", segments=12)
        mb.cylinder(0.017, 0.02, _b(x + math.cos(a) * 0.2, 0.01, z + math.sin(a) * 0.2), "rubber", segments=12)
    mb.torus(0.18, 0.009, _b(x, 0.16, z), "frame", segments=40, rings=8)
    obj = mb_build(mb, col, {"seat": M["seat"], "edge": M["seat_edge"], "frame": M["stool_frame"],
                             "rubber": M["rubber"]}, bevel=0.002)
    obj["lsb_res"] = [1024, 1024]
    return obj


# ------------------------------------------------------------------ things on the desk

def _notebook(col, M, name, at, k, yaw_deg, plane_cb):
    """開いたノート: 見開きの紙（綴じへ少し沈む）、表紙の縁、右ページは別オブジェクト（めくる、原点 = 綴じ）。
    at: 綴じの中央（Godot）。局所 X = 生徒の右、局所 Y = 奥（紙の上）。"""
    pw, ph = NOTE_W, NOTE_H
    out = []
    for side, label in ((-1, "L"), (1, "R")):
        bm = bmesh.new()
        nx, ny = 12, 4
        grid = []
        for j in range(ny + 1):
            row = []
            for i in range(nx + 1):
                xx = side * pw * i / nx
                lift = 0.006 * (1.0 - (1.0 - i / nx) ** 5) * 0.8 + 0.0012
                row.append(bm.verts.new((xx, ph * (j / ny - 0.5), lift)))
            grid.append(row)
        for j in range(ny):
            for i in range(nx):
                quad = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
                f = bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
                f.material_index = 0
                f.smooth = True
        # 紙の束の厚みと表紙
        geom = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.transform(bm, matrix=Matrix.Translation((side * pw * 0.5, 0.0, 0.0006)) @
                            Matrix.Diagonal((pw + 0.006, ph + 0.006, 0.0012, 1.0)), verts=geom["verts"])
        for f in {f for v in geom["verts"] for f in v.link_faces}:
            f.material_index = 1
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        oname = f"{name}_{label}"
        me = bpy.data.meshes.new(oname)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(oname, me)
        col.objects.link(obj)
        obj.data.materials.append(M[f"note_spread_{k}"])
        obj.data.materials.append(M["note_cover"][k])
        to_world = Matrix.Translation(_b(*at)) @ Matrix.Rotation(math.radians(180.0 + yaw_deg), 4, "Z")
        obj.matrix_world = to_world
        obj["lsb_res"] = [1024, 1024]
        out.append(obj)
    return out


def note_plane():
    """見開きの画像の平面（ノートの局所座標: X は -pw..pw、Y は -ph/2..ph/2）。"""
    return {"origin": (-NOTE_W, -NOTE_H * 0.5, 0.0), "u_axis": (1.0, 0.0, 0.0), "v_axis": (0.0, 1.0, 0.0),
            "u_len": NOTE_W * 2.0, "v_len": NOTE_H}


def _pencil(mb, start, direction, length, paint, sharpened=True, mat_prefix=""):
    """六角の鉛筆（実物の直径 7 mm × SMALL）。start は削っていない端、direction の向きへ芯。"""
    r = 0.0035 * 1.8 * 0.55 * 1.5
    d = Vector(direction).normalized()
    body = length * (0.88 if sharpened else 1.0)
    p0 = Vector(start)
    p1 = p0 + d * body
    mb.cylinder_between(p0, p1, r, paint, segments=6)
    if sharpened:
        cone_len = length - body
        tip = p1 + d * cone_len
        mb.cylinder_between(p1, p1 + d * cone_len * 0.72, r, "pwood", radius2=r * 0.32, segments=12)
        mb.cylinder_between(p1 + d * cone_len * 0.72, tip, r * 0.32, "graphite", radius2=r * 0.05, segments=10)


def build_desk_items(col, M, i, x):
    """机の上の小物。i = 0: ノートの生徒（よく書き込んだノート、蛍光ペン、鉛筆削り、消しゴムとカス）、
    1: 挙手の生徒（ノート、鉛筆、消しゴム）、2: 居眠りの生徒（ほとんど白いノート、模型）。"""
    at = _student_frame(x)
    out = []
    out += _notebook(col, M, f"PRP_Notebook_{i}", at(-0.02, 0.24, 0.0), i, (-6.0, 3.0, 9.0)[i], None)
    rng = random.Random(10 + i)
    mb = MeshBuilder(f"PRP_DeskItems_{i}")
    used = {"case", "zip"}
    # 筆箱（奥の左）
    cx, cy, cz = at(0.33, 0.47, 0.0)
    mb.box(S(0.24, 0.05, 0.075), _b(cx, cy + 0.025, cz), "case")
    mb.box(S(0.235, 0.004, 0.006), _b(cx, cy + 0.051, cz - 0.0), "zip")
    mb.box(S(0.012, 0.012, 0.02), _b(cx + 0.11, cy + 0.05, cz - 0.03), "zip")
    # 鉛筆（右手側に 1〜2 本）
    used |= {"paint0", "pwood", "graphite"}
    _pencil(mb, _b(*at(-0.3, 0.12, 0.0045)), _b(-0.11, 0.0, 0.06) - _b(0, 0, 0), 0.17, "paint0")
    if i != 2:
        used.add("paint1")
        _pencil(mb, _b(*at(-0.42, 0.42, 0.0045)), _b(0.05, 0.0, -0.12) - _b(0, 0, 0), 0.15, "paint1")
    # 消しゴム（スリーブ付き）と消しカス
    ex, ey, ez = at(-0.38, 0.28, 0.0)
    mb.box(S(0.07, 0.022, 0.03), _b(ex, ey + 0.011, ez), "eraser", rotation=Matrix.Rotation(math.radians(15), 3, "Z"))
    mb.box(S(0.045, 0.024, 0.032), _b(ex - 0.008, ey + 0.012, ez), "sleeve", rotation=Matrix.Rotation(math.radians(15), 3, "Z"))
    used |= {"eraser", "sleeve"}
    if i == 0:
        for k in range(9):
            cx2, cy2, cz2 = at(-0.3 + rng.uniform(-0.06, 0.06), 0.2 + rng.uniform(-0.05, 0.05), 0.0)
            mb.cylinder(0.0022, rng.uniform(0.008, 0.016), _b(cx2, cy2 + 0.0022, cz2), "crumb",
                        rotation=Matrix.Rotation(rng.uniform(0, math.pi), 3, "Z") @ RY, segments=8)
        used.add("crumb")
        # 蛍光ペン（ノートの右）
        hx, hy, hz = at(-0.24, 0.42, 0.0)
        d = Vector((0.0, 0.0, 1.0))
        mb.cylinder_between(_b(hx, hy + 0.009, hz - 0.07), _b(hx, hy + 0.009, hz + 0.03), 0.009, "hl_body", segments=20)
        mb.cylinder_between(_b(hx, hy + 0.009, hz + 0.03), _b(hx, hy + 0.009, hz + 0.075), 0.0095, "hl_cap", segments=20)
        used |= {"hl_body", "hl_cap"}
        # 鉛筆削り（小さな金属の削り器と削りくず）
        sx_, sy_, sz_ = at(0.42, 0.25, 0.0)
        mb.box(S(0.03, 0.02, 0.04), _b(sx_, sy_ + 0.01, sz_), "sharp")
        mb.cylinder(0.006, 0.03, _b(sx_, sy_ + 0.011, sz_ - 0.005), "blade", rotation=RX, segments=12)
        for k in range(5):
            px, py, pz = at(0.42 + rng.uniform(-0.04, 0.04), 0.2 + rng.uniform(-0.03, 0.02), 0.0)
            mb.cylinder(0.006, 0.001, _b(px, py + 0.0006, pz), "pwood", segments=10)
        used |= {"sharp", "blade"}
    mats = {"case": M["case"], "zip": M["zip"], "paint0": M["pencil_paint"][i], "paint1": M["pencil_paint"][(i + 1) % 3],
            "pwood": M["pencil_wood"], "graphite": M["graphite"], "eraser": M["eraser"], "sleeve": M["sleeve"],
            "crumb": M["crumb"], "hl_body": M["hl_body"], "hl_cap": M["hl_cap"], "sharp": M["sharpener"],
            "blade": M["blade"]}
    obj = mb_build(mb, col, {k: v for k, v in mats.items() if k in used}, bevel=0.0008)
    obj["lsb_res"] = [1024, 1024]
    out.append(obj)
    if i == 2:
        out.append(build_saw_model(col, M, at))
    return out


def build_saw_model(col, M, at):
    """机の上の連結チップソーの模型（木の台に黄色い台車、銀の刃 4 枚、小さな車輪）。"""
    mb = MeshBuilder("PRP_SawModel")
    cx, cy, cz = at(0.28, 0.2, 0.0)
    mb.box(S(0.3, 0.02, 0.12), _b(cx, cy + 0.01, cz), "base")
    mb.box(S(0.26, 0.018, 0.05), _b(cx, cy + 0.04, cz), "frame")
    for k in range(4):
        bx = cx - 0.1 + k * 0.066
        mb.cylinder(0.028, 0.002, _b(bx, cy + 0.052, cz), "blade", segments=24)
        for t in range(12):
            a = math.tau * t / 12.0
            mb.box(S(0.006, 0.002, 0.004), _b(bx + 0.029 * math.cos(a), cy + 0.052, cz + 0.029 * math.sin(a)), "blade",
                   rotation=Matrix.Rotation(-a, 3, "Z"))
        mb.cylinder(0.004, 0.012, _b(bx, cy + 0.046, cz), "frame", segments=10)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            mb.cylinder(0.008, 0.006, _b(cx + sx * 0.12, cy + 0.028, cz + sz * 0.028), "blade", rotation=RX, segments=12)
    obj = mb_build(mb, col, {"base": M["model_base"], "frame": M["model_frame"], "blade": M["model_blade"]},
                   bevel=0.001)
    obj["lsb_res"] = [1024, 1024]
    return obj


def build_student_textbook(col, M, i, x):
    """生徒の教科書（机の奥の右、閉じて表紙が上）。"""
    at = _student_frame(x)
    w, h, t = 0.21 * 1.8 * 0.5, 0.297 * 1.8 * 0.5, 0.012 * 1.8
    mb = MeshBuilder(f"PRP_StudentBook_{i}")
    cx, cy, cz = at(-0.3, 0.48, 0.0)
    rot = Matrix.Rotation(math.radians(90.0 + (4.0, -7.0, 12.0)[i]), 3, "Z")
    mb.box((h, w, 0.0024), _b(cx, cy + 0.0012, cz), "cover", rotation=rot)
    mb.box((h - 0.006, w - 0.006, t - 0.005), _b(cx, cy + t * 0.5, cz), "pages", rotation=rot)
    mb.box((h, w, 0.0024), _b(cx, cy + t - 0.0012, cz), "front", rotation=rot)
    obj = mb_build(mb, col, {"cover": M["sbook_back"], "pages": M["pages"], "front": M["sbook_front"]}, bevel=0.001)
    obj["lsb_res"] = [512, 512]
    return obj


def build(col):
    labels = make_labels()
    M = materials(labels)
    M["sleeve"] = P.paper("Eraser_Sleeve", "#2F6BB5", 0.5, labels["eraser_sleeve"], {
        "origin": (0.0, 0.0, 0.0), "u_axis": (1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0), "u_len": 0.05,
        "v_len": 0.03}, 0.3)
    for k in range(3):
        M[f"note_spread_{k}"] = P.paper(f"Notebook_Spread_{k}", "#FBFBF6", 0.8, labels[f"notebook_{k}"], note_plane(), 0.5)
    M["sbook_front"] = P.paper("StudentBook_Front", "#3C8A5E", 0.45)
    M["sbook_back"] = P.paper("StudentBook_Back", "#3C8A5E", 0.5)
    objs = []
    for i, x in enumerate(DESK_XS):
        objs.append(build_desk(col, M, i, x))
        objs.append(build_stool(col, M, i, x))
        objs += build_desk_items(col, M, i, x)
        objs.append(build_student_textbook(col, M, i, x))
    return objs

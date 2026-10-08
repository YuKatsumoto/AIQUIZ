"""教卓まわりの小道具（実写版、docs/lecture_hall_plan.md の 1b）。

教卓（Godot (2.0, 6.3)、正面 = 生徒側 = Godot -z、先生は +z 側に立つ）と、その上の
教科書（開いた 1 冊・閉じた 1 冊）・出席簿・湯呑みと長いストロー・赤チョークの皿・プリントの束・ホイッスル・
電気スタンド（夜の採点用）、黒板の前の踏み台。
天板は平ら（日本の教卓）。本やプリントは先生（+z 側、Blender -Y 側に立って +Y を向く）から読める向きに置く
（先生の右 = Blender +X、紙の上 = 生徒側 = Blender +Y）。座標は lsb_board と同じ（Godot → _b()）。
動かすもの（教科書・出席簿・湯呑み・ストロー・ホイッスル・踏み台）は別オブジェクト、原点は底の中心。
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

LECTERN = (2.0, 6.3)
L_W, L_D, L_H = 1.0, 0.62, 1.05        # 本体（幅・奥行き・高さ）
TOP_T = 0.035
STOOL_POS = (-3.3, 7.95)


# ------------------------------------------------------------------ top of the lectern

def top_y():
    """天板の上面の高さ。"""
    return L_H + TOP_T


# ------------------------------------------------------------------ labels

def make_labels():
    out = {}
    # 教科書の表紙（A4 縦の比 1:1.414 → 724×1024）
    c = LB.Canvas("textbook_cover", 724, 1024, bg="#2E5E8C")
    c.rect(0, 760, 724, 264, "#F2C230")
    c.text(362, 900, "連結チップソー概論", 64, "#16222E", align="center")
    c.text(362, 820, "第 3 版", 34, "#16222E", align="center", weight="medium")
    for k in range(8):
        c.ring(92 + k * 77, 520, 28, 36, "#F4F6F8", segments=48)
        c.circle(92 + k * 77, 520, 6, "#F4F6F8")
    c.rect(50, 470, 624, 6, "#F4F6F8")
    c.text(362, 300, "地下神殿 出版", 30, "#DCE6F0", align="center", weight="medium")
    c.text(362, 80, "ゴドー教育研究会 編", 30, "#DCE6F0", align="center", weight="medium")
    out["textbook_cover"] = c.save()
    # 開いたページ（見開き 1448×1024: 左ページ = 本文、右ページ = 図と問い）
    c = LB.Canvas("textbook_spread", 1448, 1024, bg="#F6F3EA")
    lines = ["第 3 講　安全な観察距離と回転数",
             "",
             "　連結チップソーは 8 枚の刃を 3 m おきに",
             "並べた台車で、1 分間に 90 回転する。刃の",
             "半径は 1.45 m あり、歯の先は秒速 13 m で",
             "通り過ぎる。観察するときは、刃の列から",
             "2 m 以上離れ、台車の進む向きの前に立た",
             "ない。",
             "　跳び越えるときは、刃の真上で頂点を",
             "迎えるように、刃が足元に来る 0.3 秒前に",
             "踏み切る。早すぎると刃の手前に着地し、",
             "遅すぎると歯に触れる。"]
    for i, s in enumerate(lines):
        c.text(70, 940 - i * 64, s, 30 if i else 36, "#1E1E1E", weight="bold" if i == 0 else "regular")
    c.text(360, 30, "24", 24, "#555555", align="center", weight="regular")
    c.text(1088, 30, "25", 24, "#555555", align="center", weight="regular")
    # 右ページの図: 刃の列と跳び越える放物線
    for k in range(6):
        c.ring(820 + k * 95, 560, 34, 40, "#1E1E1E", segments=48)
    c.rect(780, 505, 590, 5, "#1E1E1E")
    pts = [(900 + 300 * i / 20.0, 610 + 260 * (1.0 - ((i / 20.0 - 0.5) * 2.0) ** 2)) for i in range(21)]
    for a, b in zip(pts, pts[1:]):
        c.line(a[0], a[1], b[0], b[1], 4, "#C0392B")
    c.text(1050, 900, "図 3-2　跳び越えの軌道", 28, "#1E1E1E", align="center", weight="medium")
    c.rect(790, 160, 600, 230, "#E9E3D0")
    c.text(810, 340, "問 1　刃が足元に来る何秒前に", 28, "#1E1E1E", weight="medium")
    c.text(810, 290, "　　　踏み切ればよいか。", 28, "#1E1E1E", weight="medium")
    c.text(810, 220, "問 2　観察の距離は何 m 以上か。", 28, "#1E1E1E", weight="medium")
    out["textbook_spread"] = c.save()
    # 出席簿（紺の布表紙、白い題字）
    c = LB.Canvas("attendance_cover", 724, 1024, bg="#1D2B4A")
    c.rect(60, 640, 604, 300, "#F4F2EA")
    c.text(362, 820, "出 席 簿", 84, "#1D2B4A", align="center")
    c.text(362, 700, "連結チップソー講座　1 組", 34, "#1D2B4A", align="center", weight="medium")
    c.text(362, 120, "担任　ゴドー", 34, "#E8E4D8", align="center", weight="medium")
    out["attendance_cover"] = c.save()
    # プリント（いちばん上の 1 枚）
    c = LB.Canvas("printout_top", 724, 1024, bg="#FBFBF7")
    c.text(362, 950, "小テスト　第 3 講", 44, "#1E1E1E", align="center")
    c.text(90, 880, "名前（　　　　　　　　）", 28, "#1E1E1E", weight="regular")
    for i in range(6):
        y = 780 - i * 120
        c.text(70, y, f"{i + 1}.", 30, "#1E1E1E", weight="medium")
        c.rect(120, y - 50, 520, 3, "#9A9A9A")
    out["printout_top"] = c.save()
    # 教卓の正面のエンブレム（ゴドーくんの顔）
    c = LB.Canvas("lectern_emblem", 512, 512, bg=(0, 0, 0, 0))
    c.circle(256, 256, 240, "#478CBF")
    for sx in (-1, 1):
        c.circle(256 + sx * 82, 286, 62, "#F4F7FA")
        c.circle(256 + sx * 82, 286, 30, "#1E3A5A")
    c.rect(150, 150, 212, 22, "#F4F7FA")
    c.text(256, 40, "地下神殿講義室", 30, "#F4F7FA", align="center")
    out["lectern_emblem"] = c.save()
    # ストローの縞（横 1024 = 周、縦 = 長さ方向の繰り返し）
    c = LB.Canvas("straw_stripes", 256, 1024, bg="#FAFAFA")
    for i in range(16):
        c.rect(0, i * 64, 256, 26, "#E04848", angle_deg=0)
    out["straw"] = c.save()
    return out


# ------------------------------------------------------------------ materials

def materials(labels, planes):
    M = {}
    M["oak"] = P.wood("Lectern_Oak", "#C79A63", "#9B6B3D", 6.0, "X", 0.45, varnish=0.35, worn=0.4)
    M["oak_edge"] = P.wood("Lectern_OakEdge", "#B88752", "#8A5A30", 9.0, "X", 0.5, varnish=0.3, worn=0.6)
    M["melamine"] = P.plastic("Lectern_Melamine", "#D9D5CC", 0.5, 0.4)
    M["kick"] = P.powder_coat("Lectern_Kick", "#4A4F55", 0.55, 0.5)
    M["emblem"] = P.plastic("Lectern_Emblem", "#C9CDD2", 0.25, 0.2, labels["lectern_emblem"], planes["emblem"])
    M["book_cover"] = P.paper("Textbook_Cover", "#2E5E8C", 0.45, labels["textbook_cover"], planes["textbook_closed"], 0.8)
    M["book_pages"] = P.paper("Textbook_Pages", "#F3EFE3", 0.85, None, None, 1.5)
    M["book_spread"] = P.paper("Textbook_Spread", "#F6F3EA", 0.8, labels["textbook_spread"], planes["spread"], 0.7)
    M["book_open_cover"] = P.paper("Textbook_OpenCover", "#2E5E8C", 0.45)
    M["attendance"] = P.cloth("Attendance_Cloth", "#1D2B4A", 1400.0)
    M["attendance_label"] = P.paper("Attendance_Cover", "#1D2B4A", 0.6, labels["attendance_cover"], planes["attendance"], 0.4)
    M["paper"] = P.paper("Printout", "#FBFBF7", 0.8, labels["printout_top"], planes["printout"], 0.6)
    M["paper_side"] = P.paper("Printout_Side", "#F2F1EA", 0.85)
    M["cup"] = P.ceramic("Teacup_Glaze", "#5E7A4A", 0.08)
    M["cup_foot"] = P.paper("Teacup_Foot", "#B9A88C", 0.8)
    M["tea"] = P.ceramic("Tea", "#7E7A2E", 0.03)
    M["straw"] = P.striped("Straw", "#FAFAFA", "#E04848", 0.022, "Z", 0.22)
    M["chalk_red"] = P.chalk("Chalk_Red_Lectern", "#E9727C")
    M["dish"] = P.ceramic("Chalk_Dish", "#E8E4DA", 0.15)
    M["whistle"] = P.aluminum("Whistle", "#D9DCDF", 0.12, "Y")
    M["lanyard"] = P.cloth("Lanyard", "#C62828", 2200.0)
    M["lamp_arm"] = P.powder_coat("Lamp_Arm", "#2B2F34", 0.4, 0.3)
    M["lamp_shade"] = P.powder_coat("Lamp_Shade", "#E8E4D8", 0.45, 0.2)
    M["lamp_bulb"] = P.ceramic("Lamp_Bulb", "#FFF6E0", 0.05)
    M["stool_alu"] = P.aluminum("Stool_Alu", "#C3C7CC", 0.35, "Z")
    M["stool_tread"] = P.rubber("Stool_Tread", "#2A2C2F")
    M["stool_wood"] = P.wood("Stool_Wood", "#C9A06A", "#9C7244", 8.0, "X", 0.55, varnish=0.2, worn=0.6)
    return M


# ------------------------------------------------------------------ objects

def build_lectern(col, M):
    """教卓: メラミンの箱（正面の幕板・中の棚・足元の蹴込み、先生側は開いている）、木の天板（縁は無垢の木）、
    天板の先生側のペン溝、正面のエンブレム板（別オブジェクト）。"""
    x, z = LECTERN
    mb = MeshBuilder("PRP_Lectern")
    body_h = L_H - 0.05
    for sx in (-1.0, 1.0):
        mb.box(S(0.025, body_h, L_D - 0.02), _b(x + sx * (L_W * 0.5 - 0.0125), 0.05 + body_h * 0.5, z), "mel")
    mb.box(S(L_W - 0.05, body_h, 0.02), _b(x, 0.05 + body_h * 0.5, z - L_D * 0.5 + 0.02), "mel")
    mb.box(S(L_W - 0.05, 0.02, L_D - 0.05), _b(x, 0.07, z), "mel")
    mb.box(S(L_W - 0.05, 0.02, L_D - 0.08), _b(x, 0.55, z + 0.02), "mel")
    mb.box(S(L_W - 0.02, 0.05, L_D - 0.06), _b(x, 0.025, z), "kick")
    for y in (0.07, L_H - 0.01):
        mb.box(S(L_W + 0.01, 0.03, 0.025), _b(x, y, z - L_D * 0.5 + 0.005), "edge")
    # 天板（木）と四方の無垢の縁、先生側のペン溝
    mb.box(S(L_W + 0.02, TOP_T, L_D + 0.02), _b(x, L_H + TOP_T * 0.5, z), "oak")
    for sz in (-1.0, 1.0):
        mb.box(S(L_W + 0.06, TOP_T + 0.006, 0.02), _b(x, L_H + TOP_T * 0.5, z + sz * (L_D * 0.5 + 0.02)), "edge")
    for sx in (-1.0, 1.0):
        mb.box(S(0.02, TOP_T + 0.006, L_D + 0.06), _b(x + sx * (L_W * 0.5 + 0.02), L_H + TOP_T * 0.5, z), "edge")
    mb.box(S(L_W * 0.5, 0.004, 0.03), _b(x - 0.15, L_H + TOP_T + 0.001, z + L_D * 0.5 - 0.04), "edge")
    obj = mb_build(mb, col, {"mel": M["melamine"], "kick": M["kick"], "edge": M["oak_edge"], "oak": M["oak"]},
                   bevel=0.004, segments=2)
    obj["lsb_res"] = [2048, 2048]
    eb = MeshBuilder("PRP_LecternEmblem")
    eb.cylinder(0.17, 0.008, _b(x, 0.72, z - L_D * 0.5 + 0.006), "e", rotation=RX, segments=48)
    emblem = mb_build(eb, col, {"e": M["emblem"]}, bevel=0.002)
    emblem["lsb_res"] = [512, 512]
    return [obj, emblem]


def emblem_plane():
    x, z = LECTERN
    return {"origin": tuple(_b(x + 0.17, 0.72 - 0.17, z - L_D * 0.5)), "u_axis": (-1.0, 0.0, 0.0),
            "v_axis": (0.0, 0.0, 1.0), "u_len": 0.34, "v_len": 0.34}


BOOK_W, BOOK_H, BOOK_T = 0.21 * 1.8 * 0.55, 0.297 * 1.8 * 0.55, 0.018 * 1.8   # A4 の教科書（ゴドーくんの手に合わせて）
OPEN_AT = (-0.05, -0.02)     # 開いた教科書の綴じの中央（教卓の中心からの Godot の x, z）
CLOSED_AT = (0.34, 0.12)     # 閉じた教科書の中心
ATTEND_AT = (0.30, -0.16)    # 出席簿の中心


def _book_closed_bm(w, h, t, spine_round=0.004):
    """閉じた本: 表紙・裏表紙・背（丸み）と、少し引っ込んだ小口の紙の束。+X = 横、+Y = 縦、+Z = 厚み。"""
    bm = bmesh.new()
    cover = 0.0025
    for z0, mi in ((0.0, 0), (t - cover, 0)):
        geom = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.transform(bm, matrix=Matrix.Translation((w * 0.5, h * 0.5, z0 + cover * 0.5)) @
                            Matrix.Diagonal((w, h, cover, 1.0)), verts=geom["verts"])
        for f in {f for v in geom["verts"] for f in v.link_faces}:
            f.material_index = mi
    geom = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Translation((cover * 0.6, h * 0.5, t * 0.5)) @
                        Matrix.Diagonal((cover * 1.2, h, t, 1.0)), verts=geom["verts"])
    for f in {f for v in geom["verts"] for f in v.link_faces}:
        f.material_index = 0
    geom = bmesh.ops.create_cube(bm, size=1.0)
    inset = 0.004
    bmesh.ops.transform(bm, matrix=Matrix.Translation((w * 0.5 + 0.001, h * 0.5, t * 0.5)) @
                        Matrix.Diagonal((w - inset * 2, h - inset * 2, t - cover * 2, 1.0)), verts=geom["verts"])
    for f in {f for v in geom["verts"] for f in v.link_faces}:
        f.material_index = 1
    return bm


def _place_book(col, name, bm, mats, w, h, center_godot, yaw_deg, res=1024):
    """本の局所座標（X 横 0..w、Y 縦 0..h、Z 厚み）の中心を center に置く。先生から読める向き
    （局所 X → Blender +X、局所 Y → Blender +Y）を yaw だけ回す。原点 = 本の角（局所の 0）。"""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    for m in mats:
        obj.data.materials.append(m)
    rot = Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
    c = _b(*center_godot)
    offset = rot @ Vector((w * 0.5, h * 0.5, 0.0, 1.0))
    obj.matrix_world = Matrix.Translation(c - offset.xyz) @ rot
    obj["lsb_res"] = [res, res]
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = 0.0012
    mod.segments = 2
    mod.limit_method = "ANGLE"
    return obj


def build_books(col, M):
    """閉じた教科書と出席簿（天板の左右、先生から読める向き）、開いた教科書（中央、見開き）。"""
    x, z = LECTERN
    ty = top_y()
    out = []
    bm = _book_closed_bm(BOOK_W, BOOK_H, BOOK_T)
    out.append(_place_book(col, "PRP_Textbook_Closed", bm, [M["book_cover"], M["book_pages"]], BOOK_W, BOOK_H,
                           (x + CLOSED_AT[0], ty, z + CLOSED_AT[1]), 8.0))
    bm = _book_closed_bm(BOOK_W * 0.95, BOOK_H * 0.95, BOOK_T * 0.8)
    out.append(_place_book(col, "PRP_AttendanceBook", bm, [M["attendance_label"], M["book_pages"]], BOOK_W * 0.95,
                           BOOK_H * 0.95, (x + ATTEND_AT[0], ty, z + ATTEND_AT[1]), -14.0))
    out.append(_open_book(col, M))
    return out


def _open_book(col, M):
    """書見台の上の開いた教科書: 見開きの 2 枚の紙の束が中央の綴じへ沈む曲面、下に表紙。原点 = 綴じの中央。"""
    u0, v0 = OPEN_AT
    pw, ph = BOOK_W, BOOK_H
    bm = bmesh.new()
    nx, ny = 24, 8
    thick = BOOK_T * 0.45
    # 局所座標: X = 横（-pw..pw）, Y = 縦（0..ph、坂の上へ）, Z = 面から上
    def lift(xx):
        a = abs(xx) / pw
        return thick * (1.0 - (1.0 - a) ** 6) * 0.9 + 0.004 * math.sin(math.pi * min(1.0, a)) - 0.002

    grid = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            xx = -pw + 2.0 * pw * i / nx
            yy = ph * j / ny
            row.append(bm.verts.new((xx, yy, lift(xx) + 0.0025)))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            f.material_index = 0
            f.smooth = True
    # 紙の束の側面（小口）: 外周を下へ伸ばす
    edge_loop = [grid[0][i] for i in range(nx + 1)] + [grid[j][nx] for j in range(1, ny + 1)] + \
                [grid[ny][i] for i in range(nx - 1, -1, -1)] + [grid[j][0] for j in range(ny - 1, 0, -1)]
    lower = [bm.verts.new((v.co.x, v.co.y, 0.0025)) for v in edge_loop]
    n = len(edge_loop)
    for k in range(n):
        f = bm.faces.new((edge_loop[k], lower[k], lower[(k + 1) % n], edge_loop[(k + 1) % n]))
        f.material_index = 1
    # 表紙（少し大きい薄い板）
    geom = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Translation((0.0, ph * 0.5, 0.00125)) @
                        Matrix.Diagonal((pw * 2.0 + 0.012, ph + 0.012, 0.0025, 1.0)), verts=geom["verts"])
    for f in {f for v in geom["verts"] for f in v.link_faces}:
        f.material_index = 2
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("PRP_Textbook_Open")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("PRP_Textbook_Open", me)
    col.objects.link(obj)
    for m in (M["book_spread"], M["book_pages"], M["book_open_cover"]):
        obj.data.materials.append(m)
    # 置く: 綴じの中央を天板の OPEN_AT へ。局所 X → Blender +X（先生の右）、局所 Y → Blender +Y（生徒側が紙の上）
    centre = _b(LECTERN[0] + u0, top_y(), LECTERN[1] + v0) - Vector((0.0, ph * 0.5, 0.0))
    obj.matrix_world = Matrix.Translation(centre) @ Matrix.Rotation(math.radians(3.0), 4, "Z")
    obj["lsb_res"] = [2048, 2048]
    return obj


def book_planes():
    """閉じた教科書の表紙・出席簿の表紙・見開きのページの画像の平面。物体の局所座標（本の座標）で書く。"""
    return {
        "textbook_closed": {"origin": (0.0, 0.0, 0.0), "u_axis": (1.0, 0.0, 0.0), "v_axis": (0.0, 1.0, 0.0),
                            "u_len": BOOK_W, "v_len": BOOK_H},
        "attendance": {"origin": (0.0, 0.0, 0.0), "u_axis": (1.0, 0.0, 0.0), "v_axis": (0.0, 1.0, 0.0),
                       "u_len": BOOK_W * 0.95, "v_len": BOOK_H * 0.95},
        "spread": {"origin": (-BOOK_W, 0.0, 0.0), "u_axis": (1.0, 0.0, 0.0), "v_axis": (0.0, 1.0, 0.0),
                   "u_len": BOOK_W * 2.0, "v_len": BOOK_H},
    }


def build_printouts(col, M):
    """プリントの束（棚の左、20 枚ほど、上の数枚が少しずれる）。原点 = 束の底の中心。"""
    x, z = LECTERN
    sy = top_y()
    cz = z + 0.08
    cx = x - 0.3
    pw, ph = 0.21 * 1.8 * 0.5, 0.297 * 1.8 * 0.5
    mb = MeshBuilder("PRP_Printouts")
    rng = random.Random(3)
    sheets = 18
    for k in range(sheets):
        yaw = Matrix.Rotation(math.radians(rng.uniform(-2.5, 2.5) if k > sheets - 5 else rng.uniform(-0.8, 0.8)), 3, "Z")
        mat = "top" if k == sheets - 1 else "side"
        mb.box((pw, ph, 0.0012), _b(cx + rng.uniform(-0.004, 0.004), sy + 0.0006 + k * 0.0013,
                                    cz + rng.uniform(-0.004, 0.004)), mat, rotation=yaw)
    obj = mb_build(mb, col, {"top": M["paper"], "side": M["paper_side"]})
    set_origin(obj, (cx, sy, cz))
    obj["lsb_res"] = [1024, 1024]
    return obj


def printout_plane():
    pw, ph = 0.21 * 1.8 * 0.5, 0.297 * 1.8 * 0.5
    # 原点を移したあとの局所座標（原点 = 束の底の中心）。先生から読める: u = Blender +X、v = Blender +Y
    return {"origin": (-pw * 0.5, -ph * 0.5, 0.0), "u_axis": (1.0, 0.0, 0.0), "v_axis": (0.0, 1.0, 0.0),
            "u_len": pw, "v_len": ph}


def _lathe(bm, profile, segments=48, mat=0):
    """profile: [(r, z), ...]（下から上へ）を Z 軸まわりに回した面。"""
    rings = []
    for r, zz in profile:
        rings.append([bm.verts.new((r * math.cos(math.tau * i / segments), r * math.sin(math.tau * i / segments), zz))
                      for i in range(segments)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            f = bm.faces.new((a[i], a[(i + 1) % segments], b[(i + 1) % segments], b[i]))
            f.material_index = mat
            f.smooth = True
    return rings


def build_teacup(col, M):
    """湯呑み（釉の陶器、高台は素焼き、お茶が 7 分目）と、長い蛇腹のストロー（先生の口の高さまで伸びて先生の方へ曲がる）。"""
    x, z = LECTERN
    sy = top_y()
    cx, cz = x - 0.4, z + 0.2
    bm = bmesh.new()
    k = 1.8 * 0.55
    outer = [(0.030 * k, 0.0), (0.033 * k, 0.004), (0.031 * k, 0.010), (0.036 * k, 0.012), (0.040 * k, 0.03),
             (0.043 * k, 0.07), (0.044 * k, 0.09)]
    inner = [(0.041 * k, 0.09), (0.039 * k, 0.06), (0.035 * k, 0.02), (0.0, 0.016)]
    rings = _lathe(bm, outer + [(0.0425 * k, 0.092)], 48, 0)
    rings_in = _lathe(bm, [(0.0425 * k, 0.092)] + inner[:-1], 48, 0)
    # 高台の素焼き（いちばん下の 2 段）
    for f in bm.faces:
        if max(v.co.z for v in f.verts) <= 0.0125:
            f.material_index = 1
    # 底のふた
    bottom = bm.faces.new([v for v in reversed(rings[0])])
    bottom.material_index = 1
    inner_bottom = bm.faces.new(rings_in[-1])
    inner_bottom.material_index = 0
    # お茶の面
    tea = bmesh.ops.create_circle(bm, cap_ends=True, segments=48, radius=0.0385 * k)
    for v in tea["verts"]:
        v.co.z = 0.068
    for f in {f for v in tea["verts"] for f in v.link_faces}:
        f.material_index = 2
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("PRP_Teacup")
    bm.to_mesh(me)
    bm.free()
    cup = bpy.data.objects.new("PRP_Teacup", me)
    col.objects.link(cup)
    for m in (M["cup"], M["cup_foot"], M["tea"]):
        cup.data.materials.append(m)
    cup.location = _b(cx, sy, cz)
    cup["lsb_res"] = [512, 512]
    # ストロー: カップの中から真上へ 0.28 m、蛇腹で先生（+z 側）へ曲がって 0.1 m
    pts = [(cx, sy + 0.03, cz), (cx, sy + 0.2, cz), (cx, sy + 0.31, cz + 0.02), (cx - 0.01, sy + 0.34, cz + 0.08),
           (cx - 0.02, sy + 0.345, cz + 0.17)]
    curve = bpy.data.curves.new("PRP_Straw_curve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.0065
    curve.bevel_resolution = 4
    sp = curve.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for p, q in zip(sp.points, pts):
        v = _b(*q)
        p.co = (v.x, v.y, v.z, 1.0)
    sp.order_u = 3
    sp.use_endpoint_u = True
    sp.resolution_u = 24
    cobj = bpy.data.objects.new("PRP_Straw_curve", curve)
    col.objects.link(cobj)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(cobj.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(cobj)
    bpy.data.curves.remove(curve)
    me.name = "PRP_Straw"
    straw = bpy.data.objects.new("PRP_Straw", me)
    col.objects.link(straw)
    straw.data.materials.append(M["straw"])
    straw["lsb_res"] = [256, 256]
    set_origin(straw, (cx, sy + 0.03, cz))
    parent_keep(straw, cup)
    return [cup, straw]


def straw_plane():
    # 縞はストローの長さ方向（Blender Z）に繰り返す: u は周（使わない）、v を高さ 0.05 m ごとに 1 周期（画像は REPEAT ではないので長めに）
    return {"origin": (0.0, 0.0, -0.05), "u_axis": (1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0), "u_len": 0.05,
            "v_len": 0.45}


def build_chalk_dish(col, M):
    """赤チョークの小皿（書見台の右端の溝の脇）。皿 + 赤チョーク 2 本。"""
    x, z = LECTERN
    sy = top_y()
    cx, cz = x + 0.1, z + 0.22
    bm = bmesh.new()
    _lathe(bm, [(0.0, 0.0), (0.05, 0.0), (0.06, 0.006), (0.065, 0.016), (0.06, 0.017), (0.052, 0.008), (0.0, 0.006)],
           40, 0)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    for i, (dx, dy, yaw) in enumerate(((0.0, 0.0, 10.0), (0.012, 0.0, -25.0))):
        geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=0.0099, radius2=0.0092,
                                     depth=0.07 - i * 0.02)
        m = Matrix.Translation((dx, 0.012 * i - 0.006, 0.016 + 0.0099)) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ \
            Matrix.Rotation(math.radians(90.0), 4, "Y")
        bmesh.ops.transform(bm, matrix=m, verts=geom["verts"])
        for f in {f for v in geom["verts"] for f in v.link_faces}:
            f.material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("PRP_ChalkDish")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("PRP_ChalkDish", me)
    col.objects.link(obj)
    obj.data.materials.append(M["dish"])
    obj.data.materials.append(M["chalk_red"])
    obj.location = _b(cx, sy, cz)
    obj["lsb_res"] = [512, 512]
    return obj


def build_whistle(col, M):
    """ホイッスル（金属、ひものついた輪）と、とぐろを巻いた赤いひも。棚の上。"""
    x, z = LECTERN
    sy = top_y()
    cx, cz = x - 0.12, z + 0.24
    mb = MeshBuilder("PRP_Whistle")
    mb.cylinder(0.016, 0.03, _b(cx, sy + 0.016, cz), "w", rotation=RY, segments=24)
    mb.box(S(0.05, 0.012, 0.022), _b(cx - 0.035, sy + 0.024, cz), "w")
    mb.torus(0.008, 0.002, _b(cx + 0.02, sy + 0.03, cz), "w", rotation=RY, segments=16, rings=6)
    for k in range(3):
        r = 0.05 + k * 0.012
        mb.torus(r, 0.0035, _b(cx + 0.07, sy + 0.0035 + k * 0.006, cz - 0.02), "l", segments=40, rings=8,
                 sweep=math.radians(340.0))
    obj = mb_build(mb, col, {"w": M["whistle"], "l": M["lanyard"]}, bevel=0.0)
    set_origin(obj, (cx, sy, cz))
    obj["lsb_res"] = [512, 512]
    return obj


def build_desk_lamp(col, M):
    """電気スタンド（夜の採点用。昼は消灯）: 丸い台、2 節のアーム、ばね、笠と電球。棚の右奥。"""
    x, z = LECTERN
    sy = top_y()
    bx, bz = x + 0.4, z - 0.18
    mb = MeshBuilder("PRP_DeskLamp")
    mb.cylinder(0.07, 0.022, _b(bx, sy + 0.011, bz), "arm", segments=40, radius2=0.064)
    j1 = (bx, sy + 0.045, bz)
    j2 = (bx - 0.05, sy + 0.33, bz + 0.05)
    j3 = (bx - 0.24, sy + 0.42, bz - 0.02)
    mb.cylinder(0.014, 0.03, _b(*j1), "arm", rotation=RY, segments=16)
    mb.cylinder_between(_b(*j1), _b(*j2), 0.009, "arm", segments=12)
    mb.cylinder_between(_b(*j2), _b(*j3), 0.008, "arm", segments=12)
    mb.cylinder(0.012, 0.03, _b(*j2), "arm", rotation=RY, segments=16)
    for k in range(10):
        t = (k + 0.5) / 10.0
        p = Vector(j1).lerp(Vector(j2), t) + Vector((0.0, 0.0, -0.025))
        mb.torus(0.006, 0.0012, _b(*p), "arm", rotation=Matrix.Rotation(math.radians(80.0), 3, "X"), segments=12, rings=4)
    shade_c = Vector(j3) + Vector((-0.04, -0.05, 0.0))
    axis = Vector((-0.4, -1.0, 0.0)).normalized()
    from lsb_common import aim_matrix
    mb.cone(0.085, 0.12, _b(*shade_c), "shade", rotation=aim_matrix(Vector((axis.x, -axis.z, axis.y)) * -1.0),
            segments=40)
    mb.sphere(0.03, _b(*(shade_c + axis * 0.04)), "bulb", segments=20, rings=12)
    obj = mb_build(mb, col, {"arm": M["lamp_arm"], "shade": M["lamp_shade"], "bulb": M["lamp_bulb"]}, bevel=0.0015)
    obj["lsb_res"] = [1024, 1024]
    obj["lsb_lamp_bulb"] = list(_b(*(shade_c + axis * 0.04)))
    return obj


def build_step_stool(col, M):
    """踏み台（2 段、アルミの脚と木の踏み板にゴムの滑り止め）。黒板の前の右寄り。原点 = 床の中心。"""
    x, z = STOOL_POS
    w, d1, h1, h2 = 0.62, 0.5, 0.24, 0.46
    mb = MeshBuilder("PRP_StepStool")
    # 側の枠（アルミ角パイプ）: 前の脚、後ろの脚、上段と下段の受け
    for sx in (-1.0, 1.0):
        xx = x + sx * (w * 0.5 - 0.02)
        mb.cylinder_between(_b(xx, 0.0, z - d1 * 0.5), _b(xx, h1, z - d1 * 0.5 + 0.03), 0.016, "alu", segments=12)
        mb.cylinder_between(_b(xx, 0.0, z + d1 * 0.5), _b(xx, h2, z + d1 * 0.5 - 0.04), 0.016, "alu", segments=12)
        mb.cylinder_between(_b(xx, h1 - 0.02, z - d1 * 0.5 + 0.03), _b(xx, h2 - 0.02, z + 0.02), 0.014, "alu", segments=12)
        for sz in (-1.0, 1.0):
            mb.box(S(0.05, 0.02, 0.05), _b(xx, 0.01, z + sz * d1 * 0.5), "tread")
    # 踏み板（木）と滑り止め
    for y, zc, depth in ((h1, z - d1 * 0.5 + 0.12, 0.22), (h2, z + 0.1, 0.26)):
        mb.box(S(w, 0.025, depth), _b(x, y, zc), "wood")
        for k in range(4):
            mb.box(S(w - 0.08, 0.004, 0.02), _b(x, y + 0.0145, zc - depth * 0.36 + k * depth * 0.24), "tread")
    obj = mb_build(mb, col, {"alu": M["stool_alu"], "tread": M["stool_tread"], "wood": M["stool_wood"]}, bevel=0.003)
    set_origin(obj, (x, 0.0, z))
    obj["lsb_res"] = [1024, 1024]
    return obj


def build(col):
    labels = make_labels()
    planes = {"emblem": emblem_plane(), "printout": printout_plane(), "straw": straw_plane()}
    planes.update(book_planes())
    M = materials(labels, planes)
    objs = build_lectern(col, M)
    objs += build_books(col, M)
    objs.append(build_printouts(col, M))
    objs += build_teacup(col, M)
    objs.append(build_chalk_dish(col, M))
    objs.append(build_whistle(col, M))
    objs.append(build_desk_lamp(col, M))
    objs.append(build_step_stool(col, M))
    return objs

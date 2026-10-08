"""教室の大物と脇役の小道具（実写版、docs/lecture_hall_plan.md の 1d）。

床（板張りの舞台: 幅 0.15 m の板を乱尺で、板ごとに色むら、鋼の縁と皿ねじ）、本棚（合板と背表紙の題名つきの
バインダー・本・ファイル箱）、展示台（ドレープのあるテーブルクロスと名札）、消火器、工具箱、ごみ箱（丸めた紙）、
バケツと雑巾、ほうき・ちりとり、練習レールのカラーコーンと「実習中」の看板、昼食の弁当（ふだんは隠す:
obj["lsb_timeprop"] = "lunch"）。位置は今の小道具と同じ（lsb_props の定数）。
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
from lsb_props import DESK_XS, DESK_Z, PLATFORM_CENTER, PLATFORM_SIZE

PLANK_W = 0.15
FLOOR_TOP = 0.08


# ------------------------------------------------------------------ labels

def make_labels():
    out = {}
    titles = [("安全マニュアル", "#2E6FBF"), ("刃の点検記録 2026", "#C8463A"), ("実習の手引き", "#3C9A5F"),
              ("出席簿 控え", "#1D2B4A"), ("小テスト 第1〜3講", "#E0A52A"), ("回転数の表", "#6A4C93"),
              ("避難経路図", "#C8463A"), ("台車の取扱説明書", "#2E6FBF"), ("授業計画 後期", "#3C9A5F"),
              ("ゴドーくん 名簿", "#E0A52A")]
    # 背表紙の帯（1 本ごとに 1 列の縦長の画像を並べたアトラス: 10 列 × 1 行、各 102×1024）
    c = LB.Canvas("binder_spines", 1024, 1024, bg="#000000")
    for i, (title, color) in enumerate(titles):
        x = i * 102.4
        c.rect(x, 0, 102.4, 1024, color)
        c.rect(x + 12, 520, 78, 360, "#F4F2EA")
        for k, ch in enumerate(title[:9]):
            c.text(x + 51, 840 - k * 38, ch, 30, "#1E1E1E", align="center", valign="center", weight="medium")
        c.circle(x + 51, 300, 22, "#1E1E1E")
        c.circle(x + 51, 300, 14, "#5A5A5A")
    out["binder_spines"] = c.save()
    c = LB.Canvas("exhibit_placard", 1024, 512, bg="#F7F6F0")
    c.rect(0, 420, 1024, 92, "#1E3A5A")
    c.text(512, 450, "展示", 52, "#F7F6F0", align="center")
    c.text(512, 280, "連結チップソー", 96, "#1E3A5A", align="center")
    c.text(512, 170, "1/22 模型　8 枚刃・昇降式", 48, "#333333", align="center", weight="medium")
    c.text(512, 60, "さわらないでください", 40, "#C62828", align="center", weight="medium")
    out["placard"] = c.save()
    c = LB.Canvas("extinguisher_label", 1024, 768, bg="#D32F2F")
    c.rect(60, 60, 904, 648, "#F4F2EA")
    c.text(512, 560, "消火器", 140, "#C62828", align="center")
    c.text(512, 430, "ABC 粉末 10 型", 64, "#1E1E1E", align="center", weight="medium")
    c.rect(150, 250, 220, 120, "#F2F2F2")
    c.text(260, 290, "普通", 44, "#1E1E1E", align="center", weight="medium")
    c.rect(402, 250, 220, 120, "#F2C230")
    c.text(512, 290, "油", 44, "#1E1E1E", align="center", weight="medium")
    c.rect(654, 250, 220, 120, "#2E6FBF")
    c.text(764, 290, "電気", 44, "#F2F2F2", align="center", weight="medium")
    c.text(512, 130, "使用前にピンを抜く", 48, "#1E1E1E", align="center", weight="medium")
    out["extinguisher"] = c.save()
    c = LB.Canvas("sign_practice", 1024, 1024, bg="#F4C500")
    c.rect(0, 800, 1024, 224, "#141414")
    c.text(512, 860, "実習中", 150, "#F4C500", align="center")
    c.poly([(512, 700), (250, 260), (774, 260)], "#141414")
    c.poly([(512, 620), (318, 300), (706, 300)], "#F4C500")
    c.rect(492, 400, 40, 150, "#141414")
    c.circle(512, 350, 24, "#141414")
    c.text(512, 120, "レールに近づかない", 72, "#141414", align="center")
    out["sign"] = c.save()
    c = LB.Canvas("gauge_face", 256, 256, bg="#F4F4F4")
    c.ring(128, 128, 80, 112, "#D32F2F", a0=math.radians(200), a1=math.radians(260))
    c.ring(128, 128, 80, 112, "#2E7D32", a0=math.radians(95), a1=math.radians(200))
    c.ring(128, 128, 80, 112, "#D32F2F", a0=math.radians(-20), a1=math.radians(95))
    c.line(128, 128, 128 + 90 * math.cos(math.radians(150)), 128 + 90 * math.sin(math.radians(150)), 8, "#1E1E1E")
    out["gauge"] = c.save()
    return out


# ------------------------------------------------------------------ materials

def materials(labels, planes):
    M = {}
    M["plank"] = P.wood("Floor_Plank", "#B5834C", "#8A5B2E", 5.5, "X", 0.5, varnish=0.25, worn=0.45, per_island=0.12)
    M["floor_steel"] = P.powder_coat("Floor_Edge", "#4B5157", 0.45, 0.8)
    M["screw"] = P.aluminum("Screw", "#9EA3A8", 0.35, "X")
    M["ply"] = P.wood("Shelf_Ply", "#C59B6B", "#A57A4A", 8.0, "Z", 0.5, varnish=0.2, worn=0.4)
    M["ply_edge"] = P.wood("Shelf_Edge", "#B98B57", "#8E6338", 12.0, "X", 0.5, varnish=0.2, worn=0.6)
    M["binders"] = P.plastic("Binder_Spines", "#2E6FBF", 0.35, 0.3, labels["binder_spines"], planes["binders"])
    M["binder_side"] = P.plastic("Binder_Side", "#3A4A5A", 0.4, 0.3)
    M["book_colors"] = [P.paper(f"Book_{k}", c, 0.55) for k, c in
                        enumerate(("#7B2D26", "#24476B", "#2F5D3A", "#C9A227", "#5B3A6B", "#DCD6C8"))]
    M["paper"] = P.paper("Shelf_Paper", "#F2F0E6", 0.85)
    M["filebox"] = P.paper("FileBox", "#C7A87C", 0.8, None, None, 1.6)
    M["cloth"] = P.cloth("Exhibit_Cloth", "#1E3A6A", 900.0)
    M["table_leg"] = P.powder_coat("Exhibit_Leg", "#2F3439", 0.45, 0.5)
    M["placard"] = P.plastic("Exhibit_Placard", "#F7F6F0", 0.3, 0.2, labels["placard"], planes["placard"])
    M["acrylic_base"] = P.plastic("Placard_Stand", "#2A2D31", 0.3)
    M["ext_body"] = P.powder_coat("Extinguisher_Body", "#D32F2F", 0.35, 0.3)
    M["ext_label"] = P.paper("Extinguisher_Label", "#D32F2F", 0.5, labels["extinguisher"], planes["extinguisher"], 0.3)
    M["ext_black"] = P.plastic("Extinguisher_Black", "#1A1B1D", 0.45)
    M["ext_metal"] = P.aluminum("Extinguisher_Metal", "#C3C7CB", 0.25, "Z")
    M["ext_gauge"] = P.painted_print("Extinguisher_Gauge", labels["gauge"], planes["gauge"], "#F4F4F4", 0.2)
    M["ext_pin"] = P.plastic("Extinguisher_Pin", "#F2C230", 0.35)
    M["toolbox"] = P.powder_coat("Toolbox_Red", "#B71C1C", 0.4, 0.7)
    M["toolbox_metal"] = P.aluminum("Toolbox_Latch", "#BFC4C9", 0.3, "X")
    M["tools"] = P.plastic("Toolbox_Handles", "#F2C230", 0.4)
    M["bin"] = P.plastic("Bin_Gray", "#7E868D", 0.5, 0.6)
    M["crumple"] = P.paper("Crumpled", "#F0EEE6", 0.85, None, None, 2.0)
    M["bucket"] = P.plastic("Bucket_Blue", "#2E6FBF", 0.35, 0.5)
    M["bucket_handle"] = P.aluminum("Bucket_Handle", "#B9BEC3", 0.3, "Z")
    M["rag"] = P.cloth("Rag", "#EDEBE4", 1300.0)
    M["broom_handle"] = P.wood("Broom_Handle", "#C49A64", "#A07444", 14.0, "Z", 0.5, varnish=0.4)
    M["broom_bristle"] = P.felt("Broom_Bristle", "#B49A62", (0.0, 0.0, -1.0))
    M["dustpan"] = P.plastic("Dustpan", "#3C9A5F", 0.4, 0.6)
    M["cone"] = P.plastic("Cone_Orange", "#F26A1B", 0.45, 0.8)
    M["cone_band"] = P.plastic("Cone_Reflect", "#F4F4F0", 0.2, 0.3)
    M["cone_base"] = P.rubber("Cone_Base", "#1A1B1D")
    M["sign"] = P.plastic("Sign_Practice", "#F4C500", 0.4, 0.6, labels["sign"], planes["sign"])
    M["sign_frame"] = P.plastic("Sign_Frame", "#F4C500", 0.45, 0.7)
    M["bento_box"] = [P.plastic(f"Bento_{k}", c, 0.25, 0.3) for k, c in enumerate(("#C62828", "#1E3A5A", "#F2C230"))]
    M["furoshiki"] = [P.cloth(f"Furoshiki_{k}", c, 1100.0) for k, c in enumerate(("#3C9A5F", "#E57373", "#5C6BC0"))]
    return M


# ------------------------------------------------------------------ floor

def build_floor(col, M):
    """板張りの舞台: 幅 0.15 m の板を 1.2〜2.4 m の乱尺で（端の継ぎ目をずらす）、板と板の間に 2 mm の目地、
    周りは鋼の山形の縁と皿ねじ。"""
    cx, cz = PLATFORM_CENTER
    w, d = PLATFORM_SIZE
    mb = MeshBuilder("PRP_Platform")
    rng = random.Random(21)
    rows = int(round(d / PLANK_W))
    for r in range(rows):
        z = cz - d * 0.5 + (r + 0.5) * (d / rows)
        x0 = cx - w * 0.5
        pos = -rng.uniform(0.0, 1.8)
        while pos < w:
            length = rng.uniform(1.2, 2.4)
            a = max(pos, 0.0)
            b = min(pos + length, w)
            if b - a > 0.05:
                mb.box(S(b - a - 0.003, 0.05, d / rows - 0.003), _b(x0 + (a + b) * 0.5, FLOOR_TOP - 0.025, z), "plank")
            pos += length
    obj = mb_build(mb, col, {"plank": M["plank"]}, bevel=0.0015)
    obj["lsb_res"] = [4096, 4096]
    apply_floor_uv(obj)
    # 鋼の縁・下板・皿ねじは別のオブジェクト（板の平面の UV と重ならないように）
    mb = MeshBuilder("PRP_PlatformEdge")
    mb.box(S(w - 0.02, 0.03, d - 0.02), _b(cx, 0.015, cz), "edge")
    bar = 0.08
    for sx in (-1.0, 1.0):
        mb.box(S(bar, FLOOR_TOP + 0.004, d + bar), _b(cx + sx * (w * 0.5 + bar * 0.5), (FLOOR_TOP + 0.004) * 0.5, cz), "edge")
    for sz in (-1.0, 1.0):
        mb.box(S(w + bar * 2, FLOOR_TOP + 0.004, bar), _b(cx, (FLOOR_TOP + 0.004) * 0.5, cz + sz * (d * 0.5 + bar * 0.5)), "edge")
    # 縁の皿ねじ（0.5 m ごと）
    for k in range(int(w / 0.5) + 1):
        for sz in (-1.0, 1.0):
            mb.cylinder(0.008, 0.003, _b(cx - w * 0.5 + k * 0.5, FLOOR_TOP + 0.005, cz + sz * (d * 0.5 + bar * 0.5)),
                        "screw", segments=12)
    edge = mb_build(mb, col, {"edge": M["floor_steel"], "screw": M["screw"]}, bevel=0.0015)
    edge["lsb_res"] = [2048, 2048]
    return [obj, edge]


def apply_floor_uv(obj):
    """床の板は真上からの平面の UV（板が 700 枚あり、島に分けると詰められない）。上を向いた面だけを 0..0.98 に
    投影し、側面と裏（板の厚み 5 cm、ほとんど見えない）は右上の隅の 1 点へ寄せる（面積 0 なので焼きは書かず、
    隅の色は焼きの余白で木の色になる）。"""
    cx, cz = PLATFORM_CENTER
    w, d = PLATFORM_SIZE
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UVMap")
    lo = _b(cx + w * 0.5 + 0.1, 0.0, cz - d * 0.5 - 0.1)
    span_x, span_y = w + 0.2, d + 0.2
    for poly in me.polygons:
        top = poly.normal.z > 0.7
        for li in poly.loop_indices:
            if top:
                co = me.vertices[me.loops[li].vertex_index].co
                uv.data[li].uv = ((lo.x - co.x) / span_x * 0.98, (co.y - lo.y) / -span_y * 0.98)
            else:
                uv.data[li].uv = (0.995, 0.995)
    obj["lsb_uv"] = "keep"


# ------------------------------------------------------------------ bookshelf

SHELF = (-5.6, 8.8)
SHELF_W, SHELF_D, SHELF_H = 2.0, 0.42, 2.2


def build_bookshelf(col, M):
    """本棚: 合板の箱と 3 枚の棚板（縁は無垢）、背板。棚に背表紙の題名つきのバインダー、本、ファイル箱、紙の束。"""
    x, z = SHELF
    w, d, h = SHELF_W, SHELF_D, SHELF_H
    mb = MeshBuilder("PRP_Bookshelf")
    for sx in (-1.0, 1.0):
        mb.box(S(0.025, h, d), _b(x + sx * (w * 0.5 - 0.0125), h * 0.5, z), "ply")
        mb.box(S(0.026, h, 0.012), _b(x + sx * (w * 0.5 - 0.0125), h * 0.5, z - d * 0.5 + 0.006), "edge")
    mb.box(S(w, h, 0.012), _b(x, h * 0.5, z + d * 0.5 - 0.006), "ply")
    mb.box(S(w, 0.025, d), _b(x, h - 0.0125, z), "ply")
    mb.box(S(w - 0.05, 0.08, 0.02), _b(x, 0.04, z - d * 0.5 + 0.03), "edge")
    levels = [0.08, 0.78, 1.48]
    for y in levels:
        mb.box(S(w - 0.05, 0.022, d - 0.02), _b(x, y, z), "ply")
        mb.box(S(w - 0.05, 0.024, 0.012), _b(x, y, z - d * 0.5 + 0.016), "edge")
    obj = mb_build(mb, col, {"ply": M["ply"], "edge": M["ply_edge"]}, bevel=0.002)
    obj["lsb_res"] = [2048, 2048]
    out = [obj]
    # バインダー（1 段目と 2 段目）: 背表紙は 10 本分の画像の列を 1 本ずつ使う（u をずらす）
    rng = random.Random(8)
    bb = MeshBuilder("PRP_Binders")
    idx = 0
    spines = []
    for li, y in enumerate(levels[:1]):
        bx = x - w * 0.5 + 0.06
        for k in range(10):
            bw = 0.075
            bh = 0.33
            bb.box(S(bw, bh, d - 0.1), _b(bx + bw * 0.5, y + 0.011 + bh * 0.5, z + 0.01), "side")
            bb.box(S(bw - 0.004, bh - 0.004, 0.004), _b(bx + bw * 0.5, y + 0.011 + bh * 0.5, z + 0.01 - (d - 0.1) * 0.5 - 0.002),
                   "spine")
            spines.append((idx, bx, bw, y + 0.011, bh))
            idx += 1
            bx += bw + 0.006
    bobj = mb_build(bb, col, {"side": M["binder_side"], "spine": M["binders"]}, bevel=0.0015)
    bobj["lsb_res"] = [1024, 1024]
    bobj["lsb_spines"] = len(spines)
    out.append(bobj)
    # 本と紙の束、ファイル箱（各段の残り）
    kb = MeshBuilder("PRP_Books")
    for li, y in enumerate(levels):
        bx = x - w * 0.5 + (0.9 if li == 0 else 0.06)
        end = x + w * 0.5 - 0.06
        while bx < end - 0.1:
            if rng.random() < 0.12 and li == 2:
                kb.box(S(0.28, 0.24, 0.33), _b(bx + 0.14, y + 0.011 + 0.12, z), "filebox")
                bx += 0.3
                continue
            bw = rng.uniform(0.025, 0.055)
            bh = rng.uniform(0.22, 0.31)
            lean = math.radians(rng.uniform(-4.0, 4.0)) if rng.random() < 0.15 else 0.0
            color = f"book{rng.randrange(6)}"
            kb.box(S(bw, bh, rng.uniform(0.16, 0.22)), _b(bx + bw * 0.5, y + 0.011 + bh * 0.5, z - 0.06), color,
                   rotation=Matrix.Rotation(lean, 3, "Y"))
            bx += bw + 0.003
            if rng.random() < 0.08:
                bx += 0.06
        if li == 1:
            for k in range(14):
                kb.box(S(0.26, 0.0025, 0.19), _b(end - 0.2, y + 0.012 + k * 0.0026, z - 0.03), "paper",
                       rotation=Matrix.Rotation(math.radians(rng.uniform(-3, 3)), 3, "Z"))
    mats = {f"book{k}": M["book_colors"][k] for k in range(6)}
    mats.update({"filebox": M["filebox"], "paper": M["paper"]})
    kobj = mb_build(kb, col, mats, bevel=0.0012)
    kobj["lsb_res"] = [2048, 2048]
    out.append(kobj)
    return out


def binders_plane():
    """背表紙の画像: 1 段目の 10 本を、画像の 10 列に左から対応させる（見る人の左 = Godot +x が列 0）。"""
    x, z = SHELF
    bx0 = x - SHELF_W * 0.5 + 0.06
    width = 10 * 0.081
    return {"origin": tuple(_b(bx0 + width, 0.08 + 0.011, z)), "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0),
            "u_len": width, "v_len": 0.33}


# ------------------------------------------------------------------ exhibit table

EXHIBIT = (-3.9, 5.4)
EX_W, EX_D, EX_H = 5.6, 1.5, 0.9


def build_exhibit(col, M):
    """展示台: 折りたたみ机の脚、天板を覆うテーブルクロス（手前と両脇に垂れ、裾に波打つひだ）、名札のスタンド。"""
    x, z = EXHIBIT
    w, d, h = EX_W, EX_D, EX_H
    mb = MeshBuilder("PRP_ExhibitTable")
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            mb.cylinder(0.02, h - 0.04, _b(x + sx * (w * 0.5 - 0.15), (h - 0.04) * 0.5, z + sz * (d * 0.5 - 0.12)), "leg",
                        segments=12)
    out = [mb_build(mb, col, {"leg": M["table_leg"]}, bevel=0.0)]
    out[-1]["lsb_res"] = [512, 512]
    # クロス: 天板の面 + 垂れ（グリッドを作って縁から下へ折り、裾をひだで揺らす）
    bm = bmesh.new()
    drop = h - 0.12
    nx, nz, ny = 112, 30, 10
    top_y = h + 0.006
    def drape_point(u, v):
        """u: 0..1 を横、v: 0..1 を「手前の垂れ → 天板 → 奥」と見なした 1 枚の布の座標（両脇の垂れは別に作る）。"""
        return u, v
    grid = []
    # 手前の垂れ（v 0..0.3）と天板（0.3..1）
    for j in range(nz + ny + 1):
        row = []
        for i in range(nx + 1):
            u = i / nx
            px = x - w * 0.5 - 0.02 + (w + 0.04) * u
            if j <= ny:
                t = j / ny  # 0 = 裾、1 = 天板の縁
                fold = 0.025 * math.sin(u * math.tau * 22.0 + 0.7) * (1.0 - t) ** 1.5
                py = top_y - drop * (1.0 - t)
                pz = z - d * 0.5 - 0.02 - 0.015 * (1.0 - t) + fold
                if t > 0.9:
                    k = (t - 0.9) / 0.1
                    py = top_y - (1.0 - k) * 0.02
                    pz = z - d * 0.5 - 0.02 + k * 0.02
            else:
                t = (j - ny) / nz
                py = top_y + 0.002 * math.sin(u * 13.0 + t * 7.0)
                pz = z - d * 0.5 + d * t
            row.append(bm.verts.new(_b(px, py, pz)))
        grid.append(row)
    for j in range(len(grid) - 1):
        for i in range(nx):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            f.smooth = True
    # 両脇の垂れ
    for sx in (-1.0, 1.0):
        side = []
        for j in range(ny + 1):
            row = []
            for i in range(24 + 1):
                t = j / ny
                s = i / 24
                pz = z - d * 0.5 - 0.02 + (d + 0.02) * s
                fold = 0.02 * math.sin(s * math.tau * 6.0 + 1.3) * (1.0 - t) ** 1.5
                px = x + sx * (w * 0.5 + 0.02 + 0.012 * (1.0 - t) + fold)
                py = top_y - drop * (1.0 - t)
                row.append(bm.verts.new(_b(px, py, pz)))
            side.append(row)
        for j in range(ny):
            for i in range(24):
                quad = (side[j][i], side[j][i + 1], side[j + 1][i + 1], side[j + 1][i])
                f = bm.faces.new(quad if sx > 0 else tuple(reversed(quad)))
                f.smooth = True
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sol = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    for v in [g for g in sol["geom"] if isinstance(g, bmesh.types.BMVert)]:
        v.co.z -= 0.002
    me = bpy.data.meshes.new("PRP_ExhibitCloth")
    bm.to_mesh(me)
    bm.free()
    cloth = bpy.data.objects.new("PRP_ExhibitCloth", me)
    col.objects.link(cloth)
    cloth.data.materials.append(M["cloth"])
    cloth["lsb_res"] = [2048, 2048]
    out.append(cloth)
    # 名札（台の右手前、アクリルの L 字のスタンド）
    pb = MeshBuilder("PRP_ExhibitPlacard")
    px, pz = x + 2.3, z - 0.5
    lean = Matrix.Rotation(math.radians(-15.0), 3, "X")
    pb.box(S(0.5, 0.25, 0.006), _b(px, h + 0.135, pz), "card", rotation=lean)
    pb.box(S(0.5, 0.006, 0.18), _b(px, h + 0.009, pz + 0.07), "stand")
    pb.box(S(0.5, 0.27, 0.004), _b(px, h + 0.14, pz + 0.006), "stand", rotation=lean)
    out.append(mb_build(pb, col, {"card": M["placard"], "stand": M["acrylic_base"]}, bevel=0.0015))
    out[-1]["lsb_res"] = [1024, 1024]
    return out


def placard_plane():
    x, z = EXHIBIT
    px, pz = x + 2.3, z - 0.5
    # 傾いた札: 平面は Blender の X と、15° 倒した上向き
    up = Vector((0.0, math.sin(math.radians(15.0)), math.cos(math.radians(15.0))))
    origin = _b(px + 0.25, EX_H + 0.135, pz) - up * 0.125
    return {"origin": tuple(origin), "u_axis": (-1.0, 0.0, 0.0), "v_axis": tuple(up), "u_len": 0.5, "v_len": 0.25}


# ------------------------------------------------------------------ small things around the room

def build_extinguisher(col, M):
    """消火器（10 型）: 赤い胴（ラベル）、黒いレバーと持ち手、黄色い安全ピン、圧力計、黒いホースとノズル、樹脂の台。"""
    x, z = -4.3, 9.0
    mb = MeshBuilder("PRP_Extinguisher")
    r, h = 0.085, 0.5
    mb.cylinder(0.12, 0.04, _b(x, 0.02, z), "black", segments=32)
    mb.cylinder(r, h, _b(x, 0.04 + h * 0.5, z), "body", segments=40)
    mb.sphere(r, _b(x, 0.04 + h, z), "body", scale=(1.0, 1.0, 0.55), segments=40, rings=12)
    mb.cylinder(r * 1.002, 0.24, _b(x, 0.04 + h * 0.48, z), "label", segments=40)
    top = 0.04 + h + r * 0.55
    mb.cylinder(0.024, 0.06, _b(x, top + 0.02, z), "metal", segments=20)
    mb.box(S(0.035, 0.022, 0.16), _b(x, top + 0.06, z - 0.04), "black")
    mb.box(S(0.035, 0.018, 0.15), _b(x, top + 0.09, z - 0.03), "black", rotation=Matrix.Rotation(math.radians(-14), 3, "X"))
    mb.torus(0.012, 0.003, _b(x + 0.03, top + 0.07, z - 0.02), "pin", rotation=RY, segments=16, rings=6)
    mb.cylinder(0.022, 0.012, _b(x - 0.03, top + 0.02, z - 0.03), "metal", rotation=RX, segments=20)
    mb.cylinder(0.019, 0.004, _b(x - 0.03, top + 0.02, z - 0.037), "gauge", rotation=RX, segments=20)
    pts = [(x + 0.02, top + 0.02, z - 0.02), (x + 0.07, top - 0.05, z - 0.06), (x + 0.1, 0.32, z - 0.1),
           (x + 0.09, 0.15, z - 0.12)]
    for a, b in zip(pts, pts[1:]):
        mb.cylinder_between(_b(*a), _b(*b), 0.011, "black", segments=12)
    mb.cylinder_between(_b(*pts[-1]), _b(pts[-1][0] - 0.005, 0.1, pts[-1][2]), 0.016, "black", radius2=0.012, segments=14)
    obj = mb_build(mb, col, {"black": M["ext_black"], "body": M["ext_body"], "label": M["ext_label"],
                             "metal": M["ext_metal"], "pin": M["ext_pin"], "gauge": M["ext_gauge"]}, bevel=0.0015)
    obj["lsb_res"] = [1024, 1024]
    return obj


def extinguisher_planes():
    x, z = -4.3, 9.0
    r = 0.085 * 1.002
    # ラベルは正面（Godot -z）の弧に貼る: 平面の投影で十分（弧の幅 0.18 m）
    label = {"origin": tuple(_b(x + 0.09, 0.04 + 0.5 * 0.48 - 0.12, z - r)), "u_axis": (-1.0, 0.0, 0.0),
             "v_axis": (0.0, 0.0, 1.0), "u_len": 0.18, "v_len": 0.135}
    top = 0.04 + 0.5 + 0.085 * 0.55
    gauge = {"origin": tuple(_b(x - 0.03 + 0.019, top + 0.02 - 0.019, z - 0.04)), "u_axis": (-1.0, 0.0, 0.0),
             "v_axis": (0.0, 0.0, 1.0), "u_len": 0.038, "v_len": 0.038}
    return label, gauge


def build_toolbox(col, M):
    """赤い鋼の工具箱（ふたが少し開いて、黄色い持ち手の工具がのぞく）。"""
    x, z = -6.4, 6.8
    mb = MeshBuilder("PRP_Toolbox")
    w, d, h = 0.5, 0.24, 0.2
    mb.box(S(w, h, d), _b(x, h * 0.5, z), "red")
    hinge = Vector((0.0, 0.0, 0.0))
    lid = Matrix.Rotation(math.radians(-24.0), 3, "X")
    mb.box(S(w + 0.01, 0.05, d + 0.01), _b(x, h + 0.04, z + 0.03), "red", rotation=lid)
    mb.box(S(0.22, 0.025, 0.03), _b(x, h + 0.085, z + 0.02), "black", rotation=lid)
    for sx in (-1.0, 1.0):
        mb.box(S(0.04, 0.03, 0.012), _b(x + sx * 0.18, h - 0.01, z - d * 0.5 - 0.006), "metal")
    mb.cylinder(0.014, 0.22, _b(x - 0.08, h + 0.02, z - 0.03), "tools", rotation=RY, segments=12)
    mb.cylinder(0.011, 0.2, _b(x + 0.1, h + 0.028, z), "tools", rotation=RY, segments=12)
    obj = mb_build(mb, col, {"red": M["toolbox"], "black": M["ext_black"], "metal": M["toolbox_metal"],
                             "tools": M["tools"]}, bevel=0.004, segments=2)
    obj["lsb_res"] = [1024, 1024]
    return obj


def build_bin(col, M):
    """ごみ箱（グレーの樹脂、上の縁が厚い）と丸めた紙。"""
    x, z = 4.6, 5.0
    bm = bmesh.new()
    seg = 40
    prof = [(0.0, 0.0), (0.16, 0.0), (0.165, 0.01), (0.2, 0.46), (0.215, 0.47), (0.215, 0.5), (0.2, 0.5), (0.19, 0.48),
            (0.155, 0.03), (0.0, 0.03)]
    rings = []
    for r, hh in prof:
        rings.append([bm.verts.new(_b(x + r * math.cos(math.tau * i / seg), hh, z + r * math.sin(math.tau * i / seg)))
                      for i in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            f = bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
            f.smooth = True
            f.material_index = 0
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    rng = random.Random(2)
    for k in range(4):
        g = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.055)
        for v in g["verts"]:
            v.co = v.co * (1.0 + rng.uniform(-0.25, 0.25))
            v.co += _b(x + rng.uniform(-0.08, 0.08), 0.43 + rng.uniform(0.0, 0.07), z + rng.uniform(-0.08, 0.08))
        for f in {f for v in g["verts"] for f in v.link_faces}:
            f.material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("PRP_Bin")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("PRP_Bin", me)
    col.objects.link(obj)
    obj.data.materials.append(M["bin"])
    obj.data.materials.append(M["crumple"])
    obj["lsb_res"] = [1024, 1024]
    return obj


def build_bucket_and_rag(col, M):
    """青いバケツ（取っ手）と、縁に掛けた雑巾（濡れ拭き用、D38）。"""
    x, z = -6.3, -0.2
    out = []
    bm = bmesh.new()
    seg = 40
    prof = [(0.0, 0.0), (0.13, 0.0), (0.135, 0.008), (0.165, 0.29), (0.175, 0.3), (0.172, 0.31), (0.16, 0.3), (0.13, 0.02),
            (0.0, 0.02)]
    rings = []
    for r, hh in prof:
        rings.append([bm.verts.new(_b(x + r * math.cos(math.tau * i / seg), hh, z + r * math.sin(math.tau * i / seg)))
                      for i in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            f = bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
            f.smooth = True
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("PRP_Bucket")
    bm.to_mesh(me)
    bm.free()
    bucket = bpy.data.objects.new("PRP_Bucket", me)
    col.objects.link(bucket)
    bucket.data.materials.append(M["bucket"])
    mb = MeshBuilder("PRP_BucketHandle")
    mb.torus(0.17, 0.004, _b(x, 0.3, z), "h", rotation=RX @ Matrix.Rotation(math.radians(0), 3, "Z"), segments=32,
             rings=6, sweep=math.radians(180.0))
    handle = mb_build(mb, col, {"h": M["bucket_handle"]})
    handle["lsb_res"] = [256, 256]
    bucket["lsb_res"] = [1024, 1024]
    out += [bucket, handle]
    # 雑巾: 縁に掛けた布（内と外に垂れる、しわ）
    bm = bmesh.new()
    nx, ny = 20, 16
    grid = []
    for j in range(ny + 1):
        row = []
        t = j / ny
        for i in range(nx + 1):
            u = (i / nx - 0.5) * 0.24
            a = math.radians(70.0) + u / 0.17
            if t < 0.5:
                rr = 0.178 + 0.002
                hh = 0.31 - (0.5 - t) * 0.36
                rr += 0.006 * math.sin(i * 1.7 + j * 0.9)
            else:
                rr = 0.155
                hh = 0.31 - (t - 0.5) * 0.2
            row.append(bm.verts.new(_b(x + rr * math.cos(a), hh + 0.004 * math.sin(i * 2.3), z + rr * math.sin(a))))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            f.smooth = True
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("PRP_Rag")
    bm.to_mesh(me)
    bm.free()
    rag = bpy.data.objects.new("PRP_Rag", me)
    col.objects.link(rag)
    rag.data.materials.append(M["rag"])
    mod = rag.modifiers.new("Solid", "SOLIDIFY")
    mod.thickness = 0.004
    rag["lsb_res"] = [512, 512]
    out.append(rag)
    return out


def build_broom(col, M):
    """ほうき（木の柄、きびの穂）とちりとり。本棚の脇に立てかける。"""
    x, z = -4.42, 8.75
    out = []
    mb = MeshBuilder("PRP_Broom")
    top = Vector((x + 0.06, 1.25, z + 0.02))
    foot = Vector((x - 0.05, 0.28, z - 0.18))
    mb.cylinder_between(_b(*foot), _b(*top), 0.013, "handle", segments=12)
    head = foot + (foot - top).normalized() * 0.02
    for k in range(9):
        a = (k - 4) * 0.022
        mb.cylinder_between(_b(head.x + a * 0.3, head.y, head.z), _b(head.x + a, 0.005, head.z - 0.07 + abs(a) * 0.2), 0.016,
                            "bristle", radius2=0.024, segments=8)
    mb.box(S(0.12, 0.03, 0.04), _b(head.x, head.y + 0.01, head.z), "handle")
    out.append(mb_build(mb, col, {"handle": M["broom_handle"], "bristle": M["broom_bristle"]}, bevel=0.0))
    out[-1]["lsb_res"] = [512, 512]
    db = MeshBuilder("PRP_Dustpan")
    dx, dz = x - 0.2, z - 0.32
    db.box(S(0.26, 0.004, 0.2), _b(dx, 0.004, dz), "pan")
    for sx in (-1.0, 1.0):
        db.box(S(0.004, 0.06, 0.2), _b(dx + sx * 0.13, 0.03, dz), "pan")
    db.box(S(0.26, 0.07, 0.004), _b(dx, 0.035, dz + 0.1), "pan")
    db.cylinder_between(_b(dx, 0.05, dz + 0.1), _b(dx, 0.32, dz + 0.16), 0.012, "pan", segments=10)
    out.append(mb_build(db, col, {"pan": M["dustpan"]}, bevel=0.0015))
    out[-1]["lsb_res"] = [512, 512]
    return out


def build_cones_and_sign(col, M):
    """カラーコーン 3 本（反射の帯、ゴムの台）と、A 型の「実習中」の看板（練習レールの脇）。"""
    out = []
    for k, (x, z) in enumerate(((-3.4, -0.9), (-5.4, -0.9), (-3.4, 3.9))):
        mb = MeshBuilder(f"PRP_Cone_{k}")
        mb.box(S(0.4, 0.035, 0.4), _b(x, 0.0175, z), "base")
        mb.cone(0.16, 0.62, _b(x, 0.035 + 0.31, z), "cone", segments=32)
        mb.cylinder(0.1, 0.09, _b(x, 0.36, z), "band", segments=32, radius2=0.082)
        mb.cylinder(0.064, 0.06, _b(x, 0.5, z), "band", segments=32, radius2=0.053)
        o = mb_build(mb, col, {"base": M["cone_base"], "cone": M["cone"], "band": M["cone_band"]}, bevel=0.003)
        o["lsb_res"] = [512, 512]
        out.append(o)
    mb = MeshBuilder("PRP_SignPractice")
    x, z = -5.9, 1.6
    for s in (-1.0, 1.0):
        rot = Matrix.Rotation(math.radians(s * 14.0), 3, "X")
        mb.box(S(0.6, 0.8, 0.025), _b(x, 0.41, z + s * 0.1), "panel" if s < 0 else "frame", rotation=rot)
        for sx in (-1.0, 1.0):
            mb.box(S(0.04, 0.84, 0.035), _b(x + sx * 0.3, 0.41, z + s * 0.1), "frame", rotation=rot)
    mb.box(S(0.66, 0.04, 0.24), _b(x, 0.82, z), "frame")
    o = mb_build(mb, col, {"panel": M["sign"], "frame": M["sign_frame"]}, bevel=0.004)
    o["lsb_res"] = [1024, 1024]
    out.append(o)
    return out


def sign_plane():
    x, z = -5.9, 1.6
    rot = Matrix.Rotation(math.radians(-14.0), 3, "X")
    up = rot @ Vector((0.0, 0.0, 1.0))
    center = _b(x, 0.41, z - 0.1)
    origin = center + Vector((0.3, 0.0, 0.0)) - up * 0.4
    return {"origin": tuple(origin), "u_axis": (-1.0, 0.0, 0.0), "v_axis": tuple(up), "u_len": 0.6, "v_len": 0.8}


def build_bentos(col, M):
    """昼食の弁当（風呂敷で包んだ箱）。机 3 台に 1 つずつ。ふだんは Godot が隠す（lsb_timeprop = lunch）。"""
    out = []
    for i, x in enumerate(DESK_XS):
        mb = MeshBuilder(f"PRP_Bento_{i}")
        cx, cy, cz = x + 0.05, 0.725, DESK_Z - 0.05
        mb.box(S(0.2, 0.06, 0.13), _b(cx, cy + 0.03, cz), "box")
        mb.box(S(0.21, 0.012, 0.14), _b(cx, cy + 0.066, cz), "cloth")
        mb.sphere(0.035, _b(cx, cy + 0.085, cz), "cloth", scale=(1.3, 0.8, 0.6), segments=16, rings=8)
        for s in (-1.0, 1.0):
            mb.sphere(0.03, _b(cx + s * 0.045, cy + 0.085, cz + 0.01), "cloth", scale=(1.2, 0.5, 0.5), segments=12, rings=6)
        o = mb_build(mb, col, {"box": M["bento_box"][i], "cloth": M["furoshiki"][i]}, bevel=0.004)
        o["lsb_res"] = [512, 512]
        o["lsb_timeprop"] = "lunch"
        out.append(o)
    return out


def build(col):
    labels = make_labels()
    ext_label, gauge = extinguisher_planes()
    planes = {"binders": binders_plane(), "placard": placard_plane(), "extinguisher": ext_label, "gauge": gauge,
              "sign": sign_plane()}
    M = materials(labels, planes)
    objs = build_floor(col, M)
    objs += build_bookshelf(col, M)
    objs += build_exhibit(col, M)
    objs.append(build_extinguisher(col, M))
    objs.append(build_toolbox(col, M))
    objs.append(build_bin(col, M))
    objs += build_bucket_and_rag(col, M)
    objs += build_broom(col, M)
    objs += build_cones_and_sign(col, M)
    objs += build_bentos(col, M)
    return objs

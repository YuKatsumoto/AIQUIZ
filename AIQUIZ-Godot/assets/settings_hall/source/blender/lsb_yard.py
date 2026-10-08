"""実習場の小道具（実写版、docs/lecture_hall_plan.md の 1e）。practice_yard_props.glb に書き出し、
Godot の PracticeYard（scripts/world/settings_hall/practice_yard.gd）が台車と同じローカル座標に置く。

ローカル座標（Godot、台車と同じ）: +X = 刃の列の向き（操縦席は +X の端、x 10.7〜13.9）、+Z = 前進、原点 = 走行の中心の床。
レールは x = ±11.86 を z 方向に 9 m。台車は z ±1.85、走行で ±2.4 動く。見学のカメラは -z 側の高い所から +x の操縦席を見る。
- 停止線: 両方のレールを横切る白黒の床のテープ（z = ±3.1）と「停止線」のステンシル文字（P128）
- 点検表のボード: 操縦席の先（x 15.2）の脚つきホワイトボード。始業点検の項目、マグネット（P127）
- 合格のハンコ: ボードの脇の折りたたみ机の上の印鑑と朱肉、押した紙（P132）
- 安全柵: 黄黒の縞の A 型のバリケード（奥 +z 側と両端）
- 見学席: 奥（+z 側）の長いベンチ（P134）
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import lsb_label as LB
import lsb_pbr as P
from lsb_board import RX, RY, S, _b, mb_build, set_origin
from lsb_common import MeshBuilder

RAIL_X = 11.86
STOP_Z = 3.1
BOARD_AT = (15.3, -1.4)
TABLE_AT = (15.4, 0.45)


def make_labels():
    out = {}
    c = LB.Canvas("yard_checklist", 1400, 1000, bg="#FAFAF7")
    c.rect(0, 880, 1400, 120, "#1E3A5A")
    c.text(700, 915, "連結チップソー　始業点検", 64, "#FAFAF7", align="center")
    items = ["キーを回す前に周りを見る", "保護カバーの開閉", "計器と表示灯の点検", "レールの上に物がない",
             "刃の回転よし・指差し確認", "停止線で止まれるか"]
    for i, s in enumerate(items):
        y = 770 - i * 118
        c.rect(70, y - 6, 56, 56, "#1E1E1E")
        c.rect(76, y, 44, 44, "#FAFAF7")
        if i < 3:
            c.line(82, y + 24, 96, y + 8, 7, "#C62828")
            c.line(96, y + 8, 118, y + 44, 7, "#C62828")
        c.text(160, y + 6, s, 46, "#1E1E1E", weight="medium")
    c.text(1300, 40, "担当　ゴドー", 34, "#55595F", align="right", weight="medium")
    out["checklist"] = c.save()
    c = LB.Canvas("yard_stopline_text", 1024, 256, bg=(0, 0, 0, 0))
    c.text(512, 64, "停 止 線", 170, "#F4F4F0", align="center")
    out["stop_text"] = c.save()
    c = LB.Canvas("yard_stamp_paper", 724, 1024, bg="#FBFBF7")
    c.text(362, 930, "操作実習　合格証", 52, "#1E1E1E", align="center")
    c.text(120, 780, "氏名　ゴドー", 40, "#1E1E1E", weight="medium")
    c.text(120, 700, "始動・前進・昇降・後退・停止", 34, "#1E1E1E", weight="regular")
    c.ring(520, 360, 120, 140, "#D32F2F")
    c.text(520, 330, "合格", 96, "#D32F2F", align="center")
    out["stamp_paper"] = c.save()
    c = LB.Canvas("yard_stamp_face", 256, 256, bg="#B3261E")
    c.text(128, 92, "合格", 90, "#7A1A14", align="center")
    out["stamp_face"] = c.save()
    return out


def materials(labels, planes):
    M = {}
    M["tape_white"] = P.plastic("Yard_TapeWhite", "#EDEDE6", 0.6, 0.4)
    M["tape_black"] = P.plastic("Yard_TapeBlack", "#18191B", 0.6, 0.4)
    M["stop_text"] = P.plastic("Yard_StopText", "#18191B", 0.6, 0.3, labels["stop_text"], planes["stop_text"])
    M["board"] = P.painted_print("Yard_Checklist", labels["checklist"], planes["checklist"], "#FAFAF7", 0.15)
    M["board_frame"] = P.aluminum("Yard_BoardFrame", "#C3C7CB", 0.4, "X", anodized=True)
    M["stand"] = P.powder_coat("Yard_Stand", "#3B4046", 0.45, 0.5)
    M["rubber"] = P.rubber("Yard_Rubber")
    M["magnet"] = P.magnet("Yard_Magnet", "#D84B4B")
    M["table_top"] = P.plastic("Yard_TableTop", "#E5E1D6", 0.4, 0.4)
    M["paper"] = P.paper("Yard_StampPaper", "#FBFBF7", 0.8, labels["stamp_paper"], planes["stamp_paper"], 0.5)
    M["stamp_wood"] = P.wood("Yard_StampWood", "#D9B47E", "#B98E5A", 18.0, "Z", 0.45, varnish=0.4)
    M["stamp_face"] = P.painted_print("Yard_StampFace", labels["stamp_face"], planes["stamp_face"], "#B3261E", 0.6)
    M["pad"] = P.plastic("Yard_InkPad", "#1E1E1E", 0.3, 0.3)
    M["ink"] = P.felt("Yard_Ink", "#9B1B1B", (0.0, 0.0, 1.0))
    M["barrier_y"] = P.plastic("Yard_BarrierYellow", "#F2C230", 0.45, 0.6)
    M["barrier_k"] = P.plastic("Yard_BarrierBlack", "#16181B", 0.45, 0.6)
    M["bench_wood"] = P.wood("Yard_BenchWood", "#B88A57", "#8F6236", 7.0, "X", 0.5, varnish=0.3, worn=0.5)
    return M


# ------------------------------------------------------------------ pieces

def build_stop_lines(col, M):
    """両方のレールの外側を横切る停止線（幅 0.12 m の白黒の縞のテープ、長さ 1.2 m）と文字。"""
    mb = MeshBuilder("PRP_Yard_StopLines")
    for sz in (-1.0, 1.0):
        for sx in (-1.0, 1.0):
            x0 = sx * RAIL_X
            n = 12
            for k in range(n):
                xx = x0 - 0.6 + (k + 0.5) * (1.2 / n)
                mb.box(S(1.2 / n, 0.002, 0.12), _b(xx, 0.001, sz * STOP_Z), "w" if k % 2 == 0 else "k")
    obj = mb_build(mb, col, {"w": M["tape_white"], "k": M["tape_black"]})
    obj["lsb_res"] = [512, 512]
    tb = MeshBuilder("PRP_Yard_StopText")
    tb.box(S(1.0, 0.002, 0.25), _b(RAIL_X, 0.0012, -(STOP_Z + 0.32)), "t")
    text = mb_build(tb, col, {"t": M["stop_text"]})
    text["lsb_res"] = [1024, 1024]
    return [obj, text]


def build_checklist_board(col, M):
    """脚つきのホワイトボード（キャスター）に始業点検の表。マグネット 2 個。カメラ（-z、-x 側）へ向ける。"""
    x, z = BOARD_AT
    yaw = math.radians(-60.0)
    mb = MeshBuilder("PRP_Yard_Checklist")
    w, h = 1.4, 1.0
    cy = 1.25
    mb.box(S(w, h, 0.02), _b(0.0, cy, 0.0), "board")
    for sy in (-1.0, 1.0):
        mb.box(S(w + 0.04, 0.03, 0.03), _b(0.0, cy + sy * (h * 0.5 + 0.015), 0.0), "frame")
    for sx in (-1.0, 1.0):
        mb.box(S(0.03, h + 0.06, 0.03), _b(sx * (w * 0.5 + 0.015), cy, 0.0), "frame")
        mb.box(S(0.04, cy + h * 0.5, 0.04), _b(sx * (w * 0.5 + 0.05), (cy + h * 0.5) * 0.5, 0.02), "stand")
        mb.box(S(0.06, 0.04, 0.6), _b(sx * (w * 0.5 + 0.05), 0.08, 0.02), "stand")
        for sz in (-1.0, 1.0):
            mb.cylinder(0.03, 0.03, _b(sx * (w * 0.5 + 0.05), 0.03, 0.02 + sz * 0.26), "rubber", rotation=RY, segments=16)
    mb.box(S(w * 0.9, 0.025, 0.06), _b(0.0, cy - h * 0.5 - 0.02, -0.03), "frame")
    for mx in (-0.55, 0.5):
        mb.cylinder(0.03, 0.012, _b(mx, cy + h * 0.5 - 0.05, -0.016), "magnet", rotation=RX, segments=24)
    obj = mb_build(mb, col, {"board": M["board"], "frame": M["board_frame"], "stand": M["stand"],
                             "rubber": M["rubber"], "magnet": M["magnet"]}, bevel=0.003)
    obj.matrix_world = Matrix.Translation(_b(x, 0.0, z)) @ Matrix.Rotation(yaw, 4, "Z")
    obj["lsb_res"] = [2048, 2048]
    return obj


def checklist_plane():
    # 物体の局所座標（回す前）: ボードの面は Blender +Y を向き、見る人の左 = +X
    return {"origin": (0.7, 0.0, 1.25 - 0.5), "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 0.0, 1.0), "u_len": 1.4,
            "v_len": 1.0}


def build_stamp_table(col, M):
    """折りたたみ机に、押した合格証、印鑑（木の柄と朱の印面）、朱肉。"""
    x, z = TABLE_AT
    mb = MeshBuilder("PRP_Yard_StampTable")
    w, d, h = 0.9, 0.5, 0.72
    mb.box(S(w, 0.03, d), _b(x, h - 0.015, z), "top")
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            mb.cylinder(0.014, h - 0.03, _b(x + sx * (w * 0.5 - 0.05), (h - 0.03) * 0.5, z + sz * (d * 0.5 - 0.05)), "stand",
                        segments=12)
    mb.box(S(0.21 * 1.8 * 0.55, 0.002, 0.297 * 1.8 * 0.55), _b(x - 0.12, h + 0.001, z), "paper",
           rotation=Matrix.Rotation(math.radians(-8.0), 3, "Z"))
    mb.box(S(0.16, 0.025, 0.1), _b(x + 0.25, h + 0.0125, z - 0.08), "pad")
    mb.box(S(0.14, 0.006, 0.08), _b(x + 0.25, h + 0.026, z - 0.08), "ink")
    obj = mb_build(mb, col, {"top": M["table_top"], "stand": M["stand"], "paper": M["paper"], "pad": M["pad"],
                             "ink": M["ink"]}, bevel=0.002)
    obj["lsb_res"] = [1024, 1024]
    sb = MeshBuilder("PRP_Yard_Stamp")
    sb.cylinder(0.032, 0.02, _b(x + 0.25, h + 0.01, z + 0.12), "face", segments=28)
    sb.cylinder(0.026, 0.1, _b(x + 0.25, h + 0.07, z + 0.12), "wood", segments=24, radius2=0.03)
    sb.sphere(0.032, _b(x + 0.25, h + 0.125, z + 0.12), "wood", scale=(1.0, 1.0, 0.7), segments=24, rings=10)
    stamp = mb_build(sb, col, {"face": M["stamp_face"], "wood": M["stamp_wood"]}, bevel=0.0)
    set_origin(stamp, (x + 0.25, h, z + 0.12))
    stamp["lsb_res"] = [256, 256]
    return [obj, stamp]


def stamp_planes():
    x, z = TABLE_AT
    h = 0.72
    pw, ph = 0.21 * 1.8 * 0.55, 0.297 * 1.8 * 0.55
    rot = Matrix.Rotation(math.radians(-8.0), 3, "Z")
    u = rot @ Vector((-1.0, 0.0, 0.0))
    v = rot @ Vector((0.0, 1.0, 0.0))
    centre = _b(x - 0.12, h, z)
    origin = centre - u * pw * 0.5 - v * ph * 0.5
    paper = {"origin": tuple(origin), "u_axis": tuple(u), "v_axis": tuple(v), "u_len": pw, "v_len": ph}
    face = {"origin": (0.032, -0.032, 0.0), "u_axis": (-1.0, 0.0, 0.0), "v_axis": (0.0, 1.0, 0.0), "u_len": 0.064,
            "v_len": 0.064}
    return paper, face


def _barrier(mb, x, z, yaw_deg):
    """A 型のバリケード（幅 1.2 m）: 2 枚の縞の板を A 字に開き、上で蝶番。"""
    rot = Matrix.Rotation(math.radians(yaw_deg), 3, "Z")
    for s in (-1.0, 1.0):
        tilt = Matrix.Rotation(math.radians(s * 12.0), 3, "X")
        for k in range(6):
            mat = "y" if k % 2 == 0 else "k"
            off = rot @ (tilt @ Vector((-0.5 + (k + 0.5) * (1.0 / 6.0), 0.0, 0.0)) + Vector((0.0, s * 0.12, 0.0)))
            p = _b(x, 0.74, z) + off
            mb.box((1.0 / 6.0, 0.02, 0.22), p, mat, rotation=rot @ tilt)
        for sx in (-1.0, 1.0):
            off = rot @ (Vector((sx * 0.58, s * 0.12, 0.0)))
            mb.box((0.04, 0.03, 0.95), _b(x, 0.47, z) + off, "y", rotation=rot @ tilt)


def build_barriers(col, M):
    mb = MeshBuilder("PRP_Yard_Barriers")
    for k in range(9):
        _barrier(mb, -11.0 + k * 3.2, 5.6, 0.0)
    for x in (-14.4, 16.6):
        for z in (-3.0, 0.0, 3.0):
            _barrier(mb, x, z, 90.0)
    obj = mb_build(mb, col, {"y": M["barrier_y"], "k": M["barrier_k"]}, bevel=0.004)
    obj["lsb_res"] = [1024, 1024]
    return obj


def build_bench(col, M):
    """見学席: 奥（+z）の長いベンチ（2 台）。"""
    mb = MeshBuilder("PRP_Yard_Bench")
    for x0 in (3.0, 6.4):
        w = 3.0
        mb.box(S(w, 0.045, 0.36), _b(x0, 0.45, 6.6), "wood")
        for sx in (-1.0, 1.0):
            mb.box(S(0.05, 0.42, 0.32), _b(x0 + sx * (w * 0.5 - 0.15), 0.21, 6.6), "stand")
            mb.box(S(0.06, 0.03, 0.4), _b(x0 + sx * (w * 0.5 - 0.15), 0.015, 6.6), "rubber")
    obj = mb_build(mb, col, {"wood": M["bench_wood"], "stand": M["stand"], "rubber": M["rubber"]}, bevel=0.004)
    obj["lsb_res"] = [1024, 1024]
    return obj


def build(col):
    labels = make_labels()
    paper, face = stamp_planes()
    planes = {"checklist": checklist_plane(), "stamp_paper": paper, "stamp_face": face,
              "stop_text": {"origin": tuple(_b(RAIL_X + 0.5, 0.0, -(STOP_Z + 0.32) - 0.125)), "u_axis": (-1.0, 0.0, 0.0),
                            "v_axis": (0.0, -1.0, 0.0), "u_len": 1.0, "v_len": 0.25}}
    M = materials(labels, planes)
    objs = build_stop_lines(col, M)
    objs.append(build_checklist_board(col, M))
    objs += build_stamp_table(col, M)
    objs.append(build_barriers(col, M))
    objs.append(build_bench(col, M))
    return objs

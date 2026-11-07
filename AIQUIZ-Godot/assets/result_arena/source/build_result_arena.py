"""両者脱落の結果発表アリーナ（海上の専用アリーナ）を組み立てて書き出す決定的なビルダー。

ユーザーのライブ Blender 上で実行する（Higgsfield の Blender 連携 bl_execute 経由。ヘッドレスでは動かさない）:

    path = r"G:/AIQUIZ-Main/AIQUIZ-Godot/assets/result_arena/source/build_result_arena.py"
    exec(compile(open(path, encoding="utf-8").read(), path, "exec"), {"__file__": path, "__name__": "__main__"})

部品の形・色・材質は AIQUIZ STADIUM のビルダー（assets/aiquiz_stadium/source/blender の aqs_geom / aqs_common /
aqs_parts / aqs_wear）をそのまま使う。開いているファイルの他のシーンには触らず、シーン ResultArena を作り直す。

座標（アリーナ空間）：原点は結果発表の舞台の中心の床の上面（Godot の ResultCeremonyDirector.podium_center）。
Blender は Z 上、Godot = (X, Z, -Y)。結果発表のカメラは Godot の +Z（Blender の -Y）を向くので、正面スタンドは
Blender の -Y 側に立ち、+Y（舞台）を向く。

書き出すもの（assets/result_arena/）：
- result_arena.glb         舞台（RA_Deck・中央のフタ RA_Lid）、左右の座席スタンド（RA_WingL / RA_WingR）、照明塔（RA_Masts）
- result_arena_stand.glb   正面スタンド（RA_Stand）と大型モニター（RA_Scoreboard）。ゴール観客席と同じ約束：
                           スタンド空間（前端 y=0、奥へ +y、-Y を向く）、段・通路は goal_stand_layout.json のまま、
                           LED 面の材質 GS_ScoreboardScreen（UV 0..1、縦横比 1400:600）。GoalStand がそのまま観客を並べる
- result_arena_layout.json 正面スタンドの位置、フタの半径、左右のスタンドの座席（GrandstandCrowd の座席の形）
- source/result_arena.blend と source/previews/*.png（ゲームの結果発表のカメラと全景）
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
ASSET = HERE.parent
ROOT = ASSET.parents[1]
STADIUM_BLENDER = ROOT / "assets" / "aiquiz_stadium" / "source" / "blender"
if str(STADIUM_BLENDER) not in sys.path:
    sys.path.insert(0, str(STADIUM_BLENDER))
for cached in [name for name in sys.modules if name.startswith("aqs_")]:
    del sys.modules[cached]      # 何度実行しても、いまのファイルの中身で組む

import aqs_geom as AG  # noqa: E402
import aqs_wear as WR  # noqa: E402
from aqs_common import C, DECK_Y, IMG_WHITE, LAYOUT_GS, SEA_Y, SEABED_Y, ST, TEX  # noqa: E402
from aqs_geom import Mesh, mix, shade  # noqa: E402
from aqs_parts import pile  # noqa: E402

SCENE_NAME = "ResultArena"
BLEND = HERE / "result_arena.blend"
PREVIEW = HERE / "previews"

# --- ゲームとの約束 -------------------------------------------------------------
# 正面スタンドの前端：ゴール観客席（GoalStand.GOAL_OFFSET 25.8）と舞台（RESULT_WALK_FINISH_OFFSET 3.7）の差。
# 結果発表のカメラ（Blender で振り付けた ResultFinaleMotion）はゴール観客席を背景に作ってあるので、同じ距離に置く。
STAND_OFFSET = 25.8 - 3.7
# サドンデスの縦穴（SuddenDeathLayout.SHAFT_RADIUS）。中央のフタだけを別の部品にし、穴が開くときに隠す。
LID_RADIUS = 7.0
# 舞台の半径はコースの床の半分の幅（StageConstants.FLOOR_HALF_WIDTH）と同じ。サドンデスの水上機は床の横の壁（x=12）に
# 横付けし（FloatplaneStaging）、昇降台もそこに出るので、舞台の縁が同じ所に来る。
DECK_RADIUS = 12.0
SEA = SEA_Y - DECK_Y           # アリーナ空間の海面（-8.0）
SEABED = SEABED_Y - DECK_Y     # 海底（-128.0）
SEGMENTS = 96
# 左右の座席スタンド：中心（Godot の x, z）と長さ。正面（局所 -X）を舞台の中心へ向ける。
WING_CENTER = (22.0, 16.5)
WING_LENGTH = 20.0
WING_LIFT = -DECK_Y            # 座席スタンドの原点は Godot の Y=0（コースの客席と同じ高さの約束）
# 大型モニター：ゴール観客席（11.2 x 4.8）より少し大きく、縦横比は掲示板の画面（1400:600）のまま。
SCREEN_W, SCREEN_H, SCREEN_Z = 12.6, 5.4, 3.3


def ring(m: Mesh, r0, r1, z, col, mat="paint", n=SEGMENTS, a0=0.0, a1=2 * math.pi, tone=None):
    """z の高さの上向きの輪（r0..r1）。tone(i) で区画ごとの色を変えられる。"""
    for i in range(n):
        t0 = a0 + (a1 - a0) * i / n
        t1 = a0 + (a1 - a0) * (i + 1) / n
        c = tone(i) if tone else col
        m.add_face([(r0 * math.cos(t0), r0 * math.sin(t0), z), (r1 * math.cos(t0), r1 * math.sin(t0), z),
                    (r1 * math.cos(t1), r1 * math.sin(t1), z), (r0 * math.cos(t1), r0 * math.sin(t1), z)], c, mat)


def wall(m: Mesh, r, z0, z1, col, mat="paint", n=SEGMENTS, inward=False):
    """半径 r の円筒の壁（z0..z1）。inward で内側を向く。"""
    for i in range(n):
        t0 = 2 * math.pi * i / n
        t1 = 2 * math.pi * (i + 1) / n
        a, b = (r * math.cos(t0), r * math.sin(t0)), (r * math.cos(t1), r * math.sin(t1))
        pts = [(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)]
        m.add_face(list(reversed(pts)) if inward else pts, col, mat)


def disc(m: Mesh, r, z, col, mat="paint", n=SEGMENTS, down=False):
    pts = [(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n), z) for i in range(n)]
    m.add_face(list(reversed(pts)) if down else pts, col, mat)


# =============================================================================
# 舞台：外周のデッキ（RA_Deck）と中央のフタ（RA_Lid）
# =============================================================================
## 舞台の床：白いスコアタワーと半透明の幽霊が沈まないよう、建物の白よりはっきり暗い青みのグレー
## （ゲームの照明は明るく、段のグレー #CFD3D8 でもほぼ白に見える。コースのベルトは #666869）
FLOOR = AG.hexcol("#98A2AE")


def build_lid():
    m = Mesh()
    disc(m, 4.6, 0.0, FLOOR)
    ring(m, 4.6, 5.5, 0.0, FLOOR, tone=lambda i: shade(FLOOR, 1.0 if i % 2 == 0 else 0.94))
    ring(m, 5.5, 5.85, 0.0, C["cobalt"])
    ring(m, 5.85, 6.2, 0.0, shade(C["white"], 0.92))
    ring(m, 6.2, 6.3, 0.0, C["lantern"], "night")      # 夜に灯る細い輪
    ring(m, 6.3, LID_RADIUS, 0.0, shade(C["white"], 0.92))
    wall(m, LID_RADIUS, -0.5, 0.0, C["cobalt"])
    disc(m, LID_RADIUS, -0.5, C["deck_under"], down=True)
    return m


def build_deck():
    m = Mesh()
    # 上面：内側の縁（コバルト）→ 24 区画の白とグレーの放射 → 外周の帯
    ring(m, LID_RADIUS, 7.45, 0.0, C["cobalt"])
    ring(m, 7.45, DECK_RADIUS - 0.9, 0.0, FLOOR, n=SEGMENTS,
         tone=lambda i: shade(FLOOR, 1.08) if (i // 4) % 2 == 0 else FLOOR)
    ring(m, DECK_RADIUS - 0.9, DECK_RADIUS - 0.5, 0.0, C["cobalt"])
    ring(m, DECK_RADIUS - 0.5, DECK_RADIUS, 0.0, C["white"])
    # 内側の壁（フタが外れたとき縦穴の口に見える）と裏
    wall(m, LID_RADIUS, -0.6, 0.0, C["deck_under"], inward=True)
    ring(m, LID_RADIUS, DECK_RADIUS, -0.6, C["deck_under"])
    m.f[-SEGMENTS:] = [tuple(reversed(face)) for face in m.f[-SEGMENTS:]]   # 裏は下向き
    # 外周のスカート：白の縁、コバルトの帯、夜の灯の帯、水面の下は青緑に寄せる
    for z0, z1, col, mat in ((-0.12, 0.0, C["white"], "paint"), (-0.42, -0.12, C["cobalt"], "paint"),
                             (-0.52, -0.42, C["warm"], "night"), (SEA + 0.6, -0.52, C["white"], "paint"),
                             (SEA - 2.0, SEA + 0.6, mix(C["white"], C["sea_tint"], 0.45), "paint")):
        wall(m, DECK_RADIUS, z0, z1, col, mat)
    # 縁の低い灯の柱（15° ごと）
    for k in range(24):
        t = 2 * math.pi * (k + 0.5) / 24
        x, y = (DECK_RADIUS - 0.22) * math.cos(t), (DECK_RADIUS - 0.22) * math.sin(t)
        m.box((x, y, 0.12), (0.22, 0.22, 0.24), C["white"])
        m.box((x, y, 0.27), (0.18, 0.18, 0.06), C["lantern"], "night")
    # 杭：縦穴（半径 7 m）の外だけ
    for r, count in ((8.6, 12), (DECK_RADIUS - 1.0, 16)):
        for k in range(count):
            t = 2 * math.pi * (k + 0.5) / count
            pile(m, r * math.cos(t), r * math.sin(t), SEABED, -0.6, 0.7, tint_z=SEA - 0.8)
    return m


# =============================================================================
# 正面スタンド（スタンド空間：前端 y=0、奥へ +y、-Y を向く）。段と通路はゴール観客席と同じ
# =============================================================================
def fin(m: Mesh, x0, x1, pts_yz, col):
    """x0..x1 の厚みの、yz 平面の多角形の板（両面と縁）。pts_yz は +X から見て時計回り（y 右・z 上の図で反時計回り）。"""
    xa, xb = sorted((x0, x1))
    pts_yz = list(reversed(pts_yz))      # +X から見て反時計回りにそろえる：+X の面が +X を、縁が外を向く
    outer = [(xb, y, z) for y, z in pts_yz]
    inner = [(xa, y, z) for y, z in pts_yz]
    m.add_face(outer, col)
    m.add_face(list(reversed(inner)), col)
    n = len(pts_yz)
    for i in range(n):
        j = (i + 1) % n
        m.add_face([inner[i], inner[j], outer[j], outer[i]], shade(col, 0.96))


def build_stand():
    stand, board = Mesh(), Mesh()
    L = LAYOUT_GS
    half = L["width"] / 2
    back_y, back_top = L["back_y"], L["back_top"]
    tiers = L["tiers"]
    tread = 1.35
    tier_front = [0.30 + i * tread for i in range(len(tiers) + 1)]
    # 土台と前の胸壁
    stand.box_lohi((-half - 0.6, -0.1, -0.6), (half + 0.6, 8.6, 0.0), C["white"])
    stand.box_lohi((-half - 0.6, -0.12, -0.45), (half + 0.6, -0.1, -0.3), C["cobalt"], faces=["-y"])
    stand.box_lohi((-half, 0.0, 0.0), (half, 0.30, L["parapet_top"] - 0.06), C["white"])
    stand.box_lohi((-half - 0.05, -0.03, L["parapet_top"] - 0.06), (half + 0.05, 0.33, L["parapet_top"]), C["cobalt"])
    stand.box_lohi((-half, -0.015, 0.42), (half, 0.0, 0.5), C["warm"], "night", faces=["-y"])   # 胸壁の灯の帯
    # 段と通路の階段（ゴール観客席と同じ寸法：観客はこの段に並ぶ）
    for i, t in enumerate(tiers):
        y0, y1 = tier_front[i], (tier_front[i + 1] if i < len(tiers) - 1 else back_y - 0.30)
        for a, b in t["spans"]:
            stand.box_lohi((a, y0, 0.0), (b, y1, t["floor_z"]), C["riser"], top=C["step"])
        for ax in L["aisles"]:
            aw = L["aisle_width"] / 2
            prev = tiers[i - 1]["floor_z"] if i > 0 else 0.0
            mid = (prev + t["floor_z"]) / 2
            stand.box_lohi((ax - aw, y0, 0.0), (ax + aw, y0 + 0.675, mid), C["riser"], top=C["step"])
            stand.box_lohi((ax - aw, y0 + 0.675, 0.0), (ax + aw, y1, t["floor_z"]), C["riser"], top=C["step"])
        if i > 0:
            for a, b in t["spans"]:
                yy = y0 + 0.08
                stand.box_lohi((a + 0.1, yy - 0.03, t["floor_z"] + 0.97), (b - 0.1, yy + 0.03, t["floor_z"] + 1.03), C["cobalt"])
                n = max(2, round((b - a) / 2.1))
                for k in range(n + 1):
                    xx = a + 0.15 + (b - a - 0.3) * k / n
                    stand.box((xx, yy, t["floor_z"] + 0.5), (0.05, 0.05, 1.0), C["white"])
    # 背面の壁：白、上の縁はコバルト、腰に夜の灯の帯
    stand.box_lohi((-half, back_y - 0.30, 0.0), (half, back_y, back_top), C["white"])
    stand.box_lohi((-half - 0.03, back_y - 0.33, back_top), (half + 0.03, back_y + 0.03, back_top + 0.06), C["cobalt"])
    stand.box_lohi((-half + 0.3, back_y - 0.315, 2.55), (half - 0.3, back_y - 0.30, 2.68), C["lantern"], "night", faces=["-y"])
    # 両端のヒレ：前から奥へせり上がる白い壁。外側にチームの色の帯（スタンドは 180° 回るので、局所 -X が P1）
    prof = [(0.0, 0.0), (0.0, 1.35), (2.6, 2.4), (back_y + 0.9, 6.2), (back_y + 2.4, 6.6), (8.6, 6.6), (8.6, 0.0)]
    for sgn, team in ((-1, C["orange"]), (1, C["blue"])):
        x0, x1 = sgn * half, sgn * (half + 0.55)
        fin(stand, x0, x1, prof, C["white"])
        xo = sgn * (half + 0.56)
        band = [(0.4, 1.0), (back_y + 1.8, 5.55), (back_y + 1.8, 6.0), (0.4, 1.45)]
        pts = [(xo, y, z) for y, z in band]
        stand.add_face(pts if sgn > 0 else list(reversed(pts)), team)
        stand.beam((sgn * (half + 0.275), 0.0, 1.35), (sgn * (half + 0.275), 2.6, 2.4), 0.12, C["cobalt"])
        stand.beam((sgn * (half + 0.275), 2.6, 2.4), (sgn * (half + 0.275), back_y + 0.9, 6.2), 0.12, C["cobalt"])
    # チームの旗（ゴール観客席と同じ場所）
    for fx, col in ((L["flags"]["p1_x"], C["orange"]), (L["flags"]["p2_x"], C["blue"])):
        stand.box((fx, 0.15, (L["parapet_top"] + 5.5) / 2), (0.08, 0.08, 5.5 - L["parapet_top"]), C["white"])
        stand.quad2((fx, 0.15, 5.45), (fx - math.copysign(1.4, fx), 0.15, 5.45), (fx - math.copysign(1.4, fx), 0.15, 4.6), (fx, 0.15, 4.6), col)
    # 杭と桁
    for x in (-13.2, -6.6, 0.0, 6.6, 13.2):
        for yy in (0.3, 4.2, 8.2):
            pile(stand, x, yy, SEABED, -1.1, 0.6, tint_z=SEA - 0.8)
    for yy in (0.3, 4.2, 8.2):
        stand.box_lohi((-13.5, yy - 0.25, -1.1), (13.5, yy + 0.25, -0.6), C["deck_under"])

    # --- 大型モニター（RA_Scoreboard）：黒い筐体と白い額、上に看板、左右の照明塔 -----------------------------
    sw = SCREEN_W / 2
    sz0, sz1 = SCREEN_Z, SCREEN_Z + SCREEN_H
    bez = 0.32
    cab_x = sw + bez
    cab_y0 = back_y + 0.10
    face_y = back_y + 0.04
    board.box_lohi((-cab_x, cab_y0, sz0 - bez), (cab_x, cab_y0 + 1.1, sz1 + bez), C["dark"])
    for lo, hi in (((-cab_x, face_y - 0.06, sz0 - bez), (cab_x, cab_y0, sz0)),
                   ((-cab_x, face_y - 0.06, sz1), (cab_x, cab_y0, sz1 + bez)),
                   ((-cab_x, face_y - 0.06, sz0), (-sw, cab_y0, sz1)),
                   ((sw, face_y - 0.06, sz0), (cab_x, cab_y0, sz1))):
        board.box_lohi(lo, hi, C["dark"])
    board.add_face([(-sw, face_y, sz0), (sw, face_y, sz0), (sw, face_y, sz1), (-sw, face_y, sz1)], IMG_WHITE, "screen",
                   [(0, 0), (1, 0), (1, 1), (0, 1)])
    # 白い額とコバルトの縁取り
    fw = 0.42
    ox, oz0, oz1 = cab_x + fw, sz0 - bez - fw, sz1 + bez + fw
    for lo, hi in (((-ox, face_y - 0.12, oz0), (ox, cab_y0 + 1.1, sz0 - bez)),
                   ((-ox, face_y - 0.12, sz1 + bez), (ox, cab_y0 + 1.1, oz1)),
                   ((-ox, face_y - 0.12, sz0 - bez), (-cab_x, cab_y0 + 1.1, sz1 + bez)),
                   ((cab_x, face_y - 0.12, sz0 - bez), (ox, cab_y0 + 1.1, sz1 + bez))):
        board.box_lohi(lo, hi, C["white"])
    for lo, hi in (((-ox - 0.04, face_y - 0.16, oz1), (ox + 0.04, cab_y0 + 1.14, oz1 + 0.1)),
                   ((-ox - 0.04, face_y - 0.16, oz0 - 0.1), (ox + 0.04, cab_y0 + 1.14, oz0))):
        board.box_lohi(lo, hi, C["cobalt"])
    # 看板（AIQUIZ STADIUM の文字の画像）
    h0, h1 = oz1 + 0.1, oz1 + 1.25
    hw = (h1 - h0) * 2.5 / 2
    board.box_lohi((-hw - 0.12, cab_y0 + 0.1, h0), (hw + 0.12, cab_y0 + 0.6, h1 + 0.1), C["navy"])
    board.add_face([(-hw, cab_y0 + 0.09, h0 + 0.05), (hw, cab_y0 + 0.09, h0 + 0.05), (hw, cab_y0 + 0.09, h1 + 0.05),
                    (-hw, cab_y0 + 0.09, h1 + 0.05)], IMG_WHITE, "header", [(0, 0), (1, 0), (1, 1), (0, 1)])
    # モニターを支える左右の照明塔（土台から立ち、頂上の灯具は舞台へ向く）
    tower_x = ox + 1.1
    for sgn in (-1, 1):
        tx = sgn * tower_x
        ty = back_y + 0.75
        for cx in (tx - 0.42, tx + 0.42):
            for cy in (ty - 0.42, ty + 0.42):
                board.box((cx, cy, 7.0), (0.16, 0.16, 14.0), C["white"])
        for zz in range(1, 14, 2):
            for (ax, ay), (bx, by) in (((tx - 0.42, ty - 0.42), (tx + 0.42, ty + 0.42)), ((tx + 0.42, ty - 0.42), (tx - 0.42, ty + 0.42))):
                board.beam((ax, ay, zz), (bx, by, zz + 1.6), 0.05, C["white"])
        board.box_lohi((tx - 0.6, ty - 0.6, 13.9), (tx + 0.6, ty + 0.6, 14.1), C["cobalt"])
        # 灯具の板：暗い枠に 3 x 4 の灯
        board.box_lohi((tx - 1.5, ty - 0.55, 14.1), (tx + 1.5, ty - 0.15, 16.0), C["dark"])
        for r in range(3):
            for c in range(4):
                lx = tx - 1.2 + c * 0.8
                lz = 14.4 + r * 0.55
                board.box_lohi((lx - 0.3, ty - 0.58, lz), (lx + 0.3, ty - 0.55, lz + 0.42), C["cool"], "night", faces=["-y"])
        # 腕木でモニターの額とつなぐ
        board.beam((sgn * ox, cab_y0 + 0.5, oz1 - 0.6), (tx, ty, oz1 - 0.6), 0.14, C["cobalt"])
        board.beam((sgn * ox, cab_y0 + 0.5, oz0 + 0.6), (tx, ty, oz0 + 0.6), 0.14, C["cobalt"])
    return stand, board


# =============================================================================
# 左右の座席スタンド（局所：+X が舞台から離れる向き、Y がスタンドに沿う、原点は Godot の Y=0）
# コースの客席ブロック（aqs_parts.build_stand_block）と同じ段・座席。両端は壁で閉じ、真ん中に通路
# =============================================================================
def build_wing(team_col):
    m = Mesh()
    half_len = WING_LENGTH / 2
    y0, y1 = -half_len, half_len
    rows = ST["rows"]["count"]
    front = [ST["rows"]["first_seat_x"] - 0.55 + i * ST["rows"]["tread"] for i in range(rows + 1)]
    tops = [ST["rows"]["base_z"] + i * ST["rows"]["rise"] for i in range(rows)]
    walk_x0, back_x = ST["rear_walkway"]["x"]
    walk_top = ST["rear_walkway"]["top_z"]
    deck_top, deck_bot = ST["deck_top_z"], ST["deck_underside_z"]
    fx = ST["front_face_x"]
    aisle = 1.1
    # デッキと前面
    m.box_lohi((fx, y0, deck_bot), (back_x, y1, deck_top), C["white"], top=shade(C["step"], 1.03))
    for za, zb, col in ((deck_bot, -0.36, C["white"]), (-0.36, -0.2, C["cobalt"]), (-0.2, deck_top, C["white"])):
        m.add_face([(fx - 0.01, y1, za), (fx - 0.01, y0, za), (fx - 0.01, y0, zb), (fx - 0.01, y1, zb)], col)
    fwl = ST["front_wall"]
    wx0, wx1 = fwl["x"] - fwl["thickness"] / 2, fwl["x"] + fwl["thickness"] / 2
    m.box_lohi((wx0, y0, deck_top), (wx1, y1, fwl["top_z"]), C["white"])
    m.box_lohi((wx0 - 0.03, y0, fwl["top_z"]), (wx1 + 0.03, y1, fwl["top_z"] + 0.06), C["cobalt"])
    m.box_lohi((wx0 - 0.015, y0, 0.46), (wx0, y1, 0.52), C["warm"], "night", faces=["-x"])
    for j in range(int(WING_LENGTH / fwl["post_pitch"]) + 1):
        yy = y0 + 0.45 + j * fwl["post_pitch"]
        if yy < y1 - 0.2:
            m.box((fwl["x"], yy, (fwl["top_z"] + 0.06 + fwl["rail_top_z"]) / 2), (0.05, 0.05, fwl["rail_top_z"] - fwl["top_z"] - 0.06), C["white"])
    m.box_lohi((fwl["x"] - 0.05, y0, fwl["rail_top_z"] - 0.06), (fwl["x"] + 0.05, y1, fwl["rail_top_z"]), C["cobalt"])
    # 段（真ん中の通路を挟んで 2 つ）
    for i in range(rows):
        x1 = front[i + 1] if i < rows - 1 else walk_x0
        for a, b in ((y0 + 0.3, -aisle), (aisle, y1 - 0.3)):
            m.box_lohi((front[i], a, deck_top), (x1, b, tops[i]), C["riser"], top=C["step"])
            m.box_lohi((front[i], a, tops[i]), (front[i] + 0.08, b, tops[i] + 0.02), C["white"])
    # 通路の階段
    for j in range(12):
        xs = front[0] + j * 0.625
        m.box_lohi((xs, -aisle, deck_top), (xs + 0.625, aisle, ST["rows"]["base_z"] + j * 0.2), C["riser"], top=C["step"])
    # 後方通路と背面の手すり・背の高い背板（チームの色の帯）
    m.box_lohi((walk_x0, y0, deck_top), (back_x, y1, walk_top), C["riser"], top=C["step"])
    rail_top = ST["rear_walkway"]["back_rail_top_z"]
    m.box_lohi((back_x - 0.2, y0, walk_top), (back_x, y1, rail_top + 1.6), C["white"])
    m.box_lohi((back_x - 0.22, y0 + 0.4, rail_top + 0.55), (back_x - 0.2, y1 - 0.4, rail_top + 1.05), team_col, faces=["-x"])
    m.box_lohi((back_x - 0.25, y0, rail_top + 1.6), (back_x + 0.05, y1, rail_top + 1.7), C["cobalt"])
    # 両端の壁
    for ye, s in ((y0, 1.0), (y1, -1.0)):
        yi = ye + s * 0.3
        for i in range(rows):
            x1 = front[i + 1] if i < rows - 1 else walk_x0
            m.box_lohi((front[i], ye, deck_top), (x1, yi, tops[i] + 0.9), C["white"])
            m.box_lohi((front[i] - 0.02, ye - s * 0.03, tops[i] + 0.9), (x1, yi + s * 0.03, tops[i] + 0.96), C["cobalt"])
        m.box_lohi((walk_x0, ye, deck_top), (back_x, yi, rail_top + 1.6), C["white"])
        m.box_lohi((fx, ye, deck_top), (front[0], yi, 1.16), C["white"])
    # 座席（GrandstandCrowd の座席：[x, 座面の上, z（= -y）, 列]）
    seats = []
    pitch = ST["seats"]["pitch"]
    for i in range(rows):
        x = ST["rows"]["seat_x"][i]
        floor = tops[i]
        k = 0
        while True:
            yy = y0 + 0.75 + k * pitch
            k += 1
            if yy + 0.33 > y1 - 0.3:
                break
            if abs(yy) - 0.33 < aisle:
                continue
            m.box((x, yy, floor + 0.50), (0.61, 0.62, 0.09), C["seat"])
            m.box((x + 0.265, yy, floor + 0.78), (0.10, 0.62, 0.43), C["seat"])
            m.box((x + 0.05, yy, floor + 0.2275), (0.30, 0.30, 0.455), shade(C["seat"], 0.9))
            seats.append([round(x, 4), round(floor + 0.545, 4), round(-yy, 4), i])
    # 杭と桁（海底まで）
    for yy in (-7.5, -2.5, 2.5, 7.5):
        for x in ST["piles"]["x"]:
            pile(m, x, yy, SEABED_Y, ST["piles"]["top_z"] - 0.6, ST["piles"]["section"])
        m.box_lohi((-0.2, yy - 0.3, ST["piles"]["top_z"] - 0.6), (back_x - 0.2, yy + 0.3, ST["piles"]["top_z"]), C["deck_under"])
    return m, seats


# =============================================================================
# 照明塔（左右のスタンドの外側の奥）
# =============================================================================
def build_mast(m: Mesh, base, facing_deg, height=18.0, team_col=None):
    bx, by, bz = base
    t = math.radians(facing_deg)
    fwd = Vector((math.cos(t), math.sin(t), 0.0))          # 灯具の向き（水平）
    side = Vector((-fwd.y, fwd.x, 0.0))
    m.prism(bx, by, bz, bz + height, 0.42, 0.22, 8, C["white"], smooth=True)
    m.prism(bx, by, bz - 1.0, bz, 0.9, 0.9, 8, C["cobalt"])
    if team_col is not None:
        m.prism(bx, by, bz + 2.0, bz + 3.2, 0.44, 0.42, 8, team_col)
    top = Vector((bx, by, bz + height))
    m.beam(top - side * 1.8, top + side * 1.8, 0.16, C["cobalt"])
    head_c = top + Vector((0, 0, 1.15)) + fwd * 0.2
    for r in range(3):
        for c in range(4):
            p = head_c + side * (-1.2 + c * 0.8) + Vector((0, 0, -0.55 + r * 0.55))
            m.box(tuple(p - fwd * 0.08), (0.62, 0.62, 0.46), C["dark"])
            # 灯の面（fwd を向く）
            a = p + fwd * 0.24 - side * 0.27 - Vector((0, 0, 0.2))
            b = p + fwd * 0.24 + side * 0.27 - Vector((0, 0, 0.2))
            m.add_face([tuple(a), tuple(b), tuple(b + Vector((0, 0, 0.4))), tuple(a + Vector((0, 0, 0.4)))], C["cool"], "night")
    for p in (head_c - side * 1.6, head_c + side * 1.6):
        m.beam(tuple(p - Vector((0, 0, 0.85))), tuple(p + Vector((0, 0, 0.85))), 0.1, C["white"])


# =============================================================================
# 組み立て
# =============================================================================
def make_materials():
    mats = AG.Materials()
    mats.add("screen", AG.flat_material("GS_ScoreboardScreen", (0.02, 0.03, 0.025, 1.0), 0.25))
    mats.add("header", AG.image_material("GS_SBHeaderSign", TEX / "lighthouse_sign.png", emission=0.2))
    return mats


def fresh_scene():
    """シーン ResultArena を作り直す（他のシーンとそのデータには触らない）。"""
    old = bpy.data.scenes.get(SCENE_NAME)
    if old is not None:
        owned = {(type(obj.data).__name__, obj.data.name) for obj in old.collection.all_objects if obj.data is not None}
        for obj in list(old.collection.all_objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        for kind, name in owned:
            blocks = {"Mesh": bpy.data.meshes, "Camera": bpy.data.cameras, "SunLight": bpy.data.lights}.get(kind)
            data = blocks.get(name) if blocks is not None else None
            if data is not None and data.users == 0:
                blocks.remove(data)
        for coll in list(old.collection.children_recursive):
            bpy.data.collections.remove(coll)
        bpy.data.scenes.remove(old)
    scene = bpy.data.scenes.new(SCENE_NAME)
    scene.unit_settings.system = "METRIC"
    if bpy.context.window is not None:
        bpy.context.window.scene = scene
    return scene


def collection(scene, name):
    coll = bpy.data.collections.new(name)
    scene.collection.children.link(coll)
    return coll


def weld(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def stats(obj):
    me = obj.data
    me.calc_loop_triangles()
    return {"triangles": len(me.loop_triangles), "materials": [m.name for m in me.materials]}


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


def wing_transform(sign):
    """左右のスタンドの位置（Blender）と Z 回り（度）。局所 +X を舞台の中心から離れる向きにする。"""
    gx, gz = sign * WING_CENTER[0], WING_CENTER[1]
    bx, by = gx, -gz
    return (bx, by, WING_LIFT), math.degrees(math.atan2(by, bx))


def build(wear=True):
    scene = fresh_scene()
    mats = make_materials()
    report = {"objects": {}, "exports": []}
    arena = collection(scene, "RA_EXPORT_Arena")
    stand_coll = collection(scene, "RA_EXPORT_Stand")
    layout = collection(scene, "RA_Layout")

    deck = AG.create_object("RA_Deck", build_deck(), mats, arena)
    lid = AG.create_object("RA_Lid", build_lid(), mats, arena)
    seats = {}
    wings = []
    for sign, name, team, col in ((1, "RA_WingR", 1, C["orange"]), (-1, "RA_WingL", 2, C["blue"])):
        mesh, wing_seats = build_wing(col)
        obj = AG.create_object(name, mesh, mats, arena)
        loc, yaw = wing_transform(sign)
        obj.location = loc
        obj.rotation_euler = (0.0, 0.0, math.radians(yaw))
        seats[name] = {"team": team, "seats": wing_seats}
        wings.append(obj)
    masts = Mesh()
    for sign, col in ((1, C["orange"]), (-1, C["blue"])):
        loc, yaw = wing_transform(sign)
        t = math.radians(yaw)
        # カメラ側の端の奥：局所 (back_x + 1.6, ±y 端)。左右で局所の Y の向きが逆なので符号を掛ける
        lx, ly = ST["rear_walkway"]["x"][1] + 1.6, sign * (WING_LENGTH / 2 - 1.0)
        bx = loc[0] + lx * math.cos(t) - ly * math.sin(t)
        by = loc[1] + lx * math.sin(t) + ly * math.cos(t)
        build_mast(masts, (bx, by, WING_LIFT), math.degrees(math.atan2(-by, -bx)), team_col=col)
    mast_obj = AG.create_object("RA_Masts", masts, mats, arena)

    s_mesh, b_mesh = build_stand()
    stand = AG.create_object("RA_Stand", s_mesh, mats, stand_coll)
    board = AG.create_object("RA_Scoreboard", b_mesh, mats, stand_coll)

    for obj in (deck, lid, mast_obj, stand, board, *wings):
        weld(obj)
    if wear:
        # 頂点色へ AO・水際の汚れ・ムラを焼く（コースのスタンドと同じ）。水面は各部品の局所の高さ
        report["wear"] = {
            deck.name: WR.bake_wear(deck, SEA, extra=(lid,)),
            lid.name: WR.bake_wear(lid, SEA, extra=(deck,)),
            stand.name: WR.bake_wear(stand, SEA, extra=(board,)),
            board.name: WR.bake_wear(board, SEA, extra=(stand,)),
        }
        for obj in wings:
            report["wear"][obj.name] = WR.bake_wear(obj, SEA_Y)
    for obj in (deck, lid, mast_obj, stand, board, *wings):
        report["objects"][obj.name] = stats(obj)

    # 確認用：正面スタンドを舞台の奥に置いた複製（同じメッシュ）。書き出さない
    for src in (stand, board):
        dup = bpy.data.objects.new(src.name + "_Placed", src.data)
        dup.location = (0.0, -STAND_OFFSET, 0.0)
        dup.rotation_euler = (0.0, 0.0, math.pi)
        layout.objects.link(dup)
    stand_coll.hide_viewport = True
    stand_coll.hide_render = True
    sea = bpy.data.meshes.new("RA_PreviewSea")
    sea.from_pydata([(-400, -400, SEA), (400, -400, SEA), (400, 400, SEA), (-400, 400, SEA)], [], [(0, 1, 2, 3)])
    sea_mat = AG.flat_material("RA_PreviewSea", (0.05, 0.33, 0.45, 1.0), 0.15)
    sea.materials.append(sea_mat)
    layout.objects.link(bpy.data.objects.new("RA_PreviewSea", sea))

    # 書き出し
    ASSET.mkdir(parents=True, exist_ok=True)
    report["exports"].append(export_glb([deck, lid, *wings, mast_obj], ASSET / "result_arena.glb"))
    stand_coll.hide_viewport = False
    report["exports"].append(export_glb([stand, board], ASSET / "result_arena_stand.glb"))
    stand_coll.hide_viewport = True
    layout_json = {
        "note": "結果発表アリーナ（build_result_arena.py が書き出す）。座標は Godot のアリーナ空間：原点は舞台の中心の床の上面、"
                "結果発表のカメラは +Z を向く。stand_offset は正面スタンド（result_arena_stand.glb、GoalStand）の前端の z。"
                "wings の seats は各スタンドの局所（GrandstandCrowd.add_block の形：[x 舞台から離れる向き, 座面の上, z, 列]）。",
        "stand_offset": STAND_OFFSET,
        "lid_radius": LID_RADIUS,
        "deck_radius": DECK_RADIUS,
        "screen": {"width": SCREEN_W, "height": SCREEN_H, "bottom": SCREEN_Z},
        "wings": seats,
    }
    (ASSET / "result_arena_layout.json").write_text(json.dumps(layout_json, ensure_ascii=False, indent=1), encoding="utf-8")
    report["seats"] = {name: len(v["seats"]) for name, v in seats.items()}
    return report


def preview():
    """確認レンダー：ゲームの結果発表のカメラの最初の姿勢（Godot eye (0, 3.2, -10.6)、10° 見下ろし、縦 40°）と全景。"""
    scene = bpy.data.scenes[SCENE_NAME]
    layout = bpy.data.collections["RA_Layout"]
    cam = bpy.data.objects.get("RA_PreviewCamera")
    if cam is None:
        cam = bpy.data.objects.new("RA_PreviewCamera", bpy.data.cameras.new("RA_PreviewCamera"))
        layout.objects.link(cam)
    cam.data.sensor_fit = "VERTICAL"
    cam.data.clip_end = 3000.0
    sun = bpy.data.objects.get("RA_PreviewSun")
    if sun is None:
        sun = bpy.data.objects.new("RA_PreviewSun", bpy.data.lights.new("RA_PreviewSun", "SUN"))
        layout.objects.link(sun)
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(200))
    world = scene.world or bpy.data.worlds.new("RA_PreviewWorld")
    scene.world = world
    world.color = (0.55, 0.75, 0.95)
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.view_settings.view_transform = "Standard"
    PREVIEW.mkdir(parents=True, exist_ok=True)
    shots = {
        "game_cam": ((0.0, 10.6, 3.2), (math.radians(80), 0.0, math.radians(180)), 40.0),
        "overview": ((48.0, 46.0, 34.0), (math.radians(62), 0.0, math.radians(136)), 50.0),
    }
    out = {}
    for name, (loc, rot, fov) in shots.items():
        cam.location = loc
        cam.rotation_euler = rot
        cam.data.angle_y = math.radians(fov)
        scene.render.filepath = str(PREVIEW / f"{name}.png")
        bpy.ops.render.render(write_still=True, scene=scene.name)
        out[name] = scene.render.filepath
    cam.location, cam.rotation_euler = shots["game_cam"][0], shots["game_cam"][1]
    cam.data.angle_y = math.radians(shots["game_cam"][2])
    return out


if __name__ == "__main__":
    result = build()
    result["previews"] = preview()

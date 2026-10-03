"""ビル群の手前の岸辺の街（メニュー専用）。

メニューの街はスタジアムの遠景の街（AQS_BG_City）を置き直したもの。遠景用なので、高層ビルの手前は
窓のない低い箱・平らな護岸・丸い木の列だけだった。メニューでは 750〜950m と近いので、その帯を作り直す
（元の箱・護岸・並木はビルダーの trim_city で街の複製から取り除く）。

意匠：source/concepts/r5_waterfront_A.png（フェリーターミナル・時計塔・灯台・マリーナ・パステルの街並み）と
      r5_waterfront_B.png（観覧車・大きなアーチ窓の市場・階段の護岸・日よけ・旗）。Codex CLI の描き足し。

座標：街のローカル（Blender）。x＝岸に沿って（+x がメニューの画面の左）、+y＝海（カメラ）側、z＝海面から上。
地面（街の土地の上面）は z 4.5、岸（土地の縁）は y 252。カメラは海面から 15.3m なので、見えるのは建物の正面と
輪郭、水際。屋根はほとんど見えない。1m がメニューの画面（1080p）で約 2px なので、形は 0.5m より細くしない。

部品（材質キー）：
  paint  頂点色。街の GLB では AQS_BG_Painted（Godot ではスタジアムの遠景シェーダー：距離のかすみ）
  night  夜だけ光る灯（AQS_NightGlow）
  shop / flat / glass / mansion / tile / corridor / loggia / brick / ribbon / punched
         外壁の画像×頂点色（AMS_Facade_*。Godot では遠景シェーダーの外壁、夜は窓明かり）。建物の型ごとに使い分ける
"""
from __future__ import annotations

import math
import random

from aqs_geom import Mesh, hexcol, mix, shade

GROUND = 4.5
QUAY_Y = 252.0                 # 土地の縁
WALL_Y = 252.45                # 護岸の前面
COPING_Z = GROUND + 0.14       # 護岸の笠石の上面
X0, X1 = -578.0, 578.0
PAVE_Z = GROUND + 0.25         # 舗装。土地の上面から 25cm 上（750m 先では数 cm の差は奥行きの精度で揺れる）
GAP = 0.2                      # 壁に貼る面（窓の帯・文字盤など）を壁から離す量。同じ理由で数 cm にしない
PROM_Y0 = 228.0                # 歩道の奥（1 列目の建物の前面）
FLOOR = 3.2
GF = 4.2                       # 1 階（店）の高さ
TILE = 25.6                    # 外壁の画像 1 枚 = 8 スパン × 8 階（3.2m）

# 列：前面の y、奥行きの範囲、階数の範囲
ROWS = {1: (226.0, 12.0, 17.0, 1, 3), 2: (202.0, 15.0, 21.0, 4, 7), 3: (173.0, 16.0, 26.0, 6, 9)}
ROW3_MIN_Y = 139.0

# 目玉の場所（x の範囲）。メニューの画面の中央（走路の壁の上、x -85〜+87）に観覧車と市場
# 観覧車（2026-09-30 に回る観覧車として作り直し）：動かない脚と乗り場（AMS_FerrisWheelStand）、軸まわりに回る輪
# （AMS_FerrisWheelRim、原点＝軸の中心）、ゴンドラ 24 台（AMS_FerrisGondola_00〜23、原点＝輪の吊り点）。
# Godot が輪を軸まわりに回し、ゴンドラは向きを変えずに吊り点の円に沿って動かす（AiquizMenuStage）
WHEEL_X, WHEEL_Y, WHEEL_R = -40.0, 234.0, 30.0      # 軸の x・y、吊り点の半径（直径 60m）
WHEEL_HUB_Z = GROUND + 6.0 + WHEEL_R                 # 軸の高さ。いちばん下のゴンドラの床が乗り場の床の 0.3m 上を通る
WHEEL_AXIS = (0.0, 1.0, 0.0)                         # 軸の向き（街のローカル、+y＝海・カメラの側＝輪の正面）
WHEEL_GONDOLAS = 24
WHEEL_RIM_Y = 2.0                                    # 前後 2 本の輪の y（軸の中心から ±）。ゴンドラ（y ±1.0）はそのあいだに吊る
WHEEL_RIM_IN = WHEEL_R - 2.8                         # 輪のトラスの内側の輪の半径
WHEEL_HUB_Y = 3.6                                    # ハブの両端（スポークの付け根）の y
WHEEL_LEG_Y = 5.3                                    # 脚の頂（軸受け）の y。回るハブ（y ±3.95 まで）から離す
WHEEL_FOOT = (16.0, 7.0)                             # 脚の足もと（軸からの x、y）
PLAZA_X = (-86.0, 4.0)
HALL_X, HALL_Y = (12.0, 78.0), (204.0, 228.5)
TERMINAL_X, TERMINAL_Y = (432.0, 540.0), (229.0, 249.5)
CLOCK_X = 512.0
FERRY_X, FERRY_Y = (TERMINAL_X[0] + TERMINAL_X[1]) / 2 + 4.0, WALL_Y + 8.2
MARINA_PONTOONS = (126.0, 172.0, 218.0, 264.0, 310.0, 356.0)
MARINA_X = (112.0, 414.0)
BREAKWATER = ((566.0, WALL_Y - 0.5), (566.0, 300.0), (478.0, 334.0))    # 岸 → 沖 → 先端（灯台）
BREAKWATER_X = BREAKWATER[0][0]
STEPS = ((-74.0, -6.0), (94.0, 108.0), (410.0, 424.0), (-204.0, -190.0), (-352.0, -338.0), (-480.0, -466.0))

H = hexcol
C = {
    "white": H("#F6F5F1"), "wall": H("#F2EDE2"), "cream": H("#F2D59A"), "peach": H("#F5B281"), "mint": H("#A6D9B4"),
    "sky": H("#A8CAF0"), "sand": H("#E5C68E"), "lemon": H("#F3D66C"), "rose": H("#EFA79C"), "lilac": H("#CDBDEA"),
    "terracotta": H("#D2603A"), "terracotta2": H("#BD5333"), "roof": H("#CDD1D3"), "roof_dark": H("#AEB4B8"),
    "cobalt": H("#2F66C0"), "orange": H("#F08A34"), "teal": H("#2FA39E"), "navy": H("#1F3160"), "yellow": H("#F2C33A"),
    "red": H("#D8413A"),
    "stone": H("#DAD3C4"), "wet": H("#5A6A68"), "coping": H("#F3F1EB"), "step": H("#E6E0D3"), "riser": H("#C9C2B3"),
    "paving": H("#E7DFCF"), "paving2": H("#D8CFBD"), "street": H("#CBC8C1"), "lawn": H("#83B85E"), "plaza": H("#EFE8DA"),
    "trunk": H("#846C50"), "palm_trunk": H("#9C8567"),
    "lamp": H("#29344C"), "glow": H("#FFD9A0"), "dark_glass": H("#2F3D4C"),
    "deck": H("#CBBFA6"), "pontoon_side": H("#8F8B84"), "pile": H("#4B525A"), "rock": H("#9EA3A3"), "rock2": H("#878E90"),
    "hull": H("#F8F7F3"), "hull_blue": H("#2C5BAE"), "boot": H("#2A3340"),
}
PASTELS = ["white", "wall", "cream", "peach", "mint", "sky", "sand", "lemon", "rose", "lilac"]
PASTEL_W = [0.1, 0.08, 0.13, 0.13, 0.11, 0.12, 0.09, 0.09, 0.09, 0.06]
SIGNS = ["navy", "cobalt", "teal", "red", "orange", "white"]
LEAVES = [H("#3C8A38"), H("#4A9B3F"), H("#5BAA46"), H("#3F7F3A")]
CANOPY = [H("#6FAE45"), H("#56993F"), H("#48893B"), H("#3B7A37"), H("#7DB84C")]
AWNINGS = [("cobalt", "white"), ("orange", "white"), ("teal", "white"), ("navy", "cream"), ("red", "white")]
AWNING_W = [0.34, 0.24, 0.18, 0.12, 0.12]


_LAST = {"col": None}


def pick(rnd, names, weights):
    """隣の建物と同じ色にしない。"""
    for _ in range(6):
        name = rnd.choices(names, weights)[0]
        if name != _LAST["col"]:
            break
    _LAST["col"] = name
    return C[name]


# --- 道具 ---------------------------------------------------------------------
def quad_up(m, x0, y0, x1, y1, z, col, mat="paint"):
    """上向きの水平な四角形（x0<x1, y0<y1）。"""
    m.add_face([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], col, mat)


def v_shop(z_rel):
    """shop の外壁の v：いちばん下の段（1/8）が 1 階の店（高さ GF）、上は 3.2m ごと。"""
    return z_rel / GF * 0.125 if z_rel <= GF else 0.125 + (z_rel - GF) / TILE


def v_flat(z_rel):
    return z_rel / TILE


def wall(m, a, b, z0, z1, col, mat="paint", u0=0.0, vfun=None, lo=0.9, hi=1.02, tile_u=TILE):
    """a→b（上から見て反時計回りの外周の辺）の外向きの壁。画像の材質なら UV（u は辺に沿って tile_u ごと）。
    色は下を少し暗く（根元の陰）。返り値は次の辺の u。"""
    (ax, ay), (bx, by) = a, b
    L = math.hypot(bx - ax, by - ay)
    pts = [(ax, ay, z0), (bx, by, z0), (bx, by, z1), (ax, ay, z1)]
    c0 = shade(col, lo + (hi - lo) * min(1.0, (z0 - GROUND) / 30.0))
    c1 = shade(col, lo + (hi - lo) * min(1.0, (z1 - GROUND) / 30.0))
    uv = None
    if vfun is not None:
        v0, v1 = vfun(z0 - GROUND), vfun(z1 - GROUND)
        uv = [(u0, v0), (u0 + L / tile_u, v0), (u0 + L / tile_u, v1), (u0, v1)]
    m.add_face(pts, c0, mat, uv, ccol=[c0, c0, c1, c1])
    return u0 + L / tile_u


def rect_walls(m, x0, x1, y0, y1, z0, z1, col, mat="paint", vfun=None, u0=0.0, back=False, split=None, tile_u=TILE):
    """箱の側面（前 +y・左右。back=True なら後ろも）。split：その高さで面を分ける（shop の 1 階の境）。"""
    ol = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    edges = [(1, 2), (2, 3), (3, 0)] + ([(0, 1)] if back else [])
    zs = [z0, z1] if split is None or not (z0 < split < z1) else [z0, split, z1]
    u = u0
    for i, j in edges:
        for k in range(len(zs) - 1):
            wall(m, ol[i], ol[j], zs[k], zs[k + 1], col, mat, u, vfun, tile_u=tile_u)
        L = math.hypot(ol[j][0] - ol[i][0], ol[j][1] - ol[i][1])
        u += L / tile_u


def hip_roof(m, x0, x1, y0, y1, z, col, pitch=0.36, over=0.45):
    """寄棟の瓦屋根。棟は長い辺に沿う。"""
    x0, x1, y0, y1 = x0 - over, x1 + over, y0 - over, y1 + over
    w, d = x1 - x0, y1 - y0
    h = min(w, d) / 2 * pitch * 2
    if w >= d:
        r0, r1 = (x0 + d / 2, (y0 + y1) / 2, z + h), (x1 - d / 2, (y0 + y1) / 2, z + h)
        m.add_face([(x0, y0, z), (x1, y0, z), r1, r0], shade(col, 0.86))          # 後ろ
        m.add_face([(x1, y1, z), (x0, y1, z), r0, r1], shade(col, 1.04))          # 前
        m.add_face([(x1, y0, z), (x1, y1, z), r1], shade(col, 0.95))
        m.add_face([(x0, y1, z), (x0, y0, z), r0], shade(col, 0.93))
    else:
        r0, r1 = ((x0 + x1) / 2, y0 + w / 2, z + h), ((x0 + x1) / 2, y1 - w / 2, z + h)
        m.add_face([(x0, y0, z), (x1, y0, z), r0], shade(col, 0.86))
        m.add_face([(x1, y0, z), (x1, y1, z), r1, r0], shade(col, 0.95))
        m.add_face([(x1, y1, z), (x0, y1, z), r1], shade(col, 1.04))
        m.add_face([(x0, y1, z), (x0, y0, z), r0, r1], shade(col, 0.93))
    # 軒の裏（下から見える高い建物のため）
    m.add_face([(x0, y1, z), (x1, y1, z), (x1, y0, z), (x0, y0, z)], shade(col, 0.62))
    return h


def cornice(m, x0, x1, y1, z, col, depth=0.45, h=0.5, out=0.28):
    """屋上の縁の白い帯（前と左右へ少し張り出す）。"""
    m.box_lohi((x0 - out, y1 - depth, z), (x1 + out, y1 + out, z + h), col, faces=["+y", "top", "bottom", "-x", "+x"])


def rail_band(m, x0, x1, y, z, col=None, h=1.0):
    """手すり（ガラスか白い格子に見える帯）：前面と上面。"""
    col = col or H("#DCE9EF")
    m.box_lohi((x0, y - 0.08, z), (x1, y, z + h), col, faces=["+y", "top", "-x", "+x"])


def balcony(m, x0, x1, y1, z, depth=1.3, slab=C["white"], rail=None):
    m.box_lohi((x0, y1, z - 0.12), (x1, y1 + depth, z + 0.14), slab, faces=["+y", "top", "bottom", "-x", "+x"])
    rail_band(m, x0, x1, y1 + depth, z + 0.14, rail)


def awning(m, x0, x1, y1, z_top, cols, depth=1.9, drop=0.75, sw=0.95):
    """縞の日よけ（1 階の店の上）。"""
    n = max(2, int(round((x1 - x0) / sw)))
    zb = z_top - drop
    for i in range(n):
        xa = x0 + (x1 - x0) * i / n
        xb = x0 + (x1 - x0) * (i + 1) / n
        col = C[cols[i % 2]]
        m.add_face([(xa, y1, z_top), (xb, y1, z_top), (xb, y1 + depth, zb), (xa, y1 + depth, zb)], shade(col, 1.02))
        m.add_face([(xb, y1 + depth, zb - 0.38), (xa, y1 + depth, zb - 0.38), (xa, y1 + depth, zb), (xb, y1 + depth, zb)], col)
    m.add_face([(x0, y1, z_top), (x0, y1 + depth, zb), (x1, y1 + depth, zb), (x1, y1, z_top)], shade(C[cols[0]], 0.55))


def potted_palm(m, rnd, x, y, z):
    """屋上の鉢植えのヤシ（小さい）。"""
    m.box((x, y, z + 0.35), (0.9, 0.9, 0.7), H("#C7B8A0"), faces=["+y", "-y", "-x", "+x", "top"])
    h = rnd.uniform(2.2, 3.2)
    m.tube((x, y, z + 0.7), (x, y, z + 0.7 + h), 0.14, C["palm_trunk"], n=4, smooth=False)
    top = (x, y, z + 0.7 + h)
    for i in range(6):
        a = 2 * math.pi * (i + rnd.uniform(-0.2, 0.2)) / 6
        dx, dy = math.cos(a), math.sin(a)
        tip = (x + dx * 1.7, y + dy * 1.7, top[2] - 0.5)
        mid = (x + dx * 0.9, y + dy * 0.9, top[2] + 0.2)
        w = 0.35
        m.tri2((top[0] - dy * w, top[1] + dx * w, top[2]), (top[0] + dy * w, top[1] - dx * w, top[2]), mid, rnd.choice(LEAVES))
        m.tri2((mid[0] - dy * w, mid[1] + dx * w, mid[2]), (mid[0] + dy * w, mid[1] - dx * w, mid[2]), tip, rnd.choice(LEAVES))


def cypress(m, rnd, x, y, z, h=None):
    h = h or rnd.uniform(4.0, 6.5)
    r = h * rnd.uniform(0.12, 0.15)
    col = rnd.choice([H("#2F6036"), H("#36693A"), H("#2A5532")])
    m.prism(x, y, z, z + h * 0.3, r * 0.75, r, 6, shade(col, 0.9), cap_bottom=False, cap_top=False)
    m.cone(x, y, z + h * 0.3, z + h, r, 6, col)


def planter(m, rnd, x, y, z, w=1.6):
    """花のプランター：白い箱に緑と花の色。"""
    m.box_lohi((x - w / 2, y - 0.35, z), (x + w / 2, y + 0.35, z + 0.55), C["white"], faces=["+y", "-x", "+x", "top"])
    gc = rnd.choice(CANOPY)
    m.blob((x, y, z + 0.6), w * 0.5, 0.42, 0.4, shade(gc, 1.1), shade(gc, 0.75), seg=5, rings=2)
    fc = rnd.choice([H("#E0463C"), H("#F07AA0"), H("#F4C542"), H("#FFFFFF"), H("#B05AC8")])
    m.box((x + rnd.uniform(-0.3, 0.3), y + 0.3, z + 0.8), (w * 0.55, 0.2, 0.22), fc, faces=["+y", "top", "-x", "+x"])


def parasol(m, x, y, z, col, r=1.5):
    m.tube((x, y, z), (x, y, z + 2.3), 0.07, C["white"], n=4, smooth=False)
    m.prism(x, y, z + 2.0, z + 2.55, r, 0.12, 8, col, cap_bottom=True)


def tank(m, rnd, x, y, z):
    col = C["cobalt"] if rnd.random() < 0.25 else H("#E4E6E6")
    m.box((x, y, z + 0.4), (2.4, 2.4, 0.8), C["roof_dark"], faces=["+y", "top", "-x", "+x"])
    m.prism(x, y, z + 0.8, z + 3.0, 1.2, 1.2, 8, col, cap_bottom=False)
    m.cone(x, y, z + 3.0, z + 3.5, 1.2, 8, shade(col, 0.95))


def roof_kit(m, rnd, x0, x1, y0, y1, z):
    """屋上：給水槽・空調の箱・塔屋・アンテナ・太陽光の板。"""
    w, d = x1 - x0, y1 - y0
    if rnd.random() < 0.6:
        tank(m, rnd, rnd.uniform(x0 + 2, x1 - 2), rnd.uniform(y0 + 2, y1 - 3), z)
    for _ in range(rnd.randint(1, 3)):
        bx, by = rnd.uniform(x0 + 1.2, x1 - 1.2), rnd.uniform(y0 + 1.2, y1 - 2.5)
        m.box((bx, by, z + 0.45), (1.3, 0.9, 0.9), H("#C4C9CC"), faces=["+y", "top", "-x", "+x"])
    if rnd.random() < 0.5 and w > 10:
        bx = rnd.uniform(x0 + 3, x1 - 3)
        m.box((bx, (y0 + y1) / 2, z + 1.5), (3.2, 3.0, 3.0), C["wall"], faces=["+y", "top", "-x", "+x"])
    if rnd.random() < 0.35:
        ax = rnd.uniform(x0 + 1, x1 - 1)
        m.tube((ax, y0 + d * 0.4, z), (ax, y0 + d * 0.4, z + rnd.uniform(4, 7)), 0.12, H("#B9BEC2"), n=4, smooth=False)
    if rnd.random() < 0.25 and w > 12:
        for k in range(3):
            px = x0 + 2 + k * 2.4
            m.add_face([(px, y0 + 2, z + 1.2), (px + 2.0, y0 + 2, z + 1.2), (px + 2.0, y0 + 4.2, z + 0.3), (px, y0 + 4.2, z + 0.3)],
                       H("#2C4270"))


# --- 木・灯・旗 ---------------------------------------------------------------
def palm(m, rnd, x, y, h=None):
    h = h or rnd.uniform(9.0, 12.5)
    lean = (rnd.uniform(-1, 1), rnd.uniform(-0.6, 0.4))
    pts = []
    for k in range(6):
        t = k / 5
        pts.append((x + lean[0] * 1.6 * t * t, y + lean[1] * 1.6 * t * t, GROUND + h * t))
    for k in range(5):
        r = 0.42 - 0.12 * k / 4
        m.tube(pts[k], pts[k + 1], r, shade(C["palm_trunk"], 0.92 + 0.04 * k), n=5, smooth=False)
    top = pts[-1]
    m.blob(top, 0.7, 0.7, 0.6, H("#6E8A3A"), H("#4C6528"), seg=5, rings=3)
    nf = 9
    for i in range(nf):
        a = 2 * math.pi * (i + rnd.uniform(-0.2, 0.2)) / nf
        ln = rnd.uniform(4.2, 5.6)
        droop = rnd.uniform(0.25, 0.6)
        col = rnd.choice(LEAVES)
        dx, dy = math.cos(a), math.sin(a)
        sx, sy = -dy, dx
        prev_c, prev_w = top, 0.25
        for s in range(1, 5):
            t = s / 4
            c = (top[0] + dx * ln * t, top[1] + dy * ln * t, top[2] + ln * (0.35 * t - droop * t * t) * 1.0)
            w = 0.95 * math.sin(math.pi * min(1.0, t * 1.15)) + 0.05
            a0 = (prev_c[0] + sx * prev_w, prev_c[1] + sy * prev_w, prev_c[2])
            b0 = (prev_c[0] - sx * prev_w, prev_c[1] - sy * prev_w, prev_c[2])
            a1 = (c[0] + sx * w, c[1] + sy * w, c[2] - 0.05)
            b1 = (c[0] - sx * w, c[1] - sy * w, c[2] - 0.05)
            m.quad2(a0, b0, b1, a1, shade(col, 0.95 + 0.1 * t))
            prev_c, prev_w = c, w


def round_tree(m, rnd, x, y, s=1.0):
    h = rnd.uniform(2.4, 3.2) * s
    m.tube((x, y, GROUND), (x, y, GROUND + h + 1.0), 0.28 * s, C["trunk"], n=5, smooth=False)
    col = rnd.choice(CANOPY)
    r = rnd.uniform(2.6, 3.4) * s
    m.blob((x, y, GROUND + h + r * 0.7), r, r, r * 0.85, shade(col, 1.08), shade(col, 0.62), seg=7, rings=4)
    for _ in range(2):
        ox, oy = rnd.uniform(-1, 1) * r * 0.6, rnd.uniform(-1, 1) * r * 0.5
        rr = r * rnd.uniform(0.55, 0.75)
        m.blob((x + ox, y + oy, GROUND + h + r * rnd.uniform(0.9, 1.3)), rr, rr, rr * 0.85, shade(col, 1.12), shade(col, 0.7),
               seg=6, rings=3)


def lamp_post(m, x, y, h=5.2):
    m.tube((x, y, GROUND), (x, y, GROUND + h), 0.16, C["lamp"], n=4, smooth=False)
    m.box((x, y, GROUND + h + 0.1), (0.9, 0.3, 0.14), C["lamp"])
    for sx in (-1, 1):
        m.box((x + sx * 0.5, y, GROUND + h - 0.3), (0.6, 0.6, 0.7), C["glow"], "night")
        m.cone(x + sx * 0.5, y, GROUND + h + 0.05, GROUND + h + 0.45, 0.46, 4, C["lamp"], phase=math.pi / 4)


def banner_pole(m, x, y, cols, h=9.5):
    m.tube((x, y, GROUND), (x, y, GROUND + h), 0.14, C["white"], n=4, smooth=False)
    m.tube((x, y, GROUND + h - 0.2), (x + 1.3, y, GROUND + h - 0.2), 0.06, C["white"], n=4, smooth=False)
    z1, z0 = GROUND + h - 0.3, GROUND + h - 4.0
    # 縦の旗（2 色の縦縞）
    xm = x + 0.15 + 0.6
    m.quad2((x + 0.15, y, z0), (xm, y, z0), (xm, y, z1), (x + 0.15, y, z1), C[cols[0]])
    m.quad2((xm, y, z0), (x + 1.35, y, z0), (x + 1.35, y, z1), (xm, y, z1), C[cols[1]])


def bunting(m, a, b, sag, cols):
    """2 点のあいだの小旗の列。"""
    (ax, ay, az), (bx, by, bz) = a, b
    n = max(3, int(math.hypot(bx - ax, by - ay) / 1.4))
    for i in range(n):
        t0, t1 = i / n, (i + 0.72) / n
        p0 = (ax + (bx - ax) * t0, ay + (by - ay) * t0, az + (bz - az) * t0 - sag * 4 * t0 * (1 - t0))
        p1 = (ax + (bx - ax) * t1, ay + (by - ay) * t1, az + (bz - az) * t1 - sag * 4 * t1 * (1 - t1))
        tip = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2 - 0.8)
        m.tri2(p0, p1, tip, C[cols[i % len(cols)]])


# --- 護岸・歩道 ----------------------------------------------------------------
def quay(m, rnd, gaps):
    """護岸：濡れた帯・石積み（6m ごとに色の揺らぎ）・コバルトの細い帯・白い笠石。gaps は階段の x 範囲。"""
    z_wet0, z_wet1, z_band0, z_band1 = -1.8, 0.95, GROUND - 1.25, GROUND - 0.8
    def band(z0, z1, col_fn, step, offset):
        x = X0 - offset
        while x < X1 - 1e-6:
            xa, xe = max(X0, x), min(X1, x + step)
            if xe - xa > 1e-3:
                m.add_face([(xe, WALL_Y, z0), (xa, WALL_Y, z0), (xa, WALL_Y, z1), (xe, WALL_Y, z1)], col_fn())
            x += step
    zm = (z_wet1 + z_band0) / 2
    band(z_wet0, z_wet1, lambda: shade(C["wet"], 1.0 + rnd.uniform(-0.05, 0.05)), 6.0, 0.0)
    band(z_wet1, zm - 0.06, lambda: shade(C["stone"], 1.0 + rnd.uniform(-0.07, 0.04)), 3.0, 0.0)
    band(zm - 0.06, zm + 0.06, lambda: shade(C["stone"], 0.8), 30.0, 0.0)                      # 段の境の目地
    band(zm + 0.06, z_band0, lambda: shade(C["stone"], 1.0 + rnd.uniform(-0.07, 0.04)), 3.0, 1.5)
    band(z_band0, z_band1, lambda: C["cobalt"], 30.0, 0.0)
    band(z_band1, GROUND - 0.15, lambda: shade(C["stone"], 1.02), 30.0, 0.0)
    # 笠石（前へ張り出す白い帯）
    m.box_lohi((X0, QUAY_Y - 0.9, GROUND - 0.15), (X1, WALL_Y + 0.3, COPING_Z), C["coping"], faces=["+y", "top", "bottom", "-x", "+x"])
    # 端の側面
    for xe, s in ((X0, -1), (X1, 1)):
        pts = [(xe, QUAY_Y - 6, -1.8), (xe, WALL_Y, -1.8), (xe, WALL_Y, GROUND), (xe, QUAY_Y - 6, GROUND)]
        m.add_face(pts if s > 0 else pts[::-1], C["stone"])
    # 係船柱（階段の前は置かない）
    x = X0 + 5.0
    while x < X1:
        if not any(g0 - 2 < x < g1 + 2 for g0, g1 in gaps):
            m.prism(x, WALL_Y - 0.25, COPING_Z, COPING_Z + 0.55, 0.3, 0.26, 5, H("#3D4550"), cap_bottom=False)
        x += 11.0


def steps(m, x0, x1, n=8, depth=0.95):
    """護岸の前の水へ下りる階段（前へ張り出す）。両脇は白い笠石の低い壁。"""
    z_top, z_bot = COPING_Z, 0.25
    rise = (z_top - z_bot) / n
    for i in range(n):
        y0 = WALL_Y + 0.3 + i * depth
        y1 = y0 + depth
        zt = z_top - (i + 1) * rise
        m.add_face([(x0, y0, zt), (x1, y0, zt), (x1, y1, zt), (x0, y1, zt)], C["step"])                   # 踏み面
        m.add_face([(x1, y1, zt - rise), (x0, y1, zt - rise), (x0, y1, zt), (x1, y1, zt)], C["riser"])          # 蹴上げ（+y）
    y_end = WALL_Y + 0.3 + n * depth
    m.add_face([(x1, y_end, -1.8), (x0, y_end, -1.8), (x0, y_end, z_bot - rise), (x1, y_end, z_bot - rise)], C["wet"])
    for xs, s in ((x0 - 0.8, -1), (x1, 1)):
        m.box_lohi((xs, WALL_Y, -1.8), (xs + 0.8, y_end + 0.2, COPING_Z - 0.02), C["stone"], top=C["coping"],
                   faces=["+y", "top", "-x", "+x"])


def railing(m, gaps, x0=X0, x1=X1, y=QUAY_Y + 0.1):
    """護岸の手すり：白い上の横木・中の横木と、3m ごとの柱。gaps（階段・桟橋）は開ける。"""
    spans = []
    x = x0
    for g0, g1 in sorted(gaps):
        if g1 < x0 or g0 > x1:
            continue
        if g0 > x:
            spans.append((x, g0))
        x = max(x, g1)
    if x < x1:
        spans.append((x, x1))
    for a, b in spans:
        if b - a < 1.0:
            continue
        m.box_lohi((a, y - 0.1, COPING_Z + 1.0), (b, y + 0.1, COPING_Z + 1.2), C["white"], faces=["+y", "top", "bottom", "-x", "+x"])
        m.box_lohi((a, y - 0.05, COPING_Z + 0.5), (b, y + 0.05, COPING_Z + 0.62), C["white"], faces=["+y", "top", "bottom"])
        n = max(1, int((b - a) / 3.0))
        for k in range(n + 1):
            px = a + (b - a) * k / n
            m.box_lohi((px - 0.13, y - 0.13, COPING_Z), (px + 0.13, y + 0.13, COPING_Z + 1.0), C["white"], faces=["+y", "-x", "+x"])


def paving(m, rnd, holes):
    """歩道（プロムナード）と街の足もとの舗装。holes：舗装しない x 範囲（広場は別に張る）。"""
    # 歩道：8m ごとに濃い帯
    x = X0
    while x < X1 - 1e-6:
        xe = min(X1, x + 8.0)
        quad_up(m, x, PROM_Y0, xe - 1.2, QUAY_Y - 0.9, PAVE_Z, C["paving"])
        quad_up(m, xe - 1.2, PROM_Y0, xe, QUAY_Y - 0.9, PAVE_Z, C["paving2"])
        x = xe
    # 街の中（通り）：明るい灰色
    quad_up(m, X0, ROW3_MIN_Y - 3, X1, PROM_Y0, PAVE_Z - 0.1, C["street"])


def promenade(m, rnd, skip, skip_trees=()):
    """歩道の灯・ヤシ・並木・旗の柱。skip：何も置かない x 範囲（ターミナル）、skip_trees：奥の並木だけ置かない範囲（観覧車の乗り場）。"""
    def free(x, pad=0.0, extra=()):
        return not any(a - pad < x < b + pad for a, b in list(skip) + list(extra))
    x = X0 + 6.0
    k = 0
    while x < X1 - 4:
        if free(x, 1.0):
            lamp_post(m, x, QUAY_Y - 2.0)
        if free(x + 8.0, 3.0) and x + 8.0 < X1 - 3:
            palm(m, rnd, x + 8.0 + rnd.uniform(-1, 1), QUAY_Y - 6.2 + rnd.uniform(-0.6, 0.6))
        if k % 2 == 0 and free(x + 4.0, 4.0, skip_trees) and rnd.random() < 0.8:
            round_tree(m, rnd, x + 4.0 + rnd.uniform(-1.5, 1.5), PROM_Y0 + 8.5 + rnd.uniform(-1, 1), rnd.uniform(0.85, 1.1))
        if free(x + 12.0, 1.5) and x + 12.0 < X1 - 3:
            planter(m, rnd, x + 12.0, QUAY_Y - 1.6, PAVE_Z)
        if k % 3 == 1 and free(x + 12.0, 2.0):
            cols = rnd.choice([("cobalt", "white"), ("orange", "white"), ("cobalt", "orange"), ("teal", "white")])
            banner_pole(m, x + 12.0, QUAY_Y - 3.6, cols)
        x += 16.0
        k += 1


# --- 建物 ---------------------------------------------------------------------
# --- 建物の型（2026-09-29 追加） --------------------------------------------------------
# 窓の格子がそろいすぎて単調だったので、実在のアパート・マンションの外観の型（Web の資料：マンションの横ライン・縦ライン・
# 手すりの種類（ガラス・すりガラス・腰壁・格子）、外廊下と外階段のアパート、ロッジア、出窓、散らしたバルコニー、
# 運河の家の破風）と、Codex の見本帳 source/concepts/r7_building_catalogue.png の 12 の型で作り分ける。
# 建物ごとに外壁の画像の 1 スパン・1 階の長さを変えるので、隣り合う建物の窓の高さと間隔がそろわない。隣に同じ型を置かない。

FACADE_STYLES = ("shop", "flat", "glass", "mansion", "tile", "corridor", "loggia", "brick", "ribbon", "punched")
BRICKS = ["#B5654A", "#9C5642", "#C98B5E", "#A8704F", "#C47A5A", "#8E5A48"]
PAINTED = ["#3F4E6E", "#3E6152", "#EFE0C0", "#DCE6EE", "#5A4A6E", "#E9D7B5"]


class Skin:
    """外壁の画像の貼り方（建物ごと）。style＝材質キー、bay・floor＝画像の 1 マスの幅と高さ（m）、gf＝1 階の店の高さ（shop）。"""

    def __init__(self, rnd, style, bay, floor, gf=None):
        self.style, self.bay, self.floor, self.gf = style, bay, floor, gf
        self.tile_u = bay * 8
        self.u0 = rnd.randint(0, 7) / 8
        self.v0 = 0.0 if gf else rnd.randint(0, 7) / 8

    def v(self, z_rel):
        if self.gf:
            return z_rel / self.gf * 0.125 if z_rel <= self.gf else 0.125 + (z_rel - self.gf) / (self.floor * 8)
        return self.v0 + z_rel / (self.floor * 8)

    def walls(self, m, x0, x1, y0, y1, z0, z1, col, back=False):
        rect_walls(m, x0, x1, y0, y1, z0, z1, col, self.style, self.v, self.u0, back=back,
                   split=GROUND + self.gf if self.gf else None, tile_u=self.tile_u)

    def front_u(self, x, x1, y0, y1):
        """前面（y1、x1 → x0 の向きに貼る）の位置 x の u。"""
        return self.u0 + (y1 - y0) / self.tile_u + (x1 - x) / self.tile_u

    def front_face(self, m, pts, x1, y0, y1, col):
        """前面の平面にある多角形（(x, z) の列、外から見て反時計回り）を、壁と続く UV で貼る。"""
        uv = [(self.front_u(x, x1, y0, y1), self.v(z - GROUND)) for x, z in pts]
        m.add_face([(x, y1, z) for x, z in pts], col, self.style, uv)

    def front_fan(self, m, center, boundary, x1, y0, y1, col):
        """前面の扇（center から、x0 → x1 の順の縁の点へ）。"""
        for a, b in zip(boundary[:-1], boundary[1:]):
            self.front_face(m, [center, a, b], x1, y0, y1, col)


def roof_top(m, rnd, x0, x1, y0, y1, z, garden=0.4):
    """平らな屋根：縁の笠木と、屋上の設備か屋上庭園。"""
    quad_up(m, x0, y0, x1, y1, z, C["roof"])
    cornice(m, x0, x1, y1, z, C["white"], out=0.2, h=0.4)
    roof_kit(m, rnd, x0 + 1.5, x1 - 1.5, y0 + 1.5, y1 - 1.0, z + 0.4)
    if rnd.random() < garden:
        rail_band(m, x0 + 1.0, x1 - 1.0, y1 - 0.3, z + 0.4, H("#E3ECF0"), 0.9)
        potted_palm(m, rnd, rnd.uniform(x0 + 2, x1 - 2), y1 - 2.0, z + 0.4)
        for _ in range(rnd.randint(1, 3)):
            planter(m, rnd, rnd.uniform(x0 + 1.5, x1 - 1.5), y1 - 1.3, z + 0.4)
        if rnd.random() < 0.4:
            cypress(m, rnd, rnd.uniform(x0 + 2, x1 - 2), y1 - 3.0, z + 0.4, rnd.uniform(3.0, 4.5))


def shop_house(m, rnd, x0, x1, y0, y1, floors):
    """地中海の家（1 列目）：1 階が店（アーチの開口）、上は鎧戸と花箱の窓。日よけ・看板板・パラソル、瓦屋根か屋上テラス。"""
    col = pick(rnd, PASTELS, PASTEL_W)
    sk = Skin(rnd, "shop", rnd.uniform(2.8, 3.7), rnd.uniform(3.0, 3.5), gf=rnd.uniform(3.8, 4.6))
    z_top = GROUND + sk.gf + sk.floor * floors
    sk.walls(m, x0, x1, y0, y1, GROUND, z_top, col)
    gf = sk.gf
    if rnd.random() < 0.75:
        awning(m, x0 + 0.5, x1 - 0.5, y1, GROUND + gf - 0.55, rnd.choices(AWNINGS, AWNING_W)[0])
        # 看板板（日よけの上、1 階と 2 階のあいだ）
        sw = (x1 - x0) * rnd.uniform(0.35, 0.6)
        sx = rnd.uniform(x0 + 1.0 + sw / 2, x1 - 1.0 - sw / 2) if x1 - x0 > sw + 2.0 else (x0 + x1) / 2
        sc = C[rnd.choice(SIGNS)]
        m.box_lohi((sx - sw / 2, y1, GROUND + gf - 0.5), (sx + sw / 2, y1 + 0.3, GROUND + gf + 0.15), sc,
                   faces=["+y", "top", "-x", "+x"])
        m.box_lohi((sx - sw / 2 + 0.3, y1 + 0.3, GROUND + gf - 0.3), (sx + sw / 2 - 0.3, y1 + 0.3 + GAP, GROUND + gf - 0.05),
                   C["white"] if sc != C["white"] else C["navy"], faces=["+y"])
        # カフェの席：同じ色のパラソルを前に 1〜2 列
        pc = C[rnd.choice(["white", "yellow", "cobalt", "white", "orange", "teal"])]
        n = max(2, int((x1 - x0) / 3.6))
        for k in range(n):
            px = x0 + (x1 - x0) * (k + 0.5) / n
            parasol(m, px, y1 + 3.6, PAVE_Z, pc, r=1.35)
            if rnd.random() < 0.4:
                parasol(m, px + 1.2, y1 + 7.0, PAVE_Z, pc, r=1.35)
    if floors >= 2 and rnd.random() < 0.45:
        balcony(m, x0 + 1.0, x1 - 1.0, y1, GROUND + gf + 0.05, depth=1.1, slab=C["white"], rail=H("#E9EEF0"))
    if rnd.random() < 0.5:
        hip_roof(m, x0, x1, y0, y1, z_top, rnd.choice([C["terracotta"], C["terracotta2"]]))
    else:
        quad_up(m, x0, y0, x1, y1, z_top, C["roof"])
        cornice(m, x0, x1, y1, z_top, C["white"])
        rail_band(m, x0 + 0.4, x1 - 0.4, y1 - 0.5, z_top + 0.5, H("#E9EEF0"), 0.9)
        # 屋上テラス：パラソル・鉢植えのヤシ・縁の植栽
        for _ in range(rnd.randint(1, 3)):
            parasol(m, rnd.uniform(x0 + 2, x1 - 2), rnd.uniform(y0 + 3, y1 - 3), z_top + 0.5,
                    C[rnd.choice(["white", "orange", "cobalt", "yellow"])], r=1.3)
        if rnd.random() < 0.7:
            potted_palm(m, rnd, rnd.uniform(x0 + 1.5, x1 - 1.5), y1 - 1.6, z_top + 0.5)
        if rnd.random() < 0.35:
            cypress(m, rnd, rnd.uniform(x0 + 1.5, x1 - 1.5), rnd.uniform(y0 + 2, y1 - 3), z_top + 0.5, rnd.uniform(3.0, 4.5))
        for _ in range(rnd.randint(1, 3)):
            planter(m, rnd, rnd.uniform(x0 + 1.5, x1 - 1.5), y1 - 1.0, z_top + 0.5)
    return z_top


def apartment(m, rnd, x0, x1, y0, y1, floors):
    """集合住宅・ホテル（大きな掃き出し窓）：横に通るバルコニーの白い帯、最上階の後退、屋上の設備、ときどき瓦屋根。"""
    col = pick(rnd, ["white", "wall", "cream", "sand", "sky", "peach"], [0.3, 0.2, 0.15, 0.12, 0.13, 0.1])
    fh = rnd.uniform(3.0, 3.3)
    sk = Skin(rnd, "flat", rnd.uniform(2.9, 3.5), fh)
    z_top = GROUND + fh * floors
    setback = floors >= 6 and rnd.random() < 0.45
    z_body = z_top - fh if setback else z_top
    sk.walls(m, x0, x1, y0, y1, GROUND, z_body, col)
    if setback:
        sb = 2.6
        sk.walls(m, x0 + 1.2, x1 - 1.2, y0, y1 - sb, z_body, z_top, col)
        quad_up(m, x0, y1 - sb, x1, y1, z_body, C["roof"])
        rail_band(m, x0 + 0.2, x1 - 0.2, y1, z_body, H("#E3ECF0"), 1.0)
        y_roof1 = y1 - sb
    else:
        y_roof1 = y1
    if rnd.random() < 0.75:
        inset = 0.0 if rnd.random() < 0.4 else 1.2
        k = 1
        while GROUND + fh * k < z_body - fh * 0.5:
            balcony(m, x0 + inset, x1 - inset, y1, GROUND + fh * k, depth=1.35)
            k += 1
    if rnd.random() < 0.16:
        quad_up(m, x0, y0, x1, y_roof1, z_top, C["roof"])
        hip_roof(m, x0, x1, y0, y_roof1, z_top, rnd.choice([C["terracotta"], C["terracotta2"]]), pitch=0.3)
    else:
        xi = 1.2 if setback else 0.0
        roof_top(m, rnd, x0 + xi, x1 - xi, y0, y_roof1, z_top, garden=0.45)
    return z_top


def mansion_h(m, rnd, x0, x1, y0, y1, floors):
    """横ラインのマンション：各階に続くバルコニー（手すりはガラス・すりガラス・腰壁・格子・腰壁＋ガラス）、
    両端の額縁の柱と頂部の梁、住戸の隔て板、1 階の入口と庇。"""
    fh = rnd.uniform(2.9, 3.15)
    sk = Skin(rnd, "mansion", rnd.uniform(3.0, 3.4), fh)
    col = H(rnd.choice(["#F2F2EE", "#E4E6E6", "#E9E0D0", "#D8D4CC", "#EEF0F2", "#E6E1DA"]))
    fcol = H(rnd.choice(["#FFFFFF", "#5B6168", "#C9B69C", "#8C8F93", "#F4F1EA", "#A9876A"]))
    z_top = GROUND + fh * floors + 0.5
    depth = rnd.uniform(1.4, 1.8)
    fw = rnd.uniform(1.0, 1.6)
    sk.walls(m, x0, x1, y0, y1, GROUND, z_top, col)
    for fx0, fx1 in ((x0 - 0.1, x0 + fw), (x1 - fw, x1 + 0.1)):
        m.box_lohi((fx0, y1, GROUND), (fx1, y1 + depth + 0.25, z_top + 0.5), fcol, faces=["+y", "-x", "+x", "top"])
    xa, xb = x0 + fw, x1 - fw
    m.box_lohi((xa, y1, z_top - 0.3), (xb, y1 + depth + 0.25, z_top + 0.45), fcol, faces=["+y", "top", "bottom"])
    parapet = rnd.choice(["glass", "frosted", "wall", "lattice", "half"])
    pcol = {"glass": H("#B9D5E4"), "frosted": H("#E4ECF0"), "wall": col, "lattice": H("#56606B"), "half": col}[parapet]
    n_units = max(1, int(round((xb - xa) / rnd.uniform(5.8, 7.2))))
    for k in range(1, floors):
        z = GROUND + fh * k
        m.box_lohi((xa, y1, z - 0.2), (xb, y1 + depth, z + 0.05), H("#F4F4F2"), faces=["+y", "top", "bottom"])
        if parapet == "half":
            m.box_lohi((xa, y1 + depth - 0.14, z + 0.05), (xb, y1 + depth, z + 0.55), col, faces=["+y", "top"])
            m.box_lohi((xa, y1 + depth - 0.1, z + 0.55), (xb, y1 + depth - 0.04, z + 1.1), H("#C6DDE8"), faces=["+y", "top"])
        else:
            m.box_lohi((xa, y1 + depth - 0.12, z + 0.05), (xb, y1 + depth, z + 1.1), pcol, faces=["+y", "top"])
        for u in range(1, n_units):
            dx = xa + (xb - xa) * u / n_units
            m.box_lohi((dx - 0.08, y1, z + 0.05), (dx + 0.08, y1 + depth - 0.14, z + fh - 0.22), H("#EEF2F3"), faces=["+y", "-x", "+x"])
    ex = rnd.uniform(xa + 1.0, max(xa + 1.2, xb - 5.0))
    m.box_lohi((ex, y1, GROUND), (ex + 4.0, y1 + GAP, GROUND + 2.7), C["dark_glass"], faces=["+y", "top"])
    m.box_lohi((ex - 0.6, y1, GROUND + 2.7), (ex + 4.6, y1 + 1.8, GROUND + 3.0), fcol, faces=["+y", "top", "bottom", "-x", "+x"])
    quad_up(m, x0, y0, x1, y1, z_top, C["roof"])
    roof_kit(m, rnd, x0 + 1.5, x1 - 1.5, y0 + 1.5, y1 - 1.0, z_top)
    if rnd.random() < 0.4:
        potted_palm(m, rnd, rnd.uniform(xa + 1, xb - 1), y1 - 1.5, z_top)
    return z_top


def mansion_v(m, rnd, x0, x1, y0, y1, floors):
    """縦ラインのタイル張りのマンション：縦長の窓の列、画像の柱の列にそろえた縦の柱、石張りの基壇と店のガラス、頂部の帯。"""
    fh = rnd.uniform(3.0, 3.25)
    sk = Skin(rnd, "tile", rnd.uniform(2.9, 3.3), fh)
    col = H(rnd.choice(["#B98D6C", "#D6C2A2", "#9A8F86", "#E4DACB", "#A87560", "#C9B08E"]))
    z_top = GROUND + fh * floors
    sk.walls(m, x0, x1, y0, y1, GROUND, z_top, col)
    base_h = fh * (2 if floors >= 6 else 1)
    stone = H(rnd.choice(["#8E8983", "#CFC9BE", "#6F6B67", "#B7AFA4"]))
    m.box_lohi((x0 - 0.25, y1, GROUND), (x1 + 0.25, y1 + 0.35, GROUND + base_h), stone, faces=["+y", "top", "-x", "+x"])
    x = x0 + rnd.uniform(1.0, 2.5)
    while x < x1 - 4.0:
        w = rnd.uniform(3.0, 6.5)
        if x + w > x1 - 1.0:
            break
        m.box_lohi((x, y1 + 0.35, GROUND + 0.3), (x + w, y1 + 0.35 + GAP, GROUND + min(base_h, fh + 1.0) - 0.5), C["dark_glass"],
                   faces=["+y", "top", "-x", "+x"])
        x += w + rnd.uniform(1.2, 3.0)
    fcol = shade(col, 0.8)
    us, ue = sk.front_u(x1, x1, y0, y1), sk.front_u(x0, x1, y0, y1)
    for k in range(int(math.floor(us)) - 1, int(math.ceil(ue)) + 1):
        for c in (2, 5, 7):                              # 画像の柱の列（make_textures.facade_tile の layout）
            u = k + (c + 0.5) / 8
            if us < u < ue:
                px = x1 - (u - us) * sk.tile_u
                if x0 + 0.8 < px < x1 - 0.8:
                    m.box_lohi((px - 0.45, y1, GROUND + base_h), (px + 0.45, y1 + 0.55, z_top + 0.3), fcol,
                               faces=["+y", "-x", "+x", "top"])
    m.box_lohi((x0 - 0.2, y1 - 0.3, z_top), (x1 + 0.2, y1 + 0.6, z_top + 1.0), fcol, faces=["+y", "top", "bottom", "-x", "+x"])
    quad_up(m, x0, y0, x1, y1 - 0.3, z_top + 0.4, C["roof"])
    roof_kit(m, rnd, x0 + 1.5, x1 - 1.5, y0 + 1.5, y1 - 1.5, z_top + 0.4)
    return z_top


def apato(m, rnd, x0, x1, y0, y1, floors):
    """アパート（2〜3 階）：前面が外廊下（床の帯・手すり・柱）、玄関扉の並ぶ壁、端の外階段（折り返し）、前へ出る屋根。"""
    floors = max(2, min(3, floors))
    fh = rnd.uniform(2.75, 2.95)
    sk = Skin(rnd, "corridor", rnd.uniform(3.0, 3.3), fh)
    col = H(rnd.choice(["#F1F1EE", "#D9DCDD", "#4B5B78", "#B9C7B0", "#E7DCC6", "#6B7C8F", "#C9B8A0"]))
    rail = H(rnd.choice(["#F4F4F2", "#3D4652", "#8A949C", "#2F5FA8"]))
    cd = 1.4
    yb = y1 - cd
    z_top = GROUND + fh * floors
    sk.walls(m, x0, x1, y0, yb, GROUND, z_top, col)
    for k in range(1, floors):
        z = GROUND + fh * k
        m.box_lohi((x0, yb, z - 0.2), (x1, y1, z), C["white"], faces=["+y", "top", "bottom", "-x", "+x"])
        m.box_lohi((x0, y1 - 0.06, z), (x1, y1, z + 1.0), mix(rail, C["white"], 0.45), faces=["+y", "top", "-x", "+x"])
        m.box_lohi((x0 - 0.02, y1 - 0.1, z + 1.0), (x1 + 0.02, y1 + 0.06, z + 1.12), rail, faces=["+y", "top", "bottom"])
    m.box_lohi((x0 - 0.3, y0 - 0.1, z_top), (x1 + 0.3, y1 + 0.35, z_top + 0.3), H(rnd.choice(["#F4F4F2", "#4A515A", "#8A949C"])),
               faces=["+y", "top", "bottom", "-x", "+x"])
    n = max(2, int((x1 - x0) / 6.0) + 1)
    for i in range(n):
        px = x0 + 0.2 + (x1 - x0 - 0.4) * i / (n - 1)
        m.box_lohi((px - 0.1, y1 - 0.3, GROUND), (px + 0.1, y1 - 0.1, z_top), rail, faces=["+y", "-x", "+x"])
    # 外階段（廊下の前、端から折り返して上る）
    side = rnd.choice([-1, 1])
    xe = x1 - 0.6 if side > 0 else x0 + 0.6
    run = fh * 1.45
    for k in range(1, floors):
        zb, zt = GROUND + fh * (k - 1), GROUND + fh * k
        a, b = (xe, y1 + 0.75, zb), (xe - side * run, y1 + 0.75, zt)
        if k % 2 == 0:
            a, b = (xe - side * run, y1 + 0.75, zb), (xe, y1 + 0.75, zt)
        m.beam(a, b, 1.0, rail, h=0.22)
        m.beam((a[0], y1 + 1.22, a[2] + 1.0), (b[0], y1 + 1.22, b[2] + 1.0), 0.08, rail)
        m.box_lohi((b[0] - 0.6, y1, zt - 0.2), (b[0] + 0.6, y1 + 1.25, zt), rail, faces=["+y", "top", "bottom", "-x", "+x"])
    return z_top


def loggia_block(m, rnd, x0, x1, y0, y1, floors):
    """ロッジアの建物：凹んだバルコニーが階ごとに市松に並ぶ（画像）。基壇と頂部の帯、屋上庭園。"""
    fh = rnd.uniform(3.0, 3.3)
    sk = Skin(rnd, "loggia", rnd.uniform(3.0, 3.5), fh)
    col = H(rnd.choice(["#D98B63", "#E3B56E", "#F2EEE6", "#E8D2AC", "#BFD5EC", "#E7C1B4", "#CFD8C4"]))
    z_top = GROUND + fh * floors
    sk.walls(m, x0, x1, y0, y1, GROUND, z_top, col)
    m.box_lohi((x0 - 0.15, y1, GROUND), (x1 + 0.15, y1 + 0.25, GROUND + 1.0), shade(col, 0.78), faces=["+y", "top", "-x", "+x"])
    roof_top(m, rnd, x0, x1, y0, y1, z_top, garden=0.55)
    return z_top


def punched_block(m, rnd, x0, x1, y0, y1, floors):
    """不規則な窓の現代の建物：大きさも位置もばらばらの窓（画像）、薄い笠木。半分は色の箱のバルコニーを散らす。"""
    fh = rnd.uniform(3.0, 3.35)
    sk = Skin(rnd, "punched", rnd.uniform(2.7, 3.7), fh)
    col = H(rnd.choice(["#F4F2EE", "#E9E9E6", "#DCDDDC", "#F1D6CF", "#D5E6DA", "#E9E1F0", "#E8E2D2"]))
    z_top = GROUND + fh * floors
    sk.walls(m, x0, x1, y0, y1, GROUND, z_top, col)
    m.box_lohi((x0 - 0.05, y0, z_top), (x1 + 0.05, y1 + 0.05, z_top + 0.6), col, faces=["+y", "top", "-x", "+x"])
    if rnd.random() < 0.55 and floors >= 3:
        taken = []
        want = int((x1 - x0) * (floors - 1) / 18) + 2
        for _ in range(want * 4):
            if len(taken) >= want:
                break
            k = rnd.randint(1, floors - 1)
            bw = rnd.uniform(2.6, 3.6)
            bx = rnd.uniform(x0 + 0.8, x1 - 0.8 - bw)
            if any(tk == k and overlaps(bx, bx + bw, tx0, tx1, 1.0) for tk, tx0, tx1 in taken):
                continue
            taken.append((k, bx, bx + bw))
            z = GROUND + fh * k
            bc = C[rnd.choice(["red", "yellow", "teal", "cobalt", "orange"])]
            m.box_lohi((bx, y1, z - 0.25), (bx + bw, y1 + 1.3, z + 1.05), bc, faces=["+y", "top", "bottom", "-x", "+x"])
            if rnd.random() < 0.5:
                gc = rnd.choice(CANOPY)
                m.blob((bx + bw * 0.5, y1 + 0.7, z + 1.3), bw * 0.3, 0.5, 0.45, shade(gc, 1.1), shade(gc, 0.7), seg=5, rings=2)
    quad_up(m, x0, y0, x1, y1, z_top + 0.3, C["roof"])
    roof_kit(m, rnd, x0 + 1.5, x1 - 1.5, y0 + 1.5, y1 - 1.0, z_top + 0.3)
    return z_top


def bay_block(m, rnd, x0, x1, y0, y1, floors):
    """出窓の建物：レンガか漆喰（1 階が店）の壁に、縦に積んだ出窓（白い枠・ガラス・頂部の屋根）の列。"""
    floors = max(3, floors)
    brick = rnd.random() < 0.5
    fh = rnd.uniform(3.1, 3.4)
    if brick:
        sk = Skin(rnd, "brick", rnd.uniform(2.6, 3.0), fh)
        col = H(rnd.choice(BRICKS))
    else:
        sk = Skin(rnd, "shop", rnd.uniform(2.9, 3.4), fh, gf=rnd.uniform(3.8, 4.4))
        col = pick(rnd, ["sky", "cream", "white", "mint", "rose"], [0.3, 0.2, 0.2, 0.15, 0.15])
    z_first = GROUND + (sk.gf or fh)
    z_top = z_first + fh * (floors - 1)
    sk.walls(m, x0, x1, y0, y1, GROUND, z_top, col)
    cap = C[rnd.choice(["cobalt", "navy", "white", "terracotta"])]
    cols = [0.5] if x1 - x0 < 12 else [0.24, 0.76]
    for f in cols:
        cx = x0 + (x1 - x0) * f
        zt = z_first
        for k in range(floors - 1):
            zb = z_first + fh * k + 0.3
            zt = zb + fh - 0.6
            m.box_lohi((cx - 1.5, y1, zb), (cx + 1.5, y1 + 0.95, zt), C["white"], faces=["+y", "top", "bottom", "-x", "+x"])
            m.box_lohi((cx - 1.2, y1 + 0.95, zb + 0.25), (cx + 1.2, y1 + 1.09, zt - 0.2), C["dark_glass"], faces=["+y", "-x", "+x", "top"])
            m.box_lohi((cx - 0.08, y1 + 1.09, zb + 0.25), (cx + 0.08, y1 + 1.2, zt - 0.2), C["white"], faces=["+y", "-x", "+x"])
        m.box_lohi((cx - 1.7, y1 - 0.1, zt), (cx + 1.7, y1 + 1.2, zt + 0.35), cap, faces=["+y", "top", "bottom", "-x", "+x"])
    if brick:
        dx = (x0 + x1) / 2 + rnd.uniform(-1.5, 1.5)
        m.box_lohi((dx - 0.8, y1, GROUND), (dx + 0.8, y1 + GAP, GROUND + 2.6), H(rnd.choice(["#3E4E6A", "#2F5E4A", "#8C3A30"])),
                   faces=["+y", "top", "-x", "+x"])
    roof_top(m, rnd, x0, x1, y0, y1, z_top, garden=0.35)
    return z_top


def ribbon_block(m, rnd, x0, x1, y0, y1, floors):
    """横連窓のモダニズムの建物：全幅のガラスの帯と白い腰壁（画像）、前の角を丸める（帯が角を回る）、薄く張り出す屋根。"""
    fh = rnd.uniform(3.2, 3.5)
    sk = Skin(rnd, "ribbon", rnd.uniform(3.0, 3.4), fh)
    col = H(rnd.choice(["#F4F4F1", "#E6E8EA", "#EFE8DA", "#F2F0E8"]))
    z_top = GROUND + fh * floors
    R = max(2.0, min(5.5, (x1 - x0) * 0.3, (y1 - y0) * 0.4))
    seg = 6
    if rnd.random() < 0.5:           # +x の前の角を丸める
        arc = [(x1 - R + R * math.cos(math.pi / 2 * k / seg), y1 - R + R * math.sin(math.pi / 2 * k / seg)) for k in range(seg + 1)]
        pts = [(x0, y0), (x1, y0)] + arc + [(x0, y1)]
    else:                            # -x の前の角
        arc = [(x0 + R + R * math.cos(math.pi / 2 + math.pi / 2 * k / seg), y1 - R + R * math.sin(math.pi / 2 + math.pi / 2 * k / seg))
               for k in range(seg + 1)]
        pts = [(x0, y0), (x1, y0), (x1, y1)] + arc
    u = sk.u0
    n = len(pts)
    for i in range(1, n):
        a, b = pts[i], pts[(i + 1) % n]
        u = wall(m, a, b, GROUND, z_top, col, "ribbon", u, sk.v, tile_u=sk.tile_u)
    m.add_face([(p[0], p[1], z_top) for p in pts], C["roof"])
    cx = sum(p[0] for p in pts) / n
    cy = sum(p[1] for p in pts) / n
    over = []
    for px, py in pts:
        dx, dy = px - cx, py - cy
        dl = math.hypot(dx, dy) or 1.0
        over.append((px + dx / dl * 0.7, py + dy / dl * 0.7))
    m.extrude_poly(over, z_top, z_top + 0.45, C["white"], top=C["white"], bottom=True)
    roof_kit(m, rnd, x0 + 2, x1 - 2, y0 + 2, y1 - 3, z_top + 0.45)
    return z_top


def terrace_block(m, rnd, x0, x1, y0, y1, floors):
    """段々テラスの建物：上の階ほど後ろへ下がり、各段の縁に手すりと植栽。"""
    fh = rnd.uniform(3.0, 3.2)
    sk = Skin(rnd, rnd.choice(["flat", "punched", "loggia"]), rnd.uniform(3.0, 3.4), fh)
    col = H(rnd.choice(["#EFE3CC", "#F3EEE4", "#E8D6B8", "#F2F2EF", "#E9DCCB"]))
    step = rnd.uniform(1.9, 2.6)
    nsteps = max(1, min(floors - 1, int((y1 - y0 - 8.0) / step)))
    prev = None
    for k in range(floors):
        yk = y1 - step * min(k, nsteps)
        z0 = GROUND + fh * k
        sk.walls(m, x0, x1, y0, yk, z0, z0 + fh, col)
        if prev is not None and yk < prev - 0.01:
            quad_up(m, x0, yk, x1, prev, z0, C["roof"])
            rail_band(m, x0 + 0.2, x1 - 0.2, prev, z0, H("#E3ECF0"), 1.0)
            px = x0 + 1.2
            while px < x1 - 1.0:
                gc = rnd.choice(CANOPY)
                m.blob((px, prev - 0.7, z0 + 0.45), rnd.uniform(0.7, 1.1), 0.55, 0.5, shade(gc, 1.1), shade(gc, 0.7), seg=5, rings=2)
                px += rnd.uniform(1.8, 3.2)
        prev = yk
    roof_top(m, rnd, x0, x1, y0, prev, GROUND + fh * floors, garden=0.8)
    return GROUND + fh * floors


def hotel_fins(m, rnd, x0, x1, y0, y1, floors):
    """色のフィンのホテル：ガラスの壁に縦のフィン（コバルトから青緑のぼかし・白に差し色・紺一色）、ロビーと庇、屋上の看板の枠（文字なし）。"""
    fh = rnd.uniform(3.3, 3.6)
    sk = Skin(rnd, rnd.choice(["glass", "flat"]), rnd.uniform(3.0, 3.4), fh)
    col = H(rnd.choice(["#FFFFFF", "#EEF2F4", "#E4E9EC"]))
    z_top = GROUND + fh * floors
    sk.walls(m, x0, x1, y0, y1, GROUND, z_top, col)
    scheme = rnd.choice(["gradient", "accent", "mono"])
    sp = rnd.uniform(1.6, 2.4)
    n = max(3, int((x1 - x0) / sp))
    for i in range(1, n):
        x = x0 + (x1 - x0) * i / n
        t = i / n
        if scheme == "gradient":
            fc = mix(C["cobalt"], C["teal"], t)
        elif scheme == "accent":
            fc = C["orange"] if i % 4 == 1 else (C["cobalt"] if i % 4 == 3 else C["white"])
        else:
            fc = C["navy"]
        m.box_lohi((x - 0.2, y1, GROUND + fh), (x + 0.2, y1 + 0.95, z_top + 0.4), fc, faces=["+y", "-x", "+x", "top"])
    m.box_lohi((x0 + 1.0, y1, GROUND), (x1 - 1.0, y1 + GAP, GROUND + fh - 0.4), C["dark_glass"], faces=["+y", "top"])
    m.box_lohi((x0 + 2.0, y1, GROUND + fh - 0.4), (x1 - 2.0, y1 + 2.6, GROUND + fh - 0.1), C["white"], faces=["+y", "top", "bottom", "-x", "+x"])
    quad_up(m, x0, y0, x1, y1, z_top, C["roof"])
    cornice(m, x0, x1, y1, z_top, C["white"], out=0.2, h=0.4)
    sx0, sx1 = x0 + 2.0, x1 - 2.0
    for px in (sx0 + 0.6, sx1 - 0.6):
        m.box_lohi((px - 0.15, y1 - 1.5, z_top + 0.4), (px + 0.15, y1 - 1.2, z_top + 2.2), C["white"], faces=["+y", "-x", "+x"])
    m.box_lohi((sx0, y1 - 1.5, z_top + 2.2), (sx1, y1 - 1.2, z_top + 4.6), C["cobalt"], faces=["+y", "top", "-x", "+x", "bottom"])
    m.box_lohi((sx0 + 0.6, y1 - 1.2, z_top + 3.1), (sx1 - 0.6, y1 - 1.2 + GAP, z_top + 3.7), C["white"], faces=["+y"])
    return z_top


def canal_house(m, rnd, x0, x1, y0, y1, floors):
    """運河の家：細い間口のレンガ（ときどき塗装）、背の高い窓、破風（階段・首・鐘・三角）と白い笠石、滑車の梁、奥の切妻屋根。"""
    fh = rnd.uniform(3.3, 3.6)
    painted = rnd.random() < 0.3
    sk = Skin(rnd, "brick", rnd.uniform(2.5, 2.9), fh)
    col = H(rnd.choice(PAINTED if painted else BRICKS))
    trim = C["white"] if not painted or rnd.random() < 0.7 else H("#F3E7CF")
    ze = GROUND + fh * floors
    w = x1 - x0
    xm = (x0 + x1) / 2
    sk.walls(m, x0, x1, y0, y1, GROUND, ze, col)
    m.box_lohi((x0 - 0.1, y1, ze - 0.35), (x1 + 0.1, y1 + 0.28, ze), trim, faces=["+y", "top", "bottom", "-x", "+x"])
    kind = rnd.choice(["step", "neck", "bell", "tri", "step", "neck"])
    h = min(w * 0.95, 6.5)
    top = ze + h
    if kind == "step":
        nst = 3
        sh = h / (nst + 1)
        sw = w * 0.13
        for i in range(nst + 1):
            xa, xb = x0 + sw * i, x1 - sw * i
            if i == nst:
                xa, xb = xm - w * 0.17, xm + w * 0.17
            za, zb = ze + sh * i, ze + sh * (i + 1)
            sk.front_face(m, [(xb, za), (xa, za), (xa, zb), (xb, zb)], x1, y0, y1, col)
            m.box_lohi((xa - 0.12, y1 - 0.4, zb), (xb + 0.12, y1 + 0.14, zb + 0.22), trim, faces=["+y", "top", "-x", "+x"])
    elif kind == "neck":
        nw = w * 0.42
        sk.front_face(m, [(xm + nw / 2, ze), (xm - nw / 2, ze), (xm - nw / 2, top), (xm + nw / 2, top)], x1, y0, y1, col)
        for s in (-1, 1):
            xe = x0 if s < 0 else x1
            xn = xm + s * nw / 2
            curve = [(xe + (xn - xe) * t, ze + h * 0.5 * math.sin(t * math.pi / 2)) for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
            if s < 0:
                sk.front_fan(m, (xn, ze), curve, x1, y0, y1, col)
            else:
                sk.front_fan(m, (xn, ze), curve[::-1], x1, y0, y1, col)
            for a, b in zip(curve[:-1], curve[1:]):
                m.beam((a[0], y1 + 0.05, a[1] + 0.1), (b[0], y1 + 0.05, b[1] + 0.1), 0.26, trim, caps=False)
        m.add_face([(xm + nw / 2 + 0.25, y1 + 0.1, top), (xm - nw / 2 - 0.25, y1 + 0.1, top), (xm, y1 + 0.1, top + 1.0)], trim)
        for s in (-1, 1):
            m.beam((xm + s * nw / 2, y1 + 0.05, ze + h * 0.5), (xm + s * nw / 2, y1 + 0.05, top), 0.24, trim, caps=False)
    elif kind == "bell":
        curve = []
        for k in range(13):
            t = k / 12
            curve.append((x0 + w * t, ze + h * (max(0.0, 1.0 - (2 * t - 1) ** 2)) ** 0.7))
        sk.front_fan(m, (xm, ze), curve, x1, y0, y1, col)
        for a, b in zip(curve[:-1], curve[1:]):
            m.beam((a[0], y1 + 0.05, a[1] + 0.08), (b[0], y1 + 0.05, b[1] + 0.08), 0.26, trim, caps=False)
    else:
        h = h * 0.8
        top = ze + h
        sk.front_face(m, [(x1, ze), (x0, ze), (xm, top)], x1, y0, y1, col)
        for a, b in (((x0, ze), (xm, top)), ((xm, top), (x1, ze))):
            m.beam((a[0], y1 + 0.05, a[1] + 0.1), (b[0], y1 + 0.05, b[1] + 0.1), 0.3, trim, caps=False)
    # 破風の小窓と、滑車の梁
    m.box_lohi((xm - 0.5, y1, ze + h * 0.3), (xm + 0.5, y1 + GAP, ze + h * 0.3 + 1.3), C["dark_glass"], faces=["+y", "top", "-x", "+x"])
    m.box_lohi((xm - 0.12, y1, top - 0.9), (xm + 0.12, y1 + 1.0, top - 0.65), H("#5A4636"), faces=["+y", "top", "bottom", "-x", "+x"])
    # 奥の切妻屋根（棟は y に沿う）
    rz = ze + h * 0.7
    slate = H(rnd.choice(["#5B6470", "#6A5E58", "#4F5A66"]))
    m.add_face([(x0 - 0.05, y1 - 0.3, ze), (xm, y1 - 0.3, rz), (xm, y0, rz), (x0 - 0.05, y0, ze)][::-1], shade(slate, 0.92))
    m.add_face([(x1 + 0.05, y1 - 0.3, ze), (x1 + 0.05, y0, ze), (xm, y0, rz), (xm, y1 - 0.3, rz)][::-1], slate)
    # 玄関（色の扉と白い枠）
    dx = xm + rnd.uniform(-w * 0.2, w * 0.2)
    m.box_lohi((dx - 0.75, y1, GROUND), (dx + 0.75, y1 + GAP, GROUND + 2.7), trim, faces=["+y", "top", "-x", "+x"])
    m.box_lohi((dx - 0.55, y1 + GAP, GROUND), (dx + 0.55, y1 + GAP + 0.1, GROUND + 2.5), H(rnd.choice(["#2F5E4A", "#8C3A30", "#2B3F66", "#1F2A36"])),
               faces=["+y", "top", "-x", "+x"])
    return top


def canal_row(m, rnd, x0, x1, y0, y1, floors):
    """運河の家の並び（間口 5.5〜8.5m、階数と破風を家ごとに変える）。"""
    x = x0
    top = 0.0
    while x < x1 - 4.5:
        xe = min(x1, x + rnd.uniform(5.6, 8.4))
        if x1 - xe < 4.5:
            xe = x1
        top = max(top, canal_house(m, rnd, x, xe, y0 + rnd.uniform(0, 2), y1 + rnd.uniform(-0.4, 0.2), max(3, floors + rnd.randint(-1, 1))))
        x = xe
    return top


BUILDERS = {
    "med": shop_house, "canal": canal_row, "bay": bay_block, "mansion_h": mansion_h, "mansion_v": mansion_v, "apato": apato,
    "loggia": loggia_block, "punched": punched_block, "ribbon": ribbon_block, "terrace": terrace_block, "hotel": hotel_fins,
    "flat": apartment,
}
ROW_TYPES = {
    1: [("med", 0.55), ("canal", 0.28), ("bay", 0.17)],
    2: [("mansion_h", 0.16), ("mansion_v", 0.11), ("apato", 0.12), ("loggia", 0.11), ("punched", 0.12), ("bay", 0.08),
        ("ribbon", 0.09), ("terrace", 0.09), ("flat", 0.06), ("canal", 0.06)],
    3: [("mansion_h", 0.2), ("mansion_v", 0.15), ("loggia", 0.11), ("punched", 0.12), ("ribbon", 0.1), ("terrace", 0.08),
        ("hotel", 0.12), ("flat", 0.07), ("bay", 0.05)],
}


def pick_type(rnd, row, last):
    names = [n for n, _ in ROW_TYPES[row]]
    weights = [w for _, w in ROW_TYPES[row]]
    for _ in range(8):
        t = rnd.choices(names, weights)[0]
        if t != last:
            return t
    return t


def streets(rnd):
    """街の通り（海へ下りる、列をまたいで同じ x）。返り値：[(x0, x1)]（建物の区画）。"""
    blocks = []
    x = X0 + 2.0
    while x < X1 - 10:
        L = rnd.uniform(44.0, 86.0)
        xe = min(X1 - 2.0, x + L)
        blocks.append((x, xe))
        x = xe + rnd.uniform(9.0, 13.0)
    return blocks


def overlaps(a0, a1, b0, b1, pad=0.0):
    return a0 < b1 + pad and b0 < a1 + pad


def district(m, rnd, avoid):
    """1〜3 列目の建物。型を混ぜて並べる（隣に同じ型を置かない）。avoid：残した街の建物の足もと [(x0, x1, y0, y1)]（3 列目はその前へ下げる）。"""
    blocks = streets(rnd)
    skip1 = [PLAZA_X, HALL_X]
    info = {"buildings": 0, "blocks": blocks, "types": {}}
    for row in (1, 2, 3):
        front, dmin, dmax, fmin, fmax = ROWS[row]
        last = None
        for bx0, bx1 in blocks:
            x = bx0
            while x < bx1 - 6.0:
                w = rnd.uniform(11.0, 22.0) if row == 1 else rnd.uniform(15.0, 28.0)
                xe = min(bx1, x + w)
                if bx1 - xe < 8.0:
                    xe = bx1
                if row == 1 and any(overlaps(x, xe, a, b, 1.0) for a, b in skip1):
                    x = xe + rnd.uniform(0.0, 1.2)
                    continue
                if row == 2 and overlaps(x, xe, HALL_X[0], HALL_X[1], 1.0):
                    y1 = min(front, HALL_Y[0] - 1.5)
                else:
                    y1 = front + rnd.uniform(-1.2, 1.2)
                y0 = y1 - rnd.uniform(dmin, dmax)
                if row == 3:
                    y0 = max(y0, ROW3_MIN_Y)
                    for ax0, ax1, ay0, ay1 in avoid:
                        if overlaps(x, xe, ax0, ax1, 2.5) and ay1 + 3.0 > y0:
                            y0 = ay1 + 3.0
                    if y1 - y0 < 10.0:
                        x = xe + rnd.uniform(0.0, 1.5)
                        continue
                floors = rnd.randint(fmin, fmax)
                kind = pick_type(rnd, row, last)
                last = kind
                if row > 1:
                    # 端（画面の外）へ向かって少し低く
                    floors = max(fmin - 1, int(round(floors * (1.0 - 0.25 * (abs((x + xe) / 2) / X1) ** 2))))
                pad = 0.2 if row == 1 else 0.3
                BUILDERS[kind](m, rnd, x + pad, xe - pad, y0, y1, floors)
                info["buildings"] += 1
                info["types"][kind] = info["types"].get(kind, 0) + 1
                x = xe + (rnd.uniform(0.0, 0.6) if row == 1 else rnd.uniform(0.4, 2.0))
    # 通りの木
    for i in range(len(blocks) - 1):
        sx = (blocks[i][1] + blocks[i + 1][0]) / 2
        for yy in (ROWS[1][0] - 7, ROWS[2][0] - 8, ROWS[3][0] - 10):
            if not any(a - 3 < sx < b + 3 for a, b in skip1):
                if rnd.random() < 0.35:
                    cypress(m, rnd, sx - 1.8, yy, GROUND)
                    cypress(m, rnd, sx + 1.8, yy + rnd.uniform(-1, 1), GROUND)
                else:
                    round_tree(m, rnd, sx + rnd.uniform(-1, 1), yy + rnd.uniform(-2, 2), rnd.uniform(0.8, 1.05))
    return info


# --- 観覧車（2026-09-30 作り直し：回る観覧車） -------------------------------------------------
# 輪の面は x-z（正面は +y）。回る輪とゴンドラが、動かない脚・乗り場や互いに当たらないよう、y で住み分ける：
#   ゴンドラ |y| ≤ 1.02（2 本の輪のあいだ）、輪（外の輪・内の輪・格子・前の灯）|y| 1.6〜2.62、
#   スポークの交差（半径 13〜23、ゴンドラは半径 25.9 より内へ来ない）、ハブと前の飾り |y| ≤ 3.95、
#   脚と軸受け |y| ≥ 4.6、乗り場の屋根 y ≥ +2.8（輪の前の灯より前）、乗り場の床はいちばん下のゴンドラの 0.3m 下。
# ビルダーの検算（build_menu_stage.wheel_checks）が、1 周ぶん回したときに当たらないかを式で確かめる。
GONDOLA_COLS = ("cobalt", "orange", "teal", "yellow", "white", "red")


def wheel_hang_angle(i):
    """ゴンドラ i の吊り点の角度（輪の面 x-z、+x から +z へ。止まっている姿勢）。外の輪の 48 区間の奇数の頂点。"""
    return 2 * math.pi * (i + 0.5) / WHEEL_GONDOLAS


def wheel_hang_point(i):
    """ゴンドラ i の吊り点（街のローカル、止まっている姿勢）＝ゴンドラのオブジェクトの原点。"""
    a = wheel_hang_angle(i)
    return (WHEEL_X + WHEEL_R * math.cos(a), WHEEL_Y, WHEEL_HUB_Z + WHEEL_R * math.sin(a))


def ferris_stand(m):
    """動かない部分（街のローカル）：前後 2 組の A 字の脚（基礎・横つなぎ）、軸受けと軸、前後の脚をつなぐ低い梁、
    乗り場（白い台とコバルトの帯・前の階段・前半分の屋根）。切符売り場は広場（plaza）にある。"""
    cx, cy, hz = WHEEL_X, WHEEL_Y, WHEEL_HUB_Z
    white = C["white"]
    fx, fy = WHEEL_FOOT
    for s in (-1, 1):                     # 後ろ（-y）と前（+y、カメラの側）の A 字
        top = (cx, cy + s * WHEEL_LEG_Y, hz)
        feet = [(cx - fx, cy + s * fy, GROUND), (cx + fx, cy + s * fy, GROUND)]
        for f in feet:
            m.beam(f, top, 1.2, white)
            m.box((f[0], f[1], GROUND + 0.4), (2.4, 2.4, 0.8), C["stone"], faces=["+y", "-y", "+x", "-x", "top"])
        za = GROUND + 12.0                # A 字の横つなぎ
        t = (za - GROUND) / (hz - GROUND)
        pa = [(f[0] + (top[0] - f[0]) * t, f[1] + (top[1] - f[1]) * t, za) for f in feet]
        m.beam(pa[0], pa[1], 0.7, white)
        # 軸受け（脚の頂の白い箱と下のコバルトの帯）
        m.box((cx, cy + s * WHEEL_LEG_Y, hz), (2.6, 1.4, 2.6), white)
        m.box((cx, cy + s * WHEEL_LEG_Y, hz - 1.45), (2.8, 1.5, 0.3), C["cobalt"])
    # 軸（動かない。回るハブの中を通る）と前の端のコバルトの蓋
    m.tube((cx, cy - WHEEL_LEG_Y - 0.8, hz), (cx, cy + WHEEL_LEG_Y + 0.8, hz), 0.8, H("#D9DDE0"), n=10, smooth=False, caps=True)
    m.tube((cx, cy + WHEEL_LEG_Y + 0.8, hz), (cx, cy + WHEEL_LEG_Y + 1.1, hz), 1.15, C["cobalt"], n=10, smooth=False, caps=True)
    # 前後の脚をつなぐ梁：足もとと、ゴンドラの通り道より下（地面から 3m）
    for sx in (-1, 1):
        x = cx + sx * fx
        m.beam((x, cy - fy, GROUND + 0.5), (x, cy + fy, GROUND + 0.5), 0.7, white)
        za = GROUND + 3.0
        t = (za - GROUND) / (hz - GROUND)
        xa, ya = x + (cx - x) * t, fy + (WHEEL_LEG_Y - fy) * t
        m.beam((xa, cy - ya, za), (xa, cy + ya, za), 0.55, white)
    # 乗り場：白い台（上面は広場の舗装の色）、前面のコバルトの帯（階段の所は開ける）、前の階段 2 段、前半分の屋根と柱 4 本
    x0, x1, y0, y1, ztop = cx - 10.0, cx + 10.0, cy - 4.0, cy + 6.5, GROUND + 1.6
    m.box_lohi((x0, y0, GROUND), (x1, y1, ztop), white, top=C["plaza"], faces=["+y", "-y", "top", "-x", "+x"])
    for a, b in ((x0 - 0.1, cx - 4.0), (cx + 4.0, x1 + 0.1)):
        m.box_lohi((a, y1, GROUND + 0.95), (b, y1 + GAP, GROUND + 1.35), C["cobalt"], faces=["+y", "top", "bottom", "-x", "+x"])
    for k, zt in enumerate((GROUND + 1.07, GROUND + 0.53)):
        m.box_lohi((cx - 4.0, y1 + 0.9 * k, GROUND), (cx + 4.0, y1 + 0.9 * (k + 1), zt), C["step"], faces=["+y", "top", "-x", "+x"])
    zr = GROUND + 4.6
    for sx in (-1, 1):
        for yy in (cy + 3.2, cy + 6.0):
            m.box((cx + sx * 8.6, yy, (ztop + zr) / 2), (0.35, 0.35, zr - ztop), white, faces=["+y", "-y", "+x", "-x"])
    m.box_lohi((cx - 9.2, cy + 2.8, zr), (cx + 9.2, cy + 6.8, zr + 0.35), C["cobalt"], top=white)


def ferris_rim(m):
    """回る部分（原点＝軸の中心、y＝軸の向き、z 上）。この 1 つを軸まわりに回すと輪が回る。
    前後 2 本の輪（外の輪・内の輪と V 字の格子のトラス）、スポーク（ハブの両端から内の輪へ。半分は反対の端から交差）、
    ハブ（両端のコバルトのフランジ、前に橙と白の飾り）、ゴンドラの吊り棒（2 本の輪をつなぐ、外の輪の奇数の頂点）、
    夜の灯（前の輪の外の輪 48・内の輪 24、AQS_NightGlow）。"""
    R, Ri = WHEEL_R, WHEEL_RIM_IN
    n = 2 * WHEEL_GONDOLAS                # 48 区間：奇数の頂点に吊り点、偶数の頂点にスポーク
    white = C["white"]

    def pt(r, y, j):
        a = 2 * math.pi * j / n
        return (r * math.cos(a), y, r * math.sin(a))
    for s in (-1, 1):
        y = s * WHEEL_RIM_Y
        for j in range(n):
            m.beam(pt(R, y, j), pt(R, y, j + 1), 0.8, white, caps=False)
            m.beam(pt(Ri, y, j), pt(Ri, y, j + 1), 0.5, white, caps=False)
        for j in range(1, n, 2):          # 格子：吊り点（外の輪の奇数の頂点）から内の輪の両隣（スポークの頂点）へ V 字
            m.beam(pt(R, y, j), pt(Ri, y, j - 1), 0.32, white, caps=False)
            m.beam(pt(R, y, j), pt(Ri, y, j + 1), 0.32, white, caps=False)
    # スポーク：内の輪の偶数の頂点へ、ハブの同じ側の端から（k が偶数）と反対の端から（k が奇数、交差する）
    rf = 1.9
    for s in (-1, 1):
        for k in range(WHEEL_GONDOLAS):
            f = s if k % 2 == 0 else -s
            m.beam(pt(rf, f * WHEEL_HUB_Y, 2 * k), pt(Ri, s * WHEEL_RIM_Y, 2 * k), 0.26, white, caps=False)
    # ハブと両端のフランジ、前の飾り（橙と白の 6 枚の羽根：回っているのが遠目にも分かる）
    m.tube((0.0, -WHEEL_HUB_Y, 0.0), (0.0, WHEEL_HUB_Y, 0.0), 1.9, white, n=12, smooth=False, caps=True)
    for s in (-1, 1):
        m.tube((0.0, s * (WHEEL_HUB_Y - 0.3), 0.0), (0.0, s * (WHEEL_HUB_Y + 0.15), 0.0), 2.3, C["cobalt"], n=12, smooth=False,
               caps=True)
    yc = WHEEL_HUB_Y + 0.15 + GAP
    for k in range(12):
        a0, a1 = 2 * math.pi * k / 12, 2 * math.pi * (k + 1) / 12
        m.add_face([(0.0, yc, 0.0), (2.1 * math.cos(a1), yc, 2.1 * math.sin(a1)), (2.1 * math.cos(a0), yc, 2.1 * math.sin(a0))],
                   C["orange"] if k % 2 == 0 else white)
    # ゴンドラの吊り棒（2 本の輪をつなぐ）。ゴンドラの原点はこの棒の中心
    for i in range(WHEEL_GONDOLAS):
        a = wheel_hang_angle(i)
        x, z = R * math.cos(a), R * math.sin(a)
        m.beam((x, -WHEEL_RIM_Y, z), (x, WHEEL_RIM_Y, z), 0.3, white)
    # 夜の灯（前の輪の前の面から 0.02m 前に箱）
    lights = ((R, 0.8, 1, 0.55, C["glow"]), (Ri, 0.5, 2, 0.4, H("#A9D8FF")))
    for r, w, step, size, col in lights:
        for j in range(0, n, step):
            x, _, z = pt(r, 0.0, j)
            m.box((x, WHEEL_RIM_Y + w / 2 + 0.12, z), (size, 0.2, size), col, "night", faces=["+y", "+x", "-x", "top", "bottom"])


def gondola(m, col):
    """ゴンドラ 1 台（原点＝吊り点＝輪の吊り棒の中心、z 上、y＝軸の向き）。Godot は向きを変えずに原点だけ動かす。
    吊り具・色の腰（下がすぼまる）・ガラスの帯・色の帯・屋根。本体は x ±1.35、y ±1.02、z -4.1〜-1.15。"""
    m.tube((0.0, 0.0, 0.05), (0.0, 0.0, -1.2), 0.12, H("#9AA3AA"), n=4, smooth=False)
    zb = -4.1
    m.prism(0.0, 0.0, zb, zb + 1.1, 1.05, 1.35, 8, col, sy=0.75, cap_top=False)
    m.prism(0.0, 0.0, zb + 1.1, zb + 2.35, 1.35, 1.35, 8, C["dark_glass"], sy=0.75, cap_bottom=False, cap_top=False)
    m.prism(0.0, 0.0, zb + 2.35, zb + 2.6, 1.35, 1.35, 8, col, sy=0.75, cap_bottom=False, cap_top=False)
    m.prism(0.0, 0.0, zb + 2.6, zb + 2.95, 1.35, 0.5, 8, col, sy=0.75, cap_bottom=False)


def ferris_wheel():
    """観覧車の部品（名前 → Mesh）と、部品の原点（街のローカル。書かないものは街の原点）。
    脚と乗り場は街のローカルで、輪は軸の中心、ゴンドラは吊り点を原点に作る（Godot がその原点で動かす）。"""
    parts, origins = {}, {}
    stand = Mesh()
    ferris_stand(stand)
    parts["AMS_FerrisWheelStand"] = stand
    rim = Mesh()
    ferris_rim(rim)
    parts["AMS_FerrisWheelRim"] = rim
    origins["AMS_FerrisWheelRim"] = (WHEEL_X, WHEEL_Y, WHEEL_HUB_Z)
    for i in range(WHEEL_GONDOLAS):
        g = Mesh()
        gondola(g, C[GONDOLA_COLS[i % len(GONDOLA_COLS)]])
        name = f"AMS_FerrisGondola_{i:02d}"
        parts[name] = g
        origins[name] = wheel_hang_point(i)
    return parts, origins


def plaza(m, rnd):
    """観覧車の広場：明るい舗装、植え込み（芝の縁と木）、切符売り場、旗。"""
    x0, x1 = PLAZA_X
    quad_up(m, x0, ROWS[1][0] - 20, x1, PROM_Y0, PAVE_Z + 0.1, C["plaza"])
    for bx in (x0 + 7, x1 - 7):
        m.box_lohi((bx - 5, 212.0, GROUND), (bx + 5, 222.0, GROUND + 0.6), C["white"], top=C["lawn"], faces=["+y", "top", "-x", "+x"])
        round_tree(m, rnd, bx - 2, 216.0, 1.05)
        round_tree(m, rnd, bx + 2.5, 219.0, 0.9)
    # 切符売り場（観覧車の右の脚の足もと x = WHEEL_X + 16 と梁から離す）
    kx = WHEEL_X + 21.0
    m.box_lohi((kx - 3, 229.0, GROUND), (kx + 3, 233.0, GROUND + 3.2), C["white"], faces=["+y", "-x", "+x"])
    m.box_lohi((kx - 3.4, 228.6, GROUND + 3.2), (kx + 3.4, 233.6, GROUND + 3.7), C["cobalt"], faces=["+y", "top", "bottom", "-x", "+x"])
    m.box_lohi((kx - 2.2, 233.0, GROUND + 1.1), (kx + 2.2, 233.0 + GAP, GROUND + 2.5), C["dark_glass"], faces=["+y", "-x", "+x", "top"])
    for fx in (x0 + 2, x1 - 2):
        banner_pole(m, fx, 227.0, ("orange", "white"), h=11.0)


# --- 市場ホール ---------------------------------------------------------------
def market_hall(m, rnd):
    x0, x1 = HALL_X
    y0, y1 = HALL_Y
    nb = 3
    bw = (x1 - x0) / nb
    z_eave, z_ridge = GROUND + 10.0, GROUND + 16.5
    wallc, roofc = H("#F4EFE4"), H("#3F6FB8")
    # 側面と後ろ
    rect_walls(m, x0, x1, y0, y1, GROUND, z_eave, wallc, "paint")
    for b in range(nb):
        bx0, bx1 = x0 + b * bw, x0 + (b + 1) * bw
        xm = (bx0 + bx1) / 2
        # 正面の破風（三角）
        m.add_face([(bx1, y1, z_eave), (bx0, y1, z_eave), (xm, y1, z_ridge)], shade(wallc, 1.02))
        # 屋根（棟は y に沿う）と、正面の縁
        ov = 0.9
        m.add_face([(bx0 - 0.3, y1 + ov, z_eave - 0.3), (xm, y1 + ov, z_ridge + 0.2), (xm, y0 - 0.5, z_ridge + 0.2),
                    (bx0 - 0.3, y0 - 0.5, z_eave - 0.3)][::-1], shade(roofc, 0.92))
        m.add_face([(bx1 + 0.3, y1 + ov, z_eave - 0.3), (bx1 + 0.3, y0 - 0.5, z_eave - 0.3), (xm, y0 - 0.5, z_ridge + 0.2),
                    (xm, y1 + ov, z_ridge + 0.2)][::-1], shade(roofc, 1.02))
        for sgn, xe in ((-1, bx0 - 0.3), (1, bx1 + 0.3)):
            m.beam((xe, y1 + ov, z_eave - 0.3), (xm, y1 + ov, z_ridge + 0.2), 0.45, C["white"])
        # 棟の換気の小屋根
        m.box_lohi((xm - 1.0, y0 + 2, z_ridge + 0.1), (xm + 1.0, y1 - 2, z_ridge + 1.1), C["white"], faces=["+y", "top", "-x", "+x"])
        # 大きなアーチの窓（暗いガラス＋白い方立の放射）
        aw, spring, zb = bw * 0.62, GROUND + 9.2, GROUND + 3.4
        r = aw / 2
        yw = y1 + GAP
        seg = 12
        arc = [(xm + r * math.cos(math.pi * k / seg), spring + r * math.sin(math.pi * k / seg)) for k in range(seg + 1)]
        for k in range(seg):
            m.add_face([(xm, yw, spring), (arc[k + 1][0], yw, arc[k + 1][1]), (arc[k][0], yw, arc[k][1])], C["dark_glass"])
        m.add_face([(xm + r, yw, zb), (xm - r, yw, zb), (xm - r, yw, spring), (xm + r, yw, spring)], C["dark_glass"])
        ym = yw + 0.12
        for k in range(seg):
            a0, a1 = math.pi * k / seg, math.pi * (k + 1) / seg
            m.beam((xm + r * math.cos(a0), ym, spring + r * math.sin(a0)), (xm + r * math.cos(a1), ym, spring + r * math.sin(a1)), 0.55, C["white"], caps=False)
        for k in range(1, 6):
            a = math.pi * k / 6
            m.beam((xm, ym, spring), (xm + r * math.cos(a), ym, spring + r * math.sin(a)), 0.3, C["white"], caps=False)
        for fx in (-0.5, 0.0, 0.5):
            m.beam((xm + r * fx, ym, zb), (xm + r * fx, ym, spring), 0.3, C["white"], caps=False)
        m.beam((xm - r, ym, spring), (xm + r, ym, spring), 0.35, C["white"], caps=False)
        for fx in (-1, 1):
            m.beam((xm + r * fx, ym, zb), (xm + r * fx, ym, spring), 0.55, C["white"], caps=False)
        # 入口の庇
        m.box_lohi((xm - 3.5, y1, GROUND + 3.0), (xm + 3.5, y1 + 2.2, GROUND + 3.35), C["cobalt"], faces=["+y", "top", "bottom", "-x", "+x"])
    # 正面の足もとの帯と柱
    m.box_lohi((x0 - 0.2, y1, GROUND), (x1 + 0.2, y1 + 0.35, GROUND + 0.9), H("#D8D2C6"), faces=["+y", "top", "-x", "+x"])
    for b in range(nb + 1):
        px = x0 + b * bw
        m.box_lohi((px - 0.6, y1, GROUND), (px + 0.6, y1 + 0.5, z_eave), C["white"], faces=["+y", "-x", "+x"])
    cols = ["yellow", "white", "cobalt", "white", "yellow", "white"]
    for k in range(14):
        px = x0 + 3 + k * (x1 - x0 - 6) / 13
        parasol(m, px, y1 + 4.2 + (k % 2) * 2.6, PAVE_Z, C[cols[k % len(cols)]], r=1.4)


# --- フェリーターミナル・フェリー --------------------------------------------------
def terminal(m, rnd):
    x0, x1 = TERMINAL_X
    y0, y1 = TERMINAL_Y
    z1 = GROUND + 8.6
    # ガラスの正面と白い側面
    rect_walls(m, x0, x1, y0, y1 - 2.5, GROUND, z1, C["white"], "glass", v_flat, 0.0)
    for k in range(13):
        px = x0 + (x1 - x0) * k / 12
        m.box_lohi((px - 0.45, y1 - 2.5, GROUND), (px + 0.45, y1 + 0.6, z1 + 1.2), C["white"], faces=["+y", "-x", "+x"])
    # 波の屋根（x に沿ってうねる薄い板、前へ張り出す）
    seg = 36
    def rz(x):
        return GROUND + 11.0 + 1.5 * math.sin(2 * math.pi * (x - x0) / 36.0)
    ya, yb = y0 - 1.5, y1 + 1.6
    for k in range(seg):
        xa = x0 - 3 + (x1 - x0 + 6) * k / seg
        xb = x0 - 3 + (x1 - x0 + 6) * (k + 1) / seg
        za, zb = rz(xa), rz(xb)
        m.add_face([(xa, ya, za + 0.7), (xb, ya, zb + 0.7), (xb, yb, zb + 0.7), (xa, yb, za + 0.7)], C["white"])
        m.add_face([(xa, yb, za), (xb, yb, zb), (xb, ya, zb), (xa, ya, za)], H("#D6DCE0"))
        m.add_face([(xb, yb, zb), (xa, yb, za), (xa, yb, za + 0.7), (xb, yb, zb + 0.7)], C["white"])
        # 屋根とガラスのあいだ（高窓）
        m.add_face([(xb, y1 - 2.5, z1), (xa, y1 - 2.5, z1), (xa, y1 - 2.5, za), (xb, y1 - 2.5, zb)], H("#9CC7D4"))
    for xe, s in ((x0 - 3, -1), (x1 + 3, 1)):
        z = rz(xe)
        pts = [(xe, ya, z), (xe, yb, z), (xe, yb, z + 0.7), (xe, ya, z + 0.7)]
        m.add_face(pts if s > 0 else pts[::-1], C["white"])
    # 前の鉢植えの列
    for k in range(12):
        planter(m, rnd, x0 + 4.5 + k * (x1 - x0 - 9) / 11, QUAY_Y - 1.6, PAVE_Z, w=1.4)
    # 時計塔
    tx, ty = CLOCK_X, y1 - 7.0
    th = GROUND + 30.0
    m.box_lohi((tx - 3.6, ty - 3.6, GROUND), (tx + 3.6, ty + 3.6, th), C["white"], faces=["+y", "-x", "+x", "-y"])
    m.box_lohi((tx - 3.8, ty - 3.8, th - 7.6), (tx + 3.8, ty + 3.8, th - 6.8), C["cobalt"], faces=["+y", "-x", "+x", "top", "bottom"])
    for k in range(4):
        zz = GROUND + 12 + k * 3.4
        m.box_lohi((tx - 0.7, ty + 3.6, zz), (tx + 0.7, ty + 3.6 + GAP, zz + 1.8), C["dark_glass"], faces=["+y", "top", "-x", "+x"])
    for face in ("+y", "-x", "+x"):
        cz = th - 3.3
        r = 2.75
        nseg = 16
        if face == "+y":
            ctr, ax1, ax2 = (tx, ty + 3.62, cz), (-1, 0, 0), (0, 0, 1)
            nrm = (0, 1, 0)
        elif face == "+x":
            ctr, ax1, ax2 = (tx + 3.62, ty, cz), (0, 1, 0), (0, 0, 1)
            nrm = (1, 0, 0)
        else:
            ctr, ax1, ax2 = (tx - 3.62, ty, cz), (0, -1, 0), (0, 0, 1)
            nrm = (-1, 0, 0)
        for rr, col, off in ((r, C["navy"], GAP), (r * 0.72, C["white"], GAP + 0.18)):
            c = tuple(ctr[i] + nrm[i] * off for i in range(3))
            rim = [tuple(c[i] + ax1[i] * rr * math.cos(2 * math.pi * k / nseg) + ax2[i] * rr * math.sin(2 * math.pi * k / nseg)
                         for i in range(3)) for k in range(nseg)]
            for k in range(nseg):
                m.add_face([c, rim[k], rim[(k + 1) % nseg]], col)
        hc = tuple(ctr[i] + nrm[i] * (GAP + 0.4) for i in range(3))
        m.beam(hc, tuple(hc[i] + ax2[i] * 1.55 for i in range(3)), 0.32, C["navy"], caps=False)
        m.beam(hc, tuple(hc[i] + ax1[i] * 1.05 + ax2[i] * 0.25 for i in range(3)), 0.32, C["navy"], caps=False)
    # 頂部：柱と青い四角錐の屋根
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box((tx + sx * 3.0, ty + sy * 3.0, th + 1.6), (0.7, 0.7, 3.2), C["white"])
    m.box_lohi((tx - 3.9, ty - 3.9, th + 3.2), (tx + 3.9, ty + 3.9, th + 3.7), C["white"], faces=["+y", "top", "bottom", "-x", "+x"])
    m.cone(tx, ty, th + 3.7, th + 9.5, 5.2, 4, C["cobalt"], phase=math.pi / 4)
    m.tube((tx, ty, th + 9.5), (tx, ty, th + 12.0), 0.15, C["white"], n=4, smooth=False)
    m.box((tx, ty, th + 1.5), (1.6, 1.6, 2.2), C["glow"], "night")
    # 乗船橋（ターミナルからフェリーの舷へ）
    bx = FERRY_X - 8.0
    m.box_lohi((bx - 2, y1 + 0.5, GROUND + 1.6), (bx + 2, WALL_Y + 4.6, GROUND + 4.4), C["white"], faces=["+y", "top", "bottom", "-x", "+x"])
    m.box_lohi((bx - 2.0 - GAP, y1 + 0.7, GROUND + 2.5), (bx + 2.0 + GAP, WALL_Y + 4.4, GROUND + 3.6), C["dark_glass"], faces=["-x", "+x"])


def hull_rows(L, B, sheer, keel, bow_sharp=1.0, stations=9, stripe=None):
    """船体の断面の列（x に沿って、船尾 -L/2 → 船首 +L/2）。stripe=(下端の z, 上端の z)。"""
    rows, cols = [], []
    for k in range(stations):
        t = k / (stations - 1)
        x = -L / 2 + L * t
        half = B / 2 * (1 - (max(0.0, t - 0.6) / 0.4) ** (1.6 * bow_sharp)) * (0.9 + 0.1 * math.sin(math.pi * min(1.0, t * 1.3)))
        half = max(half, 0.02)
        sh = sheer + 0.35 * t * t
        rows.append([(x, -half, sh), (x, -half * 0.95, 0.35), (x, -half * 0.7, keel * 0.6), (x, 0.0, keel),
                     (x, half * 0.7, keel * 0.6), (x, half * 0.95, 0.35), (x, half, sh)])
    return rows


def boat(rnd, kind, L):
    """モーターボート（kind="motor"）かヨット（"sail"）。船首が +x。"""
    m = Mesh()
    B = L * rnd.uniform(0.3, 0.34)
    sheer = L * 0.095 + 0.4
    rows = hull_rows(L, B, sheer, -0.9)
    stripe_col = C[rnd.choice(["cobalt", "cobalt", "orange", "navy", "teal"])]
    # 船体の色（角ごと）：舷の上は白、喫水の上に色の帯、下は濃い色
    ccol = []
    for row in rows:
        cr = []
        for p in row:
            z = p[2]
            if z > sheer - 0.1:
                cr.append(C["hull"])
            elif z > 0.3:
                cr.append(C["hull"])
            else:
                cr.append(C["boot"])
        ccol.append(cr)
    m.add_grid(rows, C["hull"], smooth=False, ccol_rows=ccol)
    # 舷の色の帯（右舷＝+y の側に。左右とも）
    for s in (-1, 1):
        idx = 6 if s > 0 else 0
        pts = [r[idx] for r in rows]
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            off = 0.1 * s
            q = [(a[0], a[1] + off, a[2] - 0.25), (b[0], b[1] + off, b[2] - 0.25), (b[0], b[1] + off, b[2] - 0.6), (a[0], a[1] + off, a[2] - 0.6)]
            m.add_face(q if s > 0 else q[::-1], stripe_col)
    # 甲板
    for k in range(len(rows) - 1):
        a, b = rows[k], rows[k + 1]
        m.add_face([a[0], b[0], b[6], a[6]], H("#E9E2D2"))
    # 船尾の板
    r0 = rows[0]
    m.add_face([r0[i] for i in range(6, -1, -1)], shade(C["hull"], 0.9))
    if kind == "motor":
        cw, cl = B * 0.72, L * 0.42
        cx = -L * 0.06
        zc = sheer + 0.1
        m.box_lohi((cx - cl / 2, -cw / 2, zc), (cx + cl / 2, cw / 2, zc + 1.2), C["hull"], faces=["+y", "-y", "+x", "-x", "top"])
        for s in (-1, 1):
            y = s * (cw / 2 + 0.1)
            q = [(cx - cl / 2 + 0.5, y, zc + 0.4), (cx + cl / 2 - 0.3, y, zc + 0.4), (cx + cl / 2 - 0.3, y, zc + 0.95), (cx - cl / 2 + 0.5, y, zc + 0.95)]
            m.add_face(q if s < 0 else q[::-1], C["dark_glass"])
        m.add_face([(cx + cl / 2 + 0.1, -cw / 2 + 0.3, zc + 0.3), (cx + cl / 2 + 0.1, cw / 2 - 0.3, zc + 0.3),
                    (cx + cl / 2 + 0.1, cw / 2 - 0.3, zc + 1.05), (cx + cl / 2 + 0.1, -cw / 2 + 0.3, zc + 1.05)], C["dark_glass"])
        if L > 11 and rnd.random() < 0.7:
            m.box_lohi((cx - cl * 0.3, -cw * 0.4, zc + 1.2), (cx + cl * 0.2, cw * 0.4, zc + 1.9), C["hull"], faces=["+y", "-y", "+x", "-x", "top"])
            m.box_lohi((cx - cl * 0.25, -cw * 0.35, zc + 1.9), (cx + cl * 0.05, cw * 0.35, zc + 2.05), C["navy"], faces=["top", "+y", "-y", "+x", "-x"])
            m.tube((cx - cl * 0.1, 0, zc + 2.05), (cx - cl * 0.1, 0, zc + 3.4), 0.1, C["white"], n=4, smooth=False)
    else:
        cw, cl = B * 0.6, L * 0.34
        cx = -L * 0.02
        zc = sheer + 0.05
        m.box_lohi((cx - cl / 2, -cw / 2, zc), (cx + cl / 2, cw / 2, zc + 0.75), C["hull"], faces=["+y", "-y", "+x", "-x", "top"])
        for s in (-1, 1):
            y = s * (cw / 2 + 0.1)
            q = [(cx - cl / 2 + 0.4, y, zc + 0.3), (cx + cl / 2 - 0.4, y, zc + 0.3), (cx + cl / 2 - 0.4, y, zc + 0.55), (cx - cl / 2 + 0.4, y, zc + 0.55)]
            m.add_face(q if s < 0 else q[::-1], C["dark_glass"])
        mx = L * 0.1
        mh = L * rnd.uniform(1.15, 1.4)
        m.tube((mx, 0, zc), (mx, 0, zc + mh), 0.17, H("#D7DBDF"), n=4, smooth=False)
        boom = (-L * 0.36, 0, zc + 1.6)
        m.tube((mx, 0, zc + 1.6), boom, 0.12, H("#D7DBDF"), n=4, smooth=False)
        cover = C[rnd.choice(["navy", "cobalt", "cobalt", "white"])]
        m.beam((mx - 0.3, 0, zc + 1.95), (boom[0] + 0.6, 0, zc + 1.9), 0.55, cover, h=0.55)
        # 前の支索（フォアステー）
        m.tube((L * 0.46, 0, sheer + 0.3), (mx, 0, zc + mh * 0.96), 0.05, H("#B0B6BC"), n=3, smooth=False)
    return m


def ferry(rnd):
    """フェリー（56m）：コバルトの船体、白い 3 層の上部構造と窓の帯、煙突。船首が +x。"""
    m = Mesh()
    L, B = 56.0, 12.0
    rows = hull_rows(L, B, 4.2, -2.4, bow_sharp=0.7)
    ccol = [[C["hull_blue"] if p[2] < 2.6 else C["hull"] for p in row] for row in rows]
    m.add_grid(rows, C["hull_blue"], smooth=False, ccol_rows=ccol)
    for k in range(len(rows) - 1):
        a, b = rows[k], rows[k + 1]
        m.add_face([a[0], b[0], b[6], a[6]], H("#D9DDE0"))
    m.add_face([rows[0][i] for i in range(6, -1, -1)], shade(C["hull"], 0.88))
    # 白い帯と上部構造
    decks = [(-22.0, 14.0, 4.4, 7.2, B * 0.46), (-18.0, 10.0, 7.2, 9.8, B * 0.44), (-8.0, 6.0, 9.8, 12.2, B * 0.4)]
    for x0, x1, z0, z1, hw in decks:
        m.box_lohi((x0, -hw, z0), (x1, hw, z1), C["hull"], faces=["+y", "-y", "+x", "-x", "top"])
        for s in (-1, 1):
            y = s * (hw + 0.15)
            q = [(x0 + 1.0, y, z0 + 0.9), (x1 - 1.0, y, z0 + 0.9), (x1 - 1.0, y, z1 - 0.7), (x0 + 1.0, y, z1 - 0.7)]
            m.add_face(q if s < 0 else q[::-1], C["dark_glass"])
        m.box_lohi((x0 - 0.2, -hw - 0.2, z1 - 0.12), (x1 + 0.2, hw + 0.2, z1 + 0.05), H("#E6E9EB"), faces=["+y", "-y", "top", "bottom"])
    # 船橋の窓（前）
    m.add_face([(14.15, -B * 0.4, 5.3), (14.15, B * 0.4, 5.3), (14.15, B * 0.4, 6.5), (14.15, -B * 0.4, 6.5)], C["dark_glass"])
    # 煙突
    m.prism(-12.0, 0, 12.2, 16.8, 1.8, 1.5, 8, C["white"], sx=1.3)
    m.prism(-12.0, 0, 15.2, 16.8, 1.56, 1.5, 8, C["cobalt"], sx=1.3, cap_bottom=False)
    m.prism(-12.0, 0, 16.8, 17.3, 1.5, 1.4, 8, C["orange"], sx=1.3, cap_bottom=False)
    # 救命艇（橙）
    for x in (-15.0, -6.0, 3.0):
        for s in (-1, 1):
            m.box((x, s * (B * 0.46 + 0.5), 8.5), (3.2, 1.0, 0.9), C["orange"], faces=["+y", "-y", "top", "+x", "-x"])
    # 船首の旗竿・マスト
    m.tube((2.0, 0, 12.2), (2.0, 0, 18.0), 0.18, C["white"], n=4, smooth=False)
    m.box((2.0, 0, 16.8), (0.3, 3.0, 0.3), C["white"])
    return m


def marina(m, rnd):
    """桟橋（浮き桟橋、岸から垂直）と指桟橋。ボートは指桟橋に沿って横向き（カメラに舷を見せる）。"""
    boats = []
    for px in MARINA_PONTOONS:
        y0, y1 = WALL_Y + 3.0, WALL_Y + 46.0
        m.box_lohi((px - 1.3, y0, 0.05), (px + 1.3, y1, 0.7), C["pontoon_side"], top=C["deck"], faces=["+y", "top", "-x", "+x"])
        # 岸からの渡り板
        m.add_face([(px - 0.9, WALL_Y + 0.3, COPING_Z), (px + 0.9, WALL_Y + 0.3, COPING_Z), (px + 0.9, y0 + 0.5, 0.72),
                    (px - 0.9, y0 + 0.5, 0.72)], C["deck"])
        m.add_face([(px - 0.9, y0 + 0.5, 0.62), (px + 0.9, y0 + 0.5, 0.62), (px + 0.9, WALL_Y + 0.3, COPING_Z - 0.1),
                    (px - 0.9, WALL_Y + 0.3, COPING_Z - 0.1)], shade(C["deck"], 0.6))
        for s in (-1, 1):
            m.beam((px + s * 0.9, WALL_Y + 0.3, COPING_Z + 1.0), (px + s * 0.9, y0 + 0.5, 1.7), 0.12, C["white"], caps=False)
        yy = y0 + 4.0
        while yy < y1 - 2:
            last = yy + 7.2 >= y1 - 2
            for s in (-1, 1):
                fx0, fx1 = (px + 1.3, px + 12.5) if s > 0 else (px - 12.5, px - 1.3)
                m.box_lohi((fx0, yy - 0.5, 0.1), (fx1, yy + 0.5, 0.6), C["pontoon_side"], top=C["deck"], faces=["+y", "top", "-y", "-x", "+x"])
                pxl = fx1 if s > 0 else fx0
                m.prism(pxl, yy + 0.6, -1.5, 3.4, 0.42, 0.42, 6, C["pile"], cap_bottom=False, cap_top=False)
                m.prism(pxl, yy + 0.6, 3.4, 3.75, 0.47, 0.3, 6, C["white"], cap_bottom=True)
                if not last and rnd.random() < 0.85:          # 指桟橋と次の指桟橋のあいだ（1 区画に 1 隻）
                    kind = "sail" if rnd.random() < 0.45 else "motor"
                    L = rnd.uniform(9.0, 14.5) if kind == "sail" else rnd.uniform(8.5, 15.2)
                    bx = (fx0 + fx1) / 2 + s * rnd.uniform(0.0, 1.5)
                    by = yy + 3.6
                    heading = 0.0 if s > 0 else math.pi
                    boats.append((kind, L, bx, by, heading + rnd.uniform(-0.04, 0.04)))
            yy += 7.2
    return boats


def breakwater(m, rnd):
    """防波堤（岩の列と上の通路）と、先の赤白の灯台。BREAKWATER の折れ線に沿う。"""
    pts = BREAKWATER
    for (ax, ay), (bx_, by_) in zip(pts[:-1], pts[1:]):
        L = math.hypot(bx_ - ax, by_ - ay)
        dx, dy = (bx_ - ax) / L, (by_ - ay) / L
        nx, ny = -dy, dx
        t = 0.0
        while t < L:
            for s in (-1, 1):
                r = rnd.uniform(2.0, 3.0)
                col = C["rock"] if rnd.random() < 0.6 else C["rock2"]
                o = s * rnd.uniform(2.4, 3.6)
                m.blob((ax + dx * t + nx * o, ay + dy * t + ny * o, rnd.uniform(0.2, 0.9)), r, r * 0.9, r * 0.75,
                       shade(col, 1.08), shade(col, 0.7), seg=6, rings=3)
            t += rnd.uniform(3.2, 4.4)
        m.beam((ax - dx * 2.2, ay - dy * 2.2, 0.8), (bx_ + dx * 2.2, by_ + dy * 2.2, 0.8), 4.4, H("#D3CEC4"), h=3.6)
    bx, ly = pts[-1][0] - 3.0, pts[-1][1] + 1.0
    # 灯台
    m.prism(bx, ly, -1.0, 2.8, 4.2, 4.2, 12, H("#D9D5CC"))
    bands = [C["white"], C["red"], C["white"], C["red"]]
    zs = [2.8, 6.8, 10.8, 14.8, 18.6]
    for k in range(4):
        r0 = 2.1 - 0.55 * (zs[k] - 2.8) / 15.8
        r1 = 2.1 - 0.55 * (zs[k + 1] - 2.8) / 15.8
        m.prism(bx, ly, zs[k], zs[k + 1], r0, r1, 10, bands[k], cap_bottom=False, cap_top=False)
    m.prism(bx, ly, 18.6, 19.0, 2.3, 2.3, 10, C["white"])
    m.prism(bx, ly, 19.0, 20.9, 1.15, 1.15, 8, C["glow"], "night", cap_bottom=False)
    m.cone(bx, ly, 20.9, 22.6, 1.45, 10, C["red"])
    m.tube((bx, ly, 22.6), (bx, ly, 23.6), 0.08, C["white"], n=4, smooth=False)
    for k in range(10):
        a = 2 * math.pi * k / 10
        m.box((bx + 2.2 * math.cos(a), ly + 2.2 * math.sin(a), 19.5), (0.18, 0.18, 1.0), C["white"])
    return (bx, ly, 23.6)


def fenders(m, x0, x1):
    x = x0
    while x < x1:
        m.add_face([(x + 0.6, WALL_Y + 0.35, 0.2), (x, WALL_Y + 0.35, 0.2), (x, WALL_Y + 0.35, 3.0), (x + 0.6, WALL_Y + 0.35, 3.0)],
                   H("#2E3238"))
        x += 5.0


def build(seed=29, avoid=()):
    """岸辺の街の部品（街のローカル）。返り値：{名前: Mesh}, info。
    info["origins"]：原点を街の原点以外に置く部品（観覧車の輪とゴンドラ）の原点（街のローカル）。その部品の Mesh は原点からの座標。"""
    rnd = random.Random(seed)
    _LAST["col"] = None
    parts = {}
    info = {}
    gaps = list(STEPS)
    rail_gaps = list(STEPS) + [(p - 1.2, p + 1.2) for p in MARINA_PONTOONS] + [(BREAKWATER_X - 2.6, BREAKWATER_X + 2.6)]

    q = Mesh()
    quay(q, rnd, gaps)
    for a, b in STEPS:
        steps(q, a, b)
    railing(q, rail_gaps)
    fenders(q, TERMINAL_X[0] + 8, TERMINAL_X[1] - 4)
    boats = marina(q, rnd)
    info["lighthouse_top"] = breakwater(q, rnd)
    parts["AMS_CityQuay"] = q

    g = Mesh()
    paving(g, rnd, [PLAZA_X])
    promenade(g, rnd, [TERMINAL_X], [PLAZA_X])
    plaza(g, rnd)
    # 観覧車の前の小旗（灯の柱のあいだ）
    for x in range(int(PLAZA_X[0]) - 60, int(HALL_X[1]) + 40, 16):
        xa = X0 + 6.0 + 16.0 * round((x - X0 - 6.0) / 16.0)
        bunting(g, (xa, QUAY_Y - 2.0, GROUND + 5.4), (xa + 16.0, QUAY_Y - 2.0, GROUND + 5.4), 0.9,
                ["cobalt", "orange", "white", "teal", "yellow"])
    parts["AMS_CityPromenade"] = g

    b = Mesh()
    info["district"] = district(b, rnd, list(avoid))
    market_hall(b, rnd)
    terminal(b, rnd)
    parts["AMS_CityWaterfront"] = b

    wheel_parts, origins = ferris_wheel()     # 乱数は使わない（ボートの並びを変えない）
    parts.update(wheel_parts)

    h = Mesh()
    for kind, L, bx, by, heading in boats:
        bm = boat(rnd, kind, L)
        c, s = math.cos(heading), math.sin(heading)
        for i, p in enumerate(bm.v):
            bm.v[i] = (bx + p[0] * c - p[1] * s, by + p[0] * s + p[1] * c, p[2])
        h.extend(bm)
    fm = ferry(rnd)
    fm.v = [(FERRY_X + p[0], FERRY_Y + p[1], p[2]) for p in fm.v]
    h.extend(fm)
    parts["AMS_CityBoats"] = h
    info["boats"] = len(boats)
    info["wheel"] = {"center": (WHEEL_X, WHEEL_Y, WHEEL_HUB_Z), "radius": WHEEL_R, "axis": WHEEL_AXIS,
                     "gondolas": WHEEL_GONDOLAS, "rim_y": WHEEL_RIM_Y}
    info["origins"] = origins
    return parts, info

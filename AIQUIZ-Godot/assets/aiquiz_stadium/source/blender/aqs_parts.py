"""スタジアムの部品：側面スタンドのブロック、GOAL ゲート、ゴール観客席 B、灯台。

座標は各部品の約束どおり（dimensions.json の frame）。帆は aqs_sails、遠景は aqs_backdrop。
"""
from __future__ import annotations

import math
import random

from mathutils import Vector

from aqs_backdrop import palm
from aqs_common import C, GG, GS, IMG_WHITE, LAYOUT_GS, LH, ST
from aqs_geom import Mesh, mix, rounded_rect, shade

TINT_Z = -9.0   # 杭の色を変える境目（実行時に伸ばす -9.2 より上に置き、境目の頂点は動かさない）


def pile(m: Mesh, cx, cy, z_bottom, z_top, size, tint_z=None):
    """海面より下を少し青緑に寄せた角杭。"""
    tz = TINT_Z if tint_z is None else tint_z
    if z_bottom < tz < z_top:
        m.box_lohi((cx - size / 2, cy - size / 2, tz), (cx + size / 2, cy + size / 2, z_top), shade(C["white"], 0.97), faces=["-y", "+x", "+y", "-x", "top"])
        m.box_lohi((cx - size / 2, cy - size / 2, z_bottom), (cx + size / 2, cy + size / 2, tz), mix(C["white"], C["sea_tint"], 0.45), faces=["-y", "+x", "+y", "-x", "bottom"])
    else:
        m.box_lohi((cx - size / 2, cy - size / 2, z_bottom), (cx + size / 2, cy + size / 2, z_top), C["white"])


def disc_y(m: Mesh, cx, y, cz, r, n, col, mat="paint", depth=0.06):
    """-Y を向く円盤（丸窓など）。"""
    ring_f = [(cx + r * math.cos(2 * math.pi * i / n + math.pi / n), y - depth, cz + r * math.sin(2 * math.pi * i / n + math.pi / n)) for i in range(n)]
    ring_b = [(p[0], y, p[2]) for p in ring_f]
    for i in range(n):
        j = (i + 1) % n
        m.add_face([ring_b[i], ring_b[j], ring_f[j], ring_f[i]], shade(col, 0.9), mat)
    m.add_face(ring_f, col, mat)


# =============================================================================
# 1. 側面スタンドのブロック
# =============================================================================
def build_stand_block(kind: str):
    m = Mesh()
    y0, y1 = -10.0, 10.0
    prev_aisle = kind != "cap_start"
    next_aisle = kind != "cap_end"
    rows = ST["rows"]["count"]
    front = [ST["rows"]["first_seat_x"] - 0.55 + i * ST["rows"]["tread"] for i in range(rows + 1)]
    tops = [ST["rows"]["base_z"] + i * ST["rows"]["rise"] for i in range(rows)]
    walk_x0, back_x = ST["rear_walkway"]["x"]
    walk_top = ST["rear_walkway"]["top_z"]
    deck_top, deck_bot = ST["deck_top_z"], ST["deck_underside_z"]
    left = y0 + (1.1 if prev_aisle else 0.3)
    right = y1 - (1.1 if next_aisle else 0.3)

    # デッキと前面
    fx = ST["front_face_x"]
    m.box_lohi((fx, y0, deck_bot), (back_x, y1, deck_top), C["white"], top=shade(C["step"], 1.03),
               faces=["top", "bottom", "-y", "+y", "+x"])
    for za, zb, col in ((deck_bot, -0.36, C["white"]), (-0.36, -0.2, C["cobalt"]), (-0.2, deck_top, C["white"])):
        m.add_face([(fx, y1, za), (fx, y0, za), (fx, y0, zb), (fx, y1, zb)], col)     # -X 向き（走路側）
    fw = ST["front_wall"]
    wx0, wx1 = fw["x"] - fw["thickness"] / 2, fw["x"] + fw["thickness"] / 2
    m.box_lohi((wx0, y0, deck_top), (wx1, y1, fw["top_z"]), C["white"])
    m.box_lohi((wx0 - 0.03, y0, fw["top_z"]), (wx1 + 0.03, y1, fw["top_z"] + 0.06), C["cobalt"])
    m.box_lohi((wx0 - 0.015, y0, 0.46), (wx0, y1, 0.52), C["warm"], "night", faces=["-x"])        # 前手すりの灯の帯
    ny = int((y1 - y0) / fw["post_pitch"])
    for j in range(ny + 1):
        yy = y0 + 0.45 + j * fw["post_pitch"]
        if yy < y1 - 0.2:
            m.box((fw["x"], yy, (fw["top_z"] + 0.06 + fw["rail_top_z"]) / 2), (0.05, 0.05, fw["rail_top_z"] - fw["top_z"] - 0.06), C["white"])
    m.box_lohi((fw["x"] - 0.025, y0, 0.88), (fw["x"] + 0.025, y1, 0.92), C["white"])
    m.box_lohi((fw["x"] - 0.05, y0, fw["rail_top_z"] - 0.06), (fw["x"] + 0.05, y1, fw["rail_top_z"]), C["cobalt"])

    # 段
    for i in range(rows):
        x1 = front[i + 1] if i < rows - 1 else walk_x0
        m.box_lohi((front[i], left, deck_top), (x1, right, tops[i]), C["riser"], top=C["step"])
        m.box_lohi((front[i], left, tops[i]), (front[i] + 0.08, right, tops[i] + 0.02), C["white"])
    # 後方通路と背面の手すり
    m.box_lohi((walk_x0, y0, deck_top), (back_x, y1, walk_top), C["riser"], top=C["step"])
    rail_top = ST["rear_walkway"]["back_rail_top_z"]
    for k in range(8):
        yy = y0 + 1.25 + k * 2.5
        m.box((back_x - 0.1, yy, (walk_top + rail_top) / 2), (0.06, 0.06, rail_top - walk_top), C["white"])
    m.box_lohi((back_x - 0.15, y0, rail_top - 0.06), (back_x - 0.05, y1, rail_top), C["cobalt"])
    m.box_lohi((back_x - 0.125, y0, walk_top + 0.5), (back_x - 0.075, y1, walk_top + 0.55), C["white"])

    # 通路の階段（ブロックの +Y 端、幅 2.2m）
    if next_aisle:
        for j in range(12):
            xs = front[0] + j * 0.625
            top = ST["rows"]["base_z"] + j * 0.2
            m.box_lohi((xs, y1 - 1.1, deck_top), (xs + 0.625, y1 + 1.1, top), C["riser"], top=C["step"])
        for sgn in (-1.0, 1.0):
            yy = y1 + sgn * 1.0
            za = lambda x: 1.22 + (x - front[0]) / (walk_x0 - front[0]) * (walk_top + 0.9 - 1.22)
            for px in (0.9, 4.4, 7.8):
                floor = ST["rows"]["base_z"] + min(11, int((px - front[0]) / 0.625)) * 0.2
                m.box((px, yy, (floor + za(px)) / 2), (0.05, 0.05, za(px) - floor), C["white"])
            m.beam((front[0], yy, za(front[0])), (walk_x0, yy, za(walk_x0)), 0.06, C["cobalt"])

    # 座席
    seats = []
    for i in range(rows):
        x = ST["rows"]["seat_x"][i]
        floor = tops[i]
        for k in range(ST["seats"]["per_row"]):
            yy = ST["seats"]["z_range"][0] + k * ST["seats"]["pitch"]
            if yy - 0.33 < left or yy + 0.33 > right:
                continue
            m.box((x, yy, floor + 0.50), (0.61, 0.62, 0.09), C["seat"])
            m.box((x + 0.265, yy, floor + 0.78), (0.10, 0.62, 0.43), C["seat"])
            m.box((x + 0.05, yy, floor + 0.2275), (0.30, 0.30, 0.455), shade(C["seat"], 0.9))
            seats.append([round(x, 4), round(floor + 0.545, 4), round(-yy, 4), i])

    # 杭と桁
    pz0, pz1 = ST["piles"]["bottom_z"], ST["piles"]["top_z"]
    for yy in (-7.5, -2.5, 2.5, 7.5):
        for x in ST["piles"]["x"]:
            pile(m, x, yy, pz0, pz1 - 0.6, ST["piles"]["section"])
        m.box_lohi((-0.2, yy - 0.3, pz1 - 0.6), (back_x - 0.2, yy + 0.3, pz1), C["deck_under"])

    if kind == "bay":
        build_booth(m)
    else:
        build_cap_end(m, kind, front, tops, walk_x0, back_x, walk_top, deck_top, y0, y1)
    return m, seats, next_aisle


def build_booth(m: Mesh):
    """ブース（丸みのある箱と帯）。2026-09-28 のユーザー指示で、帆・マスト・ヤード・シュラウドと「?」の画面は作らない
    （帆は aqs_sails で書き出しは続くが、ゲームでは置かない）。"""
    b = ST["booth"]
    bx0, bx1 = b["x"]
    hy = b["length_y"] / 2
    z0, z1 = b["base_z"], b["base_z"] + b["height"]
    body = rounded_rect(bx0, -hy, bx1, hy, b["corner_radius"], seg=4)
    m.extrude_poly(body, z0, z1, C["white"], bottom=False)
    band = rounded_rect(bx0 - 0.08, -hy - 0.08, bx1 + 0.08, hy + 0.08, b["corner_radius"] + 0.08, seg=4)
    m.extrude_poly(band, z1, z1 + 0.12, C["cobalt"], bottom=True)
    cap = rounded_rect(bx0 + 0.1, -hy + 0.1, bx1 - 0.1, hy - 0.1, b["corner_radius"] - 0.08, seg=4)
    m.extrude_poly(cap, z1 + 0.12, z1 + 0.24, shade(C["white"], 1.02), bottom=False)


def build_cap_end(m: Mesh, kind, front, tops, walk_x0, back_x, walk_top, deck_top, y0, y1):
    s = 1.0 if kind == "cap_start" else -1.0      # 閉じる端から内側への向き
    ye = y0 if kind == "cap_start" else y1
    yi = ye + s * 0.3
    for i in range(len(tops)):
        x1 = front[i + 1] if i < len(tops) - 1 else walk_x0
        m.box_lohi((front[i], ye, deck_top), (x1, yi, tops[i] + 0.9), C["white"])
        m.box_lohi((front[i] - 0.02, ye - s * 0.03, tops[i] + 0.9), (x1, yi + s * 0.03, tops[i] + 0.96), C["cobalt"])
    m.box_lohi((walk_x0, ye, deck_top), (back_x, yi, walk_top + 1.1), C["white"])
    m.box_lohi((walk_x0, ye - s * 0.03, walk_top + 1.1), (back_x, yi + s * 0.03, walk_top + 1.16), C["cobalt"])
    m.box_lohi((ST["front_face_x"], ye, deck_top), (front[0], yi, 1.16), C["white"])
    # 見張り塔（外側の後ろの角）
    tx0, tx1 = back_x - 1.6, back_x - 0.1
    ty0, ty1 = sorted((yi, yi + s * 1.5))
    m.box_lohi((tx0, ty0, walk_top), (tx1, ty1, 6.0), C["white"])
    for cx in (tx0 + 0.08, tx1 - 0.08):
        for cy in (ty0 + 0.08, ty1 - 0.08):
            m.box((cx, cy, 6.8), (0.15, 0.15, 1.6), C["white"])
    for (ax, ay), (bx, by) in (((tx0, ty0), (tx1, ty0)), ((tx1, ty0), (tx1, ty1)), ((tx1, ty1), (tx0, ty1)), ((tx0, ty1), (tx0, ty0))):
        m.beam((ax, ay, 6.9), (bx, by, 6.9), 0.07, C["cobalt"])
    cx, cy = (tx0 + tx1) / 2, (ty0 + ty1) / 2
    m.box_lohi((tx0 - 0.1, ty0 - 0.1, 7.6), (tx1 + 0.1, ty1 + 0.1, 7.7), C["cobalt"])
    m.cone(cx, cy, 7.7, 8.8, 1.15, 4, C["cobalt"], phase=math.pi / 4)
    m.box((cx, cy, 9.4), (0.08, 0.08, 1.2), C["white"])
    m.quad2((cx, cy, 9.95), (cx, cy + s * 0.9, 9.95), (cx, cy + s * 0.9, 9.4), (cx, cy, 9.4), C["white"])
    m.box((cx, cy, 10.05), (0.25, 0.25, 0.2), C["warm"], "night")
    # 海側の船着き場へ下りる階段と桟橋
    steps = 56
    y_top = ye + s * 17.3
    for j in range(steps):
        ya = y_top - s * 0.3 * j
        yb = ya - s * 0.3
        top = walk_top - 0.2 * j
        m.box_lohi((back_x + 0.1, ya, top - 0.2), (back_x + 1.3, yb, top), C["white"], top=C["step"])
    y_bot = y_top - s * 0.3 * steps
    m.beam((back_x + 1.25, y_top, walk_top + 0.9), (back_x + 1.25, y_bot, walk_top - 0.2 * steps + 0.9), 0.06, C["cobalt"])
    for k in range(5):
        yy = y_top - s * (0.3 * steps) * k / 4
        zt = walk_top - 0.2 * (0.3 * steps * k / 4) / 0.3
        m.box((back_x + 1.25, yy, zt + 0.45), (0.05, 0.05, 0.9), C["white"])
        if k in (1, 2, 3):
            pile(m, back_x + 0.7, yy, ST["piles"]["bottom_z"], zt - 0.2, 0.3)
    lz = walk_top - 0.2 * steps
    ly0, ly1 = sorted((y_bot + s * 0.3, y_bot - s * 3.0))
    m.box_lohi((back_x + 0.1, ly0, lz - 0.3), (back_x + 3.6, ly1, lz), C["white"], top=C["step"])
    for cx2 in (back_x + 0.5, back_x + 3.2):
        for cy2 in (ly0 + 0.3, ly1 - 0.3):
            pile(m, cx2, cy2, ST["piles"]["bottom_z"], lz - 0.3, 0.35)
    for cy2 in (ly0 + 0.4, ly1 - 0.4):
        m.box((back_x + 3.4, cy2, lz + 0.35), (0.25, 0.25, 0.7), C["dark"])


# =============================================================================
# 2. GOAL ゲート
# =============================================================================
def truss_column(m: Mesh, cx, cy, z0, z1, w, chord, col):
    h = w / 2 - chord / 2
    corners = [(cx - h, cy - h), (cx + h, cy - h), (cx + h, cy + h), (cx - h, cy + h)]
    for x, y in corners:
        m.box_lohi((x - chord / 2, y - chord / 2, z0), (x + chord / 2, y + chord / 2, z1), col)
    n = max(1, round((z1 - z0) / 0.7))
    for k in range(n + 1):
        z = z0 + (z1 - z0) * k / n
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            m.beam((a[0], a[1], z), (b[0], b[1], z), chord * 0.6, col)
            if k < n:
                zz = z0 + (z1 - z0) * (k + 1) / n
                if k % 2 == 0:
                    m.beam((a[0], a[1], z), (b[0], b[1], zz), chord * 0.5, col)
                else:
                    m.beam((b[0], b[1], z), (a[0], a[1], zz), chord * 0.5, col)


def build_goal_gate():
    m = Mesh()
    cxs = GG["pillar_center_abs_x"]
    w = GG["pillar_section"]
    pl = GG["plinth"]
    bar_z0 = GG["clear_height"]
    bar_z1 = bar_z0 + w
    for sgn in (-1, 1):
        cx = sgn * cxs
        m.box((cx, 0, pl[1] / 2), (pl[0], pl[2], pl[1]), C["white"])     # [x, 高さ, 奥行き]（Godot の並び）
        truss_column(m, cx, 0, pl[1], bar_z1, w, 0.1, C["steel"])
        for fy in (w / 2 + 0.005, -w / 2 - 0.005):
            m.box_lohi((cx - 0.05, fy - 0.01, pl[1] + 0.05), (cx + 0.05, fy + 0.01, bar_z1 - 0.05), C["cobalt"])
        f = GG["floodlight_box"]
        m.box((cx, 0, bar_z1 + 0.05 + f / 2), (f, f, f), C["white"])
        m.box_lohi((cx - f * 0.4, f / 2, bar_z1 + 0.15), (cx + f * 0.4, f / 2 + 0.02, bar_z1 + f - 0.05), C["cool"], "night", faces=["+y"])
        m.box_lohi((cx - f * 0.4, -f / 2 - 0.02, bar_z1 + 0.15), (cx + f * 0.4, -f / 2, bar_z1 + f - 0.05), C["cool"], "night", faces=["-y"])
    # 梁（格子トラス）
    xa, xb = -cxs + w / 2, cxs - w / 2
    h = w / 2 - 0.05
    for yy in (-h, h):
        for zz in (bar_z0 + 0.05, bar_z1 - 0.05):
            m.box_lohi((xa, yy - 0.05, zz - 0.05), (xb, yy + 0.05, zz + 0.05), C["steel"])
    n = round((xb - xa) / 0.7)
    for k in range(n + 1):
        x = xa + (xb - xa) * k / n
        for yy in (-h, h):
            m.beam((x, yy, bar_z0 + 0.05), (x, yy, bar_z1 - 0.05), 0.06, C["steel"])
        m.beam((x, -h, bar_z0 + 0.05), (x, h, bar_z0 + 0.05), 0.06, C["steel"])
        if k < n:
            x2 = xa + (xb - xa) * (k + 1) / n
            for yy in (-h, h):
                za, zb = (bar_z0 + 0.05, bar_z1 - 0.05) if k % 2 == 0 else (bar_z1 - 0.05, bar_z0 + 0.05)
                m.beam((x, yy, za), (x2, yy, zb), 0.05, C["steel"])
    # 看板（両面、+Y が走ってくる側）
    b = GG["board"]
    bw, bh, fr = b["width"] / 2, b["height"], b["frame"]
    zc = (bar_z0 + bar_z1) / 2
    z0, z1 = zc - bh / 2, zc + bh / 2
    for sgn in (1, -1):
        y_in, y_out = sgn * (w / 2 + 0.02), sgn * (w / 2 + 0.14)
        m.box_lohi((-bw - fr, y_in, z0 - fr), (bw + fr, y_out, z1 + fr), C["white"])
        yf = y_out + sgn * 0.005
        # 見る人の右へ u が増えるように：+Y 面（走ってくる側）は右が -X、-Y 面は右が +X
        xl = bw if sgn > 0 else -bw
        m.add_face([(xl, yf, z0), (-xl, yf, z0), (-xl, yf, z1), (xl, yf, z1)], IMG_WHITE, "goal_board",
                   [(0, 0), (1, 0), (1, 1), (0, 1)])
    return m


# =============================================================================
# 3. ゴール観客席 B（港の操舵室）— goal_stand_layout.json の段・通路を保持
# =============================================================================
def build_goal_stand():
    stand, board = Mesh(), Mesh()
    L = LAYOUT_GS
    half = L["width"] / 2
    back_y, back_top = L["back_y"], L["back_top"]
    tiers = L["tiers"]
    tread = 1.35
    tier_front = [0.30 + i * tread for i in range(len(tiers) + 1)]
    stand.box_lohi((-half - 0.3, -0.1, -0.6), (half + 0.3, 7.95, 0.0), C["white"])
    stand.box_lohi((-half - 0.3, -0.12, -0.45), (half + 0.3, -0.1, -0.3), C["cobalt"], faces=["-y"])
    stand.box_lohi((-half, 0.0, 0.0), (half, 0.30, L["parapet_top"] - 0.06), C["white"])
    stand.box_lohi((-half - 0.05, -0.03, L["parapet_top"] - 0.06), (half + 0.05, 0.33, L["parapet_top"]), C["cobalt"])
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
    stand.box_lohi((-half, back_y - 0.30, 0.0), (half, back_y, back_top), C["white"])
    stand.box_lohi((-half - 0.03, back_y - 0.33, back_top), (half + 0.03, back_y + 0.03, back_top + 0.06), C["cobalt"])
    ld = GS["lower_deckhouse"]
    for sgn in (-1, 1):
        for k in range(ld["portholes_per_side"]):
            px = sgn * (7.0 + k * ld["porthole_pitch"])
            disc_y(stand, px, back_y - 0.30, 2.45, ld["porthole_diameter"] / 2, 10, C["cobalt"], depth=0.06)
            disc_y(stand, px, back_y - 0.36, 2.45, ld["porthole_diameter"] / 2 - 0.1, 10, C["glass"], depth=0.02)
    for sgn in (-1, 1):
        x0, x1 = sorted((sgn * half, sgn * (half - 0.3)))
        prof = [(0.30, L["parapet_top"])] + [(tier_front[i + 1] if i < len(tiers) - 1 else back_y, tiers[i]["floor_z"] + 1.0) for i in range(len(tiers))]
        ys = 0.0
        for ye, zt in prof:
            stand.box_lohi((x0, ys, 0.0), (x1, ye, zt), C["white"])
            stand.box_lohi((x0 - 0.02, ys, zt), (x1 + 0.02, ye, zt + 0.06), C["cobalt"])
            ys = ye
    for fx, col in ((L["flags"]["p1_x"], C["orange"]), (L["flags"]["p2_x"], C["blue"])):
        stand.box((fx, 0.15, (L["parapet_top"] + 5.5) / 2), (0.08, 0.08, 5.5 - L["parapet_top"]), C["white"])
        stand.quad2((fx, 0.15, 5.45), (fx - math.copysign(1.4, fx), 0.15, 5.45), (fx - math.copysign(1.4, fx), 0.15, 4.6), (fx, 0.15, 4.6), col)
    for x in (-12.3, -6.0, 0.0, 6.0, 12.3):
        for yy in (0.3, 3.9, 7.4):
            pile(stand, x, yy, -128.0, -1.1, 0.6, tint_z=-7.8)
    for yy in (0.3, 3.9, 7.4):
        stand.box_lohi((-12.6, yy - 0.25, -1.1), (12.6, yy + 0.25, -0.6), C["deck_under"])

    sb = L["scoreboard"]
    sw = sb["screen_width"] / 2
    sz0 = sb["screen_z"]
    sz1 = sz0 + sb["screen_height"]
    bez = 0.30
    cab_x = sb["width"] / 2
    cab_y0 = back_y + 0.05
    cab_top = sz1 + bez
    board.box_lohi((-cab_x, cab_y0, sz0 - bez), (cab_x, cab_y0 + 1.0, cab_top), C["dark"])
    for lo, hi in (((-cab_x, sb["screen_y"] - 0.06, sz0 - bez), (cab_x, cab_y0, sz0)),
                   ((-cab_x, sb["screen_y"] - 0.06, sz1), (cab_x, cab_y0, cab_top)),
                   ((-cab_x, sb["screen_y"] - 0.06, sz0), (-sw, cab_y0, sz1)),
                   ((sw, sb["screen_y"] - 0.06, sz0), (cab_x, cab_y0, sz1))):
        board.box_lohi(lo, hi, C["dark"])
    ys = sb["screen_y"]
    board.add_face([(-sw, ys, sz0), (sw, ys, sz0), (sw, ys, sz1), (-sw, ys, sz1)], IMG_WHITE, "screen",
                   [(0, 0), (1, 0), (1, 1), (0, 1)])
    h0, h1 = cab_top, sb["top"] - 0.92
    board.box_lohi((-cab_x, cab_y0, h0), (cab_x, cab_y0 + 1.0, h1), C["navy"])
    hw = (h1 - h0) * 2.5 / 2
    yh = cab_y0 - 0.01
    board.add_face([(-hw, yh, h0), (hw, yh, h0), (hw, yh, h1), (-hw, yh, h1)], IMG_WHITE, "header",
                   [(0, 0), (1, 0), (1, 1), (0, 1)])
    bh = GS["bridge_house"]
    tw = (bh["width"] / 2) - cab_x
    house_y0, house_y1 = back_y, back_y + bh["depth"]
    roof_z0 = sb["top"] - 0.30
    for sgn in (-1, 1):
        xi, xo = sgn * cab_x, sgn * (cab_x + tw)
        ch = 0.8
        pts = [(xi, house_y0), (xo - sgn * ch, house_y0), (xo, house_y0 + ch), (xo, house_y1 - ch), (xo - sgn * ch, house_y1), (xi, house_y1)]
        if sgn < 0:
            pts = list(reversed(pts))
        board.extrude_poly(pts, back_top, roof_z0, C["white"])
        wx = sgn * (cab_x + tw / 2)
        ww, wh = bh["side_tower_window"]
        board.box_lohi((wx - ww / 2, house_y0 - 0.05, 9.2), (wx + ww / 2, house_y0, 9.2 + wh), C["glass"])
        board.box_lohi((wx - ww / 2 - 0.08, house_y0 - 0.07, 9.12), (wx + ww / 2 + 0.08, house_y0 - 0.05, 9.2), C["white"])
        for zc in (4.4, 5.7, 7.0):
            disc_y(board, wx, house_y0, zc, 0.46, 10, C["cobalt"], depth=0.08)
            disc_y(board, wx, house_y0 - 0.08, zc, 0.34, 10, C["glass"], depth=0.02)
        for zz in (7.8, 8.1):
            board.box_lohi((min(xi, xo) + 0.05, house_y0 - 0.04, zz), (max(xi, xo) - 0.05, house_y0, zz + 0.15), C["cobalt"])
    board.box_lohi((-cab_x, cab_y0 + 1.0, back_top), (cab_x, house_y1, roof_z0), C["white"])
    rx = bh["width"] / 2 + 0.3
    board.box_lohi((-rx, house_y0 - 0.2, roof_z0), (rx, house_y1 + 0.3, roof_z0 + 0.15), C["cobalt"])
    board.box_lohi((-rx + 0.05, house_y0 - 0.15, roof_z0 + 0.15), (rx - 0.05, house_y1 + 0.25, sb["top"]), C["white"])
    mm = GS["mast"]
    my = (house_y0 + house_y1) / 2
    base = sb["top"]
    board.prism(0, my, base, mm["top_z"], 0.28, 0.2, 10, C["wood"], smooth=True)
    cn = mm["crows_nest"]
    board.prism(0, my, cn["z"], cn["z"] + 0.12, cn["diameter"] / 2, cn["diameter"] / 2, 10, C["wood"])
    board.prism(0, my, cn["z"] + 0.12, cn["z"] + cn["height"], cn["diameter"] / 2, cn["diameter"] / 2 * 1.05, 10, shade(C["wood"], 1.1), cap_top=False, cap_bottom=False)
    for y in mm["yards"]:
        board.tube((-y["length"] / 2, my, y["z"]), (y["length"] / 2, my, y["z"]), 0.1, C["wood"], n=8, caps=True)
    ly = mm["yards"][0]
    for sx_, col in ((-1, C["orange"]), (1, C["blue"])):      # Blender -X → Godot（180° 回転後）+X ＝ P1
        x = sx_ * ly["length"] / 2
        board.box((x, my, ly["z"] + 0.6), (0.06, 0.06, 1.2), C["white"])
        board.quad2((x, my, ly["z"] + 1.2), (x + sx_ * 1.3, my, ly["z"] + 1.15), (x + sx_ * 1.3, my, ly["z"] + 0.45), (x, my, ly["z"] + 0.4), col)
    board.box((0, my, mm["top_z"] + 0.2), (0.3, 0.3, 0.3), C["warm"], "night")
    rs = GS["roof_sails"]
    for sx_ in (-1, 1):
        a = Vector((sx_ * 0.35, my, rs["apex_z"]))
        b = Vector((sx_ * rs["foot_abs_x"], my, rs["foot_z"]))
        c = Vector((sx_ * 0.35, my, rs["foot_z"]))
        mid = (a + b + c) / 3 + Vector((0, -0.6, 0))
        for p0, p1, uvs in ((a, b, [(0, 1), (1, 0)]), (b, c, [(1, 0), (0, 0)]), (c, a, [(0, 0), (0, 1)])):
            board.add_face([p0, p1, mid], IMG_WHITE, "sail", [uvs[0], uvs[1], (0.35, 0.35)], smooth=False)
    for sx_ in (-1, 1):
        for yy in (house_y0 - 0.1, house_y1 + 0.2):
            board.tube((0, my, mm["top_z"] - 0.2), (sx_ * (rx - 0.2), yy, base + 0.05), 0.03, C["rope"], n=4)
    return stand, board


# =============================================================================
# 4. 灯台（B 案）
# =============================================================================
def star(n, r, jitter, seed, sx=1.0, sy=1.0):
    rnd = random.Random(seed)
    return [(r * sx * (1 + rnd.uniform(-jitter, jitter)) * math.cos(2 * math.pi * i / n),
             r * sy * (1 + rnd.uniform(-jitter, jitter)) * math.sin(2 * math.pi * i / n)) for i in range(n)]


def build_lighthouse():
    m = Mesh()
    res = LH["resolved"]
    W = LH["sign_inner_width_W"]
    isl_r = res["islet_width"] / 2
    isl_h = res["islet_height"]
    m.extrude_poly(star(18, isl_r * 1.04, 0.05, 11), -1.2, 0.9, shade(C["sand"], 1.03))
    m.extrude_poly(star(14, isl_r * 0.82, 0.12, 12), 0.9, isl_h * 0.55, C["rock"])
    m.extrude_poly(star(12, isl_r * 0.62, 0.1, 13), isl_h * 0.55, isl_h, shade(C["rock"], 1.06), top=C["sand"])
    rnd = random.Random(21)
    for k in range(7):
        ang = 2 * math.pi * k / 7 + 0.4
        rr = isl_r * rnd.uniform(0.75, 0.95)
        m.extrude_poly([(p[0] + rr * math.cos(ang), p[1] + rr * math.sin(ang)) for p in star(6, rnd.uniform(2.2, 4.0), 0.25, 30 + k)],
                       0.2, rnd.uniform(2.5, 5.0), shade(C["rock"], rnd.uniform(0.9, 1.1)))
    for k, (ang, rr, h) in enumerate(((0.6, 0.5, 8.5), (1.1, 0.42, 7.5), (2.4, 0.5, 9.0), (4.0, 0.46, 8.0), (5.2, 0.5, 7.0))):
        palm(m, (isl_r * rr * math.cos(ang), isl_r * rr * math.sin(ang), isl_h - 0.2), h, (0.08 * math.cos(ang), 0.08 * math.sin(ang)), random.Random(40 + k),
             mat="paint")
    m.box_lohi((-1.8, isl_r * 0.95, 0.4), (1.8, isl_r * 0.95 + 11.0, 0.9), C["white"], top=C["step"])
    for yy in (isl_r * 0.95 + 4.0, isl_r * 0.95 + 10.4):
        for xx in (-1.5, 1.5):
            m.box_lohi((xx - 0.2, yy - 0.2, -3.0), (xx + 0.2, yy + 0.2, 1.4), C["white"])
    plinth_r = res["plinth_width"] / 2
    z_p0, z_p1 = isl_h, isl_h + 2.0
    m.prism(0, 0, z_p0, z_p1, plinth_r, plinth_r * 0.98, 16, C["white"], top=C["step"])
    r_low, r_top = res["tower_width_low"] / 2, res["tower_width_top"] / 2
    z_g = res["gallery_floor_above_water"]
    m.prism(0, 0, z_p1, z_g, r_low, r_top, 20, C["white"], smooth=True)
    radius_at = lambda z: r_low + (r_top - r_low) * (z - z_p1) / (z_g - z_p1)
    m.box_lohi((-0.9, radius_at(z_p1) - 0.4, z_p1), (0.9, radius_at(z_p1) + 0.12, z_p1 + 2.8), C["glass"])
    for zc in (28.0, 38.0):
        rr = radius_at(zc)
        m.box_lohi((-0.55, rr - 0.3, zc), (0.55, rr + 0.1, zc + 1.6), C["glass"])
    m.prism(0, 0, z_g, z_g + 0.6, r_top + 1.1, r_top + 1.1, 16, C["white"])
    rail_r = r_top + 1.0
    for i in range(16):
        a = 2 * math.pi * i / 16
        m.box((rail_r * math.cos(a), rail_r * math.sin(a), z_g + 1.15), (0.12, 0.12, 1.1), C["white"])
        a2 = 2 * math.pi * (i + 1) / 16
        m.beam((rail_r * math.cos(a), rail_r * math.sin(a), z_g + 1.7), (rail_r * math.cos(a2), rail_r * math.sin(a2), z_g + 1.7), 0.1, C["white"])
    lr = res["lantern_width"] / 2
    lz0, lz1 = z_g + 0.6, z_g + 0.6 + res["lantern_height"]
    m.prism(0, 0, lz0, lz0 + 0.8, lr + 0.2, lr + 0.2, 12, C["white"])
    m.prism(0, 0, lz0 + 0.8, lz1, lr, lr, 12, C["lantern"], "night", cap_top=False, cap_bottom=False)
    for i in range(12):
        a = 2 * math.pi * i / 12
        m.beam((lr * 1.02 * math.cos(a), lr * 1.02 * math.sin(a), lz0 + 0.8), (lr * 1.02 * math.cos(a), lr * 1.02 * math.sin(a), lz1), 0.12, C["white"])
    m.prism(0, 0, (lz0 + lz1) / 2, (lz0 + lz1) / 2 + 0.12, lr * 1.03, lr * 1.03, 12, C["white"])
    top_z = res["dome_top_above_water"]
    m.prism(0, 0, lz1, lz1 + 0.35, lr + 0.35, lr + 0.35, 12, C["dome"])
    m.dome(0, 0, lz1 + 0.35, lr + 0.1, (top_z - 1.2) - (lz1 + 0.35), 12, 4, C["dome"], smooth=True)
    m.prism(0, 0, top_z - 1.2, top_z - 0.5, 0.35, 0.35, 8, C["dome"])
    m.cone(0, 0, top_z - 0.5, top_z, 0.55, 8, C["dome"])
    sh = W / 2.5
    fr = res["sign_frame_border"]
    zb = res["sign_bottom_above_water"]
    zt = zb + sh + 2 * fr
    y_back = radius_at((zb + zt) / 2) + 0.6
    y_front = y_back + 0.8
    m.box_lohi((-W / 2 - fr, y_back, zb), (W / 2 + fr, y_front, zt), C["white"])
    yf = y_front + 0.02
    m.add_face([(W / 2, yf, zb + fr), (-W / 2, yf, zb + fr), (-W / 2, yf, zb + fr + sh), (W / 2, yf, zb + fr + sh)],
               IMG_WHITE, "lh_sign", [(0, 0), (1, 0), (1, 1), (0, 1)])
    for sx_ in (-1, 1):
        for zc in (zb + 2.5, zt - 2.5):
            m.beam((sx_ * 2.8, radius_at(zc) - 0.4, zc), (sx_ * 2.8, y_back + 0.05, zc), 0.5, C["white"])
        yb = (y_back + y_front) / 2
        top_chord = [(sx_ * (radius_at(zb) + 0.3), yb, zb - 0.3), (sx_ * (W / 2 + fr - 0.3), yb, zb - 0.3)]
        bot_chord = [(sx_ * (radius_at(zb - 4.0) + 0.3), yb, zb - 4.0), (sx_ * (W / 2 + fr - 0.3), yb, zb - 1.4)]
        m.beam(top_chord[0], top_chord[1], 0.45, C["white"])
        m.beam(bot_chord[0], bot_chord[1], 0.45, C["white"])
        n = 5
        for k in range(n + 1):
            t = k / n
            pt = Vector(top_chord[0]).lerp(Vector(top_chord[1]), t)
            pb = Vector(bot_chord[0]).lerp(Vector(bot_chord[1]), t)
            m.beam(tuple(pt), tuple(pb), 0.3, C["white"])
            if k < n:
                pt2 = Vector(top_chord[0]).lerp(Vector(top_chord[1]), (k + 1) / n)
                m.beam(tuple(pb), tuple(pt2), 0.3, C["white"])
    return m

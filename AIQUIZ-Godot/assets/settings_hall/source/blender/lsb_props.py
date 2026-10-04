"""講義セットの小道具（PRP_*）。座標・寸法は Godot のセットのローカル（x 横, y 高さ, z 奥行き）で書き、
_b() / S() で Blender（x, -z, y）に写す。

Godot 側（lecture_set.gd）の定数と一致させる: 黒板 (0, 8.6) 中心高さ 2.3、教壇 (2.0, 6.3)、机 x ∈ {-2.3, 0, 2.3} z 1.6、
椅子 z 0.74、模型の台 (-3.9, 5.4)、台座 中心 (-0.8, 4.2) 12×11.5。
"""
from __future__ import annotations

import math
import random

from mathutils import Matrix, Vector

from lsb_common import MeshBuilder, aim_matrix, g2b

PLATFORM_SIZE = (12.0, 11.5)
PLATFORM_CENTER = (-0.8, 4.2)
BOARD_W = 7.6
BOARD_H = 3.3
BOARD_CENTER_Y = 2.3
BOARD_Z = 8.6
TEXT_AREA_W = 5.6  # 左側: Godot の文字のために空ける
DESK_XS = (-2.3, 0.0, 2.3)
DESK_Z = 1.6
STOOL_Z = 0.74  # ぬいぐるみの胴の正面（0.507 m）が机の手前の縁（z 1.3）に当たらない位置
STOOL_TOP = 0.45
RX = Matrix.Rotation(math.radians(90.0), 3, "X")   # 円筒の軸を Z → Blender Y（Godot の奥行き）へ、板を立てる
RY = Matrix.Rotation(math.radians(90.0), 3, "Y")   # 円筒の軸を Z → X へ


def _b(x, y, z):
    """Godot (x, 高さ, 奥行き) → Blender。"""
    return g2b(x, y, z)


def S(w, h, d):
    """Godot の寸法 (幅, 高さ, 奥行き) → Blender の (x, y, z)。"""
    return (w, d, h)


def tilt(deg):
    """前後の傾き（Blender X まわり）。"""
    return Matrix.Rotation(math.radians(deg), 3, "X")


def build_platform(col):
    mb = MeshBuilder("PRP_Platform")
    cx, cz = PLATFORM_CENTER
    w, d = PLATFORM_SIZE
    plank = 0.3
    count = int(round(d / plank))
    rng = random.Random(7)
    for i in range(count):
        z = cz - d * 0.5 + (i + 0.5) * plank
        wood = ("LS_WoodA", "LS_WoodB", "LS_WoodC")[rng.randrange(3)]
        pieces = rng.choice((2, 3))
        x0 = cx - w * 0.5
        cuts = sorted(rng.uniform(0.25, 0.75) * w for _ in range(pieces - 1))
        edges = [0.0] + cuts + [w]
        for k in range(pieces):
            length = edges[k + 1] - edges[k] - 0.012
            xm = x0 + (edges[k] + edges[k + 1]) * 0.5
            mb.box(S(length, 0.06, plank - 0.012), _b(xm, 0.05, z), wood)
    mb.box(S(w + 0.1, 0.02, d + 0.1), _b(cx, 0.01, cz), "LS_WoodDark")
    bar = 0.12
    for sx in (-1.0, 1.0):
        mb.box(S(bar, 0.1, d + bar), _b(cx + sx * w * 0.5, 0.05, cz), "LS_Steel")
    for sz in (-1.0, 1.0):
        mb.box(S(w + bar, 0.1, bar), _b(cx, 0.05, cz + sz * d * 0.5), "LS_Steel")
    return mb.build(col, bevel=0.008)


def build_blackboard(col):
    mb = MeshBuilder("PRP_Blackboard")
    cy = BOARD_CENTER_Y
    fw, fh, ft = BOARD_W + 0.3, BOARD_H + 0.3, 0.14
    # 木枠（4 本）と裏板、黒板面（面はカメラ側 -Z へ少し出す）
    mb.box(S(fw, 0.15, ft), _b(0.0, cy + fh * 0.5 - 0.075, BOARD_Z), "LS_WoodA")
    mb.box(S(fw, 0.15, ft), _b(0.0, cy - fh * 0.5 + 0.075, BOARD_Z), "LS_WoodA")
    for sx in (-1.0, 1.0):
        mb.box(S(0.15, fh, ft), _b(sx * (fw * 0.5 - 0.075), cy, BOARD_Z), "LS_WoodA")
    mb.box(S(BOARD_W, BOARD_H, 0.03), _b(0.0, cy, BOARD_Z + 0.03), "LS_WoodDark")
    mb.box(S(BOARD_W, BOARD_H, 0.02), _b(0.0, cy, BOARD_Z - 0.045), "LS_Board")
    # 脚（垂直の円筒）と足
    post_h = cy + fh * 0.5 + 0.1
    for sx in (-1.0, 1.0):
        x = sx * (fw * 0.5 + 0.08)
        mb.cylinder(0.05, post_h, _b(x, post_h * 0.5, BOARD_Z), "LS_DarkSteel", segments=16, radius2=0.06)
        mb.box(S(0.5, 0.06, 0.4), _b(x, 0.03, BOARD_Z), "LS_DarkSteel")
    # チョーク受けとチョーク、黒板消し
    tray_y = cy - BOARD_H * 0.5 + 0.02
    mb.box(S(BOARD_W * 0.9, 0.04, 0.12), _b(0.0, tray_y, BOARD_Z - 0.12), "LS_WoodB")
    mb.box(S(BOARD_W * 0.9, 0.05, 0.02), _b(0.0, tray_y + 0.04, BOARD_Z - 0.17), "LS_WoodB")
    for x, m in ((-2.4, "LS_Chalk"), (-2.25, "LS_ChalkYellow"), (-2.1, "LS_ChalkPink"), (1.9, "LS_Chalk")):
        mb.cylinder(0.009, 0.08, _b(x, tray_y + 0.03, BOARD_Z - 0.13), m, rotation=RY, segments=10)
    mb.box(S(0.14, 0.05, 0.06), _b(2.6, tray_y + 0.045, BOARD_Z - 0.12), "LS_WoodDark")
    mb.box(S(0.14, 0.02, 0.06), _b(2.6, tray_y + 0.08, BOARD_Z - 0.12), "LS_Cloth")
    # チョーク画（右端 1.8 m、Godot -X 側）: 8 枚の刃の列、台車の線、寸法の矢印、回転の弧、跳び越える棒人間
    x0 = -(BOARD_W * 0.5 - 0.2)
    x1 = x0 + (BOARD_W - TEXT_AREA_W - 0.4)
    zf = BOARD_Z - 0.065
    cxm = (x0 + x1) * 0.5
    blade_y = cy - 0.55
    pitch = (x1 - x0) / 8.0
    for k in range(8):
        x = x0 + (k + 0.5) * pitch
        mb.torus(pitch * 0.33, 0.009, _b(x, blade_y, zf), "LS_Chalk", rotation=RX, segments=18, rings=6)
        mb.sphere(0.014, _b(x, blade_y, zf), "LS_Chalk", segments=8, rings=5)
    mb.box(S(x1 - x0, 0.02, 0.012), _b(cxm, blade_y - pitch * 0.33 - 0.06, zf), "LS_Chalk")
    for x in (x0 + pitch * 0.5, x1 - pitch * 0.5):
        mb.box(S(0.02, 0.12, 0.012), _b(x, blade_y - pitch * 0.33 - 0.12, zf), "LS_Chalk")
    mb.box(S(pitch * 0.9, 0.018, 0.012), _b(x0 + pitch * 1.0, blade_y + 0.4, zf), "LS_ChalkYellow")
    for s in (-1.0, 1.0):
        tip = _b(x0 + pitch * (1.0 + s * 0.45), blade_y + 0.4, zf)
        mb.cone(0.035, 0.08, tip, "LS_ChalkYellow", segments=8, rotation=aim_matrix(Vector((s, 0.0, 0.0))))
    for x in (x0 + pitch * 0.5, x0 + pitch * 1.5):
        mb.box(S(0.012, 0.22, 0.012), _b(x, blade_y + 0.4, zf), "LS_ChalkYellow")
    mb.torus(pitch * 0.55, 0.009, _b(x1 - pitch * 1.5, blade_y, zf), "LS_ChalkPink", rotation=RX,
             segments=16, rings=6, sweep=math.radians(250.0))
    mb.torus(0.55, 0.009, _b(cxm, blade_y + 0.95, zf), "LS_Chalk", rotation=RX, segments=18, rings=6,
             sweep=math.radians(180.0))
    fx = cxm
    fy = blade_y + 1.45
    mb.torus(0.08, 0.009, _b(fx, fy + 0.12, zf), "LS_Chalk", rotation=RX, segments=14, rings=6)
    mb.box(S(0.012, 0.22, 0.012), _b(fx, fy - 0.07, zf), "LS_Chalk")
    for s in (-1.0, 1.0):
        mb.box(S(0.012, 0.18, 0.012), _b(fx + s * 0.08, fy - 0.02, zf), "LS_Chalk",
               rotation=Matrix.Rotation(math.radians(s * 50.0), 3, "Y"))
        mb.box(S(0.012, 0.18, 0.012), _b(fx + s * 0.07, fy - 0.24, zf), "LS_Chalk",
               rotation=Matrix.Rotation(math.radians(-s * 35.0), 3, "Y"))
    tri = [(-0.16, -0.12), (0.16, -0.12), (0.0, 0.16)]
    mb.prism(tri, 0.012, _b(x1 - 0.25, cy + 1.2, zf), "LS_ChalkYellow", rotation=RX)
    mb.box(S(0.03, 0.12, 0.014), _b(x1 - 0.25, cy + 1.21, zf - 0.002), "LS_Board")
    mb.box(S(0.03, 0.03, 0.014), _b(x1 - 0.25, cy + 1.1, zf - 0.002), "LS_Board")
    return mb.build(col, bevel=0.01)


def build_lectern(col):
    mb = MeshBuilder("PRP_Lectern")
    x, z = 2.0, 6.3
    mb.box(S(0.9, 1.05, 0.5), _b(x, 0.525, z), "LS_WoodB")
    mb.box(S(0.96, 0.05, 0.56), _b(x, 0.03, z), "LS_WoodDark")
    top_rot = tilt(18.0)
    mb.box(S(1.0, 0.05, 0.6), _b(x, 1.12, z + 0.02), "LS_WoodA", rotation=top_rot)
    mb.box(S(1.0, 0.06, 0.04), _b(x, 1.03, z - 0.27), "LS_WoodA", rotation=top_rot)
    # 正面のエンブレム: 青い円盤に白い目と耳
    mb.cylinder(0.17, 0.02, _b(x, 0.72, z - 0.26), "GK_Blue", rotation=RX, segments=24)
    for s in (-1.0, 1.0):
        mb.cylinder(0.05, 0.012, _b(x + s * 0.065, 0.74, z - 0.275), "GK_White", rotation=RX, segments=14)
        mb.cylinder(0.022, 0.008, _b(x + s * 0.065, 0.74, z - 0.285), "GK_Navy", rotation=RX, segments=10)
        mb.cylinder(0.02, 0.1, _b(x + s * 0.2, 0.72, z - 0.25), "GK_Navy", rotation=RY, segments=10)
    mb.box(S(0.3, 0.012, 0.22), _b(x - 0.15, 1.15, z + 0.02), "LS_Paper", rotation=top_rot)
    mb.cylinder(0.04, 0.09, _b(x + 0.35, 1.2, z + 0.12), "LS_White", segments=14, radius2=0.035)
    return mb.build(col, bevel=0.01)


def build_desks(col):
    objects = []
    for i, x in enumerate(DESK_XS):
        mb = MeshBuilder(f"PRP_Desk_{i}")
        mb.box(S(1.1, 0.05, 0.6), _b(x, 0.70, DESK_Z), "LS_WoodA")
        mb.box(S(1.06, 0.02, 0.56), _b(x, 0.665, DESK_Z), "LS_WoodDark")
        for sx in (-1.0, 1.0):
            for sz in (-1.0, 1.0):
                mb.cylinder(0.022, 0.66, _b(x + sx * 0.5, 0.33, DESK_Z + sz * 0.25), "LS_Steel", segments=12)
        mb.box(S(1.0, 0.03, 0.03), _b(x, 0.2, DESK_Z + 0.25), "LS_Steel")
        mb.box(S(1.0, 0.03, 0.03), _b(x, 0.2, DESK_Z - 0.25), "LS_Steel")
        # ノート（開いた見開き）: 生徒側（Godot -Z）に寄せる
        ny = 0.73
        nz = DESK_Z - 0.12
        for s in (-1.0, 1.0):
            yaw = Matrix.Rotation(math.radians(s * 4.0), 3, "Z")
            mb.box(S(0.22, 0.012, 0.3), _b(x + s * 0.115, ny, nz), "LS_Paper", rotation=yaw)
        mb.box(S(0.46, 0.006, 0.31), _b(x, 0.724, nz), "LS_Cloth")
        for k in range(5):
            mb.box(S(0.17, 0.004, 0.006), _b(x + 0.12, 0.74, nz - 0.1 + k * 0.045), "LS_DarkSteel")
        if i != 0:
            mb.cylinder(0.009, 0.2, _b(x + 0.33, 0.74, DESK_Z + 0.1), "GK_Yellow", rotation=RY, segments=6)
        if i == 2:
            mb.box(S(0.26, 0.03, 0.1), _b(x - 0.3, 0.74, DESK_Z + 0.12), "LS_WoodDark")
            for k in range(3):
                mb.cylinder(0.045, 0.01, _b(x - 0.38 + k * 0.08, 0.8, DESK_Z + 0.12), "LS_Steel", rotation=RY,
                            segments=16)
        objects.append(mb.build(col, bevel=0.008))
        sb = MeshBuilder(f"PRP_Stool_{i}")
        sb.cylinder(0.23, 0.05, _b(x, STOOL_TOP - 0.025, STOOL_Z), "LS_WoodB", segments=24)
        sb.torus(0.21, 0.02, _b(x, STOOL_TOP - 0.06, STOOL_Z), "LS_Steel", segments=24, rings=8)
        for k in range(4):
            a = math.tau * (k + 0.5) / 4.0
            top = _b(x + math.cos(a) * 0.17, STOOL_TOP - 0.05, STOOL_Z + math.sin(a) * 0.17)
            bottom = _b(x + math.cos(a) * 0.21, 0.0, STOOL_Z + math.sin(a) * 0.21)
            sb.cylinder_between(bottom, top, 0.018, "LS_Steel", segments=10)
        sb.torus(0.19, 0.012, _b(x, 0.15, STOOL_Z), "LS_Steel", segments=20, rings=6)
        objects.append(sb.build(col))
    return objects


def build_exhibit_table(col):
    mb = MeshBuilder("PRP_ExhibitTable")
    x, z = -3.9, 5.4
    w, d, h = 5.6, 1.5, 0.9
    mb.box(S(w, 0.06, d), _b(x, h - 0.03, z), "LS_WoodDark")
    mb.box(S(w + 0.04, 0.02, d + 0.04), _b(x, h + 0.01, z), "LS_Cloth")
    mb.box(S(w + 0.04, h - 0.1, 0.02), _b(x, (h - 0.1) * 0.5 + 0.04, z - d * 0.5 - 0.01), "LS_Cloth")
    for sx in (-1.0, 1.0):
        mb.box(S(0.02, h - 0.1, d), _b(x + sx * (w * 0.5 + 0.01), (h - 0.1) * 0.5 + 0.04, z), "LS_Cloth")
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            mb.box(S(0.06, h - 0.06, 0.06), _b(x + sx * (w * 0.5 - 0.1), (h - 0.06) * 0.5, z + sz * (d * 0.5 - 0.1)),
                   "LS_Steel")
    lean = tilt(-15.0)
    mb.box(S(0.5, 0.26, 0.02), _b(x + 2.3, h + 0.16, z - 0.5), "LS_White", rotation=lean)
    mb.box(S(0.42, 0.05, 0.022), _b(x + 2.3, h + 0.22, z - 0.515), "GK_Navy", rotation=lean)
    mb.box(S(0.3, 0.025, 0.022), _b(x + 2.3, h + 0.12, z - 0.49), "LS_DarkSteel", rotation=lean)
    mb.box(S(0.5, 0.02, 0.18), _b(x + 2.3, h + 0.02, z - 0.44), "LS_DarkSteel")
    return mb.build(col, bevel=0.008)


def build_bookshelf(col):
    mb = MeshBuilder("PRP_Bookshelf")
    x, z = -5.6, 8.8
    w, d, h = 2.0, 0.42, 2.2
    for sx in (-1.0, 1.0):
        mb.box(S(0.05, h, d), _b(x + sx * (w * 0.5 - 0.025), h * 0.5, z), "LS_WoodC")
    mb.box(S(w, h, 0.03), _b(x, h * 0.5, z + d * 0.5 - 0.015), "LS_WoodDark")
    mb.box(S(w, 0.05, d), _b(x, h - 0.025, z), "LS_WoodC")
    rng = random.Random(11)
    for level in range(3):
        y = 0.08 + level * 0.7
        mb.box(S(w - 0.1, 0.04, d - 0.03), _b(x, y, z), "LS_WoodC")
        bx = x - w * 0.5 + 0.12
        while bx < x + w * 0.5 - 0.2:
            bw = rng.uniform(0.05, 0.09)
            bh = rng.uniform(0.28, 0.36)
            color = rng.choice(("LS_BinderA", "LS_BinderB", "LS_BinderC", "LS_BinderD", "LS_White"))
            lean = rng.uniform(-3.0, 3.0) if rng.random() < 0.2 else 0.0
            rot = Matrix.Rotation(math.radians(lean), 3, "Y")
            mb.box(S(bw, bh, d - 0.14), _b(bx + bw * 0.5, y + 0.02 + bh * 0.5, z - 0.03), color, rotation=rot)
            mb.box(S(bw + 0.004, 0.05, 0.01), _b(bx + bw * 0.5, y + 0.02 + bh * 0.72, z - d * 0.5 + 0.045), "LS_Paper",
                   rotation=rot)
            bx += bw + 0.012
            if rng.random() < 0.15:
                bx += 0.08
        if level == 1:
            mb.box(S(0.3, 0.12, 0.22), _b(x + w * 0.5 - 0.3, y + 0.08, z), "LS_Paper",
                   rotation=Matrix.Rotation(math.radians(6.0), 3, "Y"))
    return mb.build(col, bevel=0.006)


def build_poster_easel(col):
    mb = MeshBuilder("PRP_PosterEasel")
    x, z = 4.9, 8.2
    lean = tilt(-12.0)
    for sx in (-1.0, 1.0):
        mb.cylinder_between(_b(x + sx * 0.4, 0.0, z + 0.15), _b(x + sx * 0.22, 1.75, z - 0.2), 0.02, "LS_WoodA",
                            segments=10)
    mb.cylinder_between(_b(x, 0.0, z - 0.45), _b(x, 1.3, z - 0.02), 0.02, "LS_WoodA", segments=10)
    mb.box(S(0.7, 0.03, 0.03), _b(x, 0.85, z + 0.0), "LS_WoodA", rotation=lean)
    mb.box(S(0.9, 1.2, 0.03), _b(x, 1.35, z - 0.08), "LS_White", rotation=lean)
    mb.box(S(0.9, 0.16, 0.034), _b(x, 1.88, z - 0.19), "LS_Red", rotation=lean)
    tri = [(-0.3, -0.22), (0.3, -0.22), (0.0, 0.3)]
    mb.prism(tri, 0.02, _b(x, 1.42, z - 0.1), "LS_HazardYellow", rotation=lean @ RX)
    mb.box(S(0.06, 0.22, 0.024), _b(x, 1.45, z - 0.11), "GK_Black", rotation=lean)
    mb.box(S(0.06, 0.06, 0.024), _b(x, 1.27, z - 0.07), "GK_Black", rotation=lean)
    for k in range(3):
        mb.box(S(0.6 - k * 0.12, 0.03, 0.024), _b(x - k * 0.06, 1.1 - k * 0.09, z - 0.035 + k * 0.02), "GK_Black",
               rotation=lean)
    return mb.build(col)


def build_misc(col):
    objects = []
    # カラーコーン ×3（レールの周り。Godot: レール x -4.4, z -1.3〜4.0）
    for k, (x, z) in enumerate(((-3.4, -0.9), (-5.4, -0.9), (-3.4, 3.9))):
        mb = MeshBuilder(f"PRP_Cone_{k}")
        mb.box(S(0.42, 0.03, 0.42), _b(x, 0.015, z), "GK_Black")
        mb.cone(0.17, 0.55, _b(x, 0.3, z), "LS_Cone", segments=20)
        mb.cylinder(0.12, 0.08, _b(x, 0.36, z), "LS_White", segments=20, radius2=0.1)
        objects.append(mb.build(col))
    # A 型の看板（黄色、黒帯）
    mb = MeshBuilder("PRP_SignPractice")
    x, z = -5.9, 1.6
    for s in (-1.0, 1.0):
        rot = tilt(s * 14.0)
        mb.box(S(0.55, 0.75, 0.03), _b(x, 0.38, z + s * 0.1), "LS_HazardYellow", rotation=rot)
        mb.box(S(0.5, 0.1, 0.034), _b(x, 0.6, z + s * 0.12), "LS_HazardBlack", rotation=rot)
        mb.box(S(0.4, 0.05, 0.034), _b(x, 0.42, z + s * 0.13), "LS_HazardBlack", rotation=rot)
    mb.box(S(0.6, 0.03, 0.26), _b(x, 0.76, z), "LS_HazardYellow")
    objects.append(mb.build(col))
    # 消火器（本棚の脇）
    mb = MeshBuilder("PRP_Extinguisher")
    x, z = -4.3, 9.0
    mb.cylinder(0.09, 0.55, _b(x, 0.3, z), "LS_Red", segments=18)
    mb.sphere(0.09, _b(x, 0.575, z), "LS_Red", scale=(1, 1, 0.5), segments=18, rings=8)
    mb.cylinder(0.11, 0.04, _b(x, 0.02, z), "GK_Black", segments=18)
    mb.cylinder(0.025, 0.12, _b(x, 0.66, z), "LS_DarkSteel", segments=12)
    mb.box(S(0.06, 0.03, 0.18), _b(x, 0.72, z - 0.06), "LS_DarkSteel")
    mb.cylinder_between(_b(x + 0.03, 0.66, z - 0.03), _b(x + 0.11, 0.3, z - 0.1), 0.012, "GK_Black", segments=8)
    mb.cylinder_between(_b(x + 0.11, 0.3, z - 0.1), _b(x + 0.08, 0.12, z - 0.14), 0.012, "GK_Black", segments=8)
    objects.append(mb.build(col))
    # 工具箱（模型の台の脇、ふたが少し開いている）
    mb = MeshBuilder("PRP_Toolbox")
    x, z = -6.4, 6.8
    mb.box(S(0.5, 0.22, 0.26), _b(x, 0.11, z), "LS_Red")
    mb.box(S(0.5, 0.06, 0.26), _b(x, 0.27, z + 0.02), "LS_Red", rotation=tilt(25.0))
    mb.box(S(0.2, 0.03, 0.03), _b(x, 0.31, z - 0.04), "GK_Black", rotation=tilt(25.0))
    mb.cylinder(0.03, 0.2, _b(x - 0.12, 0.24, z), "LS_Steel", rotation=RY, segments=10)
    mb.cylinder(0.022, 0.26, _b(x + 0.1, 0.25, z - 0.02), "LS_HazardYellow", rotation=RY, segments=8)
    objects.append(mb.build(col, bevel=0.006))
    # ごみ箱（教壇の脇）
    mb = MeshBuilder("PRP_Bin")
    x, z = 4.6, 5.0
    mb.cylinder(0.2, 0.5, _b(x, 0.25, z), "LS_Steel", segments=24, radius2=0.17)
    mb.torus(0.2, 0.015, _b(x, 0.5, z), "LS_DarkSteel", segments=24, rings=8)
    mb.box(S(0.08, 0.12, 0.08), _b(x + 0.04, 0.53, z), "LS_Paper", rotation=Matrix.Rotation(math.radians(30.0), 3, "Z"))
    objects.append(mb.build(col))
    # バケツ（練習生の脇）
    mb = MeshBuilder("PRP_Bucket")
    x, z = -6.3, -0.2
    mb.cylinder(0.16, 0.3, _b(x, 0.15, z), "GK_Blue", segments=20, radius2=0.13)
    mb.cylinder(0.14, 0.01, _b(x, 0.29, z), "LS_BinderA", segments=20)
    mb.torus(0.165, 0.012, _b(x, 0.3, z), "LS_Steel", rotation=RY, segments=20, rings=6, sweep=math.radians(180.0))
    objects.append(mb.build(col))
    return objects


def build_all_props(col):
    objects = [build_platform(col), build_blackboard(col), build_lectern(col), build_exhibit_table(col),
               build_bookshelf(col), build_poster_easel(col)]
    objects += build_desks(col)
    objects += build_misc(col)
    return objects

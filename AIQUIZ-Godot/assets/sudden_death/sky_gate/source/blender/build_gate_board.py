"""スカイゲートの問題のボード（gate_board）を作る。仕様：docs/sudden_death_v2/skygate_build_plan.md 4.6節と sky_gate.md。

ライブの Blender（Higgsfield の Blender 連携）で実行する。ヘッドレスで代替しない（AGENTS.md）。
    import runpy, sys
    sys.argv = ["blender", "--"]      # "--no-export" で書き出さない、"--no-render" で確認レンダーを出さない、"--no-save" で保存しない
    runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/sudden_death/sky_gate/source/blender/build_gate_board.py", run_name="__main__")

座標：Blender の Z が上、メートル。原点＝ボード（17 × 12.2 m）の中心 × 紙のパネルの面。+X＝右、+Y＝奥（問題文の看板の側）。
問題文は奥の 17 × 6 m の看板 QuestionSign（2026-10-19 に帯 QuestionStrip から替えた）。2026-10-19 夜：ユーザーの指示で
選択肢のパネルを大きくし、ボードの横幅を看板と同じ 17 m にそろえた（看板とパネルで 1 つの四角になる。全体は約 17 × 15.8 m）。ドローンは 6 機（看板の 4 隅とボードの手前の角）。
Godot では (x, z, -y)：+X 右、+Y 上、−Z 奥。
文字は入れない（Godot の Label3D で書く）。色は頂点色（材質 GB_Body を 1 つにして描く回数を減らす）。
"""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent
ASSET = SOURCE.parent
PREVIEWS = SOURCE / "previews"
GLB = ASSET / "gate_board.glb"
LAYOUT = ASSET / "gate_board_layout.json"
REPORT = SOURCE / "build_report.json"
BLEND = HERE / "gate_board.blend"

# ---------------------------------------------------------------- 寸法（m）
BOARD_W = 17.0          # 横（x）。看板と同じ幅（2026-10-19 夜：14 → 17、パネルを大きく）
BOARD_D = 12.2          # 奥行き（y）。横と同じ割合で広げた（10 → 12.2）
FRAME_W = 0.46          # 外枠の幅
FRAME_H = 0.34          # 外枠の高さ（紙の面をはさんで上下に半分ずつ）
INNER_W = 0.30          # 中の仕切りの幅
INNER_H = 0.26
STRIP_D = 1.80          # 前の版の問題文の帯の奥行き（今は看板の下。枠の仕切りの位置を決める）
STRIP_T = 0.10
# 問題文の看板（2026-10-19、帯から替えた：ボードより大きな看板。遠くから読めるように。ドローン 2 機を足して吊る）
SIGN_W = BOARD_W        # 横（ボードと同じ 17 m。看板とパネルで 1 つの四角）
SIGN_D = 6.0            # 奥行き
SIGN_BORDER = 0.36      # 紺の縁の幅
SIGN_T = 0.16           # 厚さ
DRONE_COUNT = 6         # 0・1＝看板の手前の角、2・3＝ボードの手前の角、4・5＝看板の奥の角
PAPER_OVERLAP = 0.06    # 紙を枠の下へ差し込む分
PAPER_SAG = 0.05        # 紙の真ん中のたわみ
DRONE_OFFSET = Vector((0.75, 0.62, 3.2))   # 角の吊り金具からドローンの中心まで（外へ・外へ・上へ）
DRONE_HOOK_Z = -0.42    # ドローンの中心からケーブルのフックまで
ARM_R = 1.0             # ドローンの腕の長さ（中心からモーターまで）
ROTOR_R = 0.55          # ローターの半径

INNER_X = BOARD_W / 2 - FRAME_W           # 6.54
INNER_Y = BOARD_D / 2 - FRAME_W           # 4.54
STRIP_Y0 = INNER_Y - STRIP_D              # 帯の手前の端 2.74
DIV_Y0 = STRIP_Y0 - INNER_W               # 仕切りの手前の端 2.44
MID_Y = (DIV_Y0 + -INNER_Y) / 2           # 前後のパネルの間の仕切りの中心 -1.05
SIGN_Y0 = STRIP_Y0 - 0.10                 # 看板の手前の端 2.64（帯のあった所から始まり、ボードの奥へはみ出す）
SIGN_Y1 = SIGN_Y0 + SIGN_D                # 看板の奥の端 8.64
SIGN_Z0 = FRAME_H / 2 + 0.04              # 看板の下面（枠の上）
SIGN_TOP = SIGN_Z0 + SIGN_T               # 看板の上面 0.37
SIGN_FACE_W = SIGN_W - 2 * SIGN_BORDER    # 白い面 16.28
SIGN_FACE_D = SIGN_D - 2 * SIGN_BORDER    # 5.28
PANEL_W = INNER_X - INNER_W / 2           # 6.39
PANEL_D = (DIV_Y0 - -INNER_Y - INNER_W) / 2   # 3.34

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
DO_RENDER = "--no-render" not in ARGS
DO_SAVE = "--no-save" not in ARGS


def srgb(hex_str, a=1.0):
    """'#RRGGBB'（sRGB）を Blender の線形の色へ。"""
    h = hex_str.lstrip("#")
    out = []
    for i in range(3):
        c = int(h[i * 2:i * 2 + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return Vector((out[0], out[1], out[2], a))


# 色（sRGB）。絵コンテ（panel_04〜06）に合わせた
NAVY = srgb("#1E2C66")
NAVY_LIGHT = srgb("#2C3F8C")
METAL = srgb("#B9BFC9")
PIN = srgb("#E6EAF0")
CABLE = srgb("#2A2E35")
WHITE = srgb("#F4F5F7")
ORANGE = srgb("#FF7A1A")
DARK = srgb("#2F333A")
LENS = srgb("#0E1216")
LED_GREEN = srgb("#38D86A")
LED_RED = srgb("#FF4040")
PAPER = {  # パネルの番号 → 名前と色（0＝奥の左・1＝奥の右・2＝手前の左・3＝手前の右）
    0: ("Mint", "#8FE3B5"),
    1: ("Sky", "#8CCDF5"),
    2: ("Lemon", "#FBE878"),
    3: ("Pink", "#F9A9C8"),
}


def panel_center(index):
    col = index % 2
    row = index // 2
    x = (-1 if col == 0 else 1) * (INNER_W / 2 + PANEL_W / 2)
    y = (MID_Y + INNER_W / 2 + PANEL_D / 2) if row == 0 else (MID_Y - INNER_W / 2 - PANEL_D / 2)
    return Vector((x, y, 0.0))


def corner_attach(index):
    """ケーブルを吊る角の金具。2・3＝ボードの手前の角（枠の上）、0・1＝看板の手前の角、4・5＝看板の奥の角（看板の縁の上）。"""
    sx = -1 if index % 2 == 0 else 1
    if index in (2, 3):
        return Vector((sx * (BOARD_W / 2 - FRAME_W / 2), -(BOARD_D / 2 - FRAME_W / 2), FRAME_H / 2 + 0.16))
    y = SIGN_Y0 + SIGN_BORDER / 2 if index in (0, 1) else SIGN_Y1 - SIGN_BORDER / 2
    return Vector((sx * (SIGN_W / 2 - SIGN_BORDER / 2), y, SIGN_TOP + 0.16))


def drone_center(index):
    sx = -1 if index % 2 == 0 else 1
    sy = {0: 0, 1: 0, 2: -1, 3: -1, 4: 1, 5: 1}[index]
    a = corner_attach(index)
    return Vector((a.x + sx * DRONE_OFFSET.x, a.y + sy * DRONE_OFFSET.y, a.z + DRONE_OFFSET.z))


def godot(v):
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


# ---------------------------------------------------------------- メッシュの道具

class Builder:
    """1 つのオブジェクトの bmesh。部品ごとに頂点色（線形）を塗る。"""

    def __init__(self, name, material, smooth=True):
        self.name = name
        self.material = material
        self.smooth = smooth
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = self.bm.loops.layers.float_color.new("Col")

    def _paint(self, start, color):
        self.bm.faces.ensure_lookup_table()
        for i in range(start, len(self.bm.faces)):
            for loop in self.bm.faces[i].loops:
                loop[self.col] = color

    def add_bm(self, other_bm, matrix, color, smooth=None):
        sm = self.smooth if smooth is None else smooth
        for f in other_bm.faces:
            f.smooth = sm
        if matrix is not None:
            bmesh.ops.transform(other_bm, matrix=matrix, verts=other_bm.verts)
        me = bpy.data.meshes.new("_tmp")
        other_bm.to_mesh(me)
        other_bm.free()
        start = len(self.bm.faces)
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        self._paint(start, color)

    def box(self, matrix, size, color, bevel=0.0, segs=2, smooth=None):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segs, affect="EDGES", profile=0.5)
        self.add_bm(bm, matrix, color, smooth=(bevel > 0) if smooth is None else smooth)

    def cylinder(self, matrix, r1, r2, depth, color, segs=16, caps=True, smooth=True):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth)
        self.add_bm(bm, matrix, color, smooth=smooth)

    def sphere(self, matrix, r, color, segs=16, rings=8, hemisphere=False):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
        if hemisphere:
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-5], context="VERTS")
        self.add_bm(bm, matrix, color, smooth=True)

    def torus(self, matrix, major, minor, color, segs=16, sides=6):
        bm = bmesh.new()
        rows = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            c = Vector((math.cos(a) * major, math.sin(a) * major, 0))
            d = Vector((math.cos(a), math.sin(a), 0))
            rows.append([bm.verts.new(c + d * math.cos(2 * math.pi * j / sides) * minor + Vector((0, 0, math.sin(2 * math.pi * j / sides) * minor)))
                         for j in range(sides)])
        for i in range(segs):
            for j in range(sides):
                i2, j2 = (i + 1) % segs, (j + 1) % sides
                bm.faces.new((rows[i][j], rows[i2][j], rows[i2][j2], rows[i][j2]))
        self.add_bm(bm, matrix, color, smooth=True)

    def disc(self, matrix, r, color, segs=24):
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=True, cap_tris=False, segments=segs, radius=r)
        self.add_bm(bm, matrix, color, smooth=False)

    def finish(self, collection, name=None, location=None):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        if location is not None:
            bmesh.ops.translate(self.bm, vec=-location, verts=self.bm.verts)
        me = bpy.data.meshes.new(name or self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        me.materials.append(MAT[self.material])
        obj = bpy.data.objects.new(name or self.name, me)
        collection.objects.link(obj)
        if location is not None:
            obj.location = location
        return obj


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation(Vector((x, y, z)))


def R(angle, axis):
    return Matrix.Rotation(angle, 4, axis)


# ---------------------------------------------------------------- 材質

MAT = {}


def material(name, color, rough=0.5, metal=0.0, alpha=1.0, vertex_color=False, double=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (-300, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = tuple(color)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Alpha"].default_value = alpha
    if vertex_color:
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        vc.location = (-600, 0)
        nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha < 1.0:
        for attr, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(mat, attr, value)
            except (AttributeError, TypeError):
                pass
    mat.use_backface_culling = not double
    MAT[name] = mat
    return mat


def build_materials():
    material("GB_Body", (1, 1, 1, 1), 0.48, vertex_color=True)
    material("GB_Strip", tuple(srgb("#FAFBFC")), 0.62)
    for index, (name, hex_str) in PAPER.items():
        material("GB_Paper_" + name, tuple(srgb(hex_str)), 0.75, alpha=0.86, double=True)
    material("GB_RotorBlur", tuple(srgb("#D8DDE4")), 0.4, alpha=0.22, double=True)


# ---------------------------------------------------------------- ボード

def beam(b, x0, x1, y0, y1, h, color, bevel=0.06):
    b.box(T((x0 + x1) / 2, (y0 + y1) / 2, 0.0), ((x1 - x0), (y1 - y0), h), color, bevel=bevel, segs=2)


def junction_plate(b, x, y, top):
    """仕切りの交わるところの丸い押さえ板とボルト（上と下）。"""
    for sign in (1, -1):
        z = sign * (top + 0.02)
        b.cylinder(T(x, y, z), 0.25, 0.25, 0.04, NAVY_LIGHT, segs=20)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            b.sphere(T(x + math.cos(a) * 0.15, y + math.sin(a) * 0.15, z + sign * 0.02), 0.035, METAL, segs=8, rings=4, hemisphere=False)


def build_frame(col):
    b = Builder("Frame", "GB_Body")
    hx, hy = BOARD_W / 2, BOARD_D / 2
    # 外枠（奥・手前は端まで、左右はその間）
    beam(b, -hx, hx, INNER_Y, hy, FRAME_H, NAVY, 0.08)
    beam(b, -hx, hx, -hy, -INNER_Y, FRAME_H, NAVY, 0.08)
    beam(b, -hx, -INNER_X, -INNER_Y - 0.02, INNER_Y + 0.02, FRAME_H, NAVY, 0.08)
    beam(b, INNER_X, hx, -INNER_Y - 0.02, INNER_Y + 0.02, FRAME_H, NAVY, 0.08)
    # 外枠の上と下の細い縁（明るい紺）
    for sign in (1, -1):
        z = sign * (FRAME_H / 2 + 0.008)
        for (x0, x1, y0, y1) in ((-hx + 0.1, hx - 0.1, hy - 0.12, hy - 0.06), (-hx + 0.1, hx - 0.1, -hy + 0.06, -hy + 0.12),
                                 (-hx + 0.06, -hx + 0.12, -hy + 0.1, hy - 0.1), (hx - 0.12, hx - 0.06, -hy + 0.1, hy - 0.1)):
            b.box(T((x0 + x1) / 2, (y0 + y1) / 2, z), (x1 - x0, y1 - y0, 0.016), NAVY_LIGHT)
    # 帯とパネルの間の仕切り、パネルの十字。帯のあった所は紺の板でふさぐ（上に看板が載る）
    beam(b, -INNER_X - 0.02, INNER_X + 0.02, DIV_Y0, STRIP_Y0, INNER_H, NAVY)
    beam(b, -INNER_X - 0.02, INNER_X + 0.02, STRIP_Y0 - 0.02, INNER_Y + 0.02, INNER_H * 0.5, NAVY)
    beam(b, -INNER_X - 0.02, INNER_X + 0.02, MID_Y - INNER_W / 2, MID_Y + INNER_W / 2, INNER_H, NAVY)
    beam(b, -INNER_W / 2, INNER_W / 2, -INNER_Y - 0.02, DIV_Y0 + 0.02, INNER_H, NAVY)
    # 押さえ板
    top = INNER_H / 2
    for (x, y) in ((0.0, MID_Y), (0.0, DIV_Y0 + INNER_W / 2), (0.0, -INNER_Y - 0.02),
                   (-INNER_X, MID_Y), (INNER_X, MID_Y), (-INNER_X, DIV_Y0 + INNER_W / 2), (INNER_X, DIV_Y0 + INNER_W / 2)):
        junction_plate(b, x, y, top if abs(abs(x) - INNER_X) > 0.01 and y > -INNER_Y else FRAME_H / 2 - 0.02)
    # 角の金具（ボードの手前の角）：大きめの角の板、吊り金具（目のついたボルト）と枷（シャックル）。奥の角は看板が吊る
    for i in (2, 3):
        a = corner_attach(i)
        for sign in (1, -1):
            b.box(T(a.x, a.y, sign * (FRAME_H / 2 + 0.03)), (0.62, 0.62, 0.06), NAVY_LIGHT, bevel=0.025, segs=2)
            for k in range(4):
                ang = math.pi / 4 + k * math.pi / 2
                b.sphere(T(a.x + math.cos(ang) * 0.21, a.y + math.sin(ang) * 0.21, sign * (FRAME_H / 2 + 0.07)), 0.035, METAL, segs=8, rings=4)
        b.cylinder(T(a.x, a.y, FRAME_H / 2 + 0.09), 0.07, 0.07, 0.06, METAL, segs=12)
        b.torus(T(a.x, a.y, a.z - 0.02) @ R(math.pi / 2, "X"), 0.075, 0.022, METAL, segs=14, sides=6)
    # 紙を留めるピン（パネルのふちに沿って枠の上）
    for i in range(4):
        c = panel_center(i)
        x0, x1 = c.x - PANEL_W / 2 - 0.07, c.x + PANEL_W / 2 + 0.07
        y0, y1 = c.y - PANEL_D / 2 - 0.07, c.y + PANEL_D / 2 + 0.07
        n_x = 5
        n_y = 3
        pts = []
        for k in range(n_x):
            t = (k + 0.5) / n_x
            pts += [(x0 + (x1 - x0) * t, y0), (x0 + (x1 - x0) * t, y1)]
        for k in range(n_y):
            t = (k + 0.5) / n_y
            pts += [(x0, y0 + (y1 - y0) * t), (x1, y0 + (y1 - y0) * t)]
        for (x, y) in pts:
            outer = abs(x) > INNER_X - 0.01 or abs(y) > INNER_Y - 0.01
            z = (FRAME_H if outer else INNER_H) / 2
            b.cylinder(T(x, y, z + 0.012), 0.045, 0.045, 0.024, PIN, segs=10)
    return b.finish(col)


def build_sign_frame(col):
    """看板の紺の台と縁・オレンジの線・下の骨・角の吊り金具（GB_Body の頂点色）。白い面は QuestionSign。"""
    b = Builder("SignFrame", "GB_Body")
    cy = (SIGN_Y0 + SIGN_Y1) / 2
    zc = SIGN_Z0 + SIGN_T / 2
    # 台（縁を含む全体）と、縁の内側のオレンジの細い線
    b.box(T(0.0, cy, zc), (SIGN_W, SIGN_D, SIGN_T), NAVY, bevel=0.06, segs=2)
    for y in (SIGN_Y0 + SIGN_BORDER - 0.08, SIGN_Y1 - SIGN_BORDER + 0.08):
        b.box(T(0.0, y, SIGN_TOP + 0.004), (SIGN_FACE_W + 0.16, 0.06, 0.012), ORANGE)
    for sx in (-1, 1):
        b.box(T(sx * (SIGN_FACE_W / 2 + 0.08), cy, SIGN_TOP + 0.004), (0.06, SIGN_FACE_D + 0.16, 0.012), ORANGE)
    # 下の骨（下から見上げたとき）：横に 3 本、縦に 4 本
    for k in range(3):
        y = SIGN_Y0 + 0.6 + k * (SIGN_D - 1.2) / 2
        b.box(T(0.0, y, SIGN_Z0 - 0.09), (SIGN_W - 0.6, 0.16, 0.18), NAVY_LIGHT, bevel=0.03, segs=1)
    for k in range(4):
        x = -SIGN_W / 2 + 1.2 + k * (SIGN_W - 2.4) / 3
        b.box(T(x, cy, SIGN_Z0 - 0.07), (0.14, SIGN_D - 0.5, 0.14), NAVY_LIGHT, bevel=0.03, segs=1)
    # 看板の角の吊り金具（目のついたボルトと角の板）
    for i in (0, 1, 4, 5):
        a = corner_attach(i)
        b.box(T(a.x, a.y, SIGN_TOP + 0.03), (0.62, 0.62, 0.06), NAVY_LIGHT, bevel=0.025, segs=2)
        for k in range(4):
            ang = math.pi / 4 + k * math.pi / 2
            b.sphere(T(a.x + math.cos(ang) * 0.21, a.y + math.sin(ang) * 0.21, SIGN_TOP + 0.07), 0.035, METAL, segs=8, rings=4)
        b.cylinder(T(a.x, a.y, SIGN_TOP + 0.09), 0.07, 0.07, 0.06, METAL, segs=12)
        b.torus(T(a.x, a.y, a.z - 0.02) @ R(math.pi / 2, "X"), 0.075, 0.022, METAL, segs=14, sides=6)
    return b.finish(col)


def build_sign(col):
    """問題文の看板の白い面（材質 GB_Strip。Godot が文字を Label3D で書き、問題が変わると一瞬光らせる）。"""
    cy = (SIGN_Y0 + SIGN_Y1) / 2
    b = Builder("QuestionSign", "GB_Body", smooth=False)
    b.box(T(0.0, cy, SIGN_TOP + 0.003), (SIGN_FACE_W, SIGN_FACE_D, 0.03), WHITE, bevel=0.012, segs=1)
    me_obj = b.finish(col, location=Vector((0.0, cy, SIGN_TOP + 0.003)))
    me_obj.data.materials.clear()
    me_obj.data.materials.append(MAT["GB_Strip"])
    return me_obj


def build_panel(col, index):
    """紙のパネル：少したわんだ格子。UV の 0〜1 が見える範囲（ふちは枠の下へ差し込む）。原点＝パネルの中心。"""
    name, _hex = PAPER[index]
    c = panel_center(index)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    nu, nv = 25, 15
    w = PANEL_W + 2 * PAPER_OVERLAP
    d = PANEL_D + 2 * PAPER_OVERLAP
    verts = []
    uvs = []
    for i in range(nu):
        row = []
        urow = []
        for j in range(nv):
            x = -w / 2 + w * i / (nu - 1)
            y = -d / 2 + d * j / (nv - 1)
            fx = max(0.0, 1.0 - (2 * x / PANEL_W) ** 2)
            fy = max(0.0, 1.0 - (2 * y / PANEL_D) ** 2)
            z = -PAPER_SAG * fx * fy
            row.append(bm.verts.new((x, y, z)))
            urow.append((x / PANEL_W + 0.5, y / PANEL_D + 0.5))
        verts.append(row)
        uvs.append(urow)
    for i in range(nu - 1):
        for j in range(nv - 1):
            f = bm.faces.new((verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1]))
            f.smooth = True
            for loop, (a, bb) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                loop[uv_layer].uv = uvs[a][bb]
    me = bpy.data.meshes.new("Panel_%d" % index)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MAT["GB_Paper_" + name])
    obj = bpy.data.objects.new("Panel_%d" % index, me)
    col.objects.link(obj)
    obj.location = c
    return obj


# ---------------------------------------------------------------- ドローン

def build_drone(col, index):
    """白い体・オレンジの腕・4 つのローター。原点＝ドローンの中心。前（+Y）にカメラ。"""
    b = Builder("Drone_%d" % index, "GB_Body")
    # 体：丸い箱・上のドーム・オレンジの帯・下のふた
    b.box(T(0, 0, 0), (0.84, 0.96, 0.32), WHITE, bevel=0.12, segs=3)
    b.box(T(0, 0, -0.01), (0.88, 1.00, 0.06), ORANGE, bevel=0.03, segs=2)
    b.sphere(T(0, -0.04, 0.12) @ Matrix.Diagonal((0.36, 0.42, 0.18, 1.0)), 1.0, WHITE, segs=20, rings=10, hemisphere=True)
    b.box(T(0, 0, -0.17), (0.56, 0.64, 0.06), DARK, bevel=0.025, segs=2)
    # 前のカメラ（丸い目）と灯
    b.sphere(T(0, 0.47, -0.05), 0.105, DARK, segs=14, rings=8)
    b.sphere(T(0, 0.535, -0.05), 0.07, LENS, segs=12, rings=6)
    b.sphere(T(0.30, 0.44, 0.06), 0.035, LED_GREEN, segs=8, rings=4)
    b.sphere(T(-0.30, 0.44, 0.06), 0.035, LED_RED, segs=8, rings=4)
    # 腕・モーター（ローターは別のオブジェクト）
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        mid = (0.32 + ARM_R) / 2
        b.box(T(math.cos(a) * mid, math.sin(a) * mid, 0.02) @ R(a, "Z"), (ARM_R - 0.32 + 0.1, 0.13, 0.10), ORANGE, bevel=0.035, segs=2)
        mx, my = math.cos(a) * ARM_R, math.sin(a) * ARM_R
        b.cylinder(T(mx, my, 0.06), 0.13, 0.12, 0.22, WHITE, segs=16)
        b.cylinder(T(mx, my, 0.185), 0.125, 0.11, 0.04, ORANGE, segs=16)
        b.cylinder(T(mx, my, -0.07), 0.08, 0.05, 0.06, DARK, segs=12)
    # 脚（2 本のそり）
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.cylinder(T(sx * 0.26, sy * 0.26, -0.29) @ R(sx * 0.35, "Y"), 0.025, 0.025, 0.22, DARK, segs=8)
        b.box(T(sx * 0.31, 0, -0.40), (0.05, 0.78, 0.05), DARK, bevel=0.02, segs=1)
    # ケーブルのウインチとフック（下の真ん中）
    b.cylinder(T(0, 0, -0.27), 0.09, 0.09, 0.08, METAL, segs=12)
    b.torus(T(0, 0, DRONE_HOOK_Z + 0.06) @ R(math.pi / 2, "X"), 0.05, 0.016, METAL, segs=12, sides=6)
    center = drone_center(index)
    obj = b.finish(col)
    obj.location = center
    return obj


def build_rotor(col, index, k):
    """2 枚羽根のローター。原点＝モーターの軸の上。Godot の +Y まわりに回す。"""
    b = Builder("Rotor_%d_%d" % (index, k), "GB_Body")
    b.cylinder(T(0, 0, 0.02), 0.055, 0.045, 0.05, DARK, segs=12)
    b.sphere(T(0, 0, 0.05), 0.035, ORANGE, segs=10, rings=5, hemisphere=True)
    for side in (0, math.pi):
        rot = R(side + k * 0.7, "Z")
        b.box(rot @ T(0.28, 0, 0.025) @ R(math.radians(10), "X"), (0.50, 0.075, 0.014), DARK, bevel=0.006, segs=1, smooth=False)
        b.box(rot @ T(0.50, 0, 0.026) @ R(math.radians(10), "X"), (0.07, 0.078, 0.016), ORANGE, bevel=0.006, segs=1, smooth=False)
    return b.finish(col)


def rotor_offsets():
    return [Vector((math.cos(math.pi / 4 + k * math.pi / 2) * ARM_R, math.sin(math.pi / 4 + k * math.pi / 2) * ARM_R, 0.205)) for k in range(4)]


def build_rotor_discs(col, index):
    b = Builder("RotorDisc_%d" % index, "GB_Body", smooth=False)
    for off in rotor_offsets():
        b.disc(T(off.x, off.y, off.z + 0.03), ROTOR_R, WHITE, segs=28)
    obj = b.finish(col)
    obj.data.materials.clear()
    obj.data.materials.append(MAT["GB_RotorBlur"])
    return obj


def build_cable(col, index):
    """吊りケーブル：角の金具からドローンのフックまで。原点＝角の金具、ローカルの +Z（Godot の +Y）がドローンへ向く。"""
    a = corner_attach(index)
    h = drone_center(index) + Vector((0, 0, DRONE_HOOK_Z))
    length = (h - a).length
    b = Builder("Cable_%d" % index, "GB_Body")
    b.cylinder(T(0, 0, length / 2), 0.03, 0.03, length, CABLE, segs=8, caps=False)
    # 両端の金具
    b.cylinder(T(0, 0, 0.08), 0.045, 0.045, 0.12, METAL, segs=8)
    b.cylinder(T(0, 0, length - 0.08), 0.045, 0.045, 0.12, METAL, segs=8)
    obj = b.finish(col)
    direction = (h - a).normalized()
    rot = direction.to_track_quat("Z", "Y").to_matrix().to_4x4()
    obj.matrix_world = Matrix.Translation(a) @ rot
    return obj, length


# ---------------------------------------------------------------- シーン

def collection(name, parent=None):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(col)
    for obj in list(col.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    return col


def purge_meshes():
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def build_review(col):
    """確かめ用：はるか下の海と、大きさ比べの腹ばいの人形（高さ 2m の人を寝かせた箱）。"""
    sea_me = bpy.data.meshes.new("REF_Sea")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=400)
    bm.to_mesh(sea_me)
    bm.free()
    sea_mat = material("REF_SeaWater", tuple(srgb("#1E6FB8")), 0.2)
    sea_me.materials.append(sea_mat)
    sea = bpy.data.objects.new("REF_Sea", sea_me)
    col.objects.link(sea)
    sea.location = (0, 0, -80)
    doll_mat = material("REF_Doll", tuple(srgb("#F28A2E")), 0.6)
    c = panel_center(1)
    for name, size, off in (("REF_DollBody", (0.76, 1.15, 0.44), (0, 0, 0)), ("REF_DollHead", (0.44, 0.44, 0.44), (0, 0.85, 0.05)),
                            ("REF_DollArmL", (1.0, 0.24, 0.24), (-0.8, 0.35, 0)), ("REF_DollArmR", (1.0, 0.24, 0.24), (0.8, 0.35, 0)),
                            ("REF_DollLegL", (0.34, 0.95, 0.34), (-0.22, -1.0, 0)), ("REF_DollLegR", (0.34, 0.95, 0.34), (0.22, -1.0, 0))):
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(doll_mat)
        o = bpy.data.objects.new(name, me)
        col.objects.link(o)
        o.location = c + Vector((0.6 + off[0], 0.2 + off[1], 3.4 + off[2]))


def build_lighting(col):
    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    try:
        sky.sky_type = "MULTIPLE_SCATTERING"
    except TypeError:
        sky.sky_type = "NISHITA"
    sky.sun_disc = False
    sky.sun_elevation = math.radians(48)
    sky.sun_rotation = math.radians(200)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.09
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    sun_data = bpy.data.lights.get("LGT_key") or bpy.data.lights.new("LGT_key", "SUN")
    sun_data.energy = 2.3
    sun_data.angle = math.radians(2.0)
    sun = bpy.data.objects.new("LGT_key", sun_data)
    col.objects.link(sun)
    sun.rotation_euler = (math.radians(38), 0.0, math.radians(200 - 180))


def add_camera(col, name, eye, target, lens):
    cam_data = bpy.data.cameras.get(name) or bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_start = 0.05
    cam_data.clip_end = 1000
    cam = bpy.data.objects.new(name, cam_data)
    col.objects.link(cam)
    cam.location = eye
    direction = Vector(target) - Vector(eye)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return cam


def build_cameras(col):
    d1 = drone_center(1)
    return {
        "gb_01_topdown": add_camera(col, "CAM_TopDown", (0.0, -14.0, 21.0), (0.0, 2.0, 0.0), 28),
        "gb_02_hero": add_camera(col, "CAM_Hero", (-11.5, -12.5, 7.5), (0.5, 0.8, 0.6), 30),
        "gb_03_below": add_camera(col, "CAM_Below", (2.0, -9.0, -9.5), (0.0, 0.5, 0.5), 30),
        "gb_04_drone": add_camera(col, "CAM_Drone", (d1.x - 2.6, d1.y - 3.3, d1.z + 1.4), (d1.x - 0.2, d1.y - 0.2, d1.z - 0.6), 40),
        "gb_05_corner": add_camera(col, "CAM_Corner", (-3.5, 0.2, 3.6), (-7.6, 3.4, 0.6), 35),
    }


def render_previews(cameras):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    paths = []
    for name, cam in cameras.items():
        scene.camera = cam
        scene.render.filepath = str(PREVIEWS / (name + ".png"))
        bpy.ops.render.render(write_still=True)
        paths.append(scene.render.filepath)
    scene.camera = cameras["gb_02_hero"]
    return paths


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main():
    if bpy.data.filepath and Path(bpy.data.filepath).resolve() != BLEND.resolve():
        raise RuntimeError("別の .blend が開いている：" + bpy.data.filepath)
    build_materials()
    export_col = collection("GB_EXPORT")
    review_col = collection("REF_Review")
    cam_col = collection("CAMERAS")
    light_col = collection("LIGHTING")
    purge_meshes()

    root = bpy.data.objects.new("GateBoard", None)
    export_col.objects.link(root)
    root.empty_display_size = 1.0
    meshes = []

    frame = build_frame(export_col)
    sign_frame = build_sign_frame(export_col)
    sign = build_sign(export_col)
    panels = [build_panel(export_col, i) for i in range(4)]
    for o in [frame, sign_frame, sign] + panels:
        o.parent = root
    meshes += [frame, sign_frame, sign] + panels

    drones, rotors, discs, cables, cable_len = [], [], [], [], {}
    for i in range(DRONE_COUNT):
        d = build_drone(export_col, i)
        d.parent = root
        drones.append(d)
        for k, off in enumerate(rotor_offsets()):
            r = build_rotor(export_col, i, k)
            r.parent = d
            r.location = off
            rotors.append(r)
        disc = build_rotor_discs(export_col, i)
        disc.parent = d
        discs.append(disc)
        cable, length = build_cable(export_col, i)
        cable.parent = root
        cables.append(cable)
        cable_len[cable.name] = round(length, 4)
    meshes += drones + rotors + discs + cables

    build_review(review_col)
    build_lighting(light_col)
    cameras = build_cameras(cam_col)

    per = {o.name: tri_count(o) for o in meshes}
    layout = {
        "note": "スカイゲートの問題のボード。Godot の座標（x 右, y 上, z 手前）。原点＝ボードの中心 × 紙の面。−Z が奥（問題文の帯）。build_gate_board.py が書く",
        "board_size": [BOARD_W, BOARD_D],
        "frame": {"width": FRAME_W, "height": FRAME_H, "inner_width": INNER_W, "inner_height": INNER_H},
        "panels": {"Panel_%d" % i: {"center": godot(panel_center(i)), "size": [round(PANEL_W, 4), round(PANEL_D, 4)],
                                    "color": PAPER[i][1], "name": PAPER[i][0]} for i in range(4)},
        "panel_order": "0=奥の左, 1=奥の右, 2=手前の左, 3=手前の右（ルールの選択肢の番号と同じ）",
        "question_sign": {"face_center_top": godot(Vector((0.0, (SIGN_Y0 + SIGN_Y1) / 2, SIGN_TOP + 0.018))),
                          "face_size": [round(SIGN_FACE_W, 4), round(SIGN_FACE_D, 4)],
                          "outer_size": [SIGN_W, SIGN_D], "near_y": round(SIGN_Y0, 4), "far_y": round(SIGN_Y1, 4)},
        "drone_order": "0・1＝看板の手前の角（左・右）、2・3＝ボードの手前の角、4・5＝看板の奥の角",
        "drones": {"Drone_%d" % i: {"center": godot(drone_center(i)), "hook": godot(drone_center(i) + Vector((0, 0, DRONE_HOOK_Z)))} for i in range(DRONE_COUNT)},
        "cables": {"Cable_%d" % i: {"attach": godot(corner_attach(i)), "length": cable_len["Cable_%d" % i]} for i in range(DRONE_COUNT)},
        "drone_hook_y": DRONE_HOOK_Z,
        "rotor_radius": ROTOR_R,
        "paper_sag": PAPER_SAG,
    }
    report = {
        "triangles": sum(per.values()),
        "objects": per,
        "materials": sorted({m.name for o in meshes for m in o.data.materials}),
        "layout": layout,
    }

    if DO_EXPORT:
        bpy.ops.object.select_all(action="DESELECT")
        for o in [root] + meshes:
            o.select_set(True)
        bpy.context.view_layer.objects.active = root
        kwargs = dict(filepath=str(GLB), export_format="GLB", use_selection=True, export_apply=True,
                      export_yup=True, export_extras=False, export_cameras=False, export_lights=False)
        try:
            bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
        except TypeError:
            bpy.ops.export_scene.gltf(**kwargs)
        LAYOUT.write_text(json.dumps(layout, ensure_ascii=False, indent=2), encoding="utf-8")
    report["previews"] = render_previews(cameras) if DO_RENDER else []
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if DO_SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    return report


if __name__ == "__main__":
    RESULT = main()

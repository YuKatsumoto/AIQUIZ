"""パラシュート一式（布・つり索・スライダー・ライザー・パイロットシュート・ブライドル・収納袋・コンテナ・ハンカチ）と水柱を作る。
仕様：SCENE_PASSPORT.md（このフォルダ）と docs/sudden_death_v2/parachute.md 6.4節。

ライブの Blender（Higgsfield の Blender 連携）で実行する。ヘッドレスで代替しない（AGENTS.md）。
    import runpy, sys
    sys.argv = ["blender", "--"]      # "--no-export" で書き出さない、"--no-render" で確認レンダーを出さない、"--no-save" で保存しない
    runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/sudden_death/parachute/chute/source/blender/build_parachute.py", run_name="__main__")
開いているファイルが parachute.blend でなければ止まる（新しく作るときは先に空のファイルにして、この名前で保存しておく）。

座標：Blender の Z が上、メートル。パラシュートの原点＝肩のライザーのつけ根（両肩の真ん中）。+X が体の横、−Y が前。
Godot では (x, z, −y)。水柱の原点＝水面の中心。
段ごとの形は形の切り替え（シェイプキー）：基本形＝全開、Packed＝袋の中、Half＝半分ふくらんだしわの形、Collapsed＝着地で後ろへつぶれる、
Breath＝ふくらみが少し抜ける（はためき用）、Grounded＝着地のあと床に落ちた形（布は後ろに小さく山になり、つり索・スライダー・
ライザーも床に寝る。原点＝床、Godot が原点を肩から床へ下ろしながら重みを上げる）。
Canopy・Lines・Slider・Risers に同じ名前で持たせ（Risers は Grounded だけ動く）、Godot が重みを変える。
"""
import json
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent
ASSET = SOURCE.parent
PREVIEWS = SOURCE / "previews"
CHUTE_GLB = ASSET / "chute.glb"
SPLASH_GLB = ASSET / "splash.glb"
LAYOUT = ASSET / "chute_layout.json"
REPORT = SOURCE / "build_report.json"
BLEND = HERE / "parachute.blend"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
DO_RENDER = "--no-render" not in ARGS
DO_SAVE = "--no-save" not in ARGS

# ---------------------------------------------------------------- 寸法
CELLS = 9
SPAN = 7.2
ARC = math.radians(70.0)
CHORD = 2.6
THICK_RATIO = 0.20           # 翼厚（翼弦に対する比）
CAMBER = 0.04
CAMBER_AT = 0.35
Z_MID = 6.3                  # 中央のセルの翼弦線の高さ
INTAKE = 0.12                # 下の面が始まる位置（前縁の取り込み口）
SPAN_STEPS = 8               # 1 セルあたりの幅方向の分割
CHORD_STEPS = 22
ROWS = [0.14, 0.38, 0.62, 0.86]   # A〜D のつり索のつけ根（翼弦の位置）
LINK_Z = 0.55
LINK_X = 0.22
LINK_Y = 0.07
TOGGLE_Z = 0.38
SLIDER_Z = 0.62
BAG_CENTER = Vector((0.0, 0.0, 1.3))
LINE_R = 0.0045
R_ARC = SPAN / ARC


# ---------------------------------------------------------------- 翼の形

def theta(u):
    return u * ARC


def arc_base(u):
    t = theta(u)
    return Vector((R_ARC * math.sin(t), 0.0, Z_MID - R_ARC + R_ARC * math.cos(t)))


def arc_normal(u):
    t = theta(u)
    return Vector((math.sin(t), 0.0, math.cos(t)))


def half_thickness(c):
    c = min(max(c, 0.0), 1.0)
    t = THICK_RATIO
    return 5.0 * t * (0.2969 * math.sqrt(c) - 0.1260 * c - 0.3516 * c * c + 0.2843 * c ** 3 - 0.1036 * c ** 4) * CHORD


def camber(c):
    m, p = CAMBER, CAMBER_AT
    if c < p:
        v = m / (p * p) * (2 * p * c - c * c)
    else:
        v = m / ((1 - p) ** 2) * ((1 - 2 * p) + 2 * p * c - c * c)
    return v * CHORD


def upper(c):
    return camber(c) + half_thickness(c)


def lower(c):
    return camber(c) - 0.55 * half_thickness(c)


def chord_y(c):
    return -CHORD * 0.5 + c * CHORD


def pillow(u, c, top):
    """セルの間のふくらみ（リブの位置で 0）。"""
    cell = (u + 0.5) * CELLS
    s = cell - math.floor(cell)
    amp = 0.06 if top else 0.035
    return amp * math.sin(math.pi * s) * math.sin(math.pi * min(1.0, max(c, 0.0) * 1.05)) ** 0.6


def skin_point(u, c, top):
    off = upper(c) + pillow(u, c, True) if top else lower(c) - pillow(u, c, False)
    return arc_base(u) + arc_normal(u) * off + Vector((0.0, chord_y(c), 0.0))


def cosine_steps(n, a=0.0, b=1.0):
    return [a + (b - a) * (0.5 - 0.5 * math.cos(math.pi * i / (n - 1))) for i in range(n)]


def rib_u(k):
    return -0.5 + k / CELLS


# ---------------------------------------------------------------- メッシュの道具（材質の番号つき）

class Builder:
    def __init__(self, name, materials, smooth=True):
        self.name = name
        self.materials = list(materials)
        self.smooth = smooth
        self.bm = bmesh.new()

    def m(self, name):
        return self.materials.index(name)

    def face(self, verts, mat, smooth=None):
        f = self.bm.faces.new(verts)
        f.material_index = mat
        f.smooth = self.smooth if smooth is None else smooth
        return f

    def grid(self, pts, mat_of=None, closed_u=False, closed_v=False, mat=0):
        nu, nv = len(pts), len(pts[0])
        verts = [[self.bm.verts.new(p) for p in row] for row in pts]
        for i in range(nu if closed_u else nu - 1):
            for j in range(nv if closed_v else nv - 1):
                i2, j2 = (i + 1) % nu, (j + 1) % nv
                self.face((verts[i][j], verts[i2][j], verts[i2][j2], verts[i][j2]), mat_of(i, j) if mat_of else mat)
        return verts

    def add_bm(self, other, matrix, mat):
        bmesh.ops.transform(other, matrix=matrix, verts=other.verts)
        for f in other.faces:
            f.material_index = mat
        me = bpy.data.meshes.new("_tmp")
        other.to_mesh(me)
        other.free()
        offset = len(self.bm.verts)
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def box(self, matrix, size, mat, bevel=0.0, segs=2):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segs, affect="EDGES", profile=0.5)
        for f in bm.faces:
            f.smooth = bevel > 0
        self.add_bm(bm, matrix, mat)

    def cylinder(self, matrix, r1, r2, depth, mat, segs=12, caps=True):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth)
        for f in bm.faces:
            f.smooth = True
        self.add_bm(bm, matrix, mat)

    def sphere(self, matrix, r, mat, segs=12, rings=6):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
        for f in bm.faces:
            f.smooth = True
        self.add_bm(bm, matrix, mat)

    def torus(self, matrix, major, minor, mat, segs=16, sides=6):
        pts = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            d = Vector((math.cos(a), math.sin(a), 0))
            pts.append([matrix @ (d * major + d * math.cos(2 * math.pi * j / sides) * minor + Vector((0, 0, math.sin(2 * math.pi * j / sides) * minor)))
                        for j in range(sides)])
        self.grid(pts, closed_u=True, closed_v=True, mat=mat)

    def sweep(self, path, radius, mat, sides=6, flat=0.0):
        """点の列に沿った管。flat > 0 なら幅 radius×2、厚さ flat の帯。"""
        tangents = []
        for i in range(len(path)):
            a = path[max(i - 1, 0)]
            b = path[min(i + 1, len(path) - 1)]
            tangents.append((b - a).normalized())
        ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
        u = tangents[0].cross(ref).normalized()
        rows = []
        for i, p in enumerate(path):
            t = tangents[i]
            u = (u - t * u.dot(t)).normalized()
            v = t.cross(u).normalized()
            if flat > 0:
                rows.append([p + u * radius + v * flat, p - u * radius + v * flat, p - u * radius - v * flat, p + u * radius - v * flat])
            else:
                rows.append([p + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * radius for k in range(sides)])
        self.grid(rows, closed_v=True, mat=mat)

    def finish(self, collection, smooth_angle=None):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for name in self.materials:
            me.materials.append(MAT[name])
        obj = bpy.data.objects.new(self.name, me)
        collection.objects.link(obj)
        return obj


# ---------------------------------------------------------------- 材質

MAT = {}


def principled(name, color, rough=0.6, metal=0.0, alpha=1.0, emit=None, strength=0.0, double=True):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    mat.use_backface_culling = not double
    MAT[name] = mat
    return mat


def build_materials():
    principled("PC_Accent", (0.92, 0.38, 0.07), 0.55)          # Godot がプレイヤーの色に塗り替える
    principled("PC_White", (0.93, 0.93, 0.91), 0.6)
    principled("PC_Rib", (0.80, 0.80, 0.78), 0.65)
    principled("PC_Line", (0.86, 0.86, 0.84), 0.7)
    principled("PC_Webbing", (0.07, 0.075, 0.085), 0.8)
    principled("PC_Metal", (0.78, 0.79, 0.80), 0.3, metal=1.0, double=False)
    principled("PC_Mesh", (0.12, 0.13, 0.14), 0.8, alpha=0.75)
    principled("PC_Bag", (0.16, 0.17, 0.19), 0.75)
    principled("PC_Container", (0.10, 0.11, 0.13), 0.7, double=False)
    principled("PC_HankyWhite", (0.97, 0.97, 0.95), 0.75)
    principled("PC_HankyRed", (0.82, 0.08, 0.10), 0.7)
    principled("SP_Water", (0.88, 0.95, 1.0), 0.15, alpha=0.82)
    principled("SP_Foam", (0.96, 0.98, 1.0), 0.6, alpha=0.86)
    principled("REF_Body", (0.95, 0.55, 0.2), 0.6, double=False)
    principled("REF_Sea", (0.012, 0.07, 0.09), 0.16, double=False)


# ---------------------------------------------------------------- 布

def build_canopy(col):
    b = Builder("Canopy", ["PC_Accent", "PC_White", "PC_Rib"])
    us = []
    for k in range(CELLS):
        for j in range(SPAN_STEPS):
            us.append(rib_u(k) + (j / SPAN_STEPS) / CELLS)
    us.append(0.5)
    cs_top = cosine_steps(CHORD_STEPS)
    cs_bottom = cosine_steps(int(CHORD_STEPS * 0.85), INTAKE, 1.0)

    def cell_mat(i, _j):
        cell = min(int(i / SPAN_STEPS), CELLS - 1)
        return b.m("PC_Accent") if cell % 2 == 0 else b.m("PC_White")

    b.grid([[skin_point(u, c, True) for c in cs_top] for u in us], mat_of=cell_mat)
    b.grid([[skin_point(u, c, False) for c in reversed(cs_bottom)] for u in us], mat_of=cell_mat)
    # リブ（翼の断面の板）。前縁の取り込み口から中が見える。
    for k in range(CELLS + 1):
        u = rib_u(k)
        outline = [skin_point(u, c, True) for c in cs_top] + [skin_point(u, c, False) for c in reversed(cs_bottom)][1:-1]
        verts = [b.bm.verts.new(p) for p in outline]
        f = b.face(verts, b.m("PC_Rib"), smooth=False)
        bmesh.ops.triangulate(b.bm, faces=[f], quad_method="BEAUTY", ngon_method="BEAUTY")
        # つり索のつけ根のタブ（リブの下へ小さく出た三角）
        for c in ROWS:
            p = skin_point(u, c, False)
            n = arc_normal(u)
            tab = [b.bm.verts.new(p + Vector((0, -0.07, 0))), b.bm.verts.new(p + Vector((0, 0.07, 0))), b.bm.verts.new(p - n * 0.09)]
            b.face(tab, b.m("PC_Rib"), smooth=False)
    # 両端の安定板（下へ垂れた三角の布）
    for k in (0, CELLS):
        u = rib_u(k)
        n = arc_normal(u)
        p0, p1 = skin_point(u, 0.22, False), skin_point(u, 0.88, False)
        tip = skin_point(u, 0.6, False) - n * 0.62
        rows = []
        for i in range(7):
            t = i / 6
            top = p0.lerp(p1, t)
            rows.append([top, top.lerp(tip, 0.5 * (1 - abs(2 * t - 1)) + 0.0), top.lerp(tip, 1 - abs(2 * t - 1))])
        b.grid(rows, mat=b.m("PC_Accent"))
    return b.finish(col)


def attach_point(k, c):
    u = rib_u(k)
    return skin_point(u, c, False) - arc_normal(u) * 0.09


def link_point(side, front):
    return Vector((LINK_X * side, -LINK_Y if front else LINK_Y, LINK_Z))


def build_lines(col):
    b = Builder("Lines", ["PC_Line", "PC_Accent"], smooth=True)
    groups = [[0, 1], [2, 3], [4], [5], [6, 7], [8, 9]]
    junctions = []
    for group in groups:
        side = -1.0 if max(group) <= 4 else 1.0
        for front, rows in ((True, ROWS[:2]), (False, ROWS[2:])):
            attaches = [attach_point(k, c) for k in group for c in rows]
            mean = sum(attaches, Vector()) / len(attaches)
            n = sum((arc_normal(rib_u(k)) for k in group), Vector()).normalized()
            junction = mean - n * 1.7
            for a in attaches:
                b.sweep([a, junction], LINE_R, b.m("PC_Line"), sides=4)
            b.sweep([junction, link_point(side, front)], LINE_R * 1.6, b.m("PC_Line"), sides=4)
            junctions.append(junction)
    # ブレーク索：後縁からトグルへ（色つき）
    for side, ribs in ((-1.0, [0, 1, 2, 3]), (1.0, [6, 7, 8, 9])):
        tails = [skin_point(rib_u(k), 0.97, False) for k in ribs]
        mean = sum(tails, Vector()) / len(tails)
        cascade = mean + Vector((0, 0.35, -2.4))
        for t in tails:
            b.sweep([t, cascade], LINE_R * 0.9, b.m("PC_Accent"), sides=4)
        toggle = Vector((LINK_X * side, LINK_Y + 0.03, TOGGLE_Z))
        b.sweep([cascade, toggle + Vector((0, 0, 0.05))], LINE_R * 1.2, b.m("PC_Accent"), sides=4)
    return b.finish(col)


def build_slider(col):
    b = Builder("Slider", ["PC_Accent", "PC_Metal"])
    rows = []
    for i in range(7):
        x = -0.475 + 0.95 * i / 6
        rows.append([Vector((x, -0.375 + 0.75 * j / 5, SLIDER_Z - 0.05 * (1 - (x / 0.475) ** 2) - 0.03 * (1 - ((-0.375 + 0.75 * j / 5) / 0.375) ** 2)))
                     for j in range(6)])
    b.grid(rows, mat=b.m("PC_Accent"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.torus(Matrix.Translation((0.44 * sx, 0.34 * sy, SLIDER_Z + 0.005)), 0.035, 0.008, b.m("PC_Metal"), segs=14, sides=5)
    return b.finish(col)


def build_risers(col):
    b = Builder("Risers", ["PC_Webbing", "PC_Metal", "PC_Accent"])
    for side in (-1.0, 1.0):
        for front in (True, False):
            base = Vector((0.17 * side, -0.035 if front else 0.035, 0.0))
            top = link_point(side, front)
            b.sweep([base, base.lerp(top, 0.5) + Vector((0.01 * side, 0, 0)), top], 0.0125, b.m("PC_Webbing"), flat=0.003)
            b.torus(Matrix.Translation(top + Vector((0, 0, 0.012))) @ Matrix.Rotation(math.pi / 2, 4, "X"), 0.018, 0.0035, b.m("PC_Metal"), segs=12, sides=4)
        # トグル（後ろのライザー）
        toggle = Vector((LINK_X * side, LINK_Y + 0.03, TOGGLE_Z))
        b.cylinder(Matrix.Translation(toggle) @ Matrix.Rotation(math.pi / 2, 4, "Y"), 0.012, 0.012, 0.09, b.m("PC_Accent"), segs=8)
    return b.finish(col)


# ---------------------------------------------------------------- 形の切り替え

def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def jitter(i, scale):
    rnd = random.Random(1000 + i)
    return Vector((rnd.uniform(-1, 1) * scale.x, rnd.uniform(-1, 1) * scale.y, rnd.uniform(-1, 1) * scale.z))


def wrinkle(p, amount):
    return Vector((0.13 * math.sin(p.x * 6.3 + p.y * 2.1) + 0.05 * math.sin(p.z * 9.0),
                   0.10 * math.cos(p.x * 4.7 + 1.3),
                   0.17 * math.sin(p.x * 3.9 + p.y * 3.3 + p.z * 1.7) + 0.06 * math.cos(p.x * 11.0))) * amount


def key_half(p, i):
    w = smoothstep(LINK_Z + 0.05, 4.6, p.z)
    target = Vector((p.x * 0.53, p.y * 0.78, LINK_Z + (p.z - LINK_Z) * 0.74))
    out = p + (target - p) * w + wrinkle(p, w * w)
    return out


def key_packed(p, i):
    if p.z <= LINK_Z + 0.02:
        return p.copy()
    top = 4.6
    t = min(max((p.z - LINK_Z) / (top - LINK_Z), 0.0), 1.0)
    root = Vector((max(-LINK_X, min(LINK_X, p.x)), max(-LINK_Y, min(LINK_Y, p.y)), LINK_Z))
    if t >= 1.0:
        return BAG_CENTER + jitter(i, Vector((0.13, 0.065, 0.2)))
    return root.lerp(BAG_CENTER + jitter(i, Vector((0.04, 0.03, 0.05))), smoothstep(0.0, 1.0, t))


def key_collapsed(p, i):
    w = smoothstep(LINK_Z + 0.05, 4.6, p.z)
    target = Vector((p.x * 0.92, p.y + 4.2, p.z * 0.12 - 2.3))
    return p + (target - p) * w + wrinkle(p, w * 0.6) * Vector((1.0, 1.0, 0.3))


def key_breath(p, i):
    w = smoothstep(LINK_Z + 0.05, 4.6, p.z)
    return p + Vector((-p.x * 0.025, 0.0, -0.08)) * w + wrinkle(p, 0.12 * w)


# 床に落ちた形（Grounded）。原点＝床の上、着地した人の少し後ろ。+Y（Blender）＝後ろ。
GROUND_BACK = 1.55     # 布の山の中心（原点から後ろ）
GROUND_HALF_X = 1.45   # 布の山の横の半分（着地面の半径 3.15 m に収まる）


def ground_low(p):
    """ライザーのあたり：つけ根を中心に後ろへ寝かせる（上 → 後ろ）。"""
    return Vector((p.x, p.z, 0.07 - p.y * 0.5))


def canopy_h(p):
    """翼の中心の弧からの高さ（上の面が＋、下の面が−）。"""
    t = math.asin(max(-1.0, min(1.0, p.x / R_ARC)))
    n = Vector((math.sin(t), 0.0, math.cos(t)))
    base = Vector((R_ARC * math.sin(t), 0.0, Z_MID - R_ARC + R_ARC * math.cos(t)))
    return (p - base).dot(n)


def pile_xy(p):
    x = p.x / (R_ARC * math.sin(ARC / 2)) * GROUND_HALF_X + 0.08 * math.sin(p.y * 3.0)
    y = GROUND_BACK + p.y * 0.6 + 0.12 * math.sin(p.x * 1.7)
    return x, y


def key_grounded(p, i):
    """布：幅をたたんで後ろの床に寝かせる。上の面は下の面より上のまま（重ならない）、ゆるいひだと、ふくらみの残り。"""
    x, y = pile_xy(p)
    h = max(-0.3, min(0.35, canopy_h(p)))
    fold = 0.09 * (0.5 + 0.5 * math.sin(p.x * 4.2 + 0.6)) * (1.0 - min(abs(p.y) / 1.7, 1.0))
    lump = 0.03 * math.sin(p.x * 2.3 + p.y * 3.1) + 0.025 * math.sin(p.y * 4.0 + 1.1)
    return Vector((x, y, max(0.02, 0.06 + (h + 0.3) * 0.18 + fold + lump)))


def key_grounded_lines(p, i):
    """つり索：ライザーの先から床をはって布の山の下へ（少しうねる）。"""
    if p.z <= LINK_Z + 0.02:
        return ground_low(p)
    s = min(max((p.z - LINK_Z) / (5.3 - LINK_Z), 0.0), 1.0)
    x, y = pile_xy(p)
    end_z = key_grounded(p, i).z
    start = Vector((p.x, LINK_Z, 0.03))
    out = start.lerp(Vector((x, y, 0.03)), s)
    out.x += 0.12 * math.sin(s * 11.0 + p.x) * 4.0 * s * (1.0 - s)
    out.z = 0.03 + (end_z - 0.03) * smoothstep(0.8, 1.0, s)
    return out


def key_grounded_slider(p, i):
    return Vector((p.x * 0.9, 0.72 + p.y * 0.9, 0.035 + (p.z - SLIDER_Z + 0.08) * 0.25))


def slider_key(name, p, i):
    if name == "Half":
        return Vector((p.x * 0.85, p.y * 0.85, p.z + 2.5))
    if name == "Packed":
        return BAG_CENTER + Vector((p.x * 0.25, p.y * 0.25, -0.32 + (p.z - SLIDER_Z)))
    if name == "Breath":
        return p + Vector((0, 0, 0.03))
    return p.copy()


KEYS = {"Packed": key_packed, "Half": key_half, "Collapsed": key_collapsed, "Breath": key_breath, "Grounded": key_grounded}
KEY_NAMES = list(KEYS)


def add_shape_keys(obj, kind="canopy"):
    """kind：canopy・lines・slider・risers（ライザーは Grounded だけ動き、ほかは基本形のまま）。"""
    obj.shape_key_add(name="Basis", from_mix=False)
    basis = [v.co.copy() for v in obj.data.vertices]
    for name, fn in KEYS.items():
        key = obj.shape_key_add(name=name, from_mix=False)
        for i, co in enumerate(basis):
            if name == "Grounded":
                fn = {"canopy": key_grounded, "lines": key_grounded_lines, "slider": key_grounded_slider, "risers": lambda c, _i: ground_low(c)}[kind]
                key.data[i].co = fn(co, i)
            elif kind == "slider":
                key.data[i].co = slider_key(name, co, i)
            elif kind == "risers":
                key.data[i].co = co.copy()
            else:
                key.data[i].co = fn(co, i)
        key.value = 0.0


# ---------------------------------------------------------------- 小物

def build_pilot(col):
    """パイロットシュート。原点＝ブライドルのつけ根（ドームの 0.6 m 下）。"""
    b = Builder("PilotChute", ["PC_Accent", "PC_White", "PC_Mesh", "PC_Line"])
    gores = 12
    lift = 0.6
    rows = []
    rings = 9
    for g in range(gores * 3):
        a = 2 * math.pi * g / (gores * 3)
        row = []
        for r in range(rings):
            t = r / (rings - 1)
            phi = t * math.radians(80)
            radius = 0.55 * math.sin(phi)
            z = lift + 0.18 + 0.42 * math.cos(phi)
            billow = 1.0 + 0.04 * math.sin(math.pi * ((g % 3) / 3.0 + 1 / 6.0))
            row.append(Vector((math.cos(a) * radius * billow, math.sin(a) * radius * billow, z)))
        rows.append(row)
    b.grid(rows, mat_of=lambda i, j: b.m("PC_Accent") if (i // 3) % 2 == 0 else b.m("PC_White"), closed_u=True)
    # 網のすそ
    skirt = []
    for g in range(gores * 3):
        a = 2 * math.pi * g / (gores * 3)
        skirt.append([Vector((math.cos(a) * 0.545, math.sin(a) * 0.545, lift + 0.25)), Vector((math.cos(a) * 0.30, math.sin(a) * 0.30, lift - 0.12))])
    b.grid(skirt, closed_u=True, mat=b.m("PC_Mesh"))
    b.sphere(Matrix.Translation((0, 0, lift + 0.61)), 0.05, b.m("PC_Accent"), segs=10, rings=5)
    b.sweep([Vector((0, 0, 0)), Vector((0, 0, lift + 0.6))], 0.006, b.m("PC_Line"), sides=4)
    for g in range(gores):
        a = 2 * math.pi * g / gores
        b.sweep([Vector((0, 0, 0.02)), Vector((math.cos(a) * 0.30, math.sin(a) * 0.30, lift - 0.12))], 0.003, b.m("PC_Line"), sides=3)
    return b.finish(col)


def build_bridle(col):
    b = Builder("Bridle", ["PC_Webbing"])
    b.sweep([Vector((0, 0, 0)), Vector((0, 0, 0.5)), Vector((0, 0, 1.0))], 0.014, b.m("PC_Webbing"), flat=0.002)
    return b.finish(col)


def build_bag(col):
    b = Builder("DeployBag", ["PC_Bag", "PC_Accent", "PC_Metal"])
    b.box(Matrix.Identity(4), (0.34, 0.18, 0.5), b.m("PC_Bag"), bevel=0.035, segs=3)
    b.box(Matrix.Translation((0, 0, 0.255)), (0.33, 0.17, 0.03), b.m("PC_Bag"), bevel=0.01)
    b.box(Matrix.Translation((0, -0.092, 0.12)), (0.30, 0.004, 0.035), b.m("PC_Accent"))
    b.torus(Matrix.Translation((0, 0, 0.275)), 0.03, 0.007, b.m("PC_Metal"), segs=12, sides=5)
    for x in (-0.09, 0.09):
        for z in (-0.05, -0.17):
            b.torus(Matrix.Translation((x, -0.095, z)) @ Matrix.Rotation(math.pi / 2, 4, "X"), 0.022, 0.006, b.m("PC_Bag"), segs=10, sides=4)
    return b.finish(col)


def build_container(col):
    """背中のコンテナ。原点＝背中に当たる面の中心。本体は +Y（Godot の後ろ）へ。"""
    b = Builder("Container", ["PC_Container", "PC_Accent", "PC_Metal", "PC_Webbing"])
    b.box(Matrix.Translation((0, 0.08, 0)), (0.36, 0.16, 0.46), b.m("PC_Container"), bevel=0.04, segs=3)
    b.box(Matrix.Translation((0, 0.09, 0.215)), (0.34, 0.15, 0.05), b.m("PC_Container"), bevel=0.02, segs=2)   # 予備のフタ
    for x in (-1, 1):
        b.box(Matrix.Translation((0.185 * x, 0.09, -0.02)), (0.02, 0.13, 0.36), b.m("PC_Container"), bevel=0.008)  # 横のフタ
    b.box(Matrix.Translation((0, 0.163, 0.02)), (0.26, 0.004, 0.012), b.m("PC_Accent"))   # 縫い目の帯
    b.box(Matrix.Translation((0, 0.163, -0.12)), (0.26, 0.004, 0.012), b.m("PC_Accent"))
    # 肩のヨーク（前へ回る帯）
    for x in (-1, 1):
        b.sweep([Vector((0.12 * x, 0.02, 0.22)), Vector((0.13 * x, -0.06, 0.30)), Vector((0.14 * x, -0.16, 0.26)), Vector((0.14 * x, -0.20, 0.12))],
                0.022, b.m("PC_Webbing"), flat=0.004)
    # 引き手（下の右）
    b.box(Matrix.Translation((0.13, 0.15, -0.21)), (0.08, 0.03, 0.05), b.m("PC_Container"), bevel=0.008)
    b.sphere(Matrix.Translation((0.13, 0.18, -0.25)), 0.024, b.m("PC_Accent"), segs=10, rings=5)
    b.torus(Matrix.Translation((0.0, 0.165, 0.18)) @ Matrix.Rotation(math.pi / 2, 4, "X"), 0.012, 0.004, b.m("PC_Metal"), segs=10, sides=4)
    return b.finish(col)


def build_hanky(col):
    """ハンカチ。原点＝ひものつけ根。布は +Z の 0.6〜1.05 m、−Y を向く。"""
    b = Builder("Hanky", ["PC_HankyWhite", "PC_HankyRed", "PC_Line"])
    n = 12
    size = 0.45
    rows = []
    for i in range(n + 1):
        x = -size / 2 + size * i / n
        row = []
        for j in range(n + 1):
            z = 0.6 + size * j / n
            wave = 0.035 * math.sin(i * 0.9 + j * 0.4) + 0.02 * math.sin(j * 1.7)
            row.append(Vector((x, wave, z)))
        rows.append(row)
    b.grid(rows, mat_of=lambda i, j: b.m("PC_HankyRed") if i in (0, 1, n - 2, n - 1) or j in (0, 1, n - 2, n - 1) else b.m("PC_HankyWhite"))
    # レースのふち（外へ波打つ細い帯）
    edge = []
    for t in range(48):
        s = t / 48 * 4
        side = int(s) % 4
        f = s - int(s)
        corners = [Vector((-size / 2, 0, 0.6)), Vector((size / 2, 0, 0.6)), Vector((size / 2, 0, 0.6 + size)), Vector((-size / 2, 0, 0.6 + size))]
        p = corners[side].lerp(corners[(side + 1) % 4], f)
        out = (p - Vector((0, 0, 0.6 + size / 2))).normalized()
        edge.append([p, p + out * (0.025 + 0.008 * math.sin(t * 2.0)) + Vector((0, 0.01 * math.sin(t * 1.3), 0))])
    b.grid(edge, closed_u=True, mat=b.m("PC_HankyWhite"))
    b.sweep([Vector((0, 0, 0)), Vector((0.01, 0.01, 0.3)), Vector((-0.2, 0.0, 0.6))], 0.004, b.m("PC_Line"), sides=3)
    b.torus(Matrix.Translation((-0.205, 0.0, 0.6)) @ Matrix.Rotation(math.pi / 2, 4, "X"), 0.012, 0.003, b.m("PC_Line"), segs=8, sides=3)
    return b.finish(col)


# ---------------------------------------------------------------- 水柱

def build_splash(col):
    parts = []
    rnd = random.Random(7)
    # 柱：でこぼこの回転体（高さ 11 m）
    b = Builder("SplashColumn", ["SP_Water"])
    rows = []
    segs, rings = 18, 24
    for i in range(segs):
        a = 2 * math.pi * i / segs
        row = []
        for j in range(rings):
            h = 11.0 * j / (rings - 1)
            r = 1.15 * (1.0 - h / 11.0) ** 0.55 + 0.12
            r *= 1.0 + 0.16 * math.sin(a * 3 + h * 1.3) + 0.1 * math.sin(a * 5 - h * 2.1)
            row.append(Vector((math.cos(a) * r, math.sin(a) * r, h)))
        rows.append(row)
    b.grid(rows, closed_u=True, mat=0)
    for k in range(9):
        h = rnd.uniform(8.0, 12.0)
        b.sphere(Matrix.Translation((rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), h)), rnd.uniform(0.18, 0.4), 0, segs=8, rings=4)
    parts.append(b.finish(col))
    # クラウン：外へ開く膜ととげ、先の水滴
    b = Builder("SplashCrown", ["SP_Water"])
    spikes = 14
    rows = []
    for i in range(spikes * 4):
        a = 2 * math.pi * i / (spikes * 4)
        spike = max(0.0, math.cos(a * spikes)) ** 6
        row = []
        for j in range(6):
            t = j / 5
            r = 1.0 + 1.25 * t + 0.25 * spike * t
            z = 1.6 * math.sin(t * math.pi * 0.5) + 0.6 * spike * t * t
            row.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
        rows.append(row)
    b.grid(rows, closed_u=True, mat=0)
    for i in range(spikes):
        a = 2 * math.pi * i / spikes
        b.sphere(Matrix.Translation((math.cos(a) * 2.6, math.sin(a) * 2.6, 2.35)), 0.11, 0, segs=8, rings=4)
    parts.append(b.finish(col))
    # 飛び散る水滴（縦に少し長い粒）
    b = Builder("SplashDroplets", ["SP_Water"])
    for i in range(46):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(1.6, 5.0)
        z = rnd.uniform(0.6, 7.5)
        s = rnd.uniform(0.08, 0.22)
        b.sphere(Matrix.Translation((math.cos(a) * r, math.sin(a) * r, z)) @ Matrix.Diagonal((1, 1, 1.6, 1)), s, 0, segs=7, rings=4)
    parts.append(b.finish(col))
    # 泡の輪（ふちがぎざぎざ）
    b = Builder("SplashFoam", ["SP_Foam"])
    rows = []
    for i in range(64):
        a = 2 * math.pi * i / 64
        outer = 3.6 * (1.0 + 0.12 * math.sin(a * 7) + 0.08 * math.sin(a * 13 + 1.0))
        rows.append([Vector((math.cos(a) * 0.4, math.sin(a) * 0.4, 0.03)), Vector((math.cos(a) * 1.9, math.sin(a) * 1.9, 0.05)),
                     Vector((math.cos(a) * outer, math.sin(a) * outer, 0.02))])
    b.grid(rows, closed_u=True, mat=0)
    parts.append(b.finish(col))
    # 波紋（半径 1 の細い輪。Godot が広げる）
    b = Builder("SplashRipple", ["SP_Foam"])
    b.torus(Matrix.Diagonal((1, 1, 0.3, 1)), 1.0, 0.06, 0, segs=48, sides=5)
    parts.append(b.finish(col))
    return parts


# ---------------------------------------------------------------- シーン

def collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    for obj in list(col.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    return col


def purge():
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def add_camera(col, name, eye, target, lens):
    data = bpy.data.cameras.get(name) or bpy.data.cameras.new(name)
    data.lens = lens
    data.clip_start = 0.05
    cam = bpy.data.objects.new(name, data)
    col.objects.link(cam)
    cam.location = eye
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
    return cam


def build_lighting(col):
    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_disc = False
    sky.sun_elevation = math.radians(40)
    sky.sun_rotation = math.radians(200)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.09
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    sun_data = bpy.data.lights.get("LGT_key") or bpy.data.lights.new("LGT_key", "SUN")
    sun_data.energy = 2.6
    sun = bpy.data.objects.new("LGT_key", sun_data)
    col.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(20))


def build_review(col):
    body = Builder("REF_Person", ["REF_Body"], smooth=False)
    body.box(Matrix.Translation((0, 0, -0.75)), (0.5, 0.3, 1.45), 0)
    body.box(Matrix.Translation((0, 0, 0.21)), (0.42, 0.42, 0.42), 0)
    body.finish(col)


def set_keys(objs, values):
    for obj in objs:
        if obj.data.shape_keys is None:
            continue
        for kb in obj.data.shape_keys.key_blocks[1:]:
            kb.value = float(values.get(kb.name, 0.0))


def render(name, cam):
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.filepath = str(PREVIEWS / (name + ".png"))
    bpy.ops.render.render(write_still=True)
    return scene.render.filepath


def main():
    if not bpy.data.filepath or Path(bpy.data.filepath).resolve() != BLEND.resolve():
        raise RuntimeError("parachute.blend を開いてから実行する（今：%s）" % bpy.data.filepath)
    build_materials()
    chute_col = collection("PC_EXPORT")
    splash_col = collection("SP_EXPORT")
    review_col = collection("REF_Review")
    cam_col = collection("CAMERAS")
    light_col = collection("LIGHTING")
    purge()

    canopy = build_canopy(chute_col)
    lines = build_lines(chute_col)
    slider = build_slider(chute_col)
    risers = build_risers(chute_col)
    pilot = build_pilot(chute_col)
    bridle = build_bridle(chute_col)
    bag = build_bag(chute_col)
    container = build_container(chute_col)
    hanky = build_hanky(chute_col)
    add_shape_keys(canopy, "canopy")
    add_shape_keys(lines, "lines")
    add_shape_keys(slider, "slider")
    add_shape_keys(risers, "risers")
    chute_root = bpy.data.objects.new("ChuteRoot", None)
    chute_col.objects.link(chute_root)
    for obj in (canopy, lines, slider, risers, pilot, bridle, bag, container, hanky):
        obj.parent = chute_root
    # 確認用の置き場所：小物は原点のままだと重なるので、確認用に少し離して置く（書き出しは原点に戻す）
    canopy_top = max((v.co.z for v in canopy.data.vertices))
    splash = build_splash(splash_col)
    splash_root = bpy.data.objects.new("SplashRoot", None)
    splash_col.objects.link(splash_root)
    for obj in splash:
        obj.parent = splash_root
    build_review(review_col)
    build_lighting(light_col)

    tris = {}
    for obj in [canopy, lines, slider, risers, pilot, bridle, bag, container, hanky] + splash:
        tris[obj.name] = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    report = {"triangles": tris, "chute_triangles": sum(v for k, v in tris.items() if not k.startswith("Splash")),
              "splash_triangles": sum(v for k, v in tris.items() if k.startswith("Splash")),
              "shape_keys": [kb.name for kb in canopy.data.shape_keys.key_blocks], "canopy_top": round(canopy_top, 3)}

    if DO_EXPORT:
        set_keys([canopy, lines, slider, risers], {})
        for objs, path in (([chute_root] + list(chute_root.children), CHUTE_GLB), ([splash_root] + list(splash_root.children), SPLASH_GLB)):
            bpy.ops.object.select_all(action="DESELECT")
            for o in objs:
                o.hide_set(False)
                o.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_apply=False,
                                      export_yup=True, export_morph=True, export_morph_normal=True, export_cameras=False, export_lights=False)
        LAYOUT.write_text(json.dumps({
            "note": "パラシュート一式の寸法（Godot の座標、原点＝肩のライザーのつけ根）。build_parachute.py が書く",
            "canopy_top": round(canopy_top, 3),
            "canopy_mid": round(Z_MID, 3),
            "bag_center": [BAG_CENTER.x, BAG_CENTER.z, -BAG_CENTER.y],
            "slider_open": SLIDER_Z,
            "link_height": LINK_Z,
            "span": SPAN,
            "shape_keys": KEY_NAMES,
            "grounded": "Grounded の原点＝床（着地した人の %.2f m 後ろに置く）。布の山の中心は原点から後ろへ %.2f m、横の半分 %.2f m" % (0.45, GROUND_BACK, GROUND_HALF_X),
            "pilot_bridle_attach": "PilotChute の原点。全開のときは布の上面の中心（canopy_top）の 0.6 m 上に置く",
            "container_mount": "Container の原点＝背中に当たる面の中心。本体は Godot の −Z（後ろ）へ 0.16 m",
            "hanky": "Hanky の原点＝ひものつけ根。布は +Y の 0.6〜1.05 m、+Z（前）を向く",
        }, ensure_ascii=False, indent=2), encoding="utf-8")

    previews = []
    if DO_RENDER:
        scene = bpy.context.scene
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.resolution_x = 1600
        scene.render.resolution_y = 900
        scene.view_settings.view_transform = "Standard"
        PREVIEWS.mkdir(parents=True, exist_ok=True)
        splash_root.location = (30.0, 0.0, 0.0)
        splash_root.hide_render = False
        hero = add_camera(cam_col, "CAM_Hero", (7.5, -11.0, 2.2), (0.0, 0.0, 3.6), 30)
        below = add_camera(cam_col, "CAM_Below", (2.0, -4.0, -2.5), (0.0, 0.0, 5.0), 24)
        for name, values in (("pc_01_full", {}), ("pc_02_half", {"Half": 1.0}), ("pc_03_packed", {"Packed": 1.0}),
                             ("pc_04_collapsed", {"Collapsed": 1.0}), ("pc_05_breath", {"Breath": 1.0}), ("pc_09_grounded", {"Grounded": 1.0})):
            set_keys([canopy, lines, slider, risers], values)
            # 床に落ちた形は原点＝床なので、肩から下の人形の箱は隠す
            ref_person = bpy.data.objects.get("REF_Person")
            if ref_person is not None:
                ref_person.hide_render = "Grounded" in values
            for o in (bag, pilot, bridle):
                o.hide_render = "Grounded" in values
            # 1 段（袋）：袋とパイロットシュートを袋の位置に置く。ほかは布の上
            if values.get("Packed", 0) > 0.5:
                bag.location = BAG_CENTER
                pilot.location = BAG_CENTER + Vector((0, 0, 1.6))
            else:
                bag.location = Vector((0, 0.0, canopy_top + 0.45))
                pilot.location = Vector((0, 0.0, canopy_top + 1.2))
            bridle.location = Vector((0, 0, canopy_top if values.get("Packed", 0) < 0.5 else BAG_CENTER.z))
            hanky.location = Vector((1.2, -0.3, -0.4))
            previews.append(render(name, hero))
        set_keys([canopy, lines, slider, risers], {})
        for o in (bag, pilot, bridle):
            o.hide_render = False
        previews.append(render("pc_06_below", below))
        # 小物の寄り：人形の箱を隠し、コンテナ（背中の面をカメラへ）・袋・パイロットシュート・ハンカチを並べる
        person = bpy.data.objects.get("REF_Person")
        if person is not None:
            person.hide_render = True
        canopy.hide_render = lines.hide_render = slider.hide_render = risers.hide_render = bridle.hide_render = True
        detail = add_camera(cam_col, "CAM_Detail", (0.2, -3.6, 1.0), (0.2, 0.0, 0.55), 40)
        container.location = (-0.75, 0.0, 0.5)
        container.rotation_euler = (0.0, 0.0, math.pi)
        bag.location = (-0.05, 0.0, 0.5)
        pilot.location = (0.75, 0.3, -0.25)
        hanky.location = (1.3, 0.0, -0.3)
        previews.append(render("pc_07_parts", detail))
        container.rotation_euler = (0.0, 0.0, 0.0)
        canopy.hide_render = lines.hide_render = slider.hide_render = risers.hide_render = bridle.hide_render = False
        if person is not None:
            person.hide_render = False
        splash_cam = add_camera(cam_col, "CAM_Splash", (30.0 + 9.0, -15.0, 3.5), (30.0, 0.0, 4.0), 32)
        sea = bpy.data.objects.get("REF_SeaPlane")
        if sea is None:
            bpy.ops.mesh.primitive_plane_add(size=80, location=(30.0, 0.0, 0.0))
            sea = bpy.context.active_object
            sea.name = "REF_SeaPlane"
            for c in sea.users_collection:
                c.objects.unlink(sea)
            review_col.objects.link(sea)
            sea.data.materials.append(MAT["REF_Sea"])
        previews.append(render("pc_08_splash", splash_cam))
        # 書き出しの置き場所へ戻す
        for obj in (bag, pilot, bridle, container, hanky):
            obj.location = (0, 0, 0)
        splash_root.location = (0, 0, 0)
        scene.camera = hero
    report["previews"] = previews
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if DO_SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    return report


if __name__ == "__main__":
    RESULT = main()

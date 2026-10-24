"""台座の横の水路の仕掛け（docs/sudden_death_v2/c130_float.md 第4章、skygate_build_plan.md W2）：
スタンドを持ち上げる白い格子の塔（4 本立てる 1 本ぶん）と、床の端の昇降台（デッキ・壁のレール・回転灯）。

ライブの Blender で実行する（ヘッドレスで代替しない。AGENTS.md）。
    import runpy, sys
    sys.argv = ["blender", "--"]      # "--no-export" で書き出さない、"--no-save" で保存しない
    runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/sudden_death/stage_gate/source/blender/build_stage_gate.py", run_name="__main__")
開いているファイルが stage_gate.blend でなければ、新しいファイルにしてこの名前で保存してから作る。

座標：Blender の Z が上（m）。Godot では (x, z, −y)。
- SG_Tower：原点＝塔の下端の中心。+Z へ TOWER_HEIGHT。四角い断面（TOWER_W 四方）の格子。頂上に滑車と箱
- 昇降台（2026-10-19 作り直し。c130_float.md 第10章）：床の横の壁に付いた「折りたたみのデッキ」。しまっているときはデッキが
  床の縁から下へぶら下がって壁に沿い（上面が外を向く。手すりは上面に寝かせてある）、出すときは付け根の軸で外へ 90° 起きて
  床と同じ高さの水平になり、手すりが起きる。2 本の縦のレールに沿って、台車ごと貨物室の床の高さまで下りる。
  - SG_LiftDeck：デッキ。原点＝付け根の軸（デッキの下面の壁側の辺の中心）。+X へ DECK_LEN、横（Blender Y）に ±DECK_HALF_Z、上面は +Z の DECK_T
  - SG_LiftHandrail：手すり 1 本。原点＝付け根の軸（デッキの上面の壁側の端）。+X に沿って、柱は +Z へ RAIL_H。左右 2 本を同じ形で置き、
    X まわりに回して寝かせる
  - SG_LiftCarriage：レールの中を上下する台車 2 つとデッキの軸の受け。原点はデッキと同じ軸
  - SG_LiftFrame：壁のレール 2 本・取り付けの金具・回転灯の腕（動かない）。原点＝床の上面の高さの壁の面
  - SG_Beacon：回転灯の光る部分（Godot が光らせる）
"""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
ASSET = HERE.parents[1]
GLB = ASSET / "stage_gate.glb"
LAYOUT = ASSET / "stage_gate_layout.json"
BLEND = HERE / "stage_gate.blend"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
DO_SAVE = "--no-save" not in ARGS

TOWER_HEIGHT = 40.0       # 海の中から、持ち上げたスタンドの上まで
TOWER_W = 1.8
POST_R = 0.14
BAY = 2.4                 # 横の段の間隔
# 昇降台（Godot の座標。壁の面 x＝0、床の上面 y＝0、台座の z ＝ 0）
DECK_LEN = 4.36           # 付け根の軸（壁から 0.04 m）から外の端まで。外の端はスロープの端に 0.25 m 重なる
DECK_HALF_Z = 1.9         # 幅 3.8 m（スロープの幅 3.1 m より広い）
DECK_T = 0.26             # 厚み（上の板 0.06 ＋ 梁）
HINGE_X = 0.04            # 付け根の軸の壁からの出
RAIL_H = 1.0              # 手すりの高さ
RAIL_Z = 1.80             # 手すりの |横|
TRACK_Z = 2.2             # 縦のレールの |横|（中心）
TRACK_W = 0.26
TRACK_D = 0.16
TRACK_TOP = -0.03         # 床の上面より少し下から（上から見えないように）
RAIL_LENGTH = 6.9         # レールの長さ（床の上面から下へ）
BEACON_Z = 2.62
BEACON_Y = -0.52
TOE_LEN = 0.32            # 外の端のスロープを受ける一段低い所の長さ
TOE_DROP = 0.30           # その深さ（スロープの先の下面は上面から 0.24〜0.28 m 下。floatplane_c130.glb で測った）


def material(name, color, rough=0.55, metal=0.0, emit=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if p is None:
        nt.nodes.clear()
        p = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(p.outputs["BSDF"], out.inputs["Surface"])
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit is not None:
        p.inputs["Emission Color"].default_value = (*emit, 1.0)
        p.inputs["Emission Strength"].default_value = 3.0
    return m


MATS = {}


def build_materials():
    MATS["white"] = material("SG_White", (0.93, 0.94, 0.96), 0.45)
    MATS["blue"] = material("SG_Blue", (0.11, 0.24, 0.52), 0.5)
    MATS["steel"] = material("SG_Steel", (0.42, 0.45, 0.50), 0.4, 0.6)
    MATS["dark"] = material("SG_Dark", (0.13, 0.14, 0.17), 0.6)
    MATS["yellow"] = material("SG_Yellow", (0.98, 0.78, 0.10), 0.5)
    MATS["black"] = material("SG_Black", (0.05, 0.05, 0.06), 0.6)
    MATS["grip"] = material("SG_Grip", (0.30, 0.32, 0.36), 0.85)
    MATS["beacon"] = material("SG_Beacon", (1.0, 0.55, 0.12), 0.3, emit=(1.0, 0.5, 0.1))
    MATS["cable"] = material("SG_Cable", (0.08, 0.08, 0.09), 0.5, 0.4)


class Builder:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, key):
        m = MATS[key]
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _add(self, other, matrix, mat):
        idx = self.mi(mat)
        other.transform(matrix)
        mesh = bpy.data.meshes.new("_tmp")
        other.to_mesh(mesh)
        other.free()
        start = len(self.bm.faces)
        self.bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
        self.bm.faces.ensure_lookup_table()
        for f in self.bm.faces[start:]:
            f.material_index = idx

    def box(self, center, size, mat, rot=None):
        b = bmesh.new()
        bmesh.ops.create_cube(b, size=1.0)
        m = Matrix.Translation(center) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        self._add(b, m, mat)

    def cyl(self, a, b_, r, mat, segs=8):
        a, b_ = Vector(a), Vector(b_)
        d = b_ - a
        length = d.length
        if length < 1e-5:
            return
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=length)
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        self._add(bm, Matrix.Translation((a + b_) * 0.5) @ rot, mat)

    def finish(self, col):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        for p in mesh.polygons:
            p.use_smooth = False
        obj = bpy.data.objects.new(self.name, mesh)
        col.objects.link(obj)
        return obj


def build_tower(col):
    b = Builder("SG_Tower")
    h = TOWER_HEIGHT
    w = TOWER_W * 0.5
    corners = [(-w, -w), (w, -w), (w, w), (-w, w)]
    for x, y in corners:
        b.cyl((x, y, 0.0), (x, y, h), POST_R, "white", 10)
    levels = int(h / BAY)
    for k in range(levels + 1):
        z = min(k * BAY, h - 0.2)
        stripe = "blue" if k % 4 == 0 else "white"
        for i in range(4):
            (x0, y0), (x1, y1) = corners[i], corners[(i + 1) % 4]
            b.cyl((x0, y0, z), (x1, y1, z), 0.07, stripe, 6)
        if k < levels:
            z1 = min((k + 1) * BAY, h - 0.2)
            for i in range(4):
                (x0, y0), (x1, y1) = corners[i], corners[(i + 1) % 4]
                if k % 2 == 0:
                    b.cyl((x0, y0, z), (x1, y1, z1), 0.05, "white", 6)
                else:
                    b.cyl((x1, y1, z), (x0, y0, z1), 0.05, "white", 6)
    # 頂上の機械の箱・滑車・ケーブル、中ほどの青い帯の板
    b.box((0.0, 0.0, h + 0.55), (TOWER_W + 0.6, TOWER_W + 0.6, 1.1), "blue")
    b.box((0.0, 0.0, h + 1.25), (TOWER_W + 0.2, TOWER_W + 0.2, 0.3), "white")
    for s in (-1, 1):
        rot = Matrix.Rotation(math.pi / 2, 4, "Y")
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.65, radius2=0.65, depth=0.18)
        b._add(bm, Matrix.Translation((s * 0.35, -w - 0.35, h + 0.6)) @ rot, "steel")
    b.cyl((0.0, -w - 0.95, h + 0.6), (0.0, -w - 0.95, h - 16.0), 0.05, "cable", 6)
    for z in (h * 0.33, h * 0.66):
        b.box((0.0, -w - 0.02, z), (TOWER_W * 0.9, 0.06, 0.8), "blue")
    # 足もとの台（海の中）
    b.box((0.0, 0.0, -0.6), (TOWER_W + 0.8, TOWER_W + 0.8, 1.2), "steel")
    return b.finish(col)


def build_deck(col):
    """昇降台のデッキ。原点＝付け根の軸（下面の壁側の辺の中心）。+X が外（海）、Y が横、上面は +Z の DECK_T。"""
    b = Builder("SG_LiftDeck")
    L = DECK_LEN
    hz = DECK_HALF_Z
    top = DECK_T
    plate = 0.06
    # 上の板（すべり止めの灰色）
    b.box(((L - TOE_LEN) * 0.5, 0.0, top - plate * 0.5), (L - TOE_LEN, hz * 2.0, plate), "grip")
    # 外の端：スロープの先（ランプトウ）を受ける一段低い鋼の受け（上面から TOE_DROP 下）。スロープの上面とデッキの上面がそろい、
    # スロープの先がデッキに TOE_LEN − 0.07 m 重なって載る（c130_float.md 第10章）
    pocket = top - TOE_DROP
    b.box((L - TOE_LEN * 0.5, 0.0, pocket - 0.03), (TOE_LEN, hz * 2.0 - 0.3, 0.06), "steel")
    b.box((L - TOE_LEN + 0.02, 0.0, (pocket + top) * 0.5 - 0.03), (0.04, hz * 2.0 - 0.3, TOE_DROP + 0.06), "steel")
    for s_ in (-1, 1):
        b.box((L - TOE_LEN * 0.5, s_ * (hz - 0.08), (pocket + top) * 0.5 - 0.03), (TOE_LEN, 0.16, TOE_DROP + 0.06), "steel")
    # 段の角の黄色と黒の縞
    nt = int((hz * 2.0 - 0.3) / 0.4)
    for i in range(nt):
        y = -(hz - 0.15) + (i + 0.5) * ((hz * 2.0 - 0.3) / nt)
        b.box((L - TOE_LEN + 0.045, y, top - 0.08), (0.01, (hz * 2.0 - 0.3) / nt - 0.01, 0.14), "yellow" if i % 2 == 0 else "black")
    # 黄色と黒の縞の縁（左右の辺と壁側の辺）
    stripe_w = 0.22
    run = L - TOE_LEN
    n2 = int(run / 0.45)
    for s_ in (-1, 1):
        for i in range(n2):
            x = (i + 0.5) * (run / n2)
            b.box((x, s_ * (hz - stripe_w * 0.5), top + 0.008), (run / n2 - 0.01, stripe_w, 0.02), "yellow" if i % 2 == 0 else "black")
    n = int(hz * 2.0 / 0.45)
    for i in range(n):
        y = -hz + (i + 0.5) * (hz * 2.0 / n)
        b.box((stripe_w * 0.5, y, top + 0.008), (stripe_w, hz * 2.0 / n - 0.01, 0.02), "yellow" if i % 2 == 0 else "black")
    # すべり止めの横線
    for i in range(1, 10):
        x = 0.3 + (run - 0.45) * i / 10.0
        b.box((x, 0.0, top + 0.004), (0.035, hz * 2.0 - 0.6, 0.012), "dark")
    # 下の梁（縦 3 本・横 5 本）
    beam_h = top - plate
    for y in (-hz + 0.12, 0.0, hz - 0.12):
        b.box((run * 0.5, y, beam_h * 0.5), (run - 0.1, 0.12, beam_h), "steel")
    for i in range(5):
        x = 0.08 + (run - 0.2) * i / 4.0
        b.box((x, 0.0, beam_h * 0.55), (0.1, hz * 2.0 - 0.1, beam_h * 0.7), "steel")
    # 付け根の軸の受け（壁側の角）
    for s_ in (-1, 1):
        b.cyl((0.0, s_ * (hz - 0.16), 0.0), (0.0, s_ * (hz + 0.0), 0.0), 0.075, "dark", 12)
        b.box((0.09, s_ * (hz - 0.08), 0.05), (0.18, 0.16, 0.12), "dark")
    # 手すりの受け（柱の足もと）
    for s_ in (-1, 1):
        for x in (0.2, L * 0.5, L - 0.2):
            b.box((x, s_ * RAIL_Z, top + 0.03), (0.12, 0.1, 0.06), "dark")
    # 手すりの柱の足もとを受ける縁（受けの所だけ上面の高さまで）
    for s_ in (-1, 1):
        b.box((L - TOE_LEN * 0.5, s_ * RAIL_Z, top - 0.15), (TOE_LEN, 0.12, 0.3), "steel")
    return b.finish(col)


def build_handrail(col):
    """手すり 1 本。原点＝付け根の軸（デッキの上面の壁側の端）。+X に沿い、柱は +Z へ。"""
    b = Builder("SG_LiftHandrail")
    L = DECK_LEN
    h = RAIL_H
    xs = (0.2, L * 0.5, L - 0.2)
    for x in xs:
        b.cyl((x - 0.05, 0.0, 0.03), (x + 0.05, 0.0, 0.03), 0.04, "dark", 10)   # 蝶番
        b.cyl((x, 0.0, 0.03), (x, 0.0, h), 0.04, "yellow", 8)
    b.cyl((xs[0], 0.0, h), (xs[-1], 0.0, h), 0.045, "yellow", 8)
    b.cyl((xs[0], 0.0, h * 0.52), (xs[-1], 0.0, h * 0.52), 0.032, "yellow", 8)
    return b.finish(col)


def build_carriage(col):
    """レールの中の台車 2 つと、デッキの付け根の軸。原点はデッキと同じ軸（壁から HINGE_X、床の上面から DECK_T 下）。"""
    b = Builder("SG_LiftCarriage")
    cx = TRACK_D * 0.5 - HINGE_X          # レールの中心の x（軸から）
    for s_ in (-1, 1):
        # 台車（レールの溝の中を走る）
        b.box((cx - 0.01, s_ * TRACK_Z, -0.15), (0.11, 0.18, 0.62), "dark")
        b.box((cx + 0.06, s_ * TRACK_Z, -0.15), (0.03, 0.24, 0.5), "steel")
        # 軸
        b.cyl((0.0, s_ * (DECK_HALF_Z - 0.02), 0.0), (0.0, s_ * (TRACK_Z + 0.04), 0.0), 0.05, "steel", 12)
        b.cyl((0.0, s_ * (TRACK_Z - 0.16), 0.0), (0.0, s_ * (TRACK_Z - 0.1), 0.0), 0.09, "yellow", 14)
    return b.finish(col)


def build_frame(col):
    """壁の縦のレール 2 本・取り付けの金具・回転灯の腕。原点＝床の上面の高さの壁の面（x ＝ 0 から外へ +X）。"""
    b = Builder("SG_LiftFrame")
    top = TRACK_TOP
    bot = -RAIL_LENGTH
    length = top - bot
    for s_ in (-1, 1):
        y = s_ * TRACK_Z
        # 溝形の鋼（背板と両側のつば）
        b.box((0.02, y, (top + bot) * 0.5), (0.04, TRACK_W, length), "dark")
        for e in (-1, 1):
            b.box((TRACK_D * 0.5, y + e * (TRACK_W * 0.5 - 0.02), (top + bot) * 0.5), (TRACK_D, 0.04, length), "dark")
            # つばの表の黄色と黒の縞
            n = int(length / 0.5)
            for i in range(n):
                z = top - (i + 0.5) * (length / n)
                b.box((TRACK_D + 0.004, y + e * (TRACK_W * 0.5 - 0.02), z), (0.01, 0.042, length / n - 0.015), "yellow" if i % 2 == 0 else "black")
        # 下の止め
        b.box((TRACK_D * 0.5, y, bot - 0.05), (TRACK_D + 0.04, TRACK_W + 0.06, 0.1), "steel")
        # 壁への取り付けの金具
        k = int(length / 1.15)
        for i in range(k + 1):
            z = top - 0.25 - i * (length - 0.5) / max(k, 1)
            for e in (-1, 1):
                b.box((0.015, y + e * (TRACK_W * 0.5 + 0.07), z), (0.03, 0.12, 0.22), "steel")
                b.cyl((0.03, y + e * (TRACK_W * 0.5 + 0.07), z), (0.05, y + e * (TRACK_W * 0.5 + 0.07), z), 0.025, "dark", 6)
        # 回転灯の腕と台
        by = s_ * BEACON_Z
        b.box((0.03, by, BEACON_Y), (0.06, 0.22, 0.3), "steel")
        b.box((0.18, by, BEACON_Y - 0.03), (0.3, 0.08, 0.06), "steel")
        b.cyl((0.3, by, BEACON_Y), (0.3, by, BEACON_Y + 0.05), 0.12, "dark", 14)
    return b.finish(col)


def build_beacon(col):
    b = Builder("SG_Beacon")
    for s_ in (-1, 1):
        b.cyl((0.3, s_ * BEACON_Z, BEACON_Y + 0.05), (0.3, s_ * BEACON_Z, BEACON_Y + 0.22), 0.1, "beacon", 14)
    return b.finish(col)


def main():
    if not bpy.data.filepath or Path(bpy.data.filepath).resolve() != BLEND.resolve():
        bpy.ops.wm.read_homefile(use_empty=True)
        BLEND.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    build_materials()
    col = bpy.data.collections.get("SG_EXPORT") or bpy.data.collections.new("SG_EXPORT")
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    objs = [build_tower(col), build_deck(col), build_handrail(col), build_carriage(col), build_frame(col), build_beacon(col)]
    # 確認用に並べる（書き出しは原点に戻す）
    offsets = [(0, 0, 0), (6, 0, 6), (6, 0, 6 + DECK_T), (6, 0, 6), (6, 0, 6), (6, 0, 6)]
    tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs}
    if DO_EXPORT:
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.location = (0, 0, 0)
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_cameras=False, export_lights=False)
        LAYOUT.write_text(json.dumps({
            "note": "台座の横の水路の仕掛けの寸法（Godot の座標）。build_stage_gate.py が書く",
            "tower_height": TOWER_HEIGHT, "tower_width": TOWER_W,
            "deck_len": DECK_LEN, "deck_half_z": DECK_HALF_Z, "deck_thickness": DECK_T, "hinge_x": HINGE_X,
            "rail_h": RAIL_H, "rail_z": RAIL_Z, "track_z": TRACK_Z, "track_d": TRACK_D, "rail_length": RAIL_LENGTH, "toe_len": TOE_LEN, "toe_drop": TOE_DROP,
            "beacon": [0.3, BEACON_Y + 0.13, BEACON_Z], "triangles": tris,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
    for o, off in zip(objs, offsets):
        o.location = off
    if DO_SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    return {"triangles": tris, "glb": str(GLB)}


if __name__ == "__main__":
    print(main())

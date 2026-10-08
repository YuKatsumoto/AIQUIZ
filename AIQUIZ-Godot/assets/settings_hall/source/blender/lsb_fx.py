"""表情の小道具（docs/lecture_hall_plan.md の 1f）: 漫符と鼻ちょうちん。lecture_fx.glb に書き出し、
Godot が必要なときに人物の頭の上へ出す（第 3 段階）。

漫符は艶のある樹脂のフィギュアのような立体（文字は Noto Sans JP の字形を押し出して面取り）:
  FX_Exclaim（！ 黄）・FX_Question（？ 青）・FX_Anger（怒りマーク 赤）・FX_Sweat（汗 水色の透け）・
  FX_Dots（… 3 つの玉）・FX_Note（♪ ピンク）・FX_Bulb（電球: ガラスと口金、光る芯）・FX_NoseBubble（鼻ちょうちん）
各オブジェクトの原点は下端の中央（頭の上に置く点）、正面は Godot -z（カメラ）。単色の材質のまま（焼かない）。
"""
from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

FONT = Path(__file__).resolve().parents[4] / "resources" / "fonts" / "NotoSansJP-Bold.otf"
COL_FX = "LS_FX"


def _mat(name, color, rough=0.18, metal=0.0, alpha=1.0, emit=None, emit_strength=0.0, coat=0.6):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Alpha"].default_value = alpha
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = 0.05
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = emit
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1.0:
        m.surface_render_method = "BLENDED" if hasattr(m, "surface_render_method") else m.surface_render_method
        try:
            m.blend_method = "BLEND"
        except AttributeError:
            pass
    return m


def _lin(hexcode):
    c = hexcode.lstrip("#")
    out = []
    for i in (0, 2, 4):
        v = int(c[i:i + 2], 16) / 255.0
        out.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def _glyph(col, name, text, size, extrude, bevel, mat):
    """文字の字形を押し出した立体（XZ 平面に立てる。正面 = Blender +Y = Godot -z）。原点 = 下端の中央。"""
    curve = bpy.data.curves.new(name + "_txt", "FONT")
    curve.body = text
    curve.font = bpy.data.fonts.load(str(FONT), check_existing=True)
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = bevel
    curve.bevel_resolution = 3
    curve.align_x = "CENTER"
    curve.resolution_u = 8
    obj = bpy.data.objects.new(name + "_txt", curve)
    col.objects.link(obj)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(curve)
    # 字形は XY 平面（Z が厚み）→ 立てる: X はそのまま、Y → Z（上）、Z → -Y（奥）。正面を +Y へ
    me.transform(Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    zs = [v.co.z for v in me.vertices]
    me.transform(Matrix.Translation((0.0, 0.0, -min(zs))))
    me.name = name
    out = bpy.data.objects.new(name, me)
    col.objects.link(out)
    out.data.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(35.0))
    return out


def _from_bm(col, name, bm, mats):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    for m in mats:
        obj.data.materials.append(m)
    return obj


def _anger(col, mat):
    """怒りマーク: 中心へ向かって反った 4 本の弧（十字の血管）。"""
    bm = bmesh.new()
    for k in range(4):
        a0 = math.pi * 0.25 + k * math.pi * 0.5
        center = Vector((math.cos(a0) * 0.11, 0.0, math.sin(a0) * 0.11 + 0.14))
        for s in range(18):
            t = s / 17.0
            ang = a0 + math.pi - 0.9 + 1.8 * t
            p = center + Vector((math.cos(ang) * 0.075, 0.0, math.sin(ang) * 0.075))
            sph = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.022 * (1.0 - 0.35 * abs(t - 0.5) * 2))
            bmesh.ops.translate(bm, vec=p, verts=sph["verts"])
    obj = _from_bm(col, "FX_Anger", bm, [mat])
    return obj


def _sweat(col, mat):
    """汗のしずく: 上がとがった涙形（回転体）。"""
    bm = bmesh.new()
    seg = 32
    prof = []
    for i in range(21):
        t = i / 20.0
        z = t * 0.2
        r = 0.055 * math.sin(math.pi * min(1.0, (1.0 - t) * 1.25)) ** 0.8 * (1.0 - t) ** 0.35 if t < 0.999 else 0.0
        prof.append((r, z))
    rings = []
    for r, z in prof:
        rings.append([bm.verts.new((r * math.cos(math.tau * i / seg), r * 0.6 * math.sin(math.tau * i / seg), z))
                      for i in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return _from_bm(col, "FX_Sweat", bm, [mat])


def _dots(col, mat):
    bm = bmesh.new()
    for k in range(3):
        sph = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.03)
        bmesh.ops.translate(bm, vec=(-0.09 + k * 0.09, 0.0, 0.03), verts=sph["verts"])
    return _from_bm(col, "FX_Dots", bm, [mat])


def _bulb(col, glass, base, filament):
    """電球: ガラスの球（少し透ける）、ねじの口金、光る芯。"""
    bm = bmesh.new()
    seg = 32
    prof = [(0.0, 0.0), (0.025, 0.002), (0.028, 0.01)]
    for i in range(7):
        prof.append((0.028 if i % 2 == 0 else 0.031, 0.012 + i * 0.008))
    prof += [(0.03, 0.07), (0.04, 0.09), (0.07, 0.14), (0.075, 0.18), (0.06, 0.225), (0.03, 0.25), (0.0, 0.255)]
    rings = []
    for r, z in prof:
        rings.append([bm.verts.new((r * math.cos(math.tau * i / seg), r * math.sin(math.tau * i / seg), z)) for i in range(seg)])
    for idx, (a, b) in enumerate(zip(rings, rings[1:])):
        for i in range(seg):
            f = bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
            f.material_index = 1 if idx < 10 else 0
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    fil = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.022)
    bmesh.ops.translate(bm, vec=(0.0, 0.0, 0.16), verts=fil["verts"])
    for f in {f for v in fil["verts"] for f in v.link_faces}:
        f.material_index = 2
    return _from_bm(col, "FX_Bulb", bm, [glass, base, filament])


def _nose_bubble(col, mat):
    """鼻ちょうちん: 少しつぶれた薄い球（原点 = 鼻に付く点、球は +X 側へふくらむ）。Godot が大きさを呼吸で変える。"""
    bm = bmesh.new()
    sph = bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=20, radius=0.07)
    for v in sph["verts"]:
        v.co = Vector((v.co.x * 1.05 + 0.065, v.co.y * 0.95, v.co.z * 0.92))
    return _from_bm(col, "FX_NoseBubble", bm, [mat])


def build(scene):
    col = bpy.data.collections.get(COL_FX) or bpy.data.collections.new(COL_FX)
    if col.name not in scene.collection.children:
        scene.collection.children.link(col)
    mats = {
        "yellow": _mat("LSF_Yellow", _lin("#FFC928"), 0.15),
        "blue": _mat("LSF_Blue", _lin("#2F7DE1"), 0.15),
        "red": _mat("LSF_Red", _lin("#E53935"), 0.18),
        "sweat": _mat("LSF_Sweat", _lin("#8FD3FF"), 0.04, alpha=0.75, coat=1.0),
        "dark": _mat("LSF_Dark", _lin("#2A2D33"), 0.25),
        "pink": _mat("LSF_Pink", _lin("#FF6FA8"), 0.15),
        "glass": _mat("LSF_BulbGlass", _lin("#FFF4C8"), 0.05, alpha=0.55, emit=_lin("#FFE680"), emit_strength=1.5,
                      coat=1.0),
        "base": _mat("LSF_BulbBase", _lin("#B9BEC4"), 0.25, metal=1.0, coat=0.0),
        "filament": _mat("LSF_BulbFilament", _lin("#FFD54F"), 0.3, emit=_lin("#FFC23A"), emit_strength=8.0, coat=0.0),
        "bubble": _mat("LSF_Bubble", _lin("#DDF2FF"), 0.02, alpha=0.32, coat=1.0),
    }
    objs = [
        _glyph(col, "FX_Exclaim", "！", 0.32, 0.03, 0.008, mats["yellow"]),
        _glyph(col, "FX_Question", "？", 0.32, 0.03, 0.008, mats["blue"]),
        _anger(col, mats["red"]),
        _sweat(col, mats["sweat"]),
        _dots(col, mats["dark"]),
        _glyph(col, "FX_Note", "♪", 0.3, 0.03, 0.008, mats["pink"]),
        _bulb(col, mats["glass"], mats["base"], mats["filament"]),
        _nose_bubble(col, mats["bubble"]),
    ]
    # 確認用に並べる（書き出しは原点を足元にしたまま、位置はシーンの確認用）
    for k, o in enumerate(objs):
        o.location = Vector((-6.0 + k * 0.45, 0.0, 3.0))
    return objs

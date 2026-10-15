"""操縦士ハテナの素材（オンライン対戦のマッチング演出、計画書 M2）をライブの Blender で作って書き出す。

aiquiz_mascot.blend を開いて実行する（Higgsfield の Blender 連携 bl_execute から runpy）：
  import runpy, sys
  sys.argv = ["blender", "--"]          # 書き出さないなら ["blender", "--", "--no-export"]
  runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/build_pilot.py", run_name="__main__")

作るもの（mascot_model.glb は変えない。審判・ノコギリの役に影響しないよう、別の GLB にする）：
  1. 動き（Rig のアクション）：Pilot_SitIdle（3.2 秒のループ）、Pilot_Wave（1.25 秒のループ）、Pilot_Point（前を指して止まる）、
     Pilot_Steer（2.6 秒のループ）。姿勢は骨の向き（ハテナの空間、glTF：前が +Z）で決め、設計図（artifacts/heli_blueprint/cast.py の
     HATENA_SEATED）と同じ「ぬいぐるみ座り」が基本。→ ../mascot_pilot.glb（骨組みとアクションだけ。メッシュなし）
  2. ヘッドセット HERO_PilotHeadset（頭の楕円体に沿うバンド、両耳のカップ、右のマイク）→ ../pilot_headset.glb（ハテナの空間）
  3. 軽い版 HERO_Mascot_LOD（約 8,000 三角形。Decimate で減らし、ウェイトはそのまま）→ ../mascot_model_lod.glb
最後の行 PILOT_BUILD {...} に結果。.blend の保存は呼ぶ側で行う（AGENTS.md）。
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = Path(__file__).resolve().parent
ASSET = HERE.parent
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
FPS = 24
LOD_TRIANGLES = 8000

# 骨の向き（ハテナの空間 = glTF：x 左右、y 上、z 前）。設計図の HATENA_SEATED
SEATED = {
    "DEF-thigh.L": (0.05, 0.16, 1.0), "DEF-thigh.R": (-0.05, 0.16, 1.0),
    "DEF-shin.L": (0.04, 0.02, 1.0), "DEF-shin.R": (-0.04, 0.02, 1.0),
    "DEF-foot.L": (0.0, 0.95, 0.30), "DEF-foot.R": (0.0, 0.95, 0.30),
    "DEF-upper_arm.L": (0.42, -0.30, 0.86), "DEF-upper_arm.R": (-0.42, -0.30, 0.86),
    "DEF-forearm.L": (0.05, 0.12, 1.0), "DEF-forearm.R": (-0.05, 0.12, 1.0),
}
WAVE_UPPER = (0.75, 0.62, 0.20)
WAVE_FORE = (0.25, 1.0, 0.15)
POINT_UPPER = (-0.22, 0.30, 1.0)
POINT_FORE = (-0.10, 0.36, 1.0)

# 体（楕円体）の中心と半径（Blender の座標。H_Body の大きさ）
BODY_C = Vector((0.0, 0.0, 1.03))
BODY_R = Vector((0.558, 0.479, 0.549))


def g2b(v):
    """ハテナの空間（glTF、Y 上・前 +Z）→ Blender のアーマチュア空間（Z 上・前 -Y）。"""
    return Vector((v[0], -v[2], v[1]))


# --- 動き ----------------------------------------------------------------------------
def _depth(pb):
    d = 0
    while pb.parent is not None:
        d += 1
        pb = pb.parent
    return d


def pose_aims(rig, aims: dict, head_nod: float = 0.0):
    """骨を親から順に、根元から先（骨の +Y）がアーマチュア空間の aims の向きを向くよう回す。"""
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    head = rig.pose.bones.get("DEF-head")
    if head is not None and head_nod != 0.0:
        head.rotation_quaternion = Quaternion(Vector((1.0, 0.0, 0.0)), head_nod)
    bpy.context.view_layer.update()
    for pb in sorted(rig.pose.bones, key=_depth):
        aim = aims.get(pb.name)
        if aim is None:
            continue
        m = pb.matrix.copy()
        cur = m.to_3x3().col[1].normalized()
        want = g2b(aim).normalized()
        rot = cur.rotation_difference(want).to_matrix()
        new = (rot @ m.to_3x3()).to_4x4()
        new.translation = m.translation
        pb.matrix = new
        bpy.context.view_layer.update()


def key_all(rig, frame):
    for pb in rig.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)


def _mix(a, b, w):
    va, vb = Vector(a).normalized(), Vector(b).normalized()
    return tuple(va.lerp(vb, w))


def make_action(rig, name, seconds, pose_at, loop=True, step=2):
    """pose_at(t) → (aims, head_nod)。seconds の長さを step フレームおきに記録する。"""
    old = bpy.data.actions.get(name)
    if old is not None:
        bpy.data.actions.remove(old)
    if rig.animation_data is None:
        rig.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    frames = max(2, round(seconds * FPS))
    for f in list(range(0, frames, step)) + [frames]:
        t = f / FPS
        aims, nod = pose_at(t if not loop or f < frames else 0.0)
        pose_aims(rig, aims, nod)
        key_all(rig, f + 1)
    action.frame_range = (1, frames + 1)
    try:
        action.use_cyclic = loop
    except AttributeError:
        pass
    rig.animation_data.action = None
    return action


def build_actions(rig):
    def sit_idle(t):
        return dict(SEATED), math.radians(1.5) * math.sin(2 * math.pi * t / 3.2)

    def wave(t):
        a = dict(SEATED)
        flap = 0.35 * math.sin(2 * math.pi * t / 0.625)
        a["DEF-upper_arm.L"] = WAVE_UPPER
        a["DEF-forearm.L"] = (WAVE_FORE[0] + flap, WAVE_FORE[1], WAVE_FORE[2])
        return a, math.radians(-4.0)

    def point(t):
        a = dict(SEATED)
        w = min(1.0, t / 0.15)
        a["DEF-upper_arm.R"] = _mix(SEATED["DEF-upper_arm.R"], POINT_UPPER, w)
        a["DEF-forearm.R"] = _mix(SEATED["DEF-forearm.R"], POINT_FORE, w)
        return a, math.radians(-2.0)

    def steer(t):
        a = dict(SEATED)
        turn = 0.12 * math.sin(2 * math.pi * t / 2.6)
        fl, fr = a["DEF-forearm.L"], a["DEF-forearm.R"]
        a["DEF-forearm.L"] = (fl[0], fl[1] + turn, fl[2])
        a["DEF-forearm.R"] = (fr[0], fr[1] - turn, fr[2])
        return a, math.radians(1.0) * math.sin(2 * math.pi * t / 2.6)

    acts = [make_action(rig, "Pilot_SitIdle", 3.2, sit_idle), make_action(rig, "Pilot_Wave", 1.25, wave),
            make_action(rig, "Pilot_Point", 0.6, point, loop=False), make_action(rig, "Pilot_Steer", 2.6, steer)]
    pose_aims(rig, dict(SEATED))
    return acts


# --- ヘッドセット ----------------------------------------------------------------------
def _material(name, rgb, rough=0.45, metal=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return mat


def _surface(dir3: Vector, lift: float) -> Vector:
    """楕円体の中心から dir3 の向きの表面の点（lift だけ外へ）。"""
    d = dir3.normalized()
    s = 1.0 / math.sqrt((d.x / BODY_R.x) ** 2 + (d.y / BODY_R.y) ** 2 + (d.z / BODY_R.z) ** 2)
    return BODY_C + d * (s + lift)


def build_headset():
    old = bpy.data.objects.get("HERO_PilotHeadset")
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    for me in [m for m in bpy.data.meshes if m.name.startswith("HERO_PilotHeadset") and m.users == 0]:
        bpy.data.meshes.remove(me)
    navy = _material("Headset_Navy", (0.07, 0.10, 0.18), 0.5)
    orange = _material("Headset_Orange", (0.95, 0.45, 0.10), 0.4)
    cushion = _material("Headset_Cushion", (0.15, 0.16, 0.18), 0.85)
    metal = _material("Headset_Metal", (0.62, 0.65, 0.70), 0.3, 0.6)
    me = bpy.data.meshes.new("HERO_PilotHeadset")
    bm = bmesh.new()
    mats = [navy, orange, cushion, metal]

    def tag(faces, idx):
        for f in faces:
            f.material_index = idx

    # 耳のカップ（X の向きの円柱。外側は紺、ふちはオレンジ、内側はクッション）
    ear_z = 1.10
    for side in (1, -1):
        x0 = side * (BODY_R.x - 0.035)
        for (r, x_in, x_out, idx) in ((0.125, 0.0, 0.085, 0), (0.135, 0.055, 0.075, 1), (0.105, -0.025, 0.0, 2)):
            res = bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=r, radius2=r, depth=abs(x_out - x_in))
            verts = res["verts"]
            centre_x = x0 + side * (x_in + x_out) / 2
            bmesh.ops.transform(bm, matrix=Matrix.Translation((centre_x, 0.0, ear_z)) @ Matrix.Rotation(math.radians(90), 4, "Y"), verts=verts)
            tag({f for v in verts for f in v.link_faces}, idx)
    # バンド：両耳の上から頭の上を通る（「？」の後ろを通るよう、少しうしろへ傾ける）
    seg = 24
    band_w, band_t = 0.075, 0.03
    ring_prev = None
    tilt = math.radians(14.0)
    for k in range(seg + 1):
        a = math.pi * k / seg                       # 0 = 右（-X）、π = 左（+X）
        d = Vector((-math.cos(a), 0.0, math.sin(a)))
        d = Matrix.Rotation(-tilt, 3, "X") @ d      # 上の方ほどうしろ（+Y）へ
        p = _surface(Vector((d.x, d.y, d.z * (1.0 if d.z > 0 else 1.0))), 0.02)
        if k in (0, seg):
            p = Vector((-(BODY_R.x + 0.06) if k == 0 else (BODY_R.x + 0.06), 0.0, ear_z + 0.06))
        n = (p - BODY_C).normalized()
        t = Matrix.Rotation(-tilt, 3, "X") @ Vector((0.0, 1.0, 0.0))
        side_v = t.normalized() * band_w / 2
        ring = [bm.verts.new(p + side_v), bm.verts.new(p - side_v), bm.verts.new(p - side_v + n * band_t), bm.verts.new(p + side_v + n * band_t)]
        if ring_prev is not None:
            for i in range(4):
                f = bm.faces.new((ring_prev[i], ring_prev[(i + 1) % 4], ring[(i + 1) % 4], ring[i]))
                f.material_index = 0 if i != 2 else 1
        ring_prev = ring
    # マイク：右（-X）のカップから口の前へ
    start = Vector((-(BODY_R.x + 0.05), -0.03, ear_z - 0.04))
    mouth = _surface(Vector((-0.25, -1.0, -0.12)), 0.06)
    pts = [start.lerp(mouth, t) + Vector((0.0, 0.0, -0.06 * math.sin(math.pi * t))) for t in [i / 10 for i in range(11)]]
    for a, b in zip(pts, pts[1:]):
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.012, radius2=0.012, depth=(b - a).length)
        q = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
        bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4(), verts=res["verts"])
        tag({f for v in res["verts"] for f in v.link_faces}, 3)
    res = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.032)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(mouth), verts=res["verts"])
    tag({f for v in res["verts"] for f in v.link_faces}, 0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new("HERO_PilotHeadset", me)
    bpy.data.collections["MASCOT_Final"].objects.link(ob)
    return ob


# --- 軽い版 ----------------------------------------------------------------------------
def build_lod(rig):
    hero = bpy.data.objects["HERO_Mascot"]
    old = bpy.data.objects.get("HERO_Mascot_LOD")
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    lod = hero.copy()
    lod.data = hero.data.copy()
    lod.name = "HERO_Mascot_LOD"
    lod.data.name = "HERO_Mascot_LOD"
    bpy.data.collections["MASCOT_Final"].objects.link(lod)
    tris = sum(len(p.vertices) - 2 for p in lod.data.polygons)
    dec = lod.modifiers.new("LOD_Decimate", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = LOD_TRIANGLES / max(tris, 1)
    dec.use_collapse_triangulate = True
    bpy.ops.object.select_all(action="DESELECT")
    lod.select_set(True)
    bpy.context.view_layer.objects.active = lod
    with bpy.context.temp_override(object=lod, active_object=lod, selected_objects=[lod]):
        bpy.ops.object.modifier_apply(modifier="LOD_Decimate")
    after = sum(len(p.vertices) - 2 for p in lod.data.polygons)
    lod.hide_set(True)
    return lod, tris, after


# --- 書き出し --------------------------------------------------------------------------
def _select(objs, active):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


def export_all(rig, headset, lod, actions):
    out = {}
    # 1) 動き：骨組みとアクションだけ（NLA の帯にして書き出す）
    rig.animation_data.action = None
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    for act in actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = act.name
        track.strips.new(act.name, 1, act)
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    _select([rig], rig)
    path = str(ASSET / "mascot_pilot.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_skins=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_def_bones=False, export_morph=False, export_apply=False, export_yup=True,
                              export_cameras=False, export_lights=False, export_materials="NONE")
    out["mascot_pilot"] = Path(path).stat().st_size
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    # 2) ヘッドセット（ハテナの空間のまま）
    _select([headset], headset)
    path = str(ASSET / "pilot_headset.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_animations=False,
                              export_apply=True, export_yup=True, export_cameras=False, export_lights=False)
    out["pilot_headset"] = Path(path).stat().st_size
    headset.hide_set(True)
    # 3) 軽い版：骨組み＋HERO_Mascot_LOD（mascot_model.glb と同じ書き出し方）
    _select([rig, lod], rig)
    path = str(ASSET / "mascot_model_lod.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_skins=True,
                              export_animations=False, export_morph=False, export_apply=False, export_yup=True,
                              export_cameras=False, export_lights=False, export_image_format="AUTO")
    out["mascot_model_lod"] = Path(path).stat().st_size
    lod.hide_set(True)
    return out


def main():
    rig = bpy.data.objects["Rig"]
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    actions = build_actions(rig)
    headset = build_headset()
    lod, before, after = build_lod(rig)
    sizes = export_all(rig, headset, lod, actions) if DO_EXPORT else {}
    # 骨組みは初期姿勢へ戻しておく（mascot_model.glb の書き出しと同じ状態）
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    result = {"actions": [(a.name, list(a.frame_range)) for a in actions],
              "headset_tris": sum(len(p.vertices) - 2 for p in headset.data.polygons),
              "lod_tris": [before, after], "exports": sizes}
    print("PILOT_BUILD " + json.dumps(result, ensure_ascii=False))
    return result


if __name__ == "__main__":
    RESULT = main()

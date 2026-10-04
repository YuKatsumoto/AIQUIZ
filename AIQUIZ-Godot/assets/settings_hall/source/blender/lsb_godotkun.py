"""ゴドーくん: ゲームの他の場面（結果演出の審判・操縦席）と同じ、Godot のロゴ形のぬいぐるみ。

形・テクスチャ・16 本の DEF ボーンは assets/result_finale/referee_finale.glb の `HERO_GodotPlush` /
`RIG_Referee` をそのまま読み込んで使う（旗は捨てる）。ここで足すのは:
- 親ボーン `Root`（足元、配置と跳躍）と `Body`（座面の高さ、体の傾き・向き）。`DEF-head` と `DEF-hips` は
  どちらも `Body` の子。ぬいぐるみは頭と胴が一体のメッシュで顔が両方のボーンに乗っているので、
  この 2 本は曲げない（体は `Body` ごと剛体で動かす。docs/result_finale の README と同じ決まり）。
- 役ごとの小道具（剛体スキンでボーンに乗せ、ぬいぐるみのメッシュに結合）。
  variant: "lecturer"（丸眼鏡・赤い蝶ネクタイ・指し棒）、"notes"（鉛筆）、"hand"（後ろ向きの緑の帽子）、
  "doze"（頭上の Zzz）、"trainee"（黄色いヘルメット・膝当て・実習レールと刃）。
正面は Blender -Y（= Godot +Z）。足元が原点。身長 1.62 m（歯の先まで）。
"""
from __future__ import annotations

import math

import bpy
from mathutils import Matrix, Vector

from lsb_common import ROOT, MeshBuilder, aim_matrix, main_window

SOURCE_GLB = ROOT / "assets" / "result_finale" / "referee_finale.glb"
SOURCE_RIG = "RIG_Referee"
SOURCE_MESH = "HERO_GodotPlush"
PLUSH_MATERIAL = "GK_Plush"
PLUSH_IMAGE = "GK_PlushAlbedo"

# ------------------------------------------------------------------ proportions (m, rest pose)
BODY_BOTTOM = 0.48          # 胴の底（座るときに座面へ乗せる高さ）
BODY_FRONT = 0.507          # 胴の正面の張り出し（-Y）
HEAD_TOP = 1.624            # 上の 2 本の歯の先
EYE_X = 0.25                # 目の中心（テクスチャ）
EYE_Z = 1.048
EYE_R = 0.125
TIE_Z = 0.69                # 口の線（ジグザグ）の下（蝶ネクタイ）
ZZZ_ANCHOR = Vector((0.3, 0.22, 1.7))

BONE_PARENT = {"DEF-head": "Body", "DEF-hips": "Body"}

# 実習レール（練習生のローカル座標）。刃は y RAIL_Y0 → RAIL_Y1 へ走る（手前 = +Y = Godot -Z）。
RAIL_Y0 = -2.8
RAIL_Y1 = 2.5
RAIL_Z = 0.0
BLADE_R = 0.36
BLADE_TEETH = 16


# ------------------------------------------------------------------ source (the real plush)

_TEMPLATE: dict = {}


def _template(collection) -> dict:
    """referee_finale.glb を 1 回だけ読み、ぬいぐるみのリグとメッシュのひな形を返す（ビルドの間だけ使う）。"""
    rig = _TEMPLATE.get("rig")
    if rig is not None and rig.name in bpy.data.objects:
        return _TEMPLATE
    win = main_window()
    scene = win.scene
    layer = scene.view_layers[0]
    before_obj = set(bpy.data.objects)
    before_act = set(bpy.data.actions)
    before_mat = set(bpy.data.materials)
    before_img = set(bpy.data.images)
    before_mesh = set(bpy.data.meshes)
    before_arm = set(bpy.data.armatures)
    with bpy.context.temp_override(window=win, scene=scene, view_layer=layer):
        bpy.ops.import_scene.gltf(filepath=str(SOURCE_GLB))
    new_objs = [o for o in bpy.data.objects if o not in before_obj]
    rig = next(o for o in new_objs if o.type == "ARMATURE" and o.name.startswith(SOURCE_RIG))
    mesh = next(o for o in new_objs if o.type == "MESH" and o.name.startswith(SOURCE_MESH))
    # 旗・読み込みの付属物・審判のアクションは捨てる
    for obj in new_objs:
        if obj not in (rig, mesh):
            bpy.data.objects.remove(obj, do_unlink=True)
    for act in [a for a in bpy.data.actions if a not in before_act]:
        bpy.data.actions.remove(act)
    if rig.animation_data is not None:
        rig.animation_data_clear()
    for obj in (rig, mesh):
        for col in list(obj.users_collection):
            col.objects.unlink(obj)
        collection.objects.link(obj)
    rig.matrix_world = Matrix.Identity(4)
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    for pb in rig.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    # 材質と画像は既存の同名を使い回す（作り直すたびに .001 が増えないように）
    material = mesh.data.materials[0]
    image = next((n.image for n in material.node_tree.nodes if n.bl_idname == "ShaderNodeTexImage" and n.image), None)
    keep_img = bpy.data.images.get(PLUSH_IMAGE)
    if image is not None:
        if keep_img is not None and keep_img != image:
            image.user_remap(keep_img)
            bpy.data.images.remove(image)
        else:
            image.name = PLUSH_IMAGE
            if image.packed_file is None:
                image.pack()
    keep_mat = bpy.data.materials.get(PLUSH_MATERIAL)
    if keep_mat is not None and keep_mat != material:
        mesh.data.materials[0] = keep_mat
        bpy.data.materials.remove(material)
    else:
        material.name = PLUSH_MATERIAL
    for m in [m for m in bpy.data.materials if m not in before_mat and m.users == 0]:
        bpy.data.materials.remove(m)
    for img in [i for i in bpy.data.images if i not in before_img and i.users == 0]:
        bpy.data.images.remove(img)
    rig.name = "GK_SrcRig"
    rig.data.name = "GK_SrcRig"
    mesh.name = "GK_SrcPlush"
    mesh.data.name = "GK_SrcPlush"
    rig.hide_render = True
    mesh.hide_render = True
    _TEMPLATE.update({"rig": rig, "mesh": mesh,
                      "new_meshes": [m for m in bpy.data.meshes if m not in before_mesh and m.users == 0],
                      "new_arms": [a for a in bpy.data.armatures if a not in before_arm and a.users == 0]})
    for block in _TEMPLATE["new_meshes"]:
        bpy.data.meshes.remove(block)
    for block in _TEMPLATE["new_arms"]:
        bpy.data.armatures.remove(block)
    return _TEMPLATE


def release_template() -> None:
    """ひな形を消す（書き出しの前に呼ぶ）。"""
    rig = _TEMPLATE.get("rig")
    mesh = _TEMPLATE.get("mesh")
    for obj in (mesh, rig):
        if obj is not None and obj.name in bpy.data.objects:
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data is not None and data.users == 0:
                (bpy.data.meshes if isinstance(data, bpy.types.Mesh) else bpy.data.armatures).remove(data)
    _TEMPLATE.clear()


def _extra_bones(variant: str):
    """(name, head, tail, parent) — ぬいぐるみのリグに足すボーン。"""
    bones = [
        ("Root", Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.12)), None),
        ("Body", Vector((0.0, 0.0, BODY_BOTTOM)), Vector((0.0, 0.0, 0.80)), "Root"),
    ]
    if variant == "doze":
        bones.append(("Zzz", ZZZ_ANCHOR, ZZZ_ANCHOR + Vector((0.0, 0.0, 0.2)), "Body"))
    if variant == "trainee":
        # レールと刃は跳躍（Root の移動）に連動しないよう、親なしの Rail ボーンにぶら下げる
        bones.append(("Rail", Vector((0.0, 0.0, -0.3)), Vector((0.0, 0.0, -0.1)), None))
        bones.append(("Blade", Vector((0.0, RAIL_Y0, RAIL_Z + BLADE_R)),
                      Vector((0.0, RAIL_Y0, RAIL_Z + BLADE_R + 0.2)), "Rail"))
    return bones


def _copy_rig(name: str, variant: str, collection) -> tuple[bpy.types.Object, bpy.types.Object]:
    tpl = _template(collection)
    arm = tpl["rig"].copy()
    arm.data = tpl["rig"].data.copy()
    arm.name = f"RIG_{name}"
    arm.data.name = f"RIG_{name}"
    arm.hide_render = False
    arm.rotation_mode = "XYZ"  # glTF の読み込みは四元数。確認用の配置（place()）はオイラーで向きを付ける
    collection.objects.link(arm)
    mesh = tpl["mesh"].copy()
    mesh.data = tpl["mesh"].data.copy()
    mesh.name = f"HERO_{name}"
    mesh.data.name = f"HERO_{name}"
    mesh.hide_render = False
    collection.objects.link(mesh)
    mesh.parent = arm
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    for mod in mesh.modifiers:
        if mod.type == "ARMATURE":
            mod.object = arm
    win = main_window()
    scene = win.scene
    layer = scene.view_layers[0]
    with bpy.context.temp_override(window=win, scene=scene, view_layer=layer, active_object=arm,
                                   selected_objects=[arm], object=arm):
        layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        edit = arm.data.edit_bones
        extras = _extra_bones(variant)
        for bname, head, tail, parent in extras:
            b = edit.new(bname)
            b.head = head
            b.tail = tail
            b.roll = 0.0
        for bname, head, tail, parent in extras:
            if parent:
                edit[bname].parent = edit[parent]
                edit[bname].use_connect = False
        for child, parent in BONE_PARENT.items():
            edit[child].parent = edit[parent]
            edit[child].use_connect = False
        bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ" if pb.name == "Blade" else "QUATERNION"
    arm.data.display_type = "OCTAHEDRAL"
    return arm, mesh


# ------------------------------------------------------------------ fitting helpers

def _surface(mesh_obj, x: float, z: float, from_front: bool = True) -> tuple[Vector, Vector]:
    """休止姿勢のぬいぐるみの表面（正面 -Y から当てる）。位置と法線を返す。"""
    origin = Vector((x, -2.0 if from_front else 2.0, z))
    direction = Vector((0.0, 1.0 if from_front else -1.0, 0.0))
    hit, loc, normal, _ = mesh_obj.ray_cast(origin, direction)
    if not hit:
        return Vector((x, -BODY_FRONT, z)), Vector((0.0, -1.0, 0.0))
    return loc, normal


def _top(mesh_obj, x: float, y: float) -> float:
    hit, loc, _, _ = mesh_obj.ray_cast(Vector((x, y, 3.0)), Vector((0.0, 0.0, -1.0)))
    return loc.z if hit else HEAD_TOP


def _hand_frame(arm, side: str) -> tuple[Vector, Vector]:
    """手の中心（休止姿勢）と、手首から手先への向き。"""
    bone = arm.data.bones[f"DEF-hand.{side}"]
    head = bone.head_local
    tail = bone.tail_local
    return head.lerp(tail, 0.85), (tail - head).normalized()


# ------------------------------------------------------------------ accessories

def _cap(mb: MeshBuilder, mesh_obj, material: str, radius: float, brim_back: bool, brim_front: bool):
    """上の 2 本の歯にかぶせる帽子（半楕円体 ＋ つば）。中心の高さは表面から決める。"""
    crown_z = max(_top(mesh_obj, x, 0.0) for x in (-0.2, 0.0, 0.2))
    cz = crown_z - radius * 0.55
    mb.sphere(radius, (0.0, 0.0, cz), material, "DEF-head", scale=(1.0, 0.95, 0.8), segments=30, rings=14)
    mb.torus(radius * 0.97, 0.022, (0.0, 0.0, cz + 0.005), material, "DEF-head", segments=30, rings=8)
    tilt = Matrix.Rotation(math.radians(-10.0), 3, "X")
    if brim_back:
        mb.box((radius * 0.85, radius * 0.75, 0.03), (0.0, radius * 1.15, cz - 0.02), material, "DEF-head",
               rotation=Matrix.Rotation(math.radians(10.0), 3, "X"))
    if brim_front:
        mb.box((radius * 0.95, radius * 0.6, 0.03), (0.0, -radius * 1.1, cz - 0.02), material, "DEF-head",
               rotation=tilt)
    mb.sphere(0.045, (0.0, 0.0, cz + radius * 0.8), "GK_White" if material != "GK_White" else "GK_Black",
              "DEF-head", segments=12, rings=8)
    return cz


def _accessories(mb: MeshBuilder, arm, mesh_obj, variant: str):
    if variant == "lecturer":
        # 丸眼鏡: 目の縁に沿わせ、表面から 1.8 cm 浮かせる（つるは頭の丸みから浮くので付けない）
        centers = []
        for s in (1.0, -1.0):
            loc, normal = _surface(mesh_obj, s * EYE_X, EYE_Z)
            c = loc + normal * 0.018
            centers.append(c)
            mb.torus(EYE_R + 0.02, 0.016, c, "GK_Black", "DEF-head", rotation=aim_matrix(normal), segments=28, rings=8)
        mid_l = centers[0] - Vector((EYE_R + 0.02, 0.0, 0.0))
        mid_r = centers[1] + Vector((EYE_R + 0.02, 0.0, 0.0))
        bridge = (mid_l + mid_r) * 0.5 + Vector((0.0, -0.02, 0.02))
        mb.cylinder_between(mid_l, bridge, 0.011, "GK_Black", "DEF-head", segments=6)
        mb.cylinder_between(bridge, mid_r, 0.011, "GK_Black", "DEF-head", segments=6)
        # 赤い蝶ネクタイ: 口の線（ジグザグ）のすぐ下、胴の正面に沿わせる
        loc, normal = _surface(mesh_obj, 0.0, TIE_Z)
        rot = aim_matrix(normal)
        at = loc + normal * 0.02
        mb.box((0.05, 0.045, 0.04), at, "GK_Red", "DEF-hips", rotation=rot)
        for s in (1.0, -1.0):
            wing = [(s * 0.02, 0.0), (s * 0.11, 0.045), (s * 0.12, -0.045)]
            mb.prism(wing if s > 0 else wing[::-1], 0.03, at - normal * 0.004, "GK_Red", "DEF-hips", rotation=rot)
        # 指し棒（右手）: 腕の延長に握らせる。先が赤
        c, d = _hand_frame(arm, "R")
        grip = c - d * 0.05
        tip = c + d * 0.82
        mb.cylinder_between(grip, tip, 0.014, "GK_Silver", "DEF-hand.R", radius2=0.009)
        mb.sphere(0.032, tip, "GK_Red", "DEF-hand.R", segments=12, rings=8)
    elif variant == "notes":
        # 鉛筆（右手）: 手先の延長に握り、芯がノートへ届く
        c, d = _hand_frame(arm, "R")
        top = c - d * 0.05
        tip = c + d * 0.26
        mb.cylinder_between(top, tip, 0.017, "GK_Yellow", "DEF-hand.R", segments=6)
        mb.cone(0.017, 0.05, tip + d * 0.025, "GK_Cream", "DEF-hand.R", segments=6, rotation=aim_matrix(d))
        mb.sphere(0.022, top, "GK_Pink", "DEF-hand.R", segments=10, rings=6)
    elif variant == "hand":
        # 緑の帽子（つばは後ろ向き。カメラは生徒の背中側から見る）
        _cap(mb, mesh_obj, "GK_Green", 0.38, brim_back=True, brim_front=False)
    elif variant == "doze":
        # Zzz: 大きさの違う 3 つの Z（箱 3 本ずつ）。カメラから見える右後ろ寄りに浮かべる
        for dx, dz, size in ((0.0, 0.0, 0.1), (0.16, 0.16, 0.14), (0.36, 0.36, 0.18)):
            c = ZZZ_ANCHOR + Vector((dx, 0.0, dz))
            t = size * 0.18
            mb.box((size, t, t), c + Vector((0, 0, size * 0.5)), "GK_Zzz", "Zzz")
            mb.box((size, t, t), c - Vector((0, 0, size * 0.5)), "GK_Zzz", "Zzz")
            mb.box((t, t, size * 1.25), c, "GK_Zzz", "Zzz", rotation=Matrix.Rotation(math.radians(-38.0), 3, "Y"))
    elif variant == "trainee":
        # 黄色いヘルメット（前つば）と膝当て
        cz = _cap(mb, mesh_obj, "GK_Yellow", 0.41, brim_back=False, brim_front=True)
        mb.sphere(0.05, (0.0, 0.0, cz + 0.41 * 0.62), "GK_Yellow", "DEF-head", scale=(0.9, 7.0, 1.0),
                  segments=16, rings=8)
        for side in ("L", "R"):
            bone = arm.data.bones[f"DEF-shin.{side}"]
            mb.sphere(0.07, bone.head_local + Vector((0.0, -0.055, -0.02)), "GK_Orange", f"DEF-shin.{side}",
                      scale=(1.0, 0.6, 1.0), segments=14, rings=8)
        _practice_rail(mb)


def _practice_rail(mb: MeshBuilder):
    """実習レール: 鋼の U 字レール、端のストッパー、モーター箱、床の黄黒テープ、走る刃（Blade ボーン）。"""
    length = RAIL_Y1 - RAIL_Y0
    yc = (RAIL_Y0 + RAIL_Y1) * 0.5
    mb.box((0.46, length, 0.04), (0.0, yc, RAIL_Z - 0.02), "LS_DarkSteel", "Rail")
    for s in (1.0, -1.0):
        mb.box((0.05, length, 0.12), (s * 0.205, yc, RAIL_Z + 0.02), "LS_Steel", "Rail")
    for y in (RAIL_Y0 - 0.08, RAIL_Y1 + 0.08):
        mb.box((0.5, 0.16, 0.26), (0.0, y, RAIL_Z + 0.09), "GK_Red", "Rail")
        mb.box((0.52, 0.04, 0.06), (0.0, y, RAIL_Z + 0.25), "LS_HazardYellow", "Rail")
    # モーター箱（奥側）
    mb.box((0.34, 0.3, 0.32), (0.0, RAIL_Y0 - 0.38, RAIL_Z + 0.16), "LS_DarkSteel", "Rail")
    mb.cylinder(0.09, 0.08, (0.0, RAIL_Y0 - 0.21, RAIL_Z + 0.16), "LS_Steel", "Rail",
                rotation=Matrix.Rotation(math.radians(90.0), 3, "X"), segments=16)
    mb.sphere(0.03, (0.1, RAIL_Y0 - 0.54, RAIL_Z + 0.28), "GK_Glow", "Rail", segments=10, rings=6)
    # 床の黄黒テープ（レールの両側）
    for s in (1.0, -1.0):
        mb.box((0.1, length + 0.8, 0.004), (s * 0.55, yc, RAIL_Z - 0.038), "LS_HazardYellow", "Rail")
        for k in range(10):
            y = RAIL_Y0 - 0.3 + (k + 0.5) * (length + 0.8) / 10.0
            mb.box((0.1, 0.18, 0.005), (s * 0.55, y, RAIL_Z - 0.0375), "LS_HazardBlack", "Rail",
                   rotation=Matrix.Rotation(math.radians(35.0), 3, "Z"))
    # 刃: 円盤と 16 の歯、ハブ、キャリッジ（Blade ボーンに付く）
    c = Vector((0.0, RAIL_Y0, RAIL_Z + BLADE_R))
    rot = Matrix.Rotation(math.radians(90.0), 3, "Y")  # 円盤の面を ±X に
    mb.cylinder(BLADE_R, 0.02, c, "LS_Steel", "Blade", rotation=rot, segments=32)
    mb.cylinder(0.08, 0.06, c, "LS_DarkSteel", "Blade", rotation=rot, segments=16)
    for k in range(BLADE_TEETH):
        a = math.tau * k / BLADE_TEETH
        p = c + Vector((0.0, math.cos(a) * (BLADE_R + 0.03), math.sin(a) * (BLADE_R + 0.03)))
        tooth_rot = Matrix.Rotation(a + math.radians(20.0), 3, "X")
        mb.box((0.024, 0.06, 0.09), p, "LS_Steel", "Blade", rotation=tooth_rot)
    mb.box((0.36, 0.28, 0.1), (0.0, RAIL_Y0, RAIL_Z + 0.07), "LS_DarkSteel", "Blade")
    for s in (1.0, -1.0):
        mb.cylinder(0.05, 0.04, (s * 0.2, RAIL_Y0, RAIL_Z + 0.05), "GK_Black", "Blade",
                    rotation=Matrix.Rotation(math.radians(90.0), 3, "Y"), segments=12)


def build_godotkun(name: str, variant: str, collection) -> dict:
    """RIG_<name>、HERO_<name>（ぬいぐるみ）、HERO_<name>_Gear（小道具）を作り、辞書 {"arm", "mesh", "gear"} を返す。
    小道具はぬいぐるみに結合しない: 読み込んだぬいぐるみはカスタム法線と頂点色を持ち、結合すると小道具の
    法線が壊れて Godot で黒く写る。別メッシュのまま同じリグでスキンする。"""
    arm, mesh_obj = _copy_rig(name, variant, collection)
    mb = MeshBuilder(f"HERO_{name}_Gear")
    _accessories(mb, arm, mesh_obj, variant)
    gear = mb.build(collection)
    gear.parent = arm
    gear.matrix_parent_inverse = Matrix.Identity(4)
    mod = gear.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mod.use_vertex_groups = True
    # どの頂点グループにも入っていない頂点は Root へ（スキンの取りこぼし防止）
    missing = 0
    for obj in (mesh_obj, gear):
        weighted = {v.index for v in obj.data.vertices if any(g.weight > 0.0 for g in v.groups)}
        loose = [v.index for v in obj.data.vertices if v.index not in weighted]
        if loose:
            root = obj.vertex_groups.get("Root") or obj.vertex_groups.new(name="Root")
            root.add(loose, 1.0, "REPLACE")
        missing += len(loose)
    return {"arm": arm, "mesh": mesh_obj, "gear": gear, "variant": variant, "missing_weights": missing}

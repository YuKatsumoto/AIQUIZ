"""机のセット（段階2〜4）を Godot 用の glb に書き出す。res://assets/tutorial_desk/tutorial_desk.glb

書き出す物：部屋・机まわり・キーボード・椅子・2 人のブロックマン（骨組みつき）・寄りのカメラ（CAM_Intro）。
動きは場面の時間軸を 1 本（SCENE）にまとめ、IK などの制約を焼き込んで書き出す。ライトと確認用のカメラ、IK の目印は書き出さない
（ライトは Godot で作り直す）。キーの文字（文字の物）は glb に入らないので、書き出す間だけ形（LEGM_）に置き換える。
材質は名前だけ使う（Blender の手続きの模様は glb に入らないので、Godot で名前ごとに作り直す）。

ライブの Blender で、build_tutorial_desk.py・build_tutorial_people.py・build_tutorial_motion.py の後に実行する。
    import runpy
    ns = runpy.run_path(r"G:/AIQUIZ-Main/AIQUIZ-Godot/assets/tutorial_desk/source/blender/export_tutorial_desk.py")
    result = ns["export"]()
"""
import os
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
GLB = HERE.parents[1] / "tutorial_desk.glb"
COLLECTIONS = ("TD_Room", "TD_Desk", "TD_Keyboard", "TD_Chairs", "TD_People", "TD_Motion")


def export(path=GLB):
    temp = legend_meshes()
    try:
        chosen = select_for_export()
        bpy.ops.export_scene.gltf(
            filepath=str(path), export_format="GLB", use_selection=True, export_apply=True,
            export_animations=True, export_animation_mode="SCENE", export_bake_animation=True, export_force_sampling=True,
            export_frame_range=True, export_cameras=True, export_lights=False, export_extras=True, export_yup=True,
            export_skins=True, export_def_bones=True, export_morph=False, export_materials="EXPORT", export_image_format="AUTO",
            export_texcoords=True, export_normals=True)
    finally:
        for obj in temp:
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.meshes.remove(data)
    return {"path": str(path), "objects": chosen, "size_mb": round(os.path.getsize(path) / 1e6, 2)}


def legend_meshes():
    """キーの文字（LEG_）を、同じ親と位置の形（LEGM_）に写す。"""
    deps = bpy.context.evaluated_depsgraph_get()
    made = []
    for obj in [o for o in bpy.data.collections["TD_Keyboard"].all_objects if o.type == "FONT"]:
        me = bpy.data.meshes.new_from_object(obj.evaluated_get(deps), depsgraph=deps)
        copy = bpy.data.objects.new("LEGM_" + obj.name[len("LEG_"):], me)
        bpy.data.collections["TD_Keyboard"].objects.link(copy)
        copy.parent = obj.parent
        copy.matrix_parent_inverse = obj.matrix_parent_inverse.copy()
        copy.matrix_basis = obj.matrix_basis.copy()
        copy["key_id"] = obj.get("key_id", "")
        made.append(copy)
    return made


def select_for_export():
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    count = 0
    for name in COLLECTIONS:
        for obj in bpy.data.collections[name].all_objects:
            if obj.type == "FONT" or (obj.type == "EMPTY" and obj.name.startswith("PEO_") and "_IK_" in obj.name):
                continue
            if obj.type == "CAMERA" and obj.name != "CAM_Intro":
                continue
            if obj.name not in bpy.context.view_layer.objects:
                continue
            obj.select_set(True)
            count += 1
    return count

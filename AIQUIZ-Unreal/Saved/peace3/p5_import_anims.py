# -*- coding: utf-8 -*-
"""Phase5: 既存 SK_YBot スケルトンへ Run/Jump/Drowning アニメをインポート（メッシュは既存）。"""
import unreal
import json

SRC = "C:/AIQUIZ/AIQUIZ-Godot/assets/animations"
DEST = "/Game/AiQuiz/Character"
out = {"anims": []}
at = unreal.AssetToolsHelpers.get_asset_tools()

sk = unreal.EditorAssetLibrary.load_asset(DEST + "/SK_YBot")
skeleton = sk.get_editor_property("skeleton")
out["skeleton"] = skeleton.get_name() if skeleton else None


def anim_task(fbx, name):
    t = unreal.AssetImportTask()
    t.filename = SRC + "/" + fbx
    t.destination_path = DEST
    t.destination_name = name
    t.automated = True
    t.replace_existing = True
    t.save = True
    ui = unreal.FbxImportUI()
    ui.set_editor_property("import_mesh", False)
    ui.set_editor_property("import_as_skeletal", True)
    ui.set_editor_property("import_animations", True)
    ui.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_ANIMATION)
    ui.set_editor_property("skeleton", skeleton)
    t.options = ui
    return t


# 1回の起動で「まだ無い最初の1本」だけインポート（2本目以降のクラッシュを回避）。
TODO = [("Run.fbx", "A_Run"), ("Jumping.fbx", "A_Jump"), ("Drowning.fbx", "A_Drown")]
out["done"] = True
for fbx, nm in TODO:
    if not unreal.EditorAssetLibrary.does_asset_exist(DEST + "/" + nm):
        at.import_asset_tasks([anim_task(fbx, nm)])
        out["imported"] = nm
        out["exists"] = unreal.EditorAssetLibrary.does_asset_exist(DEST + "/" + nm)
        out["done"] = False
        break

print("RESULT " + json.dumps(out, ensure_ascii=False))

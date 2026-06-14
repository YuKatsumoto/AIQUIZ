# -*- coding: utf-8 -*-
"""Phase5: Mixamo Y-Bot スケルタルメッシュ + Run/Jump/Drowning アニメを UE へインポート。
UE5.7 は FBX に Interchange を使うが、legacy FbxImportUI を options に渡すと従来パスで通る。"""
import unreal
import json

SRC = "C:/AIQUIZ/AIQUIZ-Godot/assets/animations"
DEST = "/Game/AiQuiz/Character"
out = {"steps": []}
at = unreal.AssetToolsHelpers.get_asset_tools()


def skel_task(fbx, name):
    t = unreal.AssetImportTask()
    t.filename = SRC + "/" + fbx
    t.destination_path = DEST
    t.destination_name = name
    t.automated = True
    t.replace_existing = True
    t.save = True
    ui = unreal.FbxImportUI()
    ui.set_editor_property("import_mesh", True)
    ui.set_editor_property("import_as_skeletal", True)
    ui.set_editor_property("import_animations", False)
    ui.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_SKELETAL_MESH)
    ui.set_editor_property("create_physics_asset", True)
    t.options = ui
    return t


def anim_task(fbx, name, skeleton):
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


# 1) Y-Bot skeletal mesh (creates SK_YBot + SK_YBot_Skeleton + physics asset)
t1 = skel_task("Y Bot.fbx", "SK_YBot")
at.import_asset_tasks([t1])
imp = list(t1.get_objects())
out["steps"].append({"ybot_imported": [o.get_name() for o in imp]})

sk = unreal.EditorAssetLibrary.load_asset(DEST + "/SK_YBot")
skeleton = sk.get_editor_property("skeleton") if sk else None
out["skeleton"] = skeleton.get_name() if skeleton else None
assert skeleton is not None, "no skeleton from Y Bot import"

# 2) animations targeting that skeleton
for fbx, nm in [("Run.fbx", "A_Run"), ("Jumping.fbx", "A_Jump"), ("Drowning.fbx", "A_Drown")]:
    ta = anim_task(fbx, nm, skeleton)
    at.import_asset_tasks([ta])
    objs = [o.get_name() for o in list(ta.get_objects())]
    out["steps"].append({nm: objs})

# 3) report sizes / what exists
out["assets"] = [p for p in unreal.EditorAssetLibrary.list_assets(DEST, recursive=True)]
# bounds of the mesh to sanity-check scale (Mixamo cm)
try:
    b = sk.get_bounds()  # may not exist; fallback
except Exception:
    b = None
out["ok"] = True
print("RESULT " + json.dumps(out, ensure_ascii=False))

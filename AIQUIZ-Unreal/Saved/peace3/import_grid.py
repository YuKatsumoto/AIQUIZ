import unreal, json
OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_import_grid.json"
res = {"ok": False, "log": []}
L = res["log"].append
DST = "/Game/AiQuiz/Meshes"
ASSET = DST + "/SM_MagmaGrid"
try:
    at = unreal.AssetToolsHelpers.get_asset_tools()
    if unreal.EditorAssetLibrary.does_asset_exist(ASSET):
        unreal.EditorAssetLibrary.delete_asset(ASSET)
        L("deleted existing SM_MagmaGrid")
    task = unreal.AssetImportTask()
    task.set_editor_property("filename", r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/SM_MagmaGrid.obj")
    task.set_editor_property("destination_path", DST)
    task.set_editor_property("destination_name", "SM_MagmaGrid")
    task.set_editor_property("automated", True)
    task.set_editor_property("replace_existing", True)
    task.set_editor_property("save", True)
    at.import_asset_tasks([task])
    exists = unreal.EditorAssetLibrary.does_asset_exist(ASSET)
    res["exists"] = exists
    if exists:
        sm = unreal.EditorAssetLibrary.load_asset(ASSET)
        try:
            res["num_tris"] = unreal.EditorStaticMeshLibrary.get_number_triangles(sm, 0)
            res["num_verts"] = unreal.EditorStaticMeshLibrary.get_number_verts(sm, 0)
            bb = sm.get_bounding_box()
            res["bb_min"] = [bb.min.x, bb.min.y, bb.min.z]
            res["bb_max"] = [bb.max.x, bb.max.y, bb.max.z]
        except Exception as e:
            L("stats err: %s" % e)
        res["ok"] = True
        L("imported SM_MagmaGrid")
except Exception as e:
    import traceback
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()
open(OUT, "w", encoding="utf-8").write(json.dumps(res, ensure_ascii=False, indent=2))
print("IMPORT_GRID", json.dumps(res, ensure_ascii=False))

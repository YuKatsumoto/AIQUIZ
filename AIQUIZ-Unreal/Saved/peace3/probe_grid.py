import unreal, json
sm = unreal.EditorAssetLibrary.load_asset("/Game/AiQuiz/Meshes/SM_MagmaGrid")
res = {}
bb = sm.get_bounding_box()
res["bb_min"] = [round(bb.min.x, 1), round(bb.min.y, 1), round(bb.min.z, 1)]
res["bb_max"] = [round(bb.max.x, 1), round(bb.max.y, 1), round(bb.max.z, 1)]
res["nlods"] = sm.get_num_lods()
print("GRID", json.dumps(res))
open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_grid.json", "w").write(json.dumps(res, indent=2))

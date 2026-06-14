import unreal, json
MEL = unreal.MaterialEditingLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
P = "/Game/AiQuiz/Materials/M_TcProbe"
if unreal.EditorAssetLibrary.does_asset_exist(P):
    unreal.EditorAssetLibrary.delete_asset(P)
m = at.create_asset("M_TcProbe", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
tc = MEL.create_material_expression(m, unreal.MaterialExpressionTextureCoordinate, 0, 0)
res = {"props": [p for p in dir(tc) if "til" in p.lower() or "coord" in p.lower()]}
try:
    tc.set_editor_property("u_tiling", 40.0)
    tc.set_editor_property("v_tiling", 40.0)
    res["u_after"] = tc.get_editor_property("u_tiling")
    res["v_after"] = tc.get_editor_property("v_tiling")
except Exception as e:
    res["err"] = str(e)
unreal.EditorAssetLibrary.delete_asset(P)
print("TCPROBE", json.dumps(res, default=str))

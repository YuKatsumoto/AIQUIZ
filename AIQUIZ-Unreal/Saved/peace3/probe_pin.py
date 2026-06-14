import unreal, json
MEL = unreal.MaterialEditingLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
if unreal.EditorAssetLibrary.does_asset_exist("/Game/AiQuiz/Materials/M_PinProbe"):
    unreal.EditorAssetLibrary.delete_asset("/Game/AiQuiz/Materials/M_PinProbe")
m = at.create_asset("M_PinProbe", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
tc = MEL.create_material_expression(m, unreal.MaterialExpressionTextureCoordinate, -400, 0)
tc.set_editor_property("u_tiling", 5.0)
ts = MEL.create_material_expression(m, unreal.MaterialExpressionTextureSample, 0, 0)
res = {}
for pin in ["UVs", "Coordinates", "UV", "Coordinate", ""]:
    try:
        ok = MEL.connect_material_expressions(tc, "", ts, pin)
        res[pin if pin else "<empty>"] = bool(ok)
    except Exception as e:
        res[pin if pin else "<empty>"] = "ERR:%s" % e
unreal.EditorAssetLibrary.delete_asset("/Game/AiQuiz/Materials/M_PinProbe")
print("PINPROBE", json.dumps(res))

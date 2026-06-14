import unreal
BASE=r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
MEL=unreal.MaterialEditingLibrary; eal=unreal.EditorAssetLibrary
TP="/Game/AiQuiz/Materials/M_CustTest"
if eal.does_asset_exist(TP):
    m=eal.load_asset(TP); MEL.delete_all_material_expressions(m)
else:
    at=unreal.AssetToolsHelpers.get_asset_tools()
    m=at.create_asset("M_CustTest","/Game/AiQuiz/Materials",unreal.Material,unreal.MaterialFactoryNew())
m.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
uv=MEL.create_material_expression(m,unreal.MaterialExpressionTextureCoordinate,-600,0)
c=MEL.create_material_expression(m,unreal.MaterialExpressionCustom,-300,0)
ci=unreal.CustomInput(); ci.set_editor_property("input_name","UV")
c.set_editor_property("inputs",[ci])
c.set_editor_property("code","return float3(UV.x, UV.y, 0.5);")
c.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT3)
MEL.connect_material_expressions(uv,"",c,"UV")
MEL.connect_material_property(c,"",unreal.MaterialProperty.MP_EMISSIVE_COLOR)
MEL.recompile_material(m)
eal.save_asset(TP,only_if_is_dirty=False)
ues=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem); world=ues.get_editor_world()
rt=unreal.RenderingLibrary.create_render_target2d(world,256,256,unreal.TextureRenderTargetFormat.RTF_RGBA16F,unreal.LinearColor(0,0,0,1),False)
unreal.RenderingLibrary.draw_material_to_render_target(world, rt, m)
unreal.RenderingLibrary.export_render_target(world, rt, BASE, "custom_test.png")
for (px,py) in [(10,10),(245,10),(128,128),(10,245)]:
    cc=unreal.RenderingLibrary.read_render_target_raw_pixel(world, rt, px, py)
    print("PX",px,py,"=",round(cc.r,3),round(cc.g,3),round(cc.b,3))
print("done")

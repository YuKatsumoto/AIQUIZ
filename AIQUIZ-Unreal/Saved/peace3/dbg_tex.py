import unreal, json
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
MAT = "/Game/AiQuiz/Materials/M_TexDbg"
res = {}

col = eal.load_asset("/Game/AiQuiz/Textures/T_Lava_Color")
res["color_loaded"] = col is not None
if col:
    res["w"] = col.blueprint_get_size_x() if hasattr(col, "blueprint_get_size_x") else "?"
    try:
        res["src_w"] = col.get_editor_property("imported_size").x
    except Exception as e:
        res["src_w_err"] = str(e)

m = None
if eal.does_asset_exist(MAT):
    m = eal.load_asset(MAT); MEL.delete_all_material_expressions(m)
if not m:
    m = at.create_asset("M_TexDbg", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
m.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)

tc = MEL.create_material_expression(m, unreal.MaterialExpressionTextureCoordinate, -600, 0)
tc.set_editor_property("u_tiling", 8.0)
tc.set_editor_property("v_tiling", 8.0)
ts = MEL.create_material_expression(m, unreal.MaterialExpressionTextureSample, -300, 0)
ts.set_editor_property("texture", col)
ts.set_editor_property("sampler_type", unreal.MaterialSamplerType.SAMPLERTYPE_COLOR)
res["uv_connect"] = bool(MEL.connect_material_expressions(tc, "", ts, "UVs"))
mul = MEL.create_material_expression(m, unreal.MaterialExpressionMultiply, -80, 0)
mul.set_editor_property("const_b", 3.0)
res["col_connect"] = bool(MEL.connect_material_expressions(ts, "", mul, "A"))
res["emis_connect"] = bool(MEL.connect_material_property(mul, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR))
MEL.recompile_material(m)
eal.save_asset(MAT, only_if_is_dirty=False)

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Magma_Floor":
        a.get_component_by_class(unreal.StaticMeshComponent).set_material(0, m)
        res["applied"] = True
print("TEXDBG", json.dumps(res, default=str))

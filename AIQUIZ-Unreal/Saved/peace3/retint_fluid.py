import unreal, json, traceback
res = {"log": []}
L = res["log"].append
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
MAT = "/Game/AiQuiz/Materials/M_LavaFluid"
try:
    # build a molten-lava translucent surface material
    mat = None
    if eal.does_asset_exist(MAT):
        mat = eal.load_asset(MAT); MEL.delete_all_material_expressions(mat)
    if not mat:
        mat = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
            "M_LavaFluid", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
    mat.set_editor_property("blend_mode", unreal.BlendMode.BLEND_TRANSLUCENT)
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_DEFAULT_LIT)
    mat.set_editor_property("two_sided", True)

    def E(c, x, y): return MEL.create_material_expression(mat, c, x, y)
    base = E(unreal.MaterialExpressionConstant3Vector, -500, -100)
    base.set_editor_property("constant", unreal.LinearColor(0.9, 0.35, 0.05, 1.0))
    MEL.connect_material_property(base, "", unreal.MaterialProperty.MP_BASE_COLOR)
    emi = E(unreal.MaterialExpressionConstant3Vector, -500, 80)
    emi.set_editor_property("constant", unreal.LinearColor(3.0, 0.9, 0.12, 1.0))
    MEL.connect_material_property(emi, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    op = E(unreal.MaterialExpressionConstant, -500, 240)
    op.set_editor_property("r", 0.9)
    MEL.connect_material_property(op, "", unreal.MaterialProperty.MP_OPACITY)
    rgh = E(unreal.MaterialExpressionConstant, -500, 360)
    rgh.set_editor_property("r", 0.2)
    MEL.connect_material_property(rgh, "", unreal.MaterialProperty.MP_ROUGHNESS)
    MEL.recompile_material(mat)
    eal.save_asset(MAT, only_if_is_dirty=False)
    L("M_LavaFluid built")

    act = None
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == "Magma_Fluid":
            act = a; break
    comp = act.get_component_by_class(unreal.NiagaraComponent)
    # override renderer materials (try a few slots)
    for i in range(3):
        try:
            comp.set_material(i, mat)
            L("set_material slot %d" % i)
        except Exception as e:
            L("slot %d err: %s" % (i, e))
    res["ok"] = True
except Exception as e:
    res["err"] = str(e); res["tb"] = traceback.format_exc()
open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_retint.json", "w", encoding="utf-8").write(
    json.dumps(res, ensure_ascii=False, indent=2))
print("RETINT", json.dumps(res, ensure_ascii=False))

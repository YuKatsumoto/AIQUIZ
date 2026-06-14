import unreal, json, traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_magma_debug.json"
SHOT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/magma_debug.png"
DBG = "/Game/AiQuiz/Materials/M_MagmaDebug"
res = {"ok": False, "log": []}
L = res["log"].append
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary

HLSL = open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/_magma_hlsl.txt", encoding="utf-8").read()


def E(mat, cls, x, y):
    return MEL.create_material_expression(mat, cls, x, y)


try:
    mat = None
    if eal.does_asset_exist(DBG):
        mat = eal.load_asset(DBG)
        MEL.delete_all_material_expressions(mat)
    if not mat:
        at = unreal.AssetToolsHelpers.get_asset_tools()
        mat = at.create_asset("M_MagmaDebug", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
    # Unlit so scene lighting cannot wash it
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)

    uv = E(mat, unreal.MaterialExpressionTextureCoordinate, -1400, -100)
    tnode = E(mat, unreal.MaterialExpressionTime, -1400, 80)
    custom = E(mat, unreal.MaterialExpressionCustom, -1050, -20)
    ci_uv = unreal.CustomInput(); ci_uv.set_editor_property("input_name", "UV")
    ci_t = unreal.CustomInput(); ci_t.set_editor_property("input_name", "Time")
    custom.set_editor_property("inputs", [ci_uv, ci_t])
    custom.set_editor_property("code", HLSL)
    custom.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT4)
    MEL.connect_material_expressions(uv, "", custom, "UV")
    MEL.connect_material_expressions(tnode, "", custom, "Time")

    col = E(mat, unreal.MaterialExpressionComponentMask, -780, -80)
    col.set_editor_property("r", True); col.set_editor_property("g", True)
    col.set_editor_property("b", True); col.set_editor_property("a", False)
    MEL.connect_material_expressions(custom, "", col, "")
    # Emissive = col directly (unlit), no scaling, so we see the true gradient
    MEL.connect_material_property(col, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)

    MEL.recompile_material(mat)
    eal.save_asset(DBG, only_if_is_dirty=False)
    L("debug mat built")

    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    magma = [a for a in eas.get_all_level_actors() if a.get_actor_label() == "Magma_Floor"][0]
    smc = magma.get_component_by_class(unreal.StaticMeshComponent)
    smc.set_material(0, mat)
    L("assigned debug to Magma_Floor")

    # neutral exposure
    ppv = [a for a in eas.get_all_level_actors() if a.get_actor_label() == "Stage_PostProcess"][0]
    s = ppv.get_editor_property("settings")
    s.set_editor_property("override_auto_exposure_min_brightness", True)
    s.set_editor_property("auto_exposure_min_brightness", 1.0)
    s.set_editor_property("override_auto_exposure_max_brightness", True)
    s.set_editor_property("auto_exposure_max_brightness", 1.0)
    ppv.set_editor_property("settings", s)

    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    ues.set_level_viewport_camera_info(unreal.Vector(400.0, 9000.0, 6000.0), unreal.Rotator(0.0, -70.0, 0.0))
    unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, SHOT)
    res["ok"] = True
except Exception as e:
    res["err"] = str(e); res["tb"] = traceback.format_exc()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
print("DEBUG", res.get("ok"), res.get("err", ""))

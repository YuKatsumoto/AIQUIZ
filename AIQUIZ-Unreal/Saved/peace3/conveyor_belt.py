import unreal, json, traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_belt.json"
MAT = "/Game/AiQuiz/Materials/M_ConveyorBelt"
res = {"ok": False, "log": []}
L = res["log"].append
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary
HLSL = open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/_belt_hlsl.txt", encoding="utf-8").read()


def E(m, c, x, y):
    return MEL.create_material_expression(m, c, x, y)


try:
    mat = None
    if eal.does_asset_exist(MAT):
        mat = eal.load_asset(MAT); MEL.delete_all_material_expressions(mat); L("cleared")
    if not mat:
        at = unreal.AssetToolsHelpers.get_asset_tools()
        mat = at.create_asset("M_ConveyorBelt", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
        L("created")

    wp = E(mat, unreal.MaterialExpressionWorldPosition, -1400, -100)
    nrm = E(mat, unreal.MaterialExpressionVertexNormalWS, -1400, 60)
    tnode = E(mat, unreal.MaterialExpressionTime, -1400, 220)

    custom = E(mat, unreal.MaterialExpressionCustom, -1050, 0)
    ins = []
    for nm in ("WP", "N", "Time"):
        ci = unreal.CustomInput(); ci.set_editor_property("input_name", nm); ins.append(ci)
    custom.set_editor_property("inputs", ins)
    custom.set_editor_property("code", HLSL)
    custom.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT4)
    custom.set_editor_property("description", "ConveyorBelt")
    MEL.connect_material_expressions(wp, "", custom, "WP")
    MEL.connect_material_expressions(nrm, "", custom, "N")
    MEL.connect_material_expressions(tnode, "", custom, "Time")

    albedo = E(mat, unreal.MaterialExpressionComponentMask, -780, -80)
    albedo.set_editor_property("r", True); albedo.set_editor_property("g", True)
    albedo.set_editor_property("b", True); albedo.set_editor_property("a", False)
    MEL.connect_material_expressions(custom, "", albedo, "")
    MEL.connect_material_property(albedo, "", unreal.MaterialProperty.MP_BASE_COLOR)

    rim = E(mat, unreal.MaterialExpressionComponentMask, -780, 120)
    rim.set_editor_property("r", False); rim.set_editor_property("g", False)
    rim.set_editor_property("b", False); rim.set_editor_property("a", True)
    MEL.connect_material_expressions(custom, "", rim, "")

    # metallic = 0.12 + rim*0.18
    mm = E(mat, unreal.MaterialExpressionMultiply, -560, 160); mm.set_editor_property("const_b", 0.18)
    MEL.connect_material_expressions(rim, "", mm, "A")
    ma = E(mat, unreal.MaterialExpressionAdd, -400, 160); ma.set_editor_property("const_b", 0.12)
    MEL.connect_material_expressions(mm, "", ma, "A")
    MEL.connect_material_property(ma, "", unreal.MaterialProperty.MP_METALLIC)

    # roughness = 0.78 - rim*0.045
    rm = E(mat, unreal.MaterialExpressionMultiply, -560, 300); rm.set_editor_property("const_b", -0.045)
    MEL.connect_material_expressions(rim, "", rm, "A")
    ra = E(mat, unreal.MaterialExpressionAdd, -400, 300); ra.set_editor_property("const_b", 0.78)
    MEL.connect_material_expressions(rm, "", ra, "A")
    MEL.connect_material_property(ra, "", unreal.MaterialProperty.MP_ROUGHNESS)

    MEL.recompile_material(mat)
    eal.save_asset(MAT, only_if_is_dirty=False)
    L("M_ConveyorBelt built")

    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    floor = [a for a in eas.get_all_level_actors() if a.get_actor_label() == "Stage_Floor"][0]
    floor.get_component_by_class(unreal.StaticMeshComponent).set_material(0, mat)
    L("assigned to Stage_Floor")
    res["ok"] = True
except Exception as e:
    res["err"] = str(e); res["tb"] = traceback.format_exc()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
print("BELT", res.get("ok"), res.get("err", ""))

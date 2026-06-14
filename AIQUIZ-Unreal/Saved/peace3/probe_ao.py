import unreal, json, traceback
OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_probe_ao.json"
res = {}
MEL = unreal.MaterialEditingLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
try:
    if unreal.EditorAssetLibrary.does_asset_exist("/Game/AiQuiz/Materials/M_ProbeAO"):
        unreal.EditorAssetLibrary.delete_asset("/Game/AiQuiz/Materials/M_ProbeAO")
    m = at.create_asset("M_ProbeAO", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
    res["m_ok"] = m is not None
    c = MEL.create_material_expression(m, unreal.MaterialExpressionCustom, 0, 0)
    ao = unreal.CustomOutput()
    ao.set_editor_property("output_name", "ExtraN")
    ao.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT3)
    try:
        c.set_editor_property("additional_outputs", [ao])
        g = c.get_editor_property("additional_outputs")
        res["AO_SET_OK"] = True
        res["len"] = len(g)
        res["name0"] = str(g[0].get_editor_property("output_name"))
    except Exception as e:
        res["AO_SET_FAIL"] = str(e)
    # also: can we connect a named output from the custom node?
    try:
        # connect_material_expressions(from, from_pin, to, to_pin) — output pin name "ExtraN"
        add = MEL.create_material_expression(m, unreal.MaterialExpressionAdd, 200, 0)
        MEL.connect_material_expressions(c, "ExtraN", add, "A")
        res["connect_named_ok"] = True
    except Exception as e:
        res["connect_named_err"] = str(e)
    unreal.EditorAssetLibrary.delete_asset("/Game/AiQuiz/Materials/M_ProbeAO")
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
print("PROBE_AO", json.dumps(res, ensure_ascii=False))

import unreal, json, traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_probe.json"
res = {"ok": False, "log": []}
L = res["log"].append


def has(name):
    return hasattr(unreal, name)


try:
    # --- 1. Custom node multiple outputs ---
    res["CustomOutput_exists"] = has("CustomOutput")
    if has("CustomOutput"):
        try:
            co = unreal.CustomOutput()
            props = [p for p in dir(co) if not p.startswith("_")]
            res["CustomOutput_props"] = props
            # try setting name/type
            try:
                co.set_editor_property("output_name", "TestOut")
                res["CustomOutput_set_name_ok"] = True
            except Exception as e:
                res["CustomOutput_set_name_err"] = str(e)
        except Exception as e:
            res["CustomOutput_instantiate_err"] = str(e)

    # Does MaterialExpressionCustom expose additional_outputs?
    try:
        # build a throwaway material in transient package
        at = unreal.AssetToolsHelpers.get_asset_tools()
        MEL = unreal.MaterialEditingLibrary
        tmp = at.create_asset("M_ProbeTmp", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
        cust = MEL.create_material_expression(tmp, unreal.MaterialExpressionCustom, 0, 0)
        cprops = [p for p in dir(cust) if not p.startswith("_")]
        res["Custom_has_additional_outputs"] = "additional_outputs" in cprops
        # try assigning an additional output
        if has("CustomOutput") and res.get("Custom_has_additional_outputs"):
            try:
                ao = unreal.CustomOutput()
                ao.set_editor_property("output_name", "ExtraN")
                try:
                    ao.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT3)
                except Exception as e2:
                    res["CustomOutput_type_err"] = str(e2)
                cust.set_editor_property("additional_outputs", [ao])
                got = cust.get_editor_property("additional_outputs")
                res["Custom_additional_outputs_set_ok"] = bool(got) and len(got) == 1
            except Exception as e:
                res["Custom_additional_outputs_set_err"] = str(e)
        # cleanup tmp material
        unreal.EditorAssetLibrary.delete_asset("/Game/AiQuiz/Materials/M_ProbeTmp")
    except Exception as e:
        res["Custom_probe_err"] = str(e)

    # --- 2. LocalPosition expression ---
    res["LocalPosition_exists"] = has("MaterialExpressionLocalPosition")
    res["ObjectLocalBounds_exists"] = has("MaterialExpressionObjectLocalBounds")
    res["VertexNormalWS_exists"] = has("MaterialExpressionVertexNormalWS")

    # --- 3. Mesh generation options ---
    res["DynamicMeshActor_exists"] = has("DynamicMeshActor")
    res["GeometryScript_Primitives_exists"] = has("GeometryScript_Primitives")
    res["GeometryScriptLibrary_MeshPrimitiveFunctions_exists"] = has("GeometryScriptLibrary_MeshPrimitiveFunctions")
    res["ProceduralMeshComponent_exists"] = has("ProceduralMeshComponent")
    res["StaticMeshDescription_exists"] = has("StaticMeshDescription")
    res["MeshDescription_exists"] = has("MeshDescription")
    # editor mesh tools that can subdivide / create from description
    res["EditorStaticMeshLibrary_exists"] = has("EditorStaticMeshLibrary")
    res["StaticMeshEditorSubsystem_exists"] = has("StaticMeshEditorSubsystem")

    # --- 4. MaterialProperty enums of interest ---
    mp = unreal.MaterialProperty
    res["MP_WORLD_POSITION_OFFSET"] = hasattr(mp, "MP_WORLD_POSITION_OFFSET")
    res["MP_NORMAL"] = hasattr(mp, "MP_NORMAL")
    res["MP_DISPLACEMENT"] = hasattr(mp, "MP_DISPLACEMENT")
    # list any displacement-ish members
    res["MP_members"] = [m for m in dir(mp) if m.startswith("MP_")]

    res["ok"] = True
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
unreal.log("PEACE3_PROBE ok=%s" % res.get("ok"))
print("PEACE3_PROBE", res.get("ok"), res.get("err", ""))

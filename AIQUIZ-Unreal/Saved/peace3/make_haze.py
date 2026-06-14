import unreal, json, traceback
OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_haze.json"
res = {"ok": False, "log": []}
L = res["log"].append
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary
MAT = "/Game/AiQuiz/Materials/M_HeatHaze"


def E(mat, cls, x, y):
    return MEL.create_material_expression(mat, cls, x, y)


HAZE = (
    "float Tw = fmod(Time, 120.0);\n"
    "float2 p = UV * HazeScale;\n"
    "float nx = sin(p.y*3.1 + Tw*2.0) + 0.5*sin(p.y*7.3 - Tw*1.3) + 0.35*sin(p.x*5.0 + Tw*1.7);\n"
    "float ny = cos(p.x*2.7 + Tw*1.5) + 0.5*cos(p.x*6.1 + Tw*2.1) + 0.35*sin(p.y*4.0 - Tw*1.1);\n"
    "return normalize(float3(nx*HazeStrength, ny*HazeStrength, 6.0));\n"
)

try:
    mat = None
    if eal.does_asset_exist(MAT):
        mat = eal.load_asset(MAT)
        MEL.delete_all_material_expressions(mat)
        L("reused M_HeatHaze")
    if not mat:
        at = unreal.AssetToolsHelpers.get_asset_tools()
        mat = at.create_asset("M_HeatHaze", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
        L("created M_HeatHaze")

    mat.set_editor_property("blend_mode", unreal.BlendMode.BLEND_TRANSLUCENT)
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    mat.set_editor_property("two_sided", True)
    try:
        mat.set_editor_property("refraction_method", unreal.RefractionMode.RM_PIXEL_NORMAL_OFFSET)
        L("refraction = pixel normal offset")
    except Exception as e:
        L("refraction set err: %s" % e)

    uv = E(mat, unreal.MaterialExpressionTextureCoordinate, -1000, -100)
    tnode = E(mat, unreal.MaterialExpressionTime, -1000, 60)

    def sp(name, val, x, y):
        n = E(mat, unreal.MaterialExpressionScalarParameter, x, y)
        n.set_editor_property("parameter_name", name)
        n.set_editor_property("default_value", val)
        return n

    p_hs = sp("HazeScale", 10.0, -1000, 220)
    p_hst = sp("HazeStrength", 0.8, -1000, 300)
    p_op = sp("HazeOpacity", 0.05, -1000, 380)
    p_rf = sp("HazeRefract", 1.3, -1000, 460)

    def cin(name):
        c = unreal.CustomInput(); c.set_editor_property("input_name", name); return c

    cust = E(mat, unreal.MaterialExpressionCustom, -700, 0)
    cust.set_editor_property("inputs", [cin("UV"), cin("Time"), cin("HazeScale"), cin("HazeStrength")])
    cust.set_editor_property("code", HAZE)
    cust.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT3)
    cust.set_editor_property("description", "HazeNormal")
    MEL.connect_material_expressions(uv, "", cust, "UV")
    MEL.connect_material_expressions(tnode, "", cust, "Time")
    MEL.connect_material_expressions(p_hs, "", cust, "HazeScale")
    MEL.connect_material_expressions(p_hst, "", cust, "HazeStrength")
    # fade the wobble normal to flat at distance so the plane doesn't smear the
    # horizon into watery blobs (grazing refraction over-distorts far away).
    pd = E(mat, unreal.MaterialExpressionPixelDepth, -520, 120)
    fs = E(mat, unreal.MaterialExpressionSubtract, -400, 120)
    fs.set_editor_property("const_b", 1000.0)
    MEL.connect_material_expressions(pd, "", fs, "A")
    fdv = E(mat, unreal.MaterialExpressionMultiply, -300, 120)
    fdv.set_editor_property("const_b", 1.0 / 4000.0)
    MEL.connect_material_expressions(fs, "", fdv, "A")
    fcl = E(mat, unreal.MaterialExpressionClamp, -200, 120)
    fcl.set_editor_property("min_default", 0.0)
    fcl.set_editor_property("max_default", 1.0)
    MEL.connect_material_expressions(fdv, "", fcl, "")
    flatn = E(mat, unreal.MaterialExpressionConstant3Vector, -520, 220)
    flatn.set_editor_property("constant", unreal.LinearColor(0.0, 0.0, 1.0, 1.0))
    nlrp = E(mat, unreal.MaterialExpressionLinearInterpolate, -360, 0)
    MEL.connect_material_expressions(cust, "", nlrp, "A")
    MEL.connect_material_expressions(flatn, "", nlrp, "B")
    MEL.connect_material_expressions(fcl, "", nlrp, "Alpha")
    MEL.connect_material_property(nlrp, "", unreal.MaterialProperty.MP_NORMAL)

    # subtle warm emissive tint so the haze volume also reads as hot air
    warm = E(mat, unreal.MaterialExpressionConstant3Vector, -700, 300)
    warm.set_editor_property("constant", unreal.LinearColor(0.25, 0.08, 0.0, 1.0))
    ew = E(mat, unreal.MaterialExpressionMultiply, -520, 320)
    MEL.connect_material_expressions(warm, "", ew, "A")
    MEL.connect_material_expressions(p_op, "", ew, "B")
    MEL.connect_material_property(ew, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)

    MEL.connect_material_property(p_op, "", unreal.MaterialProperty.MP_OPACITY)
    MEL.connect_material_property(p_rf, "", unreal.MaterialProperty.MP_REFRACTION)

    MEL.recompile_material(mat)
    eal.save_asset(MAT, only_if_is_dirty=False)
    L("M_HeatHaze built")

    # spawn the haze plane just above the magma
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == "Stage_HeatHaze":
            eas.destroy_actor(a)
            L("removed old Stage_HeatHaze")
    plane = eal.load_asset("/Engine/BasicShapes/Plane")
    actor = eas.spawn_actor_from_object(plane, unreal.Vector(400.0, 0.0, -150.0), unreal.Rotator(0, 0, 0))
    actor.set_actor_label("Stage_HeatHaze")
    actor.set_actor_scale3d(unreal.Vector(340.0, 340.0, 1.0))
    smc = actor.get_component_by_class(unreal.StaticMeshComponent)
    smc.set_material(0, mat)
    try:
        smc.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
        smc.set_editor_property("cast_shadow", False)
    except Exception as e:
        L("comp tweak: %s" % e)
    L("spawned Stage_HeatHaze")
    res["ok"] = True
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()

open(OUT, "w", encoding="utf-8").write(json.dumps(res, ensure_ascii=False, indent=2))
print("HAZE", json.dumps(res, ensure_ascii=False))

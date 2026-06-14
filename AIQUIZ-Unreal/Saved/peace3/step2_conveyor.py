import unreal, json, traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_step2.json"
MAT_PATH = "/Game/AiQuiz/Materials/M_ConveyorFloor"
res = {"ok": False, "log": []}
L = res["log"].append

MEL = unreal.MaterialEditingLibrary


def expr(mat, cls, x, y):
    return MEL.create_material_expression(mat, cls, x, y)


try:
    mat = unreal.EditorAssetLibrary.load_asset(MAT_PATH)
    if not mat:
        raise RuntimeError("M_ConveyorFloor not found")

    # Clear any existing graph so the rebuild is clean.
    try:
        MEL.delete_all_material_expressions(mat)
        L("cleared existing expressions")
    except Exception as e:
        L("delete_all_material_expressions unavailable: %s" % e)

    # --- Parameters ---
    p_speed = expr(mat, unreal.MaterialExpressionScalarParameter, -1100, -200)
    p_speed.set_editor_property("parameter_name", "ScrollSpeed")
    p_speed.set_editor_property("default_value", 400.0)  # uu/sec (~4 m/s, matches Godot)
    p_speed.set_editor_property("group", "Conveyor")

    p_offset = expr(mat, unreal.MaterialExpressionScalarParameter, -1100, -80)
    p_offset.set_editor_property("parameter_name", "ScrollOffset")
    p_offset.set_editor_property("default_value", 0.0)  # optional gameplay-driven offset
    p_offset.set_editor_property("group", "Conveyor")

    p_freq = expr(mat, unreal.MaterialExpressionScalarParameter, -1100, 40)
    p_freq.set_editor_property("parameter_name", "StripeScale")
    p_freq.set_editor_property("default_value", 0.0264)  # rad/uu -> ~2.4m stripe period
    p_freq.set_editor_property("group", "Conveyor")

    p_base = expr(mat, unreal.MaterialExpressionVectorParameter, -500, 250)
    p_base.set_editor_property("parameter_name", "BaseColor")
    p_base.set_editor_property("default_value", unreal.LinearColor(0.40, 0.41, 0.42, 1.0))
    p_base.set_editor_property("group", "Conveyor")

    p_stripe = expr(mat, unreal.MaterialExpressionVectorParameter, -500, 400)
    p_stripe.set_editor_property("parameter_name", "StripeColor")
    p_stripe.set_editor_property("default_value", unreal.LinearColor(0.34, 0.345, 0.35, 1.0))
    p_stripe.set_editor_property("group", "Conveyor")

    p_rough = expr(mat, unreal.MaterialExpressionScalarParameter, -500, 560)
    p_rough.set_editor_property("parameter_name", "Roughness")
    p_rough.set_editor_property("default_value", 0.78)
    p_rough.set_editor_property("group", "Conveyor")

    p_metal = expr(mat, unreal.MaterialExpressionScalarParameter, -500, 660)
    p_metal.set_editor_property("parameter_name", "Metallic")
    p_metal.set_editor_property("default_value", 0.12)
    p_metal.set_editor_property("group", "Conveyor")

    # --- Position along travel axis (world X) ---
    # Extract X via dot(WorldPos, (1,0,0)) -- unambiguous vs ComponentMask.
    wp = expr(mat, unreal.MaterialExpressionWorldPosition, -1400, -400)
    axis = expr(mat, unreal.MaterialExpressionConstant3Vector, -1400, -260)
    axis.set_editor_property("constant", unreal.LinearColor(1.0, 0.0, 0.0, 0.0))
    maskx = expr(mat, unreal.MaterialExpressionDotProduct, -1200, -400)
    MEL.connect_material_expressions(wp, "", maskx, "A")
    MEL.connect_material_expressions(axis, "", maskx, "B")

    # --- Time * ScrollSpeed ---
    t = expr(mat, unreal.MaterialExpressionTime, -1400, -150)
    mul_ts = expr(mat, unreal.MaterialExpressionMultiply, -950, -180)
    MEL.connect_material_expressions(t, "", mul_ts, "A")
    MEL.connect_material_expressions(p_speed, "", mul_ts, "B")

    # add_xt = worldX + Time*Speed
    add_xt = expr(mat, unreal.MaterialExpressionAdd, -780, -300)
    MEL.connect_material_expressions(maskx, "", add_xt, "A")
    MEL.connect_material_expressions(mul_ts, "", add_xt, "B")

    # add_off = add_xt + ScrollOffset
    add_off = expr(mat, unreal.MaterialExpressionAdd, -620, -250)
    MEL.connect_material_expressions(add_xt, "", add_off, "A")
    MEL.connect_material_expressions(p_offset, "", add_off, "B")

    # mul_freq = add_off * StripeScale
    mul_freq = expr(mat, unreal.MaterialExpressionMultiply, -460, -200)
    MEL.connect_material_expressions(add_off, "", mul_freq, "A")
    MEL.connect_material_expressions(p_freq, "", mul_freq, "B")

    # sine (period 2*pi -> output = sin(input))
    sine = expr(mat, unreal.MaterialExpressionSine, -300, -200)
    sine.set_editor_property("period", 6.2831853)
    MEL.connect_material_expressions(mul_freq, "", sine, "")

    # remap sin (-1..1) -> (0..1): *0.5 + 0.5
    half = expr(mat, unreal.MaterialExpressionMultiply, -150, -200)
    half.set_editor_property("const_b", 0.5)
    MEL.connect_material_expressions(sine, "", half, "A")
    bias = expr(mat, unreal.MaterialExpressionAdd, -20, -200)
    bias.set_editor_property("const_b", 0.5)
    MEL.connect_material_expressions(half, "", bias, "A")

    # lerp(base, stripe, alpha)
    lerp = expr(mat, unreal.MaterialExpressionLinearInterpolate, 150, 250)
    MEL.connect_material_expressions(p_base, "", lerp, "A")
    MEL.connect_material_expressions(p_stripe, "", lerp, "B")
    MEL.connect_material_expressions(bias, "", lerp, "Alpha")

    # --- Connect to material outputs ---
    MEL.connect_material_property(lerp, "", unreal.MaterialProperty.MP_BASE_COLOR)
    MEL.connect_material_property(p_rough, "", unreal.MaterialProperty.MP_ROUGHNESS)
    MEL.connect_material_property(p_metal, "", unreal.MaterialProperty.MP_METALLIC)

    MEL.recompile_material(mat)
    unreal.EditorAssetLibrary.save_asset(MAT_PATH, only_if_is_dirty=False)
    L("material rebuilt + saved")

    # --- Reassign base material to Stage_Floor (drop runtime MID) ---
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    floor = None
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == "Stage_Floor":
            floor = a
            break
    if floor:
        smc = floor.get_component_by_class(unreal.StaticMeshComponent)
        smc.set_material(0, mat)
        L("reassigned M_ConveyorFloor to Stage_Floor slot 0")
    else:
        L("Stage_Floor not found for reassign")

    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    saved = les.save_current_level()
    L("save_current_level=%s" % saved)

    res["ok"] = True
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
unreal.log("PEACE3_STEP2_DONE ok=%s" % res.get("ok"))

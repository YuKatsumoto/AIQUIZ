import unreal, json, traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_step3.json"
MAT_DIR = "/Game/AiQuiz/Materials"
MAT_NAME = "M_Magma"
MAT_PATH = MAT_DIR + "/" + MAT_NAME
res = {"ok": False, "log": []}
L = res["log"].append
MEL = unreal.MaterialEditingLibrary


def E(mat, cls, x, y):
    return MEL.create_material_expression(mat, cls, x, y)


def C3(mat, x, y, r, g, b):
    n = E(mat, unreal.MaterialExpressionConstant3Vector, x, y)
    n.set_editor_property("constant", unreal.LinearColor(r, g, b, 1.0))
    return n


try:
    eal = unreal.EditorAssetLibrary
    mat = None
    # Idempotent: reuse the existing material (clearing its node graph) instead
    # of delete+create. A partially-built M_Magma left loaded in memory by a
    # prior failed run makes delete_asset/create_asset return None, so reusing
    # the loaded asset is the robust path.
    if eal.does_asset_exist(MAT_PATH):
        mat = eal.load_asset(MAT_PATH)
        if mat:
            MEL.delete_all_material_expressions(mat)
            L("reused + cleared existing M_Magma")
        else:
            eal.delete_asset(MAT_PATH)
    if not eal.does_asset_exist(MAT_PATH) or not mat:
        at = unreal.AssetToolsHelpers.get_asset_tools()
        mat = at.create_asset(MAT_NAME, MAT_DIR, unreal.Material, unreal.MaterialFactoryNew())
        L("created new M_Magma")
    if not mat:
        raise RuntimeError("failed to create M_Magma")

    # --- Animated noise positions ---
    wp = E(mat, unreal.MaterialExpressionWorldPosition, -2000, 0)
    t = E(mat, unreal.MaterialExpressionTime, -2000, 200)

    flow1dir = C3(mat, -1850, 240, 8.0, 3.0, 0.0)
    flow1 = E(mat, unreal.MaterialExpressionMultiply, -1700, 220)
    MEL.connect_material_expressions(t, "", flow1, "A")
    MEL.connect_material_expressions(flow1dir, "", flow1, "B")
    pos1 = E(mat, unreal.MaterialExpressionAdd, -1550, 80)
    MEL.connect_material_expressions(wp, "", pos1, "A")
    MEL.connect_material_expressions(flow1, "", pos1, "B")

    flow2dir = C3(mat, -1850, 420, -5.0, 4.0, 0.0)
    flow2 = E(mat, unreal.MaterialExpressionMultiply, -1700, 400)
    MEL.connect_material_expressions(t, "", flow2, "A")
    MEL.connect_material_expressions(flow2dir, "", flow2, "B")
    pos2 = E(mat, unreal.MaterialExpressionAdd, -1550, 320)
    MEL.connect_material_expressions(wp, "", pos2, "A")
    MEL.connect_material_expressions(flow2, "", pos2, "B")

    # --- Noise nodes ---
    n_flow = E(mat, unreal.MaterialExpressionNoise, -1350, 60)
    # NOTE: MaterialExpressionNoise.Function is protected (cannot be set via
    # Python in UE 5.7). The node default is NOISEFUNCTION_SIMPLEX_TEX, which is
    # exactly what the flow layer wants, so we leave it unset.
    n_flow.set_editor_property("scale", 0.0025)
    n_flow.set_editor_property("output_min", 0.0)
    n_flow.set_editor_property("output_max", 1.0)
    n_flow.set_editor_property("levels", 3)
    n_flow.set_editor_property("turbulence", True)
    MEL.connect_material_expressions(pos1, "", n_flow, "Position")

    n_crack = E(mat, unreal.MaterialExpressionNoise, -1350, 320)
    # Voronoi would be ideal for molten-plate cracks, but Function is protected
    # in UE 5.7 Python. Phase 1 leaves the default simplex; Phase 2 swaps this
    # layer for an HLSL Custom voronoi if the look needs sharper cracks.
    n_crack.set_editor_property("scale", 0.004)
    n_crack.set_editor_property("output_min", 0.0)
    n_crack.set_editor_property("output_max", 1.0)
    n_crack.set_editor_property("levels", 2)
    n_crack.set_editor_property("turbulence", False)
    MEL.connect_material_expressions(pos2, "", n_crack, "Position")

    # --- heat = clamp(cracks*1.2 + flow*0.3) ---
    mc = E(mat, unreal.MaterialExpressionMultiply, -1100, 320)
    mc.set_editor_property("const_b", 1.2)
    MEL.connect_material_expressions(n_crack, "", mc, "A")
    mflo = E(mat, unreal.MaterialExpressionMultiply, -1100, 120)
    mflo.set_editor_property("const_b", 0.3)
    MEL.connect_material_expressions(n_flow, "", mflo, "A")
    hsum = E(mat, unreal.MaterialExpressionAdd, -950, 220)
    MEL.connect_material_expressions(mc, "", hsum, "A")
    MEL.connect_material_expressions(mflo, "", hsum, "B")
    heat = E(mat, unreal.MaterialExpressionClamp, -800, 220)
    heat.set_editor_property("min_default", 0.0)
    heat.set_editor_property("max_default", 1.0)
    MEL.connect_material_expressions(hsum, "", heat, "")

    # --- 4-stop color ramp via seg = heat*3 ---
    seg = E(mat, unreal.MaterialExpressionMultiply, -650, 220)
    seg.set_editor_property("const_b", 3.0)
    MEL.connect_material_expressions(heat, "", seg, "A")

    c0 = C3(mat, -500, -120, 0.15, 0.02, 0.0)
    c1 = C3(mat, -500, -20, 0.85, 0.18, 0.0)
    c2 = C3(mat, -500, 80, 1.0, 0.65, 0.0)
    c3 = C3(mat, -500, 180, 1.0, 0.95, 0.6)

    a01 = E(mat, unreal.MaterialExpressionClamp, -500, 300)
    a01.set_editor_property("min_default", 0.0)
    a01.set_editor_property("max_default", 1.0)
    MEL.connect_material_expressions(seg, "", a01, "")
    l1 = E(mat, unreal.MaterialExpressionLinearInterpolate, -300, -40)
    MEL.connect_material_expressions(c0, "", l1, "A")
    MEL.connect_material_expressions(c1, "", l1, "B")
    MEL.connect_material_expressions(a01, "", l1, "Alpha")

    s1 = E(mat, unreal.MaterialExpressionSubtract, -500, 380)
    s1.set_editor_property("const_b", 1.0)
    MEL.connect_material_expressions(seg, "", s1, "A")
    a12 = E(mat, unreal.MaterialExpressionClamp, -350, 380)
    a12.set_editor_property("min_default", 0.0)
    a12.set_editor_property("max_default", 1.0)
    MEL.connect_material_expressions(s1, "", a12, "")
    l2 = E(mat, unreal.MaterialExpressionLinearInterpolate, -150, 40)
    MEL.connect_material_expressions(l1, "", l2, "A")
    MEL.connect_material_expressions(c2, "", l2, "B")
    MEL.connect_material_expressions(a12, "", l2, "Alpha")

    s2 = E(mat, unreal.MaterialExpressionSubtract, -500, 460)
    s2.set_editor_property("const_b", 2.0)
    MEL.connect_material_expressions(seg, "", s2, "A")
    a23 = E(mat, unreal.MaterialExpressionClamp, -350, 460)
    a23.set_editor_property("min_default", 0.0)
    a23.set_editor_property("max_default", 1.0)
    MEL.connect_material_expressions(s2, "", a23, "")
    color = E(mat, unreal.MaterialExpressionLinearInterpolate, 0, 120)
    MEL.connect_material_expressions(l2, "", color, "A")
    MEL.connect_material_expressions(c3, "", color, "B")
    MEL.connect_material_expressions(a23, "", color, "Alpha")

    # --- pulse = 1 + 0.08*sin(Time*3) ---
    t3 = E(mat, unreal.MaterialExpressionMultiply, -650, 560)
    t3.set_editor_property("const_b", 3.0)
    MEL.connect_material_expressions(t, "", t3, "A")
    sinp = E(mat, unreal.MaterialExpressionSine, -500, 560)
    sinp.set_editor_property("period", 6.2831853)
    MEL.connect_material_expressions(t3, "", sinp, "")
    p1 = E(mat, unreal.MaterialExpressionMultiply, -350, 560)
    p1.set_editor_property("const_b", 0.08)
    MEL.connect_material_expressions(sinp, "", p1, "A")
    pulse = E(mat, unreal.MaterialExpressionAdd, -200, 560)
    pulse.set_editor_property("const_b", 1.0)
    MEL.connect_material_expressions(p1, "", pulse, "A")

    # --- emissive = color * intensity * heat * pulse ---
    pint = E(mat, unreal.MaterialExpressionScalarParameter, 0, 380)
    pint.set_editor_property("parameter_name", "EmissiveIntensity")
    pint.set_editor_property("default_value", 9.0)
    e1 = E(mat, unreal.MaterialExpressionMultiply, 200, 200)
    MEL.connect_material_expressions(color, "", e1, "A")
    MEL.connect_material_expressions(pint, "", e1, "B")
    e2 = E(mat, unreal.MaterialExpressionMultiply, 350, 200)
    MEL.connect_material_expressions(e1, "", e2, "A")
    MEL.connect_material_expressions(heat, "", e2, "B")
    e3 = E(mat, unreal.MaterialExpressionMultiply, 500, 200)
    MEL.connect_material_expressions(e2, "", e3, "A")
    MEL.connect_material_expressions(pulse, "", e3, "B")
    MEL.connect_material_property(e3, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)

    # base color (dark) + roughness
    bc = E(mat, unreal.MaterialExpressionMultiply, 200, 420)
    bc.set_editor_property("const_b", 0.06)
    MEL.connect_material_expressions(color, "", bc, "A")
    MEL.connect_material_property(bc, "", unreal.MaterialProperty.MP_BASE_COLOR)
    prough = E(mat, unreal.MaterialExpressionScalarParameter, 200, 560)
    prough.set_editor_property("parameter_name", "Roughness")
    prough.set_editor_property("default_value", 0.4)
    MEL.connect_material_property(prough, "", unreal.MaterialProperty.MP_ROUGHNESS)

    MEL.recompile_material(mat)
    eal.save_asset(MAT_PATH, only_if_is_dirty=False)
    L("M_Magma built + saved")

    # --- Spawn the magma plane below the belt ---
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    # remove old magma if present
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == "Magma_Floor":
            eas.destroy_actor(a)
            L("removed old Magma_Floor")
    plane_mesh = eal.load_asset("/Engine/BasicShapes/Plane")
    loc = unreal.Vector(400.0, 0.0, -360.0)
    rot = unreal.Rotator(0.0, 0.0, 0.0)
    actor = eas.spawn_actor_from_object(plane_mesh, loc, rot)
    actor.set_actor_label("Magma_Floor")
    actor.set_actor_scale3d(unreal.Vector(360.0, 360.0, 1.0))
    smc = actor.get_component_by_class(unreal.StaticMeshComponent)
    smc.set_material(0, mat)
    try:
        smc.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
        smc.set_editor_property("cast_shadow", False)
    except Exception as e:
        L("collision/shadow tweak skipped: %s" % e)
    L("spawned Magma_Floor")

    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    L("save_current_level=%s" % les.save_current_level())
    res["ok"] = True
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
unreal.log("PEACE3_STEP3_DONE ok=%s" % res.get("ok"))

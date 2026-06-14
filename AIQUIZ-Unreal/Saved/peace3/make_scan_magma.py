import unreal, json, traceback
OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_scan.json"
res = {"ok": False, "log": []}
L = res["log"].append
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary
SRC = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/lava_scan/"
TEXDIR = "/Game/AiQuiz/Textures"


def E(mat, cls, x, y):
    return MEL.create_material_expression(mat, cls, x, y)


def imp(fname, asset, srgb, comp, flip_green=False):
    path = TEXDIR + "/" + asset
    if eal.does_asset_exist(path):
        eal.delete_asset(path)
    task = unreal.AssetImportTask()
    task.set_editor_property("filename", SRC + fname)
    task.set_editor_property("destination_path", TEXDIR)
    task.set_editor_property("destination_name", asset)
    task.set_editor_property("automated", True)
    task.set_editor_property("replace_existing", True)
    task.set_editor_property("save", True)
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    t = eal.load_asset(path)
    if t:
        t.set_editor_property("srgb", srgb)
        t.set_editor_property("compression_settings", comp)
        if comp == unreal.TextureCompressionSettings.TC_NORMALMAP:
            t.set_editor_property("flip_green_channel", flip_green)
        eal.save_asset(path, only_if_is_dirty=False)
    return t


try:
    TC = unreal.TextureCompressionSettings
    col = imp("Lava001_2K-JPG_Color.jpg", "T_Lava_Color", True, TC.TC_DEFAULT)
    nrm = imp("Lava001_2K-JPG_NormalDX.jpg", "T_Lava_Normal", False, TC.TC_NORMALMAP)
    rgh = imp("Lava001_2K-JPG_Roughness.jpg", "T_Lava_Rough", False, TC.TC_GRAYSCALE)
    emi = imp("Lava001_2K-JPG_Emission.jpg", "T_Lava_Emiss", True, TC.TC_DEFAULT)
    L("imported 4 textures")

    MAT = "/Game/AiQuiz/Materials/M_MagmaScan"
    mat = None
    if eal.does_asset_exist(MAT):
        mat = eal.load_asset(MAT)
        MEL.delete_all_material_expressions(mat)
    if not mat:
        mat = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
            "M_MagmaScan", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())

    # tiled, slowly flowing UVs (floor is ~360m; tile the 2K lava across it).
    tc = E(mat, unreal.MaterialExpressionTextureCoordinate, -1100, 0)
    tc.set_editor_property("u_tiling", 8.0)
    tc.set_editor_property("v_tiling", 8.0)
    # explicit flow = tc + Time*dir  (Panner's coordinate pin wouldn't bind)
    tnode = E(mat, unreal.MaterialExpressionTime, -1300, 240)
    fdir = E(mat, unreal.MaterialExpressionConstant2Vector, -1100, 220)
    fdir.set_editor_property("r", 0.0)
    fdir.set_editor_property("g", 0.05)
    ft = E(mat, unreal.MaterialExpressionMultiply, -950, 200)
    MEL.connect_material_expressions(tnode, "", ft, "A")
    MEL.connect_material_expressions(fdir, "", ft, "B")
    uvf = E(mat, unreal.MaterialExpressionAdd, -820, 60)
    MEL.connect_material_expressions(tc, "", uvf, "A")
    MEL.connect_material_expressions(ft, "", uvf, "B")

    def tex(t, x, y, samp):
        n = E(mat, unreal.MaterialExpressionTextureSample, x, y)
        n.set_editor_property("texture", t)
        n.set_editor_property("sampler_type", samp)
        MEL.connect_material_expressions(tc, "", n, "UVs")
        return n

    ST = unreal.MaterialSamplerType
    s_col = tex(col, -650, -260, ST.SAMPLERTYPE_COLOR)
    s_nrm = tex(nrm, -650, -60, ST.SAMPLERTYPE_NORMAL)
    s_rgh = tex(rgh, -650, 160, ST.SAMPLERTYPE_LINEAR_COLOR)
    s_emi = tex(emi, -650, 360, ST.SAMPLERTYPE_COLOR)

    MEL.connect_material_property(s_col, "", unreal.MaterialProperty.MP_BASE_COLOR)
    MEL.connect_material_property(s_nrm, "", unreal.MaterialProperty.MP_NORMAL)
    MEL.connect_material_property(s_rgh, "", unreal.MaterialProperty.MP_ROUGHNESS)

    # emissive = Emission * intensity * pulse
    pint = E(mat, unreal.MaterialExpressionScalarParameter, -300, 460)
    pint.set_editor_property("parameter_name", "EmissiveIntensity")
    pint.set_editor_property("default_value", 3.5)
    t2 = E(mat, unreal.MaterialExpressionMultiply, -460, 560)
    t2.set_editor_property("const_b", 2.0)
    MEL.connect_material_expressions(tnode, "", t2, "A")
    sn = E(mat, unreal.MaterialExpressionSine, -320, 560)
    sn.set_editor_property("period", 6.2831853)
    MEL.connect_material_expressions(t2, "", sn, "")
    sm = E(mat, unreal.MaterialExpressionMultiply, -180, 560)
    sm.set_editor_property("const_b", 0.08)
    MEL.connect_material_expressions(sn, "", sm, "A")
    pls = E(mat, unreal.MaterialExpressionAdd, -40, 560)
    pls.set_editor_property("const_b", 1.0)
    MEL.connect_material_expressions(sm, "", pls, "A")
    # The bundled emission map is too dim to read at the scene's locked exposure.
    # Drive the glow from the COLOR map instead (its orange flow is already bright)
    # and use the emission map as a contrast boost so the dark crust stays cooler.
    emR = E(mat, unreal.MaterialExpressionComponentMask, -480, 300)
    emR.set_editor_property("r", True); emR.set_editor_property("g", False)
    emR.set_editor_property("b", False); emR.set_editor_property("a", False)
    MEL.connect_material_expressions(s_emi, "", emR, "")
    emb = E(mat, unreal.MaterialExpressionMultiply, -360, 300)
    emb.set_editor_property("const_b", 3.0)
    MEL.connect_material_expressions(emR, "", emb, "A")
    emask = E(mat, unreal.MaterialExpressionClamp, -240, 300)
    emask.set_editor_property("min_default", 0.25)   # crust still glows faintly
    emask.set_editor_property("max_default", 1.0)
    MEL.connect_material_expressions(emb, "", emask, "")
    emcol = E(mat, unreal.MaterialExpressionMultiply, -120, 240)
    MEL.connect_material_expressions(s_col, "", emcol, "A")
    MEL.connect_material_expressions(emask, "", emcol, "B")
    e1 = E(mat, unreal.MaterialExpressionMultiply, -20, 360)
    MEL.connect_material_expressions(emcol, "", e1, "A")
    MEL.connect_material_expressions(pint, "", e1, "B")
    e2 = E(mat, unreal.MaterialExpressionMultiply, 60, 400)
    MEL.connect_material_expressions(e1, "", e2, "A")
    MEL.connect_material_expressions(pls, "", e2, "B")
    MEL.connect_material_property(e2, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)

    MEL.recompile_material(mat)
    eal.save_asset(MAT, only_if_is_dirty=False)
    L("M_MagmaScan built")

    # apply to Magma_Floor for side-by-side comparison
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == "Magma_Floor":
            smc = a.get_component_by_class(unreal.StaticMeshComponent)
            smc.set_material(0, mat)
            L("applied M_MagmaScan to Magma_Floor")
            break
    res["ok"] = True
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()

open(OUT, "w", encoding="utf-8").write(json.dumps(res, ensure_ascii=False, indent=2))
print("SCAN", json.dumps(res, ensure_ascii=False))

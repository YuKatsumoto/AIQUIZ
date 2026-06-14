import unreal, json, traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_magma_v2.json"
MAT_PATH = "/Game/AiQuiz/Materials/M_Magma"
res = {"ok": False, "log": []}
L = res["log"].append
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary

# Simple molten-LIQUID surface (no crack/crust pattern): single colour + animated
# ripple normal + gentle swell WPO. Single source of truth shared with debug mats.
HLSL = open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/_magma_hlsl.txt", encoding="utf-8").read()


def E(mat, cls, x, y):
    return MEL.create_material_expression(mat, cls, x, y)


def C3(mat, x, y, r, g, b):
    n = E(mat, unreal.MaterialExpressionConstant3Vector, x, y)
    n.set_editor_property("constant", unreal.LinearColor(r, g, b, 1.0))
    return n


try:
    mat = None
    if eal.does_asset_exist(MAT_PATH):
        mat = eal.load_asset(MAT_PATH)
        MEL.delete_all_material_expressions(mat)
        L("reused + cleared M_Magma")
    if not mat:
        at = unreal.AssetToolsHelpers.get_asset_tools()
        mat = at.create_asset("M_Magma", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
        L("created M_Magma")

    uv = E(mat, unreal.MaterialExpressionTextureCoordinate, -1400, -100)
    tnode = E(mat, unreal.MaterialExpressionTime, -1400, 80)

    def sp(name, val, x, y):
        n = E(mat, unreal.MaterialExpressionScalarParameter, x, y)
        n.set_editor_property("parameter_name", name)
        n.set_editor_property("default_value", val)
        return n

    p_rs = sp("RippleScale", 40.0, -1400, 260)
    p_rst = sp("RippleStrength", 2.5, -1400, 340)

    # solid molten colour (single source of the surface hue)
    lavacol = E(mat, unreal.MaterialExpressionVectorParameter, -1400, -260)
    lavacol.set_editor_property("parameter_name", "LavaColor")
    lavacol.set_editor_property("default_value", unreal.LinearColor(1.0, 0.30, 0.05, 1.0))

    # --- Custom HLSL: main output = brightness(float), additional = OutNormal ---
    custom = E(mat, unreal.MaterialExpressionCustom, -1050, -20)

    def cin(name):
        c = unreal.CustomInput()
        c.set_editor_property("input_name", name)
        return c

    custom.set_editor_property("inputs", [cin("UV"), cin("Time"), cin("RippleScale"), cin("RippleStrength")])
    ao_n = unreal.CustomOutput()
    ao_n.set_editor_property("output_name", "OutNormal")
    ao_n.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT3)
    custom.set_editor_property("additional_outputs", [ao_n])
    custom.set_editor_property("code", HLSL)
    custom.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT1)
    custom.set_editor_property("description", "MagmaLiquid")
    MEL.connect_material_expressions(uv, "", custom, "UV")
    MEL.connect_material_expressions(tnode, "", custom, "Time")
    MEL.connect_material_expressions(p_rs, "", custom, "RippleScale")
    MEL.connect_material_expressions(p_rst, "", custom, "RippleStrength")

    # pulse = 1 + sin(Time*2)*0.06
    t3 = E(mat, unreal.MaterialExpressionMultiply, -780, 260)
    t3.set_editor_property("const_b", 2.0)
    MEL.connect_material_expressions(tnode, "", t3, "A")
    sinp = E(mat, unreal.MaterialExpressionSine, -640, 260)
    sinp.set_editor_property("period", 6.2831853)
    MEL.connect_material_expressions(t3, "", sinp, "")
    p08 = E(mat, unreal.MaterialExpressionMultiply, -500, 260)
    p08.set_editor_property("const_b", 0.06)
    MEL.connect_material_expressions(sinp, "", p08, "A")
    pulse = E(mat, unreal.MaterialExpressionAdd, -360, 260)
    pulse.set_editor_property("const_b", 1.0)
    MEL.connect_material_expressions(p08, "", pulse, "A")

    # emissive = LavaColor * EmissiveIntensity * brightness * pulse
    pint = E(mat, unreal.MaterialExpressionScalarParameter, -720, -200)
    pint.set_editor_property("parameter_name", "EmissiveIntensity")
    pint.set_editor_property("default_value", 5.0)
    eint = E(mat, unreal.MaterialExpressionMultiply, -560, -160)
    MEL.connect_material_expressions(lavacol, "", eint, "A")
    MEL.connect_material_expressions(pint, "", eint, "B")
    em2 = E(mat, unreal.MaterialExpressionMultiply, -400, -120)
    MEL.connect_material_expressions(eint, "", em2, "A")
    MEL.connect_material_expressions(custom, "", em2, "B")          # * brightness
    em3 = E(mat, unreal.MaterialExpressionMultiply, -220, -120)
    MEL.connect_material_expressions(em2, "", em3, "A")
    MEL.connect_material_expressions(pulse, "", em3, "B")

    # --- distance fade (dim far field so it doesn't shimmer at the horizon) ---
    p_fstart = sp("FadeStart", 1500.0, -700, 760)
    p_frange = sp("FadeRange", 6000.0, -700, 840)
    p_famt = sp("FadeAmount", 0.85, -700, 920)
    pdepth = E(mat, unreal.MaterialExpressionPixelDepth, -560, 700)
    fsub = E(mat, unreal.MaterialExpressionSubtract, -420, 700)
    MEL.connect_material_expressions(pdepth, "", fsub, "A")
    MEL.connect_material_expressions(p_fstart, "", fsub, "B")
    fdiv = E(mat, unreal.MaterialExpressionDivide, -280, 700)
    MEL.connect_material_expressions(fsub, "", fdiv, "A")
    MEL.connect_material_expressions(p_frange, "", fdiv, "B")
    fade = E(mat, unreal.MaterialExpressionClamp, -140, 700)
    fade.set_editor_property("min_default", 0.0)
    fade.set_editor_property("max_default", 1.0)
    MEL.connect_material_expressions(fdiv, "", fade, "")
    f85 = E(mat, unreal.MaterialExpressionMultiply, 0, 700)
    MEL.connect_material_expressions(fade, "", f85, "A")
    MEL.connect_material_expressions(p_famt, "", f85, "B")
    emul = E(mat, unreal.MaterialExpressionOneMinus, 140, 700)
    MEL.connect_material_expressions(f85, "", emul, "")
    em_far = E(mat, unreal.MaterialExpressionMultiply, 280, -120)
    MEL.connect_material_expressions(em3, "", em_far, "A")
    MEL.connect_material_expressions(emul, "", em_far, "B")
    MEL.connect_material_property(em_far, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)

    # base color = dark version of the lava colour (lit term, mostly overpowered by emissive)
    bc = E(mat, unreal.MaterialExpressionMultiply, -560, 40)
    bc.set_editor_property("const_b", 0.25)
    MEL.connect_material_expressions(lavacol, "", bc, "A")
    MEL.connect_material_property(bc, "", unreal.MaterialProperty.MP_BASE_COLOR)

    # roughness = LiquidRoughness (low -> wet/liquid sheen)
    prough = E(mat, unreal.MaterialExpressionScalarParameter, -240, 460)
    prough.set_editor_property("parameter_name", "LiquidRoughness")
    prough.set_editor_property("default_value", 0.25)
    MEL.connect_material_property(prough, "", unreal.MaterialProperty.MP_ROUGHNESS)

    # tangent-space ripple normal, faded to flat at distance
    flatn = C3(mat, 140, 820, 0.0, 0.0, 1.0)
    nlerp = E(mat, unreal.MaterialExpressionLinearInterpolate, 320, 760)
    MEL.connect_material_expressions(custom, "OutNormal", nlerp, "A")
    MEL.connect_material_expressions(flatn, "", nlerp, "B")
    MEL.connect_material_expressions(fade, "", nlerp, "Alpha")
    MEL.connect_material_property(nlerp, "", unreal.MaterialProperty.MP_NORMAL)

    # --- World Position Offset: gentle liquid swell (vertex stage, own node) ---
    WAVE = (
        "float Tw = fmod(Time, 120.0);\n"
        "float2 p = WorldPos.xy;\n"
        "float w1 = sin(p.x*0.0016 + Tw*0.8) * cos(p.y*0.0013 + Tw*0.6);\n"
        "float w2 = sin(p.x*0.0006 - Tw*0.5) * sin(p.y*0.0009 + Tw*0.4);\n"
        "float swell = w1*0.6 + w2*0.4;\n"
        "return float3(0.0, 0.0, swell * WaveHeight);\n"
    )
    p_wh = sp("WaveHeight", 500.0, -1050, 600)
    wpos = E(mat, unreal.MaterialExpressionWorldPosition, -1050, 460)
    wave = E(mat, unreal.MaterialExpressionCustom, -800, 520)
    wave.set_editor_property("inputs", [cin("WorldPos"), cin("Time"), cin("WaveHeight")])
    wave.set_editor_property("code", WAVE)
    wave.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT3)
    wave.set_editor_property("description", "MagmaWave")
    MEL.connect_material_expressions(wpos, "", wave, "WorldPos")
    MEL.connect_material_expressions(tnode, "", wave, "Time")
    MEL.connect_material_expressions(p_wh, "", wave, "WaveHeight")
    MEL.connect_material_property(wave, "", unreal.MaterialProperty.MP_WORLD_POSITION_OFFSET)

    MEL.recompile_material(mat)
    eal.save_asset(MAT_PATH, only_if_is_dirty=False)
    L("M_Magma (simple liquid) built + saved")
    res["ok"] = True
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
unreal.log("PEACE3_MAGMA_V2 ok=%s" % res.get("ok"))
print("PEACE3_MAGMA_V2", res.get("ok"), res.get("err", ""))

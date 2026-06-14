# -*- coding: utf-8 -*-
"""Phase 8: Godot PSX post-process (4x4 Bayer ordered dither + color depth reduction)
を UE のポストプロセスマテリアル M_PP_PSX へ逐語移植する。

Godot 原版 (addons/psx/shaders/psx_postprocess.gdshader):
    norm       = PSX_DITHER_MATRIX[index] / 16.0
    bit_levels = float((1 << psx_bit_depth) - 1)   # bit_depth=5 -> 31
    out        = floor((color + norm / bit_levels) * bit_levels) / bit_levels
    index は FRAGCOORD.xy(=スクリーンピクセル座標)を 4x4 でタイリングして引く。

UE 移植方針:
  - Material Domain = Post Process
  - BlendableLocation = After Tonemapping (Godot の SCREEN_TEXTURE は最終 LDR
    フレームバッファ ≒ トーンマップ後の 0..1 表示色なので After が一番近い)
  - SceneTexture:PostProcessInput0(=トーンマップ後のシーン色) を Custom ノードへ。
  - PixelPos = ViewportUV * ViewSize (= Godot の FRAGCOORD.xy 相当の整数ピクセル座標)。
  - MPC_PSX (psx_bit_depth=5, psx_dither_amount=1.0) からスカラパラメータを供給。
  - L_Game に Unbound な PostProcessVolume を 1 つ生成し M_PP_PSX を Blendable に登録。

スクリプトは MaterialEditingLibrary の既存スタイル(make_haze.py / custom_test.py)に倣う。
"""
import unreal
import json
import traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_pp_psx.json"
MAT_DIR = "/Game/AiQuiz/Materials"
MAT_NAME = "M_PP_PSX"
MAT_PATH = MAT_DIR + "/" + MAT_NAME
MPC_DIR = "/Game/AiQuiz/Materials"
MPC_NAME = "MPC_PSX"
MPC_PATH = MPC_DIR + "/" + MPC_NAME
MAP_PATH = "/Game/AiQuiz/Maps/L_Game"

# Godot global shader param defaults (project.godot [shader_globals])
PSX_BIT_DEPTH_DEFAULT = 5.0      # 1<<5 -1 = 31 levels per channel
PSX_DITHER_AMOUNT_DEFAULT = 1.0  # 1.0 = 原版どおりフルでディザを掛ける

res = {"ok": False, "log": []}
L = res["log"].append
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()


# Godot の dither() をそのまま HLSL 化したもの。
# SceneColor : トーンマップ後シーン色 (float3, 0..1 表示色)
# PixelPos   : スクリーンピクセル座標 (float2, = Godot FRAGCOORD.xy)
# BitDepth   : psx_bit_depth (float; 5 で 32 階調/ch)
# DitherAmt  : ディザ寄与の強さ (1.0 で原版どおり、0.0 で量子化のみ)
PSX_HLSL = (
    "// --- Godot PSX ORDERED DITHER + COLOR DEPTH REDUCTION (psx_postprocess.gdshader) ---\n"
    "// 4x4 Bayer matrix (PSX_DITHER_MATRIX) — Godot と完全に同一の並び。\n"
    "const float BAYER[16] = {\n"
    "     0.0,  8.0,  2.0, 10.0,\n"
    "    12.0,  4.0, 14.0,  6.0,\n"
    "     3.0, 11.0,  1.0,  9.0,\n"
    "    15.0,  7.0, 13.0,  5.0 };\n"
    "\n"
    "int bd = (int)(BitDepth + 0.5);\n"
    "// Godot 原版: bit_depth<=0 || >=8 は discard(=素通し)。\n"
    "if (bd <= 0 || bd >= 8) { return SceneColor; }\n"
    "\n"
    "// p = ivec2(floor(uv)); xi = p.x & 3; yi = p.y & 3; index = xi + yi*4\n"
    "int2 p  = (int2)floor(PixelPos);\n"
    "int xi  = p.x & 3;\n"
    "int yi  = p.y & 3;\n"
    "int idx = xi + yi * 4;\n"
    "\n"
    "float norm       = BAYER[idx] / 16.0;            // 0 .. 15/16\n"
    "float bit_levels = (float)((1 << bd) - 1);       // bd=5 -> 31\n"
    "\n"
    "// out = floor((color + (norm*DitherAmt)/bit_levels) * bit_levels) / bit_levels\n"
    "float3 c = saturate(SceneColor);                 // 0..1 表示色にクランプ\n"
    "float3 outc = floor((c + (norm * DitherAmt) / bit_levels) * bit_levels) / bit_levels;\n"
    "return outc;\n"
)


def E(mat, cls, x, y):
    return MEL.create_material_expression(mat, cls, x, y)


def cin(name):
    c = unreal.CustomInput()
    c.set_editor_property("input_name", name)
    return c


try:
    # ---------------------------------------------------------------
    # 1) MPC_PSX (psx_bit_depth, psx_dither_amount) を用意
    # ---------------------------------------------------------------
    mpc = None
    if eal.does_asset_exist(MPC_PATH):
        mpc = eal.load_asset(MPC_PATH)
        L("reused MPC_PSX")
    else:
        try:
            mpc = at.create_asset(MPC_NAME, MPC_DIR, unreal.MaterialParameterCollection,
                                  unreal.MaterialParameterCollectionFactoryNew())
            L("created MPC_PSX")
        except Exception as e:
            L("MPC create err: %s" % e)
            mpc = None

    if mpc is not None:
        try:
            # MERGE (never overwrite) so p8_fog_mpc.py / p8_psx_surface.py params coexist.
            existing = list(mpc.get_editor_property("scalar_parameters"))
            have = set()
            for p in existing:
                try:
                    have.add(str(p.get_editor_property("parameter_name")))
                except Exception:
                    pass
            for nm, dv in (("psx_bit_depth", PSX_BIT_DEPTH_DEFAULT),
                           ("psx_dither_amount", PSX_DITHER_AMOUNT_DEFAULT)):
                if nm in have:
                    continue
                sp = unreal.CollectionScalarParameter()
                sp.set_editor_property("parameter_name", nm)
                sp.set_editor_property("default_value", dv)
                existing.append(sp)
            mpc.set_editor_property("scalar_parameters", existing)
            eal.save_asset(MPC_PATH, only_if_is_dirty=False)
            L("MPC_PSX scalar params merged (psx_bit_depth, psx_dither_amount)")
        except Exception as e:
            L("MPC param err: %s" % e)

    # ---------------------------------------------------------------
    # 2) M_PP_PSX ポストプロセスマテリアル
    # ---------------------------------------------------------------
    mat = None
    if eal.does_asset_exist(MAT_PATH):
        mat = eal.load_asset(MAT_PATH)
        MEL.delete_all_material_expressions(mat)
        L("reused M_PP_PSX")
    else:
        mat = at.create_asset(MAT_NAME, MAT_DIR, unreal.Material, unreal.MaterialFactoryNew())
        L("created M_PP_PSX")

    # Post Process ドメイン + After Tonemapping
    mat.set_editor_property("material_domain", unreal.MaterialDomain.MD_POST_PROCESS)
    try:
        mat.set_editor_property("blendable_location",
                                unreal.BlendableLocation.BL_SCENE_COLOR_AFTER_TONEMAPPING)
        L("blendable_location = After Tonemapping")
    except Exception as e:
        # 列挙子名は UE バージョンで揺れることがあるのでフォールバック。
        try:
            mat.set_editor_property("blendable_location",
                                    unreal.BlendableLocation.BL_AFTER_TONEMAPPING)
            L("blendable_location = After Tonemapping (alt enum)")
        except Exception as e2:
            L("blendable_location err: %s / %s" % (e, e2))

    # --- SceneTexture:PostProcessInput0 (トーンマップ後のシーン色) ---
    st = E(mat, unreal.MaterialExpressionSceneTexture, -900, -120)
    try:
        st.set_editor_property("scene_texture_id", unreal.SceneTextureId.PPI_POST_PROCESS_INPUT0)
        L("SceneTexture = PostProcessInput0")
    except Exception as e:
        L("scene_texture_id err: %s" % e)

    # --- PixelPos = ViewportUV * ViewSize (= FRAGCOORD.xy 相当) ---
    # ViewSize は SceneTexture ノードの "Size" 出力から取得。ViewportUV は
    # ScreenPosition の ViewportUV 出力(0..1)を使う。
    vp = E(mat, unreal.MaterialExpressionScreenPosition, -900, 120)
    pix = E(mat, unreal.MaterialExpressionMultiply, -680, 120)
    MEL.connect_material_expressions(vp, "ViewportUV", pix, "A")
    # SceneTexture の Size 出力名はバージョン差があるため複数候補を試す。
    size_ok = False
    for sz_name in ("Size", "InvSize", "ViewSize"):
        try:
            MEL.connect_material_expressions(st, sz_name, pix, "B")
            size_ok = (sz_name == "Size")
            L("PixelPos B <- SceneTexture.%s" % sz_name)
            if size_ok:
                break
        except Exception:
            continue
    if not size_ok:
        # フォールバック: 既知の内部解像度を定数で与える(必要なら driver が調整)。
        szc = E(mat, unreal.MaterialExpressionConstant2Vector, -900, 220)
        szc.set_editor_property("r", 1920.0)
        szc.set_editor_property("g", 1080.0)
        MEL.connect_material_expressions(szc, "", pix, "B")
        L("PixelPos B <- Constant2(1920,1080) fallback")

    # --- MPC からスカラパラメータ ---
    def mpc_param(name, x, y, fallback):
        if mpc is None:
            n = E(mat, unreal.MaterialExpressionScalarParameter, x, y)
            n.set_editor_property("parameter_name", name)
            n.set_editor_property("default_value", fallback)
            return n
        n = E(mat, unreal.MaterialExpressionCollectionParameter, x, y)
        try:
            n.set_editor_property("collection", mpc)
            n.set_editor_property("parameter_name", name)
        except Exception as e:
            L("collection param %s err: %s" % (name, e))
        return n

    p_bd = mpc_param("psx_bit_depth", -900, 300, PSX_BIT_DEPTH_DEFAULT)
    p_da = mpc_param("psx_dither_amount", -900, 380, PSX_DITHER_AMOUNT_DEFAULT)

    # --- Custom HLSL ノード ---
    cust = E(mat, unreal.MaterialExpressionCustom, -440, 0)
    cust.set_editor_property("inputs",
                             [cin("SceneColor"), cin("PixelPos"), cin("BitDepth"), cin("DitherAmt")])
    cust.set_editor_property("code", PSX_HLSL)
    cust.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT3)
    cust.set_editor_property("description", "PSX_DitherQuantize")

    MEL.connect_material_expressions(st, "", cust, "SceneColor")   # SceneTexture の既定出力 = Color
    MEL.connect_material_expressions(pix, "", cust, "PixelPos")
    MEL.connect_material_expressions(p_bd, "", cust, "BitDepth")
    MEL.connect_material_expressions(p_da, "", cust, "DitherAmt")

    MEL.connect_material_property(cust, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)

    MEL.recompile_material(mat)
    eal.save_asset(MAT_PATH, only_if_is_dirty=False)
    L("M_PP_PSX built & saved")

    # ---------------------------------------------------------------
    # 3) L_Game に Unbound PostProcessVolume を生成 + Blendable 登録
    # ---------------------------------------------------------------
    try:
        les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
        les.load_level(MAP_PATH)
        L("loaded L_Game")
    except Exception as e:
        L("load_level err: %s" % e)

    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    # 既存の PSX 用 PPV を掃除(再実行で増殖させない)
    for a in eas.get_all_level_actors():
        try:
            if a.get_actor_label() == "PPV_PSX":
                eas.destroy_actor(a)
                L("removed old PPV_PSX")
        except Exception:
            pass

    ppv = eas.spawn_actor_from_class(unreal.PostProcessVolume,
                                     unreal.Vector(0.0, 0.0, 0.0),
                                     unreal.Rotator(0.0, 0.0, 0.0))
    ppv.set_actor_label("PPV_PSX")
    ppv.set_editor_property("unbound", True)            # シーン全体に適用
    ppv.set_editor_property("priority", 1.0)

    # WeightedBlendable に M_PP_PSX を登録
    try:
        settings = ppv.get_editor_property("settings")
        wb = unreal.WeightedBlendables()
        entry = unreal.WeightedBlendable()
        entry.set_editor_property("weight", 1.0)
        entry.set_editor_property("object", mat)
        wb.set_editor_property("array", [entry])
        settings.set_editor_property("weighted_blendables", wb)
        ppv.set_editor_property("settings", settings)
        L("registered M_PP_PSX as weighted blendable (weight=1.0)")
    except Exception as e:
        L("blendable register err: %s" % e)
        res["blendable_err"] = str(e)

    try:
        les.save_current_level()
        L("saved L_Game")
    except Exception as e:
        try:
            unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
            L("saved via save_dirty_packages")
        except Exception as e2:
            L("save level err: %s / %s" % (e, e2))

    res["material"] = MAT_PATH
    res["mpc"] = MPC_PATH if mpc is not None else None
    res["ppv"] = "PPV_PSX"
    res["ok"] = True
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()

open(OUT, "w", encoding="utf-8").write(json.dumps(res, ensure_ascii=False, indent=2))
print("RESULT " + json.dumps(res, ensure_ascii=False))
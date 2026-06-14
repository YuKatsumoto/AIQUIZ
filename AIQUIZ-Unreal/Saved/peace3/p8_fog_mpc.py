# -*- coding: utf-8 -*-
"""Phase 8: 共有 PSX マテリアルパラメータコレクション(MPC_PSX) と、
Godot の濃いフォグ (color (0.82,0.85,0.90) / near10->far20) に視覚的に一致する
ExponentialHeightFog を L_Game にセットアップする。

Godot 由来の値:
  - StageConstants.BG_COLOR = (0.82, 0.85, 0.90)  (= fog_light_color, 背景色)
  - PsxWorldEnvironment が Psx.fog_color にこの色を流し、a *= fog_density
  - Psx.gd GLOBAL_VARS:
        psx_bit_depth      = 5  (int)
        psx_fog_color      = (0.5,0.5,0.5,0)   ※実シーンでは BG_COLOR が上書き
        psx_fog_near       = 10.0   (meters)
        psx_fog_far        = 20.0   (meters)
        psx_precision_uv   = 128.0  -> ディザ/UV量子化
        psx_precision_xy   = 256.0  -> 頂点スナップ解像度
        psx_precision_z    = 512.0
        psx_affine_strength= 1.0
  - psx_postprocess.gdshader: 4x4 Bayer dither, bit_depth で減色

UE 換算 (計画 §1.4): Godot meters -> UE *100。
  fog_near 10m -> 1000 UU,  fog_far 20m -> 2000 UU。

MPC_PSX のパラメータ (PP_PSX / M_PSX_Surface から参照する共有定数):
  Scalar: bit_depth=5, dither_amount=1.0, snap_resolution=256.0,
          fog_near=1000.0(UU), fog_far=2000.0(UU)
          (補助: affine_strength=1.0, precision_uv=128.0, precision_z=512.0)
  Vector: fog_color=(0.82,0.85,0.90,1.0)
"""
import unreal
import json
import traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_p8.json"
MPC_PATH = "/Game/AiQuiz/Materials"
MPC_NAME = "MPC_PSX"
MPC_FULL = MPC_PATH + "/" + MPC_NAME
MAP_PATH = "/Game/AiQuiz/Maps/L_Game"

# Godot 由来の PSX 定数 (meters -> UU は fog_near/far のみ *100)
FOG_COLOR = unreal.LinearColor(0.82, 0.85, 0.90, 1.0)
FOG_NEAR_UU = 1000.0   # Godot 10m
FOG_FAR_UU = 2000.0    # Godot 20m

res = {"ok": False, "log": [], "mpc": {}, "fog": {}}
L = res["log"].append

try:
    eal = unreal.EditorAssetLibrary
    at = unreal.AssetToolsHelpers.get_asset_tools()

    # ------------------------------------------------------------------
    # 1) MPC_PSX (MaterialParameterCollection) を作成 / 更新
    # ------------------------------------------------------------------
    if eal.does_asset_exist(MPC_FULL):
        mpc = eal.load_asset(MPC_FULL)
        L("loaded existing %s" % MPC_FULL)
    else:
        factory = unreal.MaterialParameterCollectionFactoryNew()
        mpc = at.create_asset(MPC_NAME, MPC_PATH,
                              unreal.MaterialParameterCollection, factory)
        L("created %s" % MPC_FULL)
    assert mpc is not None, "MPC create/load failed"

    # --- スカラーパラメータ (Godot defaults from Psx.gd GLOBAL_VARS) ---
    scalar_defs = [
        ("bit_depth", 5.0),          # psx_bit_depth=5 (減色ビット数)
        ("dither_amount", 1.0),      # Bayer dither ON (psx_postprocess.gdshader)
        ("snap_resolution", 256.0),  # psx_precision_xy=256 (頂点クリップ空間スナップ)
        ("fog_near", FOG_NEAR_UU),   # Godot 10m -> 1000 UU
        ("fog_far", FOG_FAR_UU),     # Godot 20m -> 2000 UU
        ("affine_strength", 1.0),    # psx_affine_strength=1.0 (アフィンUV)
        ("precision_uv", 128.0),     # psx_precision_uv=128 (UV量子化)
        ("precision_z", 512.0),      # psx_precision_z=512
    ]
    # MERGE (never overwrite) so p8_pp_psx.py / p8_psx_surface.py params coexist.
    existing = list(mpc.get_editor_property("scalar_parameters"))
    have = set()
    for p in existing:
        try:
            have.add(str(p.get_editor_property("parameter_name")))
        except Exception:
            pass
    for name, val in scalar_defs:
        if name in have:
            continue
        p = unreal.CollectionScalarParameter()
        p.set_editor_property("parameter_name", name)
        p.set_editor_property("default_value", float(val))
        existing.append(p)
    mpc.set_editor_property("scalar_parameters", existing)
    scalars = existing
    res["mpc"]["scalars"] = {n: v for n, v in scalar_defs}

    # --- ベクトルパラメータ ---
    vec_defs = [
        ("fog_color", FOG_COLOR),  # StageConstants.BG_COLOR (0.82,0.85,0.90)
    ]
    existing_v = list(mpc.get_editor_property("vector_parameters"))
    have_v = set()
    for p in existing_v:
        try:
            have_v.add(str(p.get_editor_property("parameter_name")))
        except Exception:
            pass
    for name, col in vec_defs:
        if name in have_v:
            continue
        p = unreal.CollectionVectorParameter()
        p.set_editor_property("parameter_name", name)
        p.set_editor_property("default_value", col)
        existing_v.append(p)
    mpc.set_editor_property("vector_parameters", existing_v)
    vectors = existing_v
    res["mpc"]["vectors"] = {
        "fog_color": [FOG_COLOR.r, FOG_COLOR.g, FOG_COLOR.b, FOG_COLOR.a]
    }

    eal.save_loaded_asset(mpc)
    L("saved MPC_PSX (%d scalar, %d vector)" % (len(scalars), len(vectors)))

    # ------------------------------------------------------------------
    # 2) L_Game を開き、ExponentialHeightFog を濃い設定で配置
    # ------------------------------------------------------------------
    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    les.load_level(MAP_PATH)
    L("loaded level %s" % MAP_PATH)

    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    def find(label):
        for a in eas.get_all_level_actors():
            if a.get_actor_label() == label:
                return a
        return None

    # step4_fog.py が "Stage_Fog" を作っている場合は再利用、無ければ生成
    fog = find("Stage_Fog")
    if not fog:
        fog = eas.spawn_actor_from_class(
            unreal.ExponentialHeightFog, unreal.Vector(400.0, 0.0, -100.0))
        fog.set_actor_label("Stage_Fog")
        L("spawned Stage_Fog")
    else:
        L("reusing existing Stage_Fog")

    comp = fog.get_component_by_class(unreal.ExponentialHeightFogComponent)

    # --- Godot near10/far20 (非常に濃く近い) のエミュレーション ---
    # Godot の PSX 頂点フォグは線形: strength = clamp((depth-near)/(far-near),0,1)
    # で far=20m(2000UU) でほぼ完全にフォグ色。これを UE 指数ハイトフォグで近似する。
    #   - StartDistance=0 : near の手前(=Pawn直前)からフォグを掛け始める
    #   - FogDensity を高くして 20m(2000UU) 付近で飽和させる
    #     exp 減衰 transmittance(d)=exp(-density*d) より、
    #     d=2000UU で残光 ~3% にするには density ~ 0.0018/UU。
    #     近接の濃さ優先で 0.02 を採用 (床/壁が ~150UU 手前で霞み始める濃霧)。
    #   - HeightFalloff を小さくして高さ方向にほぼ均一(ランナーは Z=-120..上)。
    comp.set_editor_property("fog_density", 0.02)
    comp.set_editor_property("fog_height_falloff", 0.05)
    comp.set_editor_property("start_distance", 0.0)
    # 床上面 (UE Z=-120) より十分下から霧が立ち上がるよう原点付近に
    comp.set_editor_property("fog_max_opacity", 1.0)

    # Inscattering color プロパティ名は UE バージョンで変わる -> 両方試す
    set_color = False
    for prop in ("fog_inscattering_luminance", "fog_inscattering_color"):
        try:
            comp.set_editor_property(prop, FOG_COLOR)
            L("set %s = (0.82,0.85,0.90)" % prop)
            set_color = True
            break
        except Exception as e:
            L("skip %s: %s" % (prop, e))
    if not set_color:
        L("WARN: could not set inscattering color")

    # 第2(指向性)インスキャッタを無効化し均一なフラットフォグに
    try:
        comp.set_editor_property("directional_inscattering_exponent", 4.0)
        comp.set_editor_property("directional_inscattering_color",
                                 unreal.LinearColor(0.0, 0.0, 0.0, 1.0))
    except Exception as e:
        L("directional inscatter skip: %s" % e)

    res["fog"] = {
        "actor": fog.get_actor_label(),
        "fog_density": comp.get_editor_property("fog_density"),
        "fog_height_falloff": comp.get_editor_property("fog_height_falloff"),
        "start_distance": comp.get_editor_property("start_distance"),
        "inscattering_color": [FOG_COLOR.r, FOG_COLOR.g, FOG_COLOR.b],
        "emulates": "Godot near10m(1000UU)->far20m(2000UU) dense linear fog",
    }
    L("configured dense fog")

    # ------------------------------------------------------------------
    # 3) レベル保存
    # ------------------------------------------------------------------
    saved = les.save_current_level()
    L("save_current_level=%s" % saved)
    res["ok"] = True

except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)

print("RESULT " + json.dumps(res, ensure_ascii=False))
unreal.log("PEACE3_P8_DONE ok=%s" % res.get("ok"))
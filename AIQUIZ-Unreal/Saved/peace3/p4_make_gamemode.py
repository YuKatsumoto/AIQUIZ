# -*- coding: utf-8 -*-
"""Phase4: BP_AiQuizGameMode を作成し DefaultPawnClass=BP_AiQuizPawn に設定。

GameMode の DefaultPawnClass は CDO(Class Default Object)上のプロパティなので、
一度 compile して generated class を得てから CDO に set_editor_property する。
再 compile は CDO 変更を捨てる恐れがあるため行わず、save_loaded_asset で永続化。
最後に読み直して設定が効いているか verify する。
"""
import unreal
import json

GM_PKG = "/Game/AiQuiz/Core"
GM_NAME = "BP_AiQuizGameMode"
GM_PATH = GM_PKG + "/" + GM_NAME
PAWN_PATH = "/Game/AiQuiz/Pawn/BP_AiQuizPawn"

out = {"ok": False}

if unreal.EditorAssetLibrary.does_asset_exist(GM_PATH):
    unreal.EditorAssetLibrary.delete_asset(GM_PATH)
    out["deleted_existing"] = True

factory = unreal.BlueprintFactory()
factory.set_editor_property("parent_class", unreal.GameModeBase)
asset_tools = unreal.AssetToolsHelpers.get_asset_tools()
gm = asset_tools.create_asset(GM_NAME, GM_PKG, None, factory)
assert gm is not None, "create_asset failed"

# generated class を作るため一度 compile
unreal.BlueprintEditorLibrary.compile_blueprint(gm)

# Pawn の generated class を取得（TSubclassOf<APawn> として渡す）
pawn_class = unreal.EditorAssetLibrary.load_blueprint_class(PAWN_PATH)
assert pawn_class is not None, "load pawn class failed"

# GameMode CDO に DefaultPawnClass を設定
gm_class = gm.generated_class()
cdo = unreal.get_default_object(gm_class)
cdo.set_editor_property("default_pawn_class", pawn_class)

# 保存（再 compile せず CDO 変更を永続化）
saved = unreal.EditorAssetLibrary.save_loaded_asset(gm)

# 検証: CDO を読み直して default_pawn_class を確認
cdo2 = unreal.get_default_object(gm.generated_class())
got = cdo2.get_editor_property("default_pawn_class")

out["ok"] = True
out["saved"] = bool(saved)
out["set_pawn"] = str(pawn_class.get_name())
out["verify_pawn"] = (str(got.get_name()) if got else None)
print("RESULT " + json.dumps(out))

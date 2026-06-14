# -*- coding: utf-8 -*-
"""Phase2: BP_AiQuizGameMode の親を素の GameModeBase から C++ の
AAiQuizGameModeBase へ付け替える。

これにより、プロジェクトの GameMode が C++ 状態機械そのものになり、
L_Game の GameModeOverride 経由で PIE が状態機械を駆動できるようになる。
DefaultPawnClass(=BP_AiQuizPawn) は再設定して確実に保持する。

ヘッドレス実行:
  UnrealEditor-Cmd.exe <proj> -run=pythonscript -script="<this>" -unattended -nopause
"""
import unreal
import json

GM_PATH = "/Game/AiQuiz/Core/BP_AiQuizGameMode"
PAWN_PATH = "/Game/AiQuiz/Pawn/BP_AiQuizPawn"

out = {"ok": False}

bp = unreal.EditorAssetLibrary.load_asset(GM_PATH)
assert bp is not None, "load BP_AiQuizGameMode failed"

# 付け替え前に既に C++ GM 派生かどうかを記録
cdo0 = unreal.get_default_object(bp.generated_class())
out["was_aiquiz_gm_before"] = isinstance(cdo0, unreal.AiQuizGameModeBase)

# C++ クラス（Python では A/U プレフィクスなし）へリペアレント
new_parent = unreal.AiQuizGameModeBase
unreal.BlueprintEditorLibrary.reparent_blueprint(bp, new_parent)
unreal.BlueprintEditorLibrary.compile_blueprint(bp)

# DefaultPawnClass を再設定（reparent で保持されるが明示的に念押し）
pawn_cls = unreal.EditorAssetLibrary.load_blueprint_class(PAWN_PATH)
cdo = unreal.get_default_object(bp.generated_class())
if pawn_cls is not None:
    cdo.set_editor_property("default_pawn_class", pawn_cls)

# dirty フラグに依存せず強制保存（コミットレットでは compile が dirty を立てないことがある）
bp.modify()
unreal.EditorAssetLibrary.save_loaded_asset(bp, False)
saved = unreal.EditorAssetLibrary.save_asset(GM_PATH, False)

# 検証: 新 CDO が C++ クラスのインスタンスで、C++ 由来の Tuning プロパティを持つこと
cdo2 = unreal.get_default_object(bp.generated_class())
out["ok"] = True
out["saved"] = bool(saved)
out["is_aiquiz_gm"] = isinstance(cdo2, unreal.AiQuizGameModeBase)
try:
    out["gravity"] = float(cdo2.get_editor_property("gravity"))
    out["player_speed"] = float(cdo2.get_editor_property("player_speed"))
    out["floor_half_width"] = float(cdo2.get_editor_property("floor_half_width"))
except Exception as e:
    out["prop_err"] = str(e)
dp = cdo2.get_editor_property("default_pawn_class")
out["default_pawn"] = dp.get_name() if dp else None

print("RESULT " + json.dumps(out))

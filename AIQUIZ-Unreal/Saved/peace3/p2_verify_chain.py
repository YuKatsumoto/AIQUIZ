# -*- coding: utf-8 -*-
"""Phase2 検証: BP_AiQuizGameMode がディスク上で C++ AAiQuizGameModeBase 派生に
なっていること、および L_Game の GameModeOverride -> BP_AiQuizGameMode ->
DefaultPawnClass(BP_AiQuizPawn) の鎖が繋がっていることを、まっさらなプロセスで確認。
"""
import unreal
import json

GM_PATH = "/Game/AiQuiz/Core/BP_AiQuizGameMode"
MAP = "/Game/AiQuiz/Maps/L_Game"
out = {}

# --- GameMode 本体 ---
bp = unreal.EditorAssetLibrary.load_asset(GM_PATH)
cdo = unreal.get_default_object(bp.generated_class())
out["is_aiquiz_gm"] = isinstance(cdo, unreal.AiQuizGameModeBase)
out["gravity"] = float(cdo.get_editor_property("gravity"))
out["jump_force"] = float(cdo.get_editor_property("jump_force"))
out["magma_death_y"] = float(cdo.get_editor_property("magma_death_y"))
out["countdown_seconds"] = float(cdo.get_editor_property("countdown_seconds"))
dp = cdo.get_editor_property("default_pawn_class")
out["default_pawn"] = dp.get_name() if dp else None

# --- レベルの GameModeOverride ---
try:
    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    les.load_level(MAP)
    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    w = ues.get_editor_world()
    ws = w.get_world_settings()
    gmo = ws.get_editor_property("default_game_mode")
    out["level_gamemode_override"] = gmo.get_name() if gmo else None
except Exception as e:
    out["level_err"] = str(e)

print("VERIFY " + json.dumps(out))

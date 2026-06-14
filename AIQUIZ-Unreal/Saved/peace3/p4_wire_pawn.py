# -*- coding: utf-8 -*-
"""Phase4: BP_AiQuizGameMode の DefaultPawnClass を C++ AAiQuizPawn に再配線し、
PlayerStart を床上面(0,0,-120)へ。旧 BP_AiQuizPawn は使わない（残置）。"""
import unreal
import json

GM_PATH = "/Game/AiQuiz/Core/BP_AiQuizGameMode"
MAP = "/Game/AiQuiz/Maps/L_Game"
out = {"ok": False}

# --- DefaultPawnClass -> AAiQuizPawn ---
bp = unreal.EditorAssetLibrary.load_asset(GM_PATH)
cdo = unreal.get_default_object(bp.generated_class())
cdo.set_editor_property("default_pawn_class", unreal.AiQuizPawn)
bp.modify()
unreal.EditorAssetLibrary.save_asset(GM_PATH, False)
dp = cdo.get_editor_property("default_pawn_class")
out["default_pawn"] = dp.get_name() if dp else None

# --- PlayerStart -> (0,0,-120) ---
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
les.load_level(MAP)
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
for a in eas.get_all_level_actors():
    if a.get_class().get_name() == "PlayerStart":
        a.set_actor_location(unreal.Vector(0.0, 0.0, -120.0), False, False)
        a.set_actor_rotation(unreal.Rotator(0.0, 0.0, 0.0), False)
        out["playerstart"] = "moved to (0,0,-120)"
        break
out["level_saved"] = bool(les.save_current_level())
out["ok"] = True
print("RESULT " + json.dumps(out, ensure_ascii=False))

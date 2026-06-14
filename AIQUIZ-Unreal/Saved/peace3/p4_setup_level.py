# -*- coding: utf-8 -*-
"""Phase4: L_Game に GameModeOverride と PlayerStart を設定。

- WorldSettings.default_game_mode (= GameModeOverride) に BP_AiQuizGameMode を指定。
- PlayerStart を (-800,0,0)/yaw=0 に配置（既存があれば移動）。Possess 後すぐに
  Pawn の Tick が SetActorLocation で上書きするので、初期位置の厳密さは不要。
"""
import unreal
import json

GM_PATH = "/Game/AiQuiz/Core/BP_AiQuizGameMode"
MAP = "/Game/AiQuiz/Maps/L_Game"
START_LOC = unreal.Vector(-800.0, 0.0, 0.0)
START_ROT = unreal.Rotator(0.0, 0.0, 0.0)

out = {"ok": False}

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
les.load_level(MAP)

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
w = ues.get_editor_world()

# GameModeOverride を設定
gm_class = unreal.EditorAssetLibrary.load_blueprint_class(GM_PATH)
assert gm_class is not None, "load gamemode class failed"

# WorldSettings は get_all_level_actors に出ないので get_world_settings で取得
ws = None
if hasattr(w, "get_world_settings"):
    try:
        ws = w.get_world_settings()
    except Exception as e:
        out["ws_method_err"] = str(e)
if ws is None:
    for a in eas.get_all_level_actors():
        if "WorldSettings" in a.get_class().get_name():
            ws = a
            break
assert ws is not None, "WorldSettings not found"
out["ws_class"] = ws.get_class().get_name()
ws.set_editor_property("default_game_mode", gm_class)
out["gamemode_set"] = str(gm_class.get_name())

# PlayerStart を配置（既存再利用 or 新規 spawn）
ps = None
for a in eas.get_all_level_actors():
    if a.get_class().get_name() == "PlayerStart":
        ps = a
        break
if ps is None:
    ps = eas.spawn_actor_from_class(unreal.PlayerStart, START_LOC, START_ROT)
    ps.set_actor_label("PlayerStart")
    out["playerstart"] = "spawned"
else:
    ps.set_actor_location(START_LOC, False, False)
    ps.set_actor_rotation(START_ROT, False)
    out["playerstart"] = "moved"

# レベル保存
saved = les.save_current_level()
out["ok"] = True
out["level_saved"] = bool(saved)
print("RESULT " + json.dumps(out))

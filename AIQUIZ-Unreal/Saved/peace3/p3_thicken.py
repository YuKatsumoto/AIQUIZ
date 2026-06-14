# -*- coding: utf-8 -*-
"""Stage_Floor を Godot 準拠の厚い箱(16m)にして「浮いて見える」問題を解消。
上面 Z=-120 を保ったまま厚み 0.2m→16m(scale Z=16)、中心 Z=-920(下面 -1720)。
M_ConveyorBelt は法線で上面=ベルト/側面=side_color を出し分けるので、側面は灰色の壁になる。"""
import unreal
import json

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)

w = ues.get_editor_world()
if (w is None) or ("L_Game" not in w.get_name()):
    les.load_level("/Game/AiQuiz/Maps/L_Game")

floor = None
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Stage_Floor":
        floor = a
        break
assert floor is not None, "Stage_Floor not found"

bl = floor.get_actor_location()
bs = floor.get_actor_scale3d()
out = {
    "before_loc": [round(bl.x, 1), round(bl.y, 1), round(bl.z, 1)],
    "before_scale": [round(bs.x, 2), round(bs.y, 2), round(bs.z, 2)],
}

floor.set_actor_location(unreal.Vector(400.0, 0.0, -920.0), False, False)
floor.set_actor_scale3d(unreal.Vector(160.0, 24.0, 16.0))

al = floor.get_actor_location()
asc = floor.get_actor_scale3d()
out["after_loc"] = [round(al.x, 1), round(al.y, 1), round(al.z, 1)]
out["after_scale"] = [round(asc.x, 2), round(asc.y, 2), round(asc.z, 2)]
o, e = floor.get_actor_bounds(False)
out["after_top_z"] = round(o.z + e.z, 1)
out["after_bottom_z"] = round(o.z - e.z, 1)

saved = les.save_current_level()
out["saved"] = bool(saved)
print("RESULT " + json.dumps(out, ensure_ascii=False))

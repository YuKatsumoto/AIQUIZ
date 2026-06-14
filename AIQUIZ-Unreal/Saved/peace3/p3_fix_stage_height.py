# -*- coding: utf-8 -*-
"""Phase3 修正: マグマ面が浅すぎてステージが浸かって見える問題を、Godot 準拠の
落差に直す。

Godot (stage_constants.gd / stage_environment.gd):
  床上面 FLOOR_TOP_Y = -1.2m  →  UE Z = -120  (現状 Stage_Floor 上面 = -120 で一致)
  マグマ面 magma.position.y = -10.0m  →  UE Z = -1000
よって床上面とマグマの落差は 8.8m。現状 UE はマグマ Z=-360 で落差 2.4m しかなく浅い。

マグマ(Magma_Floor)を Z=-1000 へ下げ、陽炎(Stage_HeatHaze)はマグマとの相対オフセットを
保ったまま同じ delta で下げる。床/コンベア/レール/カメラ/壁基準(-120)は動かさない。
"""
import unreal
import json

MAP = "/Game/AiQuiz/Maps/L_Game"
TARGET_MAGMA_Z = -1000.0  # Godot Y=-10.0 * UU(100)

out = {"ok": False}

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
les.load_level(MAP)
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)


def find(label):
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == label:
            return a
    return None


magma = find("Magma_Floor")
haze = find("Stage_HeatHaze")
assert magma is not None, "Magma_Floor not found"

mloc = magma.get_actor_location()
out["magma_before"] = round(mloc.z, 1)
delta = TARGET_MAGMA_Z - mloc.z
out["delta"] = round(delta, 1)

magma.set_actor_location(unreal.Vector(mloc.x, mloc.y, TARGET_MAGMA_Z), False, False)
out["magma_after"] = round(magma.get_actor_location().z, 1)

if haze is not None:
    hloc = haze.get_actor_location()
    out["haze_before"] = round(hloc.z, 1)
    haze.set_actor_location(unreal.Vector(hloc.x, hloc.y, hloc.z + delta), False, False)
    out["haze_after"] = round(haze.get_actor_location().z, 1)
else:
    out["haze"] = "not found (skipped)"

saved = les.save_current_level()
out["ok"] = True
out["level_saved"] = bool(saved)
print("RESULT " + json.dumps(out, ensure_ascii=False))

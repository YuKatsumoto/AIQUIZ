# -*- coding: utf-8 -*-
"""SK_YBot をレベルに配置し A_Run を再生、バウンド(身長)・足元位置・向きを調べる。"""
import unreal
import json

DEST = "/Game/AiQuiz/Character"
out = {}

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
w = ues.get_editor_world()
if (w is None) or ("L_Game" not in w.get_name()):
    les.load_level("/Game/AiQuiz/Maps/L_Game")

for a in eas.get_all_level_actors():
    if a.get_actor_label() == "__YBotProbe":
        eas.destroy_actor(a)

# Which clip + frame to show. File "p5_anim.txt": "AnimName Time"; Time<0 => loop-play.
try:
    _a = open("C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/p5_anim.txt").read().split()
    ANIM_NAME = _a[0]
    ANIM_TIME = float(_a[1]) if len(_a) > 1 else -1.0
except Exception:
    ANIM_NAME, ANIM_TIME = "A_Run", -1.0

sk = unreal.EditorAssetLibrary.load_asset(DEST + "/SK_YBot")
run = unreal.EditorAssetLibrary.load_asset(DEST + "/" + ANIM_NAME)
out["anim"] = ANIM_NAME
out["anim_time"] = ANIM_TIME
# yaw +90: Mixamo faces -Y on import; rotate to face +X (gameplay forward, toward the walls).
actor = eas.spawn_actor_from_class(unreal.SkeletalMeshActor, unreal.Vector(0.0, 0.0, -120.0), unreal.Rotator(0.0, 0.0, 90.0))
actor.set_actor_label("__YBotProbe")
comp = actor.skeletal_mesh_component
comp.set_skinned_asset_and_update(sk)
comp.set_animation_mode(unreal.AnimationMode.ANIMATION_SINGLE_NODE)
# Evaluate animation in the (non-PIE) editor viewport so the screenshot shows a real
# run pose instead of the bind T-pose. Use the FUNCTION (the property is template-locked).
try:
    comp.set_update_animation_in_editor(True)
except Exception as e:
    out["upd_anim_err"] = str(e)
if run:
    if ANIM_TIME < 0.0:
        comp.play_animation(run, True)   # loop-play (run): viewport ticks advance it
        comp.set_play_rate(1.0)
    else:
        comp.play_animation(run, False)  # freeze at a chosen frame (jump rising / fall descending)
        comp.set_position(ANIM_TIME, False)
        comp.set_play_rate(0.0)

o, e = actor.get_actor_bounds(False)
out["bounds_origin"] = [round(o.x, 1), round(o.y, 1), round(o.z, 1)]
out["bounds_ext"] = [round(e.x, 1), round(e.y, 1), round(e.z, 1)]
out["height_uu"] = round(e.z * 2.0, 1)
out["feet_z"] = round(o.z - e.z, 1)
out["top_z"] = round(o.z + e.z, 1)
print("RESULT " + json.dumps(out, ensure_ascii=False))

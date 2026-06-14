# -*- coding: utf-8 -*-
"""修正後の L_Game をキャプチャするだけ（高さ修正は適用済み）。
-AllowCommandletRendering 付きで実行して RHI を有効化すること。"""
import unreal
import json

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
MAP = "/Game/AiQuiz/Maps/L_Game"
EXPO = 0.2

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les.load_level(MAP)
world = ues.get_editor_world()
out = {"shots": []}


def find(label):
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == label:
            return a
    return None


def capture(name, loc, rot, fov=70.0):
    cap = find("__Cap") or eas.spawn_actor_from_class(unreal.SceneCapture2D, loc, rot)
    cap.set_actor_label("__Cap")
    cap.set_actor_location_and_rotation(loc, rot, False, False)
    comp = cap.get_component_by_class(unreal.SceneCaptureComponent2D)
    rt = unreal.RenderingLibrary.create_render_target2d(
        world, 1280, 720, unreal.TextureRenderTargetFormat.RTF_RGBA8,
        unreal.LinearColor(0.0, 0.0, 0.0, 1.0), False)
    comp.set_editor_property("capture_source", unreal.SceneCaptureSource.SCS_FINAL_COLOR_LDR)
    comp.set_editor_property("texture_target", rt)
    comp.set_editor_property("fov_angle", fov)
    comp.set_editor_property("capture_every_frame", False)
    comp.set_editor_property("capture_on_movement", False)
    pp = comp.get_editor_property("post_process_settings")
    pp.set_editor_property("override_auto_exposure_min_brightness", True)
    pp.set_editor_property("auto_exposure_min_brightness", EXPO)
    pp.set_editor_property("override_auto_exposure_max_brightness", True)
    pp.set_editor_property("auto_exposure_max_brightness", EXPO)
    comp.set_editor_property("post_process_settings", pp)
    for _ in range(6):
        comp.capture_scene()
    ok = unreal.RenderingLibrary.export_render_target(world, rt, BASE, name + ".png")
    out["shots"].append({name: bool(ok)})


capture("stage_fix_fwd", unreal.Vector(-1500.0, 0.0, 250.0), unreal.Rotator(0.0, -7.0, 0.0))
capture("stage_fix_side", unreal.Vector(1000.0, -3500.0, 200.0), unreal.Rotator(0.0, -11.0, 90.0))
capture("stage_fix_low", unreal.Vector(-1200.0, 0.0, 20.0), unreal.Rotator(0.0, -4.0, 0.0))
print("RESULT " + json.dumps(out, ensure_ascii=False))

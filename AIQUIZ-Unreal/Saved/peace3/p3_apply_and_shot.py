# -*- coding: utf-8 -*-
"""Phase3: マグマ深さを Godot 準拠(-1000)に直し、修正前後のスクリーンショットを撮る。
実RHI 必要（-NullRHI を付けない）。

手順: L_Game ロード → 修正前ショット(forward) → マグマ/陽炎を下げる →
修正後ショット(forward, side) → レベル保存。
"""
import unreal
import json

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
MAP = "/Game/AiQuiz/Maps/L_Game"
TARGET_MAGMA_Z = -1000.0
EXPO = 0.2

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les.load_level(MAP)
world = ues.get_editor_world()

out = {"ok": False, "shots": []}


def find(label):
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == label:
            return a
    return None


def capture(name, loc, rot, fov=70.0):
    cap = find("__Cap")
    if not cap:
        cap = eas.spawn_actor_from_class(unreal.SceneCapture2D, loc, rot)
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
    pp.set_editor_property("override_auto_exposure_method", True)
    pp.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_HISTOGRAM)
    pp.set_editor_property("override_auto_exposure_min_brightness", True)
    pp.set_editor_property("auto_exposure_min_brightness", EXPO)
    pp.set_editor_property("override_auto_exposure_max_brightness", True)
    pp.set_editor_property("auto_exposure_max_brightness", EXPO)
    comp.set_editor_property("post_process_settings", pp)
    # 数フレーム回してフォグ/ストリーミングを落ち着かせてからキャプチャ
    for _ in range(4):
        comp.capture_scene()
    unreal.RenderingLibrary.export_render_target(world, rt, BASE, name + ".png")
    out["shots"].append(name)


# カメラ: 前方俯瞰（センターライン）、側面俯瞰
FWD = (unreal.Vector(-1500.0, 0.0, 250.0), unreal.Rotator(0.0, -7.0, 0.0))
SIDE = (unreal.Vector(1000.0, -3500.0, 200.0), unreal.Rotator(0.0, -11.0, 90.0))

# --- 修正前 ---
capture("stage_before_fwd", FWD[0], FWD[1])

# --- 修正適用 ---
magma = find("Magma_Floor")
haze = find("Stage_HeatHaze")
mloc = magma.get_actor_location()
out["magma_before"] = round(mloc.z, 1)
delta = TARGET_MAGMA_Z - mloc.z
out["delta"] = round(delta, 1)
magma.set_actor_location(unreal.Vector(mloc.x, mloc.y, TARGET_MAGMA_Z), False, False)
out["magma_after"] = round(magma.get_actor_location().z, 1)
if haze:
    hloc = haze.get_actor_location()
    out["haze_before"] = round(hloc.z, 1)
    haze.set_actor_location(unreal.Vector(hloc.x, hloc.y, hloc.z + delta), False, False)
    out["haze_after"] = round(haze.get_actor_location().z, 1)

# --- 修正後 ---
capture("stage_after_fwd", FWD[0], FWD[1])
capture("stage_after_side", SIDE[0], SIDE[1])

saved = les.save_current_level()
out["ok"] = True
out["level_saved"] = bool(saved)
print("RESULT " + json.dumps(out, ensure_ascii=False))

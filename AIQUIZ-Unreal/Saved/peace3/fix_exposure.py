import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
SHOT = BASE + "/expo_shot.png"

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
ppv = None
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Stage_PostProcess":
        ppv = a
        break
print("PPV", ppv.get_actor_label() if ppv else None)

s = ppv.get_editor_property("settings")
# Auto exposure (histogram) with a sane range so emissive reads correctly.
s.set_editor_property("override_auto_exposure_method", True)
s.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_HISTOGRAM)
s.set_editor_property("override_auto_exposure_min_brightness", True)
s.set_editor_property("auto_exposure_min_brightness", 0.05)
s.set_editor_property("override_auto_exposure_max_brightness", True)
s.set_editor_property("auto_exposure_max_brightness", 8.0)
s.set_editor_property("override_auto_exposure_bias", True)
s.set_editor_property("auto_exposure_bias", 1.0)
ppv.set_editor_property("settings", s)
print("exposure -> histogram auto")

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(-500.0, 0.0, 340.0), unreal.Rotator(0.0, -32.0, 0.0))
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, SHOT)
print("shot ->", SHOT)

import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
val = float(open(BASE + "/expo_val.txt").read().strip())

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
ppv = [a for a in eas.get_all_level_actors() if a.get_actor_label() == "Stage_PostProcess"][0]
s = ppv.get_editor_property("settings")
# Locked histogram exposure (min==max) == fixed exposure, matching Godot's
# no-auto-exposure model. `val` is the locked target luminance.
s.set_editor_property("override_auto_exposure_method", True)
s.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_HISTOGRAM)
s.set_editor_property("override_auto_exposure_min_brightness", True)
s.set_editor_property("auto_exposure_min_brightness", val)
s.set_editor_property("override_auto_exposure_max_brightness", True)
s.set_editor_property("auto_exposure_max_brightness", val)
s.set_editor_property("override_auto_exposure_bias", True)
s.set_editor_property("auto_exposure_bias", 0.0)
ppv.set_editor_property("settings", s)

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(-500.0, 0.0, 340.0), unreal.Rotator(0.0, -32.0, 0.0))
out = BASE + ("/shot_expo_%s.png" % str(val).replace(".", "p"))
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, out)
print("exposure locked to", val, "->", out)

import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
SHOT = BASE + "/magma_closeup.png"

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
ppv = [a for a in eas.get_all_level_actors() if a.get_actor_label() == "Stage_PostProcess"][0]
s = ppv.get_editor_property("settings")
s.set_editor_property("override_auto_exposure_method", True)
s.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_HISTOGRAM)
s.set_editor_property("override_auto_exposure_min_brightness", True)
s.set_editor_property("auto_exposure_min_brightness", 0.6)
s.set_editor_property("override_auto_exposure_max_brightness", True)
s.set_editor_property("auto_exposure_max_brightness", 0.6)
ppv.set_editor_property("settings", s)

# Higher overhead view over open magma to see several voronoi cells at once
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(400.0, 9000.0, 6000.0), unreal.Rotator(0.0, -70.0, 0.0))
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, SHOT)
print("magma closeup ->", SHOT)

import unreal, json

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
SHOT = BASE + "/env_shot.png"
log = []
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)


def find(lab):
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == lab:
            return a
    return None


# --- Directional key light: Godot color (0.90,0.92,0.95), energy ~1.2, high side angle ---
key = find("KeyLight")
if key:
    c = key.get_component_by_class(unreal.DirectionalLightComponent)
    c.set_editor_property("intensity", 4.0)
    c.set_light_color(unreal.LinearColor(0.90, 0.92, 0.95, 1.0))
    key.set_actor_rotation(unreal.Rotator(-50.0, -20.0, 0.0), False)
    log.append("key light set")

# --- Sky light: drop to a dim flat-ish ambient (Godot ambient 0.30,0.32,0.35) ---
sky = find("SkyLight")
if sky:
    sc = sky.get_component_by_class(unreal.SkyLightComponent)
    sc.set_editor_property("intensity", 0.35)
    try:
        sc.set_editor_property("lower_hemisphere_is_black", False)
    except Exception as e:
        log.append("lhb: %s" % e)
    try:
        sc.recapture_sky()
        log.append("sky recaptured @0.35")
    except Exception as e:
        log.append("recapture: %s" % e)

# --- Fixed exposure (locked histogram) to a tuned value ---
ppv = find("Stage_PostProcess")
s = ppv.get_editor_property("settings")
s.set_editor_property("override_auto_exposure_method", True)
s.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_HISTOGRAM)
s.set_editor_property("override_auto_exposure_min_brightness", True)
s.set_editor_property("auto_exposure_min_brightness", 1.0)
s.set_editor_property("override_auto_exposure_max_brightness", True)
s.set_editor_property("auto_exposure_max_brightness", 1.0)
s.set_editor_property("override_auto_exposure_bias", True)
s.set_editor_property("auto_exposure_bias", 0.0)
ppv.set_editor_property("settings", s)
log.append("exposure locked 1.0")

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(-500.0, 0.0, 340.0), unreal.Rotator(0.0, -32.0, 0.0))
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, SHOT)
print(json.dumps(log))

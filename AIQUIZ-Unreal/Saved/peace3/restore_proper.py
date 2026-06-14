import unreal, json

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
log = []
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
eal = unreal.EditorAssetLibrary


def find(lab):
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == lab:
            return a
    return None


# Restore the real (non-debug) magma material
mag = eal.load_asset("/Game/AiQuiz/Materials/M_Magma")
magma = find("Magma_Floor")
smc = magma.get_component_by_class(unreal.StaticMeshComponent)
smc.set_material(0, mag)
log.append("M_Magma restored")

ppv = find("Stage_PostProcess")
s = ppv.get_editor_property("settings")
# Soft bloom ~ Godot glow (intensity 0.5, hdr threshold 0.8, softlight)
s.set_editor_property("override_bloom_intensity", True)
s.set_editor_property("bloom_intensity", 0.7)
s.set_editor_property("override_bloom_threshold", True)
s.set_editor_property("bloom_threshold", 0.6)
# Fixed exposure
s.set_editor_property("override_auto_exposure_method", True)
s.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_HISTOGRAM)
s.set_editor_property("override_auto_exposure_min_brightness", True)
s.set_editor_property("auto_exposure_min_brightness", 1.0)
s.set_editor_property("override_auto_exposure_max_brightness", True)
s.set_editor_property("auto_exposure_max_brightness", 1.0)
ppv.set_editor_property("settings", s)
log.append("bloom+exposure set")

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
les.save_current_level()
print(json.dumps(log))

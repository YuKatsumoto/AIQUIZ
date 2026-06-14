import unreal, json, traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_step4.json"
res = {"ok": False, "log": []}
L = res["log"].append

BG = unreal.LinearColor(0.82, 0.85, 0.90, 1.0)  # Godot StageConstants.BG_COLOR

try:
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    def find(label):
        for a in eas.get_all_level_actors():
            if a.get_actor_label() == label:
                return a
        return None

    # --- Exponential Height Fog (atmospheric haze, BG-color tinted) ---
    fog = find("Stage_Fog")
    if not fog:
        fog = eas.spawn_actor_from_class(unreal.ExponentialHeightFog,
                                         unreal.Vector(400.0, 0.0, -100.0))
        fog.set_actor_label("Stage_Fog")
        L("spawned Stage_Fog")
    comp = fog.get_component_by_class(unreal.ExponentialHeightFogComponent)
    comp.set_editor_property("fog_density", 0.015)
    comp.set_editor_property("fog_height_falloff", 0.12)
    comp.set_editor_property("start_distance", 800.0)
    # Inscattering color/luminance property was renamed across UE versions.
    for prop in ("fog_inscattering_luminance", "fog_inscattering_color"):
        try:
            comp.set_editor_property(prop, BG)
            L("set %s" % prop)
            break
        except Exception as e:
            L("skip %s: %s" % (prop, e))
    try:
        comp.set_editor_property("enable_volumetric_fog", True)
        comp.set_editor_property("volumetric_fog_scattering_distribution", 0.4)
        L("enabled volumetric fog")
    except Exception as e:
        L("volumetric fog skipped: %s" % e)
    L("configured fog")

    # --- Post Process Volume: lock exposure + bloom glow (Godot ACES + glow) ---
    ppv = find("Stage_PostProcess")
    if not ppv:
        ppv = eas.spawn_actor_from_class(unreal.PostProcessVolume,
                                         unreal.Vector(400.0, 0.0, 0.0))
        ppv.set_actor_label("Stage_PostProcess")
        L("spawned Stage_PostProcess")
    ppv.set_editor_property("unbound", True)
    s = ppv.get_editor_property("settings")
    # Histogram auto-exposure with a bounded range. NOTE: AEM_MANUAL with bias 0
    # crushed the whole scene to black (emissive included), so we use a clamped
    # auto exposure that keeps the magma glowing without blowing out.
    s.set_editor_property("override_auto_exposure_method", True)
    s.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_HISTOGRAM)
    s.set_editor_property("override_auto_exposure_min_brightness", True)
    s.set_editor_property("auto_exposure_min_brightness", 0.05)
    s.set_editor_property("override_auto_exposure_max_brightness", True)
    s.set_editor_property("auto_exposure_max_brightness", 8.0)
    s.set_editor_property("override_auto_exposure_bias", True)
    s.set_editor_property("auto_exposure_bias", 1.0)
    # Bloom (glow on the magma)
    s.set_editor_property("override_bloom_intensity", True)
    s.set_editor_property("bloom_intensity", 0.85)
    s.set_editor_property("override_bloom_threshold", True)
    s.set_editor_property("bloom_threshold", 0.8)
    ppv.set_editor_property("settings", s)
    L("configured post process")

    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    L("save_current_level=%s" % les.save_current_level())
    res["ok"] = True
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
unreal.log("PEACE3_STEP4_DONE ok=%s" % res.get("ok"))

import unreal, json

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
cfg = json.load(open(BASE + "/tune.json"))
log = []
eal = unreal.EditorAssetLibrary
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)


def find(lab):
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == lab:
            return a
    return None


# Material instance of M_Magma for param tweaks without recompiling
MI = "/Game/AiQuiz/Materials/MI_Magma"
base = eal.load_asset("/Game/AiQuiz/Materials/M_Magma")
if not eal.does_asset_exist(MI):
    at = unreal.AssetToolsHelpers.get_asset_tools()
    mi = at.create_asset("MI_Magma", "/Game/AiQuiz/Materials",
                         unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    mi.set_editor_property("parent", base)
    log.append("created MI_Magma")
else:
    mi = eal.load_asset(MI)
unreal.MaterialEditingLibrary.set_material_instance_scalar_parameter_value(mi, "EmissiveIntensity", float(cfg["emissive"]))
# Arbitrary magma look params (VScale/VeinWidth/FbmScale/CrustEmber/NormalStrength)
for k, v in cfg.get("mparams", {}).items():
    unreal.MaterialEditingLibrary.set_material_instance_scalar_parameter_value(mi, k, float(v))
    log.append("%s=%s" % (k, v))
eal.save_asset(MI, only_if_is_dirty=False)
log.append("EmissiveIntensity=%s" % cfg["emissive"])

magma = find("Magma_Floor")
smc = magma.get_component_by_class(unreal.StaticMeshComponent)
smc.set_material(0, mi)
log.append("assigned MI_Magma")

# Sky light ambient level
sky = find("SkyLight")
sc = sky.get_component_by_class(unreal.SkyLightComponent)
sc.set_editor_property("intensity", float(cfg["sky"]))
try:
    sc.recapture_sky()
except Exception as e:
    log.append("recap:%s" % e)

# Directional KeyLight: grazing angle + intensity + cool tint to sculpt the
# crust relief (the magma normal map only reads under raking light).
key = find("KeyLight")
if key and ("dir_pitch" in cfg or "dir_intensity" in cfg):
    kc = key.get_component_by_class(unreal.DirectionalLightComponent)
    if "dir_pitch" in cfg:
        key.set_actor_rotation(
            unreal.Rotator(0.0, float(cfg["dir_pitch"]), float(cfg.get("dir_yaw", 0.0))), False)
    if "dir_intensity" in cfg:
        kc.set_editor_property("intensity", float(cfg["dir_intensity"]))
    if "dir_color" in cfg:
        c = cfg["dir_color"]
        kc.set_editor_property("light_color", unreal.Color(int(c[0]), int(c[1]), int(c[2]), 255))
    log.append("key pitch=%s yaw=%s int=%s" % (
        cfg.get("dir_pitch"), cfg.get("dir_yaw"), cfg.get("dir_intensity")))

# Fog (BG-tinted atmospheric haze like Godot env.fog)
if "fog" in cfg:
    fog = find("Stage_Fog")
    if fog:
        fc = fog.get_component_by_class(unreal.ExponentialHeightFogComponent)
        fc.set_editor_property("fog_density", float(cfg["fog"]))
        log.append("fog=%s" % cfg["fog"])

# Exposure (locked) + bloom
ppv = find("Stage_PostProcess")
s = ppv.get_editor_property("settings")
if "bloom_i" in cfg:
    s.set_editor_property("override_bloom_intensity", True)
    s.set_editor_property("bloom_intensity", float(cfg["bloom_i"]))
    s.set_editor_property("override_bloom_threshold", True)
    s.set_editor_property("bloom_threshold", float(cfg["bloom_t"]))
    log.append("bloom i=%s t=%s" % (cfg["bloom_i"], cfg["bloom_t"]))
s.set_editor_property("override_auto_exposure_min_brightness", True)
s.set_editor_property("auto_exposure_min_brightness", float(cfg["expo"]))
s.set_editor_property("override_auto_exposure_max_brightness", True)
s.set_editor_property("auto_exposure_max_brightness", float(cfg["expo"]))
ppv.set_editor_property("settings", s)
log.append("sky=%s expo=%s" % (cfg["sky"], cfg["expo"]))

if cfg.get("save"):
    unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).save_current_level()
    log.append("level saved")

# Shot
v = cfg["cam"].split()
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(
    unreal.Vector(float(v[0]), float(v[1]), float(v[2])),
    unreal.Rotator(float(v[3]), float(v[4]), float(v[5])))
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, BASE + "/" + cfg["name"] + ".png")
print(json.dumps(log))

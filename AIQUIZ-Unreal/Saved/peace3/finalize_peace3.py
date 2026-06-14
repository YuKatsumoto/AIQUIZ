import unreal, json

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
SHOT = BASE + "/finish_shot.png"
OUT = BASE + "/result_finish.json"
summary = {"ok": False, "log": []}
L = summary["log"].append
eal = unreal.EditorAssetLibrary
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

# 1) Remove the throwaway test material
TG = "/Game/AiQuiz/Materials/M_TestGlow"
if eal.does_asset_exist(TG):
    eal.delete_asset(TG)
    L("deleted M_TestGlow")

# 2) Ensure Magma_Floor uses M_Magma
mag_mat = eal.load_asset("/Game/AiQuiz/Materials/M_Magma")
magma = None
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Magma_Floor":
        magma = a
        break
if magma:
    smc = magma.get_component_by_class(unreal.StaticMeshComponent)
    cur = smc.get_material(0)
    if not cur or cur.get_name() != "M_Magma":
        smc.set_material(0, mag_mat)
        L("re-assigned M_Magma")
    summary["magma_material"] = smc.get_material(0).get_name()

# 3) Enable volumetric fog (correct property name in 5.7)
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Stage_Fog":
        comp = a.get_component_by_class(unreal.ExponentialHeightFogComponent)
        try:
            comp.set_editor_property("enable_volumetric_fog", True)
            comp.set_editor_property("volumetric_fog_scattering_distribution", 0.4)
            L("volumetric fog enabled")
        except Exception as e:
            L("vol fog err: %s" % e)
        break

# 4) Hero presentation camera (runway down the belt, magma flanking)
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(-500.0, 0.0, 340.0),
                                   unreal.Rotator(0.0, -32.0, 0.0))
L("camera set")

# 5) Save + screenshot
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
summary["saved"] = les.save_current_level()
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, SHOT)
L("screenshot -> finish_shot.png")
summary["ok"] = True

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)
unreal.log("PEACE3_FINALIZE_DONE ok=%s" % summary["ok"])
print("PEACE3_FINALIZE_DONE", summary)

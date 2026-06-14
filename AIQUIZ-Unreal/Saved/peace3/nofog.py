import unreal
eas=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
# restore MI_Magma to magma (debug2 left M_MagmaDebug2 on it)
eal=unreal.EditorAssetLibrary
mi=eal.load_asset("/Game/AiQuiz/Materials/MI_Magma")
for a in eas.get_all_level_actors():
    if a.get_actor_label()=="Magma_Floor":
        a.get_component_by_class(unreal.StaticMeshComponent).set_material(0, mi)
    if a.get_actor_label()=="Stage_Fog":
        a.get_component_by_class(unreal.ExponentialHeightFogComponent).set_editor_property("fog_density", 0.0)
# exposure back to 1.0 locked
for a in eas.get_all_level_actors():
    if a.get_actor_label()=="Stage_PostProcess":
        s=a.get_editor_property("settings")
        s.set_editor_property("auto_exposure_min_brightness",1.0)
        s.set_editor_property("auto_exposure_max_brightness",1.0)
        a.set_editor_property("settings",s)
ues=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(-2000,2200,500), unreal.Rotator(0,-18,-32))
unreal.AutomationLibrary.take_high_res_screenshot(1280,720,r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/nofog.png")
print("done")

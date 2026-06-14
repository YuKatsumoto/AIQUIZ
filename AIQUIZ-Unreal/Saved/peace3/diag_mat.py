import unreal
eal=unreal.EditorAssetLibrary
MEL=unreal.MaterialEditingLibrary
base=eal.load_asset("/Game/AiQuiz/Materials/M_Magma")
# scalar params on base
try:
    names=MEL.get_scalar_parameter_names(base)
except Exception as e:
    names="ERR %s"%e
print("BASE_SCALAR_PARAMS", names)
mi=eal.load_asset("/Game/AiQuiz/Materials/MI_Magma")
print("MI_PARENT", mi.get_editor_property("parent").get_name() if mi.get_editor_property("parent") else None)
try:
    print("MI_EMISSIVE_VAL", MEL.get_material_instance_scalar_parameter_value(mi,"EmissiveIntensity"))
except Exception as e:
    print("MI_GET_ERR", e)
# assign BASE directly to magma
eas=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
for a in eas.get_all_level_actors():
    if a.get_actor_label()=="Magma_Floor":
        a.get_component_by_class(unreal.StaticMeshComponent).set_material(0, base)
    if a.get_actor_label()=="Stage_PostProcess":
        s=a.get_editor_property("settings")
        s.set_editor_property("auto_exposure_min_brightness",1.0)
        s.set_editor_property("auto_exposure_max_brightness",1.0)
        a.set_editor_property("settings",s)
ues=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(-2000,2200,500), unreal.Rotator(0,-18,-32))
unreal.AutomationLibrary.take_high_res_screenshot(1280,720,r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/diag_base.png")
print("shot diag_base (BASE M_Magma, default emissive 4, expo 1.0)")

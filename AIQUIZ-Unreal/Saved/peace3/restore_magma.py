import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
SHOT = BASE + "/magma_shot.png"
eal = unreal.EditorAssetLibrary

mag_mat = eal.load_asset("/Game/AiQuiz/Materials/M_Magma")
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Magma_Floor":
        smc = a.get_component_by_class(unreal.StaticMeshComponent)
        smc.set_material(0, mag_mat)
        print("restored M_Magma to Magma_Floor")
        break

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
print("saved", les.save_current_level())

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(-500.0, 0.0, 340.0), unreal.Rotator(0.0, -32.0, 0.0))
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, SHOT)
print("shot ->", SHOT)

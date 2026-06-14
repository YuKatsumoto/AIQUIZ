import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
SHOT = BASE + "/glow_shot.png"
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()

TP = "/Game/AiQuiz/Materials/M_TestGlow"
if not eal.does_asset_exist(TP):
    m = at.create_asset("M_TestGlow", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
else:
    m = eal.load_asset(TP)
    MEL.delete_all_material_expressions(m)
c = MEL.create_material_expression(m, unreal.MaterialExpressionConstant3Vector, -300, 0)
c.set_editor_property("constant", unreal.LinearColor(12.0, 3.0, 0.2, 1.0))
MEL.connect_material_property(c, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
MEL.recompile_material(m)
eal.save_asset(TP, only_if_is_dirty=False)
print("M_TestGlow built")

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Magma_Floor":
        smc = a.get_component_by_class(unreal.StaticMeshComponent)
        smc.set_material(0, m)
        print("assigned M_TestGlow to Magma_Floor")
        break

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(-500.0, 0.0, 340.0), unreal.Rotator(0.0, -32.0, 0.0))
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, SHOT)
print("shot ->", SHOT)

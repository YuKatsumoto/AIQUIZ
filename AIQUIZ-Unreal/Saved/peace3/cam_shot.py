import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
SHOT = BASE + "/finish_shot.png"

# Presentation camera looking down the belt (travel = +X)
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(-1400.0, 0.0, 650.0),
                                   unreal.Rotator(0.0, -16.0, 0.0))
print("camera set")

unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, SHOT)
print("screenshot requested ->", SHOT)

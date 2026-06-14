import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
vals = open(BASE + "/cam_pose.txt").read().split()
x, y, z, r_roll, r_pitch, r_yaw = map(float, vals[:6])
name = vals[6] if len(vals) > 6 else "vshot"

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(unreal.Vector(x, y, z), unreal.Rotator(r_roll, r_pitch, r_yaw))
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, BASE + "/" + name + ".png")
print("vshot ->", name)

import unreal, sys

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
name = "now"
# default hero camera; can be overridden by editing below
cams = {
    "hero": (unreal.Vector(-500.0, 0.0, 340.0), unreal.Rotator(0.0, -32.0, 0.0)),
    "magma": (unreal.Vector(-200.0, 1400.0, 250.0), unreal.Rotator(0.0, -22.0, -150.0)),
}
which = "hero"
loc, rot = cams[which]
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
ues.set_level_viewport_camera_info(loc, rot)
out = BASE + "/shot_" + which + ".png"
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, out)
print("shot ->", out)

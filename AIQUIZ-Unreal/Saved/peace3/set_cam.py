import unreal
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
# Look down the conveyor belt (travel = +X). Floor center X=400, top Z~-120.
loc = unreal.Vector(-1400.0, 0.0, 650.0)
rot = unreal.Rotator(0.0, -16.0, 0.0)  # roll, pitch, yaw
ues.set_level_viewport_camera_info(loc, rot)
unreal.log("PEACE3_CAM_SET")

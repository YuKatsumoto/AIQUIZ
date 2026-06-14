import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
vals = open(BASE + "/cam_pose.txt").read().split()
# rotation triple is (roll, pitch, yaw) to match unreal.Rotator positional order
x, y, z, r_roll, r_pitch, r_yaw = map(float, vals[:6])
name = vals[6] if len(vals) > 6 else "cap"

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
world = ues.get_editor_world()
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

loc = unreal.Vector(x, y, z)
rot = unreal.Rotator(r_roll, r_pitch, r_yaw)

cap = None
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "__Cap":
        cap = a
        break
if not cap:
    cap = eas.spawn_actor_from_class(unreal.SceneCapture2D, loc, rot)
    cap.set_actor_label("__Cap")
cap.set_actor_location_and_rotation(loc, rot, False, False)

comp = cap.get_component_by_class(unreal.SceneCaptureComponent2D)
rt = unreal.RenderingLibrary.create_render_target2d(
    world, 1280, 720, unreal.TextureRenderTargetFormat.RTF_RGBA8,
    unreal.LinearColor(0.0, 0.0, 0.0, 1.0), False)
comp.set_editor_property("capture_source", unreal.SceneCaptureSource.SCS_FINAL_COLOR_LDR)
comp.set_editor_property("texture_target", rt)
comp.set_editor_property("fov_angle", 90.0)
comp.set_editor_property("capture_every_frame", False)
comp.set_editor_property("capture_on_movement", False)
# SceneCapture renders one frame synchronously, so auto-exposure can't adapt.
# Use a FIXED locked exposure (calibrated, lower value = brighter image).
try:
    expo = float(open(BASE + "/cap_expo.txt").read().strip())
except Exception:
    expo = 0.1
pp = comp.get_editor_property("post_process_settings")
pp.set_editor_property("override_auto_exposure_method", True)
pp.set_editor_property("auto_exposure_method", unreal.AutoExposureMethod.AEM_HISTOGRAM)
pp.set_editor_property("override_auto_exposure_min_brightness", True)
pp.set_editor_property("auto_exposure_min_brightness", expo)
pp.set_editor_property("override_auto_exposure_max_brightness", True)
pp.set_editor_property("auto_exposure_max_brightness", expo)
comp.set_editor_property("post_process_settings", pp)

comp.capture_scene()
unreal.RenderingLibrary.export_render_target(world, rt, BASE, name + ".png")
print("captured ->", BASE + "/" + name + ".png")

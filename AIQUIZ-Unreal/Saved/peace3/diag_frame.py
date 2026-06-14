import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
SHOT = BASE + "/diag_shot.png"

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
magma = None
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Magma_Floor":
        magma = a
        break

if not magma:
    print("NO MAGMA_FLOOR")
else:
    loc = magma.get_actor_location()
    origin, extent = magma.get_actor_bounds(False)
    print("MAGMA_LOC", loc.x, loc.y, loc.z)
    print("MAGMA_ORIGIN", origin.x, origin.y, origin.z)
    print("MAGMA_EXTENT", extent.x, extent.y, extent.z)
    smc = magma.get_component_by_class(unreal.StaticMeshComponent)
    m = smc.get_material(0)
    print("MAGMA_MAT", m.get_name() if m else None)

    # Frame camera straight in front, looking down at the magma plane
    cam = unreal.Vector(origin.x - 900.0, origin.y, origin.z + 700.0)
    rot = unreal.Rotator(0.0, -32.0, 0.0)
    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    ues.set_level_viewport_camera_info(cam, rot)
    print("CAM", cam.x, cam.y, cam.z)
    unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, SHOT)
    print("shot ->", SHOT)

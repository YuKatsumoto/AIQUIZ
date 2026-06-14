import unreal

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
for lab in ("Stage_Floor", "Magma_Floor", "Stage_Fog", "Stage_PostProcess", "KeyLight"):
    a = None
    for x in eas.get_all_level_actors():
        if x.get_actor_label() == lab:
            a = x
            break
    if not a:
        print(lab, "MISSING")
        continue
    loc = a.get_actor_location()
    scl = a.get_actor_scale3d()
    try:
        o, e = a.get_actor_bounds(False)
        bb = "bounds_o=(%.0f,%.0f,%.0f) ext=(%.0f,%.0f,%.0f)" % (o.x, o.y, o.z, e.x, e.y, e.z)
    except Exception:
        bb = ""
    print(lab, "loc=(%.0f,%.0f,%.0f)" % (loc.x, loc.y, loc.z), "scale=(%.2f,%.2f,%.2f)" % (scl.x, scl.y, scl.z), bb)

import unreal

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
for a in eas.get_all_level_actors():
    lab = a.get_actor_label()
    cls = a.get_class().get_name()
    if cls in ("DirectionalLight", "SkyLight", "SkyAtmosphere"):
        rot = a.get_actor_rotation()
        print("=== %s (%s) rot=(%.0f,%.0f,%.0f)" % (lab, cls, rot.pitch, rot.yaw, rot.roll))
        if cls == "DirectionalLight":
            c = a.get_component_by_class(unreal.DirectionalLightComponent)
            print("   intensity", c.get_editor_property("intensity"), "color", c.get_editor_property("light_color"))
        elif cls == "SkyLight":
            c = a.get_component_by_class(unreal.SkyLightComponent)
            print("   intensity", c.get_editor_property("intensity"),
                  "source", c.get_editor_property("source_type"))

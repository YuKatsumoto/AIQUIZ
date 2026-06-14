import unreal, json
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
out = []
for a in eas.get_all_level_actors():
    lab = a.get_actor_label()
    cls = a.get_class().get_name()
    if "Light" in cls or "Light" in lab or "Sky" in cls or "Fog" in cls or "PostProcess" in cls:
        rot = a.get_actor_rotation()
        info = {"label": lab, "class": cls,
                "rot": [round(rot.roll, 1), round(rot.pitch, 1), round(rot.yaw, 1)]}
        # try to read intensity
        for comp_cls in (unreal.DirectionalLightComponent, unreal.SkyLightComponent,
                         unreal.PointLightComponent, unreal.SpotLightComponent):
            c = a.get_component_by_class(comp_cls)
            if c:
                try:
                    info["intensity"] = round(c.get_editor_property("intensity"), 3)
                except Exception:
                    pass
                try:
                    col = c.get_editor_property("light_color")
                    info["color"] = [col.r, col.g, col.b]
                except Exception:
                    pass
                break
        out.append(info)
print("LIGHTS", json.dumps(out, ensure_ascii=False))
open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_lights.json", "w", encoding="utf-8").write(json.dumps(out, ensure_ascii=False, indent=2))

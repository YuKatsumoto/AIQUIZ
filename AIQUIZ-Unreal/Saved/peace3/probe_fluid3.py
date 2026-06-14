import unreal, json
res = {"log": []}
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
act = None
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Magma_Fluid":
        act = a
        break
comp = act.get_component_by_class(unreal.NiagaraComponent)

# materials used by the niagara renderers
try:
    mats = comp.get_used_materials() if hasattr(comp, "get_used_materials") else comp.get_materials()
    res["used_materials"] = [str(m.get_name()) if m else None for m in mats]
    res["used_material_paths"] = [str(m.get_path_name()) if m else None for m in mats]
except Exception as e:
    res["mat_err"] = str(e)

# component methods that look like parameter setters / material override
res["set_methods"] = [m for m in dir(comp) if m.startswith("set_") and
                      ("material" in m or "variable" in m or " niagara" in m.lower())]
res["var_methods"] = [m for m in dir(comp) if "variable" in m.lower() or "override" in m.lower()][:40]

print("FLUID3", json.dumps(res, ensure_ascii=False))
open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_fluid3.json", "w", encoding="utf-8").write(
    json.dumps(res, ensure_ascii=False, indent=2))

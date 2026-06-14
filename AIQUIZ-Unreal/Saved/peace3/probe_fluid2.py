import unreal, json
res = {}
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
act = None
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Magma_Fluid":
        act = a
        break
res["found"] = act is not None
if act:
    o, ext = act.get_actor_bounds(False)
    res["origin"] = [round(o.x), round(o.y), round(o.z)]
    res["extent"] = [round(ext.x), round(ext.y), round(ext.z)]
    comp = act.get_component_by_class(unreal.NiagaraComponent)
    sysm = comp.get_editor_property("asset")
    res["asset"] = str(sysm.get_name()) if sysm else None
    # read exposed user parameters from the system
    try:
        exposed = sysm.get_exposed_parameters()
        res["exposed"] = [str(p) for p in exposed][:80]
    except Exception as e:
        res["exposed_err"] = str(e)
    # alt: variable names via component
    for meth in ["get_overridable_parameters", "get_variable_names"]:
        if hasattr(comp, meth):
            try:
                res[meth] = [str(x) for x in getattr(comp, meth)()][:80]
            except Exception as e:
                res[meth + "_err"] = str(e)
print("FLUID2", json.dumps(res, ensure_ascii=False))
open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_fluid2.json", "w", encoding="utf-8").write(
    json.dumps(res, ensure_ascii=False, indent=2))

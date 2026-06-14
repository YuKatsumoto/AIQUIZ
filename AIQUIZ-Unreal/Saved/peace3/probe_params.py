import unreal, json
res = {}
eal = unreal.EditorAssetLibrary
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
act = None
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Magma_Fluid":
        act = a; break
comp = act.get_component_by_class(unreal.NiagaraComponent)
sysm = comp.get_editor_property("asset")

# methods on system / component related to params
res["sys_param_methods"] = [m for m in dir(sysm) if any(k in m.lower() for k in ["param", "variable", "user", "exposed"])]

# try get_overridable_parameters -> NiagaraVariable list
try:
    ov = comp.get_overridable_parameters()
    res["overridable"] = [str(v.get_name()) if hasattr(v, "get_name") else str(v) for v in ov]
except Exception as e:
    res["overridable_err"] = str(e)

# try exposed_parameters store on the system
try:
    store = sysm.get_editor_property("exposed_parameters")
    res["store_type"] = str(type(store))
    res["store_methods"] = [m for m in dir(store) if not m.startswith("_")][:40]
    # attempt to read parameter names from store
    for meth in ["get_parameter_names", "get_variables", "get_parameter_variables"]:
        if hasattr(store, meth):
            try:
                res["store_" + meth] = [str(x) for x in getattr(store, meth)()][:80]
            except Exception as e:
                res["store_" + meth + "_err"] = str(e)
except Exception as e:
    res["store_err"] = str(e)

print("PARAMS", json.dumps(res, ensure_ascii=False))
open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_params.json", "w", encoding="utf-8").write(
    json.dumps(res, ensure_ascii=False, indent=2))

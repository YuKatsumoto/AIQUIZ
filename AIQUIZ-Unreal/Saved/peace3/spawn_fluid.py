import unreal, json, traceback
OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_fluid.json"
res = {"ok": False, "log": []}
L = res["log"].append
eal = unreal.EditorAssetLibrary
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
SYS = "/NiagaraFluids/Templates/Liquid/2D/Systems/ShallowWater/Grid2D_SW_Drop"
LABEL = "Magma_Fluid"
try:
    system = eal.load_asset(SYS)
    res["system_loaded"] = system is not None

    # remove old if present
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == LABEL:
            eas.destroy_actor(a)
            L("removed old Magma_Fluid")

    loc = unreal.Vector(0.0, 4000.0, 0.0)
    actor = eas.spawn_actor_from_class(unreal.NiagaraActor, loc, unreal.Rotator(0, 0, 0))
    actor.set_actor_label(LABEL)
    comp = actor.get_component_by_class(unreal.NiagaraComponent)
    comp.set_asset(system)
    comp.set_editor_property("auto_activate", True)
    try:
        comp.activate(True)
    except Exception as e:
        L("activate: %s" % e)
    # list user-exposed parameters so we know what we can tune (size, color, ...)
    try:
        params = comp.get_overridable_parameters() if hasattr(comp, "get_overridable_parameters") else []
        res["params"] = [str(p) for p in params][:60]
    except Exception as e:
        L("params err: %s" % e)
    res["loc"] = [loc.x, loc.y, loc.z]
    L("spawned Magma_Fluid (Grid2D_SW_Pool)")
    res["ok"] = True
except Exception as e:
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()
open(OUT, "w", encoding="utf-8").write(json.dumps(res, ensure_ascii=False, indent=2))
print("FLUID", json.dumps(res, ensure_ascii=False)[:1200])

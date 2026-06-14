import unreal, json
OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_swap.json"
res = {"ok": False, "log": []}
L = res["log"].append
eal = unreal.EditorAssetLibrary
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
try:
    grid = eal.load_asset("/Game/AiQuiz/Meshes/SM_MagmaGrid")
    mi = eal.load_asset("/Game/AiQuiz/Materials/MI_Magma")
    magma = None
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == "Magma_Floor":
            magma = a
            break
    if not magma:
        raise RuntimeError("Magma_Floor not found")
    smc = magma.get_component_by_class(unreal.StaticMeshComponent)
    smc.set_static_mesh(grid)
    smc.set_material(0, mi)
    # WPO deforms verts beyond the static bounds -> stop frustum/occlusion culling
    # from popping the floor; inflate the render bounds.
    try:
        smc.set_editor_property("bounds_scale", 4.0)
    except Exception as e:
        L("bounds_scale skip: %s" % e)
    try:
        smc.set_editor_property("cast_shadow", True)
    except Exception as e:
        L("cast_shadow skip: %s" % e)
    # keep transform: loc (400,0,-360), scale (360,360,1) like the original Plane
    magma.set_actor_scale3d(unreal.Vector(360.0, 360.0, 1.0))
    res["loc"] = [magma.get_actor_location().x, magma.get_actor_location().y, magma.get_actor_location().z]
    res["scale"] = [magma.get_actor_scale3d().x, magma.get_actor_scale3d().y, magma.get_actor_scale3d().z]
    L("swapped Magma_Floor -> SM_MagmaGrid")
    res["ok"] = True
except Exception as e:
    import traceback
    res["err"] = str(e)
    res["tb"] = traceback.format_exc()
open(OUT, "w", encoding="utf-8").write(json.dumps(res, ensure_ascii=False, indent=2))
print("SWAP", json.dumps(res, ensure_ascii=False))

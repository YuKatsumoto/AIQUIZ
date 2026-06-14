import unreal, json
res = {"log": []}
L = res["log"].append
eal = unreal.EditorAssetLibrary
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
lava = eal.load_asset("/Game/AiQuiz/Materials/M_LavaFluid")
act = None
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "Magma_Fluid":
        act = a; break
comp = act.get_component_by_class(unreal.NiagaraComponent)

mat_names = ["User.WaterMaterial", "User.SurfaceMaterial", "User.Material",
             "WaterMaterial", "SurfaceMaterial", "Material", "User.RenderMaterial"]
col_names = ["User.WaterColor", "User.Color", "WaterColor", "Color",
             "User.ShallowColor", "User.DeepColor", "User.SurfaceColor"]
orange = unreal.LinearColor(1.5, 0.45, 0.05, 1.0)
for n in mat_names:
    try:
        comp.set_variable_material(n, lava); L("matvar %s set" % n)
    except Exception as e:
        L("matvar %s err" % n)
for n in col_names:
    try:
        comp.set_variable_linear_color(n, orange); L("colvar %s set" % n)
    except Exception as e:
        L("colvar %s err" % n)
try:
    comp.reinitialize_system()
except Exception:
    try:
        comp.reset_system()
    except Exception:
        pass
print("RETINT2", json.dumps(res, ensure_ascii=False))
open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_retint2.json", "w", encoding="utf-8").write(
    json.dumps(res, ensure_ascii=False, indent=2))

import unreal, json
res = {}

# 1. Niagara core + fluids classes available?
for cls in ["NiagaraSystem", "NiagaraActor", "NiagaraComponent",
            "NiagaraFunctionLibrary", "NiagaraDataInterfaceGrid2DCollection",
            "NiagaraMeshRendererProperties"]:
    res[cls] = hasattr(unreal, cls)

# 2. Is the Niagara Fluids plugin mounted? (its content path resolves)
ar = unreal.AssetRegistryHelpers.get_asset_registry()


def list_path(p):
    try:
        assets = unreal.EditorAssetLibrary.list_assets(p, recursive=True, include_folder=False)
        return [str(a) for a in assets]
    except Exception as e:
        return ["ERR:%s" % e]


_nf = list_path("/NiagaraFluids")
res["NiagaraFluids_root"] = _nf[:40]
res["NiagaraFluids_count"] = len(_nf)
res["Niagara_root_count"] = len(list_path("/Niagara"))

# 3. Search asset registry for shallow-water / liquid / fluid Niagara systems
hits = []
try:
    all_nia = ar.get_assets_by_class(unreal.TopLevelAssetPath("/Script/Niagara", "NiagaraSystem"), False)
    for a in all_nia:
        nm = str(a.asset_name)
        pkg = str(a.package_name)
        low = (nm + pkg).lower()
        if any(k in low for k in ["shallow", "water", "liquid", "fluid", "lava", "splash", "pool"]):
            hits.append(pkg + "/" + nm)
except Exception as e:
    res["registry_err"] = str(e)
res["fluid_systems"] = hits[:60]
res["total_niagara_systems"] = len(all_nia) if 'all_nia' in dir() else "?"

open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_niagara.json", "w", encoding="utf-8").write(
    json.dumps(res, ensure_ascii=False, indent=2))
print("NIAGARA", json.dumps(res, ensure_ascii=False)[:1500])

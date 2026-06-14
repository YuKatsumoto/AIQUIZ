import unreal, json
res = {}
eal = unreal.EditorAssetLibrary
base = "/NiagaraFluids/Templates/Liquid/2D/Systems/ShallowWater"
res["listing"] = [str(a) for a in eal.list_assets(base, recursive=True, include_folder=False)]
cands = [
    base + "/Grid2D_SW_Pool",
    base + "/Grid2D_SW_Pool/Grid2D_SW_Pool",
    base + "/Grid2D_SW_Drop",
    base + "/Grid2D_SW_Drop/Grid2D_SW_Drop",
]
res["exists"] = {c: eal.does_asset_exist(c) for c in cands}
print("SWPATH", json.dumps(res, ensure_ascii=False, indent=2))
open(r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_swpath.json", "w", encoding="utf-8").write(
    json.dumps(res, ensure_ascii=False, indent=2))

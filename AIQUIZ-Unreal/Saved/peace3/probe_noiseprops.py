import unreal

MEL = unreal.MaterialEditingLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary

TMP = "/Game/AiQuiz/Materials/__probe_tmp"
if eal.does_asset_exist(TMP):
    eal.delete_asset(TMP)
mat = at.create_asset("__probe_tmp", "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
n = MEL.create_material_expression(mat, unreal.MaterialExpressionNoise, 0, 0)

# Default value of function
try:
    print("DEFAULT_function", n.get_editor_property("function"))
except Exception as e:
    print("get function ERR", e)

# Try setting each property; report which succeed
tests = {
    "function": unreal.NoiseFunction.NOISEFUNCTION_VORONOI_ALU,
    "scale": 0.004,
    "output_min": 0.0,
    "output_max": 1.0,
    "levels": 2,
    "turbulence": False,
    "quality": 1,
    "tiling": False,
    "repeat_size": 512,
}
for k, v in tests.items():
    try:
        n.set_editor_property(k, v)
        print("SET_OK", k)
    except Exception as e:
        print("SET_FAIL", k, "->", str(e)[:80])

# Is there a set-by-name fallback via the expression's own method?
print("HAS_set_function_attr", hasattr(n, "set_editor_property"))

eal.delete_asset(TMP)
print("PROBE_DONE")

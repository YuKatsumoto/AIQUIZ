import unreal

# Valid NoiseFunction enum values in this UE build
vals = [n for n in dir(unreal.NoiseFunction) if n.startswith("NOISEFUNCTION")]
print("NOISEFUNCTION_VALUES", vals)

# Does the previously-used name exist?
print("HAS_SIMPLEX_TEX", hasattr(unreal.NoiseFunction, "NOISEFUNCTION_SIMPLEX_TEX"))
print("HAS_VORONOI_ALU", hasattr(unreal.NoiseFunction, "NOISEFUNCTION_VORONOI_ALU"))

# Sanity: can we create a Noise expression at all (transient material)?
try:
    mf = unreal.MaterialFactoryNew()
    at = unreal.AssetToolsHelpers.get_asset_tools()
    print("PROBE_OK enum introspection done")
except Exception as e:
    print("PROBE_ERR", e)

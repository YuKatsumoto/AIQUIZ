import unreal, json
OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_probe.json"
out = {}
try:
    out["NoiseFunction"] = [a for a in dir(unreal.NoiseFunction) if a.isupper()]
except Exception as e:
    out["NoiseFunction_err"] = str(e)
# Confirm a few expression classes exist
for cname in ["MaterialExpressionNoise", "MaterialExpressionClamp", "MaterialExpressionSubtract",
              "MaterialExpressionDotProduct", "MaterialExpressionConstant3Vector",
              "ExponentialHeightFog", "PostProcessVolume"]:
    out[cname] = hasattr(unreal, cname)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)
unreal.log("PEACE3_PROBE_DONE")

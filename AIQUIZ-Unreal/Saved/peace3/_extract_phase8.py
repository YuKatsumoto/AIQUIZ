# -*- coding: utf-8 -*-
import json, os
OUT = r"C:/Users/kykat/AppData/Local/Temp/claude/C--aiquiz/ebd122f2-5d14-4456-801b-1b3d18f15541/tasks/wzq77q8rf.output"
d = json.load(open(OUT, encoding="utf-8"))
arts = d["result"]["artifacts"]
print("artifacts:", len(arts))
refdir = r"C:/aiquiz/AIQUIZ-Unreal/Saved/peace3"
for a in arts:
    sp = a.get("script_path", "").replace(chr(92), "/")
    sc = a.get("script_content", "")
    if sp and sc:
        os.makedirs(os.path.dirname(sp), exist_ok=True)
        open(sp, "w", encoding="utf-8").write(sc)
        print("WROTE", sp, len(sc), "chars")
    ref = refdir + "/_phase8_" + a["key"] + ".md"
    with open(ref, "w", encoding="utf-8") as f:
        f.write("# %s\n\n## summary\n%s\n\n## recipe\n%s\n\n## risks\n%s\n\n## hlsl\n```hlsl\n%s\n```\n" % (
            a.get("label"), a.get("summary", ""), a.get("recipe", ""), a.get("risks", ""), a.get("hlsl", "")))
    print("  ref ->", ref)

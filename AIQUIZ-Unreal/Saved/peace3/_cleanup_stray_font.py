import unreal, json
eal = unreal.EditorAssetLibrary
stray = "/Game/AiQuiz/UI/NotoSansJP-Regular_Font"
out = {"stray_existed": eal.does_asset_exist(stray)}
if out["stray_existed"]:
    # only delete if nothing references it (the real Font is F_NotoSansJP)
    refs = eal.find_package_referencers_for_asset(stray, False)
    out["referencers"] = list(refs) if refs else []
    if not refs:
        out["deleted"] = eal.delete_asset(stray)
print("RESULT " + json.dumps(out, ensure_ascii=False))

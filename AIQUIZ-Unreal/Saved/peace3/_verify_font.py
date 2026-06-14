import unreal, json
eal = unreal.EditorAssetLibrary
font = eal.load_asset("/Game/AiQuiz/UI/F_NotoSansJP")
ff = eal.load_asset("/Game/AiQuiz/UI/NotoSansJP-Regular")
deps = eal.find_package_referencers_for_asset if False else None
out = {
  "font_class": font.get_class().get_name() if font else None,
  "fontface_class": ff.get_class().get_name() if ff else None,
  "font_cache": str(font.get_editor_property("font_cache_type")) if font else None,
}
print("RESULT " + json.dumps(out, ensure_ascii=False))

# -*- coding: utf-8 -*-
import unreal, json
P = "/Game/AiQuiz/UI/F_NotoSansJP"
out = {"path": P}
eal = unreal.EditorAssetLibrary
a = eal.load_asset(P) if eal.does_asset_exist(P) else None
out["exists"] = a is not None
if a is not None:
    out["class"] = a.get_class().get_name()
    out["is_UFont"] = isinstance(a, unreal.Font)
    if isinstance(a, unreal.Font):
        try:
            out["cache_type"] = str(a.get_editor_property("font_cache_type"))
        except Exception as e:
            out["cache_type_err"] = str(e)
        try:
            cf = a.get_editor_property("composite_font")
            dtf = cf.get_editor_property("default_typeface")
            fonts = dtf.get_editor_property("fonts")
            faces = []
            for fe in fonts:
                fd = fe.get_editor_property("font")
                ffa = fd.get_editor_property("font_face_asset")
                faces.append(ffa.get_path_name() if ffa else None)
            out["typeface_faces"] = faces
        except Exception as e:
            out["composite_err"] = str(e)
# list all objects in the package + the UI dir
out["ui_assets"] = list(eal.list_assets("/Game/AiQuiz/UI", recursive=True))
print("RESULT " + json.dumps(out, ensure_ascii=False))

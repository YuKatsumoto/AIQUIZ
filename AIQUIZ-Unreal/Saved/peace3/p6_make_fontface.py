# -*- coding: utf-8 -*-
"""Import the OTF as the FontFace 'NotoSansJP-Regular' that F_NotoSansJP depends on.
Run via ue_exec.py in the LIVE (GUI) editor so Slate is available (headless commandlets
crash in the font import factory). Creates /Game/AiQuiz/UI/NotoSansJP-Regular (FontFace);
the existing F_NotoSansJP (Font) then resolves its missing dependency."""
import unreal, json, os

SRC = [
    "C:/AIQUIZ/AIQUIZ-Godot/resources/fonts/NotoSansJP-Regular.otf",
    "C:/aiquiz/AIQUIZ-Godot/resources/fonts/NotoSansJP-Regular.otf",
]
DEST = "/Game/AiQuiz/UI"
NAME = "NotoSansJP-Regular"

out = {"ok": False}
src = next((p for p in SRC if os.path.exists(p)), None)
out["src"] = src
if not src:
    out["err"] = "otf not found"
    print("RESULT " + json.dumps(out, ensure_ascii=False))
else:
    at = unreal.AssetToolsHelpers.get_asset_tools()
    eal = unreal.EditorAssetLibrary
    task = unreal.AssetImportTask()
    task.filename = src
    task.destination_path = DEST
    task.destination_name = NAME
    task.automated = True
    task.replace_existing = True
    task.save = True
    at.import_asset_tasks([task])
    out["imported"] = [o.get_name() for o in list(task.get_objects())]

    ff_path = DEST + "/" + NAME
    out["fontface_exists"] = eal.does_asset_exist(ff_path)
    ff = eal.load_asset(ff_path) if out["fontface_exists"] else None
    out["fontface_class"] = ff.get_class().get_name() if ff else None

    # Re-save the Font so its now-resolvable dependency is persisted.
    font = eal.load_asset(DEST + "/F_NotoSansJP")
    if font:
        eal.save_loaded_asset(font)
        out["font_resaved"] = True
    out["ok"] = bool(out["fontface_exists"])
    print("RESULT " + json.dumps(out, ensure_ascii=False))

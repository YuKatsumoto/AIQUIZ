# -*- coding: utf-8 -*-
"""Phase 6/7: NotoSansJP-Regular.otf を Runtime Font (/Game/AiQuiz/UI/F_NotoSansJP) として import。
TextRender (ドアラベル) と Canvas HUD の日本語描画に使う。

UE5.7 の Font import は通常 UFont(Runtime) + UFontFace を生成する。
1本目: そのまま import → 結果から UFont を探す。
2本目(保険): UFontFace しか出来なければ Runtime UFont を構築して composite font に紐付け。
"""
import unreal
import json
import os

SRC_CANDIDATES = [
    "C:/AIQUIZ/AIQUIZ-Godot/resources/fonts/NotoSansJP-Regular.otf",
    "C:/aiquiz/AIQUIZ-Godot/resources/fonts/NotoSansJP-Regular.otf",
]
DEST = "/Game/AiQuiz/UI"
FONT_NAME = "F_NotoSansJP"
out = {"steps": []}

src = next((p for p in SRC_CANDIDATES if os.path.exists(p)), None)
assert src is not None, "NotoSansJP-Regular.otf not found in %s" % SRC_CANDIDATES
out["src"] = src

at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary

if not eal.does_directory_exist(DEST):
    eal.make_directory(DEST)

# --- 1) import the OTF ---
task = unreal.AssetImportTask()
task.filename = src
task.destination_path = DEST
task.destination_name = FONT_NAME
task.automated = True
task.replace_existing = True
task.save = True
at.import_asset_tasks([task])
imported = [o.get_name() for o in list(task.get_objects())]
out["steps"].append({"imported": imported})

# --- 2) find a UFont among results / the destination dir ---
font_path = "%s/%s" % (DEST, FONT_NAME)
font = eal.load_asset(font_path) if eal.does_asset_exist(font_path) else None
if font and not isinstance(font, unreal.Font):
    font = None

face = None
for p in eal.list_assets(DEST, recursive=True):
    a = eal.load_asset(p)
    if isinstance(a, unreal.Font) and font is None:
        font = a
        out["found_font"] = p
    if isinstance(a, unreal.FontFace):
        face = a
        out["found_face"] = p

# --- 3) fallback: build a Runtime UFont from the FontFace ---
if font is None and face is not None:
    try:
        font = at.create_asset(FONT_NAME, DEST, unreal.Font, unreal.FontFactory())
        font.set_editor_property("font_cache_type", unreal.FontCacheType.RUNTIME)
        fd = unreal.FontData()
        fd.set_editor_property("font_face_asset", face)
        entry = unreal.TypefaceEntry()
        entry.set_editor_property("name", "Regular")
        entry.set_editor_property("font", fd)
        typeface = unreal.Typeface()
        typeface.set_editor_property("fonts", [entry])
        cf = unreal.CompositeFont()
        cf.set_editor_property("default_typeface", typeface)
        font.set_editor_property("composite_font", cf)
        out["steps"].append({"built_runtime_font": True})
    except Exception as e:
        out["build_error"] = str(e)

if font is not None:
    try:
        font.set_editor_property("font_cache_type", unreal.FontCacheType.RUNTIME)
    except Exception as e:
        out["cache_type_error"] = str(e)
    eal.save_loaded_asset(font)
    out["font_class"] = font.get_class().get_name()
    out["font_path"] = font.get_path_name()
    out["ok"] = True
else:
    out["ok"] = False
    out["error"] = "no UFont produced; door labels/HUD will use the engine default font"

print("RESULT " + json.dumps(out, ensure_ascii=False))

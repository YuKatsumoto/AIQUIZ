"""メニュー UI の画像 (左の影・ボタンの落ち影・ロゴのぼかした影) を取り込む。何度実行してもよい。

先に `python SourceAssets/Menu/make_menu_textures.py` で画像を作っておく。
"""
import unreal

GEN = r"G:/AIQUIZ-Main/AIQUIZ-UE/SourceAssets/Menu/Generated/"
tools = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary

for name, dest in (("T_UI_ScrimLeft", "/Game/UI"), ("T_UI_Shadow", "/Game/UI"), ("T_TestopiaLogoShadow", "/Game/UI/Branding")):
    t = unreal.AssetImportTask()
    t.filename = GEN + name + ".png"
    t.destination_path = dest
    t.destination_name = name
    t.automated = True
    t.replace_existing = True
    t.save = True
    tools.import_asset_tasks([t])
    tex = unreal.load_asset(dest + "/" + name)
    tex.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_EDITOR_ICON)
    tex.set_editor_property("mip_gen_settings", unreal.TextureMipGenSettings.TMGS_NO_MIPMAPS)
    tex.set_editor_property("lod_group", unreal.TextureGroup.TEXTUREGROUP_UI)
    tex.set_editor_property("srgb", True)
    eal.save_loaded_asset(tex)
    print("imported", dest + "/" + name)

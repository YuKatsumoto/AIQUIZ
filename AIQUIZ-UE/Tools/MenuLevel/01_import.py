"""ロゴと街の GLB を取り込み、メニューのレベル (/Game/Maps/L_Menu) を作る。最初に 1 回だけ実行する。"""
import unreal

SRC = r"G:/AIQUIZ-Main/AIQUIZ-UE/SourceAssets/Menu/"
MAP = "/Game/Maps/L_Menu"

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
eal = unreal.EditorAssetLibrary

# --- 1. ロゴ ---
task = unreal.AssetImportTask()
task.filename = SRC + "T_TestopiaLogo.png"
task.destination_path = "/Game/UI/Branding"
task.destination_name = "T_TestopiaLogo"
task.automated = True
task.replace_existing = True
task.save = True
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
logo = unreal.load_asset("/Game/UI/Branding/T_TestopiaLogo")
if logo:
    logo.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_EDITOR_ICON)
    logo.set_editor_property("mip_gen_settings", unreal.TextureMipGenSettings.TMGS_NO_MIPMAPS)
    logo.set_editor_property("lod_group", unreal.TextureGroup.TEXTUREGROUP_UI)
    logo.set_editor_property("srgb", True)
    eal.save_loaded_asset(logo)
print("logo:", logo)

# --- 2. レベル ---
if eal.does_asset_exist(MAP):
    les.load_level(MAP)
    print("loaded existing level")
else:
    print("new_level:", les.new_level(MAP))

# --- 3. GLB をシーンとして取り込む (ノードの配置を保つ) ---
im = unreal.InterchangeManager.get_interchange_manager_scripted()
for name in ("aiquiz_menu_stage", "aiquiz_menu_city"):
    before = set(a.get_path_name() for a in eas.get_all_level_actors())
    src = unreal.InterchangeManager.create_source_data(SRC + name + ".glb")
    params = unreal.ImportAssetParameters()
    params.is_automated = True
    params.replace_existing = True
    dest = "/Game/Menu/" + ("Stage" if name.endswith("stage") else "City")
    ok = im.import_scene(dest, src, params)
    after = [a for a in eas.get_all_level_actors() if a.get_path_name() not in before]
    print(name, "import_scene ->", ok, "new actors:", len(after))

les.save_current_level()
print("saved")

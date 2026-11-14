"""画づくり：露出・色・ブルーム、空 (雲・霧・天空光)、海底、波。値を書き換えて何度でも実行できる。"""
import unreal

EV = 0.0            # 固定の露出 (EV100)。小さいほど明るい
FLOOR_DEPTH = 1400  # 海底の深さ (cm)。浅いほど海が明るい青緑になる
FLOOR_RGB = (96, 200, 205)
SUN_PITCH, SUN_YAW = -42.0, -34.0
SKY_LIGHT = 1.25    # 天空光の強さ。影の中を持ち上げる
FOG_DENSITY = 0.0055
CLOUD_COVERAGE = -0.245  # 小さいほど雲が減って青空が広がる (既定は -0.2 で曇りがち)
CLOUD_DENSITY = 0.006    # 薄いほど白く明るい雲になる
CLOUD_SCALE = 256.0
# 港の中の穏やかな水面：短い波長・小さい振幅・ゆるい波
WAVES = {
    "num_waves": 16, "min_wavelength": 220.0, "max_wavelength": 1800.0, "wavelength_falloff": 2.0,
    "min_amplitude": 1.2, "max_amplitude": 7.0, "amplitude_falloff": 2.0,
    "direction_angular_spread_deg": 120.0, "small_wave_steepness": 0.22, "large_wave_steepness": 0.1,
}

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
eal = unreal.EditorAssetLibrary
mel = unreal.MaterialEditingLibrary
tools = unreal.AssetToolsHelpers.get_asset_tools()
MAT = "/Game/Menu/Runway/Materials"
TAG = "MenuLookBuilt"


def lin(rgb):
    return unreal.LinearColor(*[pow(c / 255.0, 2.2) for c in rgb], 1.0)


for a in list(eas.get_all_level_actors()):
    if TAG in [str(t) for t in a.tags] or a.get_actor_label() in ("MenuPostProcess", "SeaFloor"):
        eas.destroy_actor(a)

# --- 露出・ブルームなど (レベル全体) ---
ppv = eas.spawn_actor_from_class(unreal.PostProcessVolume, unreal.Vector(0, 0, 0), unreal.Rotator(0, 0, 0))
ppv.set_actor_label("MenuPostProcess")
ppv.set_folder_path("Menu/Env")
ppv.tags = [TAG]
ppv.set_editor_property("unbound", True)
s = ppv.get_editor_property("settings")
for k, v in (
    ("override_auto_exposure_bias", True), ("auto_exposure_bias", 0.0),
    ("override_auto_exposure_min_brightness", True), ("auto_exposure_min_brightness", EV),
    ("override_auto_exposure_max_brightness", True), ("auto_exposure_max_brightness", EV),
    ("override_bloom_intensity", True), ("bloom_intensity", 0.55),
    ("override_vignette_intensity", True), ("vignette_intensity", 0.28),
    ("override_color_saturation", True), ("color_saturation", unreal.Vector4(1.12, 1.12, 1.12, 1.0)),
    ("override_color_contrast", True), ("color_contrast", unreal.Vector4(1.05, 1.05, 1.05, 1.0)),
    ("override_white_temp", True), ("white_temp", 6800.0),
    ("override_sharpen", True), ("sharpen", 0.6),
    ("override_lens_flare_intensity", True), ("lens_flare_intensity", 0.15),
):
    try:
        s.set_editor_property(k, v)
    except Exception as e:
        print("post process:", k, e)
ppv.set_editor_property("settings", s)

# --- 雲：青空が見える晴れの積雲 ---
ENV = "/Game/Menu/Env"
cloud_path = ENV + "/MI_MenuClouds"
cloud_mi = unreal.load_asset(cloud_path) if eal.does_asset_exist(cloud_path) else tools.create_asset("MI_MenuClouds", ENV, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
mel.set_material_instance_parent(cloud_mi, unreal.load_asset("/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst"))
mel.set_material_instance_scalar_parameter_value(cloud_mi, "Cloud_GlobalCoverage", CLOUD_COVERAGE)
mel.set_material_instance_scalar_parameter_value(cloud_mi, "Cloud_GlobalDensity", CLOUD_DENSITY)
mel.set_material_instance_scalar_parameter_value(cloud_mi, "Layout_CloudGlobalScale", CLOUD_SCALE)
mel.update_material_instance(cloud_mi)
eal.save_loaded_asset(cloud_mi)

# --- 太陽・天空光・霧・雲 ---
for a in eas.get_all_level_actors():
    lab = a.get_actor_label()
    if lab == "Sun":
        a.set_actor_rotation(unreal.Rotator(roll=0, pitch=SUN_PITCH, yaw=SUN_YAW), False)
        a.light_component.set_editor_property("cast_cloud_shadows", False)
    elif lab == "SkyLight":
        a.light_component.set_editor_property("intensity", SKY_LIGHT)
    elif lab == "HeightFog":
        a.component.set_editor_property("fog_density", FOG_DENSITY)
    elif lab == "VolumetricCloud":
        c = a.get_component_by_class(unreal.VolumetricCloudComponent)
        c.set_editor_property("material", cloud_mi)
        c.set_editor_property("view_sample_count_scale", 1.5)
        # 雲の底を暗くしすぎない
        c.set_editor_property("sky_light_cloud_bottom_occlusion", 0.0)

# --- 海底：水の色が底なしで不自然にならないように ---
path = MAT + "/MI_MenuSeaFloor"
mi = unreal.load_asset(path) if eal.does_asset_exist(path) else tools.create_asset("MI_MenuSeaFloor", MAT, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
mel.set_material_instance_parent(mi, unreal.load_asset(MAT + "/M_MenuSolid"))
mel.set_material_instance_vector_parameter_value(mi, "Color", lin(FLOOR_RGB))
mel.set_material_instance_scalar_parameter_value(mi, "Roughness", 0.9)
mel.update_material_instance(mi)
eal.save_loaded_asset(mi)
f = eas.spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(0, -40000, -920 - FLOOR_DEPTH), unreal.Rotator(0, 0, 0))
f.set_actor_label("SeaFloor")
f.set_folder_path("Menu/Env")
f.tags = [TAG]
f.static_mesh_component.set_static_mesh(unreal.load_asset("/Engine/BasicShapes/Plane"))
f.static_mesh_component.set_material(0, mi)
f.static_mesh_component.set_editor_property("cast_shadow", False)
f.set_actor_scale3d(unreal.Vector(8000, 8000, 1))

# --- 波 ---
ocean = [a for a in eas.get_all_level_actors() if a.get_class().get_name() == "WaterBodyOcean"][0]
oc = ocean.get_component_by_class(unreal.WaterBodyOceanComponent)
waves = unreal.new_object(unreal.GerstnerWaterWaves, outer=ocean)
gen = unreal.new_object(unreal.GerstnerWaterWaveGeneratorSimple, outer=waves)
for k, v in WAVES.items():
    gen.set_editor_property(k, v)
# 生成器を差し替えると波の表が作り直される (生成器の値を直接変えるだけでは反映されない)
waves.set_editor_property("gerstner_wave_generator", gen)
ocean.set_water_waves(waves)
print("max wave height (cm):", oc.get_max_wave_height())

eas.set_selected_level_actors([])
les.save_current_level()
print("look applied: EV", EV)

"""メニューのレベルの環境 (空・太陽・霧・雲・海・街の配置・カメラ・観覧車) を組む。何度実行してもよい。

海を作り直すので、このあと 04_look.py をもう一度実行すること。
"""
import math

import unreal

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
world = ues.get_editor_world()
TAG = "MenuEnvBuilt"


def g2u(x, y, z):
    """Godot (m, Y up, -Z 前) → UE (cm)。glTF の取り込みと同じ対応。"""
    return unreal.Vector(x * 100.0, z * 100.0, y * 100.0)


def spawn(cls, label, loc=None, rot=None, folder="Menu/Env"):
    a = eas.spawn_actor_from_class(cls, loc or unreal.Vector(0, 0, 0), rot or unreal.Rotator(0, 0, 0))
    a.set_actor_label(label)
    a.set_folder_path(folder)
    a.tags = [TAG]
    return a


# --- 前回のぶんを消す ---
for a in list(eas.get_all_level_actors()):
    if TAG in [str(t) for t in a.tags] or a.get_class().get_name() in ("WaterZone", "WaterBodyOcean"):
        eas.destroy_actor(a)

# --- 取り込んだルートを見分ける ---
stage_root = city_root = None
for a in eas.get_all_level_actors():
    if a.get_class().get_name() == "Actor" and a.get_actor_label() in ("AIQUIZ_MenuStage", "MenuStage_Root", "MenuCity_Root"):
        kids = [k.get_actor_label() for k in a.get_attached_actors()]
        if "AMS_City" in kids:
            city_root = a
        else:
            stage_root = a

# 発進デッキは 2026-10-01 からメニューに組み立てていない (BUILD_LAUNCH_DECK = false)。レベルからは外す (アセットは残す)。
if stage_root:
    for k in stage_root.get_attached_actors():
        eas.destroy_actor(k)
    eas.destroy_actor(stage_root)
    print("stage removed from level")

CITY_YAW = -155.0  # Godot の yaw 155° (Y 軸まわり) は UE では -155°
city_root.set_actor_label("MenuCity_Root")
city_root.set_folder_path("Menu/City")
city_root.set_actor_location_and_rotation(g2u(404.618, -9.2, -883.158), unreal.Rotator(roll=0, pitch=0, yaw=CITY_YAW), False, False)
rim = None
gondolas = []
for k in city_root.get_attached_actors():
    k.set_folder_path("Menu/City")
    lab = k.get_actor_label()
    if lab == "AMS_FerrisWheelRim":
        rim = k
    elif lab.startswith("AMS_FerrisGondola_"):
        gondolas.append(k)
    if lab == "AMS_FerrisWheelRim" or lab.startswith("AMS_FerrisGondola_"):
        k.root_component.set_mobility(unreal.ComponentMobility.MOVABLE)
print("city placed; rim:", rim is not None, "gondolas:", len(gondolas))

# --- 太陽・空・霧・雲 ---
sun = spawn(unreal.DirectionalLight, "Sun", rot=unreal.Rotator(roll=0, pitch=-40.0, yaw=-34.0))
sun.root_component.set_mobility(unreal.ComponentMobility.MOVABLE)
sc = sun.light_component
sc.set_editor_property("intensity", 7.0)
sc.set_editor_property("atmosphere_sun_light", True)
# 雲の影は走路にかかると主役が暗くなるので落とさない
sc.set_editor_property("cast_cloud_shadows", False)
sc.set_editor_property("light_source_angle", 1.0)

spawn(unreal.SkyAtmosphere, "SkyAtmosphere")

sky = spawn(unreal.SkyLight, "SkyLight")
sky.root_component.set_mobility(unreal.ComponentMobility.MOVABLE)
sky.light_component.set_editor_property("real_time_capture", True)

fog = spawn(unreal.ExponentialHeightFog, "HeightFog", loc=unreal.Vector(0, 0, -920))
fc = fog.component
fc.set_editor_property("fog_density", 0.004)
fc.set_editor_property("fog_height_falloff", 0.05)

spawn(unreal.VolumetricCloud, "VolumetricCloud")

# --- カメラ (Godot: 位置 (-18, 6.1, 23.15)、俯角 -7°、yaw -19°、縦 FOV 37.5°) ---
v_fov = 37.5
h_fov = math.degrees(2.0 * math.atan(math.tan(math.radians(v_fov / 2.0)) * 16.0 / 9.0))
cam = spawn(unreal.CameraActor, "MenuCamera", loc=g2u(-18.0, 6.1, 23.15), rot=unreal.Rotator(roll=0, pitch=-7.0, yaw=-90.0 + 19.0), folder="Menu")
cam.tags = [TAG, "MenuCamera"]
cc = cam.camera_component
cc.set_editor_property("field_of_view", h_fov)
cc.set_editor_property("constrain_aspect_ratio", False)
print("camera h_fov: %.2f" % h_fov)

# --- 観覧車 ---
if rim:
    wheel = spawn(unreal.TestopiaFerrisWheel, "FerrisWheelDriver", loc=rim.get_actor_location(), folder="Menu/City")
    psi = math.radians(CITY_YAW)
    # 街のローカルの軸 (UE ローカル (0,-1,0) = 輪の正面・カメラの側) をワールドへ
    wheel.set_editor_property("axis_world", unreal.Vector(math.sin(psi), -math.cos(psi), 0.0))
    wheel.set_editor_property("rim", rim)
    wheel.set_editor_property("gondolas", sorted(gondolas, key=lambda g: g.get_actor_label()))
    wheel.set_editor_property("period_seconds", 180.0)

# --- 海 (Water プラグイン)。島の穴は街の地面の下に隠す ---
psi = math.radians(CITY_YAW)
lx, ly = 0.0, 10400.0  # 街のローカルの中心
cx = 40461.8 + lx * math.cos(psi) - ly * math.sin(psi)
cy = -88315.8 + lx * math.sin(psi) + ly * math.cos(psi)
ocean = spawn(unreal.WaterBodyOcean, "Ocean", loc=unreal.Vector(cx, cy, -920.0))
print("ocean:", ocean)
zones = [a for a in eas.get_all_level_actors() if a.get_class().get_name() == "WaterZone"]
print("zones:", len(zones))
for z in zones:
    z.set_folder_path("Menu/Env")
    try:
        z.set_editor_property("zone_extent", unreal.Vector2D(819200.0, 819200.0))
    except Exception as e:
        print("zone_extent:", e)
    print("zone loc:", z.get_actor_location(), "extent:", z.get_editor_property("zone_extent"))
oc = ocean.get_component_by_class(unreal.WaterBodyOceanComponent)
# 海の範囲をゾーンに合わせて広げる
for prop, val in (("ocean_extents", unreal.Vector2D(819200.0, 819200.0)), ("collision_extents", unreal.Vector(409600.0, 409600.0, 10000.0))):
    oc.set_editor_property(prop, val)

sp = ocean.get_component_by_class(unreal.WaterSplineComponent)
if sp:
    n = sp.get_number_of_spline_points()
    pts = [sp.get_location_at_spline_point(i, unreal.SplineCoordinateSpace.LOCAL) for i in range(n)]
    print("island spline:", [(round(p.x), round(p.y)) for p in pts])

# --- ゲームモード ---
world.get_world_settings().set_editor_property("default_game_mode", unreal.TestopiaMenuGameMode)

# --- エディタのカメラもメニューの構図に ---
ues.set_level_viewport_camera_info(cam.get_actor_location(), cam.get_actor_rotation())
les.save_current_level()
print("done")

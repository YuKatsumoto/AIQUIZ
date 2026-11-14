"""メニューの走路 (ベルト・側枠・クイズの壁) を組む。何度実行してもよい。

先に `python SourceAssets/Menu/make_menu_textures.py` で画像を作っておく。
のこぎりの台車は 07_saw_carriage.py が置く。
"""
import unreal

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
eal = unreal.EditorAssetLibrary
mel = unreal.MaterialEditingLibrary
tools = unreal.AssetToolsHelpers.get_asset_tools()

TAG = "MenuRunwayBuilt"
GEN = r"G:/AIQUIZ-Main/AIQUIZ-UE/SourceAssets/Menu/Generated/"
TEX = "/Game/Menu/Runway/Textures"
MAT = "/Game/Menu/Runway/Materials"
CUBE = unreal.load_asset("/Engine/BasicShapes/Cube")
PLANE = unreal.load_asset("/Engine/BasicShapes/Plane")
MP = unreal.MaterialProperty

# Godot：ベルトの箱 |x| < 12、z -136〜8、床の上面 y = -1.2、海面 y = -9.2。UE = (x, z, y) * 100
FLOOR_Z = -120.0
SEA_Z = -920.0
Y_MIN, Y_MAX = -13600.0, 800.0
Y_MID, Y_LEN = (Y_MIN + Y_MAX) / 2.0, (Y_MAX - Y_MIN)


def lin(rgb):
    return unreal.LinearColor(*[pow(c / 255.0, 2.2) for c in rgb], 1.0)


def import_tex(name, normal=False):
    t = unreal.AssetImportTask()
    t.filename = GEN + name + ".png"
    t.destination_path = TEX
    t.destination_name = name
    t.automated = True
    t.replace_existing = True
    t.save = True
    tools.import_asset_tasks([t])
    tex = unreal.load_asset(TEX + "/" + name)
    if normal:
        tex.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_NORMALMAP)
        tex.set_editor_property("srgb", False)
        eal.save_loaded_asset(tex)
    return tex


def new_material(name):
    path = MAT + "/" + name
    if eal.does_asset_exist(path):
        m = unreal.load_asset(path)
        mel.delete_all_material_expressions(m)
        return m
    return tools.create_asset(name, MAT, unreal.Material, unreal.MaterialFactoryNew())


def node(m, cls, x, y):
    return mel.create_material_expression(m, getattr(unreal, "MaterialExpression" + cls), x, y)


def link(a, out, b, inp):
    if not mel.connect_material_expressions(a, out, b, inp):
        print("LINK FAILED", a.get_name(), out, "->", b.get_name(), inp)


def const(m, value, x, y):
    n = node(m, "Constant", x, y)
    n.set_editor_property("r", value)
    return n


def scalar(m, name, value, x, y):
    n = node(m, "ScalarParameter", x, y)
    n.set_editor_property("parameter_name", name)
    n.set_editor_property("default_value", value)
    return n


def vector(m, name, rgb, x, y):
    n = node(m, "VectorParameter", x, y)
    n.set_editor_property("parameter_name", name)
    n.set_editor_property("default_value", lin(rgb))
    return n


def mask(m, src, channel, x, y):
    n = node(m, "ComponentMask", x, y)
    for c in "rgba":
        n.set_editor_property(c, c == channel)
    link(src, "", n, "")
    return n


def binary(m, cls, a, b, x, y, a_out="", b_out=""):
    n = node(m, cls, x, y)
    link(a, a_out, n, "A")
    link(b, b_out, n, "B")
    return n


def lerp(m, a, b, alpha, x, y):
    n = node(m, "LinearInterpolate", x, y)
    link(a, "", n, "A")
    link(b, "", n, "B")
    link(alpha, "", n, "Alpha")
    return n


def saturate(m, src, x, y):
    n = node(m, "Saturate", x, y)
    link(src, "", n, "")
    return n


def finish(m):
    mel.recompile_material(m)
    eal.save_loaded_asset(m)


def instance(name, parent):
    path = MAT + "/" + name
    mi = unreal.load_asset(path) if eal.does_asset_exist(path) else tools.create_asset(name, MAT, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    mel.set_material_instance_parent(mi, parent)
    return mi


# ---------- 画像 ----------
walls_tex = [import_tex("T_MenuWall_%02d" % i) for i in range(4)]
belt_tex = import_tex("T_MenuBeltSlat")
belt_nrm = import_tex("T_MenuBeltSlat_N", normal=True)

# ---------- 材質 ----------
# 単色 (色・粗さ・金属をパラメータに)
m_solid = new_material("M_MenuSolid")
mel.connect_material_property(vector(m_solid, "Color", (128, 128, 128), -400, 0), "", MP.MP_BASE_COLOR)
mel.connect_material_property(scalar(m_solid, "Roughness", 0.6, -400, 200), "", MP.MP_ROUGHNESS)
mel.connect_material_property(scalar(m_solid, "Metallic", 0.0, -400, 300), "", MP.MP_METALLIC)
finish(m_solid)


def solid_instance(name, rgb, roughness=0.6, metallic=0.0):
    mi = instance(name, m_solid)
    mel.set_material_instance_vector_parameter_value(mi, "Color", lin(rgb))
    mel.set_material_instance_scalar_parameter_value(mi, "Roughness", roughness)
    mel.set_material_instance_scalar_parameter_value(mi, "Metallic", metallic)
    mel.update_material_instance(mi)
    eal.save_loaded_asset(mi)
    return mi


# ベルト：ワールド座標で桟を並べ、カメラの側 (+Y) へ流す。桟の間隔 2m。色・粗さ (A)・法線
m_belt = new_material("M_MenuBelt")
wp = node(m_belt, "WorldPosition", -1400, 0)
along = binary(m_belt, "Divide", mask(m_belt, wp, "g", -1200, 0), const(m_belt, 200.0, -1200, 150), -1000, 0)
flow = binary(m_belt, "Multiply", node(m_belt, "Time", -1200, 300), scalar(m_belt, "SlatsPerSecond", 2.5, -1200, 400), -1000, 300)
v = binary(m_belt, "Subtract", along, flow, -800, 100)
uv = binary(m_belt, "AppendVector", const(m_belt, 0.5, -800, 0), v, -650, 100)
ts = node(m_belt, "TextureSample", -450, 0)
ts.set_editor_property("texture", belt_tex)
link(uv, "", ts, "UVs")
tn = node(m_belt, "TextureSample", -450, 300)
tn.set_editor_property("texture", belt_nrm)
tn.set_editor_property("sampler_type", unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL)
link(uv, "", tn, "UVs")
mel.connect_material_property(ts, "RGB", MP.MP_BASE_COLOR)
mel.connect_material_property(ts, "A", MP.MP_ROUGHNESS)
mel.connect_material_property(tn, "RGB", MP.MP_NORMAL)
mel.connect_material_property(const(m_belt, 0.1, -450, 550), "", MP.MP_METALLIC)
finish(m_belt)

# クイズの壁の面：RGB = 色、A = 光る所 (問題の板と扉)。光る所はつやのある板
m_face = new_material("M_MenuWallFace")
tp = node(m_face, "TextureSampleParameter2D", -700, 0)
tp.set_editor_property("parameter_name", "Tex")
tp.set_editor_property("texture", walls_tex[0])
mel.connect_material_property(tp, "RGB", MP.MP_BASE_COLOR)
glow = binary(m_face, "Multiply", tp, tp, -450, 200, "RGB", "A")
glow2 = binary(m_face, "Multiply", glow, scalar(m_face, "GlowStrength", 1.1, -450, 380), -250, 250)
mel.connect_material_property(glow2, "", MP.MP_EMISSIVE_COLOR)
rough = node(m_face, "LinearInterpolate", -250, 500)
link(scalar(m_face, "WallRoughness", 0.62, -500, 480), "", rough, "A")
link(scalar(m_face, "PanelRoughness", 0.2, -500, 560), "", rough, "B")
link(tp, "A", rough, "Alpha")
mel.connect_material_property(rough, "", MP.MP_ROUGHNESS)
finish(m_face)

# 箱の側面：塗装した鋼板。パネルの継ぎ目、上端の縁取り、水ぎわの濡れ
m_hull = new_material("M_MenuHull")
wp = node(m_hull, "WorldPosition", -1600, 0)
wz = mask(m_hull, wp, "b", -1400, -100)
wy = mask(m_hull, wp, "g", -1400, 100)
# 継ぎ目：4.6m ごとの細い線
fr = node(m_hull, "Frac", -1050, 100)
link(binary(m_hull, "Divide", wy, const(m_hull, 460.0, -1400, 220), -1200, 100), "", fr, "")
line = saturate(m_hull, binary(m_hull, "Multiply", binary(m_hull, "Subtract", const(m_hull, 0.01, -1050, 250), fr, -900, 150), const(m_hull, 400.0, -900, 300), -750, 150), -600, 150)
# 濡れ：海面から 1.3m 上まで
wet = saturate(m_hull, binary(m_hull, "Divide", binary(m_hull, "Subtract", const(m_hull, SEA_Z + 130.0, -1400, -300), wz, -1200, -250), const(m_hull, 110.0, -1200, -380), -1000, -250), -850, -250)
# 上端の縁取り：床の上面から 0.6m 下まで
trim = saturate(m_hull, binary(m_hull, "Divide", binary(m_hull, "Subtract", wz, const(m_hull, FLOOR_Z - 60.0, -1400, -500), -1200, -480), const(m_hull, 4.0, -1200, -600), -1000, -480), -850, -480)
body = vector(m_hull, "Color", (78, 96, 134), -700, -700)
body = binary(m_hull, "Multiply", body, lerp(m_hull, const(m_hull, 1.0, -700, 0), const(m_hull, 0.62, -700, 60), line, -500, 50), -350, -400)
body = binary(m_hull, "Multiply", body, lerp(m_hull, const(m_hull, 1.0, -700, -200), const(m_hull, 0.5, -700, -140), wet, -500, -200), -200, -350)
col = lerp(m_hull, body, vector(m_hull, "TrimColor", (214, 220, 232), -400, -650), trim, 0, -400)
mel.connect_material_property(col, "", MP.MP_BASE_COLOR)
mel.connect_material_property(lerp(m_hull, scalar(m_hull, "Roughness", 0.48, -400, 300), const(m_hull, 0.12, -400, 380), wet, -150, 320), "", MP.MP_ROUGHNESS)
mel.connect_material_property(lerp(m_hull, const(m_hull, 0.0, -400, 500), const(m_hull, 0.7, -400, 560), trim, -150, 520), "", MP.MP_METALLIC)
finish(m_hull)

mi_rail = solid_instance("MI_MenuRail", (206, 212, 222), 0.26, 1.0)
mi_wall = solid_instance("MI_MenuWall", (92, 102, 128), 0.6)
mi_faces = []
for i, t in enumerate(walls_tex):
    mi = instance("MI_MenuWallFace_%02d" % i, m_face)
    mel.set_material_instance_texture_parameter_value(mi, "Tex", t)
    mel.update_material_instance(mi)
    eal.save_loaded_asset(mi)
    mi_faces.append(mi)

# ---------- アクター ----------
for a in list(eas.get_all_level_actors()):
    if TAG in [str(t) for t in a.tags]:
        eas.destroy_actor(a)


def mesh_actor(label, mesh, mat, loc, scale, rot=None, shadow=True):
    a = eas.spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(*loc), rot or unreal.Rotator(0, 0, 0))
    a.set_actor_label(label)
    a.set_folder_path("Menu/Runway")
    a.tags = [TAG]
    c = a.static_mesh_component
    c.set_static_mesh(mesh)
    c.set_material(0, mat)
    c.set_editor_property("cast_shadow", shadow)
    a.set_actor_scale3d(unreal.Vector(*scale))
    return a


mesh_actor("Belt", CUBE, m_belt, (0, Y_MID, FLOOR_Z - 15.0), (23.4, Y_LEN / 100.0, 0.3))
mesh_actor("BeltBody", CUBE, m_hull, (0, Y_MID, FLOOR_Z - 30.0 - 600.0), (24.0, Y_LEN / 100.0 + 0.1, 12.0))
for side in (-1.0, 1.0):
    mesh_actor("BeltRail_%s" % ("L" if side < 0 else "R"), CUBE, mi_rail, (side * 1186.0, Y_MID, FLOOR_Z + 6.0), (0.28, Y_LEN / 100.0 + 0.1, 0.42))

# クイズの壁 (間隔 30m)。面の画像はカメラの側 (+Y)
WALL_W, WALL_H, WALL_T = 2300.0, 575.0, 60.0
for i, gz in enumerate((-14.0, -44.0, -74.0, -104.0)):
    y = gz * 100.0
    mesh_actor("QuizWall_%02d" % i, CUBE, mi_wall, (0, y, FLOOR_Z + WALL_H / 2.0), (WALL_W / 100.0, WALL_T / 100.0, WALL_H / 100.0))
    mesh_actor("QuizWallFace_%02d" % i, PLANE, mi_faces[i], (0, y + WALL_T / 2.0 + 1.0, FLOOR_Z + WALL_H / 2.0), (WALL_W / 100.0, WALL_H / 100.0, 1.0),
               rot=unreal.Rotator(roll=90.0, pitch=0.0, yaw=0.0), shadow=False)

# 前の版の材質 (使わなくなったもの) を片付ける
for old in ("M_MenuFace", "MI_MenuSaw", "MI_MenuBeltBody"):
    if eal.does_asset_exist(MAT + "/" + old) and not eal.find_package_referencers_for_asset(MAT + "/" + old, False):
        eal.delete_asset(MAT + "/" + old)
if eal.does_asset_exist(TEX + "/T_MenuSaw") and not eal.find_package_referencers_for_asset(TEX + "/T_MenuSaw", False):
    eal.delete_asset(TEX + "/T_MenuSaw")

les.save_current_level()
print("runway built")

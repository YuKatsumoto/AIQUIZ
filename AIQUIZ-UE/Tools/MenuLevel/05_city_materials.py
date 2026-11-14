"""街の材質を作り直す (Godot の aiquiz_backdrop.gdshader の移植 + ガラスの映り込み)。何度実行してもよい。

glTF の取り込みのままだと、頂点色が sRGB のまま使われて白く飛び、夜の窓明かりも昼から光ってしまう。
- 塗り (AQS_BG_Painted)：頂点色をリニアに直して色にする
- 外壁 (AMS_Facade_* / AQS_CityFacade_*)：頂点色 × 外壁の画像。青い所 (ガラス) は滑らかで空を映す
- 夜の灯 (AQS_NightGlow)：昼は頂点色のまま光らせない
"""
import unreal

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
eal = unreal.EditorAssetLibrary
mel = unreal.MaterialEditingLibrary
tools = unreal.AssetToolsHelpers.get_asset_tools()
MP = unreal.MaterialProperty
MAT = "/Game/Menu/City/Materials"
SRC = "/Game/Menu/City/aiquiz_menu_city/Materials"


def new_material(name):
    path = MAT + "/" + name
    if eal.does_asset_exist(path):
        m = unreal.load_asset(path)
        mel.delete_all_material_expressions(m)
        return m
    return tools.create_asset(name, MAT, unreal.Material, unreal.MaterialFactoryNew())


def scalar(m, name, value, x, y):
    n = mel.create_material_expression(m, unreal.MaterialExpressionScalarParameter, x, y)
    n.set_editor_property("parameter_name", name)
    n.set_editor_property("default_value", value)
    return n


def node(m, cls, x, y):
    return mel.create_material_expression(m, getattr(unreal, "MaterialExpression" + cls), x, y)


def link(a, out, b, inp):
    ok = mel.connect_material_expressions(a, out, b, inp)
    if not ok:
        print("LINK FAILED", a.get_name(), out, "->", b.get_name(), inp)


def linear_vertex_colour(m, x, y):
    """頂点色 (sRGB で入っている) をリニアに直す。"""
    vc = node(m, "VertexColor", x, y)
    pw = node(m, "Power", x + 200, y)
    pw.set_editor_property("const_exponent", 2.2)
    link(vc, "", pw, "Base")
    return pw


def finish(m):
    mel.recompile_material(m)
    eal.save_loaded_asset(m)


# ---- 塗り ----
m_paint = new_material("M_MenuCityPainted")
vc = linear_vertex_colour(m_paint, -700, 0)
mel.connect_material_property(vc, "", MP.MP_BASE_COLOR)
mel.connect_material_property(scalar(m_paint, "Roughness", 0.82, -400, 250), "", MP.MP_ROUGHNESS)
finish(m_paint)

# ---- 夜の灯 (昼は光らせない) ----
m_glow = new_material("M_MenuCityGlow")
vc = linear_vertex_colour(m_glow, -700, 0)
mel.connect_material_property(vc, "", MP.MP_BASE_COLOR)
mel.connect_material_property(scalar(m_glow, "Roughness", 0.25, -400, 250), "", MP.MP_ROUGHNESS)
glow = node(m_glow, "Multiply", -250, 400)
link(vc, "", glow, "A")
link(scalar(m_glow, "NightGlow", 0.0, -500, 450), "", glow, "B")
mel.connect_material_property(glow, "", MP.MP_EMISSIVE_COLOR)
finish(m_glow)

# ---- 外壁 ----
m_fac = new_material("M_MenuCityFacade")
vc = linear_vertex_colour(m_fac, -900, -200)
tex = node(m_fac, "TextureSampleParameter2D", -900, 100)
tex.set_editor_property("parameter_name", "Facade")
base = node(m_fac, "Multiply", -450, -100)
link(vc, "", base, "A")
link(tex, "RGB", base, "B")
mel.connect_material_property(base, "", MP.MP_BASE_COLOR)
# ガラスの目安：青が赤より強い所
sub = node(m_fac, "Subtract", -650, 300)
link(tex, "B", sub, "A")
link(tex, "R", sub, "B")
gain = node(m_fac, "Multiply", -480, 300)
link(sub, "", gain, "A")
link(scalar(m_fac, "GlassGain", 7.0, -700, 450), "", gain, "B")
mask = node(m_fac, "Saturate", -320, 300)
link(gain, "", mask, "")
rough = node(m_fac, "LinearInterpolate", -120, 250)
link(scalar(m_fac, "WallRoughness", 0.8, -400, 520), "", rough, "A")
link(scalar(m_fac, "GlassRoughness", 0.18, -400, 600), "", rough, "B")
link(mask, "", rough, "Alpha")
mel.connect_material_property(rough, "", MP.MP_ROUGHNESS)
metal = node(m_fac, "Multiply", -120, 450)
link(mask, "", metal, "A")
link(scalar(m_fac, "GlassMetallic", 0.3, -400, 700), "", metal, "B")
mel.connect_material_property(metal, "", MP.MP_METALLIC)
finish(m_fac)


def facade_instance(src_name):
    src = unreal.load_asset(SRC + "/" + src_name)
    tex_asset = None
    for t in src.get_editor_property("texture_parameter_values"):
        if str(t.parameter_info.name) == "BaseColorTexture":
            tex_asset = t.parameter_value
    name = "MI_Menu_" + src_name
    path = MAT + "/" + name
    mi = unreal.load_asset(path) if eal.does_asset_exist(path) else tools.create_asset(name, MAT, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    mel.set_material_instance_parent(mi, m_fac)
    mel.set_material_instance_texture_parameter_value(mi, "Facade", tex_asset)
    mel.update_material_instance(mi)
    eal.save_loaded_asset(mi)
    return mi


# ---- 街のメッシュの材質を差し替える (取り込んだ材質の名前で) ----
cache = {}
meshes = {}
for a in eas.get_all_level_actors():
    if a.get_folder_path() != "Menu/City" or not isinstance(a, unreal.StaticMeshActor):
        continue
    sm = a.static_mesh_component.static_mesh
    if sm:
        meshes[sm.get_path_name()] = sm
count = 0
for sm in meshes.values():
    changed = False
    for i, slot in enumerate(sm.static_materials):
        cur = sm.get_material(i)
        if not cur:
            continue
        key = str(slot.material_slot_name) if str(slot.material_slot_name) not in ("", "None") else cur.get_name()
        src_name = cur.get_name().replace("MI_Menu_", "")
        if cur.get_name().startswith("M_MenuCity"):
            src_name = key
        if "Facade" in src_name:
            new = cache.get(src_name) or facade_instance(src_name)
            cache[src_name] = new
        elif "NightGlow" in src_name:
            new = m_glow
        elif "Painted" in src_name:
            new = m_paint
        else:
            print("unknown material:", src_name, "on", sm.get_name())
            continue
        if new != cur:
            sm.set_material(i, new)
            changed = True
            count += 1
    if changed:
        eal.save_loaded_asset(sm)
print("meshes:", len(meshes), "slots changed:", count, "facade instances:", len(cache))
les.save_current_level()

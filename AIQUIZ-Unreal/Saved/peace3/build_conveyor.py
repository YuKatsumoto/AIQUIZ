import unreal, json, traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_conveyor.json"
res = {"ok": False, "log": []}
L = res["log"].append
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

# Godot->Unreal: x100, Godot z(len)->UnrealX, Godot x(width)->UnrealY, Godot y(up)->UnrealZ.
# Existing belt: center (400,0,-130), top z=-120, X in [-7600,8400] (len 16000),
# Y in [-1200,1200] (width 2400). center_x=400, half_len=8000.
CX, HALF_LEN = 400.0, 8000.0
TOP_Z = -120.0
CUBE = "/Engine/BasicShapes/Cube"
CYL = "/Engine/BasicShapes/Cylinder"


def simple_mat(name, color, metal, rough):
    p = "/Game/AiQuiz/Materials/" + name
    if eal.does_asset_exist(p):
        m = eal.load_asset(p); MEL.delete_all_material_expressions(m)
    else:
        at = unreal.AssetToolsHelpers.get_asset_tools()
        m = at.create_asset(name, "/Game/AiQuiz/Materials", unreal.Material, unreal.MaterialFactoryNew())
    c = MEL.create_material_expression(m, unreal.MaterialExpressionConstant3Vector, -400, 0)
    c.set_editor_property("constant", unreal.LinearColor(color[0], color[1], color[2], 1.0))
    MEL.connect_material_property(c, "", unreal.MaterialProperty.MP_BASE_COLOR)
    cm = MEL.create_material_expression(m, unreal.MaterialExpressionConstant, -400, 150)
    cm.set_editor_property("r", metal)
    MEL.connect_material_property(cm, "", unreal.MaterialProperty.MP_METALLIC)
    cr = MEL.create_material_expression(m, unreal.MaterialExpressionConstant, -400, 250)
    cr.set_editor_property("r", rough)
    MEL.connect_material_property(cr, "", unreal.MaterialProperty.MP_ROUGHNESS)
    MEL.recompile_material(m)
    eal.save_asset(p, only_if_is_dirty=False)
    return m


def spawn(mesh_path, label, loc, scale, mat, rot=None):
    # remove old
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == label:
            eas.destroy_actor(a)
    mesh = eal.load_asset(mesh_path)
    actor = eas.spawn_actor_from_object(mesh, unreal.Vector(*loc), rot if rot else unreal.Rotator(0, 0, 0))
    actor.set_actor_label(label)
    actor.set_actor_scale3d(unreal.Vector(*scale))
    smc = actor.get_component_by_class(unreal.StaticMeshComponent)
    if mat:
        smc.set_material(0, mat)
    return actor


try:
    m_rail = simple_mat("M_Rail", (0.27, 0.275, 0.28), 0.22, 0.66)
    m_frame = simple_mat("M_SideFrame", (0.30, 0.31, 0.33), 0.16, 0.62)
    m_roller = simple_mat("M_Roller", (0.36, 0.37, 0.38), 0.30, 0.50)
    belt = eal.load_asset("/Game/AiQuiz/Materials/M_ConveyorBelt")
    L("materials built")

    # --- Floor rails: Cube (Xlen 160 -> existing 16000; Y 0.16->16; Z 0.26->26) ---
    # rail Y = +-1186, Z = -107 (sits on belt top)
    for sgn, nm in ((1, "Rail_R"), (-1, "Rail_L")):
        spawn(CUBE, nm, (CX, sgn * 1186.0, -107.0), (160.0, 0.16, 0.26), m_rail)
    L("rails")

    # --- Side frames: Y 0.24->24, Z 1.05->105, Xlen 162.4; Y +-1188, Z -146.5 ---
    for sgn, nm in ((1, "SideFrame_R"), (-1, "SideFrame_L")):
        spawn(CUBE, nm, (CX, sgn * 1188.0, -146.5), (162.4, 0.24, 1.05), m_frame)
    L("side frames")

    # --- Rollers: cylinder r48 len2340 along Y; at X ends, Z=-168 ---
    # base Cylinder r50 h100 axis=localZ. radius -> scale X,Y =0.96; length -> scale
    # Z =23.4; roll 90 about X lays local-Z (length) along world Y.
    for x, nm in ((CX + HALF_LEN, "Roller_Front"), (CX - HALF_LEN, "Roller_Back")):
        spawn(CYL, nm, (x, 0.0, -168.0), (0.96, 0.96, 23.4), m_roller, unreal.Rotator(90.0, 0.0, 0.0))
    L("rollers")

    # --- Return belt: Xlen 159.88, Y 23.4, Z 0.10; Z=-224 ---
    spawn(CUBE, "Return_Belt", (CX, 0.0, -224.0), (159.88, 23.4, 0.10), belt)
    L("return belt")

    unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).save_current_level()
    L("saved")
    res["ok"] = True
except Exception as e:
    res["err"] = str(e); res["tb"] = traceback.format_exc()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
print("CONVEYOR", res.get("ok"), res.get("err", ""))

# -*- coding: utf-8 -*-
"""ブロック人間プロトタイプ: SK_YBot のボーン区間に色付きボックスを配置（見た目確定用）。
2回に分けて実行: 1回目=スケルトン配置+Run再生, 2回目=（エディタがTickしてRun姿勢になった後）ボックス構築。
C++ Pawn は同じ区間定義で実装する。"""
import unreal
import json

DEST = "/Game/AiQuiz/Character"
MAT = DEST + "/M_Blockman"
out = {}

# ボーン区間 (boneA, boneB, 太さUU, 色種別)
SEG = [
    ("Hips", "Spine1", 34, "body"),
    ("Spine1", "Neck", 40, "body"),
    ("Head", "HeadTop_End", 26, "head"),
    ("LeftArm", "LeftForeArm", 15, "limb"),
    ("LeftForeArm", "LeftHand", 13, "limb"),
    ("RightArm", "RightForeArm", 15, "limb"),
    ("RightForeArm", "RightHand", 13, "limb"),
    ("LeftUpLeg", "LeftLeg", 21, "limb"),
    ("LeftLeg", "LeftFoot", 17, "limb"),
    ("LeftFoot", "LeftToeBase", 13, "limb"),
    ("RightUpLeg", "RightLeg", 21, "limb"),
    ("RightLeg", "RightFoot", 17, "limb"),
    ("RightFoot", "RightToeBase", 13, "limb"),
]
COLORS = {"body": (0.95, 0.55, 0.20), "head": (0.95, 0.65, 0.35), "limb": (0.85, 0.48, 0.18)}

mel = unreal.MaterialEditingLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
w = ues.get_editor_world()
if (w is None) or ("L_Game" not in w.get_name()):
    les.load_level("/Game/AiQuiz/Maps/L_Game")

# --- M_Blockman 作成 ---
if not unreal.EditorAssetLibrary.does_asset_exist(MAT):
    mat = at.create_asset("M_Blockman", DEST, unreal.Material, unreal.MaterialFactoryNew())
    col = mel.create_material_expression(mat, unreal.MaterialExpressionVectorParameter, -350, 0)
    col.set_editor_property("parameter_name", "Color")
    col.set_editor_property("default_value", unreal.LinearColor(0.85, 0.48, 0.18, 1.0))
    mel.connect_material_property(col, "", unreal.MaterialProperty.MP_BASE_COLOR)
    rough = mel.create_material_expression(mat, unreal.MaterialExpressionConstant, -350, 220)
    rough.set_editor_property("r", 0.7)
    mel.connect_material_property(rough, "", unreal.MaterialProperty.MP_ROUGHNESS)
    mel.recompile_material(mat)
    unreal.EditorAssetLibrary.save_asset(MAT, False)
    out["material"] = "created"
else:
    out["material"] = "exists"

m_block = unreal.EditorAssetLibrary.load_asset(MAT)

# 3色の MaterialInstanceConstant（永続・エディタ描画可）
MICS = {}
for ckey, c in COLORS.items():
    mic_path = DEST + "/MI_BM_" + ckey
    if not unreal.EditorAssetLibrary.does_asset_exist(mic_path):
        mic = at.create_asset("MI_BM_" + ckey, DEST, unreal.MaterialInstanceConstant,
                              unreal.MaterialInstanceConstantFactoryNew())
        mel.set_material_instance_parent(mic, m_block)
        mel.set_material_instance_vector_parameter_value(mic, "Color", unreal.LinearColor(c[0], c[1], c[2], 1.0))
        unreal.EditorAssetLibrary.save_asset(mic_path, False)
    MICS[ckey] = unreal.EditorAssetLibrary.load_asset(mic_path)

cube = unreal.EditorAssetLibrary.load_asset("/Engine/BasicShapes/Cube")
sk = unreal.EditorAssetLibrary.load_asset(DEST + "/SK_YBot")
run = unreal.EditorAssetLibrary.load_asset(DEST + "/A_Run")


def find(label):
    for a in eas.get_all_level_actors():
        if a.get_actor_label() == label:
            return a
    return None


probe = find("__YBotProbe")
boxes = [a for a in eas.get_all_level_actors() if a.get_actor_label().startswith("__BM_")]

if probe is None:
    # PHASE 1: スケルトン配置 + Run再生
    for a in eas.get_all_level_actors():
        if a.get_actor_label().startswith("__BM_"):
            eas.destroy_actor(a)
    actor = eas.spawn_actor_from_class(unreal.SkeletalMeshActor, unreal.Vector(0, 0, -120), unreal.Rotator(0, 0, 90))
    actor.set_actor_label("__YBotProbe")
    comp = actor.skeletal_mesh_component
    comp.set_skinned_asset_and_update(sk)
    comp.set_animation_mode(unreal.AnimationMode.ANIMATION_SINGLE_NODE)
    try:
        comp.set_update_animation_in_editor(True)
    except Exception:
        pass
    comp.play_animation(run, True)
    comp.set_play_rate(1.0)
    out["phase"] = "spawned (run again to build boxes)"
else:
    # PHASE 2: 古い箱を破棄して現在の姿勢(Run)からボックス再構築
    for a in boxes:
        eas.destroy_actor(a)
    comp = probe.skeletal_mesh_component
    # 固定フレームにフリーズ（ルートモーションでの移動を止め、原点付近の安定ポーズに）
    comp.set_play_rate(0.0)
    comp.set_position(0.30, False)
    probe.set_actor_location(unreal.Vector(0.0, 0.0, -120.0), False, False)
    built = 0
    for i, (ba, bb, th, ckey) in enumerate(SEG):
        pa = comp.get_socket_location(ba)
        pb = comp.get_socket_location(bb)
        d = pb - pa
        length = max(float(d.length()), 6.0)
        center = (pa + pb) * 0.5
        rot = unreal.MathLibrary.make_rot_from_x(d)
        box = eas.spawn_actor_from_class(unreal.StaticMeshActor, center, rot)
        box.set_actor_label("__BM_%02d" % i)
        smc = box.static_mesh_component
        smc.set_static_mesh(cube)
        box.set_actor_scale3d(unreal.Vector(length / 100.0, th / 100.0, th / 100.0))
        smc.set_material(0, MICS[ckey])
        built += 1
    comp.set_visibility(False)  # 箱だけ見せる
    out["phase"] = "built"
    out["boxes"] = built

    # キャラ中心(胸)を狙うカメラを p3_cam.txt に書き出す（確実なフレーミング）
    import math
    chest = comp.get_socket_location("Spine1")
    cam = unreal.Vector(chest.x - 280.0, chest.y - 240.0, chest.z + 70.0)
    d = chest - cam
    yaw = math.degrees(math.atan2(d.y, d.x))
    pitch = math.degrees(math.atan2(d.z, math.sqrt(d.x * d.x + d.y * d.y)))
    with open("C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/p3_cam.txt", "w") as f:
        f.write("%.1f %.1f %.1f 0 %.1f %.1f p5_bm_ok" % (cam.x, cam.y, cam.z, pitch, yaw))
    out["chest"] = [round(chest.x, 1), round(chest.y, 1), round(chest.z, 1)]

print("RESULT " + json.dumps(out, ensure_ascii=False))

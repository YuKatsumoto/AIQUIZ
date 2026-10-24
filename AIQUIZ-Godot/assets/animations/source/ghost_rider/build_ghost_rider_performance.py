"""GOSTRIDER（ゴーストシャーク）の乗り手の演技を作り、Godot が読む JSON に焼き出す。

ライブの Blender（Higgsfield の接続）で動かす。ヘッドレス起動はしない:
    ns = {}
    exec(open(r"<このファイル>", encoding="utf-8").read(), ns)
    ns["build_authoring_scene"]()   # 複製リグ + サメ（ソケットに乗せる）
    ns["key_all"]()                 # 全部の演技のキー
    ns["export_json"]()             # assets/animations/ghost_rider_performance.json

ゲームの乗り手は scripts/world/player_controller.gd の _build_player_skeleton が組むブロック人形。
ここではその部品の位置・箱の大きさ・親子をそのまま写した骨（RIG_GhostRider）を作る。
骨の軸はゲームの部品の軸にそろえてある（骨の X = ゲームの X、骨の Y = ゲームの Y（上）、骨の Z = ゲームの Z（正面））ので、
ポーズの骨の回転（クォータニオン）がそのままゲームの部品のローカル回転になる。
リグはサメの GhostMountSocket に「ローカル単位行列・大きさ RIDER_SCALE」で子付けする。
ゲームも乗り手をソケットの向きそのまま（向きの補正も持ち上げも無し）で、大きさ RIDER_SCALE × サメのモデルの倍率で乗せる。
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(r"G:\AIQUIZ-Main\AIQUIZ-Godot")
SHARK_BLEND = ROOT / "assets" / "shark" / "source" / "shark_swim_with_jaw.blend"
AUTHORING_BLEND = ROOT / "assets" / "animations" / "source" / "ghost_rider" / "ghost_rider_performance.blend"
EXPORT_JSON = ROOT / "assets" / "animations" / "ghost_rider_performance.json"
PREVIEW_DIR = ROOT / "artifacts" / "ghost_rider_performance"

FPS = 30
## サメのモデルの 1 単位に対する乗り手（ブロック人形）の大きさ。ゲームの GhostSharkRide と同じ値にする。
RIDER_SCALE = 0.70
RIG_NAME = "RIG_GhostRider"
COLLECTION_RIDER = "GR_Rider"
COLLECTION_SHARK = "GR_Shark"

BASE_Y = -1.2

# ---------------------------------------------------------------- ブロック人形（ゲームの値）
# 骨: (名前, 親, ゲームのローカル位置（親の軸）)
BONES: list[tuple[str, str | None, tuple[float, float, float]]] = [
    ("pelvis", None, (0.0, BASE_Y + 0.9, 0.0)),
    ("spine", "pelvis", (0.0, 0.30, 0.0)),
    ("neck", "spine", (0.0, 0.42, 0.0)),
    ("head_pivot", "neck", (0.0, 0.03, 0.0)),
    ("l_shoulder", "spine", (-0.52, 0.35, 0.0)),
    ("l_elbow", "l_shoulder", (0.0, -0.40, 0.0)),
    ("l_wrist", "l_elbow", (0.0, -0.40, 0.0)),
    ("l_fingers", "l_wrist", (0.0, -0.20, 0.0)),
    ("r_shoulder", "spine", (0.52, 0.35, 0.0)),
    ("r_elbow", "r_shoulder", (0.0, -0.40, 0.0)),
    ("r_wrist", "r_elbow", (0.0, -0.40, 0.0)),
    ("r_fingers", "r_wrist", (0.0, -0.20, 0.0)),
    ("l_hip", "pelvis", (-0.22, 0.0, 0.0)),
    ("l_knee", "l_hip", (0.0, -0.45, 0.0)),
    ("l_ankle", "l_knee", (0.0, -0.45, 0.0)),
    ("l_toe", "l_ankle", (0.0, -0.06, 0.22)),
    ("r_hip", "pelvis", (0.22, 0.0, 0.0)),
    ("r_knee", "r_hip", (0.0, -0.45, 0.0)),
    ("r_ankle", "r_knee", (0.0, -0.45, 0.0)),
    ("r_toe", "r_ankle", (0.0, -0.06, 0.22)),
]
## ゲームへ書き出す骨（指は「握り」の値にして書き出す）。
EXPORT_BONES = [name for name, _parent, _pos in BONES if not name.endswith("_fingers")]

# 箱: (骨, ゲームのローカル中心, 大きさ（全幅）, 色の役)
BOXES: list[tuple[str, tuple[float, float, float], tuple[float, float, float], str]] = [
    ("pelvis", (0.0, 0.15, 0.0), (0.75, 0.44, 0.43), "body"),
    ("spine", (0.0, 0.18, 0.0), (0.76, 0.52, 0.44), "body"),
    ("head_pivot", (0.0, 0.22, 0.0), (0.44, 0.44, 0.44), "head"),
    ("l_shoulder", (0.0, -0.20, 0.0), (0.24, 0.52, 0.24), "limb"),
    ("l_elbow", (0.0, -0.20, 0.0), (0.24, 0.52, 0.24), "limb"),
    ("l_wrist", (0.0, -0.10, 0.0), (0.18, 0.20, 0.10), "limb"),
    ("l_fingers", (0.0, -0.085, 0.0), (0.18, 0.17, 0.05), "limb"),
    ("r_shoulder", (0.0, -0.20, 0.0), (0.24, 0.52, 0.24), "limb"),
    ("r_elbow", (0.0, -0.20, 0.0), (0.24, 0.52, 0.24), "limb"),
    ("r_wrist", (0.0, -0.10, 0.0), (0.18, 0.20, 0.10), "limb"),
    ("r_fingers", (0.0, -0.085, 0.0), (0.18, 0.17, 0.05), "limb"),
    ("l_hip", (0.0, -0.225, 0.0), (0.36, 0.57, 0.36), "limb"),
    ("l_knee", (0.0, -0.225, 0.0), (0.32, 0.57, 0.32), "limb"),
    ("l_ankle", (0.0, -0.06, 0.05), (0.28, 0.12, 0.44), "limb"),
    ("l_toe", (0.0, -0.02, 0.04), (0.24, 0.08, 0.16), "limb"),
    ("r_hip", (0.0, -0.225, 0.0), (0.36, 0.57, 0.36), "limb"),
    ("r_knee", (0.0, -0.225, 0.0), (0.32, 0.57, 0.32), "limb"),
    ("r_ankle", (0.0, -0.06, 0.05), (0.28, 0.12, 0.44), "limb"),
    ("r_toe", (0.0, -0.02, 0.04), (0.24, 0.08, 0.16), "limb"),
]
COLORS = {
    "body": (0.95, 0.55, 0.20, 1.0),
    "head": (0.95, 0.65, 0.35, 1.0),
    "limb": (0.85, 0.48, 0.18, 1.0),
}


def godot_to_arm(v: tuple[float, float, float] | Vector) -> Vector:
    """ゲームの乗り手の座標 (x, y上, z正面) → リグのアーマチュアのローカル (x, -z, y)。"""
    return Vector((v[0], -v[2], v[1]))


def _rest_positions() -> dict[str, Vector]:
    positions: dict[str, Vector] = {}
    for name, parent, local in BONES:
        base = positions[parent] if parent else Vector((0.0, 0.0, 0.0))
        positions[name] = base + Vector(local)
    return positions


def _collection(name: str) -> bpy.types.Collection:
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    if collection.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(collection)
    return collection


def _material(role: str) -> bpy.types.Material:
    name = f"M_GR_{role}"
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
        material.use_nodes = True
    color = COLORS[role]
    material.diffuse_color = color
    shader = next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if shader is not None:
        shader.inputs["Base Color"].default_value = color
        shader.inputs["Roughness"].default_value = 0.7
    return material


def _box_mesh(name: str, size: Vector) -> bpy.types.Mesh:
    hx, hy, hz = size.x * 0.5, size.y * 0.5, size.z * 0.5
    verts = [(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh = bpy.data.meshes.get(name) or bpy.data.meshes.new(name)
    mesh.clear_geometry()
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    return mesh


def _view3d_override():
    """操作子（mode_set など）用に、開いている 3D ビューの文脈を貸す。"""
    window = bpy.context.window_manager.windows[0]
    for area in window.screen.areas:
        if area.type == "VIEW_3D":
            region = next(r for r in area.regions if r.type == "WINDOW")
            return bpy.context.temp_override(window=window, area=area, region=region)
    return bpy.context.temp_override(window=window)


def load_shark() -> dict[str, bpy.types.Object]:
    """サメ（鞍・ソケット込み）を追加で読み込む。もう読み込んであれば使い回す。"""
    collection = _collection(COLLECTION_SHARK)
    socket = next((o for o in collection.all_objects if o.name.startswith("GhostMountSocket")), None)
    if socket is not None:
        armature = next(o for o in collection.all_objects if o.type == "ARMATURE")
        return {"socket": socket, "armature": armature}
    with bpy.data.libraries.load(str(SHARK_BLEND), link=False) as (source, target):
        target.objects = [
            name for name in source.objects
            if name == "shark_armature" or name.startswith("SK_Shark")
            or name.startswith("SharkSaddle_") or name.startswith("GhostMountSocket")
        ]
        target.actions = list(source.actions)
    imported = [o for o in target.objects if o is not None]
    for obj in imported:
        collection.objects.link(obj)
        obj["ghost_rider_authoring_shark"] = True
    bpy.context.view_layer.update()
    socket = next(o for o in imported if o.name.startswith("GhostMountSocket"))
    armature = next(o for o in imported if o.type == "ARMATURE")
    return {"socket": socket, "armature": armature}


def build_rig(socket: bpy.types.Object) -> bpy.types.Object:
    """ブロック人形の複製リグを作り直す（同じ名前の古いものは消す）。"""
    collection = _collection(COLLECTION_RIDER)
    for obj in list(collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    old = bpy.data.armatures.get(RIG_NAME)
    if old is not None:
        bpy.data.armatures.remove(old)

    data = bpy.data.armatures.new(RIG_NAME)
    rig = bpy.data.objects.new(RIG_NAME, data)
    collection.objects.link(rig)
    rig.parent = socket
    rig.matrix_parent_inverse = Matrix.Identity(4)
    rig.location = (0.0, 0.0, 0.0)
    rig.rotation_mode = "QUATERNION"
    rig.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    rig.scale = (RIDER_SCALE, RIDER_SCALE, RIDER_SCALE)
    data.display_type = "STICK"
    rig.show_in_front = True

    positions = _rest_positions()
    view_layer = bpy.context.view_layer
    for obj in view_layer.objects:
        obj.select_set(False)
    view_layer.objects.active = rig
    rig.select_set(True)
    with _view3d_override():
        bpy.ops.object.mode_set(mode="EDIT")
        edit_bones = data.edit_bones
        for name, parent, _local in BONES:
            bone = edit_bones.new(name)
            head = godot_to_arm(positions[name])
            bone.head = head
            bone.tail = head + Vector((0.0, 0.0, 0.12))
            bone.roll = 0.0
            if parent:
                bone.parent = edit_bones[parent]
                bone.use_connect = False
        bpy.ops.object.mode_set(mode="OBJECT")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
    rig["grip_l"] = 0.0
    rig["grip_r"] = 0.0

    for bone_name, center, size, role in BOXES:
        mesh = _box_mesh(f"GR_{bone_name}_{role}_mesh", godot_to_arm_size(size))
        if not mesh.materials:
            mesh.materials.append(_material(role))
        obj = bpy.data.objects.new(f"GR_{bone_name}_box", mesh)
        collection.objects.link(obj)
        obj.parent = rig
        obj.parent_type = "BONE"
        obj.parent_bone = bone_name
        # 骨の子は骨の先（tail）が原点で、軸は骨の軸（= ゲームの軸 X、Y上、Z正面）。頭（ピボット）からの位置に直す。
        bone = data.bones[bone_name]
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.location = Vector(center) - Vector((0.0, bone.length, 0.0))
        obj.rotation_euler = (0.0, 0.0, 0.0)
    return rig


def godot_to_arm_size(size: tuple[float, float, float]) -> Vector:
    """箱の大きさは骨の軸（= ゲームの軸）で作るので、そのまま。"""
    return Vector(size)


# ---------------------------------------------------------------- ポーズ
# ポーズは {骨: (X, Y, Z) 度（ゲームの軸。Blender の XYZ 順 = Rz·Ry·Rx）, "pelvis_loc": (x, y, z)（乗り手の単位）}。
# ゲームの軸での向き：正面 +Z（サメの頭）、上 +Y、+X は乗り手の左手側（l_ の骨は −X 側＝乗り手の右手側）。
#   股関節・肩：X が負で手足が前へ。膝：X が正で脛が後ろへ。背骨・首・頭：X が正で前へかがむ。
#   l_ の股関節・肩の Z が負で外へ開く（r_ は正で外）。Y は鉛直軸回りのひねり。


def pose_quaternion(degrees: tuple[float, float, float]) -> Quaternion:
    return Euler(tuple(math.radians(v) for v in degrees), "XYZ").to_quaternion()


def apply_pose(rig: bpy.types.Object, pose: dict) -> None:
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_quaternion = pose_quaternion(pose.get(pose_bone.name, (0.0, 0.0, 0.0)))
        pose_bone.location = Vector(pose.get("pelvis_loc", (0.0, 0.0, 0.0))) if pose_bone.name == "pelvis" else Vector()
    rig["grip_l"] = float(pose.get("grip_l", 0.0))
    rig["grip_r"] = float(pose.get("grip_r", 0.0))
    _apply_finger_curl(rig)
    bpy.context.view_layer.update()


def _apply_finger_curl(rig: bpy.types.Object) -> None:
    """握り（0 = 開く、1 = 拳）を指の骨の曲げで見せる（ゲームは指の関節に分けて曲げる）。"""
    for side in ("l", "r"):
        grip = float(rig.get(f"grip_{side}", 0.0))
        rig.pose.bones[f"{side}_fingers"].rotation_quaternion = pose_quaternion((-85.0 * grip, 0.0, 0.0))


def bone_world(rig: bpy.types.Object, bone: str, local: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> Vector:
    """骨のピボット（頭）から、骨の軸（= ゲームの軸）で local だけ離れた点のワールド座標。"""
    pose_bone = rig.pose.bones[bone]
    return rig.matrix_world @ (pose_bone.matrix @ Vector(local))


LIMBS = {
    # 名前: (上の骨, 下の骨, 下の骨から先端までの長さ（乗り手の単位）, 曲げる向き)
    # 腕は前腕が骨の +Z（正面）側へ、脚は脛が骨の −Z（後ろ）側へ曲がる。
    "l_arm": ("l_shoulder", "l_elbow", 0.40 + 0.16, 1.0),
    "r_arm": ("r_shoulder", "r_elbow", 0.40 + 0.16, 1.0),
    "l_leg": ("l_hip", "l_knee", 0.45, -1.0),
    "r_leg": ("r_hip", "r_knee", 0.45, -1.0),
}


def _set_bone_armature_rotation(rig: bpy.types.Object, bone_name: str, axes: Matrix) -> None:
    """骨の向きを、アーマチュアの空間での軸（列 = 骨の X, Y, Z）で決める。"""
    # pose = 親のpose · 親のrest⁻¹ · rest · basis（回転だけ）。
    pose_bone = rig.pose.bones[bone_name]
    rest = pose_bone.bone.matrix_local.to_3x3().normalized()
    if pose_bone.parent is not None:
        parent_pose = pose_bone.parent.matrix.to_3x3().normalized()
        parent_rest = pose_bone.parent.bone.matrix_local.to_3x3().normalized()
        frame = parent_pose @ parent_rest.inverted() @ rest
    else:
        frame = rest
    pose_bone.rotation_quaternion = (frame.inverted() @ axes).to_quaternion()
    bpy.context.view_layer.update()


def solve_limb(
    rig: bpy.types.Object,
    limb: str,
    target_world: Vector,
    pole_world: Vector,
    end_twist: float = 0.0,
) -> float:
    """2 関節の IK。先端（手のひら・足首）を target_world へ、肘・膝を pole_world の向きへ出す。
    戻り値は届かなかった距離（届けば 0）。"""
    upper, lower, end_length, bend_sign = LIMBS[limb]
    to_arm = rig.matrix_world.inverted()
    scale = rig.matrix_world.to_scale().x
    start = rig.pose.bones[upper].head.copy()
    target = to_arm @ Vector(target_world)
    pole_dir = (to_arm.to_3x3() @ Vector(pole_world)).normalized()
    upper_length = 0.40 if "arm" in limb else 0.45
    lower_length = end_length
    span = target - start
    distance = span.length
    miss = max(0.0, distance - (upper_length + lower_length) * 0.999)
    distance = min(distance, (upper_length + lower_length) * 0.999)
    distance = max(distance, abs(upper_length - lower_length) * 1.001)
    direction = span.normalized()
    along = (upper_length ** 2 - lower_length ** 2 + distance ** 2) / (2.0 * distance)
    height = math.sqrt(max(0.0, upper_length ** 2 - along ** 2))
    side = (pole_dir - direction * pole_dir.dot(direction)).normalized()
    joint = start + direction * along + side * height
    end = start + direction * distance
    upper_dir = (joint - start).normalized()
    lower_dir = (end - joint).normalized()
    # 上の骨：骨の −Y が肘・膝へ。骨の Z は（前腕・脛の、上腕・腿に垂直な成分）× 曲げる向き。
    y_axis = -upper_dir
    perp = lower_dir - upper_dir * lower_dir.dot(upper_dir)
    if perp.length < 1e-5:
        perp = side
    z_axis = perp.normalized() * bend_sign
    x_axis = y_axis.cross(z_axis).normalized()
    z_axis = x_axis.cross(y_axis).normalized()
    _set_bone_armature_rotation(rig, upper, Matrix((x_axis, y_axis, z_axis)).transposed())
    # 下の骨：上の骨の X 回りに曲げる（腕は −、脚は +）。先端のひねりは Y 回り。
    bend = math.acos(max(-1.0, min(1.0, upper_dir.dot(lower_dir))))
    rig.pose.bones[lower].rotation_quaternion = (
        Quaternion((1.0, 0.0, 0.0), -bend * bend_sign)
        @ Quaternion((0.0, 1.0, 0.0), math.radians(end_twist))
    )
    bpy.context.view_layer.update()
    return miss * scale


def contact_report(rig: bpy.types.Object) -> dict:
    """手のひら・足の裏・お尻と、鞍の部品との距離（サメのモデルの単位）。"""
    report: dict = {}
    for side in ("l", "r"):
        # 乗り手の l_ は −X（サメの右舷 −Y）側。サメの部品は舷で _L（+Y）/_R（−Y）。
        shark_side = "R" if side == "l" else "L"
        palm = bone_world(rig, f"{side}_wrist", (0.0, -0.16, 0.0))
        sole = bone_world(rig, f"{side}_ankle", (0.0, -0.12, 0.05))
        for key, point, part in (("palm", palm, "Grip"), ("sole", sole, "Footrest")):
            obj = bpy.data.objects.get(f"SharkSaddle_{part}_{shark_side}")
            if obj is not None:
                center = obj.matrix_world @ (sum((Vector(c) for c in obj.bound_box), Vector()) / 8.0)
                report[f"{key}_{side}_to_{part.lower()}"] = [round(v, 3) for v in (point - center)]
        report[f"palm_{side}"] = [round(v, 3) for v in palm]
        report[f"sole_{side}"] = [round(v, 3) for v in sole]
        report[f"knee_{side}"] = [round(v, 3) for v in bone_world(rig, f"{side}_knee")]
    report["butt"] = [round(v, 3) for v in bone_world(rig, "pelvis", (0.0, -0.07, 0.0))]
    report["shoulder_l"] = [round(v, 3) for v in bone_world(rig, "l_shoulder")]
    report["head_top"] = [round(v, 3) for v in bone_world(rig, "head_pivot", (0.0, 0.44, 0.0))]
    return report


def setup_review() -> bpy.types.Object:
    """確認用のカメラ・ライト・背景（作業ファイルだけ。ゲームへは出さない）。"""
    scene = bpy.context.scene
    collection = _collection("GR_Review")
    camera = bpy.data.objects.get("CAM_Review")
    if camera is None:
        camera = bpy.data.objects.new("CAM_Review", bpy.data.cameras.new("CAM_Review"))
        collection.objects.link(camera)
    scene.camera = camera
    for name, kind, energy, color, rotation in (
        ("LGT_Sun", "SUN", 3.2, (1.0, 0.96, 0.9), (math.radians(48), 0.0, math.radians(-35))),
        ("LGT_Rim", "SUN", 2.0, (0.55, 0.8, 1.0), (math.radians(-60), 0.0, math.radians(150))),
    ):
        light = bpy.data.objects.get(name)
        if light is None:
            light = bpy.data.objects.new(name, bpy.data.lights.new(name, kind))
            collection.objects.link(light)
        light.data.energy = energy
        light.data.color = color
        light.rotation_euler = rotation
    if scene.world is None:
        scene.world = bpy.data.worlds.new("GR_World")
    scene.world.use_nodes = True
    background = next((n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if background is not None:
        background.inputs[0].default_value = (0.42, 0.62, 0.78, 1.0)
        background.inputs[1].default_value = 0.9
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    return camera


def render_review(path: str, target: tuple[float, float, float], eye: tuple[float, float, float], lens: float = 40.0) -> str:
    camera = setup_review()
    camera.location = eye
    camera.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = lens
    camera.data.sensor_fit = "VERTICAL"
    camera.data.sensor_height = 24.0
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def set_view(target: tuple[float, float, float], eye: tuple[float, float, float], lens: float = 50.0) -> None:
    """3D ビューを eye から target を見る向きにする（確認用。データは変えない）。"""
    target_v = Vector(target)
    direction = target_v - Vector(eye)
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type != "VIEW_3D":
                continue
            space = area.spaces.active
            space.lens = lens
            region_3d = space.region_3d
            region_3d.view_location = target_v
            region_3d.view_distance = direction.length
            region_3d.view_rotation = direction.to_track_quat("-Z", "Y")
            region_3d.view_perspective = "PERSP"
            space.shading.type = "MATERIAL"
            space.overlay.show_extras = False


def build_authoring_scene() -> dict:
    scene = bpy.context.scene
    scene.render.fps = FPS
    shark = load_shark()
    rig = build_rig(shark["socket"])
    bpy.context.view_layer.update()
    # 検算：骨の軸がゲームの軸（X、Y上、Z正面）とそろっているか。
    bone = rig.data.bones["pelvis"]
    axes = bone.matrix_local.to_3x3()
    return {
        "rig": rig.name,
        "socket": shark["socket"].name,
        "pelvis_bone_x": [round(v, 4) for v in axes.col[0]],
        "pelvis_bone_y": [round(v, 4) for v in axes.col[1]],
        "pelvis_bone_z": [round(v, 4) for v in axes.col[2]],
    }


# ================================================================ 演技
# ゲームの GhostSharkRideController の _sequence_elapsed（秒）での区切り。ゲームはフェーズごとに
# 「区切りの時刻 + そのフェーズに入ってからの秒」でこのクリップを読む（待ちでフェーズが延びてもずれない）。
PHASES = {
    "DEATH_HOLD": 0.0,
    "SOUL_RISE": 0.55,
    "SOUL_FLIGHT": 1.40,
    "MOUNTING": 4.05,
    "BEAM_REVEAL": 4.90,
    "ENTERING": 8.49,
    "END": 10.94,
}


def frame_at(seconds: float) -> float:
    return 1.0 + seconds * FPS


# --- 姿勢の部品（度。ゲームの軸。上の「ポーズ」の説明を参照）
RIDE_TORSO = {"pelvis_loc": (0.0, 0.28, 0.0), "pelvis": (10, 0, 0), "spine": (22, 0, 0), "neck": (-10, 0, 0), "head_pivot": (-16, 0, 0)}
GRIPS_CLOSED = {"grip_l": 1.0, "grip_r": 1.0}

CURL = {
    "pelvis_loc": (0.0, 0.36, 0.0), "pelvis": (20, 0, 0), "spine": (50, 0, 0), "neck": (25, 0, 0), "head_pivot": (22, 0, 0),
    "l_shoulder": (-48, 0, 14), "r_shoulder": (-48, 0, -14), "l_elbow": (-118, 0, 0), "r_elbow": (-118, 0, 0),
    "l_hip": (-108, 0, -6), "r_hip": (-108, 0, 6), "l_knee": (138, 0, 0), "r_knee": (138, 0, 0),
    "l_ankle": (22, 0, 0), "r_ankle": (22, 0, 0), "grip_l": 0.7, "grip_r": 0.7,
}
CURL_BREATH = {**CURL, "spine": (46, 0, 0), "head_pivot": (18, 0, 0), "pelvis_loc": (0.0, 0.38, 0.0)}
LIMP = {
    "pelvis_loc": (0.0, 0.26, 0.0), "pelvis": (8, 0, 0), "spine": (24, 0, 2), "neck": (30, 0, 0), "head_pivot": (26, 0, -4),
    "l_shoulder": (10, 0, -9), "r_shoulder": (6, 0, 7), "l_elbow": (-14, 0, 0), "r_elbow": (-18, 0, 0),
    "l_hip": (-6, 0, -4), "r_hip": (-12, 0, 5), "l_knee": (16, 0, 0), "r_knee": (24, 0, 0),
    "l_ankle": (42, 0, 0), "r_ankle": (38, 0, 0), "grip_l": 0.25, "grip_r": 0.25,
}
LIMP_DRIFT = {
    **LIMP, "spine": (20, 0, -2), "head_pivot": (30, 0, 4), "l_shoulder": (18, 0, -12), "r_shoulder": (16, 0, 11),
    "l_knee": (26, 0, 0), "r_knee": (14, 0, 0), "pelvis_loc": (0.0, 0.24, 0.0),
}
GATHER = {
    "pelvis_loc": (0.0, 0.30, 0.0), "pelvis": (14, 0, 0), "spine": (40, 0, 0), "neck": (34, 0, 0), "head_pivot": (24, 0, 0),
    "l_shoulder": (-34, 0, 26), "r_shoulder": (-34, 0, -26), "l_elbow": (-78, 0, 0), "r_elbow": (-78, 0, 0),
    "l_hip": (-44, 0, -4), "r_hip": (-44, 0, 4), "l_knee": (66, 0, 0), "r_knee": (66, 0, 0),
    "l_ankle": (30, 0, 0), "r_ankle": (30, 0, 0), "grip_l": 1.0, "grip_r": 1.0,
}
AWAKEN = {
    "pelvis_loc": (0.0, 0.30, 0.0), "pelvis": (-6, 0, 0), "spine": (-20, 0, 0), "neck": (-16, 0, 0), "head_pivot": (-22, 0, 0),
    "l_shoulder": (-28, 0, -128), "r_shoulder": (-28, 0, 128), "l_elbow": (-8, 0, 0), "r_elbow": (-8, 0, 0),
    "l_hip": (-10, 0, -20), "r_hip": (-10, 0, 20), "l_knee": (22, 0, 0), "r_knee": (22, 0, 0),
    "l_ankle": (34, 0, 0), "r_ankle": (34, 0, 0), "grip_l": 0.0, "grip_r": 0.0,
}
AWAKEN_SETTLE = {
    **AWAKEN, "spine": (-14, 0, 0), "head_pivot": (-16, 0, 0), "l_shoulder": (-24, 0, -118), "r_shoulder": (-24, 0, 118),
    "l_elbow": (-16, 0, 0), "r_elbow": (-16, 0, 0),
}
POINT = {
    "pelvis_loc": (0.0, 0.28, 0.0), "pelvis": (26, 0, 0), "spine": (6, 8, 0), "neck": (-12, 0, 0), "head_pivot": (-12, -6, 0),
    "r_shoulder": (-150, 0, 6), "r_elbow": (-6, 0, 0), "l_shoulder": (12, 0, -30), "l_elbow": (-42, 0, 0),
    "l_hip": (-32, 0, -10), "r_hip": (6, 0, 6), "l_knee": (72, 0, 0), "r_knee": (22, 0, 0),
    "l_ankle": (30, 0, 0), "r_ankle": (36, 0, 0), "grip_l": 0.6, "grip_r": 1.0,
}
LAUNCH = {
    "pelvis_loc": (0.0, 0.28, 0.0), "pelvis": (46, 0, 0), "spine": (20, 0, 0), "neck": (-30, 0, 0), "head_pivot": (-20, 0, 0),
    "r_shoulder": (-160, 0, 4), "r_elbow": (-34, 0, 0), "l_shoulder": (26, 0, -20), "l_elbow": (-34, 0, 0),
    "l_hip": (-48, 0, -6), "r_hip": (-44, 0, 6), "l_knee": (104, 0, 0), "r_knee": (98, 0, 0),
    "l_ankle": (24, 0, 0), "r_ankle": (24, 0, 0), "grip_l": 0.8, "grip_r": 1.0,
}
SUPERHERO = {
    "pelvis_loc": (0.0, 0.28, 0.0), "pelvis": (76, 0, 0), "spine": (4, 0, 0), "neck": (-38, 0, 0), "head_pivot": (-30, 0, 0),
    "r_shoulder": (-176, 0, 4), "r_elbow": (-2, 0, 0), "l_shoulder": (14, 0, -10), "l_elbow": (-18, 0, 0),
    "l_hip": (8, 0, -3), "r_hip": (12, 0, 3), "l_knee": (18, 0, 0), "r_knee": (26, 0, 0),
    "l_ankle": (46, 0, 0), "r_ankle": (44, 0, 0), "grip_l": 0.6, "grip_r": 1.0,
}
SUPERHERO_A = {**SUPERHERO, "pelvis": (73, 0, 0), "r_shoulder": (-172, 0, 2), "l_knee": (32, 0, 0), "r_knee": (12, 0, 0), "neck": (-36, 0, 0)}
SUPERHERO_B = {**SUPERHERO, "pelvis": (79, 0, 0), "r_shoulder": (-178, 0, 6), "l_knee": (14, 0, 0), "r_knee": (30, 0, 0), "neck": (-40, 0, 0)}
LANDING_PREP = {
    "pelvis_loc": (0.0, 0.34, 0.0), "pelvis": (40, 0, 0), "spine": (14, 0, 0), "neck": (-24, 0, 0), "head_pivot": (-14, 0, 0),
    "l_shoulder": (-96, 0, -14), "r_shoulder": (-96, 0, 14), "l_elbow": (-24, 0, 0), "r_elbow": (-24, 0, 0),
    "l_hip": (-36, 0, -22), "r_hip": (-36, 0, 22), "l_knee": (72, 0, 0), "r_knee": (72, 0, 0),
    "l_ankle": (20, 0, 0), "r_ankle": (20, 0, 0), "grip_l": 0.3, "grip_r": 0.3,
}
STRADDLE = {
    "pelvis_loc": (0.0, 0.42, 0.0), "pelvis": (12, 0, 0), "spine": (18, 0, 0), "neck": (-8, 0, 0), "head_pivot": (-14, 0, 0),
    "l_shoulder": (-74, 0, -24), "r_shoulder": (-74, 0, 24), "l_elbow": (-34, 0, 0), "r_elbow": (-34, 0, 0),
    "l_hip": (-80, -30, -36), "r_hip": (-80, 30, 36), "l_knee": (76, 0, 0), "r_knee": (76, 0, 0),
    "l_ankle": (8, 0, 0), "r_ankle": (8, 0, 0), "grip_l": 0.4, "grip_r": 0.4,
}
DROP = {**STRADDLE, "pelvis_loc": (0.0, 0.33, 0.0), "spine": (22, 0, 0), "head_pivot": (-12, 0, 0), "grip_l": 0.7, "grip_r": 0.7}
IMPACT = {"pelvis_loc": (0.0, 0.25, 0.02), "pelvis": (16, 0, 0), "spine": (38, 0, 0), "neck": (12, 0, 0), "head_pivot": (14, 0, 0), **GRIPS_CLOSED}
SQUASH = {"pelvis_loc": (0.0, 0.215, 0.03), "pelvis": (20, 0, 0), "spine": (47, 0, 0), "neck": (18, 0, 0), "head_pivot": (18, 0, 0), **GRIPS_CLOSED}
REBOUND = {"pelvis_loc": (0.0, 0.31, 0.0), "pelvis": (6, 0, 0), "spine": (13, 0, 0), "neck": (-12, 0, 0), "head_pivot": (-14, 0, 0), **GRIPS_CLOSED}
SETTLE = {"pelvis_loc": (0.0, 0.27, 0.0), "pelvis": (12, 0, 0), "spine": (26, 0, 0), "neck": (-7, 0, 0), "head_pivot": (-15, 0, 0), **GRIPS_CLOSED}
RIDE = {**RIDE_TORSO, **GRIPS_CLOSED}
BRACE = {"pelvis_loc": (0.0, 0.25, 0.03), "pelvis": (16, 0, 0), "spine": (34, 0, 0), "neck": (2, 0, 0), "head_pivot": (4, 0, 0), **GRIPS_CLOSED}
ERUPT = {
    "pelvis_loc": (0.0, 0.34, -0.01), "pelvis": (2, 0, 0), "spine": (-6, -8, 0), "neck": (-22, 0, 0), "head_pivot": (-22, 8, 0),
    "r_shoulder": (-166, 0, 10), "r_elbow": (-6, 0, 0), **GRIPS_CLOSED,
}
ERUPT_SETTLE = {**ERUPT, "pelvis_loc": (0.0, 0.33, -0.01), "spine": (-3, -6, 0), "head_pivot": (-18, 6, 0), "r_shoulder": (-162, 0, 8)}
ERUPT_HOLD_A = {**ERUPT_SETTLE, "spine": (-4, -7, 0), "head_pivot": (-20, 5, 0), "r_shoulder": (-165, 0, 9)}
ERUPT_HOLD_B = {**ERUPT_SETTLE, "spine": (-2, -5, 0), "head_pivot": (-17, 7, 0), "r_shoulder": (-160, 0, 7)}
LOWER_ARM = {
    "pelvis_loc": (0.0, 0.33, 0.0), "pelvis": (4, 0, 0), "spine": (2, 0, 0), "neck": (-8, 0, 0), "head_pivot": (-10, 0, 0),
    "r_shoulder": (-118, 0, 16), "r_elbow": (-42, 0, 0), **GRIPS_CLOSED,
}
READY = {"pelvis_loc": (0.0, 0.28, 0.0), "pelvis": (12, 0, 0), "spine": (27, 0, 0), "neck": (-10, 0, 0), "head_pivot": (-16, 0, 0), **GRIPS_CLOSED}
REAR_BRACE = {"pelvis_loc": (0.0, 0.26, 0.03), "pelvis": (14, 0, 0), "spine": (38, 0, 0), "neck": (-20, 0, 0), "head_pivot": (-20, 0, 0), **GRIPS_CLOSED}
VERTICAL = {"pelvis_loc": (0.0, 0.25, 0.04), "pelvis": (16, 0, 0), "spine": (44, 0, 0), "neck": (-28, 0, 0), "head_pivot": (-18, 0, 0), **GRIPS_CLOSED}
ASCENT_END = {"pelvis_loc": (0.0, 0.26, 0.03), "pelvis": (14, 0, 0), "spine": (40, 0, 0), "neck": (-24, 0, 0), "head_pivot": (-16, 0, 0), **GRIPS_CLOSED}
LEVEL_OUT = {"pelvis_loc": (0.0, 0.27, 0.01), "pelvis": (12, 0, 0), "spine": (30, 0, 0), "neck": (-14, 0, 0), "head_pivot": (-14, 0, 0), **GRIPS_CLOSED}
CRUISE_A = {"pelvis_loc": (0.0, 0.28, 0.0), "pelvis": (11, 0, 0), "spine": (26, 0, 2), "neck": (-12, 0, 0), "head_pivot": (-16, 4, 0), **GRIPS_CLOSED}
CRUISE_B = {"pelvis_loc": (0.0, 0.28, 0.0), "pelvis": (10, 0, 0), "spine": (21, 0, -1), "neck": (-9, 0, 0), "head_pivot": (-17, -2, 0), **GRIPS_CLOSED}

# 演技のキー: (秒, ポーズ)。乗っている間の手足は IK（LOCKS）が上書きする。
PERFORMANCE_KEYS: list[tuple[float, dict]] = [
    (0.00, CURL),
    (0.30, CURL_BREATH),
    (0.55, CURL),               # SOUL_RISE：ほどけながら上がる
    (0.86, LIMP),
    (1.06, LIMP_DRIFT),
    (1.17, GATHER),             # ためる
    (1.27, AWAKEN),             # 目覚め（ゲームは同じ時刻に光の輪を出す）
    (1.40, AWAKEN_SETTLE),      # SOUL_FLIGHT
    (1.63, POINT),              # サメを指して向き直る
    (1.84, LAUNCH),             # 蹴り出し
    (2.08, SUPERHERO),          # 飛ぶ
    (2.57, SUPERHERO_A),
    (3.03, SUPERHERO_B),
    (3.30, SUPERHERO),
    (3.48, LANDING_PREP),       # 起き上がる
    (3.80, STRADDLE),           # 脚を開いて落ちる
    (4.00, DROP),
    (4.07, IMPACT),             # MOUNTING：着座（4.05）
    (4.17, SQUASH),
    (4.33, REBOUND),
    (4.53, SETTLE),
    (4.90, RIDE),               # BEAM_REVEAL
    (5.00, BRACE),
    (5.13, ERUPT),              # 柱が立つ（5.10）：右の拳を突き上げる
    (5.30, ERUPT_SETTLE),
    (5.65, ERUPT_HOLD_A),
    (6.00, ERUPT_HOLD_B),
    (6.35, ERUPT_HOLD_A),
    (6.55, LOWER_ARM),
    (6.80, READY),
    (7.05, REAR_BRACE),         # 縦になる（7.09〜7.57）
    (7.57, VERTICAL),
    (8.49, ASCENT_END),         # ENTERING
    (8.95, LEVEL_OUT),
    (9.60, CRUISE_A),
    (10.30, CRUISE_B),
    (10.94, RIDE),
]
# IK の重み: 手足 → [(秒, 重み)]（直線でつなぎ、なめらかにする）。
PERFORMANCE_LOCKS: dict[str, list[tuple[float, float]]] = {
    "l_arm": [(0.0, 0.0), (3.92, 0.0), (4.07, 1.0)],
    "r_arm": [(0.0, 0.0), (3.92, 0.0), (4.07, 1.0), (5.04, 1.0), (5.12, 0.0), (6.62, 0.0), (6.80, 1.0)],
    "l_leg": [(0.0, 0.0), (3.97, 0.0), (4.09, 1.0)],
    "r_leg": [(0.0, 0.0), (3.97, 0.0), (4.09, 1.0)],
}
RIDING_LOCKS = {limb: [(0.0, 1.0)] for limb in LIMBS}

# 乗っているときの短いクリップ（照準・構え・突進）。
IDLE_KEYS = [
    (0.00, RIDE),
    (0.55, {**RIDE, "spine": (24, 0, 1), "pelvis_loc": (0.0, 0.29, 0.0), "head_pivot": (-17, 7, 0)}),
    (1.10, {**RIDE, "spine": (21, 0, 0), "pelvis_loc": (0.0, 0.275, 0.0), "head_pivot": (-14, 1, 0)}),
    (1.65, {**RIDE, "spine": (24, 0, -1), "pelvis_loc": (0.0, 0.29, 0.0), "head_pivot": (-17, -6, 0)}),
    (2.20, RIDE),
]
WINDUP_KEYS = [
    (0.00, RIDE),
    (0.16, {"pelvis_loc": (0.0, 0.24, -0.06), "pelvis": (18, 0, 0), "spine": (36, 0, 0), "neck": (-22, 0, 0), "head_pivot": (-12, 0, 0), **GRIPS_CLOSED}),
    (0.34, {"pelvis_loc": (0.0, 0.23, -0.07), "pelvis": (20, 0, 0), "spine": (40, 0, 0), "neck": (-26, 0, 0), "head_pivot": (-12, 0, 0), **GRIPS_CLOSED}),
]
DASH_KEYS = [
    (0.00, {"pelvis_loc": (0.0, 0.29, 0.05), "pelvis": (16, 0, 0), "spine": (52, 0, 0), "neck": (-32, 0, 0), "head_pivot": (-22, 0, 0), **GRIPS_CLOSED}),
]

CLIPS = {
    # 名前: (キー, IK の重み, 終わりの秒)
    "performance": (PERFORMANCE_KEYS, PERFORMANCE_LOCKS, PHASES["END"]),
    "idle": (IDLE_KEYS, RIDING_LOCKS, 2.20),
    "windup": (WINDUP_KEYS, RIDING_LOCKS, 0.34),
    "dash": (DASH_KEYS, RIDING_LOCKS, 0.0),
}

LIMB_EXTRA_BONES = {"l_leg": "l_ankle", "r_leg": "r_ankle"}


def _lock_weight(points: list[tuple[float, float]], seconds: float) -> float:
    if seconds <= points[0][0]:
        return points[0][1]
    for (t0, w0), (t1, w1) in zip(points, points[1:]):
        if seconds <= t1:
            u = 0.0 if t1 <= t0 else (seconds - t0) / (t1 - t0)
            u = u * u * (3.0 - 2.0 * u)
            return w0 + (w1 - w0) * u
    return points[-1][1]


def _part_center(name: str) -> Vector:
    obj = bpy.data.objects[name]
    return obj.matrix_world @ (sum((Vector(c) for c in obj.bound_box), Vector()) / 8.0)


def _part_top(name: str) -> Vector:
    obj = bpy.data.objects[name]
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    center = sum(corners, Vector()) / 8.0
    return Vector((center.x, center.y, max(c.z for c in corners)))


def limb_targets(rig: bpy.types.Object) -> dict:
    """乗っているときの手足の行き先（ワールド）。サメの部品から毎回読む。"""
    socket = bpy.data.objects["GhostMountSocket"].matrix_world.to_3x3().normalized()
    up = (socket @ Vector((0.0, 0.0, 1.0))).normalized()
    forward = (socket @ Vector((0.0, -1.0, 0.0))).normalized()   # ソケットの -Y = サメの頭
    scale = RIDER_SCALE
    targets: dict = {}
    for side, shark_side, sign in (("l", "R", -1.0), ("r", "L", 1.0)):
        lateral = (socket @ Vector((1.0, 0.0, 0.0))).normalized() * sign   # ソケットの +X = サメの左舷
        targets[f"{side}_arm"] = {
            "target": _part_center(f"SharkSaddle_Grip_{shark_side}"),
            "pole": (-forward * 0.6 + lateral * 0.55 - up * 0.8).normalized(),
        }
        plate = _part_top(f"SharkSaddle_Footrest_{shark_side}") - lateral * 0.03
        toe = (forward + lateral * 0.22).normalized()
        targets[f"{side}_leg"] = {
            "target": plate + up * (0.12 * scale) - toe * (0.05 * scale),
            "pole": (forward * 1.0 + lateral * 0.35 + up * 0.1).normalized(),
            "foot_up": up,
            "foot_toe": toe,
        }
    return targets


def _solve_foot(rig: bpy.types.Object, limb: str, info: dict) -> None:
    ankle = LIMB_EXTRA_BONES[limb]
    to_arm = rig.matrix_world.inverted().to_3x3()
    y_axis = (to_arm @ info["foot_up"]).normalized()
    z_axis = (to_arm @ info["foot_toe"]).normalized()
    z_axis = (z_axis - y_axis * z_axis.dot(y_axis)).normalized()
    x_axis = y_axis.cross(z_axis).normalized()
    _set_bone_armature_rotation(rig, ankle, Matrix((x_axis, y_axis, z_axis)).transposed())


def _continuous(previous: Quaternion | None, value: Quaternion) -> Quaternion:
    if previous is not None and previous.dot(value) < 0.0:
        return Quaternion((-value.w, -value.x, -value.y, -value.z))
    return value


def key_clip(rig: bpy.types.Object, name: str) -> bpy.types.Action:
    keys, locks, end_seconds = CLIPS[name]
    action_name = f"GR_{name}"
    old = bpy.data.actions.get(action_name)
    if old is not None:
        bpy.data.actions.remove(old)
    rig.animation_data_create()
    action = bpy.data.actions.new(action_name)
    action.use_fake_user = True
    rig.animation_data.action = action
    scene = bpy.context.scene

    # 1) 形のキー（FK）。前のキーと同じ側のクォータニオンにそろえる。
    previous: dict[str, Quaternion] = {}
    for seconds, pose in keys:
        frame = frame_at(seconds)
        apply_pose(rig, pose)
        for pose_bone in rig.pose.bones:
            q = _continuous(previous.get(pose_bone.name), pose_bone.rotation_quaternion.copy())
            pose_bone.rotation_quaternion = q
            previous[pose_bone.name] = q
            pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=pose_bone.name)
        rig.pose.bones["pelvis"].keyframe_insert("location", frame=frame, group="pelvis")
        rig.keyframe_insert('["grip_l"]', frame=frame)
        rig.keyframe_insert('["grip_r"]', frame=frame)
    _set_interpolation(action)

    # 2) 乗っている手足を、毎フレーム IK で鞍に合わせて焼く（先に全部計算してから入れる）。
    last_frame = int(math.floor(frame_at(end_seconds) + 1e-6))
    baked: dict[str, list[tuple[int, Quaternion]]] = {}
    limb_bones = {
        limb: [LIMBS[limb][0], LIMBS[limb][1]] + ([LIMB_EXTRA_BONES[limb]] if limb in LIMB_EXTRA_BONES else [])
        for limb in LIMBS
    }
    for frame in range(1, last_frame + 1):
        scene.frame_set(frame)
        seconds = (frame - 1) / FPS
        weights = {limb: _lock_weight(points, seconds) for limb, points in locks.items()}
        if all(w <= 0.0 for w in weights.values()):
            continue
        targets = limb_targets(rig)
        fk = {bone: rig.pose.bones[bone].rotation_quaternion.copy() for bones in limb_bones.values() for bone in bones}
        for limb, weight in weights.items():
            if weight <= 0.0:
                continue
            info = targets[limb]
            solve_limb(rig, limb, info["target"], info["pole"])
            if limb in LIMB_EXTRA_BONES:
                _solve_foot(rig, limb, info)
            for bone in limb_bones[limb]:
                ik = rig.pose.bones[bone].rotation_quaternion.copy()
                ik = _continuous(fk[bone], ik)
                blended = fk[bone].slerp(ik, weight) if weight < 1.0 else ik
                baked.setdefault(bone, []).append((frame, blended))
            for bone in limb_bones[limb]:
                rig.pose.bones[bone].rotation_quaternion = fk[bone]
            bpy.context.view_layer.update()
    for bone, samples in baked.items():
        pose_bone = rig.pose.bones[bone]
        prior = None
        for frame, q in samples:
            q = _continuous(prior, q)
            prior = q
            pose_bone.rotation_quaternion = q
            pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone)
    _set_interpolation(action)
    scene.frame_start = 1
    scene.frame_end = max(1, last_frame)
    return action


def _fcurves(action: bpy.types.Action) -> list:
    curves = []
    if hasattr(action, "fcurves"):
        curves.extend(action.fcurves)
    else:
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    try:
                        bag = strip.channelbag(slot)
                    except Exception:
                        bag = None
                    if bag is not None:
                        curves.extend(bag.fcurves)
    return curves


def _set_interpolation(action: bpy.types.Action) -> None:
    for curve in _fcurves(action):
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"
            point.handle_left_type = "AUTO_CLAMPED"
            point.handle_right_type = "AUTO_CLAMPED"
        curve.update()


def key_all() -> dict:
    rig = bpy.data.objects[RIG_NAME]
    made = {}
    for name in CLIPS:
        action = key_clip(rig, name)
        made[name] = action.name
    rig.animation_data.action = bpy.data.actions["GR_performance"]
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = int(frame_at(PHASES["END"]))
    return made


def export_json() -> dict:
    rig = bpy.data.objects[RIG_NAME]
    scene = bpy.context.scene
    clips: dict = {}
    for name, (_keys, _locks, end_seconds) in CLIPS.items():
        rig.animation_data.action = bpy.data.actions[f"GR_{name}"]
        last_frame = max(1, int(math.floor(frame_at(end_seconds) + 1e-6)))
        rotations: list = []
        pelvis: list = []
        grips: list = []
        for frame in range(1, last_frame + 1):
            scene.frame_set(frame)
            row = []
            for bone in EXPORT_BONES:
                q = rig.pose.bones[bone].rotation_quaternion.normalized()
                row.append([round(q.x, 5), round(q.y, 5), round(q.z, 5), round(q.w, 5)])
            rotations.append(row)
            loc = rig.pose.bones["pelvis"].location
            pelvis.append([round(loc.x, 5), round(loc.y, 5), round(loc.z, 5)])
            grips.append([round(float(rig.get("grip_l", 0.0)), 4), round(float(rig.get("grip_r", 0.0)), 4)])
        clips[name] = {"frames": last_frame, "rotations": rotations, "pelvis": pelvis, "grips": grips}
    rig.animation_data.action = bpy.data.actions["GR_performance"]
    data = {
        "fps": FPS,
        "rider_scale": RIDER_SCALE,
        "bones": EXPORT_BONES,
        "phases": PHASES,
        "clips": clips,
        "source": "assets/animations/source/ghost_rider/build_ghost_rider_performance.py",
    }
    EXPORT_JSON.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    return {"path": str(EXPORT_JSON), "bytes": EXPORT_JSON.stat().st_size, "frames": {k: v["frames"] for k, v in clips.items()}}

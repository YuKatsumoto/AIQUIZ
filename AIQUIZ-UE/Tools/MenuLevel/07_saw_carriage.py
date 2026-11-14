"""のこぎりの台車 (Godot の linked_saw_carriage.glb) を取り込んで走路の手前に置く。何度実行してもよい。

GLB の刃・スライダー・車輪の位置は、スキンの関節 (Spin_01 など) が持っている。UE のシーン取り込みは
関節をスケルトンに回すので、その下の部品が原点に重なってしまう。GLB を読んで関節の位置を足し戻す。
"""
import json
import math
import re
import struct

import unreal

SRC = r"G:/AIQUIZ-Main/AIQUIZ-UE/SourceAssets/Menu/linked_saw_carriage.glb"
DEST = "/Game/Menu/SawCarriage"
ROOT_LABEL = "SawCarriage_Root"
SPINNER_LABEL = "SawSpinner"
# Godot：床の上面 y = -1.2、台車は手前の端の近く (z ≒ 4.3)。UE = (x, z, y) * 100
LOCATION = unreal.Vector(0.0, 430.0, -120.0)
BLADE_DEGREES_PER_SECOND = 420.0
BLADE_METALLIC = 0.35

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)


# ---------- GLB の静止姿勢 ----------
def quat_to_mat(q):
    x, y, z, w = q
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]


def local_matrix(n):
    if "matrix" in n:
        m = n["matrix"]
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = n.get("translation", [0, 0, 0])
    r = quat_to_mat(n.get("rotation", [0, 0, 0, 1]))
    s = n.get("scale", [1, 1, 1])
    return [[r[i][0] * s[0], r[i][1] * s[1], r[i][2] * s[2], t[i]] for i in range(3)] + [[0, 0, 0, 1]]


def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def decompose(m):
    t = [m[0][3], m[1][3], m[2][3]]
    s = [math.sqrt(sum(m[i][c] ** 2 for i in range(3))) for c in range(3)]
    r = [[m[i][c] / (s[c] or 1.0) for c in range(3)] for i in range(3)]
    tr = r[0][0] + r[1][1] + r[2][2]
    if tr > 0:
        k = math.sqrt(tr + 1.0) * 2
        q = [(r[2][1] - r[1][2]) / k, (r[0][2] - r[2][0]) / k, (r[1][0] - r[0][1]) / k, 0.25 * k]
    elif r[0][0] > r[1][1] and r[0][0] > r[2][2]:
        k = math.sqrt(1.0 + r[0][0] - r[1][1] - r[2][2]) * 2
        q = [0.25 * k, (r[0][1] + r[1][0]) / k, (r[0][2] + r[2][0]) / k, (r[2][1] - r[1][2]) / k]
    elif r[1][1] > r[2][2]:
        k = math.sqrt(1.0 + r[1][1] - r[0][0] - r[2][2]) * 2
        q = [(r[0][1] + r[1][0]) / k, 0.25 * k, (r[1][2] + r[2][1]) / k, (r[0][2] - r[2][0]) / k]
    else:
        k = math.sqrt(1.0 + r[2][2] - r[0][0] - r[1][1]) * 2
        q = [(r[0][2] + r[2][0]) / k, (r[1][2] + r[2][1]) / k, 0.25 * k, (r[1][0] - r[0][1]) / k]
    return t, q, s


def norm_name(s):
    return re.sub(r"[^A-Za-z0-9]", "_", s or "")


with open(SRC, "rb") as f:
    f.read(12)
    length, _ = struct.unpack("<I4s", f.read(8))
    gltf = json.loads(f.read(length))
nodes = gltf["nodes"]
parent = {}
for i, n in enumerate(nodes):
    for c in n.get("children", []):
        parent[c] = i


def world_matrix(i):
    m = local_matrix(nodes[i])
    while i in parent:
        i = parent[i]
        m = mul(local_matrix(nodes[i]), m)
    return m


rest = {norm_name(n.get("name")): world_matrix(i) for i, n in enumerate(nodes)}


# ---------- 取り込み ----------
def descendants(actor):
    out = []
    for k in actor.get_attached_actors():
        out.append(k)
        out.extend(descendants(k))
    return out


for a in list(eas.get_all_level_actors()):
    lab = a.get_actor_label()
    if lab == ROOT_LABEL:
        for k in descendants(a):
            eas.destroy_actor(k)
        eas.destroy_actor(a)
    elif lab == SPINNER_LABEL or (lab.startswith("Saw_") and a.get_folder_path() == "Menu/Runway"):
        eas.destroy_actor(a)

before = set(a.get_path_name() for a in eas.get_all_level_actors())
im = unreal.InterchangeManager.get_interchange_manager_scripted()
params = unreal.ImportAssetParameters()
params.is_automated = True
params.replace_existing = True
ok = im.import_scene(DEST, unreal.InterchangeManager.create_source_data(SRC), params)
new = [a for a in eas.get_all_level_actors() if a.get_path_name() not in before]
root = [a for a in new if a.get_attach_parent_actor() is None][0]
print("import_scene:", ok, "new actors:", len(new), "root:", root.get_actor_label())

# 格納の動き用のスキンメッシュは使わない (静止姿勢の部品と重なる)
for a in new:
    if isinstance(a, unreal.SkeletalMeshActor):
        eas.destroy_actor(a)

# ---------- 関節の位置を足し戻す ----------
rig = root.get_attached_actors()[0]
fixed, missing, rotors = 0, [], []
for k in rig.get_attached_actors():
    m = rest.get(norm_name(k.get_actor_label()))
    if m is None:
        missing.append(k.get_actor_label())
        continue
    t, q, s = decompose(m)
    rc = k.root_component
    # glTF (Y 上、右手) → UE (Z 上、左手)：Y と Z を入れ替える
    rc.set_editor_property("relative_location", unreal.Vector(t[0] * 100.0, t[2] * 100.0, t[1] * 100.0))
    rc.set_editor_property("relative_rotation", unreal.Quat(-q[0], -q[2], -q[1], q[3]).rotator())
    rc.set_editor_property("relative_scale3d", unreal.Vector(s[0], s[2], s[1]))
    fixed += 1
    if k.get_actor_label().startswith("Rotor_"):
        rotors.append(k)
print("placed:", fixed, "missing:", missing)

root.set_actor_label(ROOT_LABEL)
root.set_actor_location(LOCATION, False, False)
for k in [root] + descendants(root):
    k.set_folder_path("Menu/Runway/SawCarriage")

# ---------- 刃を回す ----------
rotors.sort(key=lambda a: a.get_actor_label())
for r in rotors:
    for k in [r] + descendants(r):
        k.root_component.set_mobility(unreal.ComponentMobility.MOVABLE)
spinner = eas.spawn_actor_from_class(unreal.TestopiaSpinner, LOCATION, unreal.Rotator(0, 0, 0))
spinner.set_actor_label(SPINNER_LABEL)
spinner.set_folder_path("Menu/Runway/SawCarriage")
spinner.set_editor_property("targets", rotors)
spinner.set_editor_property("degrees_per_second", BLADE_DEGREES_PER_SECOND)
print("rotors:", [(r.get_actor_label(), round(r.get_actor_location().x)) for r in rotors])

# ---------- 材質の調整 ----------
# 刃は金属のままだと暗い空を映して黒っぽく沈む。Godot 版の白い刃の見え方に寄せて、金属を弱める
eal = unreal.EditorAssetLibrary
mel = unreal.MaterialEditingLibrary
for name, metallic in (("01___circular_ground_satin_steel", BLADE_METALLIC), ("03___tungsten_carbide_tips", 0.5), ("02___machined_edge_steel", 0.6)):
    path = DEST + "/linked_saw_carriage/Materials/" + name
    if eal.does_asset_exist(path):
        mi = unreal.load_asset(path)
        mel.set_material_instance_scalar_parameter_value(mi, "MetallicFactor", metallic)
        mel.update_material_instance(mi)
        eal.save_loaded_asset(mi)
    else:
        print("material not found:", path)

les.save_current_level()
# 取り込んだメッシュ・材質・テクスチャも保存する (しないとエディタを閉じるときに失われる)
unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)

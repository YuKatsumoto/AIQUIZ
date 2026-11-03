"""t8（絵コンテ docs/pv/thumbnail/gen_v2/a_shoulder.png：肩から扉を突き破って飛び出す）を Blender で仕上げる。

build_scene.py の build("t8") で組んだファイルに、開いている Blender の中で、build_scene と同じ名前空間で重ねて動かす:

    ns = {}
    exec(open(r"<ROOT>\\docs\\pv\\thumbnail\\blender\\build_scene.py", encoding="utf-8").read(), ns)
    ns["build"]("t8")                                   # 初回だけ（t8_thumbnail.blend を新しく作る）
    exec(open(r"<ROOT>\\docs\\pv\\thumbnail\\blender\\t8_art.py", encoding="utf-8").read(), ns)
    ns["setup"]()                                       # 骨組み・破片・土ぼこり・カメラのぼけ・view layer（何度呼んでもよい）

値は docs/pv/thumbnail/t8/blender_art.json（ポーズ・破片・土ぼこり・ぼけ）。書き換えて setup() を呼び直すと当て直す。
組むもの:
  - RIG_P1_<関節>：書き出しの関節（scene.json の joints。PlayerController の parts のノード）の空の物体。部位はいちばん近い
    関節の子にする。pose の値で関節を回す（毎回、書き出しの姿に戻してから回す）
  - DEBRIS：扉の破片。画面の位置（u・v）とカメラからの距離で置く箱と、扉の穴の縁の割れ残り（壁の中心・床からの位置）。
    扉の穴から外へ飛ぶ速さでモーションブラー
  - DUST：扉の穴と足もとの土ぼこり（角ばった low-poly の煙。build_scene の make_dust と同じ作り）
  - GHOST：ゴーストライダー（幽霊になった P2 が乗ったサメ）。P1 の左上から頭をめがけて襲う（絵コンテ gen_v3/a_chase.png）
  - カメラのぼけ（ピントは P1）と、全部をいっしょに描く view layer VL_t8（2 人目と文字の板は外す）
"""
import json
import math
import os
import random

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

T8_SHOT = "t8"
T8_ART = os.path.join(ROOT, "docs", "pv", "thumbnail", "t8", "blender_art.json")
DOOR_BLUE = (0.10, 0.60, 0.95)            # quiz_wall.gd の DOOR_COLORS_2[0]（sRGB）
# pose の aim で向ける部分：関節 → 部分の先の関節
SEGMENT_TIP = {"spine": "neck", "neck": "head_pivot", "head_pivot": "hat_mount",
               "l_shoulder": "l_elbow", "l_elbow": "l_wrist", "l_wrist": "l_hand",
               "r_shoulder": "r_elbow", "r_elbow": "r_wrist", "r_wrist": "r_hand",
               "l_hip": "l_knee", "l_knee": "l_ankle", "l_ankle": "l_toe",
               "r_hip": "r_knee", "r_knee": "r_ankle", "r_ankle": "r_toe"}
FLOOR_Z = -1.2                            # Godot の床の高さ −1.2（Blender の z）


def _J():
    return json.load(open(os.path.join(find_export(T8_SHOT), "scene.json"), encoding="utf-8"))


def _art():
    return json.load(open(T8_ART, encoding="utf-8"))


def _anchor(J):
    """壁の中心・床（Godot の (0, −1.2, wall_z)）"""
    return Vector((0.0, -J["state"]["wall_z"], FLOOR_Z))


def _g_rel(J, p):
    """壁の中心・床からの Godot の (x, 床からの高さ, z) → Blender の位置"""
    return g2b((p[0], FLOOR_Z + p[1], J["state"]["wall_z"] + p[2]))


# ------------------------------------------------------------------ 骨組みとポーズ

def rig(group="P1"):
    """書き出しの関節を空の物体にして、部位をいちばん近い関節の子にする（2 回目からは何もしない）"""
    J = _J()
    joints = J["joints"][group]
    rows = [e for e in J["meshes"] if e["group"] == group]
    mesh_paths = {e["path"] for e in rows}
    names = [n for n, j in joints.items() if j["path"] not in mesh_paths]
    if bpy.data.objects.get("RIG_%s_pelvis" % group):
        return {"joints": len(names), "made": False}
    c = coll(group)
    made = {}
    for n in names:
        e = bpy.data.objects.new("RIG_%s_%s" % (group, n), None)
        e.empty_display_type = 'PLAIN_AXES'
        e.empty_display_size = 0.08
        c.objects.link(e)
        e.matrix_world = g2b_matrix(joints[n]["xform"])
        made[n] = e
    bpy.context.view_layer.update()
    for n, e in made.items():
        p = joints[n]["parent"]
        while p and p not in made:
            p = joints.get(p, {}).get("parent", "")
        if p:
            e.parent = made[p]
            e.matrix_parent_inverse = made[p].matrix_world.inverted()
    by_path = sorted(((joints[n]["path"], n) for n in made), key=lambda t: -len(t[0]))
    parented = 0
    for r in rows:
        ob = bpy.data.objects.get(r["name"])
        if ob is None:
            continue
        owner = next((n for path, n in by_path if r["path"].startswith(path + "/")), None)
        if owner is None:
            continue
        ob.parent = made[owner]
        ob.matrix_parent_inverse = made[owner].matrix_world.inverted()
        parented += 1
    bpy.context.view_layer.update()
    for e in made.values():
        e["rest_basis"] = [v for row in e.matrix_basis for v in row]
    return {"joints": len(made), "parented": parented, "meshes": len(rows), "made": True}


def _rig_objects(group):
    return [o for o in bpy.data.objects if o.name.startswith("RIG_%s_" % group)]


def _depth(o):
    d = 0
    while o.parent is not None:
        d += 1
        o = o.parent
    return d


def pose(spec, group="P1"):
    """書き出しの姿に戻してから、spec の順に回す。
    spec = {"turn": 度（床の上の腰を軸に、上から見て左回り）, "lean": 度（前へ傾ける）, "move": [x, y, z]（m、Blender）,
            "rot": [[関節, "R"|"F"|"U", 度], ...]}。R・F・U は体の右・前（走る向き）・上（turn のあと）。
    R まわりの + は、垂れた手足を前へ振り、上へ伸びる胴や首をうしろへ起こす。U まわりの + は上から見て左回り"""
    rigs = _rig_objects(group)
    for e in rigs:
        rb = e.get("rest_basis")
        if rb is not None:
            e.matrix_basis = Matrix([rb[0:4], rb[4:8], rb[8:12], rb[12:16]])
    bpy.context.view_layer.update()
    pelvis = bpy.data.objects["RIG_%s_pelvis" % group]
    turn = math.radians(spec.get("turn", 0.0))
    fwd = Matrix.Rotation(turn, 3, 'Z') @ Vector((0.0, -1.0, 0.0))        # Godot の +z（走る向き）
    up = Vector((0.0, 0.0, 1.0))
    right = fwd.cross(up)
    p = pelvis.matrix_world.translation.copy()
    pivot = Vector((p.x, p.y, FLOOR_Z))
    root = (Matrix.Translation(pivot) @ Matrix.Rotation(-math.radians(spec.get("lean", 0.0)), 4, right)
            @ Matrix.Rotation(turn, 4, 'Z') @ Matrix.Translation(-pivot))
    pelvis.matrix_world = Matrix.Translation(Vector(spec.get("move", (0, 0, 0)))) @ root @ pelvis.matrix_world
    axes = {"R": right, "F": fwd, "U": up}
    # aim：部分（関節 → 次の関節）を、体の右・前・上で書いた向きへ向ける（いちばん小さい回転で）。親から順に並べる。
    # twist があれば、向けたあとその部分の軸まわりに回す（度）
    for item in spec.get("aim", []):
        name, want = item[0], item[1]
        twist = item[2] if len(item) > 2 else 0.0
        bpy.context.view_layer.update()
        e = bpy.data.objects.get("RIG_%s_%s" % (group, name))
        tip = bpy.data.objects.get("RIG_%s_%s" % (group, SEGMENT_TIP.get(name, "")))
        if e is None or tip is None:
            continue
        q = e.matrix_world.translation.copy()
        have = (tip.matrix_world.translation - q).normalized()
        if want == "cam":                   # カメラそのものへ（手前へ突き出す腕を、正面から見た形にする）
            target = (bpy.context.scene.camera.matrix_world.translation - q).normalized()
        else:
            target = (right * want[0] + fwd * want[1] + up * want[2]).normalized()
        rot = have.rotation_difference(target).to_matrix().to_4x4()
        if twist:
            rot = Matrix.Rotation(math.radians(twist), 4, target) @ rot
        e.matrix_world = Matrix.Translation(q) @ rot @ Matrix.Translation(-q) @ e.matrix_world
    for side in spec.get("fists", []):
        fist(group, side, spec.get("fist_deg", (75.0, 85.0, 65.0)))
    for name, axis, deg in spec.get("rot", []):
        bpy.context.view_layer.update()
        e = bpy.data.objects.get("RIG_%s_%s" % (group, name))
        if e is None:
            continue
        q = e.matrix_world.translation.copy()
        e.matrix_world = (Matrix.Translation(q) @ Matrix.Rotation(math.radians(deg), 4, axes[axis])
                          @ Matrix.Translation(-q)) @ e.matrix_world
    bpy.context.view_layer.update()
    # 足が床にめり込まないように（浮くのはよい。突進で片足は宙にある）。ground があれば、いちばん低い所を床に合わせる
    # （脚を深く曲げて腰が浮いたときに、体ごと床まで下ろす）
    low = min(min((o.matrix_world @ v.co).z for v in o.data.vertices)
              for o in coll(group).objects if o.type == 'MESH' and o.parent is not None and o.name.startswith(group + "_"))
    lift = (FLOOR_Z - low) if spec.get("ground") else max(0.0, FLOOR_Z - low)
    if lift != 0:
        pelvis.matrix_world = Matrix.Translation((0.0, 0.0, lift)) @ pelvis.matrix_world
        bpy.context.view_layer.update()
    bpy.context.scene["t8_pose"] = json.dumps(spec)
    return {"lift": round(lift, 3), "pelvis": [round(v, 3) for v in pelvis.matrix_world.translation]}


def fist(group, side, degs):
    """side（"l" か "r"）の手を握る：人差し指〜小指の付け根・中・先を、付け根の並び（人差し指 → 小指）の軸まわりに、
    手のひら側（親指のある側）へ degs 度ずつ曲げる。親指は人差し指の付け根のほうへ寄せる"""
    def obj(n):
        return bpy.data.objects.get("RIG_%s_%s_%s" % (group, side, n))
    bpy.context.view_layer.update()
    hand, thumb = obj("hand"), obj("thumb_prox")
    knuckle = (obj("index_prox").matrix_world.translation - obj("pinky_prox").matrix_world.translation).normalized()
    finger = (obj("middle_prox").matrix_world.translation - hand.matrix_world.translation).normalized()
    n = knuckle.cross(finger).normalized()
    sign = 1.0 if (thumb.matrix_world.translation - hand.matrix_world.translation).dot(n) >= 0 else -1.0
    for f in ("index", "middle", "ring", "pinky"):
        for part, deg in zip(("prox", "mid", "dist"), degs):
            bpy.context.view_layer.update()
            e = obj("%s_%s" % (f, part))
            q = e.matrix_world.translation.copy()
            e.matrix_world = (Matrix.Translation(q) @ Matrix.Rotation(sign * math.radians(deg), 4, knuckle)
                              @ Matrix.Translation(-q)) @ e.matrix_world
    bpy.context.view_layer.update()
    q = thumb.matrix_world.translation.copy()
    tip = obj("thumb_dist").matrix_world.translation
    want = (obj("index_mid").matrix_world.translation - q).normalized()
    rot = (tip - q).normalized().rotation_difference(want).to_matrix().to_4x4()
    thumb.matrix_world = Matrix.Translation(q) @ rot @ Matrix.Translation(-q) @ thumb.matrix_world


# ------------------------------------------------------------------ 骨（手でポーズを変える）

def joint_pos(name, group="P1"):
    """関節の世界の位置（骨にしたあとは骨の根もと、その前は空の物体）"""
    arm = bpy.data.objects.get("ARM_%s" % group)
    if arm is not None and name in arm.pose.bones:
        return arm.matrix_world @ arm.pose.bones[name].head
    return bpy.data.objects["RIG_%s_%s" % (group, name)].matrix_world.translation.copy()


def _bone_tip(name, rest, rigs):
    """骨の先：部分の先の関節（SEGMENT_TIP）か、指・手・つま先・帽子はそれらしい向きに少し伸ばす"""
    head = rest[name].translation
    tip_name = SEGMENT_TIP.get(name)
    if name == "pelvis":
        tip_name = "spine"
    elif name.endswith("_hand"):
        tip_name = name[:2] + "middle_prox"
    elif name.endswith("_prox") or name.endswith("_mid"):
        tip_name = name.replace("_prox", "_mid") if name.endswith("_prox") else name.replace("_mid", "_dist")
    if tip_name and tip_name in rest and (rest[tip_name].translation - head).length > 0.02:
        return rest[tip_name].translation.copy()
    parent = rigs[name].parent
    if parent is not None:
        d = head - parent.matrix_world.translation
        if d.length > 0.02:
            return head + d.normalized() * (0.04 if "_" in name and name.split("_")[1] in ("thumb", "index", "middle", "ring", "pinky") else 0.1)
    return head + Vector((0.0, 0.0, 0.1))


def armature(group="P1"):
    """関節の空の物体（RIG_P1_*）を、Blender のふつうのアーマチュア ARM_P1 の骨に置き換える（いまのポーズのまま）。
    骨の休みの姿（エディットモード）は書き出しの姿なので、ポーズモードで骨を選んで R で回し、Alt+R で書き出しの姿に戻せる。
    部位は骨の子（骨の親子）にし、空の物体は消す。2 回目からは何もしない"""
    if bpy.data.objects.get("ARM_%s" % group):
        return {"made": False}
    rigs = {o.name[len("RIG_%s_" % group):]: o for o in _rig_objects(group)}
    bpy.context.view_layer.update()
    posed = {n: e.matrix_world.copy() for n, e in rigs.items()}
    for e in rigs.values():
        rb = e.get("rest_basis")
        e.matrix_basis = Matrix([rb[0:4], rb[4:8], rb[8:12], rb[12:16]])
    bpy.context.view_layer.update()
    rest = {n: e.matrix_world.copy() for n, e in rigs.items()}
    kids = {n: [c for c in e.children if c.type == 'MESH'] for n, e in rigs.items()}
    data = bpy.data.armatures.new("ARM_%s" % group)
    data.display_type = 'OCTAHEDRAL'
    arm = bpy.data.objects.new("ARM_%s" % group, data)
    arm.show_in_front = True
    coll(group).objects.link(arm)
    view = bpy.context.view_layer
    for o in view.objects:
        o.select_set(False)
    view.objects.active = arm
    arm.select_set(True)
    win = bpy.context.window_manager.windows[0]
    area = next((a for a in win.screen.areas if a.type == 'VIEW_3D'), None)
    with bpy.context.temp_override(window=win, area=area, active_object=arm, object=arm):
        bpy.ops.object.mode_set(mode='EDIT')
        for n in rigs:
            b = data.edit_bones.new(n)
            b.head = rest[n].translation
            b.tail = _bone_tip(n, rest, rigs)
        for n, e in rigs.items():
            p = e.parent
            if p is not None and p.name.startswith("RIG_%s_" % group):
                data.edit_bones[n].parent = data.edit_bones[p.name[len("RIG_%s_" % group):]]
        bpy.ops.object.mode_set(mode='OBJECT')
    view.update()
    # 部位を骨の子に（書き出しの姿のまま）
    moved = 0
    for n, obs in kids.items():
        for ob in obs:
            w = ob.matrix_world.copy()
            ob.parent = arm
            ob.parent_type = 'BONE'
            ob.parent_bone = n
            ob.matrix_parent_inverse = Matrix.Identity(4)
            view.update()
            ob.matrix_world = w
            moved += 1
    # いまのポーズを骨へ：骨の姿 = 空の物体の（ポーズ ÷ 書き出しの姿）× 骨の休みの姿。親から順に
    for n in sorted(rigs, key=lambda k: _depth(rigs[k])):
        pb = arm.pose.bones[n]
        p_rest = arm.matrix_world @ pb.bone.matrix_local
        pb.matrix = arm.matrix_world.inverted() @ posed[n] @ rest[n].inverted() @ p_rest
        view.update()
    for e in rigs.values():
        bpy.data.objects.remove(e)
    for ob in coll(group).objects:
        if ob.type == 'MESH':
            ob.hide_select = True          # クリックで骨を選びやすく（部位は選べないようにする）
    return {"made": True, "bones": len(rigs), "meshes": moved}


def save_pose(group="P1"):
    """いまの骨の姿（書き出しの姿からの、骨ごとの位置・回転・大きさ）を blender_art.json の bone_pose に書く。
    組み直したとき（setup）は、aim などのあとにこれを当てる（手で変えた姿がそのまま戻る）"""
    arm = bpy.data.objects["ARM_%s" % group]
    out = {pb.name: [round(v, 6) for row in pb.matrix_basis for v in row] for pb in arm.pose.bones}
    art = _art()
    art["bone_pose"] = out
    with open(T8_ART, "w", encoding="utf-8") as f:
        json.dump(art, f, ensure_ascii=False, indent=1)
    bpy.context.scene["t8_pose_saved"] = True
    return {"bones": len(out), "file": T8_ART}


def apply_bone_pose(art, group="P1"):
    arm = bpy.data.objects.get("ARM_%s" % group)
    bp = art.get("bone_pose")
    if arm is None or not bp:
        return {"applied": 0}
    n = 0
    for name, m in bp.items():
        pb = arm.pose.bones.get(name)
        if pb is not None:
            pb.matrix_basis = Matrix([m[0:4], m[4:8], m[8:12], m[12:16]])
            n += 1
    bpy.context.view_layer.update()
    return {"applied": n}


FINGERS = ("thumb", "index", "middle", "ring", "pinky")


def hide_fingers(art, group="P1"):
    """art["hide_fingers"] の側（"l" は体の右＝画面の左に構えた手、"r" は体の左）の指の部位を描かない（手のひらの箱だけのこぶしにする）"""
    sides = set(art.get("hide_fingers", []))
    n = 0
    for ob in coll(group).objects:
        if ob.type != 'MESH' or ob.parent_type != 'BONE':
            continue
        b = ob.parent_bone
        finger = b[:2] in ("l_", "r_") and b[2:].split("_")[0] in FINGERS
        if finger:
            hide = b[0] in sides
            ob.hide_render = ob.hide_viewport = hide
            n += hide
    return {"hidden": n, "sides": sorted(sides)}


def side_names(group="P1"):
    """l_・r_ のどちらが体の右か（書き出しの姿で、肩が体の右（R）側にあるほう）"""
    pel = bpy.data.objects["RIG_%s_pelvis" % group].matrix_world.translation
    right = Vector((0.0, -1.0, 0.0)).cross(Vector((0.0, 0.0, 1.0)))
    ls = bpy.data.objects["RIG_%s_l_shoulder" % group].matrix_world.translation
    return {"l_is": "right" if (ls - pel).dot(right) > 0 else "left"}


# ------------------------------------------------------------------ 破片

def _blue_material(i):
    name = "MAT_t8_debris_%d" % (i % 5)
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    nt, out = fresh_tree(mat)
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tint = 0.03 + 0.04 * (i % 5)                    # ゲームの破片と同じく、扉の色を少しずつ白へ
    rgb = tuple(c + (1.0 - c) * tint for c in DOOR_BLUE)
    p.inputs["Base Color"].default_value = lin3(rgb) + (1.0,)
    p.inputs["Roughness"].default_value = 0.45
    p.inputs["Specular IOR Level"].default_value = 0.5
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.inputs["Radius"].default_value = 0.015
    bev.samples = 8
    nt.links.new(bev.outputs["Normal"], p.inputs["Normal"])
    nt.links.new(p.outputs[0], out.inputs["Surface"])
    mat["thumb_role"] = "t8 door debris (DOOR_COLORS_2 blue)"
    return mat


def _box(name, size, mat, c):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    c.objects.link(ob)
    mod = ob.modifiers.new("BEVEL", 'BEVEL')         # 角を少し丸く（形の大きさは変えない。物体の大きさは 1 のまま）
    mod.width = min(size) * 0.08
    mod.segments = 2
    mod.limit_method = 'ANGLE'
    return ob


def _clear(name):
    c = coll(name)
    for o in list(c.objects):
        me = o.data if o.type == 'MESH' else None
        bpy.data.objects.remove(o)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)
    return c


def _cam_point(cam, u, v, d):
    """画面の位置 (u, v)（左上が 0）とカメラからの距離 d（m、視線の向きの奥行き）→ 世界の位置"""
    data = cam.data
    sx, sy = bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y
    ty = math.tan(data.angle_y / 2.0)
    tx = ty * sx / sy
    local = Vector(((u - 0.5) * 2.0 * tx * d, (0.5 - v) * 2.0 * ty * d, -d))
    return cam.matrix_world @ local


def debris(art):
    """art["debris"]：画面の位置で置く箱。art["remains"]：扉の穴の縁の割れ残り。どちらも扉の穴の真ん中（art["burst"]、
    壁の中心・床からの Godot の位置）から外へ飛ぶ速さで、MOTION_FRAME の 1 フレーム前からの動きをキーにする（モーションブラー）"""
    J = _J()
    cam = bpy.context.scene.camera
    c = _clear("DEBRIS")
    burst = _g_rel(J, art["burst"])
    rng = random.Random(art.get("seed", 8))
    tau = art.get("blur_s", 0.03)
    made = 0
    pieces = [("s", d) for d in art.get("debris", [])] + [("w", d) for d in art.get("remains", [])]
    for i, (kind, d) in enumerate(pieces):
        if kind == "s":
            u, v, dist, sx, sy, sz, rx, ry, rz = d[:9]
            pos = _cam_point(cam, u, v, dist)
            speed = d[9] if len(d) > 9 else 8.0
        else:
            x, y, z, sx, sy, sz, rx, ry, rz = d[:9]
            pos = _g_rel(J, (x, y, z))
            speed = d[9] if len(d) > 9 else 0.0
        ob = _box("DEB_%03d" % i, (sx, sy, sz), _blue_material(i), c)
        ob.rotation_mode = 'XYZ'
        if kind == "s":
            # 画面で置く箱の回転はカメラから見た向き（0 なら正面をカメラへ。x：上の面をカメラへ倒す、y：横へ振る、z：画面の中で回す）
            from mathutils import Euler
            m = cam.matrix_world.to_3x3().normalized() @ Euler((math.radians(rx), math.radians(ry), math.radians(rz))).to_matrix()
            rot = Vector(m.to_euler('XYZ'))
        else:
            rot = Vector((math.radians(rx), math.radians(ry), math.radians(rz)))
        out = (pos - burst)
        out = out.normalized() if out.length > 1e-6 else Vector((0, 0, 1))
        vel = out * speed
        spin = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * (art.get("spin", 6.0) if speed > 0 else 0.0)
        for frame, t in ((MOTION_FRAME - 1, -tau), (MOTION_FRAME, 0.0)):
            ob.location = pos + vel * t
            ob.rotation_euler = rot + spin * t
            ob.keyframe_insert("location", frame=frame)
            ob.keyframe_insert("rotation_euler", frame=frame)
        if ob.animation_data and ob.animation_data.action:
            for fc in _fcurves(ob.animation_data):
                for kp in fc.keyframe_points:
                    kp.interpolation = 'LINEAR'
        ob["t8_piece"] = kind
        made += 1
    bpy.context.scene.frame_set(MOTION_FRAME)
    return {"pieces": made, "burst": [round(v, 2) for v in burst]}


# ------------------------------------------------------------------ 土ぼこり

def _dust_mat():
    mat = bpy.data.materials.get("MAT_t8_dust")
    if mat is not None:
        return mat
    mat = bpy.data.materials.new("MAT_t8_dust")
    nt, out = fresh_tree(mat)
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.inputs["Base Color"].default_value = lin3((0.93, 0.92, 0.90)) + (1.0,)
    p.inputs["Roughness"].default_value = 1.0
    p.inputs["Specular IOR Level"].default_value = 0.1
    p.inputs["Alpha"].default_value = 0.55              # 粉の煙：少し透ける（重なると濃くなる）
    nt.links.new(p.outputs[0], out.inputs["Surface"])
    mat["thumb_role"] = "t8 dust puff (soft, semi-transparent)"
    return mat


def dust(art):
    """art["dust"] = [[x, 床からの高さ, z, 広がり, 数, 大きさ], ...]（壁の中心・床からの Godot の位置。煙のかたまりの真ん中）"""
    J = _J()
    c = _clear("DUST")
    mat = _dust_mat()
    rng = random.Random(art.get("seed", 8) + 1)
    made = 0
    for k, (x, y, z, spread, count, size) in enumerate(art.get("dust", [])):
        center = _g_rel(J, (x, y, z))
        for i in range(int(count)):
            r = size * rng.uniform(0.45, 1.0)
            off = Vector((rng.gauss(0, spread), rng.gauss(0, spread), abs(rng.gauss(0, spread * 0.6))))
            name = "DUST_t8_%d_%02d" % (k, i)
            me = bpy.data.meshes.new(name)
            bm = bmesh.new()
            bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
            for v in bm.verts:
                v.co *= rng.uniform(0.86, 1.1)
            bm.to_mesh(me)
            bm.free()
            for poly in me.polygons:
                poly.use_smooth = True
            me.materials.append(mat)
            ob = bpy.data.objects.new(name, me)
            c.objects.link(ob)
            pos = center + off
            pos.z = max(pos.z, FLOOR_Z + r * 0.5)
            ob.location = pos
            ob.rotation_euler = (rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0, 6.28))
            ob.scale = (rng.uniform(0.9, 1.25), rng.uniform(0.9, 1.25), rng.uniform(0.75, 1.0))
            made += 1
    return {"puffs": made}


# ------------------------------------------------------------------ ゴーストライダー（P2 の幽霊が乗ったサメ）

# 乗り手の演技を作った作業ファイル（サメ・鞍・GhostMountSocket・乗り手の複製リグ RIG_GhostRider が、鞍に乗った形で入っている）
GHOST_PERF_BLEND = os.path.join(ROOT, "assets", "animations", "source", "ghost_rider", "ghost_rider_performance.blend")
SHARK_SRC_BLEND = os.path.join(ROOT, "assets", "shark", "source", "shark_swim_with_jaw.blend")
SHARK_SNOUT_X, SHARK_TAIL_X = 4.57, -4.09  # サメのモデルの鼻先と尾の x（+X が前、+Z が背）


def _ghost_objects():
    c = coll("GHOST")
    arm = next(o for o in c.objects if o.type == 'ARMATURE' and o.name.startswith("shark_armature"))
    rig = next(o for o in c.objects if o.type == 'ARMATURE' and o.name.startswith("RIG_GhostRider"))
    return c, arm, rig


def _ghost_rider_mat(g):
    """乗り手：絵コンテ（gen_v3/a_chase.png）の、氷のように透けて光る幽霊。ゲームの ghost_rider_solid と同じく体の色をうっすら光らせ、
    輪郭を P2 の水色で強く光らせる。少し透かす（Transmission）"""
    mat = bpy.data.materials.get("MAT_t8_ghost_rider") or bpy.data.materials.new("MAT_t8_ghost_rider")
    nt, out = fresh_tree(mat)
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    body = lin3(g.get("rider_color", (0.55, 0.88, 1.0)))
    p.inputs["Base Color"].default_value = body + (1.0,)
    p.inputs["Roughness"].default_value = 0.25
    p.inputs["Transmission Weight"].default_value = g.get("rider_transmission", 0.55)
    p.inputs["IOR"].default_value = 1.2
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = 'POWER'
    pw.inputs[1].default_value = g.get("rider_rim_pow", 2.0)   # 大きいほど光が縁（落とした角）に寄り、面の明暗が残る
    rim = nt.nodes.new("ShaderNodeMath")
    rim.operation = 'MULTIPLY_ADD'                     # 光の強さ = 輪郭 × rim + core
    rim.inputs[1].default_value = g.get("rider_rim", 3.0)
    rim.inputs[2].default_value = g.get("rider_core", 0.6)
    nt.links.new(lw.outputs["Facing"], pw.inputs[0])
    nt.links.new(pw.outputs[0], rim.inputs[0])
    p.inputs["Emission Color"].default_value = lin3(g.get("rim_color", (0.34, 0.78, 1.0))) + (1.0,)
    nt.links.new(rim.outputs[0], p.inputs["Emission Strength"])
    nt.links.new(p.outputs[0], out.inputs["Surface"])
    mat["thumb_role"] = "t8 ghost rider (icy translucent, rim glow)"
    return mat


def _ghost_shark_mat(src, g):
    """サメ：ゲームの材質の色を、絵コンテの明るい薄い青へ寄せ（tint・tint_amount）、輪郭を P2 の水色で光らせる
    （ghost_possession.gdshader の輪郭の光 (1 − facing)^4 と同じ形）"""
    old = bpy.data.materials.get("MAT_t8_ghost_shark")
    if old is not None:
        bpy.data.materials.remove(old)
    mat = src.copy()
    mat.name = "MAT_t8_ghost_shark"
    nt = mat.node_tree
    p = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    base = p.inputs["Base Color"].links[0].from_socket
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    mix.inputs["B"].default_value = lin3(g.get("shark_tint", (0.72, 0.86, 1.0))) + (1.0,)
    nt.links.new(base, mix.inputs["A"])
    # 暗いところ（黒い目・口の中）には色を混ぜない（一様に混ぜると目が灰色にぼける）。混ぜる割合 = tint_amount × min(明るさ × 8, 1)
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(base, bw.inputs[0])
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = 'MULTIPLY'
    k.use_clamp = True
    k.inputs[1].default_value = 8.0
    nt.links.new(bw.outputs[0], k.inputs[0])
    f = nt.nodes.new("ShaderNodeMath")
    f.operation = 'MULTIPLY'
    f.inputs[1].default_value = g.get("shark_tint_amount", 0.45)
    nt.links.new(k.outputs[0], f.inputs[0])
    nt.links.new(f.outputs[0], mix.inputs["Factor"])
    nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.45
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = 'POWER'
    pw.inputs[1].default_value = 3.0
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = 'MULTIPLY'
    mul.inputs[1].default_value = g.get("shark_rim", 1.6)
    nt.links.new(lw.outputs["Facing"], pw.inputs[0])
    nt.links.new(pw.outputs[0], mul.inputs[0])
    p.inputs["Emission Color"].default_value = lin3(g.get("rim_color", (0.34, 0.78, 1.0))) + (1.0,)
    nt.links.new(mul.outputs[0], p.inputs["Emission Strength"])
    mat["thumb_role"] = "t8 ghost shark (game texture tinted pale blue + rim glow)"
    return mat


def _bake_pose(ob, frame):
    """アクションのそのフレームの姿を、骨の姿（matrix_basis）に写してアクションを外す（描くフレームが違っても同じ姿のまま）"""
    scn = bpy.context.scene
    scn.frame_set(frame)
    mats = {pb.name: pb.matrix_basis.copy() for pb in ob.pose.bones}
    ob.animation_data.action = None
    for name, m in mats.items():
        ob.pose.bones[name].matrix_basis = m


def _bone_head(rig, name):
    return rig.matrix_world @ rig.pose.bones[name].head


def _turn_bone(rig, name, rot3):
    """骨を、その根もとを中心に世界の回転 rot3 で回す（子も付いてくる）"""
    q = _bone_head(rig, name)
    w = Matrix.Translation(q) @ rot3.to_4x4() @ Matrix.Translation(-q)
    pb = rig.pose.bones[name]
    pb.matrix = rig.matrix_world.inverted() @ w @ rig.matrix_world @ pb.matrix
    bpy.context.view_layer.update()


def _reach(rig, side, target, pole, joints=("shoulder", "elbow", "wrist")):
    """腕（side の肩 → ひじ → 手首。脚なら joints=("hip", "knee", "ankle")）を、先が target に届くように曲げる
    （2 本の骨の IK。ひじ・ひざは pole の向きへ出す）"""
    ja, jb, jc = ("%s_%s" % (side, n) for n in joints)
    s, e, w = _bone_head(rig, ja), _bone_head(rig, jb), _bone_head(rig, jc)
    a, b = (e - s).length, (w - e).length
    to = target - s
    d = min(to.length, (a + b) * 0.999)
    ax = to.normalized()
    x = (a * a - b * b + d * d) / (2.0 * d)
    h = math.sqrt(max(a * a - x * x, 0.0))
    side_dir = (pole - ax * pole.dot(ax)).normalized()
    elbow = s + ax * x + side_dir * h
    _turn_bone(rig, ja, (e - s).normalized().rotation_difference((elbow - s).normalized()).to_matrix())
    e, w = _bone_head(rig, jb), _bone_head(rig, jc)
    _turn_bone(rig, jb, (w - e).normalized().rotation_difference((s + ax * d - e).normalized()).to_matrix())


SHARK_SNOUT = Vector((SHARK_SNOUT_X, 0.0, -0.16))   # モデルの鼻先の点


def p1_head_center(group="P1"):
    """P1 の頭の箱の真ん中（世界。いまの骨の姿で）"""
    arm = bpy.data.objects["ARM_%s" % group]
    head = next(o for o in coll(group).objects if o.type == 'MESH' and o.parent is arm and o.parent_bone == "head_pivot")
    return head.matrix_world @ (sum((Vector(v) for v in head.bound_box), Vector()) / 8.0)


def place_ghost(g):
    """サメを、P1 の頭を狙って襲う形に置く（鼻先は P1 の頭の手前、頭の向きは P1 の頭の真ん中）。
      angle：画面の上で、P1 の頭からサメの尾へ向かう向き（度。0 が右、90 が上、180 が左。絵コンテは左上から襲う）
      recede：尾がカメラから遠ざかる角度（度。0 で体が画面と平行。大きいほど頭がこちら（と P1）へ向く）
      gap：鼻先と P1 の頭の箱の面のあいだ（m。口は閉じたまま、かみつく直前）。length：サメの長さ（m）
      bank：背をカメラのほうへ倒す（度。カメラは下から見上げるので、倒さないと背の乗り手が隠れる）
      shark_bulk：太さ（横・縦）の倍率（絵コンテのサメは少しずんぐりしている）"""
    cam = bpy.context.scene.camera
    cm = cam.matrix_world.to_3x3().normalized()
    right, up_s, view = cm @ Vector((1.0, 0.0, 0.0)), cm @ Vector((0.0, 1.0, 0.0)), cm @ Vector((0.0, 0.0, -1.0))
    th, ph = math.radians(g.get("angle", 150.0)), math.radians(g.get("recede", 35.0))
    tail_dir = (math.cos(ph) * (math.cos(th) * right + math.sin(th) * up_s) + math.sin(ph) * view).normalized()
    ax = -tail_dir                                     # サメの前（鼻先の向き）＝ P1 の頭の真ん中へ
    head = p1_head_center() + Vector((0.0, 0.0, g.get("aim_dz", 0.0)))   # aim_dz：狙う高さ（頭の真ん中から、m）
    snout = head + tail_dir * (0.22 + g.get("gap", 0.2))
    s = g.get("length", 2.8) / (SHARK_SNOUT_X - SHARK_TAIL_X)
    world_up = Vector((0.0, 0.0, 1.0))
    up = (world_up - ax * world_up.dot(ax)).normalized()
    side = up.cross(ax).normalized()
    to_cam = cam.matrix_world.translation - snout
    rot = Matrix.Rotation(math.radians(g.get("bank", 25.0)) * (1.0 if to_cam.dot(side) < 0 else -1.0), 3, ax)
    m = Matrix((ax, rot @ side, rot @ up)).transposed()
    bulk = g.get("shark_bulk", (1.0, 1.0))
    scale = Matrix.Diagonal((s, s * bulk[0], s * bulk[1], 1.0))
    root = bpy.data.objects["GHOST_root"]
    root.matrix_world = Matrix.Translation(snout - m @ (scale.to_3x3() @ SHARK_SNOUT)) @ m.to_4x4() @ scale
    bpy.context.view_layer.update()
    return {"scale": round(s, 3), "aim_error_deg": round(math.degrees(ax.angle(head - snout)), 1),
            "snout_to_head_m": round((head - snout).length, 2)}


def _motes(g, rig, arm, c):
    """乗り手のまわりと、サメのうしろへ流れる光の粒（小さな光る立方体）"""
    mat = bpy.data.materials.get("MAT_t8_ghost_mote") or bpy.data.materials.new("MAT_t8_ghost_mote")
    nt, out = fresh_tree(mat)
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = lin3(g.get("mote_color", (0.6, 0.92, 1.0))) + (1.0,)
    e.inputs["Strength"].default_value = g.get("mote_strength", 6.0)
    nt.links.new(e.outputs[0], out.inputs["Surface"])
    rng = random.Random(g.get("mote_seed", 3))
    center = _bone_head(rig, "spine")
    back = (arm.matrix_world.to_3x3() @ Vector((-1.0, 0.0, 0.0))).normalized()
    size = arm.matrix_world.to_scale()[0]
    made = 0
    for i in range(int(g.get("motes", 36))):
        trail = rng.random() < 0.45
        if trail:          # サメのうしろへ流れる粒
            p = center + back * rng.uniform(0.3, 3.0) * size * 3.0 + Vector([rng.gauss(0, 0.35) for _ in range(3)])
        else:              # 乗り手のまわり
            p = center + Vector([rng.gauss(0, 0.45) for _ in range(3)])
        s = rng.uniform(0.025, 0.07)
        ob = _box("GHOST_mote_%02d" % i, (s, s, s), mat, c)
        ob.modifiers.clear()
        ob.location = p
        ob.rotation_euler = (rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0, 6.28))
        ob.visible_shadow = False
        made += 1
    return made


def ghost(art):
    """art["ghost"]：ゴーストライダー（幽霊になった P2 が乗ったサメ）を組み直す（GHOST を空にして、作業ファイルから読み直す）。
      rider_frame：乗り手の演技（GR_performance、30 fps）のフレーム。170 = 5.65 秒、右の拳を突き上げる ERUPT_HOLD_A
      shark_frame：サメのかみつき（SharkBite）のフレーム（口は開けない。ゲームのサメのあごは頂点が付いておらず動かない）
      rider_size：乗り手の背丈の、サメの長さに対する割合。rider_upright・rider_lean：上体の起こし方
      angle・recede・gap・length・bank・shark_bulk：place_ghost（P1 の頭を狙う置き方）
      world・rider_pose：パネルで手で直して保存したサメの位置と乗り手の骨の姿（save_ghost。あれば優先）
      見た目：rider_color・rider_transmission・rider_rim・rider_core・rim_color・shark_tint・shark_tint_amount・shark_rim・motes
      突進のぶれ：charge_m・charge_hold・charge_ease・mote_streak_m・tail_beat・motion_steps（_charge）、streaks・streak_*（_streaks）"""
    g = art["ghost"]
    c = _clear("GHOST")
    for a in [a for a in bpy.data.armatures if a.users == 0]:
        bpy.data.armatures.remove(a)
    with bpy.data.libraries.load(GHOST_PERF_BLEND, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if not n.startswith(("LGT_", "CAM_"))]
    with bpy.data.libraries.load(SHARK_SRC_BLEND, link=False) as (src, dst2):
        dst2.actions = ["SharkBite"]
    for ob in dst.objects:
        if ob is not None:
            c.objects.link(ob)
    root = bpy.data.objects.new("GHOST_root", None)
    root.empty_display_type = 'ARROWS'
    c.objects.link(root)
    c, arm, rig = _ghost_objects()
    arm.parent = root
    arm.matrix_parent_inverse.identity()
    _bake_pose(rig, g.get("rider_frame", 170))
    arm.animation_data_create()
    arm.animation_data.action = dst2.actions[0]
    if arm.animation_data.action.slots:
        arm.animation_data.action_slot = arm.animation_data.action.slots[0]
    _bake_pose(arm, g.get("shark_frame", 7))
    bpy.context.scene.frame_set(MOTION_FRAME)
    sk = next(o for o in c.objects if o.name.startswith("SK_Shark"))
    sk.data.materials[0] = _ghost_shark_mat(sk.data.materials[0], g)
    rider_mat = _ghost_rider_mat(g)
    for ob in c.objects:
        if ob.name.startswith("GR_") and ob.type == 'MESH':
            ob.data.materials[0] = rider_mat
            # 角を少し落とす（ゲームの箱は角が立っていて、面の向きの差だけでは箱どうしが溶け合う。落とした角が光を拾って箱の縁が読める）
            bev = ob.modifiers.new("t8_bevel", 'BEVEL')
            bev.width = g.get("rider_bevel", 0.018)
            bev.segments = 2
            bev.use_clamp_overlap = True
    if "world" in g:
        w = g["world"]
        root.matrix_world = Matrix([w[0:4], w[4:8], w[8:12], w[12:16]])
        placed = {"world": True}
    else:
        placed = place_ghost(g)
    bpy.context.view_layer.update()
    # 乗り手をサメから切り離す（サメの太さの倍率で乗り手が伸びないように。向き（サメと同じ前）と位置はそのまま、大きさは均一に）。
    # rider_size：乗り手の背丈の、サメの長さに対する割合（ゲームは 0.17。絵コンテは乗り手が大きい）。腰を動かさずに大きさを変え、
    # 上体を起こして拳を突き上げ、ハンドルを握り直し、足掛けを踏み直す
    pel = _bone_head(rig, "pelvis")
    loc, rot, _ = rig.matrix_world.decompose()
    shark_len = root.matrix_world.to_scale()[0] * (SHARK_SNOUT_X - SHARK_TAIL_X)
    u = g.get("rider_size", 0.3) * shark_len / 2.09          # ブロック人形の背丈はモデルの 2.09 単位
    rig.parent = None
    rig.matrix_world = Matrix.LocRotScale(loc, rot, Vector((u, u, u)))
    bpy.context.view_layer.update()
    rig.matrix_world = Matrix.Translation(pel - _bone_head(rig, "pelvis")) @ rig.matrix_world
    bpy.context.view_layer.update()
    def center(name):
        o = next((o for o in c.objects if o.name.startswith(name)), None)
        return None if o is None else o.matrix_world @ (sum((Vector(v) for v in o.bound_box), Vector()) / 8.0)

    shark_up = (arm.matrix_world.to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized()
    down = -shark_up
    ahead = (arm.matrix_world.to_3x3() @ Vector((1.0, 0.0, 0.0))).normalized()
    cam_pos = bpy.context.scene.camera.matrix_world.translation
    # 上体の「上」：サメの背の向きと世界の上のあいだ（rider_upright：世界の上の割合。サメが傾いても背すじは空へ）
    wu = g.get("rider_upright", 0.5)
    up = (shark_up * (1.0 - wu) + Vector((0.0, 0.0, 1.0)) * wu).normalized()
    ahead = (ahead - up * ahead.dot(up)).normalized()

    def aim(name, child, want):
        have = (_bone_head(rig, child) - _bone_head(rig, name)).normalized()
        _turn_bone(rig, name, have.rotation_difference(want.normalized()).to_matrix())

    # 上体を起こす（絵コンテの乗り手は背すじを立てて拳を突き上げる）。lean：前への傾き（上 1 に対する前の割合）
    lean = g.get("rider_lean", 0.2)
    aim("pelvis", "spine", up + ahead * lean * 0.5)
    aim("spine", "neck", up + ahead * lean)
    # 鞍にまたがったまま、胸をカメラのほうへひねる（rider_twist 度。カメラは前から来るサメのななめ前にいるので、
    # ひねらないと乗り手は横向きで、腕と胴が重なって箱のかたまりに見える）。頭は胸より少し多くこちらを向く
    def flat(v):
        return (v - up * v.dot(up)).normalized()

    def turn_about_up(a, b):
        return a.angle(b) * (1.0 if up.dot(a.cross(b)) > 0 else -1.0)

    sp = _bone_head(rig, "spine")
    to_cam = flat(cam_pos - sp)
    want = Matrix.Rotation(min(math.radians(g.get("rider_twist", 50.0)), ahead.angle(to_cam))
                           * (1.0 if turn_about_up(ahead, to_cam) > 0 else -1.0), 3, up) @ ahead
    chest = up.cross(flat(_bone_head(rig, "r_shoulder") - _bone_head(rig, "l_shoulder")))
    chest = chest if chest.dot(ahead) > 0 else -chest     # 胸の向き（両肩を結ぶ線に直角。鞍の上では前向き）
    tw = turn_about_up(chest, want)
    _turn_bone(rig, "spine", Matrix.Rotation(tw, 3, up))
    _turn_bone(rig, "neck", Matrix.Rotation(tw * 0.35, 3, up))
    # 拳を突き上げる腕は、ひねって尾のほうへ回った肩（絵コンテと同じく画面では頭の左、サメの尾の側）。
    # 上腕を外へ張り、前腕は真上へ。もう片方は前のハンドルへ
    raise_side = min(("l", "r"), key=lambda s: (_bone_head(rig, s + "_shoulder") - sp).dot(ahead))
    hold_side = "r" if raise_side == "l" else "l"
    out = _bone_head(rig, raise_side + "_shoulder") - _bone_head(rig, "spine")
    out = (out - up * out.dot(up)).normalized()
    aim(raise_side + "_shoulder", raise_side + "_elbow", up * 0.45 + out * 0.8)
    aim(raise_side + "_elbow", raise_side + "_wrist", up + out * 0.08)
    # もう片方の手はいちばん近いグリップを握る
    grips = [p for p in (center("SharkSaddle_Grip_R"), center("SharkSaddle_Grip_L")) if p is not None]
    if grips:
        sh = _bone_head(rig, hold_side + "_shoulder")
        _reach(rig, hold_side, min(grips, key=lambda p: (p - sh).length), down)
    # 足：いちばん近い足掛けの上に（ひざは前へ）
    rests = [p for p in (center("SharkSaddle_Footrest_R"), center("SharkSaddle_Footrest_L")) if p is not None]
    for side in ("l", "r"):
        if rests:
            hip = _bone_head(rig, side + "_hip")
            _reach(rig, side, min(rests, key=lambda p: (p - hip).length), ahead, ("hip", "knee", "ankle"))
    if "rider_pose" in g:
        for name, m in g["rider_pose"].items():
            pb = rig.pose.bones.get(name)
            if pb is not None:
                pb.matrix_basis = Matrix([m[0:4], m[4:8], m[8:12], m[12:16]])
        bpy.context.view_layer.update()
    motes = _motes(g, rig, arm, c)
    # 乗り手と光の粒を GHOST_root の子にする（パネルの「体ごと動かす」で GHOST_root を動かすと、いっしょに付いてくる）。
    # GHOST_root は太さの倍率で縦・横の大きさが違うので、親の逆行列をいまの GHOST_root の逆にして、形と位置を保つ
    inv = root.matrix_world.inverted()
    for ob in [rig] + [o for o in c.objects if o.name.startswith("GHOST_mote")]:
        ob.parent = root
        ob.matrix_parent_inverse = inv
    bpy.context.view_layer.update()
    charge = _charge(g, root, arm, c)
    return {"objects": len(c.objects), "motes": motes, "purged": _purge_unused(), **charge, **placed}


def _charge(g, root, arm, c):
    """突進のぶれ（モーションブラー。シャッターは MOTION_FRAME の 1 フレーム前に開いて、いまで閉じる）。
      charge_m：シャッターのあいだにサメ・乗り手・光の粒が鼻先の向きへ進む道のり（m）。GHOST_root の delta_location にキーを打つ
        （location は空けておくので、パネルの G でサメごと動かしても、ぶれはそのまま付いてくる）
      charge_ease：その動きの補間（'QUAD'・'CUBIC'・'EXPO' などを EASE_OUT で。'LINEAR' なら一様）
      charge_hold：シャッターのうち、いまの位置に止まっている割合（0〜1）。サメはほぼカメラへ向かって進むので、少し進むだけで
        頭の見かけの大きさが変わり、ズームのように大きく流れる（1.2 m を一様に近く動かすと顔が読めなかった）。止まっている時間で
        いまの姿（顔）をくっきり残し、輪郭のうしろ側だけを流す
      mote_streak_m：光の粒だけ、シャッターのあいだにさらに鼻先の向きへ進ませる道のり（m。一様）。粒が長い光の筋になり、速さの線になる
      tail_beat：シャッターのあいだに尾を横へ振る角度（度。尾の 3 本の骨に、付け根から 1:2:3 で分ける。正でカメラから見える右の横腹の側から）
      motion_steps：Cycles がぶれを描くときの途中の姿の数（2^(n−1) 区切り。曲がった動き・ゆっくりになる動きをなめらかに）"""
    steps = int(g.get("motion_steps", 4))
    for o in c.objects:
        o.cycles.motion_steps = steps
    out = {}
    fwd = (root.matrix_world.to_3x3() @ Vector((1.0, 0.0, 0.0))).normalized()
    zero = Vector((0.0, 0.0, 0.0))
    d = g.get("charge_m", 0.0)
    if d > 0:
        hold = min(max(g.get("charge_hold", 0.0), 0.0), 0.95)
        keys = [(MOTION_FRAME - 1, -fwd * d)] + ([(MOTION_FRAME - hold, zero)] if hold > 0 else []) + [(MOTION_FRAME, zero)]
        for frame, off in keys:
            root.delta_location = off
            root.keyframe_insert("delta_location", frame=frame)
        for fc in _fcurves(root.animation_data):
            for kp in fc.keyframe_points:
                kp.interpolation = g.get("charge_ease", 'QUAD')
                kp.easing = 'EASE_OUT'
        out["charge_m"] = d
    e = g.get("mote_streak_m", 0.0)
    if e > 0:
        # 粒は GHOST_root の子で、親の逆行列が組み立てたときの GHOST_root の逆なので、delta_location は世界の向きのまま効く
        for o in c.objects:
            if o.name.startswith("GHOST_mote"):
                for frame, off in ((MOTION_FRAME - 1, -fwd * e), (MOTION_FRAME, zero)):
                    o.delta_location = off
                    o.keyframe_insert("delta_location", frame=frame)
                for fc in _fcurves(o.animation_data):
                    for kp in fc.keyframe_points:
                        kp.interpolation = 'LINEAR'
        out["mote_streak_m"] = e
    if g.get("streaks", 0) > 0:
        out["streaks"] = _streaks(g, root, arm, c, fwd)
    beat = math.radians(g.get("tail_beat", 0.0))
    names = [n for n in ("tail_01", "tail_02", "tail_03") if n in arm.pose.bones]
    if beat and names:
        keep = {}
        for n in names:
            pb = arm.pose.bones[n]
            pb.rotation_mode = 'QUATERNION'
            keep[n] = pb.matrix_basis.copy()
            pb.keyframe_insert("rotation_quaternion", frame=MOTION_FRAME)
        # 骨のあいだ（サメの骨の空間。+Z が背）で、骨の付け根を中心に背の軸のまわりへ回す（世界で回すと太さの倍率でゆがむ）
        for k, n in enumerate(names):
            pb = arm.pose.bones[n]
            q = pb.head.copy()
            pb.matrix = (Matrix.Translation(q) @ Matrix.Rotation(beat * (k + 1) / 6.0, 4, 'Z')
                         @ Matrix.Translation(-q) @ pb.matrix)
            bpy.context.view_layer.update()
        for n in names:
            arm.pose.bones[n].keyframe_insert("rotation_quaternion", frame=MOTION_FRAME - 1)
        for n in names:
            arm.pose.bones[n].matrix_basis = keep[n]
        out["tail_beat"] = g["tail_beat"]
    bpy.context.scene.frame_set(MOTION_FRAME)
    return out


def _streaks(g, root, arm, c, fwd):
    """速さの線：サメの体のまわりと、通ってきた道（尾のうしろ）に置く小さな光る箱。シャッターのあいだに鼻先の向きへ
    streak_m m（1 本ずつ 0.6〜1.4 倍）進むので、ぶれて細い光の筋になる（シャッターの開いた側ほど薄い）。
      streaks：本数。streak_strength：光の強さ（細い箱が長く流れると 1 画素あたりの光は薄まるので、粒より強く）。streak_seed
      streak_size：箱の太さの範囲（m。ピントの外なので細すぎると消える）。streak_len：進む向きに伸ばした長さの範囲（m）
      streak_from・streak_reach：鼻先からうしろへ置く範囲（サメの長さの倍数）。streak_radius：体の軸からの距離の範囲
        （体の太さの倍数。[体の横, 尾のうしろの道]）。サメはほぼカメラへ向かうので、うしろの道は体の陰に入りやすい。体から離して置く
    カメラから見て体に重なる側（体の手前・奥）には置かない（体の上に筋が走ると傷に見える）。輪郭の外側と、尾のうしろの道に寄せる"""
    scn = bpy.context.scene
    scn.frame_set(MOTION_FRAME)
    sk = next(o for o in c.objects if o.name.startswith("SK_Shark"))
    dg = bpy.context.evaluated_depsgraph_get()
    ev = sk.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [sk.matrix_world @ v.co for i, v in enumerate(me.vertices) if i % 5 == 0]
    ev.to_mesh_clear()
    c0 = sum(pts, Vector()) / len(pts)
    proj = [(p - c0).dot(fwd) for p in pts]
    s_snout, s_tail = max(proj), min(proj)
    length = s_snout - s_tail
    rad = sorted(((p - c0) - fwd * s).length for p, s in zip(pts, proj) if abs(s) < 0.25 * length)
    body_r = rad[int(len(rad) * 0.85)] if rad else 0.1 * length
    cam = scn.camera
    cam_pos = cam.matrix_world.translation

    def on_screen(p):
        v = world_to_camera_view(scn, cam, p)
        return v.x, 1.0 - v.y, v.z                     # 画面の位置（左上が 0）とカメラからの奥行き（m）

    def box_of(pts, m, depth=None):
        return (min(p[0] for p in pts) - m, min(p[1] for p in pts) - m, max(p[0] for p in pts) + m,
                max(p[1] for p in pts) + m, depth)

    # 筋を通さない画面の四角（x0, y0, x1, y1, 奥行き）。奥行きがあれば、それより手前を通るときだけ外す（奥を通る筋は隠れる）
    keep_out = []
    # P1 の頭（帽子・プロペラごと）：主役の顔の上を線が横切るとうるさい
    arm_p1 = bpy.data.objects.get("ARM_P1")
    if arm_p1 is not None:
        head_pts = [on_screen(o.matrix_world @ Vector(cn)) for o in coll("P1").objects
                    if o.type == 'MESH' and o.parent is arm_p1 and o.parent_bone == "head_pivot" for cn in o.bound_box]
        if head_pts:
            keep_out.append(box_of(head_pts, g.get("streak_keep_out_margin", 0.03)))
    # 乗り手：手前を筋が横切ると、ブロックの体がざらついて読めない
    rider_pts = [on_screen(o.matrix_world @ Vector(cn)) for o in c.objects if o.name.startswith("GR_") for cn in o.bound_box]
    if rider_pts:
        keep_out.append(box_of(rider_pts, g.get("streak_rider_margin", 0.01), max(p[2] for p in rider_pts)))
    # streak_keep_out：ほかに筋を通さない画面の四角（左上が 0。[x0, y0, x1, y1]。ロゴより下は、ロゴに隠れるか P1 の体にかかるだけ）
    keep_out += [tuple(b)[:4] + (None,) for b in g.get("streak_keep_out", [])]

    def crosses_keep_out(a, b):
        for i in range(11):
            x, y, z = on_screen(a.lerp(b, i / 10.0))
            if any(x0 <= x <= x1 and y0 <= y <= y1 and (dz is None or z < dz) for x0, y0, x1, y1, dz in keep_out):
                return True
        return False

    mat = bpy.data.materials.get("MAT_t8_ghost_streak") or bpy.data.materials.new("MAT_t8_ghost_streak")
    nt, out_node = fresh_tree(mat)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = lin3(g.get("streak_color", (0.7, 0.95, 1.0))) + (1.0,)
    em.inputs["Strength"].default_value = g.get("streak_strength", 40.0)
    nt.links.new(em.outputs[0], out_node.inputs["Surface"])
    rng = random.Random(g.get("streak_seed", 5))
    inv = root.matrix_world.inverted()
    made = 0
    tries = 0
    zero = Vector((0.0, 0.0, 0.0))
    while made < int(g["streaks"]) and tries < 2000:
        tries += 1
        t = rng.uniform(g.get("streak_from", 0.15), g.get("streak_reach", 1.6))   # 鼻先からうしろへ、長さの何倍か（1 より先は尾のうしろの道）
        on_axis = c0 + fwd * (s_snout - t * length)
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        d = (d - fwd * d.dot(fwd))
        if d.length < 1e-6:
            continue
        d.normalize()
        to_cam = (cam_pos - on_axis).normalized()
        if abs(d.dot(to_cam)) > 0.55:                   # 体の手前・奥（画面で体に重なる）は避ける
            continue
        near, wake = g.get("streak_radius", ((1.05, 2.4), (0.2, 1.6)))
        r = body_r * (rng.uniform(*near) if t < 1.0 else rng.uniform(*wake))
        s = rng.uniform(*g.get("streak_size", (0.012, 0.03)))
        ln = rng.uniform(*g.get("streak_len", (0.0, 0.0)))   # 進む向きに伸ばした長さ（m。ぶれに足して、ピントの外でも線に見える）
        run = g.get("streak_m", 2.0) * rng.uniform(0.6, 1.4)
        pos = on_axis + d * r
        # シャッターが開いたときの位置は、サメごとの突進（charge_m）と筋自身の道のり（run）のぶん後ろ
        if keep_out and crosses_keep_out(pos - fwd * (run + g.get("charge_m", 0.0) + ln / 2.0), pos + fwd * (ln / 2.0)):
            continue
        ob = _box("GHOST_streak_%02d" % made, (s, s, max(s, ln)), mat, c)
        ob.modifiers.clear()
        ob.location = pos
        ob.rotation_euler = fwd.to_track_quat('Z', 'Y').to_euler()
        ob.visible_shadow = False
        ob.parent = root
        ob.matrix_parent_inverse = inv
        ob.cycles.motion_steps = 1
        for frame, off in ((MOTION_FRAME - 1, -fwd * run), (MOTION_FRAME, zero)):
            ob.delta_location = off
            ob.keyframe_insert("delta_location", frame=frame)
        for fc in _fcurves(ob.animation_data):
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR'
        made += 1
    scn.frame_set(MOTION_FRAME)
    return made


def _purge_unused():
    """組み直しで使われなくなったメッシュ・骨・材質・画像・動きを消す（作業ファイルを読み直すたびに 2048 のサメの画像などが増え、
    Blender が重くなる。使われていないものは .blend にも保存されない）"""
    n = 0
    for _ in range(2):              # 材質を消すと、その画像が使われなくなる
        for data in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images, bpy.data.actions):
            for idb in [x for x in data if x.users == 0 and not x.use_fake_user
                        and getattr(x, "type", 'IMAGE') == 'IMAGE']:
                data.remove(idb)
                n += 1
    return n


def save_ghost():
    """いまのサメの位置（GHOST_root、world）と乗り手の骨の姿（rider_pose）を blender_art.json の ghost に書く（パネルの保存）。
    組み直したとき（setup・ghost）は snout・tail・roll の代わりにこれを当てる"""
    c, arm, rig = _ghost_objects()
    bpy.context.scene.frame_set(MOTION_FRAME)      # 突進のぶれのキー（delta_location）が 0 のフレームで読む
    art = _art()
    g = art.setdefault("ghost", {})
    g["world"] = [round(v, 6) for row in bpy.data.objects["GHOST_root"].matrix_world for v in row]
    g["rider_pose"] = {pb.name: [round(v, 6) for row in pb.matrix_basis for v in row] for pb in rig.pose.bones}
    with open(T8_ART, "w", encoding="utf-8") as f:
        json.dump(art, f, ensure_ascii=False, indent=1)
    return {"bones": len(g["rider_pose"]), "file": T8_ART}


def apply_ghost_pose(art):
    """blender_art.json の ghost の world・rider_pose を、いまのゴーストライダーに当て直す（パネルの「保存した姿に戻す」）"""
    g = art.get("ghost", {})
    c, arm, rig = _ghost_objects()
    bpy.context.scene.frame_set(MOTION_FRAME)      # 突進のぶれのキー（delta_location）が 0 のフレームで当てる
    if "world" in g:
        w = g["world"]
        bpy.data.objects["GHOST_root"].matrix_world = Matrix([w[0:4], w[4:8], w[8:12], w[12:16]])
    n = 0
    for name, m in g.get("rider_pose", {}).items():
        pb = rig.pose.bones.get(name)
        if pb is not None:
            pb.matrix_basis = Matrix([m[0:4], m[4:8], m[8:12], m[12:16]])
            n += 1
    bpy.context.view_layer.update()
    return {"applied": n}


# ------------------------------------------------------------------ ぼけ・描く層

def zoom(art):
    """art["fov"]（縦の画角、度）でズームする。位置と向きはゲームのカメラのまま（背景のゲームの絵は、合成で
    同じ倍率に拡大する：compose.py の plate_zoom = tan(ゲームの画角/2) / tan(fov/2)）"""
    J = _J()
    cam = bpy.context.scene.camera
    cam.data.angle_y = math.radians(art.get("fov", J["camera"]["fov"]))
    z = math.tan(math.radians(J["camera"]["fov"]) / 2) / math.tan(cam.data.angle_y / 2)
    bpy.context.scene["t8_plate_zoom"] = z
    return {"fov": round(math.degrees(cam.data.angle_y), 2), "plate_zoom": round(z, 4)}


def lens(art):
    """カメラのぼけ：ピントは P1 の胸（art["focus"] があればその Godot の位置）、絞りは art["fstop"]"""
    J = _J()
    cam = bpy.context.scene.camera
    focus = _g_rel(J, art["focus"]) if "focus" in art else joint_pos("spine")
    d = (cam.matrix_world.inverted() @ focus)
    cam.data.dof.use_dof = True
    cam.data.dof.focus_distance = -d.z
    cam.data.dof.aperture_fstop = art.get("fstop", 0.5)
    cam.data.dof.aperture_blades = 7
    return {"focus_m": round(-d.z, 3), "fstop": cam.data.dof.aperture_fstop}


def layer():
    """全部をいっしょに描く VL_t8（ぼけとモーションブラーは Cycles のまま。背景はゲームの絵に重ねる）。2 人目・文字の板は外す"""
    scn = bpy.context.scene
    vl = scn.view_layers.get("VL_t8") or scn.view_layers.new("VL_t8")
    for lc in vl.layer_collection.children:
        lc.exclude = lc.name in ("P2", "IMPORT_ROOT")
        if not lc.exclude:
            lc.holdout = False
            lc.indirect_only = False
    for o in bpy.data.objects:
        if o.name.startswith("LBL_"):
            o.hide_render = True
    for other in scn.view_layers:
        other.use = (other.name == "VL_t8")
    vl.use_pass_combined = True
    r = scn.render
    # 描画データの持ち越しを切る（build_scene はオン。描いたあとに破片を作り直すと Blender が落ちた）
    r.use_persistent_data = False
    r.use_motion_blur = True
    r.motion_blur_position = 'END'
    r.motion_blur_shutter = 1.0
    return [v.name for v in scn.view_layers if v.use]


def preview(path, engine="BLENDER_EEVEE", res=(960, 540), samples=16, layer_name="VL_t8"):
    """確かめるための速い絵（その層だけ、背景は透明の PNG）。描いたあとは設定を元に戻す"""
    scn = bpy.context.scene
    r = scn.render
    keep = (r.engine, r.resolution_x, r.resolution_y, r.filepath, r.image_settings.file_format, r.image_settings.color_mode,
            getattr(scn.eevee, "taa_render_samples", None), scn.cycles.samples)
    uses = {vl.name: vl.use for vl in scn.view_layers}
    try:
        for vl in scn.view_layers:
            vl.use = (vl.name == layer_name)
        r.engine = engine
        r.resolution_x, r.resolution_y = res
        r.image_settings.file_format = 'PNG'
        r.image_settings.color_mode = 'RGBA'
        if engine == "CYCLES":
            scn.cycles.samples = samples
        elif hasattr(scn.eevee, "taa_render_samples"):
            scn.eevee.taa_render_samples = samples
        r.filepath = path
        bpy.ops.render.render(write_still=True)
    finally:
        for vl in scn.view_layers:
            vl.use = uses[vl.name]
        r.engine, r.resolution_x, r.resolution_y, r.filepath, r.image_settings.file_format, r.image_settings.color_mode = keep[:6]
        if keep[6] is not None:
            scn.eevee.taa_render_samples = keep[6]
        scn.cycles.samples = keep[7]
    return path


def preview_views(path_stem, group="P1", dist=9.0):
    """ポーズを確かめる絵：体の正面・右横・本番のカメラ（turn のあとの向き）。確かめ用のカメラは描いたあと消す"""
    scn = bpy.context.scene
    main = scn.camera
    spec = json.loads(scn.get("t8_pose", "{}"))
    turn = math.radians(spec.get("turn", 0.0))
    fwd = Matrix.Rotation(turn, 3, 'Z') @ Vector((0.0, -1.0, 0.0))
    right = fwd.cross(Vector((0.0, 0.0, 1.0)))
    center = joint_pos("pelvis", group)
    out = []
    data = bpy.data.cameras.new("CAM_debug")
    data.angle = math.radians(30.0)
    cam = bpy.data.objects.new("CAM_debug", data)
    scn.collection.objects.link(cam)
    try:
        for name, d in (("front", fwd), ("side", right)):
            eye = center + d * dist
            cam.location = eye
            cam.rotation_euler = (center - eye).to_track_quat('-Z', 'Y').to_euler()
            scn.camera = cam
            out.append(preview("%s_%s.png" % (path_stem, name)))
        scn.camera = main
        out.append(preview("%s_shot.png" % path_stem))
    finally:
        scn.camera = main
        bpy.data.objects.remove(cam)
        bpy.data.cameras.remove(data)
    return out


def setup():
    """組んだ直後のファイルに、t8 の演出を全部かける。骨（ARM_P1）がもうあるファイルでは、骨はそのまま（保存した姿だけ当て直す）"""
    art = _art()
    res = {}
    if bpy.data.objects.get("ARM_P1") is None:
        res["rig"] = rig()
        res["sides"] = side_names()
    res["zoom"] = zoom(art)                 # 画面で置く破片より先に（画角で置き場所が変わる）
    if bpy.data.objects.get("ARM_P1") is None:
        res["pose"] = pose(art.get("pose", {}))
        res["armature"] = armature()
    res["bone_pose"] = apply_bone_pose(art)
    res["fingers"] = hide_fingers(art)
    res["debris"] = debris(art)
    res["dust"] = dust(art)
    if "ghost" in art:
        res["ghost"] = ghost(art)
    res["lens"] = lens(art)
    res["layer"] = layer()
    return res

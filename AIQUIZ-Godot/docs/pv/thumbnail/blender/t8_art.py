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
  - カメラのぼけ（ピントは P1）と、全部をいっしょに描く view layer VL_t8（2 人目と文字の板は外す）
"""
import json
import math
import os
import random

import bmesh
import bpy
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
    res["lens"] = lens(art)
    res["layer"] = layer()
    return res

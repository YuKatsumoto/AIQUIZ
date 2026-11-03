"""机のセットの人物：等身大のブロックマン（P1・P2）。服は着ない。

ゲームのブロックマン（player_controller.gd の _build_player_skeleton・_create_detailed_hand）と同じパーツの組み方
（こし・むね・頭・上腕・前腕・手のひらと指 3 節・親指・もも・すね・足・つま先、顔の目と口）と色（PlayerSkin.SLOT_COLORS）で、
体の比率だけ人に合わせる。ゲームの比率のまま人の背丈にすると肩幅が約 0.8m になり、2 人並んで 1 台のキーボードに手が届かないため。
骨組みは MPFB2（MakeHuman の Blender 版）の人の体の mixamo（Mixamo と同じ骨の名前、指まで 52 本）を使い、骨ごとに角を丸めた箱を
付ける（1 つの形に、骨ごとの重み 1 で。Godot へはそのまま骨組みつきの形として持っていける）。人の体の形そのものは使わない。
P1：オレンジ。左手で W A S D・Space、右手は膝の上。P2：水色。右手は矢印、左手は膝の上（8・9・0 は Godot で伸ばして押す）。

ライブの Blender（Higgsfield の Blender 連携の bl_execute）で実行する。先に build_tutorial_desk.py でセットを作っておく。
    import runpy
    ns = runpy.run_path(r"G:/AIQUIZ-Main/AIQUIZ-Godot/assets/tutorial_desk/source/blender/build_tutorial_people.py")
    result = ns["build"]()
TD_People コレクションの中だけを作り直す。仮の体（TD_Proxy）は隠す。
"""
import importlib
import math
import runpy
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
DESK = runpy.run_path(str(HERE / "build_tutorial_desk.py"))
MPFB = "bl_ext.blender_org.mpfb"
COLLECTION = "TD_People"
B = "mixamorig:"
CHAIR_Y = DESK["CHAIR_Y"]

# PlayerSkin.SLOT_COLORS（sRGB）。頭、胴（むね・こし）、手足（腕・手・足）
COLORS = {
    "P1": {"head": (0.95, 0.65, 0.35), "body": (0.95, 0.55, 0.20), "limb": (0.85, 0.48, 0.18)},
    "P2": {"head": (0.30, 0.75, 0.95), "body": (0.20, 0.65, 0.90), "limb": (0.15, 0.55, 0.80)},
}
SLOTS = ("head", "body", "limb", "face")
FINGERS = ("Index", "Middle", "Ring", "Pinky")

PEOPLE = {
    "P1": {
        "x": -DESK["CHAIR_X"],
        # 骨組みの大きさを決める人の体（背丈は約 1.65m）
        "macro": {"gender": 0.75, "age": 0.43, "muscle": 0.5, "weight": 0.45, "proportions": 0.6, "height": 0.62,
                  "cupsize": 0.5, "firmness": 0.5, "race": {"asian": 0.6, "caucasian": 0.25, "african": 0.15}},
        # 手："lap"（膝の上）か、指ごとに置くキー（None なら少し浮かせる）と、手の向き（yaw。度。正で世界の +X へ向ける）。
        # twist は上半身をキーボードの真ん中へひねる角度（骨の Y 軸まわりの正の回転で、その人の左＝世界の -X を向く）
        "hands": {"Left": {"Index": "D", "Middle": "S", "Ring": "A", "Pinky": "Caps", "Thumb": "Space", "yaw": 10.0},
                  "Right": "lap"},
        "twist": -4.0, "head_yaw": -4.0,
    },
    "P2": {
        "x": DESK["CHAIR_X"],
        "macro": {"gender": 0.4, "age": 0.42, "muscle": 0.45, "weight": 0.45, "proportions": 0.6, "height": 0.62,
                  "cupsize": 0.4, "firmness": 0.5, "race": {"asian": 0.6, "caucasian": 0.3, "african": 0.1}},
        # 左手はふだん膝の上（前腕がキーボードの真ん中を隠さないように）。8・9・0 を押すときだけ Godot で伸ばす
        "hands": {"Right": {"Index": "←", "Middle": "↓", "Ring": "→", "Pinky": None, "Thumb": None, "yaw": -10.0},
                  "Left": "lap"},
        "twist": 3.0, "head_yaw": 6.0,
    },
}


# ---------- 入口 ----------

def build():
    coll = reset()
    proxy = bpy.data.collections.get("TD_Proxy")
    if proxy is not None:
        proxy.hide_render = True
        proxy.hide_viewport = True
    keys = {str(o["key_id"]): o for o in bpy.data.objects if o.name.startswith("KEY_") and "key_id" in o}
    made = {}
    for tag, cfg in PEOPLE.items():
        rig = create_rig(tag, cfg, coll)
        block = build_block(tag, rig, coll)
        made[tag] = {"rig": rig.name, "block": block.name, "vertices": len(block.data.vertices),
                     "pose": pose_seated(tag, cfg, rig, keys, coll, block)}
    return {"people": made, "objects": len(coll.all_objects)}


def reset():
    scene_root = bpy.context.scene.collection
    coll = bpy.data.collections.get(COLLECTION) or bpy.data.collections.new(COLLECTION)
    if coll.name not in scene_root.children:
        scene_root.children.link(coll)
    for obj in list(coll.all_objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            for kind, pool in ((bpy.types.Mesh, "meshes"), (bpy.types.Armature, "armatures"), (bpy.types.Curve, "curves")):
                if isinstance(data, kind):
                    getattr(bpy.data, pool).remove(data)
                    break
    for mat in list(bpy.data.materials):
        if mat.name.startswith("PEO_") and mat.users == 0:
            bpy.data.materials.remove(mat)
    return coll


# ---------- 骨組み ----------

def create_rig(tag, cfg, coll):
    """MPFB2 の人の体で骨組み（mixamo）を合わせ、体の形は消す。"""
    human_service = importlib.import_module(MPFB + ".services.humanservice").HumanService
    layer = bpy.context.view_layer.layer_collection.children[coll.name]
    previous = bpy.context.view_layer.active_layer_collection
    bpy.context.view_layer.active_layer_collection = layer
    try:
        body = human_service.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
                                          feet_on_ground=True, scale=0.1, macro_detail_dict=cfg["macro"])
        rig = human_service.add_builtin_rig(body, "mixamo", import_weights=False)
    finally:
        bpy.context.view_layer.active_layer_collection = previous
    mesh = body.data
    bpy.data.objects.remove(body, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)
    rig.name = f"PEO_{tag}_Rig"
    rig.data.name = f"PEO_{tag}_Rig"
    # MPFB2 の人は -Y を向く。机（+Y）へ向け、椅子の上に置く
    rig.location = (cfg["x"], CHAIR_Y, 0.0)
    rig.rotation_euler = (0.0, 0.0, math.pi)
    return rig


# ---------- ブロックマンの形 ----------

def build_block(tag, rig, coll):
    """骨ごとに角を丸めた箱を付けた 1 つの形（骨組みの休みの姿勢の座標で作り、骨ごとの重み 1 で曲げる）。"""
    bones = {b.name[len(B):]: b for b in rig.data.bones}

    def head(n):
        return bones[n].head_local.copy()

    def tail(n):
        return bones[n].tail_local.copy()

    def x_axis(n):
        return bones[n].matrix_local.to_3x3().col[0].normalized()

    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    groups = []

    def part(a, b, width, depth, hint_x, slot, bone, radius=None):
        a, b = Vector(a), Vector(b)
        y = b - a
        length = y.length
        y.normalize()
        x = (hint_x - y * hint_x.dot(y)).normalized()
        z = x.cross(y)
        r = radius if radius is not None else min(0.012, 0.16 * min(width, depth))
        temp = bmesh.new()
        bmesh.ops.create_cube(temp, size=1.0)
        bmesh.ops.scale(temp, vec=Vector((width, length, depth)), verts=temp.verts)
        rounded = bmesh.ops.bevel(temp, geom=temp.edges[:], offset=r, segments=3, profile=0.5, affect="EDGES",
                                  clamp_overlap=True)
        for face in temp.faces:
            face.smooth = False
        for face in rounded["faces"]:
            face.smooth = True
        basis = Matrix((x, y, z)).transposed().to_4x4()
        basis.translation = (a + b) / 2
        temp.transform(basis)
        me = bpy.data.meshes.new("PEO_tmp_part")
        temp.to_mesh(me)
        temp.free()
        v0, f0 = len(bm.verts), len(bm.faces)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        name = B + bone
        if name not in groups:
            groups.append(name)
        index = groups.index(name)
        for v in bm.verts[v0:]:
            v[deform][index] = 1.0
        for face in bm.faces[f0:]:
            face.material_index = SLOTS.index(slot)

    up = Vector((0.0, 0.0, 1.0))
    across = Vector((1.0, 0.0, 0.0))
    # こし・むね（ゲームと同じく、むねが少し大きい）。むねは背骨のいちばん上の骨で曲がる
    part(head("Hips") - up * 0.07, head("Spine1"), 0.38, 0.23, across, "body", "Hips")
    part(head("Spine1"), head("Neck") + up * 0.015, 0.42, 0.245, across, "body", "Spine2")
    part(head("Neck"), head("Head") + up * 0.02, 0.095, 0.095, across, "head", "Neck")
    # 頭（立方体）と顔（骨組みの座標では前が -Y）
    base = head("Head")
    size = 0.25
    part(base - up * 0.005, base + up * (size - 0.005), size, size, across, "head", "Head", radius=0.018)
    front = base.y - size / 2 - 0.002
    for ex in (-0.052, 0.052):
        part(Vector((base.x + ex, front, base.z + 0.13)), Vector((base.x + ex, front, base.z + 0.162)), 0.032, 0.008,
             across, "face", "Head", radius=0.003)
    part(Vector((base.x, front, base.z + 0.066)), Vector((base.x, front, base.z + 0.082)), 0.07, 0.008, across, "face",
         "Head", radius=0.003)
    for side in ("Left", "Right"):
        arm, fore, hand = f"{side}Arm", f"{side}ForeArm", f"{side}Hand"
        d = (tail(arm) - head(arm)).normalized()
        part(head(arm) - d * 0.02, tail(arm) + d * 0.01, 0.095, 0.095, x_axis(arm), "limb", arm)
        d = (tail(fore) - head(fore)).normalized()
        part(head(fore) - d * 0.01, tail(fore), 0.085, 0.085, x_axis(fore), "limb", fore)
        roots = [head(f"{side}Hand{f}1") for f in FINGERS]
        lateral = roots[0] - roots[-1]
        palm_end = sum(roots, Vector()) / len(roots)
        part(head(hand), palm_end, lateral.length + 0.024, 0.034, lateral, "limb", hand)
        for finger in FINGERS:
            for i in (1, 2, 3):
                n = f"{side}Hand{finger}{i}"
                d = (tail(n) - head(n)).normalized()
                part(head(n), tail(n) + d * (0.004 if i == 3 else 0.0), 0.019, 0.021, lateral, "limb", n, radius=0.004)
        for i in (1, 2, 3):
            n = f"{side}HandThumb{i}"
            d = (tail(n) - head(n)).normalized()
            part(head(n), tail(n) + d * (0.004 if i == 3 else 0.0), 0.022, 0.022, x_axis(n), "limb", n, radius=0.005)
        up_leg, leg, foot, toe = f"{side}UpLeg", f"{side}Leg", f"{side}Foot", f"{side}ToeBase"
        d = (tail(up_leg) - head(up_leg)).normalized()
        part(head(up_leg) - d * 0.02, tail(up_leg), 0.15, 0.15, x_axis(up_leg), "limb", up_leg)
        part(head(leg), tail(leg), 0.125, 0.125, x_axis(leg), "limb", leg)
        d = (tail(foot) - head(foot)).normalized()
        part(head(foot) - d * 0.05, head(toe), 0.10, 0.075, across, "limb", foot)
        d = (tail(toe) - head(toe)).normalized()
        part(head(toe), tail(toe) + d * 0.01, 0.095, 0.05, across, "limb", toe)

    me = bpy.data.meshes.new(f"PEO_{tag}_Block")
    bm.to_mesh(me)
    bm.free()
    for slot in SLOTS:
        me.materials.append(mat_face() if slot == "face" else mat_block(f"PEO_{tag}_{slot.capitalize()}", COLORS[tag][slot]))
    obj = bpy.data.objects.new(me.name, me)
    coll.objects.link(obj)
    for name in groups:
        obj.vertex_groups.new(name=name)
    obj.parent = rig
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    return obj


# ---------- 座った姿勢 ----------

def pose_seated(tag, cfg, rig, keys, coll, block):
    # 姿勢を決める間は、この骨組みで曲げる形の変形を止めて計算を軽くする（指先の当たりは骨ごとの箱の頂点で測る）
    meshes = [o for o in bpy.data.objects if o.parent == rig and o.type == "MESH"]
    states = [(m, m.show_viewport) for o in meshes for m in o.modifiers]
    for m, _ in states:
        m.show_viewport = False
    try:
        return _pose_seated(tag, cfg, rig, keys, coll, bone_points(block))
    finally:
        for m, shown in states:
            m.show_viewport = shown
        bpy.context.view_layer.update()


def _pose_seated(tag, cfg, rig, keys, coll, points):
    x = cfg["x"]
    bpy.context.view_layer.update()
    to_arm = rig.matrix_world.inverted()

    def rest(name):
        return rig.data.bones[B + name].matrix_local

    hips = rig.pose.bones[B + "Hips"]
    target = to_arm @ Vector((x, CHAIR_Y + 0.03, 0.575))
    hips.location = rest("Hips").to_3x3().inverted() @ (target - rest("Hips").translation)
    # 前かがみで、キーボードを見下ろす（骨の X 軸まわりの正の回転が前へ倒れる向き）。
    # 上半身はキーボードの真ん中へ少しひねる（twist。3 つの背骨に分ける）
    twist = math.radians(cfg.get("twist", 0.0))
    head_yaw = math.radians(cfg.get("head_yaw", 0.0))
    for name, deg, yaw in (("Spine", 11.0, twist), ("Spine1", 9.0, twist), ("Spine2", 7.0, twist), ("Neck", 6.0, head_yaw * 0.4),
                           ("Head", 16.0, head_yaw * 0.6)):
        bone = rig.pose.bones[B + name]
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (math.radians(deg), yaw, 0.0)
    report = {}
    side_x = {"Left": -1.0, "Right": 1.0}
    for side in ("Left", "Right"):
        sx = side_x[side]
        ankle = empty(f"PEO_{tag}_IK_{side}Ankle", (x + sx * 0.10, 0.06, 0.085), coll)
        knee_pole = empty(f"PEO_{tag}_IK_{side}KneePole", (x + sx * 0.13, 0.50, 0.56), coll)
        ik(rig, f"{side}Leg", ankle, knee_pole, 2)
        toe = empty(f"PEO_{tag}_IK_{side}Toe", (x + sx * 0.11, 0.20, 0.01), coll)
        track = rig.pose.bones[B + f"{side}Foot"].constraints.new("DAMPED_TRACK")
        track.target = toe
    for side, spec in cfg["hands"].items():
        sx = side_x[side]
        if spec == "lap":
            wrist = Vector((x + sx * 0.09, CHAIR_Y + 0.34, 0.63))
            aim = wrist + Vector((-sx * 0.05, 0.12, -0.02))
            pole = Vector((x + sx * 0.32, CHAIR_Y + 0.05, 0.85))
        else:
            # 中指の付け根が、中指のキーの手前・上に来る所から始める（place_typing_hand が指先の当たりで合わせ直す）
            yaw = math.radians(spec["yaw"])
            forward = Vector((math.sin(yaw), math.cos(yaw), 0.0))
            palm = (rig.data.bones[B + f"{side}HandMiddle1"].head_local - rig.data.bones[B + f"{side}Hand"].head_local).length
            wrist = key_top(keys[spec["Middle"]]) - forward * (palm + KNUCKLE_BACK) + Vector((0.0, 0.0, KNUCKLE_HEIGHT))
            aim = wrist + forward * 0.25
            # 肘は体の外側の、少し後ろの下（キーボードの真ん中へ伸ばす手は、体の前に寄せる）
            reach_in = (wrist.x - x) * sx < 0
            pole = Vector((x + sx * (0.30 if reach_in else 0.18), CHAIR_Y + 0.22, 0.78))
        wrist_e = empty(f"PEO_{tag}_IK_{side}Wrist", tuple(wrist), coll)
        pole_e = empty(f"PEO_{tag}_IK_{side}ElbowPole", tuple(pole), coll)
        aim_e = empty(f"PEO_{tag}_IK_{side}Aim", tuple(aim), coll)
        ik(rig, f"{side}ForeArm", wrist_e, pole_e, 2)
        track = rig.pose.bones[B + f"{side}Hand"].constraints.new("DAMPED_TRACK")
        track.target = aim_e
        roll = palm_down(rig, side)
        bpy.context.view_layer.update()
        if spec == "lap":
            reached = rig.matrix_world @ rig.pose.bones[B + f"{side}Hand"].head
            report[side] = {"wrist_error": round((reached - wrist).length, 3), "roll": roll, "curl": curl_fingers(rig, side)}
        else:
            report[side] = place_typing_hand(rig, side, spec, keys, points, wrist_e, aim_e)
            report[side]["roll"] = roll
    return report


def empty(name, loc, coll, size=0.03):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = size
    obj.location = loc
    obj.hide_render = True
    coll.objects.link(obj)
    return obj


def ik(rig, bone_name, target, pole, chain):
    """IK を付け、膝・肘がいちばん pole に近づく pole_angle を選ぶ。"""
    bone = rig.pose.bones[B + bone_name]
    constraint = bone.constraints.new("IK")
    constraint.target = target
    constraint.pole_target = pole
    constraint.chain_count = chain
    constraint.use_tail = True
    best = None
    for angle in range(-180, 180, 15):
        constraint.pole_angle = math.radians(angle)
        bpy.context.view_layer.update()
        joint = rig.matrix_world @ bone.head
        distance = (joint - pole.location).length
        if best is None or distance < best[0]:
            best = (distance, angle)
    constraint.pole_angle = math.radians(best[1])
    bpy.context.view_layer.update()
    return best[1]


def palm_down(rig, side):
    """手のひらが下を向くよう、手の骨をその向き（Y 軸）のまわりに回す。手が前を向くとき、
    下向きの左手は親指が右に、右手は親指が左に来る。その度合いがいちばん大きい角度を選ぶ。"""
    hand = rig.pose.bones[B + f"{side}Hand"]
    hand.rotation_mode = "XYZ"
    sign = 1.0 if side == "Left" else -1.0
    best = None
    for deg in range(-180, 180, 10):
        hand.rotation_euler = (0.0, math.radians(deg), 0.0)
        bpy.context.view_layer.update()
        mw = rig.matrix_world
        wrist = mw @ hand.head
        middle = mw @ rig.pose.bones[B + f"{side}HandMiddle1"].head
        thumb = mw @ rig.pose.bones[B + f"{side}HandThumb1"].tail
        pinky = mw @ rig.pose.bones[B + f"{side}HandPinky1"].head
        lateral = (middle - wrist).normalized().cross(Vector((0.0, 0.0, 1.0)))
        score = sign * (thumb - pinky).dot(lateral)
        if best is None or score > best[0]:
            best = (score, deg)
    hand.rotation_euler = (0.0, math.radians(best[1]), 0.0)
    return best[1]


def curl_fingers(rig, side):
    """指をキーへ軽く曲げる。曲げる向きは、中指で試して指先が下がる向き（手のひらは下向き）。手の中ではそろえる。"""
    def set_curl(finger, angles, sign):
        for i, deg in zip((1, 2, 3), angles):
            bone = rig.pose.bones[B + f"{side}Hand{finger}{i}"]
            bone.rotation_mode = "XYZ"
            bone.rotation_euler = (math.radians(deg) * sign, 0.0, 0.0)

    def tip_z(finger):
        bpy.context.view_layer.update()
        return (rig.matrix_world @ rig.pose.bones[B + f"{side}Hand{finger}3"].tail).z

    base = tip_z("Middle")
    set_curl("Middle", (15.0, 15.0, 15.0), 1.0)
    sign = 1.0 if tip_z("Middle") < base else -1.0
    for finger, angles in (("Index", (14.0, 32.0, 18.0)), ("Middle", (16.0, 34.0, 18.0)), ("Ring", (18.0, 36.0, 20.0)),
                           ("Pinky", (20.0, 38.0, 22.0))):
        set_curl(finger, angles, sign)
    thumb_base = tip_z("Thumb")
    set_curl("Thumb", (6.0, 12.0, 12.0), 1.0)
    thumb_sign = 1.0 if tip_z("Thumb") < thumb_base else -1.0
    set_curl("Thumb", (6.0, 12.0, 12.0), thumb_sign)
    return {"fingers": sign, "thumb": thumb_sign}


# ---------- キーに置く手 ----------

# 中指の付け根を、中指のキーからどれだけ手前（m）・上（キーの天面から, m）に置くか。キーを打つ手の丸みの形
KNUCKLE_BACK = 0.056
KNUCKLE_HEIGHT = 0.042
# 人差し指〜小指の付け根の並びを水平にするとき、親指の側をどれだけ高くするか（m。手のひらがわずかに内へ傾く自然な形）
THUMB_SIDE_UP = 0.005
# 指先の当たる高さ（キーの天面のわずか上）と、受け持つキーのない指を浮かせる高さ
CONTACT = 0.0004
HOVER = 0.010
# 2 つ目・3 つ目の節の曲げ（度）の割合。付け根の節はキーの上の点へ向け、この 2 つをこの割合で曲げて指先をキーへ下ろす。
# 曲げる量（この何倍か）は、指先がキーの真ん中に来るよう指ごとに決める（長い中指ほどよく曲がる。キーを打つ手の丸み）
BEND = {"finger": (40.0, 16.0), "thumb": (10.0, 6.0)}
BEND_RANGE = {"finger": (0.0, 2.2), "thumb": (0.0, 3.0)}
# 親指を置く所を探す基準：人差し指のキーからこれだけ手前（m）。そこにいちばん近い、親指のキーの天面の点に置く
THUMB_BELOW_INDEX = 0.04


def key_top(obj):
    """キーの天面の真ん中（世界の座標）。"""
    top = max(corner[2] for corner in obj.bound_box)
    return obj.matrix_world @ Vector((0.0, 0.0, top))


def key_top_near(obj, point, margin=0.004):
    """キーの天面のうち、point にいちばん近い点（世界の座標。縁から margin 内側）。横に長いキー（Space など）で使う。"""
    corners = [Vector(c) for c in obj.bound_box]
    local = obj.matrix_world.inverted() @ point
    x = min(max(local.x, min(c.x for c in corners) + margin), max(c.x for c in corners) - margin)
    y = min(max(local.y, min(c.y for c in corners) + margin), max(c.y for c in corners) - margin)
    return obj.matrix_world @ Vector((x, y, max(c.z for c in corners)))


def bone_points(block):
    """骨ごとの、その骨で曲がる箱の頂点（骨組みの休みの姿勢の座標）。重みは骨ごとに 1 なので、骨と一緒に固く動く。"""
    names = {group.index: group.name for group in block.vertex_groups}
    points = {}
    for vertex in block.data.vertices:
        for group in vertex.groups:
            if group.weight > 0.5:
                points.setdefault(names[group.group], []).append(vertex.co.copy())
    return points


def posed_points(rig, points, bone_name):
    pose_bone = rig.pose.bones[bone_name]
    matrix = rig.matrix_world @ pose_bone.matrix @ pose_bone.bone.matrix_local.inverted()
    return [matrix @ p for p in points.get(bone_name, [])]


def segment_low(rig, side, finger, points, index):
    """その指の index 番目（1〜3）の節の箱の、いちばん低い点。"""
    return min(posed_points(rig, points, B + f"{side}Hand{finger}{index}"), key=lambda p: p.z)


def finger_contact(rig, side, finger, points):
    """その指の 3 つの節の箱のうち、いちばん低い点（キーに当たる所）。"""
    return min((segment_low(rig, side, finger, points, i) for i in (1, 2, 3)), key=lambda p: p.z)


def set_finger_curl(rig, side, finger, degrees, sign):
    for i in (1, 2, 3):
        bone = rig.pose.bones[B + f"{side}Hand{finger}{i}"]
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (math.radians(degrees) * sign, 0.0, 0.0)
    bpy.context.view_layer.update()


def curl_sign(rig, side, finger, points):
    """節の X 軸まわりの正の回転で指先が下がるなら 1。"""
    set_finger_curl(rig, side, finger, 0.0, 1.0)
    straight = finger_contact(rig, side, finger, points).z
    set_finger_curl(rig, side, finger, 10.0, 1.0)
    bent = finger_contact(rig, side, finger, points).z
    set_finger_curl(rig, side, finger, 0.0, 1.0)
    return 1.0 if bent < straight else -1.0


def nearest_key(keys, point):
    best = None
    for key_id, obj in keys.items():
        top = key_top(obj)
        distance = Vector((top.x - point.x, top.y - point.y)).length
        if best is None or distance < best[0]:
            best = (distance, key_id)
    return best[1]


def level_palm(rig, side):
    """手のひらを下へ向け、人差し指〜小指の付け根の並びを水平に近づける（親指の側をわずかに高く）。手の骨の向きまわりの角度（度）。
    6 度おきに探してから、そのまわりを 1 度おきに探す。"""
    hand = rig.pose.bones[B + f"{side}Hand"]
    hand.rotation_mode = "XYZ"
    sign = 1.0 if side == "Left" else -1.0

    def score(degrees):
        hand.rotation_euler = (0.0, math.radians(degrees), 0.0)
        bpy.context.view_layer.update()
        mw = rig.matrix_world
        wrist = mw @ hand.head
        middle = mw @ rig.pose.bones[B + f"{side}HandMiddle1"].head
        index = mw @ rig.pose.bones[B + f"{side}HandIndex1"].head
        pinky = mw @ rig.pose.bones[B + f"{side}HandPinky1"].head
        lateral = (middle - wrist).normalized().cross(Vector((0.0, 0.0, 1.0)))
        # 手のひらが下なら、人差し指は親指の側（左手は右、右手は左）
        if sign * (index - pinky).dot(lateral) <= 0.0:
            return None
        return abs((index.z - pinky.z) - THUMB_SIDE_UP)

    best = None
    for candidates in (range(-180, 180, 6), None):
        if candidates is None:
            candidates = range(best[1] - 5, best[1] + 6)
        for degrees in candidates:
            value = score(degrees)
            if value is not None and (best is None or value < best[0]):
                best = (value, degrees)
    hand.rotation_euler = (0.0, math.radians(best[1]), 0.0)
    bpy.context.view_layer.update()
    return best[1]


def shape_finger(rig, side, finger, base, point, bend, sign):
    """付け根の節を point へ向け（base はその節を回さないときの姿勢。そこからいちばん少ない回転で向ける）、
    2 つ目・3 つ目の節を BEND の bend 倍だけ曲げる。"""
    names = [B + f"{side}Hand{finger}{i}" for i in (1, 2, 3)]
    second, third = BEND["thumb" if finger == "Thumb" else "finger"]
    for name, degrees in zip(names[1:], (second * bend, third * bend)):
        rig.pose.bones[name].rotation_euler = (math.radians(degrees) * sign, 0.0, 0.0)
    goal = rig.matrix_world.inverted() @ point
    turn = base.col[1].to_3d().normalized().rotation_difference((goal - base.translation).normalized())
    rig.pose.bones[names[0]].matrix = Matrix.Translation(base.translation) @ turn.to_matrix().to_4x4() @ base.to_3x3().to_4x4()
    bpy.context.view_layer.update()


def settle_finger(rig, side, finger, base, point, bend, height, points, sign):
    """その曲げ方のまま、付け根の節を向ける点の高さを二分法で決め、いちばん低い点を height に合わせる。"""
    low, high = -0.12, 0.18
    for _ in range(13):
        lift = (low + high) / 2
        shape_finger(rig, side, finger, base, point + Vector((0.0, 0.0, lift)), bend, sign)
        if finger_contact(rig, side, finger, points).z < height:
            low = lift
        else:
            high = lift
    shape_finger(rig, side, finger, base, point + Vector((0.0, 0.0, (low + high) / 2)), bend, sign)
    return finger_contact(rig, side, finger, points)


def place_finger(rig, side, finger, target, height, points, sign):
    """指先（いちばん低い点）を target の真上の height にちょうど当てる。前後のずれは曲げる量で（二分法。曲げるほど指先は
    手前へ戻る）、高さは付け根の節を向ける点の高さで合わせ、横のずれは向ける点を横へずらして直す（数回くり返す）。"""
    for i in (1, 2, 3):
        bone = rig.pose.bones[B + f"{side}Hand{finger}{i}"]
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    base = rig.pose.bones[B + f"{side}Hand{finger}1"].matrix.copy()
    knuckle = rig.matrix_world @ base.translation
    heading = Vector((target.x - knuckle.x, target.y - knuckle.y, 0.0)).normalized()
    across = Vector((-heading.y, heading.x, 0.0))
    shift = 0.0
    contact = None
    for _ in range(3):
        point = target + across * shift
        low, high = BEND_RANGE["thumb" if finger == "Thumb" else "finger"]
        for _ in range(10):
            bend = (low + high) / 2
            contact = settle_finger(rig, side, finger, base, point, bend, height, points, sign)
            if (contact - target).dot(heading) > 0.0:
                low = bend
            else:
                high = bend
        contact = settle_finger(rig, side, finger, base, point, (low + high) / 2, height, points, sign)
        miss = (target - contact).dot(across)
        shift += miss
        if abs(miss) < 0.0005:
            break
    return contact


def seat_hand(rig, side, spec, keys, wrist_e, aim_e):
    """手のひらを下へ水平にし、中指の付け根が中指のキーの KNUCKLE_BACK 手前・KNUCKLE_HEIGHT 上に来るまで手首を動かす
    （手を向ける点も一緒に動かすので、手の向きは変わらない。最後にもう一度手のひらを水平にそろえる）。"""
    yaw = math.radians(spec["yaw"])
    forward = Vector((math.sin(yaw), math.cos(yaw), 0.0))
    goal = key_top(keys[spec["Middle"]]) - forward * KNUCKLE_BACK + Vector((0.0, 0.0, KNUCKLE_HEIGHT))
    aim_e.location = wrist_e.location + forward * 0.25
    level_palm(rig, side)
    for _ in range(10):
        move = goal - rig.matrix_world @ rig.pose.bones[B + f"{side}HandMiddle1"].head
        wrist_e.location += move
        aim_e.location = wrist_e.location + forward * 0.25
        bpy.context.view_layer.update()
        if move.length < 0.0003:
            break
    roll = level_palm(rig, side)
    move = goal - rig.matrix_world @ rig.pose.bones[B + f"{side}HandMiddle1"].head
    wrist_e.location += move
    aim_e.location = wrist_e.location + forward * 0.25
    bpy.context.view_layer.update()
    return roll, forward


def place_typing_hand(rig, side, spec, keys, points, wrist_e, aim_e):
    """キーに置く手。手のひらを下へ水平にして中指の付け根をキーの手前・上に置き、指ごとに、指先がそのキーの天面の
    真ん中にちょうど当たるよう向けて曲げる（親指は受け持つキーの、人差し指の手前にいちばん近い所。
    受け持つキーのない指は外側に少し浮かせる）。"""
    finger_sign = curl_sign(rig, side, "Middle", points)
    thumb_sign = curl_sign(rig, side, "Thumb", points)
    roll, forward = seat_hand(rig, side, spec, keys, wrist_e, aim_e)
    report = {"palm_roll": roll, "fingers": {}}
    outward = Vector((-1.0 if side == "Left" else 1.0, 0.0, 0.0))
    for finger in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
        key_id = spec.get(finger)
        if finger == "Thumb" and key_id is None:
            # 受け持つキーのない親指は、人差し指のキーの手前に少し浮かせる
            target = key_top(keys[spec["Index"]]) - forward * THUMB_BELOW_INDEX
            height = target.z + HOVER
        elif finger == "Thumb":
            target = key_top_near(keys[key_id], key_top(keys[spec["Index"]]) - forward * THUMB_BELOW_INDEX)
            height = target.z + CONTACT
        elif key_id is None:
            ring = key_top(keys[spec["Ring"]])
            target = ring + outward * DESK["PITCH"]
            height = ring.z + HOVER
        else:
            target = key_top(keys[key_id])
            height = target.z + CONTACT
        contact = place_finger(rig, side, finger, target, height, points, thumb_sign if finger == "Thumb" else finger_sign)
        upper = min(segment_low(rig, side, finger, points, i).z for i in (1, 2))
        report["fingers"][finger] = {
            "target": key_id, "on": nearest_key(keys, contact),
            "off_mm": round(Vector((contact.x - target.x, contact.y - target.y)).length * 1000.0, 1),
            "height_mm": round((contact.z - target.z) * 1000.0, 1),
            "upper_clearance_mm": round((upper - target.z) * 1000.0, 1)}
    palm = min(p.z for p in posed_points(rig, points, B + f"{side}Hand"))
    report["palm_clearance_mm"] = round((palm - key_top(keys[spec["Middle"]]).z) * 1000.0, 1)
    return report


# ---------- 材質 ----------

def linear(color):
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in color)


def mat_block(name, srgb):
    """ブロックマンの体。つやを抑えた塗装の樹脂（細かいゆず肌の凹凸と、面ごとの塗りのわずかなむら）。"""
    color = linear(srgb)
    mat, nt, bsdf = DESK["_material"](name)
    tone = DESK["_noise"](nt, DESK["_coords"](nt), 6.0, detail=3.0)
    shade = DESK["_ramp"](nt, tone, [(0.3, tuple(c * 0.93 for c in color)), (0.7, tuple(min(1.0, c * 1.05) for c in color))])
    nt.links.new(shade, bsdf.inputs["Base Color"])
    peel = DESK["_noise"](nt, DESK["_coords"](nt), 1400.0, detail=2.0)
    nt.links.new(DESK["_range"](nt, peel, 0.38, 0.48), bsdf.inputs["Roughness"])
    DESK["_bump"](nt, peel, 0.05, 0.0002, bsdf)
    bsdf.inputs["Coat Weight"].default_value = 0.25
    bsdf.inputs["Coat Roughness"].default_value = 0.3
    mat.diffuse_color = (*color, 1.0)
    return mat


def mat_face():
    return DESK["mat_principled"]("PEO_Face", (0.012, 0.012, 0.014), 0.22)

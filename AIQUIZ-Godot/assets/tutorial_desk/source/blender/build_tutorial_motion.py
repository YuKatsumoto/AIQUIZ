"""机のセットの動き（段階4）。2 人が引いた椅子の前に立つ → 腰を下ろす → 椅子ごと机へ寄る → 片手をキーボードへ伸ばす。
カメラは部屋の後ろ（D1）から 2 人の頭の上（D5）まで 1 本の動きで寄る。24 fps、1〜132 コマ（5.5 秒）。最後のコマが説明画面の
準備完了の姿勢（build_tutorial_people.py が決めた、手をキーに置いた姿勢）。

ライブの Blender で、build_tutorial_desk.py・build_tutorial_people.py の後に実行する（それらを作り直したら、これもやり直す）。
    import runpy
    ns = runpy.run_path(r"G:/AIQUIZ-Main/AIQUIZ-Godot/assets/tutorial_desk/source/blender/build_tutorial_motion.py")
    result = ns["build"]()
"""
import math
import runpy
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
DESK = runpy.run_path(str(HERE / "build_tutorial_desk.py"))
PEOPLE = runpy.run_path(str(HERE / "build_tutorial_people.py"))
B = "mixamorig:"
FPS = 24
END = 132
CHAIR_Y = DESK["CHAIR_Y"]
CHAIR_BACK = DESK["CHAIR_Y_D1"]
# 拍（コマ）。立つ → 座り始め → 座り終わり → 寄り始め → 寄り終わり → 手を伸ばし終わり
STAND, SIT_START, SIT_MID, SIT_END, SCOOT_END, REACH_END = 1, 20, 38, 56, 84, 114
STAND_Y = CHAIR_BACK + 0.22
SPINE = ("Spine", "Spine1", "Spine2", "Neck", "Head")
FINGERS = ("Index", "Middle", "Ring", "Pinky", "Thumb")
# カメラの拍：(コマ, カメラの名前)。D1 → D2 → D3 → D5
CAMERA_BEATS = ((STAND, "CAM_D1"), (SIT_START, "CAM_D1"), (52, "CAM_D2"), (SCOOT_END, "CAM_D3"), (118, "CAM_D5"), (END, "CAM_D5"))


def build():
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = 1
    scene.frame_end = END
    scene.frame_set(END)
    bpy.context.view_layer.update()
    report = {}
    for tag, cfg in PEOPLE["PEOPLE"].items():
        report[tag] = animate_person(tag, cfg)
    for tag in ("P1", "P2"):
        animate_chair(f"PRP_Chair_{tag}")
    camera = animate_camera()
    scene.camera = camera
    scene.frame_set(END)
    return {"people": report, "camera": camera.name, "frames": [1, END]}


# ---------- キー ----------

def clear(obj):
    if obj.animation_data is not None:
        obj.animation_data_clear()


def key_loc(obj, frame, loc):
    obj.location = loc
    obj.keyframe_insert("location", frame=frame)


def key_bone(pose_bone, frame, rot=None, loc=None):
    if rot is not None:
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler = rot
        pose_bone.keyframe_insert("rotation_euler", frame=frame)
    if loc is not None:
        pose_bone.location = loc
        pose_bone.keyframe_insert("location", frame=frame)


# ---------- 人 ----------

def animate_person(tag, cfg):
    rig = bpy.data.objects[f"PEO_{tag}_Rig"]
    x = cfg["x"]
    pose = rig.pose.bones
    clear(rig)
    # 最後のコマの姿勢（手をキーに置いた姿勢）を覚える
    final_hips = pose[B + "Hips"].location.copy()
    final_rot = {name: pose[B + name].rotation_euler.copy() for name in SPINE}
    final_hand_roll = {side: pose[B + f"{side}Hand"].rotation_euler.copy() for side in ("Left", "Right")}
    final_fingers = {}
    for side in ("Left", "Right"):
        for finger in FINGERS:
            for i in (1, 2, 3):
                name = f"{side}Hand{finger}{i}"
                final_fingers[name] = pose[B + name].rotation_euler.copy()
    to_arm = rig.matrix_world.inverted()
    rest = rig.data.bones[B + "Hips"].matrix_local

    def hips_at(world):
        return rest.to_3x3().inverted() @ (to_arm @ Vector(world) - rest.translation)

    stand_z = rest.translation.z
    hips_keys = (
        (STAND, (x, STAND_Y, stand_z)), (SIT_START, (x, STAND_Y, stand_z - 0.01)),
        (SIT_MID, (x, STAND_Y - 0.10, stand_z - 0.20)), (SIT_END, (x, CHAIR_BACK + 0.03, 0.575)),
    )
    for frame, world in hips_keys:
        key_bone(pose[B + "Hips"], frame, loc=hips_at(world))
    key_bone(pose[B + "Hips"], SCOOT_END, loc=final_hips)
    key_bone(pose[B + "Hips"], END, loc=final_hips)
    # 背骨と頭：立って画面を見る → 座りながら前へ倒れて釣り合いをとる → 座って起きる → キーボードへかがむ
    lean = {STAND: (0, 0, 0, 0, 6), SIT_START: (0, 0, 0, 0, 6), SIT_MID: (14, 10, 6, 0, 0), SIT_END: (4, 3, 2, 2, 8),
            SCOOT_END: (5, 4, 3, 3, 10)}
    for frame, degrees in lean.items():
        for name, deg in zip(SPINE, degrees):
            key_bone(pose[B + name], frame, rot=(math.radians(deg), 0.0, 0.0))
    for frame in (REACH_END, END):
        for name in SPINE:
            key_bone(pose[B + name], frame, rot=final_rot[name])
    # 足：立っている間はかかとの下、寄るときに机の下へすべらせる
    for side, sx in (("Left", -1.0), ("Right", 1.0)):
        ankle = bpy.data.objects[f"PEO_{tag}_IK_{side}Ankle"]
        toe = bpy.data.objects[f"PEO_{tag}_IK_{side}Toe"]
        final_ankle, final_toe = ankle.location.copy(), toe.location.copy()
        clear(ankle)
        clear(toe)
        start_ankle = Vector((x + sx * 0.10, STAND_Y + 0.02, 0.075))
        start_toe = start_ankle + Vector((sx * 0.01, 0.15, -0.07))
        for frame in (STAND, SIT_END, SIT_END + 4):
            key_loc(ankle, frame, start_ankle)
            key_loc(toe, frame, start_toe)
        for frame in (SCOOT_END, END):
            key_loc(ankle, frame, final_ankle)
            key_loc(toe, frame, final_toe)
    # 腕：立っている間は体の横、座ったら膝の上、最後に使う手だけキーボードへ
    for side, sx in (("Left", -1.0), ("Right", 1.0)):
        wrist = bpy.data.objects[f"PEO_{tag}_IK_{side}Wrist"]
        aim = bpy.data.objects[f"PEO_{tag}_IK_{side}Aim"]
        pole = bpy.data.objects[f"PEO_{tag}_IK_{side}ElbowPole"]
        final_wrist, final_aim, final_pole = wrist.location.copy(), aim.location.copy(), pole.location.copy()
        uses_keys = cfg["hands"][side] != "lap"
        for obj in (wrist, aim, pole):
            clear(obj)
        hang = Vector((x + sx * 0.24, STAND_Y + 0.02, 0.80))
        hang_pole = Vector((x + sx * 0.32, STAND_Y - 0.30, 1.05))
        lap_back = Vector((x + sx * 0.10, CHAIR_BACK + 0.32, 0.63))
        lap_front = Vector((x + sx * 0.10, CHAIR_Y + 0.32, 0.63))
        lap_pole = Vector((x + sx * 0.32, CHAIR_BACK + 0.05, 0.85))
        for frame, w, p in ((STAND, hang, hang_pole), (SIT_START, hang, hang_pole), (SIT_END, lap_back, lap_pole)):
            key_loc(wrist, frame, w)
            key_loc(aim, frame, w + Vector((-sx * 0.03, 0.10, -0.06)))
            key_loc(pole, frame, p)
        scoot_wrist = lap_front if uses_keys else final_wrist
        key_loc(wrist, SCOOT_END, scoot_wrist)
        key_loc(aim, SCOOT_END, scoot_wrist + Vector((-sx * 0.03, 0.10, -0.06)) if uses_keys else final_aim)
        key_loc(pole, SCOOT_END, final_pole)
        for frame in (REACH_END, END):
            key_loc(wrist, frame, final_wrist)
            key_loc(aim, frame, final_aim)
            key_loc(pole, frame, final_pole)
        # 手のひらの向きと指：伸ばし始めは休みの姿勢、伸ばし終わりでキーに置いた形
        hand = pose[B + f"{side}Hand"]
        start_frame = SCOOT_END if uses_keys else SIT_END
        key_bone(hand, STAND, rot=(0.0, 0.0, 0.0))
        key_bone(hand, start_frame, rot=(0.0, 0.0, 0.0))
        for frame in (REACH_END, END):
            key_bone(hand, frame, rot=final_hand_roll[side])
        for finger in FINGERS:
            for i in (1, 2, 3):
                bone = pose[B + f"{side}Hand{finger}{i}"]
                relaxed = tuple(v * 0.35 for v in final_fingers[f"{side}Hand{finger}{i}"])
                key_bone(bone, STAND, rot=relaxed)
                key_bone(bone, start_frame, rot=relaxed)
                for frame in (REACH_END, END):
                    key_bone(bone, frame, rot=final_fingers[f"{side}Hand{finger}{i}"])
    return {"hips_keys": len(hips_keys) + 2}


def animate_chair(name):
    chair = bpy.data.objects[name]
    clear(chair)
    final = chair.location.copy()
    back = Vector((final.x, CHAIR_BACK, final.z))
    for frame in (STAND, SIT_END):
        key_loc(chair, frame, back)
    for frame in (SCOOT_END, END):
        key_loc(chair, frame, final)


# ---------- カメラ ----------

def animate_camera():
    """D1 → D2 → D3 → D5 を 1 本でつなぐ寄りのカメラ（CAM_Intro）。レンズの長さも拍ごとに合わせる。"""
    coll = bpy.data.collections.get("TD_Motion") or bpy.data.collections.new("TD_Motion")
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    old = bpy.data.objects.get("CAM_Intro")
    if old is not None:
        data = old.data
        bpy.data.objects.remove(old, do_unlink=True)
        bpy.data.cameras.remove(data)
    data = bpy.data.cameras.new("CAM_Intro")
    data.sensor_width = 36.0
    data.sensor_fit = "HORIZONTAL"
    data.clip_start = 0.02
    data.clip_end = 60.0
    d5 = bpy.data.objects["CAM_D5"].data
    data.dof.use_dof = d5.dof.use_dof
    data.dof.focus_object = d5.dof.focus_object
    data.dof.aperture_fstop = d5.dof.aperture_fstop
    cam = bpy.data.objects.new("CAM_Intro", data)
    coll.objects.link(cam)
    cam.rotation_mode = "QUATERNION"
    previous = None
    for frame, source in CAMERA_BEATS:
        ref = bpy.data.objects[source]
        cam.location = ref.location
        q = ref.rotation_euler.to_quaternion()
        # となりの拍と同じ側の四元数にして、間で遠回りに回らないように
        if previous is not None and q.dot(previous) < 0.0:
            q.negate()
        previous = q
        cam.rotation_quaternion = q
        cam.keyframe_insert("location", frame=frame)
        cam.keyframe_insert("rotation_quaternion", frame=frame)
        data.lens = ref.data.lens
        data.keyframe_insert("lens", frame=frame)
    return cam

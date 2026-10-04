"""ゴドーくん（Godot のロゴ形のぬいぐるみ）のアクション（24fps、各 1 本のループ）。

リグは lsb_godotkun.py: `Root`（足元。位置・向き）→ `Body`（座面の高さ。体の傾き）→ `DEF-head` / `DEF-hips`
（曲げない）→ 腕 `DEF-upper_arm/forearm/hand.L|R` と脚 `DEF-thigh/shin/foot/toe.L|R`。
頭と胴は 1 枚のメッシュなので、うなずき・見回し・居眠りの首の動きは `Body` ごと（剛体）で表す。

キーはボーンの「アーマチュア空間での回転」で指定する: R をアーマチュア空間（正面 -Y、Z 上）の 3x3 回転とし、
ボーンのレスト行列 Mb で P = Mb⁻¹ R Mb に写してポーズの四元数にする。親の回転の上に相対で乗る。
  pitch(+) = 前へ倒れる、yaw(+) = 左（+X）へ向く、roll(+) = 左へ傾く
腕と脚は chain() で「体の座標での各節の向き」から作る（腕が短いので、向きで決めたほうが手の位置を読みやすい）。
Blender 5.1: アクションはスロット付き。F カーブは action.layers[].strips[].channelbags[] から辿る。
"""
from __future__ import annotations

import math

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

FPS = 24

ARM_L = ("DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L")
ARM_R = ("DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R")
LEG_L = ("DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "DEF-toe.L")
LEG_R = ("DEF-thigh.R", "DEF-shin.R", "DEF-foot.R", "DEF-toe.R")


# ------------------------------------------------------------------ rotation helpers

def R(pitch: float = 0.0, yaw: float = 0.0, roll: float = 0.0) -> Matrix:
    """度で指定するアーマチュア空間の回転（pitch: X, roll: Y, yaw: Z）。"""
    return Euler((math.radians(pitch), math.radians(roll), math.radians(yaw)), "XYZ").to_matrix()


def rest_dir(pb: bpy.types.PoseBone) -> Vector:
    b = pb.bone
    return (b.tail_local - b.head_local).normalized()


def local_quat(pb: bpy.types.PoseBone, r_arm: Matrix) -> Quaternion:
    mb = pb.bone.matrix_local.to_3x3()
    return (mb.inverted() @ r_arm @ mb).to_quaternion()


def chain(arm, bones, dirs) -> dict:
    """節ごとの向き（体の座標。None は親に付いたまま休止の向き）から、親に対する回転を作る。"""
    out = {}
    parent = Matrix.Identity(3)
    for bone, d in zip(bones, dirs):
        pb = arm.pose.bones[bone]
        if d is None:
            r = Matrix.Identity(3)
        else:
            target = parent.inverted() @ Vector(d).normalized()
            r = rest_dir(pb).rotation_difference(target).to_matrix()
        out[bone] = r
        parent = parent @ r
    return out


def mx(v):
    """左右反転（+X が左）。"""
    return None if v is None else (-v[0], v[1], v[2])


def arms(arm, left=None, right=None) -> dict:
    """left / right: 上腕・前腕・手の向き。どちらも左側の座標で書く（right は鏡像にして右腕へ。省くと left と同じ）。"""
    out = {}
    if left is not None:
        out.update(chain(arm, ARM_L, left))
    if right is None and left is not None:
        right = [mx(d) for d in left]
    elif right is not None:
        right = [mx(d) for d in right]
    if right is not None:
        out.update(chain(arm, ARM_R, right))
    return out


def legs(arm, left, right=None) -> dict:
    out = chain(arm, LEG_L, left)
    out.update(chain(arm, LEG_R, [mx(d) for d in (right if right is not None else left)]))
    return out


class Clip:
    """1 体 1 本のアクション。key_* でキーを打ち、finish() でループ用の末尾キーと補間を整える。"""

    def __init__(self, arm: bpy.types.Object, name: str, length: int):
        self.arm = arm
        self.name = name
        self.length = length
        # データ名は書き出しの名前と別にする（作り直しで消せるように ACT_ を付ける。glTF 上の名前は NLA トラック名）
        act = bpy.data.actions.new(f"ACT_{arm.name}_{name}")
        arm.animation_data_create()
        arm.animation_data.action = act
        try:
            if arm.animation_data.action_slot is None:
                slot = act.slots.new(id_type="OBJECT", name=arm.name)
                arm.animation_data.action_slot = slot
        except (AttributeError, TypeError):
            pass
        act.use_frame_range = True
        act.frame_start = 0
        act.frame_end = length
        self.act = act
        self.keyed_rot: set[str] = set()
        self.keyed_loc: set[str] = set()
        self.keyed_scale: set[str] = set()

    # --- keys
    def rot(self, bone: str, frame: int, r_arm: Matrix) -> None:
        pb = self.arm.pose.bones[bone]
        pb.rotation_quaternion = local_quat(pb, r_arm)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        self.keyed_rot.add(bone)

    def euler(self, bone: str, frame: int, euler_xyz) -> None:
        pb = self.arm.pose.bones[bone]
        pb.rotation_euler = euler_xyz
        pb.keyframe_insert("rotation_euler", frame=frame)
        self.keyed_rot.add(bone)

    def loc(self, bone: str, frame: int, offset_arm) -> None:
        """アーマチュア空間のずれ（親なしボーン用: Root / Blade）。"""
        pb = self.arm.pose.bones[bone]
        mb = pb.bone.matrix_local.to_3x3()
        pb.location = mb.inverted() @ Vector(offset_arm)
        pb.keyframe_insert("location", frame=frame)
        self.keyed_loc.add(bone)

    def scale(self, bone: str, frame: int, s) -> None:
        pb = self.arm.pose.bones[bone]
        pb.scale = Vector(s) if not isinstance(s, (int, float)) else Vector((s, s, s))
        pb.keyframe_insert("scale", frame=frame)
        self.keyed_scale.add(bone)

    def pose(self, frame: int, rots: dict | None = None, loc=None, body: Matrix | None = None,
             root: Matrix | None = None, scales: dict | None = None) -> None:
        """rots: ボーン → 回転。body: 体の傾き（Body）。root: 足元の向き（Root）。loc: 足元の位置（Root）。"""
        for bone, r_arm in (rots or {}).items():
            self.rot(bone, frame, r_arm)
        if body is not None:
            self.rot("Body", frame, body)
        if root is not None:
            self.rot("Root", frame, root)
        if loc is not None:
            self.loc("Root", frame, loc)
        if scales:
            for bone, s in scales.items():
                self.scale(bone, frame, s)

    # --- fcurves (Blender 5.1 slotted actions)
    def fcurves(self):
        act = self.act
        adt = self.arm.animation_data
        slot = adt.action_slot
        handle = slot.handle if slot is not None else None
        curves = []
        if hasattr(act, "layers"):
            for layer in act.layers:
                for strip in layer.strips:
                    for cb in strip.channelbags:
                        if handle is None or cb.slot_handle == handle:
                            curves.extend(cb.fcurves)
        elif hasattr(act, "fcurves"):
            curves.extend(act.fcurves)
        return curves

    def set_interpolation(self, data_path_contains: str, mode: str) -> int:
        count = 0
        for fc in self.fcurves():
            if data_path_contains in fc.data_path:
                for kp in fc.keyframe_points:
                    kp.interpolation = mode
                    count += 1
        return count

    def make_cyclic(self) -> None:
        """最初のキーの値を最後のフレームにも打ち、継ぎ目を消す（最後にキーが無いカーブだけ）。"""
        for fc in self.fcurves():
            pts = fc.keyframe_points
            if len(pts) == 0:
                continue
            first = pts[0]
            last = pts[-1]
            if abs(last.co.x - self.length) > 0.5:
                fc.keyframe_points.insert(self.length, first.co.y, options={"FAST"})
            elif abs(last.co.y - first.co.y) > 1e-6:
                last.co.y = first.co.y
            fc.update()

    def finish(self) -> dict:
        self.make_cyclic()
        info = {"action": self.name, "length": self.length, "fcurves": len(self.fcurves()),
                "bones_rot": sorted(self.keyed_rot), "bones_loc": sorted(self.keyed_loc)}
        self.push_to_nla()
        return info

    def push_to_nla(self) -> None:
        """アクションを NLA トラック（名前 = クリップ名）に置き、アクティブなアクションは外す。glTF は NLA_TRACKS で
        オブジェクトごとに自分のトラックだけを書き出す（ACTIONS だと他キャラのアクションまで混ざる）。"""
        adt = self.arm.animation_data
        slot = adt.action_slot if hasattr(adt, "action_slot") else None
        track = adt.nla_tracks.new()
        track.name = self.name
        strip = track.strips.new(self.name, 0, self.act)
        strip.name = self.name
        if slot is not None and hasattr(strip, "action_slot"):
            try:
                strip.action_slot = slot
            except (AttributeError, TypeError, RuntimeError):
                pass
        strip.frame_start = 0
        strip.frame_end = self.length
        strip.action_frame_start = 0
        strip.action_frame_end = self.length
        strip.repeat = 1.0
        strip.blend_type = "REPLACE"
        strip.extrapolation = "HOLD"
        adt.action = None


# ------------------------------------------------------------------ shared poses (向きは左側、体の座標)

HANG = [(0.55, 0.05, -0.83), (0.5, -0.08, -0.86), (0.45, -0.15, -0.88)]
DESK = [(0.42, -0.86, -0.28), (0.3, -0.9, -0.3), (0.22, -0.82, -0.53)]
STAND = [None, None, None, None]
SEATED = [(0.0, -0.97, -0.25), (0.0, -0.45, -0.89), (0.0, -0.85, -0.53), (0.0, -0.95, 0.3)]
CROUCH = [(0.0, -0.5, -0.87), (0.0, 0.38, -0.93), (0.0, -0.74, -0.67), None]
TUCK = [(0.0, -0.96, -0.28), (0.0, 0.2, -0.98), (0.0, -0.6, -0.8), None]
ARMS_UP = [(0.5, -0.12, 0.86), (0.35, -0.12, 0.93), (0.25, -0.12, 0.96)]


def _idle_body(c: Clip, frame: int, sway: float, loc=(0.0, 0.0, 0.0)):
    c.pose(frame, body=R(roll=sway), loc=loc)


# ------------------------------------------------------------------ clips

def clip_teach(arm) -> dict:
    """講師 288f: 待機 → 振り向いて黒板を指し棒で 2 回叩く → 教室へ向き直っておじぎ 2 回、左手で説明 →
    両腕を上げて「ジャンプ！」の小さな跳躍 → 待機へ。黒板は背中側（講師はクラスを向いて置かれる）。"""
    c = Clip(arm, "Teach", 288)
    hang = arms(arm, HANG)
    stand = legs(arm, STAND)
    c.pose(0, {**hang, **stand}, body=R(), root=R(), loc=(0, 0, 0))
    _idle_body(c, 12, 2.0)
    _idle_body(c, 24, -1.5)
    # 振り向く（足元ごと右へ 115°）: 右手の指し棒を黒板の方へ上げる
    point = arms(arm, HANG, [(0.3, -0.82, 0.48), (0.25, -0.78, 0.58), (0.22, -0.72, 0.66)])
    c.pose(40, hang, body=R(roll=-1.0), root=R(yaw=-20.0))
    c.pose(60, point, body=R(pitch=-6.0), root=R(yaw=-115.0))
    # 指し棒で 2 回叩く（手先を小さく振り下ろす）
    tap = arms(arm, HANG, [(0.3, -0.82, 0.48), (0.25, -0.86, 0.45), (0.2, -0.9, 0.38)])
    for k, f in enumerate((72, 80, 88, 96)):
        c.pose(f, tap if k % 2 == 0 else point, body=R(pitch=-3.0 if k % 2 == 0 else -6.0))
    c.pose(112, point, body=R(pitch=-6.0), root=R(yaw=-115.0))
    # 教室へ向き直る
    c.pose(136, hang, body=R(pitch=2.0), root=R())
    # おじぎ（体ごと）2 回、左手で説明（手のひらを前へ差し出す）
    explain_a = arms(arm, [(0.55, -0.78, -0.1), (0.45, -0.85, 0.2), (0.4, -0.75, 0.5)], HANG)
    explain_b = arms(arm, [(0.75, -0.6, 0.05), (0.6, -0.7, 0.3), (0.55, -0.55, 0.6)], HANG)
    c.pose(150, explain_a, body=R(pitch=10.0))
    c.pose(158, body=R(pitch=2.0))
    c.pose(166, explain_b, body=R(pitch=10.0, roll=2.0))
    c.pose(178, body=R(pitch=0.0))
    c.pose(184, hang)
    # 「ジャンプ！」: しゃがむ → 両腕を上げて小さく跳ぶ → 着地で沈む
    c.pose(196, {**hang, **legs(arm, CROUCH)}, body=R(pitch=6.0), loc=(0, 0, -0.07))
    c.pose(204, {**arms(arm, ARMS_UP), **legs(arm, TUCK)}, body=R(pitch=-4.0), loc=(0, 0, 0.34))
    c.pose(212, {**arms(arm, ARMS_UP), **stand}, body=R(pitch=-2.0), loc=(0, 0, 0.02))
    wiggle = arms(arm, [(0.8, -0.15, 0.55), (0.7, -0.15, 0.68), (0.6, -0.15, 0.78)])
    c.pose(220, {**wiggle, **legs(arm, CROUCH)}, body=R(pitch=5.0), loc=(0, 0, -0.07))
    c.pose(236, {**hang, **stand}, body=R(pitch=0.0), loc=(0, 0, 0))
    _idle_body(c, 256, 1.5)
    _idle_body(c, 272, -1.0)
    c.pose(288, {**hang, **stand}, body=R(), root=R(), loc=(0, 0, 0))
    return c.finish()


def clip_take_notes(arm, seat_lift: float) -> dict:
    """ノートを取る生徒 192f: 黒板を見る → 前かがみで鉛筆を走らせる（6 往復）→ 顔を上げてうなずく。"""
    c = Clip(arm, "TakeNotes", 192)
    seat = (0.0, 0.0, seat_lift)
    sit = legs(arm, SEATED)
    rest_pen = [(0.3, -0.88, -0.25), (0.22, -0.88, -0.38), (0.14, -0.8, -0.58)]
    write = [(0.3, -0.88, -0.25), (0.2, -0.85, -0.45), (0.1, -0.6, -0.8)]
    desk = arms(arm, DESK, rest_pen)
    look_board = R(pitch=-4.0)
    look_note = R(pitch=9.0, yaw=-4.0)
    c.pose(0, {**desk, **sit}, body=look_board, root=R(), loc=seat)
    c.pose(30, body=R(pitch=-5.0, yaw=4.0))
    c.pose(48, arms(arm, DESK, write), body=look_note)
    # 鉛筆を走らせる: 手先を左右に小さく往復させ、体もかすかに揺らす（6 往復）
    for k in range(7):
        f = 54 + k * 11
        s = -1.0 if k % 2 == 0 else 1.0
        stroke = [write[0], write[1], (0.1 + s * 0.12, -0.6, -0.8)]
        c.pose(f, arms(arm, DESK, stroke), body=R(pitch=9.0, yaw=-4.0, roll=s * 1.2))
    c.pose(136, arms(arm, DESK, write), body=look_note)
    c.pose(154, desk, body=R(pitch=-5.0))
    c.pose(164, body=R(pitch=5.0))
    c.pose(172, body=R(pitch=-5.0))
    c.pose(180, body=R(pitch=2.0))
    c.pose(192, {**desk, **sit}, body=look_board, root=R(), loc=seat)
    return c.finish()


def clip_raise_hand(arm, seat_lift: float) -> dict:
    """挙手する生徒 240f: 待機 → 右手を高く挙げて振る（座面で弾む）→ 下ろす → 左右を見回す。"""
    c = Clip(arm, "RaiseHand", 240)
    seat = Vector((0.0, 0.0, seat_lift))
    sit = legs(arm, SEATED)
    desk = arms(arm, DESK)
    c.pose(0, {**desk, **sit}, body=R(pitch=-3.0), root=R(), loc=seat)
    c.pose(40, body=R(pitch=-3.0, yaw=7.0, roll=2.0))
    c.pose(72, desk, body=R(pitch=-3.0))
    # 挙手（予備で少し沈んでから一気に）。腕が短いので横の歯に当たらないよう外・前へ開いて挙げる
    c.pose(80, body=R(pitch=5.0), loc=seat - Vector((0, 0, 0.02)))
    up = [(0.68, -0.3, 0.67), (0.45, -0.3, 0.84), (0.3, -0.28, 0.91)]
    raised = arms(arm, DESK, up)
    c.pose(94, raised, body=R(pitch=-5.0, roll=5.0), loc=seat + Vector((0, 0, 0.05)))
    c.pose(102, body=R(pitch=-4.0, roll=4.0), loc=seat)
    # 手を振る（前腕から先を左右へ）と座面で弾む
    for k in range(6):
        f = 108 + k * 8
        s = 1.0 if k % 2 == 0 else -1.0
        wave = [up[0], (0.45 + s * 0.3, -0.3, 0.8), (0.3 + s * 0.42, -0.28, 0.82)]
        c.pose(f, arms(arm, DESK, wave), loc=seat + Vector((0, 0, 0.03 if k % 2 == 0 else 0.0)))
    c.pose(160, raised, body=R(pitch=-4.0, roll=4.0), loc=seat)
    # 下ろす
    c.pose(180, desk, body=R(pitch=-3.0))
    # 見回す（体ごと）
    c.pose(196, body=R(pitch=-2.0, yaw=20.0))
    c.pose(214, body=R(pitch=-2.0, yaw=-17.0))
    c.pose(230, body=R(pitch=-3.0))
    c.pose(240, {**desk, **sit}, body=R(pitch=-3.0), root=R(), loc=seat)
    return c.finish()


def clip_doze(arm, seat_lift: float) -> dict:
    """居眠りする生徒 216f: 体ごとゆっくり前へ垂れる（Zzz が出る）→ はっと起きる → 見回す → また垂れる。"""
    c = Clip(arm, "Doze", 216)
    seat = Vector((0.0, 0.0, seat_lift))
    sit = legs(arm, SEATED)
    desk = arms(arm, [(0.4, -0.85, -0.34), (0.3, -0.88, -0.37), (0.2, -0.8, -0.57)])
    c.pose(0, {**desk, **sit}, body=R(pitch=5.0), root=R(), loc=seat, scales={"Zzz": 0.3})
    c.pose(36, body=R(pitch=10.0, roll=3.0), scales={"Zzz": 0.7})
    c.pose(60, body=R(pitch=14.0, roll=4.0), scales={"Zzz": 1.0})
    c.pose(72, body=R(pitch=11.0, roll=3.5), scales={"Zzz": 1.0})
    c.pose(96, body=R(pitch=18.0, roll=5.0), scales={"Zzz": 1.2})
    # はっと起きる: 体を跳ね起こして座面で小さく跳ね、腕がびくっと開く。Zzz が消える
    startle = arms(arm, [(0.75, -0.45, 0.1), (0.7, -0.4, 0.3), (0.6, -0.35, 0.5)])
    c.pose(104, startle, body=R(pitch=-7.0, roll=-2.0), loc=seat + Vector((0, 0, 0.05)), scales={"Zzz": 0.0})
    c.pose(112, desk, body=R(pitch=-3.0), loc=seat, scales={"Zzz": 0.0})
    # 見回す（誰も見てないよね）
    c.pose(126, body=R(pitch=-2.0, yaw=22.0))
    c.pose(142, body=R(pitch=-2.0, yaw=-19.0))
    c.pose(158, body=R(pitch=0.0), scales={"Zzz": 0.0})
    # また垂れ始める（ループの先頭へつながる姿勢）
    c.pose(190, body=R(pitch=3.0), scales={"Zzz": 0.1})
    c.pose(216, {**desk, **sit}, body=R(pitch=5.0), root=R(), loc=seat, scales={"Zzz": 0.3})
    return c.finish()


def clip_practice(arm, rail_y0: float, rail_y1: float, blade_r: float) -> dict:
    """練習生 120f: 刃がレールを手前（+Y）へ走る（0→96f）。練習生は予備動作 → 刃が足元を通る 51f を頂点に
    刃の真上を跳び越える（胴の底が刃の上 0.3 m 以上）→ 着地の沈み → 「ふう」と腕を振って体を揺らす → 構え直す。
    Blade ボーンの位置はアーマチュア空間で y を進める。"""
    c = Clip(arm, "Practice", 120)
    ready_arms = arms(arm, [(0.78, -0.25, -0.57), (0.7, -0.35, -0.62), (0.6, -0.45, -0.66)])
    knees = legs(arm, [(0.0, -0.25, -0.97), (0.0, 0.2, -0.98), (0.0, -0.74, -0.67), None])
    ready = {**ready_arms, **knees}
    c.pose(0, ready, body=R(pitch=4.0), root=R(), loc=(0, 0, -0.02))
    c.pose(24, body=R(pitch=4.0, yaw=5.0))
    # 予備動作: 深くしゃがんで腕を後ろへ
    back_arms = arms(arm, [(0.55, 0.55, -0.63), (0.45, 0.65, -0.62), (0.4, 0.7, -0.6)])
    c.pose(31, {**back_arms, **legs(arm, CROUCH)}, body=R(pitch=10.0), loc=(0, 0, -0.08))
    # 踏み切り → 空中（脚を抱える、体を少し前へ回す）→ 着地
    c.pose(36, {**arms(arm, ARMS_UP), **legs(arm, STAND)}, body=R(pitch=-4.0), loc=(0, 0, 0.35))
    c.pose(41, {**legs(arm, TUCK)}, body=R(pitch=4.0), loc=(0, 0, 0.85))
    c.pose(51, {**arms(arm, [(0.7, -0.2, 0.68), (0.55, -0.2, 0.81), (0.45, -0.2, 0.87)])},
           body=R(pitch=10.0), loc=(0, 0, 1.1))
    c.pose(59, body=R(pitch=6.0), loc=(0, 0, 0.82))
    c.pose(64, {**arms(arm, [(0.85, -0.2, 0.3), (0.8, -0.25, 0.4), (0.7, -0.3, 0.5)]), **legs(arm, STAND)},
           body=R(pitch=0.0), loc=(0, 0, 0.4))
    c.pose(68, {**legs(arm, CROUCH)}, body=R(pitch=9.0), loc=(0, 0, -0.08))
    c.pose(78, ready, body=R(pitch=3.0), loc=(0, 0, -0.02))
    # 「ふう」: 両腕をぱたぱた、体を左右に揺らす
    flap_a = arms(arm, [(0.85, -0.3, 0.1), (0.8, -0.35, 0.3), (0.7, -0.4, 0.45)])
    flap_b = arms(arm, [(0.7, -0.3, -0.45), (0.6, -0.35, -0.6), (0.5, -0.4, -0.7)])
    for k, f in enumerate((86, 92, 98, 104)):
        c.pose(f, flap_a if k % 2 == 0 else flap_b, body=R(roll=5.0 if k % 2 == 0 else -5.0, pitch=-3.0))
    c.pose(120, ready, body=R(pitch=4.0), root=R(), loc=(0, 0, -0.02))
    # 刃: 0→96f で手前へ、97f で奥へ戻って待機。回転は X 軸まわりに連続
    c.loc("Blade", 0, (0.0, 0.0, 0.0))
    c.loc("Blade", 96, (0.0, rail_y1 - rail_y0, 0.0))
    c.loc("Blade", 98, (0.0, 0.0, 0.0))
    c.loc("Blade", 120, (0.0, 0.0, 0.0))
    turns = 11.25  # 16 歯: 1 コマ 33.75° = 歯の対称角 22.5° の 1.5 倍（ストロボを避ける）。11.25 回転 = 180 歯で継ぎ目なし
    c.euler("Blade", 0, (0.0, 0.0, 0.0))
    c.euler("Blade", 120, (-math.tau * turns, 0.0, 0.0))
    c.set_interpolation('pose.bones["Blade"]', "LINEAR")
    return c.finish()

"""練習（チュートリアル）の案内役のハテナの動きをライブの Blender で作って書き出す（docs/new_tutorial/phase9_design.md 1章）。

aiquiz_mascot.blend を開いて実行する（Higgsfield の Blender 連携 bl_execute から runpy）：
  import runpy, sys
  sys.argv = ["blender", "--"]          # 書き出さないなら ["blender", "--", "--no-export"]、確認の絵も撮るなら "--preview" を足す
  runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/build_practice_mascot.py", run_name="__main__")

作るもの（mascot_model.glb は変えない）：Rig のアクション 16 本 → ../mascot_practice.glb（骨組みとアクションだけ、メッシュなし）
  Practice_OpenArms  2.0 秒のループ。両手を広げて見せる（ようこそ・紹介）
  Practice_Proud     2.0 秒のループ。腰に手を当てて胸をはる
  Practice_Cross     1.6 秒のループ。両手を前に出して「だめ」、首を2回ふって止まる（赤い × の文字は Godot 側で重ねる）
  Practice_Tilt      2.0 秒のループ。右手をほおに当てて首をかしげる（ヒント・注意）
  Practice_Oops      2.0 秒のループ。左手を頭の横に当てて、うなだれる（あちゃー。失敗したとき）
  Practice_Nod       1.6 秒のループ。2 回うなずいて止まる
  Practice_Hop       0.6 秒のループ。跳んでいる間：ひざを曲げ、両手を上げてつり合いをとる（位置は Godot が動かす）
  Practice_Land      0.4 秒（ループしない）。着地：ひざを曲げて受け止め、立ち姿へ戻る
  Practice_Ride      2.4 秒のループ。雲の上：ひざを軽く曲げ、両手を横に出して、ゆっくりつり合いをとる
  （2026-10-26 追加。席へ戻る・席を離れる・ヘリに乗り降りする動き）
  Practice_Walk      0.8 秒のループ（2 歩）。腕を振って歩く
  Practice_DuckWalk  0.8 秒のループ。かがんで歩く（ヘリのドアをくぐる）
  Practice_Step      0.45 秒。右足から段を上がる・下りる（位置は Godot が動かす）
  Practice_SitDown   0.55 秒。かがんで両手を後ろへのばし、お尻から座って脚を前へ出す（終わりは Pilot_SitIdle と同じ「ぬいぐるみ座り」）
  Practice_StandUp   0.5 秒。座った姿から前へかがみ、座面を押して立ち上がる
  Practice_PushUp    0.8 秒。右手でヘリのドア（上へ開くガルウィング）を押し上げる
  Practice_PullDown  0.8 秒。右手でドアのふちをつかみ、引き下ろして閉める
姿勢の決め方は build_stand_mascot.py と同じ（ハテナの空間 = glTF：x 左右（+x が本人の左）、y 上、z 前）。ただし腕の向きは
体（DEF-head）の空間で決め、体を傾けると腕もいっしょに傾く。手の位置で決めたいときは arm_ik（2 本の骨の IK）を使う。
腕は短い（上腕 0.159・前腕 0.137・手 0.137 m）ので、体の前で腕を交差させたり、頭の上で手を合わせたりはできない。
--preview：アクションごとに正面と斜めから数コマ撮って artifacts/practice_mascot/ に置く（PNG。合わせた一覧は呼ぶ側で作る）。
最後の行 PRACTICE_MASCOT {...} に結果。.blend の保存は呼ぶ側で行う（AGENTS.md）。
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = Path(__file__).resolve().parent
ASSET = HERE.parent
PROJECT = ASSET.parent.parent.parent
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
DO_PREVIEW = "--preview" in ARGS
PREVIEW_DIR = PROJECT / "artifacts" / "practice_mascot"
FPS = 24
TAU = math.tau

# 腕の向き（体の空間）。休みは体の横に下ろす。
ARM_REST_UPPER = (0.80, -0.55, 0.05)
ARM_REST_FORE = (0.70, -0.70, 0.12)
# 腕の骨（体の空間の位置。glTF の向き）と長さ
SHOULDER = {"L": Vector((0.52, 0.819, 0.0)), "R": Vector((-0.52, 0.819, 0.0))}
UPPER_LEN = 0.159
FORE_LEN = 0.137
ARM_BONES = ("DEF-upper_arm", "DEF-forearm", "DEF-hand")


def g2b(v):
    """ハテナの空間（glTF、Y 上・前 +Z）→ Blender のアーマチュア空間（Z 上・前 -Y）。"""
    return Vector((v[0], -v[2], v[1]))


def _depth(pb):
    d = 0
    while pb.parent is not None:
        d += 1
        pb = pb.parent
    return d


def two_bone(root, target, l1, l2, pole):
    to = target - root
    d = min(max(to.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    axis = to.normalized()
    cos_a = (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    perp = pole - axis * pole.dot(axis)
    if perp.length < 1e-5:
        perp = axis.orthogonal()
    perp.normalize()
    joint = root + axis * (l1 * cos_a) + perp * (l1 * sin_a)
    end = root + axis * d
    return (joint - root).normalized(), (end - joint).normalized()


def arm_ik(side, wrist, pole, hand=None):
    """side の腕で、手首（体の空間の点。glTF）へ届く上腕・前腕の向き。pole はひじを出す向き。
    hand は手の向き（省略すると前腕の続き）。返り値は aims に足す辞書。"""
    upper, fore = two_bone(SHOULDER[side], Vector(wrist), UPPER_LEN, FORE_LEN, Vector(pole))
    aims = {"DEF-upper_arm." + side: tuple(upper), "DEF-forearm." + side: tuple(fore)}
    if hand is not None:
        aims["DEF-hand." + side] = hand
    return aims


class Poser:
    def __init__(self, rig):
        self.rig = rig
        self.bones = rig.data.bones
        self.leg = {}
        self.foot = {}
        for s in ("L", "R"):
            thigh = self.bones["DEF-thigh." + s]
            shin = self.bones["DEF-shin." + s]
            foot = self.bones["DEF-foot." + s]
            self.leg[s] = (thigh.head_local.copy(), shin.head_local.copy(), shin.tail_local.copy())
            self.foot[s] = (foot.tail_local - foot.head_local).normalized()

    def pose(self, aims: dict, body_lift=0.0, hips_lift=0.0, sway=0.0, tilt=0.0, nod=0.0, yaw=0.0, feet_lift=0.0,
             feet=None, legs=None, legs_weight=1.0):
        """aims: 腕の骨 → 体の空間の向き。body/hips_lift は上下（m）、sway は左右（m）、
        tilt は前から見た体の傾き（rad。+ で本人の左へ）、nod は体のうなずき（rad。+ で前へ）、
        yaw は体のひねり（rad。+ で本人の左を向く）。feet_lift は両足を浮かせる高さ（m。ひざが曲がる）。
        feet：足ごとのずれ {"L": (前 m, 上 m), "R": …}（歩く・段を上がる）。
        legs：脚の骨の向き（アーマチュア空間。build_pilot.py の SEATED と同じ書き方）。IK の脚と legs_weight で混ぜる（座る）。"""
        rig = self.rig
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion()
            pb.location = (0.0, 0.0, 0.0)
            pb.scale = (1.0, 1.0, 1.0)
        bpy.context.view_layer.update()
        # 体の玉は腰（DEF-hips）と体（DEF-head）にまたがってウェイトが付いているので、2 本を同じだけ回して玉を曲げない
        # （体だけを大きく回すと、玉の腰のあたりにしわが出た）。脚は足首を床に置いたまま IK で付いていく。
        turn = Quaternion((0.0, 0.0, 1.0), yaw) @ Quaternion((0.0, 1.0, 0.0), tilt) @ Quaternion((1.0, 0.0, 0.0), nod)
        offset = {"DEF-head": (Vector((sway, 0.0, body_lift)), turn), "DEF-hips": (Vector((sway, 0.0, hips_lift)), turn)}
        for name, (move, rot) in offset.items():
            pb = rig.pose.bones[name]
            rest = pb.bone.matrix_local
            pb.matrix = Matrix.Translation(rest.translation + move) @ rot.to_matrix().to_4x4() @ rest.to_3x3().to_4x4()
        bpy.context.view_layer.update()
        # 脚：股関節は腰について動き、足首は床（feet_lift だけ浮く）に置いたまま。
        legs_out = {}
        hips = rig.pose.bones["DEF-hips"]
        hip_m = hips.matrix @ hips.bone.matrix_local.inverted()
        for s in ("L", "R"):
            hip, knee, ankle = self.leg[s]
            hip_now = hip_m @ hip
            l1, l2 = (knee - hip).length, (ankle - knee).length
            ahead, lift = (feet or {}).get(s, (0.0, 0.0))
            target = ankle + Vector((sway * 0.4, -ahead, feet_lift + lift))
            upper, lower = two_bone(hip_now, target, l1, l2, Vector((0.0, -1.0, 0.0)))
            ik = {"DEF-thigh." + s: upper, "DEF-shin." + s: lower, "DEF-foot." + s: self.foot[s]}  # feet stay flat
            for name, direction in ik.items():
                if legs is not None and name in legs and legs_weight > 0.0:
                    direction = direction.lerp(g2b(legs[name]).normalized(), legs_weight).normalized()
                legs_out[name] = direction
        body = turn.to_matrix()
        for pb in sorted(rig.pose.bones, key=_depth):
            want = None
            if pb.name in legs_out:
                want = legs_out[pb.name]
            elif pb.name in aims:
                want = (body @ g2b(aims[pb.name])).normalized()
            if want is None:
                continue
            m = pb.matrix.copy()
            cur = m.to_3x3().col[1].normalized()
            rot = cur.rotation_difference(want).to_matrix()
            new = (rot @ m.to_3x3()).to_4x4()
            new.translation = m.translation
            pb.matrix = new
            bpy.context.view_layer.update()


def key_all(rig, frame):
    for pb in rig.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)
        if pb.name in ("DEF-head", "DEF-hips"):
            pb.keyframe_insert("location", frame=frame, group=pb.name)


def make_action(poser, name, seconds, pose_at, cyclic=True):
    rig = poser.rig
    old = bpy.data.actions.get(name)
    if old is not None:
        bpy.data.actions.remove(old)
    if rig.animation_data is None:
        rig.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    frames = max(2, round(seconds * FPS))
    for f in range(frames + 1):
        # ループする動きは最後のコマを最初と同じ姿勢にする
        t = (f % frames if cyclic else f) / FPS
        poser.pose(**pose_at(t))
        key_all(rig, f + 1)
    action.frame_range = (1, frames + 1)
    try:
        action.use_cyclic = cyclic
    except AttributeError:
        pass
    rig.animation_data.action = None
    return action


def arms(left_upper, left_fore, right_upper=None, right_fore=None):
    """左腕の向きを渡し、右腕は省略すると左右反転。"""
    if right_upper is None:
        right_upper = (-left_upper[0], left_upper[1], left_upper[2])
        right_fore = (-left_fore[0], left_fore[1], left_fore[2])
    return {"DEF-upper_arm.L": left_upper, "DEF-forearm.L": left_fore,
            "DEF-upper_arm.R": right_upper, "DEF-forearm.R": right_fore}


def side_arm(side, upper, fore):
    """片方の腕（向きは本人の左の腕で書き、右なら左右反転）。"""
    if side == "R":
        upper = (-upper[0], upper[1], upper[2])
        fore = (-fore[0], fore[1], fore[2])
    return {"DEF-upper_arm." + side: upper, "DEF-forearm." + side: fore}


def mix(a, b, w):
    return tuple(Vector(a).normalized().lerp(Vector(b).normalized(), w))


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


# 跳んでいる間の腕（Practice_Hop と、着地の始まり）
HOP_UPPER = (0.62, 0.70, 0.18)
HOP_FORE = (0.45, 0.85, 0.20)
HOP_FEET = 0.15
# 座った姿（build_pilot.py の SEATED と同じ「ぬいぐるみ座り」。座る動きの終わりを操縦士の Pilot_SitIdle にそろえる）
SEATED = {
    "DEF-thigh.L": (0.05, 0.16, 1.0), "DEF-thigh.R": (-0.05, 0.16, 1.0),
    "DEF-shin.L": (0.04, 0.02, 1.0), "DEF-shin.R": (-0.04, 0.02, 1.0),
    "DEF-foot.L": (0.0, 0.95, 0.30), "DEF-foot.R": (0.0, 0.95, 0.30),
}
SEATED_UPPER = (0.42, -0.30, 0.86)
SEATED_FORE = (0.05, 0.12, 1.0)
# 歩く：1 歩の足の前後の振り幅（m。片側）、足を上げる高さ（m）
WALK_SWING = 0.12
WALK_LIFT = 0.07


def build_actions(poser):
    def open_arms(t):
        p = t / 2.0
        breathe = 0.5 - 0.5 * math.cos(TAU * p)
        bob = 0.02 * (0.5 - 0.5 * math.cos(TAU * 2.0 * p))
        a = arms((0.80, 0.22 + 0.10 * breathe, 0.50), (0.62, 0.38 + 0.12 * breathe, 0.62))
        return {"aims": a, "body_lift": -bob, "hips_lift": -bob, "nod": -0.07 - 0.03 * breathe,
                "tilt": 0.03 * math.sin(TAU * p)}

    def proud(t):
        p = t / 2.0
        bob = 0.015 * (0.5 - 0.5 * math.cos(TAU * 2.0 * p))
        sway = math.sin(TAU * p)
        a = {}
        for s, sign in (("L", 1.0), ("R", -1.0)):
            # 手首を腰の横（体の玉の下のほうの横）に置き、ひじは外へうしろへ張る
            a.update(arm_ik(s, (0.50 * sign, 0.645, -0.05), (sign, 0.1, -0.6), (-0.60 * sign, -0.20, 0.50)))
        return {"aims": a, "body_lift": 0.01 - bob, "hips_lift": -bob, "nod": -0.13, "yaw": 0.06 * sway,
                "tilt": -0.03 * sway}

    def cross(t):
        p = t / 1.6
        # はじめの半分で首を 2 回ふって、あとは止まる
        k = min(p / 0.5, 1.0)
        shake = 0.22 * math.sin(TAU * 2.0 * k) * (1.0 - k) ** 0.7 if p < 0.5 else 0.0
        push = 0.5 - 0.5 * math.cos(TAU * p)
        a = arms((0.42, -0.02 + 0.04 * push, 0.90), (0.18, 0.66, 0.73))
        return {"aims": a, "yaw": shake, "nod": 0.05, "body_lift": -0.01 * push, "hips_lift": -0.01 * push}

    def tilt(t):
        p = t / 2.0
        wobble = math.sin(TAU * p)
        a = side_arm("L", ARM_REST_UPPER, ARM_REST_FORE)
        # 右手をほお（体の玉の右の横、少し前）に当てる。ひじは下へ
        a.update(arm_ik("R", (-0.60, 1.00 + 0.01 * wobble, 0.20), (-0.4, -1.0, 0.3), (0.45, 0.60, 0.35)))
        return {"aims": a, "tilt": -0.30 - 0.04 * wobble, "nod": -0.03, "yaw": -0.05}

    def oops(t):
        p = t / 2.0
        # はじめの 0.3 秒でがくっとうなだれ、そのあとは小さく首をふる
        drop = smooth(t / 0.3)
        shake = 0.06 * math.sin(TAU * 2.0 * p) * drop
        a = side_arm("R", (0.62, -0.78, 0.10), (0.55, -0.82, 0.18))
        a.update(arm_ik("L", (0.60, 1.08, 0.12), (0.6, -0.4, 0.6), (-0.35, 0.60, 0.50)))
        return {"aims": a, "nod": 0.20 * drop, "tilt": 0.08 * drop, "yaw": shake,
                "body_lift": -0.03 * drop, "hips_lift": -0.02 * drop}

    def nod(t):
        # 0.4 秒のうなずきを 2 回、そのあとは止まる
        dip = math.sin(math.pi * (t % 0.4) / 0.4) if t < 0.8 else 0.0
        a = arms((0.78, -0.55, 0.20), (0.62, -0.62, 0.40))
        return {"aims": a, "nod": 0.04 + 0.20 * dip, "body_lift": -0.02 * dip, "hips_lift": -0.01 * dip}

    def hop(t):
        p = t / 0.6
        flutter = 0.08 * math.sin(TAU * p)
        a = arms((HOP_UPPER[0], HOP_UPPER[1] + flutter, HOP_UPPER[2]), (HOP_FORE[0], HOP_FORE[1] + flutter, HOP_FORE[2]))
        return {"aims": a, "feet_lift": HOP_FEET, "nod": -0.06}

    def land(t):
        p = t / 0.4
        # 0.1 秒でいちばん深くかがみ、そのあと立ち姿へ戻る
        crouch = smooth(p / 0.25) if p < 0.25 else 1.0 - smooth((p - 0.25) / 0.75)
        feet = HOP_FEET * (1.0 - smooth(p / 0.15))
        out_u, out_f = (0.85, -0.10, 0.30), (0.75, -0.05, 0.45)
        w_out = smooth(p / 0.25)
        w_rest = smooth((p - 0.3) / 0.7)
        upper = mix(mix(HOP_UPPER, out_u, w_out), ARM_REST_UPPER, w_rest)
        fore = mix(mix(HOP_FORE, out_f, w_out), ARM_REST_FORE, w_rest)
        a = arms(upper, fore)
        return {"aims": a, "feet_lift": feet, "body_lift": -0.13 * crouch, "hips_lift": -0.12 * crouch,
                "nod": -0.06 * (1.0 - w_out) + 0.12 * crouch}

    def ride(t):
        p = t / 2.4
        see = math.sin(TAU * p)
        a = arms((0.88, -0.18 + 0.12 * see, 0.22), (0.80, -0.08 + 0.14 * see, 0.32),
                 (-0.88, -0.18 - 0.12 * see, 0.22), (-0.80, -0.08 - 0.14 * see, 0.32))
        return {"aims": a, "tilt": 0.05 * see, "sway": 0.015 * see, "body_lift": -0.035, "hips_lift": -0.035,
                "nod": -0.04}

    def walk_feet(p, swing, lift):
        """p：0〜1（1 周で 2 歩）。左足は前半に宙を前へ振り、後半は床についたまま後ろへ送る（右足は半周ずれる）。"""
        feet = {}
        for side, offset in (("L", 0.0), ("R", 0.5)):
            q = (p + offset) % 1.0
            if q < 0.5:
                k = q / 0.5
                feet[side] = (-swing + 2.0 * swing * smooth(k), lift * math.sin(math.pi * k))
            else:
                k = (q - 0.5) / 0.5
                feet[side] = (swing - 2.0 * swing * k, 0.0)
        return feet

    def walk(t):
        p = t / 0.8
        feet = walk_feet(p, WALK_SWING, WALK_LIFT)
        ahead = feet["L"][0] / WALK_SWING  # + で左足が前（右腕が前）
        a = arms((0.76, -0.60, 0.10 - 0.42 * ahead), (0.60, -0.70, 0.25 - 0.42 * ahead),
                 (-0.76, -0.60, 0.10 + 0.42 * ahead), (-0.60, -0.70, 0.25 + 0.42 * ahead))
        # 足がすれ違うとき（p = 0.25・0.75）にいちばん高い
        bob = -0.02 + 0.03 * (0.5 + 0.5 * math.cos(2.0 * TAU * (p - 0.25)))
        return {"aims": a, "feet": feet, "body_lift": bob, "hips_lift": bob, "tilt": -0.04 * math.sin(TAU * p),
                "yaw": -0.05 * ahead, "nod": 0.05}

    def duck_walk(t):
        p = t / 0.8
        feet = walk_feet(p, WALK_SWING * 0.7, WALK_LIFT * 0.7)
        ahead = feet["L"][0] / (WALK_SWING * 0.7)
        a = arms((0.62, -0.45, 0.62 - 0.15 * ahead), (0.35, -0.40, 0.85 - 0.10 * ahead),
                 (-0.62, -0.45, 0.62 + 0.15 * ahead), (-0.35, -0.40, 0.85 + 0.10 * ahead))
        low = -0.18 + 0.015 * (0.5 + 0.5 * math.cos(2.0 * TAU * (p - 0.25)))
        return {"aims": a, "feet": feet, "body_lift": low, "hips_lift": low, "nod": 0.32, "tilt": -0.03 * math.sin(TAU * p)}

    def step(t):
        # 右足を上げて前へ置き、左足が追いつく（台・段の上り下り。位置は Godot が動かす）
        p = min(t / 0.45, 1.0)
        lead_lift = 0.15 * math.sin(math.pi * min(p / 0.5, 1.0))
        trail_lift = 0.12 * math.sin(math.pi * min(max((p - 0.5) / 0.5, 0.0), 1.0))
        feet = {"R": (0.12 * math.sin(math.pi * p), lead_lift), "L": (-0.12 * math.sin(math.pi * p), trail_lift)}
        lean = math.sin(math.pi * p)
        a = arms((0.82, -0.35 + 0.10 * lean, 0.15), (0.70, -0.40 + 0.15 * lean, 0.30))
        return {"aims": a, "feet": feet, "nod": 0.12 * lean, "body_lift": 0.02 * lean, "hips_lift": 0.02 * lean}

    def sit_down(t):
        # かがんで両手を後ろの座面へのばし、お尻から座って、脚を前へ出す（終わりは操縦士の Pilot_SitIdle と同じ姿）
        p = min(t / 0.55, 1.0)
        crouch = math.sin(math.pi * min(p / 0.7, 1.0))
        w = smooth((p - 0.25) / 0.6)
        back_u, back_f = (0.70, -0.50, -0.45), (0.55, -0.70, -0.30)
        upper = mix(mix(ARM_REST_UPPER, back_u, min(crouch * 1.4, 1.0)), SEATED_UPPER, w)
        fore = mix(mix(ARM_REST_FORE, back_f, min(crouch * 1.4, 1.0)), SEATED_FORE, w)
        a = arms(upper, fore)
        return {"aims": a, "legs": SEATED, "legs_weight": w, "body_lift": -0.10 * crouch * (1.0 - w),
                "hips_lift": -0.10 * crouch * (1.0 - w), "nod": 0.14 * crouch * (1.0 - w)}

    def stand_up(t):
        # 座った姿から、前へかがんで両手で座面を押し、立ち上がる
        p = min(t / 0.5, 1.0)
        w = 1.0 - smooth(p / 0.55)
        lean = math.sin(math.pi * min(p / 0.85, 1.0))
        push_u, push_f = (0.75, -0.60, -0.15), (0.55, -0.80, 0.05)
        settle = smooth((p - 0.55) / 0.45)
        upper = mix(mix(SEATED_UPPER, push_u, smooth(p / 0.35)), ARM_REST_UPPER, settle)
        fore = mix(mix(SEATED_FORE, push_f, smooth(p / 0.35)), ARM_REST_FORE, settle)
        a = arms(upper, fore)
        return {"aims": a, "legs": SEATED, "legs_weight": w, "nod": 0.22 * lean, "body_lift": -0.06 * lean,
                "hips_lift": -0.06 * lean}

    rest_r_u = (-ARM_REST_UPPER[0], ARM_REST_UPPER[1], ARM_REST_UPPER[2])
    rest_r_f = (-ARM_REST_FORE[0], ARM_REST_FORE[1], ARM_REST_FORE[2])
    reach_u, reach_f = (-0.25, 0.55, 0.80), (-0.15, 0.70, 0.70)
    high_u, high_f = (-0.20, 0.92, 0.35), (-0.10, 0.98, 0.18)
    low_u, low_f = (-0.30, -0.10, 0.95), (-0.15, -0.25, 0.95)

    def push_up(t):
        # 右手を前の上へのばし、ヘリのドア（上へ開くガルウィング）を押し上げて、手を下ろす
        p = min(t / 0.8, 1.0)
        up, lift, down = smooth(p / 0.35), smooth((p - 0.35) / 0.3), smooth((p - 0.75) / 0.25)
        a = side_arm("L", ARM_REST_UPPER, ARM_REST_FORE)
        a["DEF-upper_arm.R"] = mix(mix(mix(rest_r_u, reach_u, up), high_u, lift), rest_r_u, down)
        a["DEF-forearm.R"] = mix(mix(mix(rest_r_f, reach_f, up), high_f, lift), rest_r_f, down)
        stretch = lift * (1.0 - down)
        return {"aims": a, "nod": -0.10 * stretch, "body_lift": 0.03 * stretch, "hips_lift": 0.03 * stretch,
                "tilt": -0.05 * stretch}

    def pull_down(t):
        # 右手を上へのばしてドアのふちをつかみ、手前の下へ引いて閉め、手を下ろす
        p = min(t / 0.8, 1.0)
        up, pull, down = smooth(p / 0.25), smooth((p - 0.3) / 0.35), smooth((p - 0.75) / 0.25)
        a = side_arm("L", ARM_REST_UPPER, ARM_REST_FORE)
        a["DEF-upper_arm.R"] = mix(mix(mix(rest_r_u, high_u, up), low_u, pull), rest_r_u, down)
        a["DEF-forearm.R"] = mix(mix(mix(rest_r_f, high_f, up), low_f, pull), rest_r_f, down)
        reach = up * (1.0 - pull)
        return {"aims": a, "nod": -0.08 * reach + 0.10 * pull * (1.0 - down), "body_lift": 0.03 * reach,
                "hips_lift": 0.03 * reach}

    return [make_action(poser, "Practice_OpenArms", 2.0, open_arms), make_action(poser, "Practice_Proud", 2.0, proud),
            make_action(poser, "Practice_Cross", 1.6, cross), make_action(poser, "Practice_Tilt", 2.0, tilt),
            make_action(poser, "Practice_Oops", 2.0, oops), make_action(poser, "Practice_Nod", 1.6, nod),
            make_action(poser, "Practice_Hop", 0.6, hop), make_action(poser, "Practice_Land", 0.4, land, cyclic=False),
            make_action(poser, "Practice_Ride", 2.4, ride),
            make_action(poser, "Practice_Walk", 0.8, walk), make_action(poser, "Practice_DuckWalk", 0.8, duck_walk),
            make_action(poser, "Practice_Step", 0.45, step, cyclic=False),
            make_action(poser, "Practice_SitDown", 0.55, sit_down, cyclic=False),
            make_action(poser, "Practice_StandUp", 0.5, stand_up, cyclic=False),
            make_action(poser, "Practice_PushUp", 0.8, push_up, cyclic=False),
            make_action(poser, "Practice_PullDown", 0.8, pull_down, cyclic=False)]


# 確認の絵で撮る時刻（秒）
PREVIEW_TIMES = {"Practice_OpenArms": [0.0, 1.0], "Practice_Proud": [0.0, 1.0], "Practice_Cross": [0.12, 1.0],
                 "Practice_Tilt": [0.0, 1.0], "Practice_Oops": [0.4, 1.4], "Practice_Nod": [0.2, 1.2],
                 "Practice_Hop": [0.0, 0.3], "Practice_Land": [0.1, 0.4], "Practice_Ride": [0.6, 1.8],
                 "Practice_Walk": [0.0, 0.2], "Practice_DuckWalk": [0.0, 0.2], "Practice_Step": [0.12, 0.3],
                 "Practice_SitDown": [0.2, 0.55], "Practice_StandUp": [0.0, 0.25], "Practice_PushUp": [0.3, 0.55],
                 "Practice_PullDown": [0.2, 0.5]}


def preview(rig, actions):
    """アクションごとに、正面と斜めから PREVIEW_TIMES のコマを撮る（ヘッドセットは隠す）。"""
    scene = bpy.context.scene
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    saved = {"camera": scene.camera, "res": (scene.render.resolution_x, scene.render.resolution_y,
             scene.render.resolution_percentage), "path": scene.render.filepath, "frame": scene.frame_current}
    headset = bpy.data.objects.get("HERO_PilotHeadset")
    headset_hidden = headset.hide_render if headset else None
    if headset:
        headset.hide_render = True
    cams = []
    for name, loc in (("front", (0.0, -5.6, 1.15)), ("side", (3.2, -4.6, 1.35))):
        data = bpy.data.cameras.new("TMP_PracticePreview_" + name)
        data.lens = 50
        cam = bpy.data.objects.new("TMP_PracticePreview_" + name, data)
        scene.collection.objects.link(cam)
        cam.location = loc
        direction = Vector((0.0, 0.0, 1.0)) - Vector(loc)
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cams.append((name, cam))
    files = []
    try:
        scene.render.resolution_x = scene.render.resolution_y = 360
        scene.render.resolution_percentage = 100
        for act in actions:
            rig.animation_data.action = act
            for i, seconds in enumerate(PREVIEW_TIMES.get(act.name, [0.0])):
                scene.frame_set(1 + round(seconds * FPS))
                for cam_name, cam in cams:
                    scene.camera = cam
                    path = PREVIEW_DIR / f"{act.name}_{i}_{cam_name}.png"
                    scene.render.filepath = str(path)
                    bpy.ops.render.render(write_still=True)
                    files.append(path.name)
    finally:
        rig.animation_data.action = None
        for _name, cam in cams:
            data = cam.data
            bpy.data.objects.remove(cam)
            bpy.data.cameras.remove(data)
        if headset:
            headset.hide_render = headset_hidden
        scene.camera = saved["camera"]
        scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = saved["res"]
        scene.render.filepath = saved["path"]
        scene.frame_set(saved["frame"])
    return files


def _select(objs, active):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


def export(rig, actions):
    rig.animation_data.action = None
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    for act in actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = act.name
        track.strips.new(act.name, 1, act)
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    _select([rig], rig)
    path = str(ASSET / "mascot_practice.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_skins=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_def_bones=False, export_morph=False, export_apply=False, export_yup=True,
                              export_cameras=False, export_lights=False, export_materials="NONE")
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    return Path(path).stat().st_size


def main():
    rig = bpy.data.objects["Rig"]
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    poser = Poser(rig)
    actions = build_actions(poser)
    files = preview(rig, actions) if DO_PREVIEW else []
    size = export(rig, actions) if DO_EXPORT else 0
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    result = {"actions": [(a.name, list(a.frame_range)) for a in actions], "mascot_practice": size, "preview": len(files)}
    print("PRACTICE_MASCOT " + json.dumps(result, ensure_ascii=False))
    return result


if __name__ == "__main__":
    RESULT = main()

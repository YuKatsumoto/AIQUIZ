"""客席のハテナ（観客の盛り上げ役）の動きをライブの Blender で作って書き出す。

aiquiz_mascot.blend を開いて実行する（Higgsfield の Blender 連携 bl_execute から runpy）：
  import runpy, sys
  sys.argv = ["blender", "--"]          # 書き出さないなら ["blender", "--", "--no-export"]
  runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/build_stand_mascot.py", run_name="__main__")

作るもの（mascot_model.glb は変えない）：Rig のアクション 5 本 → ../mascot_stand.glb（骨組みとアクションだけ、メッシュなし）
  Stand_Idle      2.0 秒のループ。弾みながら、左手で客席に手を振る
  Stand_Cheer     0.75 秒のループ。両手を上げて跳ぶ（ゴール・判定・スタート）
  Stand_Dance     2.0 秒のループ。左右にステップして腕を交互に突き上げる（勝者のダンスの間）
  Stand_WaveLead  1.5 秒のループ。両腕を下から頭上へ大きく振り上げる（ウェーブの合図）
  Stand_Clap      0.5 秒のループ。頭上で手拍子（応援団の 0.5 秒の拍に合わせる）
姿勢は骨の向き（ハテナの空間 = glTF：x 左右、y 上、z 前）と、体（DEF-head）と腰（DEF-hips）の上下で決める。
脚は足首を床に置いたまま 2 本の骨の IK で曲げる（跳ぶ間は足ごと浮く）。
最後の行 STAND_MASCOT {...} に結果。.blend の保存は呼ぶ側で行う（AGENTS.md）。
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
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
FPS = 24
TAU = math.tau

# 腕の向き（ハテナの空間）。休みは体の横に下ろす。
ARM_REST_UPPER = (0.80, -0.55, 0.05)
ARM_REST_FORE = (0.70, -0.70, 0.12)
LEG_BONES = ("DEF-thigh", "DEF-shin")


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

    def pose(self, aims: dict, body_lift=0.0, hips_lift=0.0, sway=0.0, tilt=0.0, nod=0.0, feet_lift=0.0):
        """aims: 骨 → ハテナの空間の向き。body/hips_lift は上下（m）、sway は左右（m）、
        tilt は前から見た体の傾き（rad）、nod は体のうなずき（rad）。"""
        rig = self.rig
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion()
            pb.location = (0.0, 0.0, 0.0)
            pb.scale = (1.0, 1.0, 1.0)
        bpy.context.view_layer.update()
        offset = {"DEF-head": Vector((sway, 0.0, body_lift)), "DEF-hips": Vector((sway, 0.0, hips_lift))}
        for name, move in offset.items():
            pb = rig.pose.bones[name]
            rest = pb.bone.matrix_local
            turn = Quaternion((0.0, 1.0, 0.0), tilt) @ Quaternion((1.0, 0.0, 0.0), nod if name == "DEF-head" else 0.0)
            m = Matrix.Translation(rest.translation + move) @ turn.to_matrix().to_4x4() @ rest.to_3x3().to_4x4()
            pb.matrix = m
        bpy.context.view_layer.update()
        # 脚：股関節は腰について動き、足首は床（feet_lift だけ浮く）に置いたまま。
        legs = {}
        hips = rig.pose.bones["DEF-hips"]
        hip_m = hips.matrix @ hips.bone.matrix_local.inverted()
        for s in ("L", "R"):
            hip, knee, ankle = self.leg[s]
            hip_now = hip_m @ hip
            l1, l2 = (knee - hip).length, (ankle - knee).length
            target = ankle + Vector((sway * 0.4, 0.0, feet_lift))
            upper, lower = two_bone(hip_now, target, l1, l2, Vector((0.0, -1.0, 0.0)))
            legs["DEF-thigh." + s] = upper
            legs["DEF-shin." + s] = lower
            legs["DEF-foot." + s] = self.foot[s]          # feet stay flat
        for pb in sorted(rig.pose.bones, key=_depth):
            want = None
            if pb.name in legs:
                want = legs[pb.name]
            elif pb.name in aims:
                want = g2b(aims[pb.name]).normalized()
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


def make_action(poser, name, seconds, pose_at, step=1):
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
    for f in list(range(0, frames, step)) + [frames]:
        t = (f % frames) / FPS
        poser.pose(**pose_at(t))
        key_all(rig, f + 1)
    action.frame_range = (1, frames + 1)
    try:
        action.use_cyclic = True
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


def mix(a, b, w):
    return tuple(Vector(a).normalized().lerp(Vector(b).normalized(), w))


def build_actions(poser):
    def idle(t):
        p = t / 2.0
        bob = 0.025 * (0.5 - 0.5 * math.cos(TAU * 2.0 * p))
        flap = 0.45 * math.sin(TAU * 4.0 * p)
        a = arms((0.70, 0.55, 0.30), (0.20 + flap, 1.0, 0.25), (-0.80, -0.55, 0.10), (-0.70, -0.65, 0.20))
        return {"aims": a, "body_lift": -bob, "hips_lift": -bob, "tilt": -0.05, "nod": 0.04 * math.sin(TAU * 2.0 * p)}

    def cheer(t):
        p = t / 0.75
        jump = max(0.0, math.sin(TAU * p))
        crouch = max(0.0, -math.sin(TAU * p))
        shake = 0.25 * math.sin(TAU * 2.0 * p)
        a = arms((0.45, 0.90, 0.10), (0.25 + shake, 1.0, 0.12))
        return {"aims": a, "body_lift": 0.16 * jump - 0.06 * crouch, "hips_lift": 0.16 * jump - 0.06 * crouch,
                "feet_lift": 0.16 * jump, "nod": -0.10}

    def dance(t):
        p = t / 2.0
        step = math.sin(TAU * p)
        beat = 0.5 - 0.5 * math.cos(TAU * 4.0 * p)
        left_up = max(0.0, math.sin(TAU * 2.0 * p))
        right_up = max(0.0, -math.sin(TAU * 2.0 * p))
        a = arms(mix((0.80, -0.30, 0.30), (0.35, 1.0, 0.10), left_up), mix((0.50, -0.60, 0.60), (0.15, 1.0, 0.10), left_up),
                 mix((-0.80, -0.30, 0.30), (-0.35, 1.0, 0.10), right_up), mix((-0.50, -0.60, 0.60), (-0.15, 1.0, 0.10), right_up))
        return {"aims": a, "sway": 0.10 * step, "body_lift": -0.05 * beat, "hips_lift": -0.05 * beat,
                "tilt": 0.10 * step, "nod": 0.05 * math.sin(TAU * 4.0 * p)}

    def wave_lead(t):
        p = t / 1.5
        # 0..0.45 下から頭上へ振り上げ、0.45..0.7 上で揺らし、0.7..1 下ろす
        if p < 0.45:
            up = math.sin(0.5 * math.pi * p / 0.45)
        elif p < 0.70:
            up = 1.0
        else:
            up = 1.0 - math.sin(0.5 * math.pi * (p - 0.70) / 0.30)
        flutter = 0.20 * math.sin(TAU * 4.0 * p) * up
        low_u, low_f = (0.55, -0.80, 0.25), (0.35, -0.80, 0.50)
        high_u, high_f = (0.30, 1.0, 0.05), (0.10 + flutter, 1.0, 0.05)
        a = arms(mix(low_u, high_u, up), mix(low_f, high_f, up))
        rise = 0.10 * up - 0.06 * math.exp(-((p - 0.08) / 0.07) ** 2)
        return {"aims": a, "body_lift": rise, "hips_lift": rise, "feet_lift": 0.04 * up, "nod": -0.12 * up}

    def clap(t):
        k = (t % 0.5) / 0.5
        open_amount = math.sin(math.pi * k) ** 0.6
        a = arms((0.30 + 0.30 * open_amount, 1.0, 0.15), (-0.25 + 0.30 * open_amount, 1.0, 0.25))
        bounce = -0.04 * (1.0 - open_amount)
        return {"aims": a, "body_lift": bounce, "hips_lift": bounce, "nod": -0.08}

    return [make_action(poser, "Stand_Idle", 2.0, idle), make_action(poser, "Stand_Cheer", 0.75, cheer),
            make_action(poser, "Stand_Dance", 2.0, dance), make_action(poser, "Stand_WaveLead", 1.5, wave_lead),
            make_action(poser, "Stand_Clap", 0.5, clap)]


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
    path = str(ASSET / "mascot_stand.glb")
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
    size = export(rig, actions) if DO_EXPORT else 0
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    result = {"actions": [(a.name, list(a.frame_range)) for a in actions], "mascot_stand": size}
    print("STAND_MASCOT " + json.dumps(result, ensure_ascii=False))
    return result


if __name__ == "__main__":
    RESULT = main()

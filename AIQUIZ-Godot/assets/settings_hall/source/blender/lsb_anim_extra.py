"""一日の流れと実習のための追加の動き（docs/lecture_hall_plan.md の 2c・2d、項目 28・31・89・90・126）。
約束は lsb_anim_teacher と同じ（24 fps、ループは最初と最後が同じ姿勢、1 回きりは休止の姿勢で始まって終わる、
頭と胴は Body ごと）。体の座標: +X = 本人の左、-Y = 正面、+Z = 上。腕の向きは左腕の座標で書く（右は鏡像）。

- G_Sweep（掃除: ほうきを両手で右下に持って左右に掃く）、G_PushDesk（机を後ろへ押す: 両腕を前へ、前のめりで足踏み）、
  G_Carry（肩車の下の段: 両腕を上げて上の人の足を支え、膝を曲げてぐらぐら）、G_PointCheck（指差し確認「よし！」）
- T_Carry（先生: 踏み台を両手で前に抱えて歩く。足踏み、Godot が Root を動かす）
- S_Eat（座って給食・お弁当: 弁当へ体ごと前へ倒れてパクッ → もぐもぐ）
"""
from __future__ import annotations

import math

from lsb_anim import DESK, SEATED, Clip, R, arms, legs
from lsb_anim_teacher import HIGH, SIDE_OUT, lerp_dir, rest_pose, walk_leg

# 右下でほうきの柄を握る両手（左腕も体の前を横切って右へ）
BROOM_L = [(-0.25, -0.62, -0.74), (-0.4, -0.6, -0.69), (-0.5, -0.55, -0.67)]
BROOM_R = [(0.45, -0.45, -0.77), (0.5, -0.5, -0.71), (0.55, -0.5, -0.67)]
FORWARD = [(0.12, -0.98, -0.12), (0.08, -0.99, -0.05), (0.05, -0.99, 0.0)]
HOLD_LOW = [(0.12, -0.78, -0.61), (0.06, -0.9, -0.42), (0.02, -0.95, -0.3)]
POINT = [(0.08, -0.99, 0.12), (0.04, -0.99, 0.1), (0.0, -0.99, 0.08)]
HIP = [(0.85, 0.2, -0.48), (0.4, -0.3, -0.87), (-0.2, -0.5, -0.84)]


def g_sweep(arm):
    """掃除: ほうきを両手で右下に持ち、体ごと左右に振って掃く（1 往復 1.5 秒のループ）。"""
    c = Clip(arm, "G_Sweep", 36)
    for k, f in enumerate((0, 9, 18, 27, 36)):
        s = math.sin(k / 4.0 * math.tau)
        c.pose(f, {**arms(arm, BROOM_L, BROOM_R), **legs(arm, [(0.06 * s, 0.0, -0.99), None, None, None],
                                                         [(-0.06 * s, 0.0, -0.99), None, None, None])},
               body=R(pitch=10.0, yaw=-14.0 * s, roll=-3.0 * s), root=R(), loc=(0, 0, -0.01 + 0.006 * abs(s)))
    return c.finish()


def g_push_desk(arm):
    """机を後ろへ押す: 両腕を前へ伸ばし、前のめりで足踏み（Godot が Root と机を一緒に動かす）。1 秒ループ。"""
    c = Clip(arm, "G_PushDesk", 24)
    for k in range(5):
        f = k * 6
        ph = k / 4.0
        c.pose(f, {**arms(arm, FORWARD), **legs(arm, walk_leg(ph), walk_leg(ph + 0.5))},
               body=R(pitch=12.0, roll=3.0 * math.sin(ph * math.tau)), root=R(),
               loc=(0, 0, 0.012 * abs(math.cos(ph * math.tau))))
    return c.finish()


def g_carry(arm):
    """肩車の下の段: 両腕を上げて上の人の足を支え、膝を曲げて踏ん張る。重くてぐらぐら（2 秒ループ）。"""
    c = Clip(arm, "G_Carry", 48)
    hold = lerp_dir(HIGH, SIDE_OUT, 0.18)
    bend = [(0.0, -0.3, -0.95), (0.0, 0.22, -0.97), (0.0, -0.6, -0.8), None]
    for k, f in enumerate((0, 12, 24, 36, 48)):
        s = math.sin(k / 4.0 * math.tau)
        c.pose(f, {**arms(arm, hold), **legs(arm, bend)}, body=R(pitch=-2.0, roll=5.0 * s, yaw=2.0 * s), root=R(),
               loc=(0.012 * s, 0, -0.05 + 0.008 * abs(s)))
    return c.finish()


def g_point_check(arm):
    """指差し確認: 右腕で前をビシッと指す → 「よし！」で上下に振って止める。左手は腰。2 秒。"""
    c = Clip(arm, "G_PointCheck", 48)
    rest_pose(c, 0)
    c.pose(8, arms(arm, HIP, POINT), body=R(pitch=-3.0), loc=(0, 0, 0.01))
    c.pose(16, arms(arm, HIP, POINT), body=R(pitch=-4.0))
    up = [(0.08, -0.85, 0.52), (0.04, -0.8, 0.6), (0.0, -0.75, 0.66)]
    c.pose(22, arms(arm, HIP, up), body=R(pitch=-6.0), loc=(0, 0, 0.015))
    c.pose(27, arms(arm, HIP, POINT), body=R(pitch=4.0), loc=(0, 0, -0.012))
    c.pose(36, arms(arm, HIP, POINT), body=R(pitch=1.0))
    rest_pose(c, 48)
    return c.finish()


def t_carry(arm):
    """先生: 踏み台を両手で前に低く抱えて歩く（足踏み 1 歩 0.5 秒、重そうに体が弾む）。"""
    c = Clip(arm, "T_Carry", 24)
    for k in range(5):
        f = k * 6
        ph = k / 4.0
        c.pose(f, {**arms(arm, HOLD_LOW), **legs(arm, walk_leg(ph), walk_leg(ph + 0.5))},
               body=R(pitch=-5.0, roll=4.0 * math.sin(ph * math.tau)), root=R(),
               loc=(0, 0, 0.02 * abs(math.cos(ph * math.tau))))
    return c.finish()


def s_eat(arm, seat_lift):
    """座って給食・お弁当: 腕が口に届かないので、体ごと弁当へ倒れてパクッ → 起きてもぐもぐ（3 秒ループ）。"""
    c = Clip(arm, "S_Eat", 72)
    hold = [(0.3, -0.88, -0.36), (0.18, -0.9, -0.4), (0.1, -0.85, -0.5)]

    def p(f, pitch, dz, chew=0.0):
        c.pose(f, {**arms(arm, DESK, hold), **legs(arm, SEATED)}, body=R(pitch=pitch, roll=chew), root=R(),
               loc=(0, 0, seat_lift + dz))

    p(0, -3.0, 0.0)
    p(14, 22.0, -0.01)         # 弁当へ倒れて
    p(20, 24.0, -0.015)        # パクッ
    p(28, -4.0, 0.012)         # 起きて
    for k, f in enumerate((36, 44, 52, 60)):
        p(f, -3.0 + (1.5 if k % 2 else 0.0), 0.006 if k % 2 else 0.0, chew=2.0 if k % 2 else -2.0)
    p(72, -3.0, 0.0)
    return c.finish()


def build_extra(arm, role: str, seat_lift: float = 0.0) -> dict:
    """role: "teacher"（G_ と T_Carry）/ "student"（G_ と S_Eat）/ "other"（G_ だけ）。"""
    out = {}
    fns = [g_sweep, g_push_desk, g_carry, g_point_check]
    if role == "teacher":
        fns.append(t_carry)
    for fn in fns:
        info = fn(arm)
        out[info["action"]] = info
    if role == "student":
        info = s_eat(arm, seat_lift)
        out[info["action"]] = info
    return out

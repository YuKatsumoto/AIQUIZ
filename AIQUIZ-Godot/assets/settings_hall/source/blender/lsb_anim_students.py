"""生徒（座っている 3 人）の動きの部品（docs/lecture_hall_plan.md の 2b、S_）。3 人のリグに同じものを積む
（誰がどの役でもできるように。挙手の生徒の帽子・居眠りの生徒の Zzz は各自のギアのボーンが持つ）。

座っている姿勢: Root は椅子の中心、Body は座面の高さ（seat_lift）、脚は SEATED。手は机の手前の縁（DESK）。
立ち上がり（S_StandUp）は横（本人の左、+X）へ 0.55 m ずれて床に立って終わる。Godot はそこで人物の位置を
その立ち位置へ移し、共通の G_ の動き（立った姿勢）を使う。座る（S_SitDown）はその逆。
"""
from __future__ import annotations

import math

from lsb_anim import ARMS_UP, CROUCH, DESK, SEATED, STAND, TUCK, Clip, R, arms, legs
from lsb_anim_teacher import CLAP_TOP, HIGH, REST, SIDE_OUT, SIDE_UP, lerp_dir

WRITE = [(0.3, -0.88, -0.25), (0.2, -0.85, -0.45), (0.1, -0.6, -0.8)]
PEN_REST = [(0.3, -0.88, -0.25), (0.22, -0.88, -0.38), (0.14, -0.8, -0.58)]
STAND_SIDE = 0.55


class Seat:
    def __init__(self, seat_lift: float):
        self.lift = seat_lift

    def loc(self, dz=0.0, dx=0.0, dy=0.0):
        return (dx, dy, self.lift + dz)


def sit_pose(c: Clip, f: int, seat: Seat, right=None, body=None):
    c.pose(f, {**arms(c.arm, DESK, right or PEN_REST), **legs(c.arm, SEATED)}, body=body or R(pitch=-3.0), root=R(),
           loc=seat.loc())


def s_sit_idle(arm, seat):
    c = Clip(arm, "S_SitIdle", 120)
    sit_pose(c, 0, seat)
    c.pose(30, body=R(pitch=-2.0, roll=1.2), loc=seat.loc(0.003))
    c.pose(60, body=R(pitch=-3.5, roll=-1.0))
    c.pose(90, body=R(pitch=-2.5, roll=0.6), loc=seat.loc(0.003))
    sit_pose(c, 120, seat)
    return c.finish()


def s_look_board(arm, seat):
    """黒板を見る（集中）: 少し前のめりで、ときどきうなずく。4 秒。"""
    c = Clip(arm, "S_LookBoard", 96)
    sit_pose(c, 0, seat)
    c.pose(20, body=R(pitch=-6.0))
    c.pose(44, body=R(pitch=2.0))
    c.pose(52, body=R(pitch=-5.0))
    c.pose(76, body=R(pitch=-6.0, roll=1.5))
    sit_pose(c, 96, seat)
    return c.finish()


def s_copy_notes(arm, seat, fast=False):
    """板書を写す（鉛筆を往復、体もかすかに揺れる）。fast: 追いつかなくて倍速、体が大きく揺れる。ループ。"""
    name = "S_FastWrite" if fast else "S_CopyNotes"
    step = 4 if fast else 8
    c = Clip(arm, name, step * 8)
    look = R(pitch=9.0, yaw=-4.0)
    sit_pose(c, 0, seat, WRITE, look)
    for k in range(1, 8):
        s = -1.0 if k % 2 == 0 else 1.0
        stroke = [WRITE[0], WRITE[1], (0.1 + s * (0.16 if fast else 0.12), -0.6, -0.8)]
        c.pose(k * step, arms(arm, DESK, stroke), body=R(pitch=9.0 + (2.0 if fast else 0.0), yaw=-4.0,
                                                          roll=s * (2.5 if fast else 1.2)),
               loc=seat.loc(0.006 if (fast and k % 2) else 0.0))
    sit_pose(c, step * 8, seat, WRITE, look)
    return c.finish()


def s_peek(arm, seat, side):
    """先生の体で黒板が見えない → 体を左右（side +1 = 左）へ傾けて覗き込む。2.5 秒。"""
    c = Clip(arm, "S_PeekLeft" if side > 0 else "S_PeekRight", 60)
    sit_pose(c, 0, seat)
    c.pose(14, body=R(roll=side * 16.0, pitch=-4.0, yaw=side * 6.0), loc=seat.loc(0.02, dx=side * 0.06))
    c.pose(40, body=R(roll=side * 17.0, pitch=-5.0, yaw=side * 7.0), loc=seat.loc(0.02, dx=side * 0.07))
    sit_pose(c, 60, seat)
    return c.finish()


def s_erase(arm, seat):
    """消しゴムでごしごし → 左腕で消しカスを払う。2.5 秒。"""
    c = Clip(arm, "S_Erase", 60)
    sit_pose(c, 0, seat)
    rub_a = [(0.35, -0.86, -0.3), (0.25, -0.85, -0.45), (0.18, -0.65, -0.74)]
    rub_b = [(0.25, -0.86, -0.3), (0.12, -0.85, -0.45), (0.0, -0.65, -0.74)]
    for k in range(6):
        c.pose(6 + k * 4, arms(arm, DESK, rub_a if k % 2 == 0 else rub_b), body=R(pitch=10.0, roll=1.5 if k % 2 else -1.5))
    sweep_a = [(0.5, -0.82, -0.28), (0.4, -0.85, -0.35), (0.3, -0.8, -0.52)]
    sweep_b = [(0.2, -0.85, -0.3), (0.05, -0.85, -0.38), (-0.05, -0.8, -0.55)]
    c.pose(36, arms(arm, sweep_a, PEN_REST), body=R(pitch=8.0, yaw=6.0))
    c.pose(44, arms(arm, sweep_b, PEN_REST), body=R(pitch=8.0, yaw=-6.0))
    c.pose(50, arms(arm, sweep_a, PEN_REST), body=R(pitch=6.0))
    sit_pose(c, 60, seat)
    return c.finish()


def s_sharpen(arm, seat):
    """鉛筆削り（机の縁で、右の手先をくるくる回す。左手は押さえる）。3 秒。"""
    c = Clip(arm, "S_Sharpen", 72)
    sit_pose(c, 0, seat)
    for k in range(10):
        a = k / 10.0 * math.tau * 2.0
        turn = [(0.35, -0.86, -0.3), (0.25, -0.86, -0.42), (0.18 + 0.08 * math.cos(a), -0.72, -0.64 + 0.08 * math.sin(a))]
        c.pose(6 + k * 6, arms(arm, DESK, turn), body=R(pitch=11.0, roll=math.sin(a) * 1.2))
    sit_pose(c, 72, seat)
    return c.finish()


def s_page_flip(arm, seat):
    """ノートのページをめくる（右手が右から左へ弧を描く）。1.2 秒。"""
    c = Clip(arm, "S_PageFlip", 30)
    sit_pose(c, 0, seat)
    lift = [(0.45, -0.85, -0.1), (0.35, -0.8, 0.0), (0.25, -0.7, 0.15)]
    over = [(0.05, -0.9, -0.2), (-0.1, -0.85, -0.25), (-0.2, -0.75, -0.4)]
    c.pose(8, arms(arm, DESK, lift), body=R(pitch=6.0, yaw=-5.0))
    c.pose(16, arms(arm, DESK, over), body=R(pitch=7.0, yaw=5.0))
    sit_pose(c, 30, seat)
    return c.finish()


def s_raise_hand(arm, seat, level):
    """挙手の 3 段階（ループ）: 1 = まっすぐ挙げる、2 = 腰を浮かせて大きく振る、3 = 立ち上がって両手を振る（G_ へ）。"""
    names = {1: "S_RaiseHand", 2: "S_RaiseHandEager"}
    c = Clip(arm, names[level], 24 if level == 1 else 16)
    up = [(0.68, -0.3, 0.67), (0.45, -0.3, 0.84), (0.3, -0.28, 0.91)]
    if level == 1:
        c.pose(0, {**arms(arm, DESK, up), **legs(arm, SEATED)}, body=R(pitch=-5.0, roll=5.0), root=R(), loc=seat.loc())
        c.pose(12, arms(arm, DESK, [up[0], (0.5, -0.3, 0.81), (0.4, -0.28, 0.87)]), body=R(pitch=-5.0, roll=6.0),
               loc=seat.loc(0.01))
        c.pose(24, {**arms(arm, DESK, up), **legs(arm, SEATED)}, body=R(pitch=-5.0, roll=5.0), root=R(), loc=seat.loc())
    else:
        half = [(0.0, -0.75, -0.66), (0.0, -0.1, -0.99), (0.0, -0.85, -0.53), (0.0, -0.95, 0.3)]
        for k in range(3):
            s = 1.0 if k % 2 == 0 else -1.0
            wave = [up[0], (0.45 + s * 0.35, -0.3, 0.78), (0.3 + s * 0.5, -0.28, 0.8)]
            c.pose(k * 8, {**arms(arm, DESK, wave), **legs(arm, half)}, body=R(pitch=-8.0, roll=6.0 + 3.0 * s),
                   root=R(), loc=seat.loc(0.12 if k == 1 else 0.08))
    return c.finish()


def s_stand_up(arm, seat):
    """立ち上がる（横 +X へ 0.55 m ずれて床に立つ）。1.2 秒。"""
    c = Clip(arm, "S_StandUp", 30)
    sit_pose(c, 0, seat)
    c.pose(8, {**legs(arm, CROUCH)}, body=R(pitch=14.0), loc=seat.loc(0.04, dx=0.1))
    c.pose(18, {**arms(arm, SIDE_OUT), **legs(arm, TUCK)}, body=R(pitch=0.0), loc=(STAND_SIDE * 0.7, 0.0, 0.12))
    c.pose(24, {**arms(arm, REST), **legs(arm, CROUCH)}, body=R(pitch=4.0), loc=(STAND_SIDE, 0.0, -0.03))
    c.pose(30, {**arms(arm, REST), **legs(arm, STAND)}, body=R(), root=R(), loc=(STAND_SIDE, 0.0, 0.0))
    return c.finish()


def s_sit_down(arm, seat):
    c = Clip(arm, "S_SitDown", 30)
    c.pose(0, {**arms(arm, REST), **legs(arm, STAND)}, body=R(), root=R(), loc=(STAND_SIDE, 0.0, 0.0))
    c.pose(8, {**legs(arm, CROUCH)}, body=R(pitch=6.0), loc=(STAND_SIDE, 0.0, -0.04))
    c.pose(16, {**arms(arm, SIDE_OUT), **legs(arm, TUCK)}, body=R(pitch=-2.0), loc=(STAND_SIDE * 0.4, 0.0, 0.14))
    c.pose(22, {**legs(arm, SEATED)}, body=R(pitch=6.0), loc=seat.loc(-0.01))
    sit_pose(c, 30, seat)
    return c.finish()


def s_forget(arm, seat):
    """指されたのに答えを忘れる（立ったまま固まり、首をかしげ、しょんぼり座る直前の姿勢まで）。立った姿勢。3 秒。"""
    c = Clip(arm, "S_Forget", 72)
    c.pose(0, {**arms(arm, REST), **legs(arm, STAND)}, body=R(), root=R(), loc=(0, 0, 0))
    c.pose(10, body=R(pitch=-4.0), loc=(0, 0, 0.01))
    c.pose(30, body=R(pitch=-3.0, roll=-10.0))
    c.pose(48, body=R(pitch=-2.0, roll=10.0))
    c.pose(60, arms(arm, [(0.3, 0.0, -0.95), (0.2, -0.05, -0.98), (0.15, -0.1, -0.98)]), body=R(pitch=12.0))
    c.pose(72, {**arms(arm, REST), **legs(arm, STAND)}, body=R(), root=R(), loc=(0, 0, 0))
    return c.finish()


def s_fix_cap(arm, seat):
    """帽子を直す（両手を頭の上へ、つばを回す）。2 秒。"""
    c = Clip(arm, "S_FixCap", 48)
    sit_pose(c, 0, seat)
    c.pose(12, arms(arm, CLAP_TOP), body=R(pitch=-4.0))
    c.pose(20, arms(arm, CLAP_TOP), body=R(pitch=-4.0, yaw=10.0))
    c.pose(28, arms(arm, CLAP_TOP), body=R(pitch=-4.0, yaw=-6.0))
    c.pose(36, arms(arm, SIDE_UP), body=R(pitch=-2.0))
    sit_pose(c, 48, seat)
    return c.finish()


def s_doze_drift(arm, seat):
    """うとうと → こっくり（ループ 6 秒）: 体ごとゆっくり前へ垂れ、かくんと戻る。"""
    c = Clip(arm, "S_DozeDrift", 144)
    sit_pose(c, 0, seat, body=R(pitch=5.0))
    c.pose(50, body=R(pitch=13.0, roll=3.0))
    c.pose(70, body=R(pitch=17.0, roll=4.0), loc=seat.loc(-0.005))
    c.pose(74, body=R(pitch=6.0, roll=1.0), loc=seat.loc(0.01))
    c.pose(110, body=R(pitch=12.0, roll=-2.0))
    c.pose(124, body=R(pitch=15.0, roll=-3.0))
    c.pose(128, body=R(pitch=5.0), loc=seat.loc(0.008))
    sit_pose(c, 144, seat, body=R(pitch=5.0))
    return c.finish()


def s_faceplant(arm, seat):
    """机に突っ伏す（ゴン）: 前へ大きく倒れて机に当たり、少し弾んで、そのまま寝る姿勢（ループの頭へ）。2 秒。"""
    c = Clip(arm, "S_Faceplant", 48)
    sit_pose(c, 0, seat, body=R(pitch=12.0))
    c.pose(14, body=R(pitch=26.0), loc=seat.loc(-0.01))
    c.pose(17, arms(arm, [(0.75, -0.5, -0.43), (0.7, -0.55, -0.45), (0.65, -0.6, -0.45)]), body=R(pitch=31.0),
           loc=seat.loc(-0.02))
    c.pose(21, body=R(pitch=28.0), loc=seat.loc(0.0))
    c.pose(26, body=R(pitch=31.0), loc=seat.loc(-0.02))
    c.pose(48, body=R(pitch=30.0, roll=2.0), loc=seat.loc(-0.02))
    return c.finish()


def s_sleep_slumped(arm, seat):
    """突っ伏したまま眠る（ループ 4 秒、寝息で体が上下）。"""
    c = Clip(arm, "S_SleepSlumped", 96)
    pose = {**arms(arm, [(0.75, -0.5, -0.43), (0.7, -0.55, -0.45), (0.65, -0.6, -0.45)]), **legs(arm, SEATED)}
    c.pose(0, pose, body=R(pitch=30.0, roll=2.0), root=R(), loc=seat.loc(-0.02))
    c.pose(48, body=R(pitch=28.5, roll=2.5), loc=seat.loc(-0.012))
    c.pose(96, pose, body=R(pitch=30.0, roll=2.0), root=R(), loc=seat.loc(-0.02))
    return c.finish()


def s_wake_jolt(arm, seat):
    """飛び起きる（キーッ、テストに出る、チョーク）: 腕がびくっと開いて座面で跳ね、きょろきょろ。2 秒。"""
    c = Clip(arm, "S_WakeJolt", 48)
    sit_pose(c, 0, seat, body=R(pitch=18.0))
    startle = [(0.75, -0.45, 0.1), (0.7, -0.4, 0.3), (0.6, -0.35, 0.5)]
    c.pose(5, arms(arm, startle, startle), body=R(pitch=-8.0, roll=-2.0), loc=seat.loc(0.07))
    c.pose(11, arms(arm, DESK, PEN_REST), body=R(pitch=-3.0), loc=seat.loc())
    c.pose(22, body=R(pitch=-2.0, yaw=20.0))
    c.pose(36, body=R(pitch=-2.0, yaw=-18.0))
    sit_pose(c, 48, seat)
    return c.finish()


def s_teeter(arm, seat):
    """椅子から落ちかける: 横へ傾いて片側が浮き、脚をばたばた、腕を振り回して戻る。2.5 秒。"""
    c = Clip(arm, "S_Teeter", 60)
    sit_pose(c, 0, seat, body=R(pitch=10.0))
    flail_a = [(0.9, 0.1, 0.4), (0.85, 0.2, 0.5), (0.8, 0.25, 0.55)]
    flail_b = [(0.9, -0.3, 0.2), (0.85, -0.4, 0.3), (0.8, -0.45, 0.35)]
    kick_a = [(0.0, -0.9, -0.43), (0.0, -0.6, -0.8), None, None]
    kick_b = [(0.0, -0.6, -0.8), (0.0, -0.95, -0.3), None, None]
    for k in range(7):
        c.pose(6 + k * 6, {**arms(arm, flail_a if k % 2 else flail_b, flail_b if k % 2 else flail_a),
                           **legs(arm, kick_a if k % 2 else kick_b, kick_b if k % 2 else kick_a)},
               body=R(roll=-22.0 + 4.0 * (k % 2), pitch=-4.0), loc=seat.loc(0.02, dx=-0.08))
    c.pose(50, {**legs(arm, SEATED)}, body=R(roll=4.0, pitch=0.0), loc=seat.loc(0.01))
    sit_pose(c, 60, seat)
    return c.finish()


def s_frenzy(arm, seat):
    """「テストに出る」で猛烈に写す（ループ 0.5 秒、体ごと震える）。"""
    c = Clip(arm, "S_Frenzy", 12)
    sit_pose(c, 0, seat, WRITE, R(pitch=13.0))
    for k in range(1, 6):
        s = 1.0 if k % 2 else -1.0
        stroke = [WRITE[0], WRITE[1], (0.1 + s * 0.2, -0.6, -0.8)]
        c.pose(k * 2, arms(arm, DESK, stroke), body=R(pitch=13.0, roll=s * 3.0, yaw=s * 2.0), loc=seat.loc(0.01 if k % 2 else 0.0))
    sit_pose(c, 12, seat, WRITE, R(pitch=13.0))
    return c.finish()


def s_turn_sound(arm, seat, side):
    """音のほうを振り向く（効果音の試し鳴らし・立坑の音）: 体ごと左右へ 35°、少し止まって戻る。2 秒。"""
    c = Clip(arm, "S_TurnLeft" if side > 0 else "S_TurnRight", 48)
    sit_pose(c, 0, seat)
    c.pose(8, body=R(yaw=side * 35.0, pitch=-4.0), loc=seat.loc(0.015))
    c.pose(32, body=R(yaw=side * 36.0, pitch=-3.0))
    sit_pose(c, 48, seat)
    return c.finish()


def s_clap_seated(arm, seat):
    """座ったまま拍手（ループ 1 秒）。"""
    c = Clip(arm, "S_Clap", 24)
    apart = [(0.6, -0.1, 0.79), (0.45, -0.15, 0.88), (0.35, -0.15, 0.92)]
    c.pose(0, {**arms(arm, apart), **legs(arm, SEATED)}, body=R(pitch=-3.0), root=R(), loc=seat.loc())
    for k, f in enumerate((3, 6, 9, 12, 15, 18, 21)):
        c.pose(f, arms(arm, CLAP_TOP if k % 2 == 0 else apart), body=R(pitch=-3.0, roll=1.0 if k % 2 else -1.0),
               loc=seat.loc(0.005 if k % 2 == 0 else 0.0))
    c.pose(24, {**arms(arm, apart), **legs(arm, SEATED)}, body=R(pitch=-3.0), root=R(), loc=seat.loc())
    return c.finish()


def s_hide_notes(arm, seat):
    """ノートを覗かれて隠す（腕を机に広げて覆いかぶさる）。2.5 秒。"""
    c = Clip(arm, "S_HideNotes", 60)
    sit_pose(c, 0, seat)
    cover = [(0.7, -0.6, -0.38), (0.55, -0.7, -0.45), (0.4, -0.75, -0.53)]
    c.pose(8, arms(arm, cover), body=R(pitch=24.0), loc=seat.loc(-0.01))
    c.pose(44, arms(arm, cover), body=R(pitch=25.0, roll=3.0), loc=seat.loc(-0.01))
    sit_pose(c, 60, seat)
    return c.finish()


def build_students(arm, seat_lift: float) -> dict:
    seat = Seat(seat_lift)
    out = {}
    fns = [lambda a: s_sit_idle(a, seat), lambda a: s_look_board(a, seat), lambda a: s_copy_notes(a, seat),
           lambda a: s_copy_notes(a, seat, fast=True), lambda a: s_peek(a, seat, 1.0), lambda a: s_peek(a, seat, -1.0),
           lambda a: s_erase(a, seat), lambda a: s_sharpen(a, seat), lambda a: s_page_flip(a, seat),
           lambda a: s_raise_hand(a, seat, 1), lambda a: s_raise_hand(a, seat, 2), lambda a: s_stand_up(a, seat),
           lambda a: s_sit_down(a, seat), lambda a: s_forget(a, seat), lambda a: s_fix_cap(a, seat),
           lambda a: s_doze_drift(a, seat), lambda a: s_faceplant(a, seat), lambda a: s_sleep_slumped(a, seat),
           lambda a: s_wake_jolt(a, seat), lambda a: s_teeter(a, seat), lambda a: s_frenzy(a, seat),
           lambda a: s_turn_sound(a, seat, 1.0), lambda a: s_turn_sound(a, seat, -1.0), lambda a: s_clap_seated(a, seat),
           lambda a: s_hide_notes(a, seat)]
    for fn in fns:
        info = fn(arm)
        out[info["action"]] = info
    return out

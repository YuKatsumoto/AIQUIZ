"""全員が使う動きの部品（G_、立っている姿勢: Root が床）。先生・生徒・練習生・新しいキャラのリグに同じものを積み、
Godot が誰にでも同じ名前で頼める（起立・礼、拍手、さようなら、びくっ、見上げる…）。
約束は lsb_anim_teacher と同じ（24 fps、1 回きりは休止の姿勢で始まって終わる、頭と胴は Body ごと）。
"""
from __future__ import annotations

import math

from lsb_anim import ARMS_UP, CROUCH, HANG, STAND, TUCK, Clip, R, arms, legs
from lsb_anim_teacher import CLAP_TOP, HIGH, REST, SIDE_OUT, SIDE_UP, lerp_dir, rest_pose, walk_leg


def g_idle(arm):
    c = Clip(arm, "G_Idle", 120)
    rest_pose(c, 0)
    c.pose(30, body=R(pitch=1.2, roll=1.0), loc=(0, 0, 0.003))
    c.pose(60, body=R(pitch=0.0, roll=-1.2))
    c.pose(90, body=R(pitch=1.0, roll=0.5), loc=(0, 0, 0.003))
    return c.finish()


def g_walk(arm, run=False):
    """歩き（run=True で小走り: 速く大きく弾む）。その場の足踏み、Godot が Root を動かす。"""
    name = "G_Run" if run else "G_Walk"
    frames = 16 if run else 24
    c = Clip(arm, name, frames)
    amp = 1.4 if run else 1.0
    for k in range(5):
        f = int(round(k * frames / 4))
        ph = k / 4.0
        swing = math.sin(ph * math.tau)
        fwd = [(0.55, -0.35 * amp, -0.76), (0.5, -0.4 * amp, -0.76), (0.45, -0.45 * amp, -0.77)]
        back = [(0.55, 0.35 * amp, -0.76), (0.5, 0.3 * amp, -0.81), (0.45, 0.25 * amp, -0.86)]
        la = lerp_dir(lerp_dir(REST, fwd, max(0.0, swing)), back, max(0.0, -swing))
        ra = lerp_dir(lerp_dir(REST, fwd, max(0.0, -swing)), back, max(0.0, swing))
        c.pose(f, {**arms(arm, la, ra), **legs(arm, walk_leg(ph), walk_leg(ph + 0.5))},
               body=R(pitch=3.0 * amp, roll=4.0 * swing), root=R(),
               loc=(0, 0, (0.045 if run else 0.025) * abs(math.cos(ph * math.tau))))
    return c.finish()


def g_jump_write(arm):
    """黒板に答えを書く（届かないので 1 画ごとに跳ぶ）。0.8 秒で 1 回。"""
    c = Clip(arm, "G_JumpWrite", 20)
    left = lerp_dir(REST, SIDE_OUT, 0.5)
    c.pose(0, {**arms(arm, left, SIDE_UP), **legs(arm, STAND)}, body=R(pitch=2.0), root=R(), loc=(0, 0, 0))
    c.pose(4, {**legs(arm, CROUCH)}, body=R(pitch=8.0), loc=(0, 0, -0.06))
    c.pose(9, {**arms(arm, SIDE_UP, HIGH), **legs(arm, TUCK)}, body=R(pitch=-4.0, roll=-4.0), loc=(0, 0, 0.3))
    c.pose(14, {**legs(arm, STAND)}, body=R(pitch=-2.0), loc=(0, 0, 0.05))
    c.pose(17, {**arms(arm, left, SIDE_UP), **legs(arm, CROUCH)}, body=R(pitch=6.0), loc=(0, 0, -0.05))
    c.pose(20, {**arms(arm, left, SIDE_UP), **legs(arm, STAND)}, body=R(pitch=2.0), root=R(), loc=(0, 0, 0))
    return c.finish()


def g_bow(arm):
    c = Clip(arm, "G_Bow", 48)
    rest_pose(c, 0)
    front = [(0.35, -0.3, -0.89), (0.25, -0.35, -0.9), (0.15, -0.4, -0.9)]
    c.pose(12, arms(arm, front), body=R(pitch=30.0), loc=(0, 0, -0.01))
    c.pose(28, arms(arm, front), body=R(pitch=31.0), loc=(0, 0, -0.01))
    c.pose(40, arms(arm, REST), body=R(pitch=-1.0))
    rest_pose(c, 48)
    return c.finish()


def g_wave(arm):
    c = Clip(arm, "G_Wave", 60)
    rest_pose(c, 0)
    up = [(0.68, -0.3, 0.67), (0.45, -0.3, 0.84), (0.3, -0.28, 0.91)]
    c.pose(10, arms(arm, REST, up), body=R(roll=4.0))
    for k in range(6):
        s = 1.0 if k % 2 == 0 else -1.0
        wave = [up[0], (0.45 + s * 0.3, -0.3, 0.8), (0.3 + s * 0.42, -0.28, 0.82)]
        c.pose(16 + k * 5, arms(arm, REST, wave), body=R(roll=4.0 + s * 1.5), loc=(0, 0, 0.01 if k % 2 == 0 else 0.0))
    c.pose(50, arms(arm, REST, up), body=R(roll=2.0))
    rest_pose(c, 60)
    return c.finish()


def g_wave_both(arm):
    """両手を振る（さようなら・元気よく）。2.5 秒。"""
    c = Clip(arm, "G_WaveBoth", 60)
    rest_pose(c, 0)
    for k in range(8):
        s = 1.0 if k % 2 == 0 else -1.0
        la = [(0.6 + 0.2 * s, -0.25, 0.75), (0.45 + 0.3 * s, -0.25, 0.85), (0.3 + 0.4 * s, -0.25, 0.86)]
        ra = [(0.6 - 0.2 * s, -0.25, 0.75), (0.45 - 0.3 * s, -0.25, 0.85), (0.3 - 0.4 * s, -0.25, 0.86)]
        c.pose(8 + k * 5, arms(arm, la, ra), body=R(roll=2.0 * s, pitch=-2.0), loc=(0, 0, 0.015 if k % 2 == 0 else 0.0))
    rest_pose(c, 60)
    return c.finish()


def g_startle(arm):
    c = Clip(arm, "G_Startle", 24)
    rest_pose(c, 0)
    c.pose(4, {**arms(arm, SIDE_OUT), **legs(arm, TUCK)}, body=R(pitch=-6.0), loc=(0, 0, 0.08))
    c.pose(9, {**arms(arm, lerp_dir(REST, SIDE_OUT, 0.4)), **legs(arm, CROUCH)}, body=R(pitch=4.0), loc=(0, 0, -0.03))
    rest_pose(c, 24)
    return c.finish()


def g_happy_hop(arm):
    c = Clip(arm, "G_HappyHop", 36)
    rest_pose(c, 0)
    for k, f in enumerate((6, 11, 16, 21)):
        up = k % 2 == 0
        c.pose(f, {**arms(arm, ARMS_UP if up else SIDE_UP), **legs(arm, TUCK if up else CROUCH)},
               body=R(pitch=-4.0 if up else 4.0), loc=(0, 0, 0.16 if up else -0.03))
    rest_pose(c, 36)
    return c.finish()


def g_look_up(arm):
    c = Clip(arm, "G_LookUp", 72)
    rest_pose(c, 0)
    c.pose(14, body=R(pitch=-20.0, yaw=10.0))
    c.pose(40, body=R(pitch=-21.0, yaw=-12.0))
    c.pose(58, body=R(pitch=-12.0))
    rest_pose(c, 72)
    return c.finish()


def g_clap(arm):
    """拍手（頭の上で打つ、ループ 1 秒で 4 回）。"""
    c = Clip(arm, "G_Clap", 24)
    apart = [(0.6, -0.1, 0.79), (0.45, -0.15, 0.88), (0.35, -0.15, 0.92)]
    c.pose(0, {**arms(arm, apart), **legs(arm, STAND)}, body=R(pitch=-2.0), root=R(), loc=(0, 0, 0))
    for k, f in enumerate((3, 6, 9, 12, 15, 18, 21)):
        c.pose(f, arms(arm, CLAP_TOP if k % 2 == 0 else apart), body=R(pitch=-2.0, roll=1.0 if k % 2 else -1.0),
               loc=(0, 0, 0.006 if k % 2 == 0 else 0.0))
    c.pose(24, {**arms(arm, apart), **legs(arm, STAND)}, body=R(pitch=-2.0), root=R(), loc=(0, 0, 0))
    return c.finish()


def g_nod(arm):
    c = Clip(arm, "G_Nod", 24)
    rest_pose(c, 0)
    c.pose(6, body=R(pitch=9.0))
    c.pose(11, body=R(pitch=-1.0))
    c.pose(16, body=R(pitch=7.0))
    rest_pose(c, 24)
    return c.finish()


def g_head_tilt(arm):
    c = Clip(arm, "G_HeadTilt", 48)
    rest_pose(c, 0)
    c.pose(12, body=R(roll=-12.0, pitch=-2.0))
    c.pose(34, body=R(roll=-13.0, pitch=-2.0))
    rest_pose(c, 48)
    return c.finish()


def g_sad(arm):
    c = Clip(arm, "G_Sad", 72)
    rest_pose(c, 0)
    limp = [(0.3, 0.0, -0.95), (0.2, -0.05, -0.98), (0.15, -0.1, -0.98)]
    c.pose(20, arms(arm, limp), body=R(pitch=16.0), loc=(0, 0, -0.03))
    c.pose(52, arms(arm, limp), body=R(pitch=17.0, roll=2.0), loc=(0, 0, -0.03))
    rest_pose(c, 72)
    return c.finish()


def g_stretch(arm):
    """伸び（休み時間）: 両腕を真上へ、つま先立ちで反り、ふーっと戻る。3 秒。"""
    c = Clip(arm, "G_Stretch", 72)
    rest_pose(c, 0)
    toe = [(0.0, 0.08, -0.99), (0.0, 0.0, -1.0), (0.0, -0.2, -0.98), (0.0, -0.95, 0.3)]
    c.pose(18, {**arms(arm, HIGH), **legs(arm, toe)}, body=R(pitch=-10.0), loc=(0, 0, 0.06))
    c.pose(36, {**arms(arm, HIGH), **legs(arm, toe)}, body=R(pitch=-12.0, roll=3.0), loc=(0, 0, 0.065))
    c.pose(46, {**arms(arm, SIDE_OUT), **legs(arm, STAND)}, body=R(pitch=4.0), loc=(0, 0, -0.01))
    rest_pose(c, 72)
    return c.finish()


def g_chat(arm):
    """おしゃべり（休み時間、横の相手へ）: 体を弾ませて腕で身ぶり、相づち。ループ 3 秒。"""
    c = Clip(arm, "G_Chat", 72)
    rest_pose(c, 0)
    g1 = [(0.75, -0.45, 0.2), (0.65, -0.5, 0.4), (0.55, -0.5, 0.55)]
    for k, f in enumerate((10, 20, 32, 44, 56)):
        s = 1.0 if k % 2 == 0 else -1.0
        c.pose(f, arms(arm, g1 if k % 2 == 0 else REST, REST if k % 2 == 0 else g1),
               body=R(pitch=4.0 if k % 2 else -2.0, roll=2.0 * s, yaw=8.0), loc=(0, 0, 0.012 if k % 2 == 0 else 0.0))
    rest_pose(c, 72)
    return c.finish()


def g_cheer(arm):
    """ばんざい（合格・正解）: 両腕を上げて 3 回跳ねる。2 秒。"""
    c = Clip(arm, "G_Cheer", 48)
    rest_pose(c, 0)
    for k in range(6):
        up = k % 2 == 0
        c.pose(6 + k * 6, {**arms(arm, HIGH if up else ARMS_UP), **legs(arm, TUCK if up else CROUCH)},
               body=R(pitch=-6.0 if up else 3.0), loc=(0, 0, 0.2 if up else -0.02))
    rest_pose(c, 48)
    return c.finish()


def g_freeze(arm):
    """だるまさんがころんだ（照明が点いた瞬間に固まる）: 走っている途中の片足立ちで止まり、ぷるぷる。1.5 秒。"""
    c = Clip(arm, "G_Freeze", 36)
    one = [(0.0, -0.4, -0.92), (0.0, 0.3, -0.95), (0.0, -0.7, -0.7), None]
    pose = {**arms(arm, [(0.6, -0.4, 0.69), (0.5, -0.45, 0.74), (0.45, -0.45, 0.77)],
                   [(0.6, 0.4, -0.69), (0.55, 0.4, -0.73), (0.5, 0.4, -0.77)]), **legs(arm, one, STAND)}
    c.pose(0, pose, body=R(pitch=6.0, roll=-3.0), root=R(), loc=(0, 0, 0.02))
    for k in range(1, 6):
        c.pose(k * 6, body=R(pitch=6.0, roll=-3.0 + (1.2 if k % 2 else -1.2)), loc=(0, 0, 0.02))
    c.pose(36, pose, body=R(pitch=6.0, roll=-3.0), root=R(), loc=(0, 0, 0.02))
    return c.finish()


def build_common(arm) -> dict:
    out = {}
    for fn in (g_idle, g_walk, g_jump_write, g_bow, g_wave, g_wave_both, g_startle, g_happy_hop, g_look_up, g_clap,
               g_nod, g_head_tilt, g_sad, g_stretch, g_chat, g_cheer, g_freeze):
        info = fn(arm)
        out[info["action"]] = info
    info = g_walk(arm, run=True)
    out[info["action"]] = info
    return out

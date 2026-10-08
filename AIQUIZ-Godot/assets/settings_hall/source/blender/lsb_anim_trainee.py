"""練習生の動きの部品（docs/lecture_hall_plan.md の 2c、P_）。実習レールの刃（Blade ボーン）の走りと組で作る。

レール: 刃は練習生のローカルで y RAIL_Y0（-2.8、後ろ）→ RAIL_Y1（+2.5、前）を走り、y = 0（足元）を通る。
基本の P（lsb_anim.clip_practice、Practice）は 96 フレームで 5.3 m（足元を 51 フレーム目）。ここで足すのは:
  P_JumpEarly  早すぎ: 刃の前に着地 → 慌ててもう一度ぴょん → よろける
  P_JumpLate   遅すぎ: 踏み切りが遅れて刃に足をすくわれ、前へ転がって尻もち、目を回す（「カンッ」は Godot の音）
  P_Double     2 枚続けて（刃が 2 回走る）→ 2 回跳ぶ
  P_Fast       速い刃（2 倍）→ 早めに踏み切る
  P_Reverse    逆走（前から来る）→ 振り向いて跳ぶ
  P_Clipboard  休憩中、記録を書く（左腕で板を持つ形、右手で小さく書く）
  P_FanSelf    ヘルメットの下が暑くて手であおぐ、肩で息
刃の回転は 16 歯の対称（22.5°）に合わせ、ループの継ぎ目で回転がそろう回数にする。
"""
from __future__ import annotations

import math

from lsb_anim import ARMS_UP, CROUCH, STAND, TUCK, Clip, R, arms, legs
from lsb_anim_teacher import HIGH, REST, SIDE_OUT, SIDE_UP, lerp_dir

READY_ARMS = [(0.78, -0.25, -0.57), (0.7, -0.35, -0.62), (0.6, -0.45, -0.66)]
KNEES = [(0.0, -0.25, -0.97), (0.0, 0.2, -0.98), (0.0, -0.74, -0.67), None]
BACK_ARMS = [(0.55, 0.55, -0.63), (0.45, 0.65, -0.62), (0.4, 0.7, -0.6)]
SPIN_PER_FRAME = 11.25 / 120.0  # 回転/フレーム（基本の Practice と同じ）


def _ready(c: Clip, f: int, z=-0.02):
    c.pose(f, {**arms(c.arm, READY_ARMS), **legs(c.arm, KNEES)}, body=R(pitch=4.0), root=R(), loc=(0, 0, z))


def _blade(c: Clip, keys, length, rail_y0):
    """keys: [(frame, y)]（ローカルの y、走りの区間）。回転は全体で連続。"""
    for f, y in keys:
        c.loc("Blade", f, (0.0, y - rail_y0, 0.0))
    turns = SPIN_PER_FRAME * length
    c.euler("Blade", 0, (0.0, 0.0, 0.0))
    c.euler("Blade", length, (-math.tau * turns, 0.0, 0.0))
    c.set_interpolation('pose.bones["Blade"]', "LINEAR")


def _jump(c: Clip, peak: int, height=1.1, prep=12, air=14):
    """peak を頂点にした跳躍: 予備動作 → 踏み切り → 抱え込み → 着地の沈み。"""
    arm = c.arm
    c.pose(peak - prep - 5, {**arms(arm, BACK_ARMS), **legs(arm, CROUCH)}, body=R(pitch=10.0), loc=(0, 0, -0.08))
    c.pose(peak - prep, {**arms(arm, ARMS_UP), **legs(arm, STAND)}, body=R(pitch=-4.0), loc=(0, 0, height * 0.32))
    c.pose(peak - prep // 2, {**legs(arm, TUCK)}, body=R(pitch=4.0), loc=(0, 0, height * 0.78))
    c.pose(peak, {**arms(arm, [(0.7, -0.2, 0.68), (0.55, -0.2, 0.81), (0.45, -0.2, 0.87)])}, body=R(pitch=10.0),
           loc=(0, 0, height))
    c.pose(peak + air // 2, body=R(pitch=6.0), loc=(0, 0, height * 0.74))
    c.pose(peak + air - 1, {**arms(arm, SIDE_OUT), **legs(arm, STAND)}, body=R(pitch=0.0), loc=(0, 0, height * 0.35))
    c.pose(peak + air + 3, {**legs(arm, CROUCH)}, body=R(pitch=9.0), loc=(0, 0, -0.08))


def p_jump_early(arm, y0, y1):
    c = Clip(arm, "P_JumpEarly", 120)
    _ready(c, 0)
    _jump(c, 36, 0.9)
    # 刃がまだ来ていない → 気づいて慌てて小さくもう一度
    c.pose(54, {**arms(arm, SIDE_OUT), **legs(arm, TUCK)}, body=R(pitch=-6.0, roll=6.0), loc=(0, 0, 0.62))
    c.pose(62, {**arms(arm, SIDE_UP), **legs(arm, CROUCH)}, body=R(pitch=8.0, roll=-8.0), loc=(0, 0, -0.06))
    c.pose(72, body=R(pitch=-4.0, roll=10.0), loc=(0, 0, 0.0))
    c.pose(82, body=R(pitch=2.0, roll=-6.0))
    c.pose(96, {**arms(arm, REST)}, body=R(pitch=0.0))
    _ready(c, 120)
    _blade(c, [(0, y0), (96, y1), (98, y0), (120, y0)], 120, y0)
    return c.finish()


def p_jump_late(arm, y0, y1):
    """遅すぎ: 刃が来る 51 フレーム目に踏み切ったばかり → 足をすくわれて前へ 1 回転して尻もち、目を回す。"""
    c = Clip(arm, "P_JumpLate", 168)
    _ready(c, 0)
    c.pose(40, {**arms(arm, BACK_ARMS), **legs(arm, CROUCH)}, body=R(pitch=10.0), loc=(0, 0, -0.08))
    c.pose(50, {**arms(arm, ARMS_UP), **legs(arm, STAND)}, body=R(pitch=-4.0), loc=(0, 0, 0.25))
    # すくわれる: 前（-Y）へ回りながら飛ぶ（Root の回転で体ごと 1 回転）
    for f, ang, y, z in ((54, 60.0, -0.25, 0.55), (58, 150.0, -0.55, 0.7), (62, 240.0, -0.85, 0.55),
                         (66, 330.0, -1.1, 0.25), (69, 360.0, -1.2, 0.05)):
        c.pose(f, {**arms(arm, SIDE_OUT), **legs(arm, TUCK)}, root=R(pitch=ang), loc=(0, y, z))
    c.pose(70, root=R(pitch=0.0), loc=(0, -1.2, 0.0))
    # 尻もち（脚を前へ投げ出して座る）→ 目を回す（体がぐるぐる）→ 立ち上がって戻る
    sit_legs = [(0.0, -0.9, -0.4), (0.0, -0.95, -0.3), (0.0, -0.6, 0.8), None]
    c.pose(74, {**arms(arm, SIDE_OUT), **legs(arm, sit_legs)}, body=R(pitch=-6.0), loc=(0, -1.25, -0.42))
    for k in range(6):
        a = k / 6.0 * math.tau
        c.pose(80 + k * 7, body=R(pitch=-4.0 + 4.0 * math.sin(a), roll=7.0 * math.cos(a)), loc=(0, -1.25, -0.42))
    c.pose(130, {**arms(arm, REST), **legs(arm, CROUCH)}, body=R(pitch=12.0), loc=(0, -1.0, -0.1))
    c.pose(146, {**legs(arm, STAND)}, body=R(pitch=0.0), loc=(0, -0.4, 0.0))
    _ready(c, 168)
    _blade(c, [(0, y0), (96, y1), (98, y0), (168, y0)], 168, y0)
    return c.finish()


def p_double(arm, y0, y1):
    """2 枚続けて: 刃が 60 フレームで走り、もう一度 60 フレームで走る（足元は 32・104 フレーム目）。"""
    c = Clip(arm, "P_Double", 144)
    _ready(c, 0)
    _jump(c, 32, 1.0, prep=10, air=12)
    c.pose(56, {**arms(arm, READY_ARMS), **legs(arm, KNEES)}, body=R(pitch=6.0, roll=-4.0), loc=(0, 0, -0.03))
    _jump(c, 104, 1.0, prep=10, air=12)
    c.pose(126, {**arms(arm, SIDE_OUT)}, body=R(pitch=-4.0, roll=4.0))
    _ready(c, 144)
    v = (y1 - y0) / 60.0
    t0 = 32 - (0 - y0) / v
    t1 = 104 - (0 - y0) / v
    _blade(c, [(0, y0), (int(t0), y0), (int(t0) + 60, y1), (int(t0) + 61, y0), (int(t1), y0), (int(t1) + 60, y1),
               (int(t1) + 61, y0), (144, y0)], 144, y0)
    return c.finish()


def p_fast(arm, y0, y1):
    """速い刃（48 フレームで 5.3 m、足元は 25 フレーム目）。"""
    c = Clip(arm, "P_Fast", 96)
    _ready(c, 0)
    _jump(c, 25, 1.05, prep=9, air=12)
    c.pose(50, {**arms(arm, SIDE_OUT)}, body=R(pitch=-3.0))
    _ready(c, 96)
    _blade(c, [(0, y0), (48, y1), (50, y0), (96, y0)], 96, y0)
    return c.finish()


def p_reverse(arm, y0, y1):
    """逆走（前から来る）: 気配で振り向き（体ごと 150°）、向き直って跳ぶ（足元は 45 フレーム目）。"""
    c = Clip(arm, "P_Reverse", 120)
    _ready(c, 0)
    c.pose(10, body=R(pitch=2.0, yaw=40.0))
    c.pose(18, body=R(pitch=2.0, yaw=-30.0), loc=(0, 0, 0.0))
    c.pose(24, body=R(pitch=4.0))
    _jump(c, 45, 1.1)
    _ready(c, 120)
    span = y1 - y0
    ts = int(45 - y1 / (span / 88.0))
    # 前から後ろへ 88 フレームで走り、後ろの端で一瞬で前へ戻る（基本の Practice と同じ）
    _blade(c, [(0, y1), (ts, y1), (ts + 88, y0), (ts + 89, y1), (120, y1)], 120, y0)
    return c.finish()


def p_clipboard(arm):
    """休憩中に記録を書く（左腕で板を脇に抱えた形、右手で小さく書く、ときどき見上げてうなずく）。4 秒ループ。"""
    c = Clip(arm, "P_Clipboard", 96)
    hold = [(0.6, -0.4, -0.2), (0.4, -0.6, -0.1), (0.2, -0.7, 0.0)]
    write = [(0.55, -0.45, -0.25), (0.35, -0.6, -0.2), (0.15, -0.7, -0.1)]
    c.pose(0, {**arms(arm, hold, write), **legs(arm, STAND)}, body=R(pitch=12.0), root=R(), loc=(0, 0, 0))
    for k in range(6):
        s = 1.0 if k % 2 else -1.0
        w = [write[0], write[1], (0.15 + 0.06 * s, -0.7, -0.1)]
        c.pose(8 + k * 6, arms(arm, hold, w), body=R(pitch=12.0, roll=s * 0.8))
    c.pose(56, body=R(pitch=-2.0))
    c.pose(64, body=R(pitch=6.0))
    c.pose(72, body=R(pitch=0.0))
    c.pose(96, {**arms(arm, hold, write), **legs(arm, STAND)}, body=R(pitch=12.0), root=R(), loc=(0, 0, 0))
    return c.finish()


def p_fan_self(arm):
    """暑い: 右手を顔の横でぱたぱた、肩で息（体が上下）。2 秒ループ。"""
    c = Clip(arm, "P_FanSelf", 48)
    fan_a = [(0.85, -0.3, 0.42), (0.6, -0.5, 0.62), (0.4, -0.6, 0.69)]
    fan_b = [(0.85, -0.3, 0.42), (0.75, -0.45, 0.48), (0.65, -0.55, 0.52)]
    c.pose(0, {**arms(arm, REST, fan_a), **legs(arm, STAND)}, body=R(pitch=-3.0), root=R(), loc=(0, 0, 0))
    for k in range(1, 8):
        c.pose(k * 6, arms(arm, REST, fan_b if k % 2 else fan_a), body=R(pitch=-3.0 + (1.5 if k % 2 else 0.0)),
               loc=(0, 0, 0.008 if k % 2 else 0.0))
    c.pose(48, {**arms(arm, REST, fan_a), **legs(arm, STAND)}, body=R(pitch=-3.0), root=R(), loc=(0, 0, 0))
    return c.finish()


def build_trainee(arm, y0, y1) -> dict:
    out = {}
    for fn in (lambda a: p_jump_early(a, y0, y1), lambda a: p_jump_late(a, y0, y1), lambda a: p_double(a, y0, y1),
               lambda a: p_fast(a, y0, y1), lambda a: p_reverse(a, y0, y1), p_clipboard, p_fan_self):
        info = fn(arm)
        out[info["action"]] = info
    return out

"""先生ゴドーくんの動きの部品（docs/lecture_hall_plan.md の 2a）。godotkun_lecturer.glb に NLA トラックとして入れ、
Godot の授業の進行役（第 3 段階）が状況に応じて選んでつなぐ。

約束（lsb_anim と同じ）:
- 24 fps。名前は "T_" で始める。ループ（loop=True）は最初と最後が同じ姿勢。1 回きり（one-shot）は休止の姿勢で始まって終わる
  （つなぎ目で姿勢が飛ばない）。
- 位置の移動・向き（歩く道筋、黒板への向き）と、黒板に書く手先の位置合わせは Godot（Root を動かす・IK）。ここでは体の
  表情（傾き・弾み・腕・脚）だけを作る。歩き・横歩きは足踏み（その場）。
- 頭と胴は曲げない（Body ごと）。腕は体の正面より前へ届かない（手を合わせるのは頭の上）。
体の座標: +X = 本人の左、-Y = 正面、+Z = 上。R(pitch 前に倒れる, yaw 左を向く, roll 左へ傾く)（度）。
"""
from __future__ import annotations

import math

from lsb_anim import ARMS_UP, CROUCH, HANG, STAND, TUCK, Clip, R, arms, legs

FPS = 24

# ------------------------------------------------------------------ shared poses（左腕の向き、右は鏡像で作る）
SIDE_OUT = [(0.95, 0.0, -0.3), (0.98, -0.05, -0.15), (0.98, -0.1, -0.1)]          # 横へ下げ気味に開く
SIDE_UP = [(0.85, 0.05, 0.52), (0.75, 0.0, 0.66), (0.66, -0.05, 0.75)]             # 斜め上へ
HIGH = [(0.25, 0.0, 0.97), (0.15, -0.05, 0.99), (0.1, -0.1, 0.99)]                # ほぼ真上
CLAP_TOP = [(0.35, -0.12, 0.93), (0.05, -0.15, 0.99), (-0.08, -0.15, 0.98)]       # 頭の上で手を合わせる（左）
REST = HANG


def seg(*dirs):
    return [tuple(d) for d in dirs]


def lerp_dir(a, b, t):
    return [(a[i][0] + (b[i][0] - a[i][0]) * t, a[i][1] + (b[i][1] - a[i][1]) * t, a[i][2] + (b[i][2] - a[i][2]) * t)
            for i in range(3)]


def walk_leg(phase):
    """歩きの片脚（phase 0..1）: 太ももの前後、膝の曲げ、足の向き。"""
    s = math.sin(phase * math.tau)
    lift = max(0.0, math.sin(phase * math.tau + math.pi * 0.5))
    thigh = (0.0, -0.32 * s, -0.95)
    shin = (0.0, -0.32 * s + 0.3 * lift, -0.95)
    foot = (0.0, -0.75, -0.66 + 0.2 * lift)
    return [thigh, shin, foot, None]


def rest_pose(c: Clip, f: int):
    c.pose(f, {**arms(c.arm, REST), **legs(c.arm, STAND)}, body=R(), root=R(), loc=(0, 0, 0))


# ------------------------------------------------------------------ loops

def t_idle(arm):
    """待機: ゆっくりの呼吸（前後 1.5°）と重心の移動（左右 1.5°）、腕は体の脇で少し揺れる。6 秒。"""
    c = Clip(arm, "T_Idle", 144)
    rest_pose(c, 0)
    for f, p, r in ((36, 1.5, 1.2), (72, 0.0, -1.5), (108, 1.2, -0.4)):
        sway = lerp_dir(REST, SIDE_OUT, 0.06)
        c.pose(f, arms(arm, sway if f == 36 else REST), body=R(pitch=p, roll=r), loc=(0, 0, 0.004 if p > 0 else 0.0))
    return c.finish()


def t_idle_look(arm):
    """見回し: 体ごと左 → 右 → 正面（教室を見渡す）。8 秒。"""
    c = Clip(arm, "T_IdleLook", 192)
    rest_pose(c, 0)
    c.pose(30, body=R(yaw=22.0, pitch=-2.0))
    c.pose(78, body=R(yaw=22.0, pitch=-1.0, roll=1.0))
    c.pose(110, body=R(yaw=-24.0, pitch=-2.0))
    c.pose(158, body=R(yaw=-24.0, pitch=0.0, roll=-1.0))
    c.pose(192, body=R())
    return c.finish()


def t_walk(arm):
    """歩き（その場の足踏み、1 歩 0.5 秒）: 脚を交互に振り、体は弾んで左右に揺れ、腕は脚と逆に振る。"""
    c = Clip(arm, "T_Walk", 24)
    for k in range(5):
        f = k * 6
        ph = k / 4.0
        swing = math.sin(ph * math.tau)
        la = lerp_dir(REST, [(0.55, -0.35, -0.76), (0.5, -0.4, -0.76), (0.45, -0.45, -0.77)], max(0.0, swing))
        la = lerp_dir(la, [(0.55, 0.35, -0.76), (0.5, 0.3, -0.81), (0.45, 0.25, -0.86)], max(0.0, -swing))
        ra = lerp_dir(REST, [(0.55, -0.35, -0.76), (0.5, -0.4, -0.76), (0.45, -0.45, -0.77)], max(0.0, -swing))
        ra = lerp_dir(ra, [(0.55, 0.35, -0.76), (0.5, 0.3, -0.81), (0.45, 0.25, -0.86)], max(0.0, swing))
        rots = {**arms(arm, la, ra), **legs(arm, walk_leg(ph), walk_leg(ph + 0.5))}
        c.pose(f, rots, body=R(pitch=3.0, roll=4.0 * swing), root=R(), loc=(0, 0, 0.025 * abs(math.cos(ph * math.tau))))
    return c.finish()


def t_side_step(arm):
    """横歩き（黒板に沿って、その場、1 歩 0.5 秒）: 左脚を開く → 右脚を寄せる。体は弾み、書く右腕は上げたまま。"""
    c = Clip(arm, "T_SideStep", 24)
    open_l = [(0.35, 0.0, -0.94), (0.3, 0.0, -0.95), None, None]
    close = [None, None, None, None]
    high_r = [(0.75, 0.1, 0.65), (0.6, 0.1, 0.79), (0.5, 0.05, 0.86)]
    for f, lg, rg, z in ((0, close, close, 0.0), (6, open_l, close, 0.03), (12, open_l, close, 0.0),
                         (18, close, close, 0.03), (24, close, close, 0.0)):
        c.pose(f, {**arms(arm, REST, high_r), **legs(arm, lg, rg)}, body=R(roll=-3.0 if f in (6, 12) else 0.0, pitch=2.0),
               root=R(), loc=(0, 0, z))
    return c.finish()


def t_write_stance(arm):
    """書く構え（半身。Godot が黒板に対して体を 45° に向け、右手を IK で線に沿わせる）: 体は黒板側（右）へ 4° 傾け、
    左腕は脇で軽く開いて釣り合いを取る。呼吸と、1 画ごとの小さな上下は Godot が足す。4 秒。"""
    c = Clip(arm, "T_WriteStance", 96)
    ready_r = [(0.8, -0.1, 0.59), (0.7, -0.15, 0.7), (0.6, -0.2, 0.77)]
    left = lerp_dir(REST, SIDE_OUT, 0.35)
    base = {**arms(arm, left, ready_r), **legs(arm, [(0.12, 0.0, -0.99), None, None, None],
                                               [(-0.05, 0.05, -0.99), None, None, None])}
    c.pose(0, base, body=R(roll=-4.0, pitch=1.0), root=R(), loc=(0, 0, 0))
    c.pose(48, body=R(roll=-4.5, pitch=2.0), loc=(0, 0, -0.006))
    c.pose(96, base, body=R(roll=-4.0, pitch=1.0), root=R(), loc=(0, 0, 0))
    return c.finish()


def t_write_tiptoe(arm):
    """背伸びで書く（上の段に届かない）: つま先立ち（足首とつま先を曲げて 6 cm 上がる）、ぷるぷる左右に揺れる。2 秒。"""
    c = Clip(arm, "T_WriteTiptoe", 48)
    toe = [(0.0, 0.08, -0.99), (0.0, 0.0, -1.0), (0.0, -0.2, -0.98), (0.0, -0.95, 0.3)]
    reach_r = HIGH
    left = lerp_dir(REST, SIDE_OUT, 0.6)
    for k in range(7):
        f = k * 8
        if f > 48:
            break
        wob = (1.0 if k % 2 == 0 else -1.0) * (2.5 if 0 < k < 6 else 0.0)
        c.pose(f, {**arms(arm, left, reach_r), **legs(arm, toe)}, body=R(roll=-6.0 + wob, pitch=-3.0), root=R(),
               loc=(0, 0, 0.06 + (0.005 if k % 2 else 0.0)))
    c.pose(48, {**arms(arm, left, reach_r), **legs(arm, toe)}, body=R(roll=-6.0, pitch=-3.0), root=R(), loc=(0, 0, 0.06))
    return c.finish()


def t_jump_write(arm):
    """跳びながら書く（1 画ごとに跳ぶ）: しゃがむ → 右手を上へ伸ばして跳ぶ（0.3 m）→ 着地で沈む。0.8 秒で 1 回。"""
    c = Clip(arm, "T_JumpWrite", 20)
    left = lerp_dir(REST, SIDE_OUT, 0.5)
    c.pose(0, {**arms(arm, left, SIDE_UP), **legs(arm, STAND)}, body=R(pitch=2.0), root=R(), loc=(0, 0, 0))
    c.pose(4, {**legs(arm, CROUCH)}, body=R(pitch=8.0), loc=(0, 0, -0.06))
    c.pose(9, {**arms(arm, SIDE_UP, HIGH), **legs(arm, TUCK)}, body=R(pitch=-4.0, roll=-4.0), loc=(0, 0, 0.3))
    c.pose(14, {**legs(arm, STAND)}, body=R(pitch=-2.0), loc=(0, 0, 0.05))
    c.pose(17, {**arms(arm, left, SIDE_UP), **legs(arm, CROUCH)}, body=R(pitch=6.0), loc=(0, 0, -0.05))
    c.pose(20, {**arms(arm, left, SIDE_UP), **legs(arm, STAND)}, body=R(pitch=2.0), root=R(), loc=(0, 0, 0))
    return c.finish()


def t_wipe_loop(arm):
    """黒板を拭く（几帳面: 右腕を高い所から左右へ大きく往復、体も左右に揺れる）。1 往復 1.2 秒。"""
    c = Clip(arm, "T_WipeLoop", 29)
    a = [(0.7, 0.3, 0.65), (0.55, 0.35, 0.76), (0.45, 0.35, 0.82)]
    b = [(0.9, -0.3, 0.3), (0.85, -0.35, 0.4), (0.8, -0.35, 0.48)]
    left = lerp_dir(REST, SIDE_OUT, 0.4)
    c.pose(0, {**arms(arm, left, a), **legs(arm, STAND)}, body=R(roll=-3.0, yaw=-6.0), root=R(), loc=(0, 0, 0))
    c.pose(14, arms(arm, left, b), body=R(roll=3.0, yaw=6.0), loc=(0, 0, 0.01))
    c.pose(29, {**arms(arm, left, a), **legs(arm, STAND)}, body=R(roll=-3.0, yaw=-6.0), root=R(), loc=(0, 0, 0))
    return c.finish()


def t_wipe_messy(arm):
    """ぐるぐる適当に消す: 右腕を上で大きく回す（円）、体がつられて回る。1 周 1 秒。"""
    c = Clip(arm, "T_WipeMessy", 24)
    left = lerp_dir(REST, SIDE_OUT, 0.3)
    for k in range(5):
        f = k * 6
        a = k / 4.0 * math.tau
        d = (0.75 + 0.15 * math.cos(a), 0.25 * math.sin(a), 0.6 + 0.2 * math.cos(a))
        r_arm = [d, (d[0] * 0.9, d[1] * 1.1, d[2] + 0.1), (d[0] * 0.85, d[1] * 1.2, d[2] + 0.15)]
        c.pose(f, {**arms(arm, left, r_arm), **legs(arm, STAND)}, body=R(roll=-4.0 * math.cos(a), yaw=5.0 * math.sin(a)),
               root=R(), loc=(0, 0, 0.008 * (1 + math.cos(a))))
    return c.finish()


def t_explain(arm):
    """説明（教壇の横で教室へ）: 左手を差し出して小さく振り、うなずき気味に前後。4 秒。"""
    c = Clip(arm, "T_Explain", 96)
    a = [(0.55, -0.78, -0.1), (0.45, -0.85, 0.2), (0.4, -0.75, 0.5)]
    b = [(0.75, -0.6, 0.05), (0.6, -0.7, 0.3), (0.55, -0.55, 0.6)]
    rest_pose(c, 0)
    c.pose(16, arms(arm, a, REST), body=R(pitch=6.0))
    c.pose(32, arms(arm, b, REST), body=R(pitch=1.0, roll=2.0))
    c.pose(50, arms(arm, a, REST), body=R(pitch=7.0, roll=-1.0))
    c.pose(68, arms(arm, b, REST), body=R(pitch=2.0, roll=2.0))
    c.pose(84, arms(arm, REST), body=R(pitch=0.0))
    c.pose(96, arms(arm, REST), body=R())
    return c.finish()


def t_sit_grade(arm, seat_lift):
    """座って採点（夜、踏み台に腰かける）: 脚を前へ、右手で小さく書く（赤ペン）、ときどき伸び。4 秒ループ。"""
    c = Clip(arm, "T_SitGrade", 96)
    seat = (0.0, 0.0, seat_lift)
    from lsb_anim import SEATED
    write = [(0.9, -0.2, -0.38), (0.8, -0.35, -0.48), (0.7, -0.45, -0.56)]
    c.pose(0, {**arms(arm, REST, write), **legs(arm, SEATED)}, body=R(pitch=10.0), root=R(), loc=seat)
    for k in range(6):
        f = 8 + k * 8
        s = 1.0 if k % 2 == 0 else -1.0
        w = [write[0], write[1], (0.7 + 0.1 * s, -0.45, -0.56)]
        c.pose(f, arms(arm, REST, w), body=R(pitch=11.0, roll=s * 0.8), loc=seat)
    c.pose(64, {**arms(arm, ARMS_UP)}, body=R(pitch=-6.0), loc=(0.0, 0.0, seat_lift + 0.02))
    c.pose(76, {**arms(arm, ARMS_UP)}, body=R(pitch=-8.0, roll=2.0), loc=(0.0, 0.0, seat_lift + 0.02))
    c.pose(96, {**arms(arm, REST, write), **legs(arm, SEATED)}, body=R(pitch=10.0), root=R(), loc=seat)
    return c.finish()


def t_doze_stand(arm):
    """立ったまま居眠り（10 分放置）: ゆっくり前へ垂れて、かくん → はっ（びくっと跳ねる）→ また垂れる。6 秒。"""
    c = Clip(arm, "T_DozeStand", 144)
    rest_pose(c, 0)
    c.pose(50, body=R(pitch=9.0, roll=3.0), loc=(0, 0, -0.01))
    c.pose(84, body=R(pitch=15.0, roll=4.0), loc=(0, 0, -0.02))
    c.pose(90, {**arms(arm, SIDE_OUT)}, body=R(pitch=-6.0, roll=-1.0), loc=(0, 0, 0.06))
    c.pose(98, {**arms(arm, REST)}, body=R(pitch=-1.0), loc=(0, 0, 0.0))
    c.pose(120, body=R(pitch=3.0))
    c.pose(144, {**arms(arm, REST), **legs(arm, STAND)}, body=R(), root=R(), loc=(0, 0, 0))
    return c.finish()


# ------------------------------------------------------------------ one-shots

def t_bow(arm):
    """お辞儀（起立・礼、あいさつ）: 体を 30° 前へ倒して止め、戻る。2 秒。"""
    c = Clip(arm, "T_Bow", 48)
    rest_pose(c, 0)
    front = [(0.35, -0.3, -0.89), (0.25, -0.35, -0.9), (0.15, -0.4, -0.9)]
    c.pose(12, arms(arm, front), body=R(pitch=30.0), loc=(0, 0, -0.01))
    c.pose(28, arms(arm, front), body=R(pitch=31.0), loc=(0, 0, -0.01))
    c.pose(40, arms(arm, REST), body=R(pitch=-1.0))
    rest_pose(c, 48)
    return c.finish()


def t_crouch_pickup(arm):
    """しゃがんで拾う（折れたチョーク）: しゃがむ → 右手を床へ → 拾って立つ。2.5 秒。"""
    c = Clip(arm, "T_CrouchPickup", 60)
    rest_pose(c, 0)
    reach = [(0.4, -0.45, -0.8), (0.3, -0.5, -0.81), (0.25, -0.55, -0.8)]
    c.pose(14, {**legs(arm, CROUCH), **arms(arm, REST, reach)}, body=R(pitch=24.0), loc=(0, 0, -0.12))
    c.pose(24, {**legs(arm, CROUCH), **arms(arm, REST, reach)}, body=R(pitch=27.0, roll=-3.0), loc=(0, 0, -0.14))
    c.pose(30, {**legs(arm, CROUCH)}, body=R(pitch=20.0), loc=(0, 0, -0.12))
    c.pose(44, {**legs(arm, STAND), **arms(arm, REST, SIDE_UP)}, body=R(pitch=-3.0), loc=(0, 0, 0.0))
    rest_pose(c, 60)
    return c.finish()


def t_sneeze(arm):
    """くしゃみ（黒板消しの粉）: 息を吸って反る（はっ、はっ）→ 前へびくん（くしゅん）→ ぶるっと首を振る。2 秒。"""
    c = Clip(arm, "T_Sneeze", 48)
    rest_pose(c, 0)
    c.pose(8, arms(arm, lerp_dir(REST, SIDE_OUT, 0.4)), body=R(pitch=-6.0), loc=(0, 0, 0.01))
    c.pose(14, body=R(pitch=-10.0), loc=(0, 0, 0.02))
    c.pose(17, arms(arm, SIDE_OUT), body=R(pitch=22.0), loc=(0, 0, -0.03))
    c.pose(22, body=R(pitch=14.0), loc=(0, 0, 0.0))
    c.pose(28, arms(arm, REST), body=R(pitch=4.0, roll=4.0))
    c.pose(33, body=R(pitch=3.0, roll=-4.0))
    c.pose(38, body=R(pitch=2.0, roll=2.0))
    rest_pose(c, 48)
    return c.finish()


def t_point_tap(arm):
    """指し棒で黒板を指して、トントンと 2 回叩く（「ここ大事」）。2.4 秒。"""
    c = Clip(arm, "T_PointTap", 58)
    rest_pose(c, 0)
    point = [(0.3, -0.82, 0.48), (0.25, -0.78, 0.58), (0.22, -0.72, 0.66)]
    tap = [(0.3, -0.82, 0.48), (0.25, -0.86, 0.45), (0.2, -0.9, 0.38)]
    c.pose(12, arms(arm, REST, point), body=R(pitch=-4.0))
    for k, f in enumerate((22, 28, 34, 40)):
        c.pose(f, arms(arm, REST, tap if k % 2 == 0 else point), body=R(pitch=-2.0 if k % 2 == 0 else -4.0))
    c.pose(48, arms(arm, REST, point), body=R(pitch=-3.0))
    rest_pose(c, 58)
    return c.finish()


def t_clap_dust(arm):
    """手の粉をはたく（頭の上で手を 3 回打つ、体は少し縮める）。1.6 秒。"""
    c = Clip(arm, "T_ClapDust", 38)
    rest_pose(c, 0)
    apart = [(0.6, -0.1, 0.79), (0.45, -0.15, 0.88), (0.35, -0.15, 0.92)]
    for k, f in enumerate((8, 12, 16, 20, 24, 28)):
        c.pose(f, arms(arm, CLAP_TOP if k % 2 else apart), body=R(pitch=-2.0, roll=1.5 if k % 2 else -1.5),
               loc=(0, 0, 0.008 if k % 2 else 0.0))
    rest_pose(c, 38)
    return c.finish()


def t_snap_chalk(arm):
    """新しいチョークをパキッと半分に折る（頭の上で両手を合わせ、ひねって開く）。1.5 秒。"""
    c = Clip(arm, "T_SnapChalk", 36)
    rest_pose(c, 0)
    c.pose(10, arms(arm, CLAP_TOP), body=R(pitch=-3.0))
    c.pose(16, arms(arm, CLAP_TOP), body=R(pitch=-3.0, roll=2.0))
    c.pose(19, arms(arm, [(0.7, -0.1, 0.7), (0.6, -0.15, 0.78), (0.5, -0.2, 0.84)]), body=R(pitch=1.0), loc=(0, 0, 0.012))
    c.pose(26, arms(arm, SIDE_UP), body=R(pitch=0.0))
    rest_pose(c, 36)
    return c.finish()


def t_throw(arm):
    """チョーク投げ（居眠りの生徒へ、ぽこっ）: 体ごと右へひねって振りかぶり、左へ戻しながら上から投げる。1.6 秒。"""
    c = Clip(arm, "T_Throw", 38)
    rest_pose(c, 0)
    wind = [(0.55, 0.6, 0.58), (0.4, 0.65, 0.64), (0.3, 0.7, 0.65)]
    release = [(0.6, -0.55, 0.58), (0.65, -0.6, 0.45), (0.7, -0.62, 0.35)]
    c.pose(12, {**arms(arm, SIDE_OUT, wind), **legs(arm, [(0.1, 0.0, -0.99), None, None, None])},
           body=R(yaw=-22.0, pitch=-6.0, roll=-3.0), loc=(0, 0, 0.01))
    c.pose(17, arms(arm, REST, release), body=R(yaw=14.0, pitch=10.0, roll=2.0), loc=(0, 0, 0.02))
    c.pose(24, arms(arm, REST, [(0.7, -0.4, -0.2), (0.7, -0.45, -0.3), (0.7, -0.45, -0.4)]), body=R(yaw=8.0, pitch=6.0))
    rest_pose(c, 38)
    return c.finish()


def t_clap_erasers(arm):
    """黒板消しを 2 つ打ち合わせる（頭の上で 3 回。粉は Godot の粒子）→ 顔をそむける。2 秒。"""
    c = Clip(arm, "T_ClapErasers", 48)
    rest_pose(c, 0)
    apart = [(0.8, -0.05, 0.6), (0.65, -0.1, 0.75), (0.55, -0.12, 0.83)]
    for k, f in enumerate((8, 13, 18, 23, 28, 33)):
        c.pose(f, arms(arm, CLAP_TOP if k % 2 else apart), body=R(pitch=-2.0, yaw=-10.0 if k > 1 else 0.0))
    c.pose(40, arms(arm, REST), body=R(yaw=-14.0, pitch=4.0))
    rest_pose(c, 48)
    return c.finish()


def t_drink(arm):
    """湯呑みのストローで飲む（腕が口に届かない）: 教壇の上のストローへ体ごと前に傾け、ちゅーっと 3 回、はぁ。3 秒。"""
    c = Clip(arm, "T_Drink", 72)
    rest_pose(c, 0)
    c.pose(14, body=R(pitch=18.0, yaw=8.0), loc=(0, 0, -0.03))
    for k, f in enumerate((22, 30, 38)):
        c.pose(f, body=R(pitch=19.0 + (1.0 if k % 2 else 0.0), yaw=8.0), loc=(0, 0, -0.03 - 0.005 * (k % 2)))
    c.pose(48, arms(arm, lerp_dir(REST, SIDE_OUT, 0.3)), body=R(pitch=-6.0), loc=(0, 0, 0.01))
    c.pose(60, arms(arm, REST), body=R(pitch=-2.0))
    rest_pose(c, 72)
    return c.finish()


def t_look_clock(arm):
    """黒板の上の時計を見上げる → 「おっと」と小さく跳ねて向き直る。2.5 秒。"""
    c = Clip(arm, "T_LookClock", 60)
    rest_pose(c, 0)
    c.pose(14, body=R(pitch=-16.0), loc=(0, 0, 0.01))
    c.pose(32, body=R(pitch=-17.0, roll=1.0), loc=(0, 0, 0.01))
    c.pose(38, {**arms(arm, SIDE_OUT), **legs(arm, TUCK)}, body=R(pitch=-4.0), loc=(0, 0, 0.12))
    c.pose(44, {**arms(arm, REST), **legs(arm, CROUCH)}, body=R(pitch=6.0), loc=(0, 0, -0.04))
    rest_pose(c, 60)
    return c.finish()


def t_nod(arm):
    """うなずき（満足げ）: 体ごと 2 回前へ。1 秒。"""
    c = Clip(arm, "T_Nod", 24)
    rest_pose(c, 0)
    c.pose(6, body=R(pitch=9.0))
    c.pose(11, body=R(pitch=-1.0))
    c.pose(16, body=R(pitch=7.0))
    rest_pose(c, 24)
    return c.finish()


def t_head_tilt(arm):
    """首をかしげる（字が右下がり）: 体ごと右へ 12° 傾けて止め、戻る。2 秒。"""
    c = Clip(arm, "T_HeadTilt", 48)
    rest_pose(c, 0)
    c.pose(12, arms(arm, REST, lerp_dir(REST, SIDE_OUT, 0.3)), body=R(roll=-12.0, pitch=-2.0))
    c.pose(34, body=R(roll=-13.0, pitch=-2.0))
    rest_pose(c, 48)
    return c.finish()


def t_sad(arm):
    """しょんぼり（誰も手を挙げない）: 体が前へ垂れ、腕は内へだらり、足元を見る。3 秒。"""
    c = Clip(arm, "T_Sad", 72)
    rest_pose(c, 0)
    limp = [(0.3, 0.0, -0.95), (0.2, -0.05, -0.98), (0.15, -0.1, -0.98)]
    c.pose(20, arms(arm, limp), body=R(pitch=16.0), loc=(0, 0, -0.03))
    c.pose(52, arms(arm, limp), body=R(pitch=17.0, roll=2.0), loc=(0, 0, -0.03))
    rest_pose(c, 72)
    return c.finish()


def t_wave(arm):
    """手を振る（さようなら・会釈）: 右手を高く挙げて 4 回振る。2.5 秒。"""
    c = Clip(arm, "T_Wave", 60)
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


def t_whistle(arm):
    """ホイッスル（実習の合図）: 胸をふくらませて反り（息を吸う）、ピーッで前へ弾む。1.5 秒。"""
    c = Clip(arm, "T_Whistle", 36)
    rest_pose(c, 0)
    c.pose(8, arms(arm, lerp_dir(REST, SIDE_OUT, 0.5)), body=R(pitch=-8.0), loc=(0, 0, 0.02))
    c.pose(12, body=R(pitch=6.0), loc=(0, 0, -0.01))
    c.pose(24, body=R(pitch=5.0, roll=1.0), loc=(0, 0, -0.01))
    rest_pose(c, 36)
    return c.finish()


def t_stamp(arm):
    """合格のハンコを押す（右手を上げて、ぐっと押し下げ、ぐりぐり）。1.5 秒。"""
    c = Clip(arm, "T_Stamp", 36)
    rest_pose(c, 0)
    raise_r = [(0.8, -0.3, 0.5), (0.75, -0.35, 0.56), (0.7, -0.4, 0.6)]
    press = [(0.85, -0.35, -0.38), (0.8, -0.4, -0.45), (0.75, -0.45, -0.49)]
    c.pose(8, arms(arm, REST, raise_r), body=R(pitch=-3.0))
    c.pose(13, arms(arm, REST, press), body=R(pitch=14.0), loc=(0, 0, -0.03))
    c.pose(18, body=R(pitch=15.0, roll=2.0), loc=(0, 0, -0.035))
    c.pose(22, body=R(pitch=15.0, roll=-2.0), loc=(0, 0, -0.035))
    c.pose(28, arms(arm, REST, raise_r), body=R(pitch=0.0))
    rest_pose(c, 36)
    return c.finish()


def t_startle(arm):
    """びくっ（チョークのキーッ、照明のちらつき、地響き）: 腕が開いて小さく跳ね、肩をすくめる。1 秒。"""
    c = Clip(arm, "T_Startle", 24)
    rest_pose(c, 0)
    c.pose(4, {**arms(arm, SIDE_OUT), **legs(arm, TUCK)}, body=R(pitch=-6.0), loc=(0, 0, 0.08))
    c.pose(9, {**arms(arm, lerp_dir(REST, SIDE_OUT, 0.4)), **legs(arm, CROUCH)}, body=R(pitch=4.0), loc=(0, 0, -0.03))
    rest_pose(c, 24)
    return c.finish()


def t_happy_hop(arm):
    """得意げ（円がきれいに描けた・正解）: 両腕を上げて 2 回跳ねる。1.5 秒。"""
    c = Clip(arm, "T_HappyHop", 36)
    rest_pose(c, 0)
    for k, f in enumerate((6, 11, 16, 21)):
        up = k % 2 == 0
        c.pose(f, {**arms(arm, ARMS_UP if up else SIDE_UP), **legs(arm, TUCK if up else CROUCH)},
               body=R(pitch=-4.0 if up else 4.0), loc=(0, 0, 0.16 if up else -0.03))
    rest_pose(c, 36)
    return c.finish()


def t_look_up(arm):
    """天井を見上げる（地響き・水の音・照明）: 体ごと反ってゆっくり左右を見る。3 秒。"""
    c = Clip(arm, "T_LookUp", 72)
    rest_pose(c, 0)
    c.pose(14, body=R(pitch=-20.0, yaw=10.0))
    c.pose(40, body=R(pitch=-21.0, yaw=-12.0))
    c.pose(58, body=R(pitch=-12.0))
    rest_pose(c, 72)
    return c.finish()


def build_library(arm, seat_lift_stool: float) -> dict:
    """先生の全部の部品を作って NLA トラックに積む。戻り値は名前 → 情報。"""
    out = {}
    for fn in (t_idle, t_idle_look, t_walk, t_side_step, t_write_stance, t_write_tiptoe, t_jump_write, t_wipe_loop,
               t_wipe_messy, t_explain, t_doze_stand, t_bow, t_crouch_pickup, t_sneeze, t_point_tap, t_clap_dust,
               t_snap_chalk, t_throw, t_clap_erasers, t_drink, t_look_clock, t_nod, t_head_tilt, t_sad, t_wave,
               t_whistle, t_stamp, t_startle, t_happy_hop, t_look_up):
        info = fn(arm)
        out[info["action"]] = info
    info = t_sit_grade(arm, seat_lift_stool)
    out[info["action"]] = info
    return out

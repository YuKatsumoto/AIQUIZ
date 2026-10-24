"""The Sky Gate drop clips (W3).  Loaded after dm_lib.py into the same namespace:

    ns = {}
    exec(open(SRC + "/dm_lib.py", encoding="utf-8").read(), ns)
    exec(open(SRC + "/dm_clips.py", encoding="utf-8").read(), ns)
    ns["build_all"]()        # or ns["build"]("SD_Jump_Basic_A")

Each clip is a timeline:
  limbs  key poses in the upright frame (functions of time), blended with an ease between keys
  body   pitch / long / yaw / roll curves (degrees, monotone cubic) turned about the pelvis head
  root   ground travel before `leave`, a ballistic arc after it (and the floor again after `land`)
  box    from `box_from` the pose blends into SD_Box_Loop(t - settle); from `settle` on it IS that loop
The design is docs/sudden_death_v2/heli_drop.md 2.1-2.3 and 3.1.
"""
import json
import math

from mathutils import Vector

RUN_PLAY = 0.8                    # SD_Ramp_Run_Out = UAL Sprint_Loop at 0.8x
WALK_PLAY = 1.5                   # SD_Ramp_Walk = UAL Walk_Loop at 1.5x
RUN_UP_PLAY = 1.0                 # SD_Ramp_Run_Up = UAL Jog_Fwd_Loop
BOX_LEN = 2.0
SIT_LEN = 2.4
GRAVITY = 9.8
LAND_DROP = 4.0                   # heli_drop.md 2.3: the plane passes ~4 m above the floor
SETTLE_LIMIT = 1.2
TAU = math.tau


def foot_speed(name, play):
    """Ground speed (m/s) that keeps the planted foot of a UAL loop still: mean backward speed
    of the lower foot while it is on the ground."""
    length = ual_length(name)
    steps = int(round(length * FPS))
    total, count = 0.0, 0
    prev = None
    for i in range(steps + 1):
        t = length * i / steps
        w = world(ual(name, t, loop=False))
        feet = [(w["foot_l"].translation, w["ball_l"].translation), (w["foot_r"].translation, w["ball_r"].translation)]
        low = min(range(2), key=lambda k: min(feet[k][0].z, feet[k][1].z))
        y = feet[low][1].y
        h = min(feet[low][0].z, feet[low][1].z)
        if prev is not None and prev[0] == low and h < 0.03 and prev[2] < 0.03:
            total += (y - prev[1])
            count += 1
        prev = (low, y, h)
    per_frame = total / max(count, 1)
    return per_frame * FPS * play


RUN_SPEED = foot_speed("Sprint_Loop", RUN_PLAY)
WALK_SPEED = foot_speed("Walk_Loop", WALK_PLAY)
RUN_UP_SPEED = foot_speed("Jog_Fwd_Loop", RUN_UP_PLAY)
RUN_LEN = ual_length("Sprint_Loop") / RUN_PLAY
WALK_LEN = ual_length("Walk_Loop") / WALK_PLAY
RUN_UP_LEN = ual_length("Jog_Fwd_Loop") / RUN_UP_PLAY


# ------------------------------------------------------------------ sources (upright frame)

_CACHE = {}


def K(builder, on_floor=False, knees=False):
    """A static key pose from a spec builder (solved once).  on_floor: drop the pelvis so the feet
    (and the knees when knees=True) touch z = 0."""
    pose = solve(builder())
    if on_floor:
        pose = ground(pose, knees)

    def f(_t):
        return pose
    return f


def run_out_pose(tt):
    key = ("run", round(tt * 240))
    if key not in _CACHE:
        s = spine({}, fwd=8.0)
        _CACHE[key] = solve(s, ual("Sprint_Loop", tt, speed=RUN_PLAY))
    return _CACHE[key]


def run_src(start=0.0, warp=None):
    def f(t):
        return run_out_pose(start + (warp(t) if warp else t))
    return f


def decel(ta, tb):
    """Time warp: full speed until ta, easing to a stop at tb (returns elapsed 'run time')."""
    def w(t):
        if t <= ta:
            return t
        if t >= tb:
            return ta + (tb - ta) * 0.5
        x = t - ta
        return ta + x - x * x / (2.0 * (tb - ta))
    return w


def idle_src(start=0.0):
    def f(t):
        return ual("Idle_Loop", start + t)
    return f


def sit_base(t=0.0):
    return ual("Sitting_Idle_Loop", t)


# --- the box (skydive arch) -----------------------------------------------------------

def box_spec(t, lean=None):
    k = TAU / BOX_LEN
    s = {}
    a = math.sin(k * t)
    b = math.sin(k * t + 1.7)
    c = math.sin(2 * k * t + 0.6)
    fwd = 0.0
    up = 0.0
    arm_up = 0.0
    arm_out = 0.0
    knee = 0.0
    if lean == "forward":
        fwd, arm_up, knee = 0.0, -1.0, -1.0
    elif lean == "back":
        arm_up, knee = 1.0, 1.0
    spine(s, fwd=-22.0 + 2.0 * a + (8.0 if lean == "forward" else 0.0) - (6.0 if lean == "back" else 0.0))
    neck(s, pitch=-52.0 + 3.0 * b + (10.0 if lean == "forward" else 0.0))
    for side, ph in (("l", 0.0), ("r", 1.3)):
        f1 = math.sin(k * t + ph)
        f2 = math.sin(2 * k * t + ph * 0.7)
        bank = 0.0
        if lean in ("left", "right"):
            # the side we move toward drops: that arm tucks in a little, the other reaches out
            toward = (lean == "left") == (side == "l")
            bank = -1.0 if toward else 1.0
        if lean == "forward":
            upper = v(side, 0.62, 0.0 - 0.02 * f1, -0.62)
            lower = v(side, 0.30, 0.10, -0.95)
            palm = v(side, -0.2, 0.3, 0.0)
        elif lean == "back":
            upper = v(side, 0.55, 0.12 + 0.02 * f1, 0.80)
            lower = v(side, 0.22, 0.20, 0.97)
            palm = v(side, 0.0, 1.0, 0.1)
        else:
            upper = v(side, 0.95 + 0.06 * bank, 0.10 + 0.03 * f1, 0.28 + 0.12 * bank + 0.03 * f2)
            lower = v(side, 0.10 + 0.05 * bank, -0.32 + 0.04 * f2, 0.94)
            palm = v(side, 0.0, 1.0, 0.0)
        arm(s, side, upper, lower, palm=palm)
        fingers(s, side, 14.0 + 4.0 * f2, 8.0)
        if lean == "forward":
            thigh = v(side, 0.22, -0.20, -0.96)
            calf = v(side, 0.16, -0.30, -0.94)
        elif lean == "back":
            thigh = v(side, 0.28, -0.18, -0.94)
            calf = v(side, 0.12, -0.92, -0.38)
        else:
            thigh = v(side, 0.30 + 0.04 * bank, -0.22 + 0.02 * f1, -0.93)
            calf = v(side, 0.16, -0.90 + 0.05 * f2, -0.42)
        leg(s, side, thigh, calf, foot=(calf * 0.6 + v(side, 0.0, 0.0, -1.0) * 0.4).normalized(),
            sole=v(side, 0.0, -0.5, 0.85))
    return s


def box_body(t, lean=None):
    k = TAU / BOX_LEN
    pitch = 90.0 + 1.6 * math.sin(k * t + 0.4)
    long_ = 2.2 * math.sin(k * t + 2.1)
    yaw = 1.4 * math.sin(2 * k * t)
    if lean == "left":
        long_ -= 16.0
    elif lean == "right":
        long_ += 16.0
    elif lean == "forward":
        pitch += 12.0
    elif lean == "back":
        pitch -= 10.0
    return body_rot(pitch=pitch, long=long_, yaw=yaw)


def BOX(t, lean=None):
    t = math.fmod(t, BOX_LEN)
    if t < 0:
        t += BOX_LEN
    key = ("box", lean, round(t * 240))
    if key not in _CACHE:
        p = solve(box_spec(t, lean))
        p, _shift = rotate_body(p, box_body(t, lean))
        _CACHE[key] = zero_root(p)
    return _CACHE[key]


# --- key poses ---------------------------------------------------------------------------

def takeoff(foot, arms="up"):
    """Push-off from `foot` ("l"/"r"): that leg extended behind on its toes, the other knee driven up."""
    other = "r" if foot == "l" else "l"
    s = spine({}, fwd=6.0)
    neck(s, pitch=-10.0)
    leg(s, foot, v(foot, 0.04, -0.42, -0.90), v(foot, 0.03, -0.62, -0.78), foot=v(foot, 0.02, -0.55, -0.83), sole=v(foot, 0.0, -0.83, 0.55))
    leg(s, other, v(other, 0.06, 0.80, -0.60), v(other, 0.04, -0.20, -0.98), foot=v(other, 0.0, 0.70, -0.70), sole=v(other, 0.0, -0.70, -0.70))
    for side in ("l", "r"):
        if arms == "up":
            arm(s, side, v(side, 0.70, 0.35, 0.62), v(side, 0.50, 0.45, 0.75), palm=v(side, 0.0, 0.5, -0.8))
        else:
            # long-jump arms: the arm opposite the knee forward and high, the other back
            if side == other:
                arm(s, side, v(side, 0.30, -0.70, -0.40), v(side, 0.25, -0.60, -0.70), palm=v(side, 0.3, 0.0, -1.0))
            else:
                arm(s, side, v(side, 0.35, 0.80, 0.50), v(side, 0.25, 0.70, 0.67), palm=v(side, 0.0, 0.0, -1.0))
        fingers(s, side, 25.0, 12.0)
    return s


def spread(arms_back=0.0):
    s = spine({}, fwd=-10.0)
    neck(s, pitch=-30.0)
    for side in ("l", "r"):
        arm(s, side, v(side, 0.95, 0.05 - arms_back, 0.30), v(side, 0.90, 0.10 - arms_back, 0.40), palm=v(side, 0.0, 0.7, -0.7))
        fingers(s, side, 10.0, 6.0)
        leg(s, side, v(side, 0.14, -0.30, -0.95), v(side, 0.10, -0.55, -0.83), foot=v(side, 0.05, -0.50, -0.85), sole=v(side, 0.0, -0.85, 0.50))
    return s


def superman():
    s = spine({}, fwd=-8.0)
    neck(s, pitch=-30.0)
    for side in ("l", "r"):
        arm(s, side, v(side, 0.12, 0.08, 0.99), v(side, 0.10, 0.10, 0.99), palm=v(side, 0.0, 1.0, 0.0))
        flat_hand(s, side)
        leg(s, side, v(side, 0.04, -0.06, -1.0), v(side, 0.03, -0.10, -1.0), foot=v(side, 0.02, -0.20, -0.98), sole=v(side, 0.0, -0.98, 0.2))
    return s


def tuck(hug=True):
    s = spine({}, fwd=28.0)
    neck(s, pitch=22.0)
    for side in ("l", "r"):
        leg(s, side, v(side, 0.14, 0.80, 0.58), v(side, 0.06, -0.25, -0.97), foot=v(side, 0.02, 0.30, -0.95), sole=v(side, 0.0, -0.95, -0.3))
        if hug:
            arm(s, side, v(side, 0.30, 0.78, -0.55), v(side, -0.40, 0.80, -0.45), palm=v(side, -1.0, 0.0, 0.0))
        else:
            arm(s, side, v(side, 0.40, 0.70, -0.60), v(side, 0.10, 0.20, -0.97), palm=v(side, -1.0, 0.0, 0.0))
        fist(s, side)
    return s


def crouch(arms_back=True):
    s = spine({}, fwd=24.0)
    neck(s, pitch=-12.0)
    for side in ("l", "r"):
        leg(s, side, v(side, 0.10, 0.75, -0.66), v(side, 0.06, -0.62, -0.78), foot=v(side, 0.02, 0.86, -0.51))
        if arms_back:
            arm(s, side, v(side, 0.20, -0.75, -0.62), v(side, 0.15, -0.65, -0.74), palm=v(side, 0.3, 0.0, -1.0))
        else:
            arm(s, side, v(side, 0.25, 0.70, -0.65), v(side, 0.15, 0.85, -0.50), palm=v(side, 0.0, 0.0, -1.0))
        fingers(s, side, 25.0, 10.0)
    return s


def reach_up():
    """Jumping up with straight legs and arms overhead (backflip launch, pencil jump)."""
    s = spine({}, fwd=-6.0)
    neck(s, pitch=-15.0)
    for side in ("l", "r"):
        arm(s, side, v(side, 0.20, 0.10, 0.97), v(side, 0.15, 0.05, 0.99), palm=v(side, -1.0, 0.0, 0.0))
        fingers(s, side, 8.0, 5.0)
        leg(s, side, v(side, 0.04, -0.04, -1.0), v(side, 0.03, -0.10, -1.0), foot=v(side, 0.02, -0.30, -0.95), sole=v(side, 0.0, -0.95, 0.3))
    return s


def spin_tuck():
    s = spine({}, fwd=-4.0)
    neck(s, pitch=-10.0)
    for side in ("l", "r"):
        arm(s, side, v(side, 0.30, 0.55, -0.78), v(side, -0.85, 0.45, 0.25), palm=v(side, 0.0, -1.0, 0.0))
        fist(s, side)
        leg(s, side, v(side, 0.02, -0.04, -1.0), v(side, 0.02, -0.08, -1.0), foot=v(side, 0.02, -0.25, -0.97), sole=v(side, 0.0, -0.97, 0.25))
    return s


def starfish():
    s = spine({}, fwd=-6.0)
    neck(s, pitch=-18.0)
    for side in ("l", "r"):
        arm(s, side, v(side, 0.82, 0.05, 0.57), v(side, 0.80, 0.08, 0.59), palm=v(side, 0.0, 1.0, 0.0))
        fingers(s, side, 0.0, 0.0)
        leg(s, side, v(side, 0.42, 0.02, -0.91), v(side, 0.40, 0.0, -0.92), foot=v(side, 0.30, -0.15, -0.94), sole=v(side, 0.0, -0.94, 0.15))
    return s


def flail(t, amount=1.0):
    """Windmilling arms and kicking legs (the trip, the hesitant jump)."""
    s = spine({}, fwd=-8.0 + 6.0 * math.sin(TAU * 1.7 * t))
    neck(s, pitch=-20.0 + 10.0 * math.sin(TAU * 2.1 * t + 0.5), yaw=15.0 * math.sin(TAU * 1.3 * t))
    for side, ph in (("l", 0.0), ("r", math.pi * 0.85)):
        a = TAU * 2.4 * t + ph
        upper = v(side, 0.75, 0.65 * math.cos(a) * amount, 0.65 * math.sin(a) * amount + 0.15)
        lower = v(side, 0.65, 0.70 * math.cos(a + 0.6) * amount, 0.70 * math.sin(a + 0.6) * amount + 0.2)
        arm(s, side, upper, lower, palm=v(side, 0.0, 0.0, -1.0))
        fingers(s, side, 5.0, 5.0)
        b = TAU * 2.8 * t + ph * 1.3
        thigh = v(side, 0.22, 0.45 * math.sin(b) * amount, -0.88)
        calf = v(side, 0.15, -0.55 - 0.25 * math.cos(b) * amount, -0.80)
        leg(s, side, thigh, calf, foot=v(side, 0.05, -0.4, -0.9), sole=v(side, 0.0, -0.9, 0.4))
    return s


def flail_src(amount=1.0):
    def f(t):
        key = ("flail", amount, round(t * 240))
        if key not in _CACHE:
            _CACHE[key] = solve(flail(t, amount))
        return _CACHE[key]
    return f


def attention(salute=0.0):
    """Standing to attention; salute 0..1 raises the doll's right hand (UAL left: the doll mirrors) to the brow."""
    s = {}
    neck(s, pitch=-4.0)
    for side in ("l", "r"):
        leg(s, side, v(side, 0.02, 0.0, -1.0), v(side, 0.02, -0.02, -1.0), foot=v(side, 0.10, 0.86, -0.51))
    arm(s, "r", v("r", 0.10, 0.02, -1.0), v("r", 0.06, 0.06, -1.0), palm=v("r", -1.0, 0.0, 0.0))
    flat_hand(s, "r")
    down_u, down_l = v("l", 0.10, 0.02, -1.0), v("l", 0.06, 0.06, -1.0)
    up_u, up_l = v("l", 0.86, 0.38, 0.12), v("l", -0.80, 0.12, 0.58)
    k = smooth(salute)
    arm(s, "l", down_u.lerp(up_u, k).normalized(), down_l.lerp(up_l, k).normalized(),
        palm=v("l", -1.0, 0.0, 0.0).lerp(v("l", 0.0, 0.55, -0.85), k).normalized())
    flat_hand(s, "l")
    return s


def peek():
    """Leaning over the edge to look down, arms out for balance."""
    s = spine({}, fwd=38.0)
    neck(s, pitch=35.0)
    for side in ("l", "r"):
        leg(s, side, v(side, 0.06, -0.12, -0.99), v(side, 0.04, 0.10, -0.99), foot=v(side, 0.05, 0.86, -0.51))
        arm(s, side, v(side, 0.80, -0.30, 0.25), v(side, 0.75, -0.20, 0.50), palm=v(side, 0.0, 0.0, -1.0))
        fingers(s, side, 30.0, 10.0)
    return s


def stomp(t):
    """Nervous running on the spot (knees alternate up), arms bent and shaking."""
    s = spine({}, fwd=8.0)
    neck(s, pitch=10.0, yaw=20.0 * math.sin(TAU * 3.0 * t))
    ph = TAU * 3.2 * t
    for side, off in (("l", 0.0), ("r", math.pi)):
        lift = max(0.0, math.sin(ph + off))
        leg(s, side, v(side, 0.06, 0.15 + 0.6 * lift, -0.97 + 0.35 * lift), v(side, 0.04, -0.05 - 0.4 * lift, -1.0),
            foot=v(side, 0.03, 0.86 - 0.3 * lift, -0.51 - 0.3 * lift))
        arm(s, side, v(side, 0.30, 0.25, -0.92), v(side, 0.10, 0.85 + 0.1 * math.sin(ph * 2 + off), 0.40), palm=v(side, -1.0, 0.0, 0.0))
        fist(s, side)
    return s


def stomp_src():
    def f(t):
        key = ("stomp", round(t * 240))
        if key not in _CACHE:
            _CACHE[key] = ground(solve(stomp(t)))
        return _CACHE[key]
    return f


def brace():
    """Eyes shut, fists at the chin, knees bent: about to jump."""
    s = spine({}, fwd=14.0)
    neck(s, pitch=28.0)
    for side in ("l", "r"):
        leg(s, side, v(side, 0.08, 0.45, -0.89), v(side, 0.05, -0.45, -0.89), foot=v(side, 0.03, 0.86, -0.51))
        arm(s, side, v(side, 0.18, 0.55, -0.82), v(side, -0.35, 0.40, 0.85), palm=v(side, 0.0, -1.0, 0.0))
        fist(s, side)
    return s


def air_balance(t):
    """Dropping feet first from the ramp: arms out and circling slowly, knees a little up."""
    s = spine({}, fwd=6.0)
    neck(s, pitch=10.0)
    for side, ph in (("l", 0.0), ("r", 1.2)):
        a = TAU * 1.1 * t + ph
        arm(s, side, v(side, 0.85, 0.15 * math.cos(a), 0.45 + 0.15 * math.sin(a)), v(side, 0.80, 0.25 * math.cos(a + 0.5), 0.55),
            palm=v(side, 0.0, 0.0, -1.0))
        fingers(s, side, 12.0, 8.0)
    leg(s, "l", v("l", 0.10, 0.45, -0.89), v("l", 0.06, -0.30, -0.95), foot=v("l", 0.03, 0.80, -0.60))
    leg(s, "r", v("r", 0.10, 0.20, -0.98), v("r", 0.06, -0.15, -0.99), foot=v("r", 0.03, 0.80, -0.60))
    return s


def air_src():
    def f(t):
        key = ("air", round(t * 240))
        if key not in _CACHE:
            _CACHE[key] = solve(air_balance(t))
        return _CACHE[key]
    return f


def touch_down(knee=0.25):
    """Legs reaching for the floor just before a landing."""
    s = spine({}, fwd=10.0)
    neck(s, pitch=12.0)
    for side in ("l", "r"):
        leg(s, side, v(side, 0.10, knee, -0.97), v(side, 0.08, -knee * 0.8, -0.99), foot=v(side, 0.05, 0.86, -0.51))
        arm(s, side, v(side, 0.80, 0.30, 0.35), v(side, 0.75, 0.40, 0.40), palm=v(side, 0.0, 0.0, -1.0))
        fingers(s, side, 15.0, 8.0)
    return s


def hero_pose(look=0.0):
    """Superhero landing: doll's right knee and fist on the floor (UAL left side; the doll mirrors)."""
    s = spine({}, fwd=34.0 - 20.0 * look)
    neck(s, pitch=30.0 - 50.0 * look)
    # kneeling leg (UAL l): knee on the floor under the hip, shin back along the floor
    leg(s, "l", v("l", 0.12, 0.05, -0.99), v("l", 0.04, -0.98, -0.12), foot=v("l", 0.02, -0.97, -0.20), sole=v("l", 0.0, -0.2, 0.98))
    # front leg (UAL r): foot planted ahead, knee up
    leg(s, "r", v("r", 0.16, 0.92, -0.38), v("r", 0.06, -0.08, -0.99), foot=v("r", 0.05, 0.86, -0.51))
    # fist on the floor beside the kneeling leg, other arm out behind
    arm(s, "l", v("l", 0.25, 0.42, -0.87), v("l", 0.10, 0.20, -0.97), palm=v("l", -1.0, 0.0, 0.0))
    fist(s, "l")
    arm(s, "r", v("r", 0.55, -0.55, -0.62), v("r", 0.45, -0.60, -0.66), palm=v("r", 0.0, 0.0, -1.0))
    fingers(s, "r", 25.0, 10.0)
    return s


def victory_v():
    """The 'stick': both arms up in a V, chest out."""
    s = spine({}, fwd=-8.0)
    neck(s, pitch=-12.0)
    for side in ("l", "r"):
        arm(s, side, v(side, 0.55, 0.10, 0.83), v(side, 0.50, 0.12, 0.86), palm=v(side, 0.0, 1.0, 0.0))
        flat_hand(s, side)
        leg(s, side, v(side, 0.07, 0.0, -1.0), v(side, 0.05, -0.02, -1.0), foot=v(side, 0.10, 0.86, -0.51))
    return s


def stick_land():
    """Knees bent, arms forward-out for balance (the moment of the stick)."""
    s = spine({}, fwd=22.0)
    neck(s, pitch=-5.0)
    for side in ("l", "r"):
        leg(s, side, v(side, 0.12, 0.70, -0.71), v(side, 0.08, -0.66, -0.75), foot=v(side, 0.08, 0.86, -0.51))
        arm(s, side, v(side, 0.60, 0.70, 0.30), v(side, 0.55, 0.72, 0.40), palm=v(side, 0.0, 0.0, -1.0))
        flat_hand(s, side)
    return s


# ------------------------------------------------------------------ the timeline machinery

class Clip:
    def __init__(self, name, length, kind, loop=False):
        self.name = name
        self.length = length
        self.kind = kind
        self.loop = loop
        self.limbs = []
        self.curves = {"pitch": [], "long": [], "yaw": [], "roll": []}
        self.pivot = None
        self.travel = lambda t: 0.0
        self.leave = None
        self.settle = None
        self.box_from = None
        self.land = None
        self.air = None
        self.after_land = lambda t: 0.0
        self.contact = None
        self.extra = {}
        self.speed = 0.0

    def key(self, t, fn, ease=smooth):
        self.limbs.append((t, fn, ease))
        return self

    def curve(self, channel, keys):
        self.curves[channel] = keys
        return self

    def limb_pose(self, t):
        ks = self.limbs
        if t <= ks[0][0]:
            return ks[0][1](t)
        for i in range(len(ks) - 1):
            t0, f0, _e0 = ks[i]
            t1, f1, e1 = ks[i + 1]
            if t <= t1:
                w = e1((t - t0) / (t1 - t0)) if t1 > t0 else 1.0
                if w <= 0.0:
                    return f0(t)
                if w >= 1.0:
                    return f1(t)
                return mix(f0(t), f1(t), w)
        return ks[-1][1](t)

    def frame(self, t):
        p = self.limb_pose(t)
        ang = {c: pchip(k, t) for c, k in self.curves.items() if k}
        # the twist / turn on the spot always about the pelvis, then the dive / flip about the pivot
        p, _shift = rotate_body(p, body_rot(long=ang.get("long", 0.0), roll=ang.get("roll", 0.0)))
        piv = self.pivot(t) if self.pivot else None
        p, _shift = rotate_body(p, body_rot(pitch=ang.get("pitch", 0.0), yaw=ang.get("yaw", 0.0)), piv)
        if self.box_from is not None and t >= self.box_from:
            w = 1.0 if t >= self.settle else smooth((t - self.box_from) / (self.settle - self.box_from))
            p = mix(p, BOX(t - self.settle), w)
        return zero_root(p)


def bake_clip(c):
    frames = int(round(c.length * FPS))
    # the box takes over on a whole frame, so "settle" in the json is exact
    if c.settle is not None:
        c.settle = round(c.settle * FPS) / FPS
    poses = [c.frame(i / FPS) for i in range(frames + 1)]
    if c.loop:
        poses[-1] = copy_pose(poses[0])
    heads = [world(p)["pelvis"].translation.copy() for p in poses]
    feet = []
    for p in poses:
        w = world(p)
        feet.append([w[b].translation.copy() for b in ("ball_leaf_l", "ball_leaf_r", "foot_l", "foot_r")])
    # Godot frame: x = Blender x, y = Blender z, z = -Blender y
    p0 = heads[0]
    root = []
    leave_i = None if c.leave is None else int(round(c.leave * FPS))
    land_i = None if c.land is None else int(round(c.land * FPS))
    h_leave = heads[leave_i].z if leave_i is not None else 0.0
    if c.air is not None and land_i is not None:
        tau_l = (land_i - leave_i) / FPS
        vy = c.air.get("vy", 0.0)
        drop = c.air.get("drop", LAND_DROP)
        g_eff = 2.0 * (vy * tau_l + drop + h_leave - heads[land_i].z) / (tau_l * tau_l)
    else:
        g_eff = GRAVITY
    land_xz = None
    for i, h in enumerate(heads):
        t = i / FPS
        if leave_i is None or i <= leave_i:
            x = h.x - p0.x
            z = c.travel(t) + (-(h.y - p0.y))
            y = 0.0
        else:
            tau = (i - leave_i) / FPS
            hl = heads[leave_i]
            base_x = hl.x - p0.x
            base_z = c.travel(c.leave) + (-(hl.y - p0.y))
            vz = c.air.get("vz", 0.0)
            vx = c.air.get("vx", 0.0)
            k = c.air.get("drag", 0.0)
            if k > 0:
                ax = (1.0 - math.exp(-k * tau)) / k
            else:
                ax = tau
            x = base_x + vx * ax
            z = base_z + vz * ax
            y = c.air.get("vy", 0.0) * tau - 0.5 * g_eff * tau * tau + h_leave - h.z
            if land_i is not None and i >= land_i:
                if land_xz is None:
                    tl = (land_i - leave_i) / FPS
                    al = (1.0 - math.exp(-k * tl)) / k if k > 0 else tl
                    land_xz = (base_x + vx * al, base_z + vz * al, heads[land_i])
                lx, lz, hland = land_xz
                x = lx + (h.x - hland.x)
                z = lz + c.after_land(t - c.land) + (-(h.y - hland.y))
                y = -c.air.get("drop", LAND_DROP)
        root.append([round(x, 4), round(y, 4), round(z, 4)])
    if c.loop:
        cyc = c.speed * c.length
        root[-1] = [root[0][0], root[0][1], round(root[0][2] + cyc, 4)]
    bake(c.name, poses)
    info = {
        "length": round(frames / FPS, 4), "loop": c.loop, "kind": c.kind, "fps": FPS,
        "leave": -1.0 if c.leave is None else round(leave_i / FPS, 4),
        "settle": -1.0 if c.settle is None else round(c.settle, 4),
        "land": -1.0 if c.land is None else round(land_i / FPS, 4),
        "root": root,
    }
    if c.contact is not None:
        info["contact"] = c.contact
    elif c.kind in ("bench", "ramp"):
        info["contact"] = [[0.0, info["length"]]]
    elif c.leave is not None:
        info["contact"] = [[0.0, info["leave"]]] + ([[info["land"], info["length"]]] if c.land is not None else [])
    else:
        info["contact"] = []
    if c.speed:
        info["speed"] = round(c.speed, 4)
    if leave_i is not None:
        # how far ahead of the start (under the pelvis) the outermost foot point is when the feet leave
        hl = heads[leave_i]
        front = max(-(f.y - hl.y) for f in feet[leave_i])
        info["edge"] = round(root[leave_i][2] + front, 4)
    info.update(c.extra)
    return info


# ------------------------------------------------------------------ the clips

def jump_common(c, leave, settle, box_from, vz, vy, drag=1.1):
    c.leave = leave
    c.settle = settle
    c.box_from = box_from
    c.air = {"vz": vz, "vy": vy, "drag": drag}
    c.travel = lambda t: RUN_SPEED * t
    c.extra["run_phase"] = 0.0
    return c


def clip_basic_a():
    c = Clip("SD_Jump_Basic_A", 1.25, "jump")
    # Sprint_Loop: the left foot is down at frames 1-4 (0.04-0.17 s at 0.8x); push off on it
    c.key(0.0, run_src(0.0)).key(0.10, run_src(0.0), smooth).key(0.21, K(lambda: takeoff("l"), True), smooth)
    c.key(0.42, K(spread), smooth)
    c.curve("pitch", [(0.0, 0.0), (0.14, 4.0), (0.30, 25.0), (0.55, 66.0), (0.85, 88.0), (1.0, 90.0)])
    c.curve("yaw", [(0.2, 0.0), (0.55, 4.0), (0.85, -2.0), (1.0, 0.0)])
    return jump_common(c, leave=0.21, settle=1.0, box_from=0.62, vz=RUN_SPEED * 0.95, vy=2.2)


def clip_basic_b():
    c = Clip("SD_Jump_Basic_B", 1.3, "jump")
    start = RUN_LEN * 0.5   # the right foot comes down next (Sprint_Loop frames 12-14)
    c.key(0.0, run_src(start)).key(0.12, run_src(start), smooth).key(0.23, K(lambda: takeoff("r", arms="long"), True), smooth)
    c.key(0.48, K(lambda: spread(arms_back=0.25)), smooth)
    c.curve("pitch", [(0.0, 0.0), (0.16, 6.0), (0.34, 30.0), (0.62, 70.0), (0.92, 89.0), (1.05, 90.0)])
    c.curve("long", [(0.2, 0.0), (0.5, -8.0), (0.85, 3.0), (1.05, 0.0)])
    jump_common(c, leave=0.23, settle=1.05, box_from=0.68, vz=RUN_SPEED * 0.95, vy=2.0)
    c.extra["run_phase"] = round(start, 4)
    return c


def clip_superman():
    c = Clip("SD_Jump_Superman", 1.3, "jump")
    c.key(0.0, run_src(0.0)).key(0.08, run_src(0.0), smooth).key(0.20, K(lambda: takeoff("l"), True), smooth)
    c.key(0.36, K(superman), smooth).key(0.70, K(superman), smooth)
    c.curve("pitch", [(0.0, 0.0), (0.12, 8.0), (0.30, 52.0), (0.45, 78.0), (0.75, 84.0), (1.05, 90.0)])
    return jump_common(c, leave=0.20, settle=1.05, box_from=0.70, vz=RUN_SPEED * 1.1, vy=1.2)


def clip_spin_dive():
    c = Clip("SD_Jump_SpinDive", 1.3, "jump")
    c.key(0.0, run_src(0.0)).key(0.08, run_src(0.0), smooth).key(0.20, K(lambda: takeoff("l"), True), smooth)
    c.key(0.34, K(spin_tuck), smooth).key(0.74, K(spin_tuck), smooth)
    c.curve("pitch", [(0.0, 0.0), (0.18, 6.0), (0.45, 45.0), (0.80, 82.0), (1.05, 90.0)])
    # one full twist about the long axis (a whole turn keeps the belly down at the end)
    c.curve("long", [(0.20, 0.0), (0.30, 25.0), (0.60, 210.0), (0.84, 345.0), (0.95, 360.0)])
    return jump_common(c, leave=0.20, settle=1.08, box_from=0.76, vz=RUN_SPEED * 0.95, vy=2.4)


def clip_starfish():
    c = Clip("SD_Jump_Starfish", 1.35, "jump")
    c.key(0.0, run_src(0.0)).key(0.08, run_src(0.0), smooth).key(0.20, K(lambda: takeoff("l"), True), smooth)
    c.key(0.36, K(starfish), smooth).key(0.78, K(starfish), smooth)
    c.curve("pitch", [(0.0, 0.0), (0.20, 4.0), (0.50, 14.0), (0.78, 40.0), (1.0, 82.0), (1.12, 90.0)])
    return jump_common(c, leave=0.20, settle=1.12, box_from=0.80, vz=RUN_SPEED * 0.8, vy=3.0)


def clip_backflip():
    c = Clip("SD_Jump_Backflip", 1.95, "jump")
    w = decel(0.10, 0.42)
    c.key(0.0, run_src(0.0, w)).key(0.30, run_src(0.0, w), smooth)
    c.key(0.52, K(lambda: crouch(arms_back=False), True), smooth).key(0.68, K(crouch, True), smooth)
    c.key(0.80, K(reach_up, True), smooth).key(0.98, K(tuck), smooth).key(1.30, K(tuck), smooth)
    c.key(1.50, K(spread), smooth)
    c.travel = lambda t: RUN_SPEED * w(t)
    # turn to face the cabin on the edge, flip backwards three quarters, then a flat half turn in the box
    c.curve("long", [(0.30, 0.0), (0.58, 180.0)])
    c.curve("pitch", [(0.78, 0.0), (0.90, 40.0), (1.10, 160.0), (1.32, 250.0), (1.48, 270.0)])
    c.curve("yaw", [(1.20, 0.0), (1.48, 100.0), (1.66, 180.0)])
    c.leave = 0.80
    c.settle = 1.82
    c.box_from = 1.50
    c.air = {"vz": 1.6, "vy": 3.4, "drag": 1.1}
    c.extra["run_phase"] = 0.0
    return c


def clip_trip():
    c = Clip("SD_Jump_Trip", 1.55, "jump")
    c.key(0.0, run_src(0.0)).key(0.10, run_src(0.0), smooth).key(0.26, flail_src(0.8), smooth).key(0.86, flail_src(1.0), smooth)
    c.key(1.05, K(spread), smooth)
    # catches the toe at the edge and tumbles forward a whole somersault before the arch
    c.curve("pitch", [(0.0, 0.0), (0.12, 4.0), (0.24, 28.0), (0.45, 120.0), (0.75, 300.0), (1.0, 420.0), (1.18, 450.0)])
    c.curve("long", [(0.3, 0.0), (0.7, 25.0), (1.1, 0.0)])
    return jump_common(c, leave=0.22, settle=1.38, box_from=1.0, vz=RUN_SPEED * 0.75, vy=0.4)


def clip_cannonball():
    c = Clip("SD_Jump_Cannonball", 1.45, "jump")
    c.key(0.0, run_src(0.0)).key(0.08, run_src(0.0), smooth).key(0.20, K(lambda: takeoff("l"), True), smooth)
    c.key(0.38, K(tuck), smooth).key(0.86, K(tuck), smooth).key(1.06, K(spread), smooth)
    c.curve("pitch", [(0.0, 0.0), (0.2, 4.0), (0.45, -22.0), (0.80, -18.0), (1.05, 60.0), (1.22, 90.0)])
    return jump_common(c, leave=0.20, settle=1.30, box_from=1.0, vz=RUN_SPEED * 0.7, vy=3.3)


def clip_salute():
    c = Clip("SD_Jump_Salute", 2.55, "jump")
    w = decel(0.08, 0.40)
    c.key(0.0, run_src(0.0, w)).key(0.28, run_src(0.0, w), smooth)
    c.key(0.55, K(lambda: attention(0.0), True), smooth).key(0.74, K(lambda: attention(1.0), True), smooth)
    c.key(1.55, K(lambda: attention(1.0), True), smooth).key(1.95, K(spread), smooth)
    c.travel = lambda t: RUN_SPEED * w(t)
    c.curve("long", [(0.30, 0.0), (0.60, 180.0), (1.70, 180.0), (2.10, 360.0)])
    # stiff as a board: tips over backwards about the heels, then rolls over onto the belly
    c.curve("pitch", [(1.08, 0.0), (1.30, 12.0), (1.45, 38.0), (1.66, 80.0), (1.82, 92.0), (2.0, 90.0)])

    # the back edge of the heels once turned round (the outermost point toward the open air, -Y)
    turned, _s = rotate_body(ground(solve(attention(1.0))), body_rot(long=180.0))
    back = min(contact_points(turned), key=lambda pt: pt.y)
    heel_pivot = Vector((0.0, back.y, 0.0))

    def heel(t):
        return heel_pivot if t >= 1.0 else None
    c.pivot = heel
    c.leave = 1.42
    c.settle = 2.38
    c.box_from = 2.0
    c.air = {"vz": 1.2, "vy": 0.0, "drag": 1.1}
    c.extra["run_phase"] = 0.0
    return c


def clip_hesitate():
    # about half a second later off the edge than the basic jump (heli_drop.md 2.2): stop, peek, stamp, "えいっ"
    c = Clip("SD_Jump_Hesitate", 1.85, "jump")
    w = decel(0.04, 0.28)
    c.key(0.0, run_src(0.0, w)).key(0.20, run_src(0.0, w), smooth)
    c.key(0.33, K(peek, True), smooth).key(0.42, K(peek, True), smooth)
    c.key(0.49, stomp_src(), smooth).key(0.60, stomp_src(), smooth)
    c.key(0.66, K(brace, True), smooth).key(0.76, K(reach_up, True), smooth)
    c.key(0.90, flail_src(0.7), smooth).key(1.22, flail_src(0.9), smooth).key(1.40, K(spread), smooth)
    c.travel = lambda t: RUN_SPEED * w(t)
    c.curve("pitch", [(0.74, 0.0), (0.93, -6.0), (1.22, 40.0), (1.50, 86.0), (1.63, 90.0)])
    c.curve("long", [(0.88, 0.0), (1.18, 18.0), (1.48, 0.0)])
    c.leave = 0.76
    c.settle = 1.74
    c.box_from = 1.40
    c.air = {"vz": 1.4, "vy": 2.6, "drag": 1.1}
    c.extra["run_phase"] = 0.0
    return c


def clip_box(lean=None, name="SD_Box_Loop"):
    c = Clip(name, BOX_LEN, "box", loop=True)
    c.key(0.0, lambda t: BOX(t, lean))
    c.contact = []
    return c


def loop_clip(name, kind, src, length, speed):
    c = Clip(name, length, kind, loop=True)
    c.key(0.0, src)
    c.speed = speed
    c.travel = lambda t: speed * t
    return c


def clip_run_out():
    return loop_clip("SD_Ramp_Run_Out", "ramp", run_src(0.0), RUN_LEN, RUN_SPEED)


def clip_run_up():
    def f(t):
        key = ("runup", round(t * 240))
        if key not in _CACHE:
            s = spine({}, fwd=12.0)
            neck(s, pitch=-8.0)
            _CACHE[key] = solve(s, ual("Jog_Fwd_Loop", t, speed=RUN_UP_PLAY))
        return _CACHE[key]
    return loop_clip("SD_Ramp_Run_Up", "ramp", f, RUN_UP_LEN, RUN_UP_SPEED)


def clip_walk():
    def f(t):
        key = ("walk", round(t * 240))
        if key not in _CACHE:
            s = spine({}, fwd=6.0)
            _CACHE[key] = solve(s, ual("Walk_Loop", t, speed=WALK_PLAY))
        return _CACHE[key]
    return loop_clip("SD_Ramp_Walk", "ramp", f, WALK_LEN, WALK_SPEED)


# --- the bench ---------------------------------------------------------------------------

def sit_fidget(t):
    """Sitting_Idle_Loop is still; add the fidget of waiting for the jump: a knee bounce,
    looking around, a small sway with the plane, thumbs drumming."""
    k = TAU / SIT_LEN
    s = {}
    spine(s, fwd=4.0 + 2.0 * math.sin(k * t), side=1.5 * math.sin(k * t + 0.8))
    neck(s, pitch=4.0 * math.sin(2 * k * t + 0.3), yaw=22.0 * math.sin(k * t + 0.5))
    base = sit_base(0.0)
    p = solve(s, base)
    bounce = max(0.0, math.sin(4 * k * t))
    s2 = {"foot_r": {"delta": rx(-10.0 * bounce)}, "calf_r": {"delta": rx(4.0 * bounce)}}
    return solve(s2, p)


def sit_src():
    def f(t):
        key = ("sit", round(math.fmod(t, SIT_LEN) * 240))
        if key not in _CACHE:
            _CACHE[key] = sit_fidget(math.fmod(t, SIT_LEN))
        return _CACHE[key]
    return f


def lap(hands="rest", spread=0.0):
    """Arms over a seated base.  hands: 'rest' on the thighs, 'hips' at the belt ends, 'lap' at the buckle."""
    base = sit_base(0.0)
    w = world(base)
    s = {}
    for side in ("l", "r"):
        sh = w["upperarm_" + side].translation
        if hands == "hips":
            target = Vector((0.24 if side == "l" else -0.24, 0.30, 0.62))
        elif hands == "lap":
            target = Vector((0.04 if side == "l" else -0.04, 0.06, 0.66))
        elif hands == "fling":
            target = Vector((0.55 if side == "l" else -0.55, 0.15, 0.85))
        else:
            target = Vector((0.12 if side == "l" else -0.12, -0.12, 0.60))
        target = target + Vector((spread if side == "l" else -spread, 0.0, 0.0))
        lu, lf = (w["lowerarm_" + side].translation - sh).length, (w["hand_" + side].translation - w["lowerarm_" + side].translation).length
        pole = Vector((1.0 if side == "l" else -1.0, 0.6, -0.4))
        upper, lower = two_bone(sh, target, lu, lf, pole)
        arm(s, side, upper, lower, palm=Vector((0.0, 0.0, -1.0)) if hands != "fling" else Vector((0.0, -1.0, 0.0)))
        if hands in ("hips", "lap"):
            fingers(s, side, 55.0, 25.0)
    return solve(s, base)


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


def clip_sit():
    c = Clip("SD_Bench_Sit_Loop", SIT_LEN, "bench", loop=True)
    c.key(0.0, sit_src())
    return c


def clip_belt():
    c = Clip("SD_Bench_Belt_Click", 1.3, "bench")
    rest_pose_ = lap("rest")
    hips_ = lap("hips")
    lap_ = lap("lap")
    click = lap("lap", spread=0.0)
    c.key(0.0, lambda t: rest_pose_).key(0.30, lambda t: hips_, smooth).key(0.42, lambda t: hips_, smooth)
    c.key(0.72, lambda t: lap_, smooth).key(0.80, lambda t: click, smooth)
    c.key(1.05, lambda t: rest_pose_, smooth).key(1.3, sit_src(), smooth)
    c.extra["click"] = 0.78
    return c


def clip_unbuckle():
    c = Clip("SD_Bench_Unbuckle_Stand", 1.55, "bench")
    rest_pose_ = lap("rest")
    lap_ = lap("lap")
    fling = lap("fling")
    exit_play = 1.3
    exit_len = ual_length("Sitting_Exit") / exit_play

    def stand_up(t):
        return ual("Sitting_Exit", max(0.0, t - 0.48), loop=False, speed=exit_play)
    c.key(0.0, sit_src()).key(0.14, lambda t: lap_, smooth).key(0.26, lambda t: lap_, smooth)
    c.key(0.42, lambda t: fling, smooth).key(0.56, stand_up, smooth)
    c.key(0.48 + exit_len, stand_up, smooth).key(1.55, idle_src(0.0), smooth)
    c.extra["release"] = 0.30
    c.extra["stand"] = round(0.48 + exit_len, 4)
    return c


# --- landings (the winner drops from the ramp onto the podium, heli_drop.md 2.3) ---------

def land_common(c, leave, land, vz=2.2, vy=1.6):
    c.leave = leave
    c.land = land
    c.air = {"vz": vz, "vy": vy, "drag": 0.6, "drop": LAND_DROP}
    c.travel = lambda t: RUN_UP_SPEED * 0.6 * t
    c.extra["drop"] = LAND_DROP
    return c


def jog_src(play=0.6):
    def f(t):
        return ual("Jog_Fwd_Loop", t, speed=play)
    return f


def clip_land_stick():
    c = Clip("SD_Land_Stick", 2.9, "land")
    c.key(0.0, jog_src()).key(0.12, jog_src(), smooth).key(0.30, K(crouch, True), smooth).key(0.42, K(reach_up, True), smooth)
    c.key(0.62, air_src(), smooth).key(1.20, air_src(), smooth).key(1.44, K(lambda: touch_down(0.25)), smooth)
    c.key(1.62, K(stick_land, True), ease_out).key(1.90, K(stick_land, True), smooth).key(2.25, K(victory_v, True), smooth)
    c.key(2.9, idle_src(0.0), smooth)
    return land_common(c, leave=0.42, land=1.50)


def clip_land_hero():
    c = Clip("SD_Land_Hero", 3.2, "land")
    c.key(0.0, jog_src()).key(0.12, jog_src(), smooth).key(0.30, K(crouch, True), smooth).key(0.42, K(reach_up, True), smooth)
    c.key(0.62, air_src(), smooth).key(1.20, air_src(), smooth).key(1.44, K(lambda: touch_down(0.35)), smooth)
    c.key(1.66, K(lambda: hero_pose(0.0), True, True), ease_out).key(2.05, K(lambda: hero_pose(0.0), True, True), smooth)
    c.key(2.30, K(lambda: hero_pose(1.0), True, True), smooth).key(2.75, idle_src(0.0), smooth)
    return land_common(c, leave=0.42, land=1.50)


def clip_land_roll():
    c = Clip("SD_Land_Roll", 3.0, "land")
    roll_start = 1.50

    def roll(t):
        return ual("Roll", max(0.0, t - roll_start), loop=False)
    c.key(0.0, jog_src()).key(0.12, jog_src(), smooth).key(0.30, K(crouch, True), smooth).key(0.42, K(reach_up, True), smooth)
    c.key(0.62, air_src(), smooth).key(1.20, air_src(), smooth).key(1.44, K(lambda: touch_down(0.45)), smooth)
    c.key(1.56, roll, smooth).key(roll_start + 1.30, roll, smooth).key(3.0, idle_src(0.0), smooth)
    land_common(c, leave=0.42, land=1.50, vz=2.6)
    # the UAL roll stays on the spot: carry the body forward through it
    c.after_land = lambda u: 1.7 * smoother(u / 1.0)
    return c


def all_clips():
    return [
        clip_sit(), clip_belt(), clip_unbuckle(),
        clip_run_up(), clip_walk(), clip_run_out(),
        clip_basic_a(), clip_basic_b(),
        clip_superman(), clip_backflip(), clip_spin_dive(), clip_starfish(),
        clip_trip(), clip_cannonball(), clip_salute(), clip_hesitate(),
        clip_box(None, "SD_Box_Loop"), clip_box("left", "SD_Box_Lean_Left"), clip_box("right", "SD_Box_Lean_Right"),
        clip_box("forward", "SD_Box_Lean_Forward"), clip_box("back", "SD_Box_Lean_Back"),
        clip_land_hero(), clip_land_roll(), clip_land_stick(),
    ]


def build(name=None):
    """Bake one clip (or all) into SD_* actions and return the json info."""
    infos = {}
    for c in all_clips():
        if name is not None and c.name != name:
            continue
        infos[c.name] = bake_clip(c)
    return infos

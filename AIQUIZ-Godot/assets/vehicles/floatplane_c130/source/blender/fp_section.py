"""水上機 C-130 の胴体の断面（bpy を使わない計算だけ。普通の Python でも確かめられる）。

断面は上下で丸みの違う超楕円：x = a·sgn(c)|c|^(2/n)、v = belt + h·sgn(s)|s|^(2/n)（θ は +x から反時計回り、右半分は −π/2〜π/2）。
a（半幅）・top・bottom は c130_design.py の FUS_* を pchip でつなぐ。いちばん太い高さ belt と丸み n_top・n_bot はここで決める
（設計にない数。貨物室の床の幅がスロープの幅 3.10 になり、窓のある壁がほぼ立つように選んだ）。

輪（1 つの u の断面の点の並び）は、下の真ん中 B から右へ上がって上の真ん中 T、そこから左を下りて B へ戻る。
途中に決まった点（下の切れ目 D・R、濃紺の線 N、青・オレンジの線）を入れ、点の数をどの u でも同じにする
（格子をそのまま張れるように）。
  D：上のふた（尾の下）の縁。R：スロープの縁（|x| = 1.55）。スロープは u 11.2〜14.1 の B〜R、上のふたは u 14.1〜17.85 の B〜D。
"""
from __future__ import annotations

import importlib.util
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("fp_c130_design_s", HERE.parent / "c130_design.py")
C = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(C)

U0 = 0.5 * (C.WING_U[0] + C.WING_U[1])      # 6.6
HINGE_U = C.HINGE_U                          # 11.2
RAMP_HALF_W = C.RAMP_HALF_W                  # 1.55
FLOOR_V = C.FLOOR_V                          # 1.90
WALL = C.WALL                                # 0.18
LENGTH = C.LENGTH                            # 18.0

# スロープ：閉じると付け根から上へ RAMP_CLOSED_DEG。上面の長さ RAMP_LEN（3.20）で端が u 14.1
RAMP_CLOSED_DEG = 25.0
RAMP_END_U = HINGE_U + C.RAMP_LEN * math.cos(math.radians(RAMP_CLOSED_DEG))     # 14.100
RAMP_END_V = FLOOR_V + C.RAMP_LEN * math.sin(math.radians(RAMP_CLOSED_DEG))     # 3.252
RAMP_OPEN_END_U = HINGE_U + C.RAMP_LEN                                           # 14.4（開くと床と水平）
# 上のふた（尾の下）：u RAMP_END_U〜DOOR_END_U、幅は胴体の半幅 × DOOR_W_FACTOR（両わきは動かない「ほお」）
DOOR_END_U = 17.85
DOOR_W_FACTOR = 0.75
DOOR_MAX_HALF_W = 0.85 * RAMP_HALF_W           # 1.3175：スロープの端の幅より少し狭い（前の角は動かない）
DOOR_THICK = 0.07
# 内張りの始まり（操縦席の計器盤の奥）と終わり（尾の先）
LINING_U0 = 0.70
LINING_U1 = DOOR_END_U
NOSE_DOME_U = 0.20          # 機首の先 0.20 m を丸める（断面を中心へ縮める）
TAIL_DOME_U = LENGTH - DOOR_END_U   # 尾の先 0.15 m

# 濃紺と細い線の高さ（v）。線は機首から 0.6 m の所からスロープの付け根まで
NAVY_V = 3.00
BLUE_V = (3.04, 3.11)
ORANGE_V = (3.19, 3.27)
STRIPE_U = (0.60, HINGE_U)

# 断面の丸み（設計にない数）
F_U = [0.0, 0.6, 1.5, 3.2, 11.2, 13.0, 14.5, 16.2, 18.0]
F_V = [0.50, 0.40, 0.33, 0.31, 0.31, 0.35, 0.44, 0.53, 0.60]       # belt ＝ bottom + F·(top − bottom)
NT_U = [0.0, 1.5, 3.2, 11.2, 14.5, 18.0]
NT_V = [2.4, 2.8, 3.2, 3.2, 3.0, 2.6]
NB_U = [0.0, 1.0, 3.2, 11.2, 14.5, 18.0]
NB_V = [2.4, 3.2, 4.0, 4.0, 3.8, 3.0]

# 輪の区間ごとの点の数（右半分。B→D, D→R, R→N, N→b1, b1→b2, b2→o1, o1→o2, o2→T）
SEG_N = [6, 2, 7, 1, 1, 1, 1, 14]
K_HALF = sum(SEG_N)          # 33
K = 2 * K_HALF               # 66
SEG_START = [sum(SEG_N[:i]) for i in range(len(SEG_N))] + [K_HALF]
SEG_NAMES = ["B-D", "D-R", "R-N", "N-b1", "b1-b2", "b2-o1", "o1-o2", "o2-T"]

# 輪を置く u（スロープの付け根・端、上のふたの終わり、内張りの始まりを必ず含む）
U_STATIONS = [0.0, 0.02, 0.06, 0.12, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.95, 1.10, 1.30, 1.50, 1.75, 2.00, 2.30, 2.60,
              2.90, 3.20, 3.60, 4.00, 4.50, 5.40, 6.30, 7.20, 8.10, 9.00, 9.90, 10.60, HINGE_U, 11.60, 12.00, 12.40, 12.80, 13.20,
              13.60, RAMP_END_U, 14.40, 14.80, 15.20, 15.60, 16.00, 16.40, 16.80, 17.20, 17.50, 17.70, DOOR_END_U, 17.93, 17.98, LENGTH]


def pchip(xk, yk, x):
    return C.pchip(xk, yk, x)


def section(u):
    top, bot, a = C.top(u), C.bottom(u), C.half_w(u)
    f = pchip(F_U, F_V, u)
    return {"u": u, "a": a, "top": top, "bottom": bot, "belt": bot + f * (top - bot),
            "nt": pchip(NT_U, NT_V, u), "nb": pchip(NB_U, NB_V, u)}


def inner_section(u, wall=None):
    """内張りの断面（外形を wall だけ縮めた超楕円。点の位置は外形の点を法線で押した物と少し違う。中か外かの判定用）。"""
    s = section(u)
    w = wall_at(u) if wall is None else wall
    return dict(s, a=s["a"] - w, top=s["top"] - w, bottom=s["bottom"] + w)


def wall_at(u):
    s = section(u)
    return min(WALL, 0.22 * min(s["a"], 0.5 * (s["top"] - s["bottom"])))


def point(s, th):
    """右半分の θ（−π/2〜π/2）の点 (x, v)。"""
    c, sn = math.cos(th), math.sin(th)
    n = s["nt"] if sn >= 0 else s["nb"]
    h = (s["top"] - s["belt"]) if sn >= 0 else (s["belt"] - s["bottom"])
    x = s["a"] * abs(c) ** (2 / n)
    v = s["belt"] + h * math.copysign(abs(sn) ** (2 / n), sn)
    return x, v


def normal(s, th):
    """右半分の θ の外向きの法線 (nx, nv)。"""
    x, v = point(s, th)
    up = v >= s["belt"]
    n = s["nt"] if up else s["nb"]
    h = (s["top"] - s["belt"]) if up else (s["belt"] - s["bottom"])
    gx = (n / s["a"]) * (abs(x) / s["a"]) ** (n - 1)
    gy = (n / h) * (abs(v - s["belt"]) / h) ** (n - 1) * (1 if up else -1)
    ln = math.hypot(gx, gy)
    if ln < 1e-12:
        return (1.0, 0.0)
    return gx / ln, gy / ln


def theta_for_x_lower(s, x):
    r = min(max(x / s["a"], 0.0), 1.0)
    c = r ** (s["nb"] / 2)
    return -math.acos(min(1.0, c))


def theta_for_v(s, v):
    y = v - s["belt"]
    if y >= 0:
        h = s["top"] - s["belt"]
        return math.asin(min(1.0, (y / h) ** (s["nt"] / 2)))
    h = s["belt"] - s["bottom"]
    return -math.asin(min(1.0, (-y / h) ** (s["nb"] / 2)))


def v_at_x_lower(s, x):
    return point(s, theta_for_x_lower(s, x))[1]


def x_at_v(s, v):
    return point(s, theta_for_v(s, v))[0]


def ramp_x(u, s=None):
    s = s or section(u)
    if HINGE_U - 1e-9 <= u <= RAMP_END_U + 1e-9:
        return RAMP_HALF_W                         # スロープの縁（幅 3.10）
    if u < HINGE_U:
        return min(RAMP_HALF_W, 0.72 * s["a"])     # 前はただの頂点（機首で細くなる）
    xd = door_x(u, s)
    return min(RAMP_HALF_W, xd + 0.6 * (s["a"] - xd))


def door_x(u, s=None):
    s = s or section(u)
    if u < HINGE_U:
        return min(DOOR_MAX_HALF_W, 0.612 * s["a"])
    return min(DOOR_MAX_HALF_W, DOOR_W_FACTOR * s["a"])


def stripe_heights(u, s=None):
    """N, b1, b2, o1, o2 の高さ。スロープの付け根より後ろは R〜top の間へ同じ割合で移す（ただの頂点）。"""
    s = s or section(u)
    base = [NAVY_V, BLUE_V[0], BLUE_V[1], ORANGE_V[0], ORANGE_V[1]]
    if u <= HINGE_U:
        return base
    s0 = section(HINGE_U)
    vr0 = v_at_x_lower(s0, ramp_x(HINGE_U, s0))
    vr = v_at_x_lower(s, ramp_x(u, s))
    k = (s["top"] - vr) / (s0["top"] - vr0)
    return [vr + (b - vr0) * k for b in base]


def ring_thetas(u, s=None):
    """右半分の θ の並び（K_HALF + 1 点、B から T まで）と、決まった点の θ。"""
    s = s or section(u)
    keys = [-math.pi / 2, theta_for_x_lower(s, door_x(u, s)), theta_for_x_lower(s, ramp_x(u, s))]
    keys += [theta_for_v(s, v) for v in stripe_heights(u, s)]
    keys.append(math.pi / 2)
    for a, b in zip(keys[:-1], keys[1:]):
        if not b > a:
            raise ValueError(f"輪の決まった点の順がくずれた u={u:.3f}: {keys}")
    ths = []
    for i, n in enumerate(SEG_N):
        a, b = keys[i], keys[i + 1]
        for j in range(n):
            ths.append(a + (b - a) * j / n)
    ths.append(keys[-1])
    return ths, keys


def dome_scale(u):
    if u < NOSE_DOME_U:
        t = 1 - u / NOSE_DOME_U
        return math.sqrt(max(0.0, 1 - t * t))
    if u > DOOR_END_U:
        t = (u - DOOR_END_U) / TAIL_DOME_U
        return math.sqrt(max(0.0, 1 - t * t))
    return 1.0


def ring(u, offset=0.0):
    """u の輪（K 点、Godot の座標の (x, y, z) のタプル）と、各点の外向きの法線 (nx, ny, 0)。
    offset > 0 で法線の内側へ押した輪（内張り）。機首と尾の先は中心へ縮める。"""
    su = min(max(u, NOSE_DOME_U), DOOR_END_U)
    s = section(su)
    ths, _ = ring_thetas(su, s)
    right = []
    for th in ths:
        x, v = point(s, th)
        nx, nv = normal(s, th)
        right.append((x - offset * nx, v - offset * nv, nx, nv))
    pts = right[:]                              # B .. T（K_HALF + 1 点）
    pts += [(-x, v, -nx, nv) for (x, v, nx, nv) in reversed(right[1:-1])]   # T の次から B の前まで（左）
    sc = dome_scale(u)
    if sc < 1.0:
        cx = 0.0
        cv = 0.5 * (s["top"] + s["bottom"])
        pts = [(cx + (x - cx) * sc, cv + (v - cv) * sc, nx, nv) for (x, v, nx, nv) in pts]
    z = u - U0
    return [(x, v, z) for (x, v, _, _) in pts], [(nx, nv, 0.0) for (_, _, nx, nv) in pts]


def edge_segment(k):
    """輪の点 k → k+1 の辺が入る区間の番号（左右で同じ番号）。"""
    if k < K_HALF:
        kk = k
    else:
        kk = K - 1 - k
    for i in range(len(SEG_N)):
        if SEG_START[i] <= kk < SEG_START[i + 1]:
            return i
    return len(SEG_N) - 1


def in_ramp(u_mid, k):
    return HINGE_U < u_mid < RAMP_END_U and edge_segment(k) in (0, 1)


def in_door(u_mid, k):
    return RAMP_END_U < u_mid < DOOR_END_U and edge_segment(k) == 0


def inside_inner(u, x, v, margin=0.0):
    """点 (u, x, v) が内張りの中にあるか（超楕円の式で 1 以下）。margin だけ内張りを縮めて判定。"""
    s = inner_section(min(max(u, NOSE_DOME_U), LINING_U1))
    a = s["a"] - margin
    top, bot = s["top"] - margin, s["bottom"] + margin
    belt = s["belt"]
    if v >= belt:
        h, n = top - belt, s["nt"]
    else:
        h, n = belt - bot, s["nb"]
    if a <= 0 or h <= 0:
        return 9.9
    return (abs(x) / a) ** n + (abs(v - belt) / h) ** n

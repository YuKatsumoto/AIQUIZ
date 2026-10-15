"""新しいヘリ（乗り込めるヘリ）の寸法と、図面用の簡単な立体（ブロックアウト）。

数値はすべてここに置き、図面・寸法表・JSON（heli_pilot_spec.json）を同じ数値から作る。
座標は Godot と同じ（x 右、y 上、機首 -z、m）。図面の高さは地面（スキッドの下面）を 0 とした値。
GLB の原点は「メインローターの軸 × 重心の高さ（ORIGIN_Y）」に置く（今のヘリと同じ約束：着地したときスキッド下面が原点の ORIGIN_Y 下）。
"""
import functools
import math

import numpy as np

from blueprint_lib import (Mesh, box, cylinder, extrude_polygon_x, loft, pchip, rot_axis, superellipse_ring)

ORIGIN_Y = 1.75          # GLB の原点の高さ（地面から）＝ SKID_DROP

# ---- 胴体（外形）の断面：z ごとの 上端・下端・いちばん太い高さ・半幅
BODY_Z = [-3.14, -3.06, -2.95, -2.70, -2.25, -1.60, -0.60, 0.30, 1.15, 1.70, 2.25]
BODY_TOP = [1.47, 1.62, 1.98, 2.60, 3.16, 3.48, 3.56, 3.56, 3.38, 3.10, 2.92]
BODY_BOTTOM = [1.14, 1.00, 0.92, 0.68, 0.55, 0.52, 0.52, 0.52, 0.56, 1.30, 2.18]
BODY_BELT = [1.30, 1.33, 1.42, 1.58, 1.78, 1.88, 1.88, 1.88, 1.98, 2.30, 2.55]
BODY_HALF_W = [0.20, 0.56, 0.82, 1.32, 1.70, 1.82, 1.82, 1.78, 1.62, 1.00, 0.38]
N_TOP = (2.5, 3.3)       # 機首 → キャビン（上半分の丸み。大きいほど角ばる）
N_BOTTOM = 3.6
WALL = 0.10              # 外板＋内張りの厚み

FLOOR_Y = 0.70           # キャビンの床（上面）
BELLY_Y = 0.52           # 胴体の下面
STEP_Y = 0.35            # 乗り込みステップの上面

# ---- 座席（左＝プレイヤー、右＝ハテナ）
SEAT_X = 0.77            # 座席中心の |x|
SEAT_TOP_Y = 1.18        # 座面（クッション上面）。床から 0.48
SEAT_FRONT_Z = -1.52
SEAT_BACK_Z = -0.84      # 背もたれの前面
SEAT_W = 1.10
SEAT_BACK_TOP_Y = 2.12
SEAT_BACK_TILT_DEG = 10.0
BOOSTER_H = 0.25         # ハテナ用のクッション（右の座席に載せる）
PASSENGER_PELVIS = (-SEAT_X, SEAT_TOP_Y + 0.18, -1.10)   # 座ったプレイヤーの pelvis（ももの下面が座面）

# ---- 計器盤・操縦かん
DASH_BACK_Z = -2.30      # 計器盤の座席側の面
DASH_FRONT_Z = -2.62
DASH_TOP_Y = 1.75        # 計器盤の上端（正面カメラで顔が隠れない高さ）
DASH_BOTTOM_Y = 1.40
CONSOLE_HALF_W = 0.20

# ---- ドア（ガルウィング：屋根の継ぎ目を軸に上へ開く）
DOOR_FRONT_Z = -2.25
DOOR_REAR_Z = -0.55
DOOR_HINGE_X = 0.35      # ヒンジ線の |x|（屋根の中央の梁の両端）
DOOR_SILL_Y = 0.76
DOOR_OPEN_DEG = 90.0
WINDOW_BELT_Y = 1.95     # これより上はガラス
STRIPE_Y = (1.30, 1.44)  # 白い帯

# ---- 後ろの荷室と床下ハッチ（ゲーム本編の投下用。名前は今のまま）
BAY_FRONT_Z = -0.55
BAY_REAR_Z = 1.15
HATCH_HALF_W = 0.65
HATCH_Z = (-0.20, 1.00)

# ---- ローター
MAST_FAIRING = dict(x=0.46, z0=-0.55, z1=0.95, y0=3.42, y1=3.78)
ROTOR_HUB_Y = 4.00
ROTOR_RADIUS = 5.30
ROTOR_CHORD = 0.34
ROTOR_BLADES = 2
ROTOR_PARK_DEG = 0.0     # 0＝ブレードを前後方向（機首と尾）に止める。ガルウィングと当たらない向き
TAIL_ROTOR = dict(x=0.30, y=3.62, z=6.55, radius=0.65)

# ---- 尾部
BOOM = dict(z0=1.70, z1=6.60, y0=2.56, y1=2.98, r0=0.40, r1=0.20)
FIN = [(5.95, 2.80), (6.50, 4.05), (6.95, 4.12), (6.88, 2.78), (6.62, 2.10), (6.25, 2.30)]
STAB = dict(z0=5.25, z1=5.72, y=2.88, half_span=0.95)

# ---- スキッド
SKID_X = 1.56
SKID_Z = (-2.30, 1.35)
SKID_R = 0.06
CROSS_Z = (-1.40, 0.62)
CROSS_TOP_X = 1.05

# ---- 乗り込みステップ（左の前のクロスチューブに付ける）
STEP = dict(x0=-2.12, x1=-1.64, z0=-1.82, z1=-1.02)

BODY_PAINT = (0.95, 0.55, 0.20)    # P1 のオレンジ（ゲストはブルー）。実機は BodyPaint を色替え
TRIM = (0.96, 0.96, 0.94)
CHARCOAL = (0.17, 0.19, 0.23)
GLASS = (0.62, 0.84, 0.95)
INTERIOR = (0.55, 0.58, 0.63)
SEAT_COLOR = (0.22, 0.29, 0.43)
DASH_COLOR = (0.20, 0.22, 0.27)
SCREEN = (0.35, 0.85, 0.95)


def body_params(z):
    t = np.clip((z - BODY_Z[0]) / (-1.60 - BODY_Z[0]), 0, 1)
    return dict(
        top=float(pchip(BODY_Z, BODY_TOP, z)), bottom=float(pchip(BODY_Z, BODY_BOTTOM, z)),
        belt=float(pchip(BODY_Z, BODY_BELT, z)), a=float(pchip(BODY_Z, BODY_HALF_W, z)),
        n_top=N_TOP[0] + (N_TOP[1] - N_TOP[0]) * float(t), n_bot=N_BOTTOM)


def section_extent(z, x=None, y=None, inner=False):
    """断面の大きさ。x を渡すとその x での上端（y）を、y を渡すとその y での半幅を返す。inner なら内張りの面。"""
    p = body_params(z)
    a, top, bottom, belt = p["a"], p["top"], p["bottom"], p["belt"]
    if inner:
        a, top, bottom = a - WALL, top - WALL, bottom + WALL
    if a <= 0.02 or top <= belt:
        return None if x is not None else 0.0
    if x is not None:
        r = abs(x) / a
        if r >= 1:
            return None
        return belt + (top - belt) * (1 - r ** p["n_top"]) ** (1 / p["n_top"])
    if y is not None:
        if y >= belt:
            r = (y - belt) / (top - belt)
            n = p["n_top"]
        else:
            r = (belt - y) / (belt - bottom)
            n = p["n_bot"]
        if r >= 1:
            return 0.0
        return a * (1 - r ** n) ** (1 / n)
    return p


def _classify_body(c):
    """胴体の四角形の中心 c から (部品, 材質) を決める。材質は paint / glass / trim。"""
    x, y, z = c
    in_door = DOOR_FRONT_Z < z < DOOR_REAR_Z and abs(x) > DOOR_HINGE_X and y > DOOR_SILL_Y
    stripe = STRIPE_Y[0] < y < STRIPE_Y[1] and abs(x) > 0.6
    if in_door:
        side = "L" if x < 0 else "R"
        return f"door_{side}", "glass" if y > WINDOW_BELT_Y else ("trim" if stripe else "paint")
    if z <= DOOR_FRONT_Z and y > 1.48 + 0.25 * max(0.0, (z + 2.95)) and z > -3.02:
        return "canopy", "glass"
    if BAY_FRONT_Z + 0.15 < z < 0.95 and abs(x) > 0.95 and 2.05 < y < 2.85:
        return "bay_window", "glass"
    return "body", "trim" if stripe else "paint"


def body_stations(step=0.022):
    """輪を置く z。形が急に変わる所（機首）ほど細かくする（弧の長さで等間隔）。"""
    zf = np.linspace(BODY_Z[0], BODY_Z[-1], 4000)
    a = pchip(BODY_Z, BODY_HALF_W, zf)
    t = pchip(BODY_Z, BODY_TOP, zf)
    b = pchip(BODY_Z, BODY_BOTTOM, zf)
    d = np.sqrt(np.diff(zf) ** 2 + np.diff(a) ** 2 + np.diff(t) ** 2 + np.diff(b) ** 2)
    s_ = np.concatenate([[0], np.cumsum(d)])
    n = int(s_[-1] / step) + 1
    return np.interp(np.linspace(0, s_[-1], n), s_, zf)


@functools.lru_cache(maxsize=2)
def build_body(ring=300):
    zs = body_stations()
    sections = []
    for z in zs:
        p = body_params(z)
        xs, ys = superellipse_ring(p["a"], p["belt"], p["top"] - p["belt"], p["belt"] - p["bottom"], p["n_top"], p["n_bot"], ring)
        sections.append((z, xs, ys))
    tris = loft(sections, closed_ends=True)
    n_quads = (len(sections) - 1) * ring
    groups = {}
    for i in range(0, 2 * n_quads, 2):
        key = _classify_body(np.concatenate([tris[i], tris[i + 1]]).mean(0))
        groups.setdefault(key, []).extend([tris[i], tris[i + 1]])
    for t in tris[2 * n_quads:]:
        groups.setdefault(_classify_body(t.mean(0)), []).append(t)
    return {k: np.array(v) for k, v in groups.items()}


def door_hinge(side):
    sx = -1 if side == "L" else 1
    p0 = np.array([sx * DOOR_HINGE_X, section_extent(DOOR_FRONT_Z, x=DOOR_HINGE_X), DOOR_FRONT_Z])
    p1 = np.array([sx * DOOR_HINGE_X, section_extent(DOOR_REAR_Z, x=DOOR_HINGE_X), DOOR_REAR_Z])
    return p0, p1


def door_rotation(side, openness):
    p0, p1 = door_hinge(side)
    axis = p1 - p0
    ang = math.radians(DOOR_OPEN_DEG) * openness * (-1 if side == "L" else 1)
    return p0, rot_axis(axis, ang)


def _rotate_about(tris, pivot, R):
    t = tris.reshape(-1, 3) - pivot
    return ((R @ t.T).T + pivot).reshape(-1, 3, 3)


def seat_meshes(x_center, booster=False):
    out = []
    out.append(Mesh("seat_base", box((x_center, (FLOOR_Y + SEAT_TOP_Y - 0.20) / 2, (SEAT_FRONT_Z + SEAT_BACK_Z) / 2 + 0.05),
                                      (SEAT_W - 0.25, SEAT_TOP_Y - 0.20 - FLOOR_Y, 0.50)), DASH_COLOR))
    out.append(Mesh("seat_cushion", box((x_center, SEAT_TOP_Y - 0.10, (SEAT_FRONT_Z + SEAT_BACK_Z) / 2),
                                         (SEAT_W, 0.20, SEAT_BACK_Z - SEAT_FRONT_Z)), SEAT_COLOR))
    back_h = SEAT_BACK_TOP_Y - SEAT_TOP_Y
    R = rot_axis([1, 0, 0], math.radians(SEAT_BACK_TILT_DEG))
    center = np.array([x_center, SEAT_TOP_Y + back_h / 2, SEAT_BACK_Z + 0.08])
    out.append(Mesh("seat_back", box(center, (SEAT_W, back_h, 0.16), R), SEAT_COLOR))
    if booster:
        out.append(Mesh("booster", box((x_center, SEAT_TOP_Y + BOOSTER_H / 2, (SEAT_FRONT_Z + SEAT_BACK_Z) / 2 - 0.02),
                                        (SEAT_W - 0.16, BOOSTER_H, SEAT_BACK_Z - SEAT_FRONT_Z - 0.06)), BODY_PAINT, tags={"kind": "booster"}))
    return out


def yoke_meshes(grip_l, grip_r, bar_y, bar_z, color=CHARCOAL):
    """U 字の操縦かん：2 本の握り（grip の点を中心に縦）、下の横棒、計器盤へのびる柱。"""
    gl, gr = np.asarray(grip_l, float), np.asarray(grip_r, float)
    tris = []
    for g in (gl, gr):
        tris.append(cylinder((g[0], bar_y, bar_z), (g[0], g[1] + 0.10, g[2]), 0.045))
        tris.append(cylinder((g[0], g[1] - 0.10, g[2]), (g[0], g[1] + 0.12, g[2]), 0.06))
    tris.append(cylinder((gl[0], bar_y, bar_z), (gr[0], bar_y, bar_z), 0.045))
    mid_x = (gl[0] + gr[0]) / 2
    tris.append(cylinder((mid_x, bar_y, bar_z), (mid_x, bar_y + 0.05, DASH_BACK_Z), 0.06))
    return [Mesh("yoke", np.concatenate(tris), color)]


def build_heli(door_l=0.0, door_r=0.0, hatch=0.0, rotor_deg=ROTOR_PARK_DEG, yokes=None, booster=True,
               paint=BODY_PAINT, cut=None):
    """図面用のヘリ。cut=("x", 値, 側) / ("z", 値, 側) で、その面より手前の外板を外す（断面図）。"""
    meshes = []
    groups = build_body()

    def keep(tris):
        if cut is None or len(tris) == 0:
            return tris
        axis, value, side = cut
        k = {"x": 0, "y": 1, "z": 2}[axis]
        c = tris.mean(1)[:, k]
        return tris[(c > value) if side == "+" else (c < value)]

    for (part, material), tris in groups.items():
        if part.startswith("door_"):
            side = part[-1]
            openness = door_l if side == "L" else door_r
            pivot, R = door_rotation(side, openness)
            tris = _rotate_about(tris, pivot, R)
        tris = keep(tris)
        if material == "glass":
            meshes.append(Mesh(part, tris, GLASS, glass=True, tags={"part": part}))
        else:
            meshes.append(Mesh(part, tris, TRIM if material == "trim" else paint, back_color=INTERIOR, tags={"part": part}))
    # 床・内装・後ろの仕切り（尾の付け根をふさぐ）
    bulk = section_outline("z", BAY_REAR_Z, inner=True, samples=64)
    c = np.array([0, bulk[:, 1].mean(), BAY_REAR_Z])
    ring = np.c_[bulk, np.full(len(bulk), BAY_REAR_Z)]
    fan = np.array([[c, ring[i], ring[(i + 1) % len(ring)]] for i in range(len(ring))])
    meshes.append(Mesh("bulkhead", fan, INTERIOR, back_color=INTERIOR))
    meshes.append(Mesh("floor", box((0, FLOOR_Y - 0.05, (-2.45 + BAY_REAR_Z) / 2), (2 * 1.55, 0.10, BAY_REAR_Z + 2.45)), INTERIOR))
    meshes.append(Mesh("dash", box((0, (DASH_TOP_Y + DASH_BOTTOM_Y) / 2, (DASH_FRONT_Z + DASH_BACK_Z) / 2),
                                   (2 * 1.50, DASH_TOP_Y - DASH_BOTTOM_Y, DASH_BACK_Z - DASH_FRONT_Z)), DASH_COLOR))
    meshes.append(Mesh("dash_shroud", box((0, DASH_TOP_Y + 0.03, (DASH_FRONT_Z + DASH_BACK_Z) / 2 - 0.05),
                                          (2 * 1.50, 0.06, DASH_BACK_Z - DASH_FRONT_Z + 0.14)), CHARCOAL))
    for sx in (-1, 1):
        meshes.append(Mesh("screen", box((sx * SEAT_X, DASH_TOP_Y - 0.15, DASH_BACK_Z + 0.005), (0.50, 0.22, 0.01)), SCREEN, emissive=True))
    meshes.append(Mesh("console", box((0, (FLOOR_Y + 1.30) / 2, (DASH_BACK_Z + SEAT_BACK_Z) / 2), (2 * CONSOLE_HALF_W, 1.30 - FLOOR_Y, SEAT_BACK_Z - DASH_BACK_Z)), DASH_COLOR))
    meshes += seat_meshes(-SEAT_X)
    meshes += seat_meshes(SEAT_X, booster=booster)
    if yokes:
        for y in yokes:
            meshes += yoke_meshes(**y)
    # 床下ハッチ（2 枚。外側のふちを軸に開く）
    hz0, hz1 = HATCH_Z
    for sx in (-1, 1):
        leaf = box((sx * HATCH_HALF_W / 2, BELLY_Y - 0.02, (hz0 + hz1) / 2), (HATCH_HALF_W, 0.05, hz1 - hz0))
        pivot = np.array([sx * HATCH_HALF_W, BELLY_Y, 0])
        R = rot_axis([0, 0, 1], -sx * math.radians(78) * hatch)
        meshes.append(Mesh("hatch", _rotate_about(leaf, pivot, R), paint, back_color=(0.35, 0.33, 0.30)))
    # マスト・ローター
    mf = MAST_FAIRING
    meshes.append(Mesh("mast_fairing", box((0, (mf["y0"] + mf["y1"]) / 2, (mf["z0"] + mf["z1"]) / 2), (2 * mf["x"], mf["y1"] - mf["y0"], mf["z1"] - mf["z0"])), paint))
    meshes.append(Mesh("mast", cylinder((0, mf["y1"], 0), (0, ROTOR_HUB_Y, 0), 0.11), CHARCOAL))
    meshes.append(Mesh("hub", cylinder((0, ROTOR_HUB_Y - 0.08, 0), (0, ROTOR_HUB_Y + 0.10, 0), 0.26), CHARCOAL))
    for k in range(ROTOR_BLADES):
        ang = math.radians(rotor_deg) + k * 2 * math.pi / ROTOR_BLADES
        d = np.array([math.sin(ang), 0, -math.cos(ang)])
        tip = d * ROTOR_RADIUS + [0, ROTOR_HUB_Y - 0.12, 0]
        root = d * 0.28 + [0, ROTOR_HUB_Y, 0]
        mid = (tip + root) / 2
        length = np.linalg.norm(tip - root)
        R = np.c_[np.cross([0, 1, 0], d), [0, 1, 0], d]
        blade = box((0, 0, 0), (ROTOR_CHORD, 0.05, length))
        blade = (R @ blade.reshape(-1, 3).T).T + mid
        meshes.append(Mesh("blade", blade.reshape(-1, 3, 3), CHARCOAL))
    # 尾部
    b = BOOM
    zs = np.linspace(b["z0"], b["z1"], 24)
    secs = []
    for z in zs:
        t = (z - b["z0"]) / (b["z1"] - b["z0"])
        r = b["r0"] + (b["r1"] - b["r0"]) * t
        yc = b["y0"] + (b["y1"] - b["y0"]) * t
        ang = np.linspace(0, 2 * np.pi, 24, endpoint=False)
        secs.append((z, r * np.cos(ang), yc + r * np.sin(ang)))
    meshes.append(Mesh("boom", loft(secs), paint))
    meshes.append(Mesh("fin", extrude_polygon_x(FIN, -0.06, 0.06), paint))
    st = STAB
    meshes.append(Mesh("stab", box((0, st["y"], (st["z0"] + st["z1"]) / 2), (2 * st["half_span"], 0.06, st["z1"] - st["z0"])), paint))
    for sx in (-1, 1):
        meshes.append(Mesh("stab_end", box((sx * st["half_span"], st["y"] + 0.05, (st["z0"] + st["z1"]) / 2 + 0.03), (0.05, 0.36, 0.44)), TRIM))
    tr = TAIL_ROTOR
    meshes.append(Mesh("tail_hub", cylinder((0.06, tr["y"], tr["z"]), (tr["x"] + 0.06, tr["y"], tr["z"]), 0.08), CHARCOAL))
    for k in range(2):
        ang = math.radians(35) + k * math.pi
        d = np.array([0, math.cos(ang), math.sin(ang)])
        mid = np.array([tr["x"], tr["y"], tr["z"]]) + d * tr["radius"] / 2
        R = np.c_[[1, 0, 0], np.cross(d, [1, 0, 0]), d]
        blade = box((0, 0, 0), (0.04, 0.14, tr["radius"]))
        blade = (R @ blade.reshape(-1, 3).T).T + mid
        meshes.append(Mesh("tail_blade", blade.reshape(-1, 3, 3), CHARCOAL))
    # スキッド
    for sx in (-1, 1):
        x = sx * SKID_X
        tr_ = [cylinder((x, SKID_R, SKID_Z[0]), (x, SKID_R, SKID_Z[1]), SKID_R),
               cylinder((x, SKID_R, SKID_Z[0]), (x, 0.36, SKID_Z[0] - 0.42), SKID_R)]
        for cz in CROSS_Z:
            tr_.append(cylinder((x, SKID_R, cz), (sx * CROSS_TOP_X, BELLY_Y + 0.02, cz), 0.055))
        meshes.append(Mesh("skid", np.concatenate(tr_), CHARCOAL))
    # 乗り込みステップ（左）
    s = STEP
    meshes.append(Mesh("step", box(((s["x0"] + s["x1"]) / 2, STEP_Y - 0.03, (s["z0"] + s["z1"]) / 2), (s["x1"] - s["x0"], 0.06, s["z1"] - s["z0"])), TRIM))
    meshes.append(Mesh("step_arm", np.concatenate([cylinder((s["x1"], STEP_Y - 0.05, cz), (-SKID_X, 0.30, CROSS_Z[0]), 0.035) for cz in (s["z0"] + 0.1, s["z1"] - 0.1)]), CHARCOAL))
    # 灯火（断面図では出さない）
    if cut is not None:
        return _apply_cut(meshes, cut)
    meshes.append(Mesh("nav_l", box((-1.50, 1.70, -2.40), (0.10, 0.10, 0.16)), (0.95, 0.15, 0.12), emissive=True))
    meshes.append(Mesh("nav_r", box((1.50, 1.70, -2.40), (0.10, 0.10, 0.16)), (0.15, 0.85, 0.30), emissive=True))
    meshes.append(Mesh("beacon", box((0, MAST_FAIRING["y1"] + 0.05, 0.75), (0.16, 0.10, 0.16)), (0.95, 0.20, 0.15), emissive=True))
    return meshes


def _apply_cut(meshes, cut):
    """断面図：外板は build_heli の keep で切ってあるので、ここでは手前の内装（計器盤・操縦かんなど）を落とす。"""
    if True:
        axis, value, side = cut
        k = {"x": 0, "y": 1, "z": 2}[axis]
        trimmed = []
        for m in meshes:
            if m.name in ("body", "canopy", "door_L", "door_R", "bay_window") or m.name.startswith("door"):
                trimmed.append(m)  # 既に keep 済み
                continue
            if m.name in ("floor",) or m.tags.get("part"):
                trimmed.append(m)
                continue
            c = m.tris.mean(1)[:, k]
            mask = (c > value) if side == "+" else (c < value)
            if m.name in ("dash", "dash_shroud", "console", "screen", "yoke", "nav_l", "nav_r", "step", "step_arm", "skid"):
                m = Mesh(m.name, m.tris[mask], m.color, m.glass, m.emissive, m.back_color, m.tags)
            trimmed.append(m)
        meshes = [m for m in trimmed if len(m.tris)]
    return meshes


def section_outline(axis, value, inner=False, samples=400):
    """断面の輪郭（図面の太線）。axis="z" なら (x, y) の輪、"x" なら (z, y) の上下の線。"""
    if axis == "z":
        p = body_params(value)
        a, top, bottom = p["a"], p["top"], p["bottom"]
        if inner:
            a, top, bottom = a - WALL, top - WALL, bottom + WALL
        xs, ys = superellipse_ring(a, p["belt"], top - p["belt"], p["belt"] - bottom, p["n_top"], p["n_bot"], samples)
        return np.c_[xs, ys]
    zs = np.linspace(BODY_Z[0], BODY_Z[-1], samples)
    upper, lower = [], []
    for z in zs:
        t = section_extent(z, x=value, inner=inner)
        if t is None:
            continue
        p = body_params(z)
        a = p["a"] - (WALL if inner else 0)
        bottom = p["bottom"] + (WALL if inner else 0)
        if a <= 0.02:
            continue
        r = abs(value) / a
        bot = p["belt"] - (p["belt"] - bottom) * (1 - r ** p["n_bot"]) ** (1 / p["n_bot"])
        upper.append((z, t))
        lower.append((z, bot))
    return np.array(upper), np.array(lower)

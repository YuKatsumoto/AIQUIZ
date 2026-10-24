"""サドンデス用の「水上機の C-130」（ずんぐりしたおもちゃの形）の寸法の案。

写し：artifacts/sudden_death_v2/c130_float/c130_design.py（2026-10-18）を、W1 のビルダーが読むためにここへ写した。
数字は元のまま。変えたのは pchip の読み込みだけ（元は artifacts/heli_blueprint/blueprint_lib.py の numpy 版を読む）。
元の設計を直したら、この写しも同じに直す（build_floatplane_c130.py が起動時に元と数字を比べて、違えば知らせる）。

座標：u＝機首の先から後ろへ（m）、v＝海面からの高さ（m）、x＝左右（機体の右が +）。
実機（C-130H）の寸法は米空軍の資料から（docs/sudden_death_v2/c130_float.md）。
"""


def pchip(xk, yk, x):
    """単調な 3 次補間（Fritsch–Carlson）。artifacts/heli_blueprint/blueprint_lib.py の pchip と同じ式を
    numpy なしで書いた（Blender の Python からも読めるように）。"""
    n = len(xk)
    h = [xk[i + 1] - xk[i] for i in range(n - 1)]
    d = [(yk[i + 1] - yk[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    m[0], m[-1] = d[0], d[-1]
    x = min(max(float(x), xk[0]), xk[-1])
    i = 0
    while i < n - 2 and x > xk[i + 1]:
        i += 1
    t = (x - xk[i]) / h[i]
    h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
    h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
    return h00 * yk[i] + h10 * h[i] * m[i] + h01 * yk[i + 1] + h11 * h[i] * m[i + 1]


# ---------------------------------------------------------------- 実機（C-130H。米空軍の資料）
REAL = dict(length=29.3, span=39.7, height=11.6, hold=(12.3, 3.12, 2.74), ramp=(3.02, 3.12))

# ---------------------------------------------------------------- 人物
PLAYER_H = 2.30
PLAYER_H_HAT = 2.92

# ---------------------------------------------------------------- 舞台（scripts/world/stage_constants.gd）
STAGE_FLOOR_ABOVE_SEA = 8.0      # 床の上面 −1.2、海面 −9.2
STAGE_FLOOR_HALF_W = 12.0
STAND_INNER_X = 27.2             # 横のスタンドの内側
CHANNEL = STAND_INNER_X - STAGE_FLOOR_HALF_W   # 床とスタンドの間の海の幅 15.2

# ---------------------------------------------------------------- 胴体（側面の上下。v は海面から）
# 2026-10-18：ユーザーの指示で「もう少し大きく、細長く」（全長 13.2 → 18.0）。前の案は c130_design_v1_compact.py
FUS_U = [0.0, 0.4, 1.1, 2.2, 3.2, 4.5, 11.2, 12.6, 14.2, 16.2, 18.0]
FUS_TOP = [3.40, 4.20, 4.90, 5.45, 5.75, 5.80, 5.80, 5.76, 5.66, 5.50, 5.30]
FUS_BOT = [2.90, 2.25, 1.80, 1.62, 1.60, 1.60, 1.60, 2.15, 3.05, 4.25, 5.00]   # 11.2 から後ろは下面がはね上がる（スロープ）
FUS_HALF_W = [0.30, 1.05, 1.65, 2.05, 2.20, 2.20, 2.20, 2.10, 1.75, 1.10, 0.35]
LENGTH = FUS_U[-1]
WALL = 0.18
COCKPIT_END_U = 3.2
FLOOR_V = 1.90                   # 貨物室の床
HOLD = (COCKPIT_END_U, 11.2)     # 貨物室の前後（8.0 m）
HINGE_U = 11.2                    # スロープの付け根
RAMP_LEN = 3.20
RAMP_HALF_W = 1.55               # 幅 3.10（実機 3.12）
OPENING_TOP_V = 5.20             # 後ろの開口の上端（高さ 3.30）。上は「上のふた」が尾の中へ上がる
CEILING_V = 5.80 - WALL

# ---------------------------------------------------------------- 主翼・エンジン
WING_U = (5.0, 8.2)              # 翼弦 3.2
WING_V = (5.80, 6.35)
SPAN = 24.0
ENGINE_X = [4.4, 8.0]            # 内側・外側のエンジンの |x|
NACELLE = dict(u0=3.0, u1=7.6, v=5.20, r=0.60)
PROP_U = 2.9
PROP_D = 2.80
PORTHOLES_U = [5.4, 7.6, 9.8]

# ---------------------------------------------------------------- 尾
FIN = [(12.6, 5.62), (16.4, 9.40), (17.6, 9.50), (18.05, 5.30)]
STAB = dict(u0=15.6, u1=18.0, v=5.45, half_span=4.60)

# ---------------------------------------------------------------- フロート（2 本）
FLOAT = dict(u0=0.8, u1=15.0, v=0.20, r=0.85, x=3.60)     # 喫水 0.65 m
STRUTS_U = [3.6, 9.0]

HEIGHT = FIN[2][1] - (FLOAT["v"] - FLOAT["r"])

# ---------------------------------------------------------------- 機内（docs/sudden_death_v2/c130_float.md 第5章）
# 操縦席は実機と同じく貨物室の床より一段高い（段 3 つで上がる）。ハテナは真ん中の 1 席。
FLIGHT_DECK_V = FLOOR_V + 1.05          # 操縦席の床
FLIGHT_DECK_U = (0.9, 3.2)
STEPS_U = (3.2, 3.95)                   # 段（3 段、1 段 0.35 m）
PILOT_SEAT_U = 1.75
DECK_DOOR_HALF_W = 0.75                 # 操縦席と貨物室の間の出入り口（幅 1.5 m、扉はなし）
# ベンチ：左右の壁に沿う。2 人は真ん中で向かい合う。飛び出す画（機内から後ろを向く）で P1 が画面の左になるよう、
# P1 は機体の右の壁（+x）、P2 は左の壁（−x）に座る（2026-10-18、ユーザーと決定）
BENCH_U = (4.4, 10.4)
BENCH_SEAT_V = FLOOR_V + 0.48
BENCH_DEPTH = 0.50
BENCH_INNER_X = 2.02 - BENCH_DEPTH      # 座面の通路側の端の |x|
SIT_U = 7.4
AISLE_W = 2 * (BENCH_INNER_X - 0.55)    # 座った 2 人のひざの先どうしの間
# 窓（丸窓、左右に 3 つずつ。座った人の頭の少し上）
WINDOW_V = FLOOR_V + 2.30
WINDOW_R = 0.30
# 手すり（天井から下がる、左右 2 本）と、降下のランプ（後ろの開口の上、赤と緑）
RAIL_X = 0.95
RAIL_V = FLOOR_V + 2.85
RAIL_U = (4.0, 11.0)
JUMP_LIGHT_V = OPENING_TOP_V + 0.20


def top(u):
    return float(pchip(FUS_U, FUS_TOP, u))


def bottom(u):
    return float(pchip(FUS_U, FUS_BOT, u))


def half_w(u):
    return float(pchip(FUS_U, FUS_HALF_W, u))


def summary():
    return [
        ("全長（機首〜尾の端）", LENGTH, REAL["length"]),
        ("翼の幅", SPAN, REAL["span"]),
        ("高さ（フロートの底〜尾翼の上）", HEIGHT, REAL["height"]),
        ("胴体の幅・高さ", "%.2f・%.2f" % (max(FUS_HALF_W) * 2, max(FUS_TOP) - min(FUS_BOT)), "4.3（直径）"),
        ("貨物室（長さ×幅×立てる高さ）", "%.1f × %.1f × %.2f" % (HOLD[1] - HOLD[0], (max(FUS_HALF_W) - WALL) * 2, CEILING_V - FLOOR_V), "12.3 × 3.12 × 2.74"),
        ("後ろの開口（幅×高さ）", "%.2f × %.2f" % (RAMP_HALF_W * 2, OPENING_TOP_V - FLOOR_V), "3.12 × 2.74"),
        ("スロープ（長さ×幅）", "%.2f × %.2f" % (RAMP_LEN, RAMP_HALF_W * 2), "3.02 × 3.12"),
        ("プロペラの直径", PROP_D, "4.1"),
        ("床の海面からの高さ", FLOOR_V, "約 1.0（地面から）"),
        ("床とスタンドの間の海に後ろ向きで入れたときの余り", CHANNEL - LENGTH - 0.8, "—"),
        ("舞台の床とスロープの端の高さの差", STAGE_FLOOR_ABOVE_SEA - FLOOR_V, "—"),
    ]

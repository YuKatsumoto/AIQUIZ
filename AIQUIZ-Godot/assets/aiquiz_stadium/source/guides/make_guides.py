"""AIQUIZ STADIUM のカメラ固定ガイド画像を作る。

ゲームの実カメラ（camera_controller.gd の 1P / 2P / プリロード）で、走路・水路・側面スタンドの
外形・マスト位置・ゴール・灯台候補・背景の目安を正確に透視投影し、塗り分けた下絵にする。
Higgsfield には「2枚目の参照画像＝カメラ・位置・幅を厳守」として渡す。

- *_clean.png: 生成に渡す版（文字なし）
- *_annotated.png: 人が読む版（ラベル・寸法注記つき）

座標は Godot のワールド座標（+X＝P1 オレンジ＝画面左、+Y＝上、+Z＝コース前方、走路上面 Y=-1.2）。
寸法は game_constants.json（extract_game_constants.py の出力）と、寸法表で決める前の暫定設計値
（DESIGN）から取る。暫定値は CP4 の寸法表で確定し、ずれたらガイドを作り直す。

    python assets/aiquiz_stadium/source/guides/make_guides.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
CONSTANTS = json.loads((HERE.parent / "game_constants.json").read_text(encoding="utf-8"))


def const(file_suffix: str, name: str) -> float:
    for rel, values in CONSTANTS["constants"].items():
        if rel.endswith(file_suffix) and name in values:
            return float(values[name]["value"])
    raise KeyError(f"{file_suffix}:{name}")


DECK_Y = const("stage_constants.gd", "FLOOR_TOP_Y")            # -1.2
SEA_Y = const("stage_constants.gd", "OCEAN_SURFACE_Y")          # -9.2
HALF_W = const("stage_constants.gd", "FLOOR_HALF_WIDTH")        # 12
BACK_Z = const("stage_constants.gd", "FLOOR_BACK_Z")            # -12.5
WALL_START = const("stage_constants.gd", "WALL_START_Z")        # 22
WALL_SPACING = const("stage_constants.gd", "WALL_SPACING")      # 30
CURB_X = const("conveyor_rails.gd", "CENTER_X")                 # 11.86
CURB_TOP = const("conveyor_rails.gd", "TOP_HEIGHT")             # 0.26
BLOCK = const("santorini_terrace_stand.gd", "BLOCK_LENGTH")     # 20
ROW_FRONT = const("build_santorini_grandstand.py", "ROW_FRONT")  # 1.15
ROW_PITCH = const("build_santorini_grandstand.py", "ROW_PITCH")  # 1.25
ROW_RISE = const("build_santorini_grandstand.py", "ROW_RISE")    # 0.40
ROW_BASE = const("build_santorini_grandstand.py", "ROW_BASE")    # 0.32
FRONT_X = const("build_santorini_grandstand.py", "FRONT_X")      # -0.8
GOAL_OFFSET = const("goal_stand.gd", "GOAL_OFFSET")              # 25.8
EYE_2P = const("camera_controller.gd", "TWO_PLAYER_EYE_Y")       # 4.5 (world Y)
LOOK_2P = const("camera_controller.gd", "TWO_PLAYER_LOOK_Y")     # 1.0
AHEAD_2P = const("camera_controller.gd", "TWO_PLAYER_LOOK_AHEAD")  # 8
BACK_2P = const("camera_controller.gd", "TWO_PLAYER_CAMERA_BACK")  # 9
FOV_2P = const("camera_controller.gd", "TWO_PLAYER_FOV")         # 50
FOV_1P = const("camera_controller.gd", "THIRD_PERSON_FOV")       # 50
DIST_1P = const("camera_controller.gd", "THIRD_PERSON_DISTANCE")  # 5.6
FOCUS_1P = const("camera_controller.gd", "THIRD_PERSON_FOCUS_HEIGHT")  # 1.0
BASE_1P = const("camera_controller.gd", "THIRD_PERSON_BASE_HEIGHT")    # 2.0
FOV_PRELOAD = const("camera_controller.gd", "PRELOAD_CAMERA_FOV")  # 66
LAYOUT = CONSTANTS["json"]["goal_stand_layout"]

# 暫定設計値（CP4 の寸法表で確定する）。側面スタンドはブロック空間（x＝コースから外向き、y＝上）。
DESIGN = {
    "stand_center_x": 28.0,       # stage_environment.gd layout_grandstand_side_offset
    "rows": 6,
    "stand_back_x": 10.9,         # 6段目 x=7.40 の後ろに後方通路＋ブース
    "booth": {"x0": 8.4, "x1": 10.6, "height": 2.6, "length": 4.6},
    "mast": {"x": 9.5, "top_y": 12.0},
    "sail": {"low_x": 1.4, "low_y": 5.2, "half_len": 7.0},
    "stand_pile_pitch": 5.0,
    "runway_pile_pitch": 10.0,
    "runway_pile_x": (11.2, 4.0),
    "quiz_wall_height": 7.0,
    "gate_height": 5.0,
    "lighthouse": {"z": 950.0, "tower_h": 95.0, "tower_r": 9.0, "sign_w": 52.0, "sign_h": 21.0,
                   "base_r": 30.0, "base_h": 8.0},
}

W, H = 1920, 1080
COL = {
    "sky_top": (141, 207, 245), "sky_low": (214, 238, 250), "sea_far": (183, 234, 248),
    "sea_near": (89, 187, 207), "deck": (236, 233, 226), "deck_edge": (47, 95, 168),
    "frame": (150, 158, 170), "pile": (225, 228, 232), "stand_face": (228, 230, 234),
    "stand_top": (206, 211, 218), "row_p1": (240, 150, 70), "row_p2": (70, 150, 230),
    "aisle": (188, 193, 200), "booth": (246, 244, 240), "booth_panel": (30, 78, 150),
    "mast": (122, 90, 60), "sail": (242, 238, 230), "wall": (140, 140, 150),
    "door": (95, 95, 105), "gate": (124, 138, 148), "goal_stand": (220, 224, 230),
    "scoreboard": (50, 62, 80), "lighthouse": (236, 238, 242), "sign": (59, 80, 104),
    "island": (94, 158, 90), "sand": (234, 219, 184), "skyline": (207, 227, 238),
    "p1": (242, 140, 51), "p2": (51, 166, 230),
}


class Camera:
    def __init__(self, eye, target, fov_deg):
        self.eye = eye
        f = norm(sub(target, eye))
        r = norm(cross(f, (0.0, 1.0, 0.0)))
        u = cross(r, f)
        self.f, self.r, self.u = f, r, u
        self.tv = math.tan(math.radians(fov_deg) * 0.5)   # Godot の fov は縦（KEEP_HEIGHT）
        self.th = self.tv * W / H

    def cam(self, p):
        d = sub(p, self.eye)
        return (dot(d, self.r), dot(d, self.u), dot(d, self.f))

    def px(self, c):
        x, y, z = c
        return ((x / (z * self.th) + 1) * 0.5 * W, (1 - y / (z * self.tv)) * 0.5 * H)

    def horizon_y(self):
        far = add(self.eye, (0.0, 0.0, 1e6))
        return self.px(self.cam((self.eye[0], self.eye[1], far[2])))[1]


def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def norm(a):
    n = math.sqrt(dot(a, a))
    return (a[0] / n, a[1] / n, a[2] / n)


NEAR = 0.3


def clip_poly(cam_pts):
    """カメラ座標の多角形を z=NEAR 平面で切る（Sutherland-Hodgman）。"""
    out = []
    n = len(cam_pts)
    for i in range(n):
        a, b = cam_pts[i], cam_pts[(i + 1) % n]
        ain, bin_ = a[2] >= NEAR, b[2] >= NEAR
        if ain:
            out.append(a)
        if ain != bin_:
            t = (NEAR - a[2]) / (b[2] - a[2])
            out.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(3)))
    return out


class Scene:
    def __init__(self):
        self.polys = []   # (depth, color, world_pts, outline)
        self.labels = []  # (world_pt, text)

    def quad(self, pts, color, outline=None):
        self.polys.append((pts, color, outline))

    def box(self, x0, x1, y0, y1, z0, z1, color, top=None, outline=None):
        c = color
        t = top or color
        faces = [
            ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], t),
            ([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], shade(c, 0.93)),
            ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], shade(c, 0.93)),
            ([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], shade(c, 0.86)),
            ([(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)], shade(c, 0.86)),
        ]
        for pts, col in faces:
            self.quad(pts, col, outline)

    def label(self, p, text):
        self.labels.append((p, text))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def world_x(side: int, local_x: float) -> float:
    """side=+1: 右スタンド(+X, P1)。side=-1: 左スタンド(−X, P2, 180°回転)。"""
    return side * (DESIGN["stand_center_x"] + local_x)


def add_stand(sc: Scene, side: int, z0: float, z1: float, neutral: bool = False):
    d = DESIGN
    rows = d["rows"]
    back = d["stand_back_x"]
    team = COL["stand_top"] if neutral else (COL["row_p1"] if side > 0 else COL["row_p2"])
    xs = lambda lx: world_x(side, lx)
    # スタンドのデッキ（前面の化粧板を含む）。ブロック空間 y はワールド Y と同じ原点（走路上面 +1.2）。
    front, deck_top, deck_bot = FRONT_X, 0.22, -1.0
    sc.box(*sorted((xs(front), xs(back))), deck_bot, deck_top, z0, z1, COL["stand_face"], COL["stand_top"])
    # 段（6段）。各ブロックの -Z 端に 2.2m の通路。
    for zb in frange(z0, z1, BLOCK):
        aisle0, aisle1 = zb, zb + 2.2
        for i in range(rows):
            lx0 = ROW_FRONT - 0.6 + i * ROW_PITCH
            lx1 = lx0 + ROW_PITCH
            top = ROW_BASE + i * ROW_RISE
            sc.box(*sorted((xs(lx0), xs(lx1))), deck_top, top, aisle1, zb + BLOCK, team if i % 2 == 0 else shade(team, 0.9))
            sc.box(*sorted((xs(lx0), xs(lx1))), deck_top, top - 0.05, aisle0, aisle1, COL["aisle"])
        # 後方通路とブース・マスト・帆（1ブロック＝1組、ブロック中央）
        plat = ROW_BASE + rows * ROW_RISE
        sc.box(*sorted((xs(ROW_FRONT - 0.6 + rows * ROW_PITCH), xs(back))), deck_top, plat, zb, zb + BLOCK, COL["stand_top"])
        zc = zb + BLOCK * 0.5
        b = d["booth"]
        sc.box(*sorted((xs(b["x0"]), xs(b["x1"]))), plat, plat + b["height"], zc - b["length"] / 2, zc + b["length"] / 2,
               COL["booth"])
        m = d["mast"]
        sc.box(*sorted((xs(m["x"] - 0.15), xs(m["x"] + 0.15))), plat + b["height"], m["top_y"], zc - 0.15, zc + 0.15, COL["mast"])
        s = d["sail"]
        sc.quad([(xs(m["x"]), m["top_y"] - 0.3, zc), (xs(s["low_x"]), s["low_y"], zc - s["half_len"]),
                 (xs(s["low_x"]), s["low_y"], zc + s["half_len"])], COL["sail"], outline=shade(COL["sail"], 0.8))
        # 帆の縁（端面・真上から見たときにも線として見えるように薄い帯を付ける）
        for dz in (-s["half_len"], s["half_len"]):
            a, b = (xs(m["x"]), m["top_y"] - 0.3, zc), (xs(s["low_x"]), s["low_y"], zc + dz)
            sc.quad([a, b, (b[0], b[1] + 0.25, b[2]), (a[0], a[1] + 0.25, a[2])], shade(COL["sail"], 0.85))
    # 杭（ブロック空間 x=0 と後方、ピッチ 5m）
    for zp in frange(z0 + 1.0, z1, d["stand_pile_pitch"]):
        for lx in (0.2, 5.4, back - 0.6):
            sc.box(*sorted((xs(lx - 0.3), xs(lx + 0.3))), SEA_Y, deck_bot, zp - 0.3, zp + 0.3, COL["pile"])


def frange(a, b, step):
    v = a
    while v < b - 1e-6:
        yield v
        v += step


def add_runway(sc: Scene, z1: float):
    # デッキ（上面）と側面の帯、縁石、杭
    sc.box(-HALF_W, HALF_W, DECK_Y - 1.0, DECK_Y, BACK_Z, z1, COL["deck"], COL["deck"])
    for sgn in (1, -1):
        x0, x1 = sorted((sgn * 11.15, sgn * HALF_W))
        sc.quad([(x0, DECK_Y + 0.005, BACK_Z), (x1, DECK_Y + 0.005, BACK_Z), (x1, DECK_Y + 0.005, z1), (x0, DECK_Y + 0.005, z1)],
                COL["deck_edge"])
        cx0, cx1 = sorted((sgn * (CURB_X - 0.08), sgn * (CURB_X + 0.08)))
        sc.box(cx0, cx1, DECK_Y, DECK_Y + CURB_TOP, BACK_Z, z1, COL["deck_edge"])
        for zp in frange(BACK_Z + 2.0, z1, DESIGN["runway_pile_pitch"]):
            for px_ in DESIGN["runway_pile_x"]:
                x = sgn * px_
                sc.box(x - 0.35, x + 0.35, SEA_Y, DECK_Y - 1.0, zp - 0.35, zp + 0.35, COL["pile"])


def add_walls(sc: Scene, indices):
    for i in indices:
        z = WALL_START + i * WALL_SPACING
        h = DESIGN["quiz_wall_height"]
        sc.box(-HALF_W, HALF_W, DECK_Y, DECK_Y + h, z, z + 0.6, COL["wall"])
        for k in range(4):
            x0 = -HALF_W + 1.5 + k * 5.5
            sc.quad([(x0, DECK_Y, z - 0.01), (x0 + 4.0, DECK_Y, z - 0.01), (x0 + 4.0, DECK_Y + 3.6, z - 0.01),
                     (x0, DECK_Y + 3.6, z - 0.01)], COL["door"])


def add_goal(sc: Scene, goal_z: float):
    gh = DESIGN["gate_height"]
    for sgn in (1, -1):
        sc.box(sgn * 11.8 - 0.3, sgn * 11.8 + 0.3, DECK_Y, DECK_Y + gh, goal_z - 0.3, goal_z + 0.3, COL["gate"])
    sc.box(-12.1, 12.1, DECK_Y + gh - 0.9, DECK_Y + gh, goal_z - 0.3, goal_z + 0.3, COL["gate"])
    front = goal_z + GOAL_OFFSET
    w = LAYOUT["width"] * 0.5
    sc.box(-w, w, DECK_Y - 1.8, DECK_Y + LAYOUT["back_top"], front, front + LAYOUT["back_y"], COL["goal_stand"])
    sb = LAYOUT["scoreboard"]
    sc.box(-sb["width"] / 2, sb["width"] / 2, DECK_Y + 3.25, DECK_Y + sb["top"], front + sb["screen_y"],
           front + sb["screen_y"] + 1.0, COL["scoreboard"])
    sc.label((0.0, DECK_Y + sb["top"] + 2, front), "new goal stand (26 m)")
    sc.label((0.0, DECK_Y + gh + 1.5, goal_z), "GOAL gate 24 m")


def add_lighthouse(sc: Scene):
    lh = DESIGN["lighthouse"]
    z = lh["z"]
    r, bh = lh["base_r"], lh["base_h"]
    sc.box(-r, r, SEA_Y, SEA_Y + bh, z - r, z + r, COL["sand"])
    tr = lh["tower_r"]
    sc.box(-tr, tr, SEA_Y + bh, SEA_Y + bh + lh["tower_h"], z - tr, z + tr, COL["lighthouse"])
    top = SEA_Y + bh + lh["tower_h"]
    sc.box(-lh["sign_w"] / 2, lh["sign_w"] / 2, top - lh["sign_h"] - 6, top - 6, z - tr - 1.0, z - tr, COL["sign"])
    sc.box(-tr * 0.7, tr * 0.7, top, top + 8, z - tr * 0.7, z + tr * 0.7, (255, 236, 176))
    sc.label((0.0, top + 12, z), f"landmark lighthouse (z={z:.0f} m, candidate)")


def add_background(sc: Scene):
    # 島（+X が画面左）。遠景ビル群は左の水平線（+X 側）、かすみ色。
    islands = [(+700, 2600, 900, 60), (+260, 2200, 220, 25), (-800, 2400, 1000, 70), (-300, 3000, 260, 20)]
    for x, z, w, h in islands:
        sc.quad([(x - w / 2, SEA_Y, z), (x + w / 2, SEA_Y, z), (x + w * 0.2, SEA_Y + h, z), (x - w * 0.25, SEA_Y + h * 0.8, z)],
                COL["island"])
    for i, (dx, hh) in enumerate([(0, 180), (60, 260), (120, 210), (170, 300), (230, 190), (290, 240), (350, 160)]):
        x = 900 + dx * 1.6
        sc.box(x - 35, x + 35, SEA_Y, SEA_Y + hh, 9000, 9060, COL["skyline"])
    sc.label((1200.0, SEA_Y + 380, 9000), "distant hazy skyline (left horizon)")


def raster_triangle(rgb, zbuf, a, b, c, col):
    """画面座標 (x, y, 1/z) の三角形を Z バッファ付きで塗る（1/z は画面上で線形補間できる）。"""
    xs = (a[0], b[0], c[0])
    ys = (a[1], b[1], c[1])
    x0, x1 = max(0, int(math.floor(min(xs)))), min(W - 1, int(math.ceil(max(xs))))
    y0, y1 = max(0, int(math.floor(min(ys)))), min(H - 1, int(math.ceil(max(ys))))
    if x0 > x1 or y0 > y1:
        return
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-9:
        return
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    w0 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / den
    w1 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / den
    w2 = 1.0 - w0 - w1
    inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
    iz = w0 * a[2] + w1 * b[2] + w2 * c[2]
    zb = zbuf[y0:y1 + 1, x0:x1 + 1]
    m = inside & (iz > zb)
    zb[m] = iz[m]
    rgb[y0:y1 + 1, x0:x1 + 1][m] = col


def render(cam: Camera, sc: Scene, annotated: bool, title: str) -> Image.Image:
    img = Image.new("RGB", (W, H), COL["sky_low"])
    d = ImageDraw.Draw(img)
    hy = cam.horizon_y()
    for y in range(int(max(0, hy))):
        t = y / max(1, hy)
        d.line([(0, y), (W, y)], fill=tuple(int(COL["sky_top"][k] + (COL["sky_low"][k] - COL["sky_top"][k]) * t) for k in range(3)))
    for y in range(int(max(0, hy)), H):
        t = (y - hy) / max(1, H - hy)
        d.line([(0, y), (W, y)], fill=tuple(int(COL["sea_far"][k] + (COL["sea_near"][k] - COL["sea_far"][k]) * min(1, t * 1.6)) for k in range(3)))
    # 長い面（走路デッキなど）は平均奥行きの並べ替えでは前後が崩れるので、Z バッファで塗る。
    rgb = np.asarray(img, dtype=np.uint8).copy()
    zbuf = np.zeros((H, W), dtype=np.float64)          # 1/z（大きいほど手前）
    for pts, col, outline in sc.polys:
        cp = clip_poly([cam.cam(p) for p in pts])
        if len(cp) < 3:
            continue
        scr = [(*cam.px(c), 1.0 / c[2]) for c in cp]
        for i in range(1, len(scr) - 1):
            raster_triangle(rgb, zbuf, scr[0], scr[i], scr[i + 1], col)
    img = Image.fromarray(rgb)
    d = ImageDraw.Draw(img)
    if annotated:
        font = ImageFont.truetype("C:/Windows/Fonts/meiryob.ttc", 22)
        for p, text in sc.labels:
            c = cam.cam(p)
            if c[2] > NEAR:
                x, y = cam.px(c)
                if -50 < x < W + 50 and -50 < y < H + 50:
                    d.text((x, y), text, fill=(20, 20, 20), font=font, anchor="mb", stroke_width=3, stroke_fill=(255, 255, 255))
        d.text((24, 20), title, fill=(20, 20, 20), font=font, stroke_width=3, stroke_fill=(255, 255, 255))
        d.line([(0, hy), (W, hy)], fill=(255, 0, 255), width=1)
    return img


def build(kind: str) -> tuple[Camera, Scene, str]:
    sc = Scene()
    if kind == "2p":
        zf = 0.0
        cam = Camera((0.0, EYE_2P, zf - BACK_2P), (0.0, LOOK_2P, zf + AHEAD_2P), FOV_2P)
        goal_z = WALL_START + 10 * WALL_SPACING + 15.0   # game_state.gd: 22 + 30N + 15
        floor_front = goal_z + 20.0
        stand_end = BACK_Z + BLOCK * math.ceil((floor_front - BACK_Z) / BLOCK)
        title = f"2P camera: eye (0,{EYE_2P},{zf - BACK_2P}) look (0,{LOOK_2P},{zf + AHEAD_2P}) FOV {FOV_2P:.0f}"
        add_goal(sc, goal_z)
    elif kind == "1p":
        feet = (3.0, DECK_Y, 0.0)
        focus = (feet[0], feet[1] + FOCUS_1P, feet[2])
        cam = Camera((focus[0], focus[1] + BASE_1P, focus[2] - DIST_1P), (focus[0], focus[1], focus[2] + 8.0), FOV_1P)
        floor_front = 322.0
        stand_end = BACK_Z + BLOCK * math.ceil((floor_front - BACK_Z) / BLOCK)
        title = f"1P camera: eye {tuple(round(v, 2) for v in cam.eye)} FOV {FOV_1P:.0f}"
    elif kind == "goal":  # 2P カメラでゴールまで残り約 40m（壁はもう無い）
        zf = 0.0
        cam = Camera((0.0, EYE_2P, zf - BACK_2P), (0.0, LOOK_2P, zf + AHEAD_2P), FOV_2P)
        goal_z = 40.0
        floor_front = goal_z + 24.0
        stand_end = 367.5
        title = "2P camera near the goal (goal line 40 m ahead)"
        add_goal(sc, goal_z)
    elif kind == "ocean":  # 海落下カメラ（右スタンド側の水路に落ちた P1 を見る）
        cam = Camera((20.0, -5.5, -8.0), (19.0, -6.5, 30.0), 60.0)
        floor_front = 322.0
        stand_end = 327.5
        title = "water-lane view: eye 3.7 m above the sea in the channel, looking along the course"
    else:  # preload (2P の引き)
        cam = Camera((0.0, 7.3, -22.7), (0.0, LOOK_2P, AHEAD_2P), FOV_PRELOAD)
        goal_z = WALL_START + 10 * WALL_SPACING + 15.0
        floor_front = goal_z + 20.0
        stand_end = BACK_Z + BLOCK * math.ceil((floor_front - BACK_Z) / BLOCK)
        title = f"preload camera: eye (0,7.3,-22.7) FOV {FOV_PRELOAD:.0f}"
        add_goal(sc, goal_z)
    add_background(sc)
    add_lighthouse(sc)
    add_runway(sc, floor_front)
    if kind not in ("goal", "ocean"):
        add_walls(sc, (2,))
    for side in (1, -1):
        add_stand(sc, side, BACK_Z, stand_end)
    sc.label((world_x(1, 4.0), 6.0, 30.0), "P1 orange stand (+X, screen left)")
    sc.label((world_x(-1, 4.0), 6.0, 30.0), "P2 blue stand (-X, screen right)")
    sc.label((0.0, DECK_Y + 7.5, WALL_START + 2 * WALL_SPACING), "quiz wall (existing, 3rd wall)")
    sc.label((world_x(1, -8.0), SEA_Y + 1.0, 40.0), "water lane 15.2 m")
    # プレイヤーの目安（オレンジ＝+X）
    for x, col in ((3.0, COL["p1"]), (-3.0, COL["p2"])):
        sc.box(x - 0.4, x + 0.4, DECK_Y, DECK_Y + 1.8, -0.3, 0.3, col)
    return cam, sc, title


def main():
    for kind in ("2p", "1p", "preload", "goal", "ocean"):
        cam, sc, title = build(kind)
        for annotated in (False, True):
            name = f"guide_{kind}_{'annotated' if annotated else 'clean'}.png"
            render(cam, sc, annotated, title).save(HERE / name)
            print(name, "horizon y", round(cam.horizon_y(), 1))


if __name__ == "__main__":
    main()

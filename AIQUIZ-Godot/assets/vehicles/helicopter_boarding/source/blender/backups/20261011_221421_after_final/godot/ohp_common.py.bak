"""AIQUIZ ONLINE HELIPORT（オンライン対戦メニューの背景）ビルダーの共通設定。v2：パッド 1 つ。

座標：オンラインメニューの 3D ワールド（Godot）。デッキ上面 y = -1.2、海面 y = -9.2。パッドの中心が原点。
Blender には g2b で置く（Godot (x, y, z) → Blender (x, -z, y)）。部品の寸法はここだけで決め、ビルダーと部品はここを読む。
ゲームの値（デッキ・海面）は .gd から、ヘリの寸法と目印は乗り込めるヘリの配置 JSON から、
カメラは演出の定数（scripts/world/online_staging/online_staging_timeline.gd）から直接読む。
形と材質の道具はスタジアムのビルダーの aqs_geom を使う。

ヘリの座標（H）：原点＝ヘリの接地点、+x＝機体の右、+y＝上、-z＝機首（仕様書 5）。h2g で Godot のワールドへ。
"""
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

from mathutils import Vector

HERE = Path(__file__).resolve().parent
SRC = HERE.parent
ASSET = SRC.parent
ROOT = ASSET.parents[1]
STADIUM_BLENDER = ROOT / "assets" / "aiquiz_stadium" / "source" / "blender"
if str(STADIUM_BLENDER) not in sys.path:
    sys.path.insert(0, str(STADIUM_BLENDER))

from aqs_geom import hexcol  # noqa: E402

BLEND = HERE / "online_heliport.blend"
TEX = SRC / "textures"
PREVIEW = SRC / "previews"
EVIDENCE = ROOT / "artifacts" / "online_heliport" / "blender"
GLB = ASSET / "online_heliport.glb"
LAYOUT_JSON = ASSET / "online_heliport_layout.json"
REPORT = SRC / "build_report.json"
SCENE_NAME = "OHP_OnlineHeliport"
HELI_DIR = ROOT / "assets" / "vehicles" / "helicopter_boarding"
HELI_GLB = HELI_DIR / "helicopter_boarding.glb"
HELI_LAYOUT = HELI_DIR / "helicopter_boarding_layout.json"
CITY_GLB = ROOT / "assets" / "aiquiz_menu_stage" / "aiquiz_menu_city.glb"
TIMELINE_GD = ROOT / "scripts" / "world" / "online_staging" / "online_staging_timeline.gd"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_RENDER = "--no-render" not in ARGS
DO_SAVE = "--no-save" not in ARGS


# --- ゲームの値（.gd から読む） ----------------------------------------------
def _gd(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _const_float(text: str, name: str) -> float:
    m = re.search(r"const\s+%s\s*(?::\s*float)?\s*:?=\s*(-?[\d.]+)" % re.escape(name), text)
    if m is None:
        raise KeyError(name)
    return float(m.group(1))


_SC = _gd("scripts/world/stage_constants.gd")
DECK_Y = _const_float(_SC, "FLOOR_TOP_Y")          # -1.2
SEA_Y = _const_float(_SC, "OCEAN_SURFACE_Y")       # -9.2

# --- ヘリ（乗り込めるヘリ。寸法と目印は配置 JSON から） ------------------------------
HELI = json.loads(HELI_LAYOUT.read_text(encoding="utf-8"))
HELI_SKID_DROP = float(HELI["skid_drop"])          # 1.75（GLB の原点はデッキの上この高さ）
HELI_ROTOR_R = float(HELI.get("main_rotor", {}).get("radius", 5.3))
_TR = HELI.get("tail_rotor", {})
_TP = _TR.get("pivot", [0.3, 1.87, 6.55])
HELI_TAIL_ROTOR = (float(_TP[0]), float(_TP[1]) + HELI_SKID_DROP, float(_TP[2]))   # H 座標（尾のファン／ローターの中心）
HELI_TAIL_ROTOR_R = float(_TR.get("shroud_radius", _TR.get("radius", 0.65)))      # フェネストロンなら囲いの外形
# パッドの上のヘリの向き（Godot の Y 回り、度。0 で機首が -Z）。
# 待機のカメラ（H の左前）が太陽の側に来るように回す：太陽は Godot の方位 145°（+X・-Z の上、仰角 60°）
HELI_YAW_DEG = -90.0

# --- 配置（パッド 1 つ。すべてデッキの高さ） ----------------------------------------
PAD = (0.0, 0.0)            # パッドの中心（Godot の x, z）
PAD_FLAT = 18.0             # 八角形の対辺（ローターの直径 10.6 m の 1.7 倍）
PAD_R = PAD_FLAT / 2 / math.cos(math.pi / 8)
PAD_T = 0.30
PAD_RIM_H = 0.08
PAD_RIM_W = 0.14
NET_W = 1.5
NET_DROP = math.tan(math.radians(10.0)) * NET_W
PAD_LAMPS = 16
COLUMN_R = 1.6
LEG_BOTTOM = SEA_Y - 8.0
# H の中の目印（接地点の真下が H の中心）
TD_RING_R = 4.4             # 黄色の輪（中心線の半径）
TD_RING_W = 0.6
H_LEG_GAP = 1.4             # H の 2 本の足（機体の左右 ±）
H_LEG_LEN = 5.0
H_BAR_W = 0.42

# 小物の位置（H 座標の x, z。デッキの縁の内側、ローターの円の外）
H_WINDSOCK = (6.6, -4.8)
H_FLAGS = ((3.2, 7.5), (4.7, 6.7))
H_FLOODS = ((-6.0, 5.6),)
H_MONITORS = ((7.9, 1.6), (-2.6, -7.8))
H_CABINETS = ((8.1, -1.2, 0.0), (8.1, -2.3, 0.0))   # (x, z, 向きの回転)
H_BUOYS = ((-7.6, 3.4), (5.6, 6.2), (-1.0, 8.3), (7.0, -4.0))
# 風下の向き（Blender の Z 回り、度）。吹き流し・旗がこの向きへ流れる
WIND_DEG = -60.0

# --- 色（スタジアム・メニューと同じパレット） ----------------------------------------
C = {
    "white": hexcol("#ECE9E2"), "white2": hexcol("#E2DFD8"), "cobalt": hexcol("#2F5FA8"), "cobalt_dark": hexcol("#24497F"),
    "navy": hexcol("#1D2F5C"), "navy2": hexcol("#3B5068"), "orange": hexcol("#F28C33"), "orange_dark": hexcol("#C9671C"),
    "blue": hexcol("#33A6E6"), "amber": hexcol("#FFB23E"), "steel": hexcol("#7C8A94"), "steel_dark": hexcol("#5B6670"),
    "dark": hexcol("#1F262E"), "deck_edge": hexcol("#4A5652"), "red": hexcol("#D8352B"), "red_dark": hexcol("#9E2620"),
    "yellow": hexcol("#F2C230"), "black": hexcol("#22252A"), "lens": hexcol("#FFF3D6"), "glass_frame": hexcol("#D5D9DD"),
    "lamp_green": hexcol("#5BE38A"), "rubber": hexcol("#2A2D31"), "concrete": hexcol("#B9BDBF"),
}


def g2b(x, y, z):
    """Godot のワールド座標 → Blender の位置。"""
    return Vector((x, -z, y))


def b2g(v):
    """Blender の位置 → Godot のワールド座標（タプル）。"""
    return (round(v[0], 4), round(v[2], 4), round(-v[1], 4))


def gxz(p):
    """Godot (x, z) → Blender (x, y)。"""
    return (p[0], -p[1])


def h2g(x, y, z):
    """ヘリの座標（H）→ Godot のワールド座標。"""
    a = math.radians(HELI_YAW_DEG)
    gx = x * math.cos(a) + z * math.sin(a)
    gz = -x * math.sin(a) + z * math.cos(a)
    return (PAD[0] + gx, DECK_Y + y, PAD[1] + gz)


def h2g_xz(x, z):
    g = h2g(x, 0.0, z)
    return (g[0], g[2])


def heli_marker(name):
    """乗り込めるヘリの目印（H 座標の地面の位置）。"""
    mk = HELI["markers"][name]["position"]
    return (mk[0], mk[1] + HELI_SKID_DROP, mk[2])


IDLE_SPOT = h2g_xz(*(lambda m: (m[0], m[2]))(heli_marker("MK_IdleSpot")))


# --- カメラ（演出の定数から読む。H 座標） ---------------------------------------------
def _read_cameras():
    text = TIMELINE_GD.read_text(encoding="utf-8")
    pat = re.compile(r'"(CAM_\w+)":\s*\{"pos":\s*Vector3\(([^)]*)\),\s*"look":\s*Vector3\(([^)]*)\),\s*"fov":\s*([\d.]+)\}')
    out = {}
    for name, pos, look, fov in pat.findall(text):
        out[name] = (tuple(float(v) for v in pos.split(",")), tuple(float(v) for v in look.split(",")), float(fov))
    if "CAM_Idle" not in out:
        raise KeyError("CAM_Idle is missing in %s" % TIMELINE_GD)
    return out


CAMERAS_H = _read_cameras()
# パッドの上で使うショット（ヘリが止まっているときの H → ワールド）と、確認用の全体
PAD_CAMERAS = ("CAM_Idle", "CAM_Board", "CAM_Cockpit", "CAM_PadLow")
CAMERAS = {name: (h2g(*CAMERAS_H[name][0]), h2g(*CAMERAS_H[name][1]), CAMERAS_H[name][2]) for name in PAD_CAMERAS}
CAMERAS["CAM_Overview"] = ((-34.0, 22.0, 30.0), (0.0, -2.0, 0.0), 40.0)


# --- 街（メニューの街の GLB、街のローカル：+Y が正面・原点が海面）を置く方位と距離 --------
CITY_BEARING = -8.0         # CAM_Idle の視線から見た方位（右が正）
CITY_DISTANCE = 1150.0
CITY_CENTER_LOCAL_Y = -100.0


def camera_rotation_deg(pos, target):
    """Godot の Camera3D の回転（度、YXZ）：pos から target を向く。"""
    dx, dy, dz = (target[i] - pos[i] for i in range(3))
    yaw = math.degrees(math.atan2(-dx, -dz))
    pitch = math.degrees(math.atan2(dy, math.hypot(dx, dz)))
    return (round(pitch, 3), round(yaw, 3), 0.0)


def city_placement():
    """街の原点（Godot）と Y 回り：CAM_Idle の視線から方位 CITY_BEARING・距離 CITY_DISTANCE に街の中心を置き、正面をカメラへ。"""
    cam, look, _fov = CAMERAS["CAM_Idle"]
    base = math.atan2(look[0] - cam[0], -(look[2] - cam[2]))      # 視線の方位（右が正、0 = -Z）
    t = base + math.radians(CITY_BEARING)
    cx = cam[0] + CITY_DISTANCE * math.sin(t)
    cz = cam[2] - CITY_DISTANCE * math.cos(t)
    yaw_face = math.atan2(cam[0] - cx, cam[2] - cz)
    yaw = yaw_face + math.pi
    off_local = Vector((0.0, 0.0, -CITY_CENTER_LOCAL_Y))
    s, c = math.sin(yaw), math.cos(yaw)
    off_world = (off_local.x * c + off_local.z * s, -off_local.x * s + off_local.z * c)
    origin = (cx - off_world[0], SEA_Y, cz - off_world[1])
    return {"position": origin, "yaw": yaw, "center": (cx, SEA_Y, cz)}

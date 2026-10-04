"""ビルダー共通の設定：パス、寸法表、ゲームの定数、色、座標変換。"""
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

from mathutils import Vector

from aqs_geom import hexcol

HERE = Path(__file__).resolve().parent
SRC = HERE.parent
ASSET = SRC.parent
ROOT = ASSET.parents[1]
DIMS = json.loads((SRC / "dimensions.json").read_text(encoding="utf-8"))
CONST = json.loads((SRC / "game_constants.json").read_text(encoding="utf-8"))
LAYOUT_GS = CONST["json"]["goal_stand_layout"]
M = DIMS["modules"]
ST = M["side_stand_block"]["data"]
SR = ST["sail_rig"]
GG = M["goal_gate"]["data"]
GS = M["goal_stand_B"]["data"]
LH = M["lighthouse"]["data"]
BG = M["background"]["data"]
BLEND = HERE / "aiquiz_stadium.blend"
PREVIEW = SRC / "previews"
EVIDENCE = ROOT / "artifacts" / "aiquiz_stadium" / "blender"
TEX = SRC / "textures"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_RENDER = "--no-render" not in ARGS
DO_WEAR = "--no-wear" not in ARGS      # スタンド・ゲート・ゴール観客席の頂点色へ AO・汚れ・ムラを焼く（aqs_wear）。--no-wear で省く
ONLY = None
if "--only-renders" in ARGS:
    ONLY = set(ARGS[ARGS.index("--only-renders") + 1].split(","))

_SC = CONST["constants"]["scripts/world/stage_constants.gd"]
SEA_Y = _SC["OCEAN_SURFACE_Y"]["value"]        # -9.2
DECK_Y = _SC["FLOOR_TOP_Y"]["value"]           # -1.2（ベルトの上面）
SEABED_Y = SEA_Y - _SC["OCEAN_DEPTH"]["value"]  # -129.2
FLOOR_WIDTH = _SC["FLOOR_WIDTH"]["value"]      # 24
_OCEAN = re.search(r"OCEAN_SIZE: Vector2 = Vector2\(([\d.]+), ([\d.]+)\)", (ROOT / "scripts/world/stage_constants.gd").read_text(encoding="utf-8"))
OCEAN_HALF = (float(_OCEAN.group(1)) / 2, float(_OCEAN.group(2)) / 2)   # ゲームの海の板（半透明）の半分の大きさ
OCEAN_CENTER_Z = _SC["OCEAN_CENTER_Z"]["value"]
CAM = CONST["constants"]["scripts/world/camera_controller.gd"]
GOAL_Z = _SC["WALL_START_Z"]["value"] + 10 * _SC["WALL_SPACING"]["value"] + 15.0   # 2P・10 問のゴール（game_world.gd と同じ式）
GOAL_STAND_OFFSET = 25.8

# --- 色（palette.json の頂点色の値） -----------------------------------------
C = {
    "white": hexcol("#ECE9E2"), "riser": hexcol("#E4E1DA"), "cobalt": hexcol("#2F5FA8"), "panel": hexcol("#1E4E96"),
    "step": hexcol("#CFD3D8"), "wood": hexcol("#7A5A3C"), "sail": hexcol("#F2EEE6"), "navy": hexcol("#3B5068"),
    "steel": hexcol("#7C8A94"), "lantern": hexcol("#FFE6B0"), "sand": hexcol("#EADBB8"), "green": hexcol("#5E9E5A"),
    "rock": hexcol("#A4989C"), "seat": hexcol("#F6F4F0"), "glass": hexcol("#26323E"), "warm": hexcol("#FFC878"),
    "cool": hexcol("#EAF4FF"), "orange": hexcol("#F28C33"), "blue": hexcol("#33A6E6"), "dark": hexcol("#2B323A"),
    "rope": hexcol("#5A4E44"), "sea_tint": hexcol("#9FC9C4"), "dome": hexcol("#9AA3AE"), "deck_under": hexcol("#D9D6CF"),
}
IMG_WHITE = (1.0, 1.0, 1.0, 1.0)   # 画像の面の頂点色（掛けても色が変わらない）

# 遠景のかすみ（shaders/aiquiz_backdrop.gdshader の既定値と同じ式）：
# 量 = min(max, (1 - exp(-距離 / distance)) × (1 - height_clear × 高さ(0..height m) の smoothstep))
HAZE = {"distance": 10000.0, "max": 0.6, "height": 350.0, "height_clear": 0.3}


def g2b(x, y, z):
    """Godot のワールド座標 → Blender の位置。"""
    return Vector((x, -z, y))


def bearing_pos(bearing_deg, distance, y=None):
    """スタート地点から見た方位（正＝左＝Godot +X）と距離 → Godot の位置。"""
    t = math.radians(bearing_deg)
    return (distance * math.sin(t), SEA_Y if y is None else y, distance * math.cos(t))


def in_ocean(gx, gz, margin=0.0):
    """Godot の位置がゲームの海の板の内側か（外は空の下半分が見えるので、海の中の地形や白波を作らない）。"""
    return abs(gx) + margin <= OCEAN_HALF[0] and abs(gz - OCEAN_CENTER_Z) + margin <= OCEAN_HALF[1]


def facing_yaw(gx, gz):
    """部品の +Y（Blender）＝正面を、スタート地点へ向ける Z 回り（度）。Godot の Y 回りと同じ符号。"""
    # Blender での向き：部品の位置 (gx, -gz) から原点へ
    dx, dy = -gx, gz
    return math.degrees(math.atan2(-dx, dy))

"""AIQUIZ HARBOR LAUNCH（メニューのステージ）ビルダーの共通設定。

座標：メニューのワールド（Godot）。ベルトの中心線 x = 0、ベルト上面 y = -1.2、ベルトは z -136〜8、
海面 y = -9.2、メニューのカメラは -Z（ベルトの奥）を向く。Blender には g2b で置く（Godot (x, y, z) → Blender (x, -z, y)）。
ゲームの値は .gd から直接読む（ゲーム側が変われば作り直しで追従する）。形と材質の道具はスタジアムのビルダーの aqs_geom を使う。
"""
from __future__ import annotations

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

from aqs_geom import hexcol  # noqa: E402  （スタジアムの形と材質の道具）

BLEND = HERE / "aiquiz_menu_stage.blend"
TEX = SRC / "textures"
PREVIEW = SRC / "previews"
EVIDENCE = ROOT / "artifacts" / "aiquiz_menu_stage" / "blender"
GLB = ASSET / "aiquiz_menu_stage.glb"
CITY_GLB = ASSET / "aiquiz_menu_city.glb"      # メニューの街（手前を作り直した街、街のローカル座標）
LAYOUT_JSON = ASSET / "aiquiz_menu_stage_layout.json"
REPORT = SRC / "build_report.json"
STADIUM_BLEND = STADIUM_BLENDER / "aiquiz_stadium.blend"
SCENE_NAME = "AIQUIZ_MenuStage"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_RENDER = "--no-render" not in ARGS


# --- ゲームの値（.gd から読む） ----------------------------------------------
def _gd(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _const_float(text: str, name: str) -> float:
    m = re.search(r"const\s+%s\s*(?::\s*float)?\s*:?=\s*(-?[\d.]+)" % re.escape(name), text)
    if m is None:
        raise KeyError(name)
    return float(m.group(1))


def _const_vec3(text: str, name: str) -> tuple:
    m = re.search(r"%s\s*:?=\s*Vector3\(\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)" % re.escape(name), text)
    if m is None:
        raise KeyError(name)
    return tuple(float(m.group(i)) for i in (1, 2, 3))


_SC = _gd("scripts/world/stage_constants.gd")
_PV = _gd("scripts/ui/menu_wall_background_preview.gd")
_HP = _gd("scripts/ui/menu_helicopter_sequence_profile.gd")
_HD = _gd("scripts/world/helicopter_arrival_director.gd")

DECK_Y = _const_float(_SC, "FLOOR_TOP_Y")                  # -1.2（ベルト上面）
SEA_Y = _const_float(_SC, "OCEAN_SURFACE_Y")               # -9.2
BELT_HALF = _const_float(_SC, "FLOOR_HALF_WIDTH")          # 12
FRAME_W = _const_float(_SC, "CONVEYOR_SIDE_FRAME_WIDTH")   # 0.24
FRAME_H = _const_float(_SC, "CONVEYOR_SIDE_FRAME_HEIGHT")  # 1.05
FRAME_CLEAR = _const_float(_SC, "CONVEYOR_SIDE_FRAME_TOP_CLEARANCE")
RAIL_H = _const_float(_SC, "FLOOR_RAIL_HEIGHT")            # 0.26
# 側枠（stage_environment.gd）：ベルトの縁の内側 x ±11.76〜12.0、上面はベルト上 0.08（y -1.12）、高さ 1.05
FRAME_TOP = DECK_Y + FRAME_CLEAR                            # -1.12
FRAME_BOTTOM = FRAME_TOP - FRAME_H                          # -2.17
BELT_EDGE = BELT_HALF                                       # 12.0：ベルトの箱と側枠の外面
# メニューのベルト（menu_wall_background_preview.gd の _stage_env.build）
_m = re.search(r'"floor_center_z":\s*(-?[\d.]+),\s*"floor_length":\s*([\d.]+)', _PV)
MENU_FLOOR_CENTER_Z = float(_m.group(1))
MENU_FLOOR_LENGTH = float(_m.group(2))
BELT_Z0 = MENU_FLOOR_CENTER_Z - MENU_FLOOR_LENGTH / 2      # -136（奥）
BELT_Z1 = MENU_FLOOR_CENTER_Z + MENU_FLOOR_LENGTH / 2      # 8（手前）
PLAYER_X = (_const_float(_PV, "PREVIEW_PLAYER_X"), _const_float(_PV, "PREVIEW_PLAYER2_X"))
PICKUPS = [_const_vec3(_HP, n) for n in ("pickup_single_ground", "pickup_left_ground", "pickup_right_ground")]
PICKUP_HOVER = _const_float(_HD, "MENU_PICKUP_HOVER_HEIGHT")
OLD_CAM_POS = _const_vec3(_PV, "PREVIEW_CAM_POS")
OLD_CAM_ROT = _const_vec3(_PV, "PREVIEW_CAM_ROT_DEG")
CAM_FOV = _const_float(_PV, "PREVIEW_CAM_FOV")

# --- メニューの新しいカメラ（街を背にする） ----------------------------------
CAMERA = {"position": OLD_CAM_POS, "rotation_deg": (-7.0, OLD_CAM_ROT[1], 0.0), "fov": CAM_FOV}

# --- 他の演出が使う場所（ここには何も置かない） --------------------------------
# のこぎりの台車・操縦席のデッキ（左へ 2.25m 展開）・収納した刃（|x| 14.06〜16.61、ベルト面の 1.9m 下）が動く範囲
SAW_ZONE_Z = (-12.0, 14.0)
SAW_STOW_X = (13.95, 16.8)
OPERATOR_DECK_BOTTOM_Y = DECK_Y - 0.80                      # 操縦席の床の下面（床下げ 0.63 + 厚み）の目安
HELI_ROTOR_R = 5.2

# --- ステージの寸法 -------------------------------------------------------------
# 2026-09-30：ユーザーの依頼「コンベアの横の白い杭とライトを消して、コンベアとディスプレイの間の道も消して、
# ディスプレイのステージだけ残して」で、走路の脇の部品（白い丸杭・奥の歩道・ガラスの手すり・琥珀の灯・照明塔）と
# 発進デッキから走路への橋を組み立てから外した。ベルトの箱の側面の白い外装（AMS_PierFascia）も外したが、
# この 1 つだけは下の旗で戻せる。
KEEP_PIER_FASCIA = False              # True：ベルトの箱の側面に白い外装とコバルトの帯（AMS_PierFascia）を戻す
RUNWAY_SIDE_CLEAR_X = 16.0            # 走路の脇（|x| がこれ未満、ベルトの z の範囲）には外装のほかに何も置かない（検算・テスト）
NEAR_Z = -12.0                        # これより手前（カメラ側）は台車が動くので、走路の縁は外装だけ
FASCIA_TOP = -2.30                    # 外装の上端（操縦席のデッキの下に 0.3m 以上）
FASCIA_T = 0.32                       # 外装の厚み（ベルトの側面 x=±12 から外へ）
PILE_BOTTOM = SEA_Y - 3.0             # 杭は海の下まで（ゲームの海は半透明）。発進デッキの杭が使う
WALK_TOP = FRAME_TOP                  # 発進デッキの床の上面（もとは奥の歩道の上面。側枠の上面とそろえる、-1.12）
WALK_BOTTOM = WALK_TOP - 0.88         # 外装の奥の区間の上端
DECK_C = (30.0, -34.0)                # 発進デッキの中心（Godot x, z）
DECK_R = 12.0
DECK_T = 1.2
# 使っていない走路の脇の部品（ams_parts の「使っていない部品」）の寸法。組み立てには使わない
PILE_R = 0.55
PILE_STEP = 8.0
WALK_OUT = 13.8                       # 奥の歩道の外端 |x|
RAIL_POST_STEP = 2.0
LAMP_STEP = 8.0
TOWER_X = 15.6
TOWER_Z = (-24.0, -52.0, -80.0, -108.0)
TOWER_H = 10.0                        # 歩道の上から

# --- 街（スタジアムの遠景の AQS_BG_City）をメニューのワールドへ --------------------
CITY_BEARING = 25.0                   # カメラから見た方位（右が正、0 = -Z）
CITY_DISTANCE = 1100.0
CITY_CENTER_LOCAL_Y = -100.0          # 街のローカルで「中心」とみなす奥行き（高層ビルの密集）

# --- 色（スタジアムの palette.json と同じ頂点色） --------------------------------
C = {
    "white": hexcol("#ECE9E2"), "white2": hexcol("#E2DFD8"), "paving": hexcol("#D9DADB"), "joint": hexcol("#BFC3C8"),
    "cobalt": hexcol("#2F5FA8"), "cobalt_dark": hexcol("#24497F"), "navy": hexcol("#1D2F5C"), "navy2": hexcol("#3B5068"),
    "orange": hexcol("#F28C33"), "blue": hexcol("#33A6E6"), "amber": hexcol("#FFB23E"), "amber_dark": hexcol("#6A4A1C"),
    "steel": hexcol("#7C8A94"), "dark": hexcol("#1F262E"), "speaker": hexcol("#222A33"), "speaker_ring": hexcol("#3A4552"),
    "lens": hexcol("#FFF3D6"), "trunk": hexcol("#8A6A48"), "trunk_dark": hexcol("#6E5238"), "leaf": hexcol("#3E8F45"),
    "leaf_light": hexcol("#6DBA5A"), "soil": hexcol("#5A4632"), "glass": hexcol("#BFE6F2", 0.35), "sock_w": hexcol("#F4F1EA"),
    "pile_ring": hexcol("#2F5FA8"), "pad_line": hexcol("#F6F4EE"), "hood": hexcol("#C9CFD6"),
}


def g2b(x, y, z):
    """Godot のワールド座標 → Blender の位置。"""
    return Vector((x, -z, y))


def camera_basis_forward(rot_deg):
    """Godot の回転（度、YXZ）→ 前方（-Z）のベクトル（Godot）。"""
    rx, ry = math.radians(rot_deg[0]), math.radians(rot_deg[1])
    return Vector((-math.sin(ry) * math.cos(rx), math.sin(rx), -math.cos(ry) * math.cos(rx)))


def facing_yaw(from_xz, to_xz):
    """from から to を向く Godot の Y 回り（ラジアン）。ローカル +Z が to の方向。"""
    dx, dz = to_xz[0] - from_xz[0], to_xz[1] - from_xz[1]
    return math.atan2(dx, dz)


def city_placement():
    """街（ローカル：+Y が正面、原点が海面）をメニューのワールドへ置く。

    返り値：Godot の位置（街の原点）と Y 回り（ラジアン）、Blender の行列の要素。
    街の「中心」（ローカル (0, CITY_CENTER_LOCAL_Y)）をカメラから方位 CITY_BEARING・距離 CITY_DISTANCE に置き、正面をカメラへ向ける。
    """
    cam = CAMERA["position"]
    t = math.radians(CITY_BEARING)
    cx = cam[0] + CITY_DISTANCE * math.sin(t)
    cz = cam[2] - CITY_DISTANCE * math.cos(t)
    yaw_face = facing_yaw((cx, cz), (cam[0], cam[2]))   # 街の正面（Godot ローカル -Z ではなく、Blender ローカル +Y）
    # Blender：街のローカル +Y（正面）→ Godot では -Z（ローカル）。Godot の Y 回り yaw で -Z が (−sin, −cos) を向く。
    # 正面をカメラへ向けるには、Godot ローカル -Z をカメラ方向へ：yaw = yaw_face + π
    yaw = yaw_face + math.pi
    # 中心（ローカル Godot (0, 0, -CITY_CENTER_LOCAL_Y)）が (cx, cz) に来るよう原点を戻す
    off_local = Vector((0.0, 0.0, -CITY_CENTER_LOCAL_Y))
    s, c = math.sin(yaw), math.cos(yaw)
    off_world = (off_local.x * c + off_local.z * s, -off_local.x * s + off_local.z * c)
    origin = (cx - off_world[0], SEA_Y, cz - off_world[1])
    return {"position": origin, "yaw": yaw, "center": (cx, SEA_Y, cz)}

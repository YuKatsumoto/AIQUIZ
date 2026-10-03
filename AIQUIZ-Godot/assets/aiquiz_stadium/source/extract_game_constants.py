"""AIQUIZ STADIUM の寸法表が守るべきゲーム定数を、ソースから読み取って game_constants.json に書く。

手で写さないための抽出器。作業ツリーに未コミット変更があるので、git HEAD と
各ファイルの sha256 を一緒に残す。

    python assets/aiquiz_stadium/source/extract_game_constants.py
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "game_constants.json"

# ファイル → 読み取る定数名。GDScript は `const NAME[: T] := value`、Python は `NAME = value`
# （タプル代入 `A, B = 1, 2` も可）。
GD_CONSTANTS = {
    "scripts/world/stage_constants.gd": [
        "FLOOR_TOP_Y", "OCEAN_DEPTH", "FLOOR_WIDTH", "FLOOR_HALF_WIDTH",
        "FLOOR_RAIL_HEIGHT", "FLOOR_RAIL_WIDTH", "FLOOR_RAIL_INSET",
        "CONVEYOR_ROLLER_RADIUS", "CONVEYOR_ROLLER_LENGTH",
        "CONVEYOR_SIDE_FRAME_WIDTH", "CONVEYOR_SIDE_FRAME_HEIGHT",
        "CONVEYOR_SIDE_FRAME_OVERHANG", "CONVEYOR_SIDE_FRAME_TOP_CLEARANCE",
        "OCEAN_SURFACE_Y", "OCEAN_ENTRY_Y", "OCEAN_SINK_Y", "OCEAN_CENTER_Z",
        "FLOOR_BACK_Z", "WALL_START_Z", "WALL_SPACING",
    ],
    "scripts/world/conveyor_rails.gd": ["CENTER_X", "TOP_HEIGHT"],
    "scripts/world/santorini_terrace_stand.gd": ["BLOCK_LENGTH", "MIN_BLOCKS", "PERGOLA_EVERY"],
    "scripts/world/goal_stand/goal_stand.gd": ["GOAL_OFFSET", "SPACING", "P1_COLOR", "P2_COLOR"],
    "scripts/world/camera_controller.gd": [
        "PRELOAD_CAMERA_FOV", "THIRD_PERSON_FOV", "THIRD_PERSON_DISTANCE",
        "THIRD_PERSON_FOCUS_HEIGHT", "THIRD_PERSON_BASE_HEIGHT",
        "TWO_PLAYER_FOV", "TWO_PLAYER_EYE_Y", "TWO_PLAYER_LOOK_Y", "TWO_PLAYER_LOOK_AHEAD",
        "TWO_PLAYER_CAMERA_BACK", "TWO_PLAYER_REAR_MAX_BACK",
    ],
    "scripts/world/helicopter_arrival_director.gd": [
        "RELEASE_HEIGHT", "HELICOPTER_ABOVE_RELEASE", "OFFSCREEN_DISTANCE", "EXIT_RISE_HEIGHT",
        "OCEAN_SIDE_HOVER_HEIGHT", "OCEAN_SIDE_APPROACH_RISE",
    ],
    "scripts/world/ghost_shark_ride_controller.gd": ["HOVER_OUTSIDE_STAGE_OFFSET"],
    "scripts/core/game_state.gd": ["RESULT_WALK_FINISH_OFFSET", "MIN_PLAY_FLOOR_FRONT_Z"],
}
PY_CONSTANTS = {
    "assets/environment/santorini_grandstand/source/build_santorini_grandstand.py": [
        "ROW_COUNT", "ROW_FRONT", "ROW_PITCH", "ROW_RISE", "ROW_BASE", "SEAT_OFFSET",
        "SEAT_PITCH", "AISLE_HALF_WIDTH", "AISLE_CLEARANCE", "FRONT_X", "BACK_X",
    ],
    "assets/environment/santorini_grandstand/source/build_terrace_modules.py": [
        "BLOCK_LENGTH", "GROUND_DROP", "SEATS_PER_ROW",
    ],
    "assets/goal_stand/source/build_scoreboard.py": [
        "BACK_TOP", "DECK_FOOT", "DEPTH", "SCREEN_W", "SCREEN_H", "BEZEL", "CAB_BOTTOM",
        "SIGN_W", "SIGN_H", "PILASTER", "LEG_X",
    ],
}
JSON_FILES = {
    "goal_stand_layout": "assets/goal_stand/goal_stand_layout.json",
}
# JSON は座席などの大きな配列を除き、スカラーと小さな辞書だけを残す。
TERRACE_JSON = "assets/environment/santorini_grandstand/santorini_terrace_modules.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_value(text: str):
    text = text.strip().split("#")[0].strip()
    color = re.fullmatch(r"Color\(([^)]*)\)", text)
    if color:
        return {"Color": [float(v) for v in color.group(1).split(",")]}
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    try:
        return float(text) if re.fullmatch(r"-?\d+(\.\d+)?", text) else text
    except ValueError:
        return text


def read_gd(path: Path, names: list[str]) -> dict:
    found = {}
    for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        m = re.match(r"\s*const\s+([A-Z0-9_]+)\s*(?::\s*[\w\[\]]+)?\s*:?=\s*(.+)$", line)
        if m and m.group(1) in names and m.group(1) not in found:
            found[m.group(1)] = {"value": parse_value(m.group(2)), "line": no}
    return found


def read_py(path: Path, names: list[str]) -> dict:
    found = {}
    for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        m = re.match(r"^([A-Z0-9_]+(?:\s*,\s*[A-Z0-9_]+)*)\s*=\s*(.+)$", line)
        if not m:
            continue
        keys = [k.strip() for k in m.group(1).split(",")]
        rhs = m.group(2).split("#")[0].strip()
        values = [v.strip() for v in rhs.split(",")] if len(keys) > 1 else [rhs]
        for key, raw in zip(keys, values):
            if key in names and key not in found:
                try:
                    value = eval(raw, {"__builtins__": {}}, {})  # 数値リテラルのみ
                except Exception:
                    value = raw
                found[key] = {"value": value, "line": no}
    return found


def main() -> None:
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip()
    dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    result = {"git_head": head, "sources": {}, "constants": {}, "json": {}}

    def record(rel: str, values: dict, expected: list[str]):
        path = ROOT / rel
        result["sources"][rel] = {
            "sha256": sha256(path),
            "uncommitted_change": any(rel in line for line in dirty.splitlines()),
        }
        missing = [n for n in expected if n not in values]
        if missing:
            raise SystemExit(f"{rel}: 定数が見つからない {missing}")
        result["constants"][rel] = values

    for rel, names in GD_CONSTANTS.items():
        record(rel, read_gd(ROOT / rel, names), names)
    for rel, names in PY_CONSTANTS.items():
        record(rel, read_py(ROOT / rel, names), names)
    for key, rel in JSON_FILES.items():
        path = ROOT / rel
        result["sources"][rel] = {"sha256": sha256(path),
                                  "uncommitted_change": any(rel in l for l in dirty.splitlines())}
        result["json"][key] = json.loads(path.read_text(encoding="utf-8"))
    terrace = json.loads((ROOT / TERRACE_JSON).read_text(encoding="utf-8"))
    result["sources"][TERRACE_JSON] = {"sha256": sha256(ROOT / TERRACE_JSON),
                                       "uncommitted_change": any(TERRACE_JSON in l for l in dirty.splitlines())}
    bay = terrace["blocks"]["bay"] if isinstance(terrace.get("blocks"), dict) else terrace["blocks"][0]
    rows = sorted({s[3] for s in bay["seats"]})
    result["json"]["terrace_modules"] = {
        "block_length": terrace["block_length"],
        "seat_rows": terrace["seat_rows"],
        "bay_seats": len(bay["seats"]),
        "bay_aisle_z": bay["aisle_z"],
        "row_front_x": [next(s[0] for s in bay["seats"] if s[3] == r) for r in rows],
        "row_cushion_top": [next(s[1] for s in bay["seats"] if s[3] == r) for r in rows],
        "seat_z_range": [min(s[2] for s in bay["seats"]), max(s[2] for s in bay["seats"])],
    }

    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    n = sum(len(v) for v in result["constants"].values())
    print(f"{OUT.name}: {n} constants from {len(result['sources'])} files, HEAD {head[:7]}")


if __name__ == "__main__":
    main()

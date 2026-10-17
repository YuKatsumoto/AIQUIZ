"""PV S01〜S07 の音声を作る（曲はまだ入れない）。撮影で鳴った効果音（各テイクの cues.json）を、ゲームと同じファイル・
同じ音量で同じ時刻に並べ、観客の環境音とヘリの音を敷く。

    python tools/pv/mix_s01_s07.py docs/pv/previz/v4/PV_S01-S07_audio.wav

  S01〜S03  artifacts/pv_capture/v3_frames       0 フレームから（mix_audio.py と同じ：スタートまでざわめき、そこから声援）
  S04〜S05  artifacts/pv_capture/s04_s05_frames  1180 フレームから（各 2 小節）。設定の矢印（ui_click）・ゲーム開始（ui_start）。
            メニューでは UI 以外の効果音が鳴らないので、ヘリの音はここで置く：出発からローター（近づいてくるので
            ゆっくり大きく）、つかまる瞬間に grip、打ち上がりで jet_ignite とジェット（ゲームの assets/audio/sfx/helicopter）。
            フレームはテイクの report.json（departure_frame / grab_frame / launch_frame）から読む
  S06〜S07  artifacts/pv_capture/s06_s07_frames  1630 フレームから。壁の着地（wall_land）。観客はスタート前のざわめき。
            S07 の問題の切り替え（ui_click として記録）はシャッターの代わりの「カチッ」（helicopter/belt_click）にする
"""
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mix_audio import FFMPEG, ROOT, SFX, cue_table  # noqa: E402

FPS = 60.0
V3_FRAMES = 1180
SEG_A = V3_FRAMES                 # S04 の頭（PV フレーム 1181 の始まり）
SEG_B = V3_FRAMES + 450           # S06 の頭（S04・S05 は 2 小節ずつ）
TOTAL = V3_FRAMES + 900
CROWD_FADE = 0.8
MASTER_DB = 4.0
WALL_LAND_TRIM_DB = -3.0          # S06 は 1 拍ごとに 8 回続けて着地するので、1 回のときより少し下げる
SHUTTER_DB = -4.0
HELI = SFX / "helicopter"
# テイク s04_s05 のフレーム（1 = S04 の頭）
S07_SWITCHES = [226, 268, 310, 353, 395]   # テイク s06_s07 のフレーム（bf(8 + 0, 1.5, 3, 4.5, 6)）


def t_of(frame: float) -> float:
    return (frame - 1) / FPS


def main() -> None:
    out = Path(sys.argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    table, beds = cue_table()
    inputs, filters, labels, missing = [], [], [], []

    def add_input(path: Path) -> int:
        inputs.extend(["-i", str(path)])
        return len(inputs) // 2 - 1

    def place(path: Path, at: float, db: float, label: str) -> None:
        if not path.exists():
            missing.append(str(path.relative_to(ROOT)))
            return
        i = add_input(path)
        ms = max(int(round(at * 1000)), 0)
        filters.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,volume={db}dB,adelay={ms}|{ms}[{label}]")
        labels.append(f"[{label}]")

    def bed(path: Path, start: float, end: float, db: float, label: str, fade_in: float = 0.0, fade_out: float = 0.0) -> None:
        if not path.exists():
            missing.append(str(path.relative_to(ROOT)))
            return
        i = add_input(path)
        length = end - start
        chain = (f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,aloop=loop=-1:size=2147483647,"
                 f"atrim=0:{length:.3f},volume={db}dB")
        if fade_in > 0:
            chain += f",afade=t=in:st=0:d={fade_in}"
        if fade_out > 0:
            chain += f",afade=t=out:st={max(length - fade_out, 0):.3f}:d={fade_out}"
        ms = int(round(start * 1000))
        chain += f",adelay={ms}|{ms}[{label}]"
        filters.append(chain)
        labels.append(f"[{label}]")

    def cues_of(cap: str) -> list:
        return json.loads((ROOT / "artifacts/pv_capture" / cap / "cues.json").read_text(encoding="utf-8"))

    # S01〜S03（mix_audio.py と同じ）
    skip_v3 = {"countdown_go", "countdown_beep", "countdown_rumble", "ui_click", "ui_start"}
    report = json.loads((ROOT / "artifacts/pv_capture/v3_frames/report.json").read_text(encoding="utf-8"))
    race_t = (report.get("plan", {}).get("frames", {}).get("race", 507) - 1) / FPS
    for k, c in enumerate(cues_of("v3_frames")):
        if c["cue"] in skip_v3 or c["cue"] not in table:
            continue
        path, db = table[c["cue"]]
        place(path, c["t"], db, f"a{k}")
    v3_end = V3_FRAMES / FPS
    if "murmur" in beds:
        bed(beds["murmur"][0], 0.0, race_t + CROWD_FADE, beds["murmur"][1], "v3_murmur", fade_out=CROWD_FADE)
    if "race" in beds:
        bed(beds["race"][0], race_t, v3_end, beds["race"][1], "v3_race", fade_in=CROWD_FADE, fade_out=0.25)

    # S04〜S05
    a0 = SEG_A / FPS
    for k, c in enumerate(cues_of("s04_s05_frames")):
        if c["cue"] not in ("ui_click", "ui_start") or c["cue"] not in table:
            continue
        path, db = table[c["cue"]]
        place(path, a0 + c["t"], db, f"b{k}")
    take = json.loads((ROOT / "artifacts/pv_capture/s04_s05_frames/report.json").read_text(encoding="utf-8"))
    depart = int(take["events"]["departure_frame"])
    GRAB, LAUNCH = int(take["grab_frame"]), int(take["launch_frame"])
    bed(HELI / "rotor_loop.ogg", a0 + t_of(depart), a0 + t_of(LAUNCH) + 0.25, -9.0, "rotor", fade_in=0.6, fade_out=0.25)
    place(HELI / "grip.ogg", a0 + t_of(GRAB), -4.0, "grip")
    place(HELI / "jet_ignite.ogg", a0 + t_of(LAUNCH), -2.0, "jet_ignite")
    bed(HELI / "jet_loop.ogg", a0 + t_of(LAUNCH), SEG_B / FPS + 0.05, -6.0, "jet", fade_in=0.05, fade_out=0.2)

    # S06〜S07
    b0 = SEG_B / FPS
    s06_cues = cues_of("s06_s07_frames")
    if "wall_land" in table:
        path, db = table["wall_land"]
        # 3 問目の壁は撮り始めのフレームに着地する（その更新は撮影の記録より前なので cues.json に入らない）
        if not any(c["cue"] == "wall_land" and c["frame"] <= 2 for c in s06_cues):
            place(path, b0, db + WALL_LAND_TRIM_DB, "c_first")
        for k, c in enumerate(s06_cues):
            if c["cue"] == "wall_land":
                place(path, b0 + c["t"], db + WALL_LAND_TRIM_DB, f"c{k}")
    for k, f in enumerate(S07_SWITCHES):
        place(HELI / "belt_click.ogg", b0 + t_of(f), SHUTTER_DB, f"shutter{k}")
        if "ui_click" in table:
            place(table["ui_click"][0], b0 + t_of(f) + 0.045, table["ui_click"][1] - 6.0, f"shutter_b{k}")
    if "murmur" in beds:
        bed(beds["murmur"][0], b0, TOTAL / FPS, beds["murmur"][1], "s06_murmur", fade_in=0.15)

    duration = TOTAL / FPS
    filters.append("".join(labels) + f"amix=inputs={len(labels)}:normalize=0:dropout_transition=0,"
                   f"volume={MASTER_DB}dB,alimiter=limit=0.89,atrim=0:{duration:.4f}[mix]")
    cmd = [FFMPEG, "-y", "-v", "error", *inputs, "-filter_complex", ";".join(filters), "-map", "[mix]",
           "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", str(out)]
    subprocess.run(cmd, check=True)
    print(json.dumps({"out": str(out), "duration": round(duration, 3), "inputs": len(labels),
                      "missing": sorted(set(missing))}, ensure_ascii=False))


if __name__ == "__main__":
    main()

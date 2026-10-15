"""PV 撮影で鳴った効果音（cues.json）を、ゲームと同じファイル・同じ音量で同じ時刻に並べ、観客の環境音を敷いた音声を作る。

    python tools/pv/mix_audio.py artifacts/pv_capture/v3_sub4 docs/pv/previz/v3/PV_S01-S03_v3_audio.wav
cues.json: [{"t": 秒, "cue": 名前}]（tests/pv_capture/pv_v3_runtime.gd が書く）。report.json の plan.frames.race で
スタートの時刻を取り、それまでは観客のざわめき、そこからは声援のループを敷く（ゲームの AudioManager と同じ切り替え）。
キュー → ファイル・音量は scripts/autoload/audio_manager.gd の SFX_CUES / CROWD_AMBIENCES から読む。
効果音ラボ・観客の素材は git に入っていない（assets/audio/sfx/se_lab, crowd）。無いファイルは飛ばして知らせる。
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SFX = ROOT / "assets" / "audio" / "sfx"
FFMPEG = "C:/ffmpeg/bin/ffmpeg.exe"
FPS = 60.0
# PV では使わないキュー（スタートの合図の音はカウントダウンの壁が無いので鳴らさない）
SKIP = {"countdown_go", "countdown_beep", "countdown_rumble", "ui_click", "ui_start"}
CROWD_FADE = 0.8
MASTER_DB = 4.0


def cue_table() -> dict:
    src = (ROOT / "scripts" / "autoload" / "audio_manager.gd").read_text(encoding="utf-8")
    table = {}
    for m in re.finditer(r'&"(\w+)": \{"files": \["([^"]+)"[^\]]*\], "volume_db": (-?[\d.]+)', src):
        table[m.group(1)] = (SFX / m.group(2), float(m.group(3)))
    beds = {}
    for m in re.finditer(r'CROWD_(\w+): \{"path": "res://assets/audio/sfx/([^"]+)", "volume_db": (-?[\d.]+)\}', src):
        beds[m.group(1).lower()] = (SFX / m.group(2), float(m.group(3)))
    return table, beds


def main() -> None:
    cap, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.parent.mkdir(parents=True, exist_ok=True)
    cues = json.loads((cap / "cues.json").read_text(encoding="utf-8"))
    report = json.loads((cap / "report.json").read_text(encoding="utf-8"))
    frames = report.get("plan", {}).get("frames", {})
    race_t = (frames.get("race", 507) - 1) / FPS
    duration = int(sys.argv[3]) / FPS if len(sys.argv) > 3 else 1180 / FPS
    table, beds = cue_table()
    inputs, filters, labels, missing = [], [], [], []

    def add_input(path: Path) -> int:
        inputs.extend(["-i", str(path)])
        return len(inputs) // 2 - 1

    for k, c in enumerate(cues):
        name = c["cue"]
        if name in SKIP or name not in table:
            continue
        path, db = table[name]
        if not path.exists():
            missing.append(str(path.relative_to(ROOT)))
            continue
        i = add_input(path)
        ms = max(int(round(c["t"] * 1000)), 0)
        filters.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,volume={db}dB,adelay={ms}|{ms}[e{k}]")
        labels.append(f"[e{k}]")
    for key, start, end in (("murmur", 0.0, race_t + CROWD_FADE), ("race", race_t, duration)):
        if key not in beds:
            continue
        path, db = beds[key]
        if not path.exists():
            missing.append(str(path.relative_to(ROOT)))
            continue
        i = add_input(path)
        length = end - start
        fade_in = 0.0 if start == 0.0 else CROWD_FADE
        fade_out_at = max(length - CROWD_FADE, 0.0)
        ms = int(round(start * 1000))
        chain = (f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,aloop=loop=-1:size=2147483647,"
                 f"atrim=0:{length:.3f},volume={db}dB")
        if fade_in > 0:
            chain += f",afade=t=in:st=0:d={fade_in}"
        if key == "murmur":
            chain += f",afade=t=out:st={fade_out_at:.3f}:d={CROWD_FADE}"
        chain += f",adelay={ms}|{ms}[bed_{key}]"
        filters.append(chain)
        labels.append(f"[bed_{key}]")
    if not labels:
        raise SystemExit("no audio to mix")
    filters.append("".join(labels) + f"amix=inputs={len(labels)}:normalize=0:dropout_transition=0,"
                   f"volume={MASTER_DB}dB,alimiter=limit=0.95,atrim=0:{duration:.4f}[mix]")
    cmd = [FFMPEG, "-y", "-v", "error", *inputs, "-filter_complex", ";".join(filters), "-map", "[mix]",
           "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", str(out)]
    subprocess.run(cmd, check=True)
    used = sorted({c["cue"] for c in cues if c["cue"] not in SKIP})
    print(json.dumps({"out": str(out), "duration": round(duration, 3), "cues_used": used, "race_t": round(race_t, 3),
                      "missing": sorted(set(missing))}, ensure_ascii=False))


if __name__ == "__main__":
    main()

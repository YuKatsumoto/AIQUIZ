"""Measure before/after live bus captures and export an unnormalized A/B preview.

Run after injecting probe_audio_balance.gd into the real game for each label.
The shared capture ring contains four stereo pairs in 512-frame blocks on the
test machine's WASAPI 7.1 device; use the runtime metadata to extract the front.
"""
import json
import subprocess
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2] / "artifacts/audio_balance"


def read_capture(folder, record, pairs):
    raw = folder / (record["phase"] + ".f32")
    samples = np.fromfile(raw, dtype="<f4").reshape(-1, 2)
    stride = pairs * 512
    samples = samples[:len(samples) // stride * stride]
    return samples.reshape(-1, pairs, 512, 2)[:, 0].reshape(-1, 2)


def db(value):
    return round(float(20 * np.log10(max(value, 1e-10))), 2)


def measure(samples, sample_rate):
    energy = np.mean(samples * samples, axis=1, dtype=np.float64)
    window = min(len(samples), int(sample_rate * .08))
    summed = np.concatenate(([0.], np.cumsum(energy)))
    strongest = np.max((summed[window:] - summed[:-window]) / window)
    return {"seconds": round(len(samples) / sample_rate, 3),
            "peak_dbfs": db(np.max(np.abs(samples))),
            "rms_dbfs": db(np.sqrt(np.mean(energy))),
            "active80_dbfs": db(np.sqrt(strongest)),
            "clipped_samples": int(np.sum(np.abs(samples) >= 1.0))}


def export(samples, sr, path):
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(sr),
                    "-ac", "2", "-i", "pipe:0", "-ar", "48000", str(path)],
                   input=samples.astype("<f4").tobytes(), check=True)


def main():
    results = {}
    preview = []
    for label in ("before", "after"):
        folder = ROOT / label
        runtime = json.loads((folder / "runtime.json").read_text(encoding="utf8"))
        levels, clips = {}, {}
        for record in runtime["snapshots"]:
            samples = read_capture(folder, record, int(runtime["capture_stereo_pairs"]))
            sr = int(record["sample_rate"])
            levels[record["phase"]] = measure(samples, sr)
            if record["phase"].endswith("__Master"):
                clips[record["phase"]] = samples
                export(samples, sr, folder / (record["phase"] + ".wav"))
        (folder / "levels.json").write_text(json.dumps(levels, indent=2), encoding="utf8")
        results[label] = levels
        # Each block: push, jump landing, helicopter landing, wall impact.
        for cue in ("push_kick", "jump_land", "heli_land", "wall_crash"):
            preview.append(clips[cue + "__Master"])
        preview.append(np.zeros((sr, 2), dtype=np.float32))
    export(np.concatenate(preview), sr, ROOT / "balance_before_after.mp3")
    differences = {}
    for phase in results["before"]:
        differences[phase] = round(results["after"][phase]["active80_dbfs"] -
                                   results["before"][phase]["active80_dbfs"], 2)
    report = {"before": results["before"], "after": results["after"],
              "active80_change_db": differences,
              "preview_order": ["before", "after"],
              "preview_cues": ["push_kick", "jump_land", "heli_land", "wall_crash"]}
    (ROOT / "comparison.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    # SFX is an intermediate mix; only the final Master must stay below full scale.
    assert not any(v["clipped_samples"] for k, v in results["after"].items()
                   if k.endswith("__Master")), "Final output clipped."
    for cue in ("push_kick", "jump_land", "heli_land", "ui_click", "wall_crash", "helicopters", "overlap"):
        key = cue + "__Master"
        print(cue, "before", results["before"][key], "after", results["after"][key])


if __name__ == "__main__":
    main()

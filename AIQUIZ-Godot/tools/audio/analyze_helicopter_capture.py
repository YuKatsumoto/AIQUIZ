"""Export and measure the actual runtime captures (numpy and ffmpeg required).

Run after tests/helicopter_audio_bootstrap.gd. AudioEffectCapture shares its
buffer among surround-channel instances. On this WASAPI 7.1 device it records
four stereo pairs in 512-frame blocks. Our MIX_TARGET_STEREO players use pair 0.
Use --block-frames if the audio driver's processing block size differs.
"""
import argparse
from pathlib import Path
import json
import subprocess
import numpy as np


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--block-frames", type=int, default=512)
    parser.add_argument("--folder", default="artifacts/helicopter_audio")
    args = parser.parse_args()
    folder = Path(__file__).resolve().parents[2] / args.folder
    report = json.loads((folder / "runtime.json").read_text(encoding="utf8"))
    pairs = int(report["capture_stereo_pairs"])
    levels = []
    for record in report["snapshots"]:
        raw = folder / (record["phase"] + ".f32")
        samples = np.fromfile(raw, dtype="<f4").reshape(-1, 2)
        if pairs > 1:
            stride = pairs * args.block_frames
            samples = samples[:len(samples) // stride * stride]
            samples = samples.reshape(-1, pairs, args.block_frames, 2)[:, 0].reshape(-1, 2)
        peak = float(np.max(np.abs(samples))) if len(samples) else 0.0
        rms = float(np.sqrt(np.mean(samples * samples))) if len(samples) else 0.0
        sr = int(record["sample_rate"])
        metrics = {"file": raw.with_suffix(".wav").name, "seconds": round(len(samples) / sr, 2),
                   "peak_dbfs": round(20 * np.log10(max(peak, 1e-8)), 2),
                   "rms_dbfs": round(20 * np.log10(max(rms, 1e-8)), 2),
                   "clipped_samples": int(np.sum(np.abs(samples) >= 1))}
        levels.append(metrics)
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(sr), "-ac", "2",
                        "-i", "pipe:0", "-ar", "48000", str(raw.with_suffix(".wav"))],
                       input=samples.astype("<f4").tobytes(), check=True)
        print(json.dumps(metrics))
    (folder / "capture_levels.json").write_text(json.dumps(levels, indent=2), encoding="utf8")
    if any(x["clipped_samples"] for x in levels):
        raise SystemExit("Captured helicopter audio clipped.")


if __name__ == "__main__":
    main()

"""Find a seamless loop in a generated BGM take and render the looping Ogg (docs/bgm_renewal.md).

The loops follow the delivered BGM: the first pass plays from the head of the file, then
Godot jumps from the end of the file back to loop_offset. The last 30 ms of the file fade
(equal power) from the audio that leads up to the cut into the audio that leads up to
loop_offset, so the jump continues the original take. Cuts sit 40 ms before a beat so they
miss the attack.

  python tools/audio/make_bgm_loop.py analyze <take.mp3> --bpm 112 [--bar 4] [--min-loop 60]
  python tools/audio/make_bgm_loop.py render <take.mp3> <out.ogg> --start-beat 20 --end-beat 180 --bpm 112

Needs ffmpeg on PATH and numpy only. analyze prints the beat grid and the best (start, end)
beat pairs: chord (beat chroma), timbre (band levels), rhythm (onset pattern) and level are
compared over the bars before and after both cut points. render repeats the beat tracking so
the beat numbers mean the same thing, aligns the end cut to the start cut by the onset
envelope, normalises the file to -16 LUFS and prints the .import values.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

import numpy as np

RATE = 48000
HOP = 480  # 10 ms frames
N_FFT = 4096
PRE_CUT = 0.040  # cut this long before the beat
XFADE = 0.030
HEAD_FADE = 0.003
TARGET_LUFS = -16.0


def decode(path: str) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(RATE), "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def features(mono: np.ndarray) -> dict:
    """Per-frame onset flux, 24 log band levels (dB) and chroma."""
    window = np.hanning(N_FFT)
    padded = np.concatenate([np.zeros(N_FFT // 2), mono, np.zeros(N_FFT)])
    n_frames = (len(mono)) // HOP
    freqs = np.fft.rfftfreq(N_FFT, 1.0 / RATE)
    edges = np.geomspace(40.0, 16000.0, 25)
    band_of = np.digitize(freqs, edges) - 1
    chroma_mask = (freqs >= 60.0) & (freqs <= 5000.0)
    pitch_class = np.zeros_like(freqs, dtype=int)
    pitch_class[chroma_mask] = np.round(12.0 * np.log2(freqs[chroma_mask] / 440.0) + 69.0).astype(int) % 12
    flux = np.zeros(n_frames)
    bands = np.zeros((n_frames, 24))
    chroma = np.zeros((n_frames, 12))
    prev = None
    for start in range(0, n_frames, 1024):
        idx = np.arange(start, min(n_frames, start + 1024))
        frames = np.stack([padded[i * HOP:i * HOP + N_FFT] for i in idx]) * window
        mag = np.abs(np.fft.rfft(frames, axis=1))
        power = mag ** 2
        for b in range(24):
            sel = band_of == b
            bands[idx, b] = 10.0 * np.log10(power[:, sel].sum(axis=1) + 1e-10)
        for pc in range(12):
            sel = chroma_mask & (pitch_class == pc)
            chroma[idx, pc] = mag[:, sel].sum(axis=1)
        logmag = np.log1p(100.0 * mag)
        if prev is None:
            prev = logmag[:1]
        diff = np.diff(np.vstack([prev, logmag]), axis=0)
        flux[idx] = np.maximum(diff, 0.0).sum(axis=1)
        prev = logmag[-1:]
    chroma /= np.linalg.norm(chroma, axis=1, keepdims=True) + 1e-9
    flux = flux - np.convolve(flux, np.ones(41) / 41.0, mode="same")
    return {"flux": np.maximum(flux, 0.0), "bands": bands, "chroma": chroma}


def track_beats(flux: np.ndarray, bpm_hint: float) -> tuple[float, float]:
    """A constant beat grid (period and phase in frames) that best lines up with the onsets."""
    fps = RATE / HOP
    p0 = 60.0 * fps / bpm_hint
    # Coarse: autocorrelation near the hinted period.
    x = flux - flux.mean()
    lags = np.arange(int(p0 * 0.9), int(p0 * 1.1) + 1)
    ac = np.array([np.dot(x[:-lag], x[lag:]) for lag in lags])
    period = float(lags[int(np.argmax(ac))])
    # Fine: comb over the whole take (period to 1/2000, phase to 1/4 frame).
    t = np.arange(len(flux))
    best = (-1.0, period, 0.0)
    for p in np.linspace(period * 0.985, period * 1.015, 301):
        n = int((len(flux) - 2) / p)
        for phase in np.arange(0.0, p, 0.25):
            pos = phase + np.arange(n) * p
            score = np.interp(pos, t, flux).mean()
            if score > best[0]:
                best = (score, p, phase)
    return best[1], best[2]


def beat_frames(period: float, phase: float, n_frames: int) -> np.ndarray:
    return phase + np.arange(int((n_frames - 1 - phase) / period) + 1) * period


def beat_features(feat: dict, beats: np.ndarray) -> dict:
    n = len(beats) - 1
    # Chroma of each quarter of the beat, so the melody's movement counts, not only the chord.
    chroma = np.zeros((n, 48))
    bands = np.zeros((n, 24))
    rhythm = np.zeros((n, 8))
    level = np.zeros(n)
    t = np.arange(len(feat["flux"]))
    for i in range(n):
        a, b = int(round(beats[i])), int(round(beats[i + 1]))
        for k in range(4):
            qa = int(round(beats[i] + k * (beats[i + 1] - beats[i]) / 4.0))
            qb = max(qa + 1, int(round(beats[i] + (k + 1) * (beats[i + 1] - beats[i]) / 4.0)))
            q = feat["chroma"][qa:qb].mean(axis=0)
            chroma[i, k * 12:(k + 1) * 12] = q / (np.linalg.norm(q) + 1e-9)
        bands[i] = feat["bands"][a:b].mean(axis=0)
        level[i] = 10.0 * np.log10(np.mean((10.0 ** (feat["bands"][a:b] / 10.0)).sum(axis=1)) + 1e-10)
        rhythm[i] = np.log1p(np.interp(beats[i] + np.arange(8) * (beats[i + 1] - beats[i]) / 8.0, t, feat["flux"]))
    # A loop keeps one key, so the raw chroma of any two beats looks alike; compare what each beat
    # adds to the take's average instead.
    chroma /= np.linalg.norm(chroma, axis=1, keepdims=True) + 1e-9
    chroma -= chroma.mean(axis=0)
    chroma /= np.linalg.norm(chroma, axis=1, keepdims=True) + 1e-9
    return {"chroma": chroma, "bands": bands, "rhythm": rhythm, "level": level}


def compare(bf: dict, s: int, e: int, before: int, after: int) -> dict:
    """How alike the music is around beat s and beat e (before/after in beats)."""
    a = np.arange(s - before, s + after)
    b = np.arange(e - before, e + after)
    chord = float(np.mean(np.sum(bf["chroma"][a] * bf["chroma"][b], axis=1)))
    timbre = float(np.mean(np.abs((bf["bands"][a] - bf["level"][a, None]) - (bf["bands"][b] - bf["level"][b, None]))))
    ra = bf["rhythm"][a].ravel()
    rb = bf["rhythm"][b].ravel()
    ra = ra - ra.mean()
    rb = rb - rb.mean()
    rhythm = float(np.dot(ra, rb) / (np.linalg.norm(ra) * np.linalg.norm(rb) + 1e-9))
    level = float(np.mean(bf["level"][b]) - np.mean(bf["level"][a]))
    score = chord + 0.5 * rhythm - 0.15 * timbre - 0.1 * abs(level)
    return {"chord": chord, "timbre": timbre, "rhythm": rhythm, "level_db": level, "score": score}


def analyse(path: str, bpm: float) -> tuple[np.ndarray, dict, np.ndarray, float]:
    audio = decode(path)
    feat = features(audio.mean(axis=1))
    period, phase = track_beats(feat["flux"], bpm)
    beats = beat_frames(period, phase, len(feat["flux"]))
    return audio, feat, beats, period


def steady_end(bf: dict, tail_db: float = 3.0) -> int:
    """Last beat before the ending: the level stays within tail_db of the median."""
    median = np.median(bf["level"])
    ok = np.where(bf["level"] > median - tail_db)[0]
    return int(ok[-1])


def cmd_analyze(args: argparse.Namespace) -> None:
    audio, feat, beats, period = analyse(args.take, args.bpm)
    fps = RATE / HOP
    bpm = 60.0 * fps / period
    bf = beat_features(feat, beats)
    n = len(bf["level"])
    # Drift check: how far the onsets sit from the constant grid, per 30 s.
    t = np.arange(len(feat["flux"]))
    drift = []
    for seg in range(0, int(len(audio) / RATE), 30):
        sel = (beats / fps >= seg) & (beats / fps < seg + 30)
        if sel.sum() < 8:
            continue
        offs = np.linspace(-6, 6, 49)
        sc = [np.interp(beats[sel] + o, t, feat["flux"]).mean() for o in offs]
        drift.append((seg, round(float(offs[int(np.argmax(sc))]) * 1000.0 / fps, 1)))
    end_beat = steady_end(bf)
    print(f"take {args.take}: {len(audio) / RATE:.3f} s, {bpm:.3f} BPM (beat {period / fps:.5f} s), first beat {beats[0] / fps:.3f} s, {n} beats")
    print(f"grid drift per 30 s (ms, + = onsets late): {drift}")
    print(f"steady until beat {end_beat} ({beats[end_beat] / fps:.2f} s)")
    level = bf["level"]
    print("level per 8 beats (dB): " + " ".join(f"{i}:{np.mean(level[i:i + 8]):.1f}" for i in range(0, n, 8)))
    # Where the take repeats itself: mean chord match of every beat with the beat `lag` later.
    repeats = []
    for lag in range(16, end_beat - 16, args.bar * 2):
        i = np.arange(0, end_beat - lag)
        repeats.append((lag, float(np.mean(np.sum(bf["chroma"][i] * bf["chroma"][i + lag], axis=1)))))
    repeats.sort(key=lambda r: -r[1])
    print("repeat lags (beats: chord match): " + " ".join(f"{lag}:{c:.3f}" for lag, c in repeats[:10]))
    before, after = args.context, args.context // 2
    min_len = int(np.ceil(args.min_loop / (period / fps)))
    rows = []
    for s in range(max(before, args.bar), end_beat - min_len):
        for e in range(s + min_len, end_beat - after + 1):
            if (e - s) % (args.bar * 2):
                continue
            c = compare(bf, s, e, before, after)
            rows.append((c["score"], s, e, c))
    rows.sort(key=lambda r: -r[0])
    print(f"best cuts (context {before} beats before / {after} after, loop >= {args.min_loop:.0f} s, multiple of {args.bar * 2} beats):")
    shown = []
    for score, s, e, c in rows:
        if any(abs(s - ss) < args.bar and abs(e - ee) < args.bar for ss, ee in shown):
            continue
        shown.append((s, e))
        print(f"  start beat {s:4d} ({beats[s] / fps:7.3f} s) -> end beat {e:4d} ({beats[e] / fps:7.3f} s), loop {e - s} beats "
              f"{(beats[e] - beats[s]) / fps:6.2f} s | chord {c['chord']:.3f} rhythm {c['rhythm']:.3f} timbre {c['timbre']:.2f} level {c['level_db']:+.2f} | {score:.3f}")
        if len(shown) >= args.top:
            break


def envelope(x: np.ndarray, width: int = 48) -> np.ndarray:
    m = np.abs(x.mean(axis=1))
    return np.convolve(m, np.ones(width) / width, mode="same")


def loudness(path: str) -> dict:
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    summary = out[out.rfind("Summary:"):]
    i = float(re.search(r"I:\s+(-?[\d.]+) LUFS", summary).group(1))
    peak = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", summary).group(1))
    return {"lufs": i, "true_peak_dbfs": peak}


def write_ogg(samples: np.ndarray, path: str) -> None:
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "6", path],
        input=samples.astype(np.float32).tobytes(), check=True,
    )


def cmd_render(args: argparse.Namespace) -> None:
    audio, feat, beats, period = analyse(args.take, args.bpm)
    fps = RATE / HOP
    # Whole milliseconds, so loop_offset in the .import lands on the exact sample.
    start = int(round((beats[args.start_beat] / fps - PRE_CUT) * 1000.0)) * (RATE // 1000)
    end = int(round((beats[args.end_beat] / fps - PRE_CUT) * RATE))
    # Line the end cut up with the start cut by the onset envelope over the 0.8 s before each.
    env = envelope(audio)
    span = int(0.8 * RATE)
    ref = env[start - span:start]
    ref = ref - ref.mean()
    best = (-np.inf, 0)
    for lag in range(-int(0.03 * RATE), int(0.03 * RATE) + 1, 4):
        seg = env[end + lag - span:end + lag]
        seg = seg - seg.mean()
        c = float(np.dot(ref, seg) / (np.linalg.norm(ref) * np.linalg.norm(seg) + 1e-12))
        if c > best[0]:
            best = (c, lag)
    end += best[1]
    xf = int(XFADE * RATE)
    out = audio[:end].copy()
    u = np.linspace(0.0, 1.0, xf)[:, None]
    out[end - xf:end] = audio[end - xf:end] * np.cos(u * np.pi / 2.0) + audio[start - xf:start] * np.sin(u * np.pi / 2.0)
    head = int(HEAD_FADE * RATE)
    out[:head] *= np.linspace(0.0, 1.0, head)[:, None]
    # Seam step against the natural step at the same spot of the take.
    seam_step = float(np.max(np.abs(audio[start] - out[end - 1])))
    natural_step = float(np.max(np.abs(audio[start] - audio[start - 1])))
    write_ogg(out, args.out)
    gain = TARGET_LUFS - loudness(args.out)["lufs"]
    out *= 10.0 ** (gain / 20.0)
    write_ogg(out, args.out)
    final = loudness(args.out)
    bpm = 60.0 * fps / period
    report = {
        "take": args.take, "out": args.out, "bpm": round(bpm, 3),
        "start_beat": args.start_beat, "end_beat": args.end_beat,
        "loop_offset": round(start / RATE, 3), "end_seconds": round(end / RATE, 6), "length_samples": end,
        "loop_seconds": round((end - start) / RATE, 3), "end_align_ms": round(best[1] * 1000.0 / RATE, 2), "end_align_corr": round(best[0], 3),
        "seam_step": round(seam_step, 4), "natural_step": round(natural_step, 4), "gain_db": round(gain, 2), **final,
        "import": {"loop": True, "loop_offset": round(start / RATE, 3), "bpm": round(bpm, 2), "beat_count": 0, "bar_beats": args.bar},
    }
    print(json.dumps(report, indent=1, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("analyze")
    a.add_argument("take")
    a.add_argument("--bpm", type=float, required=True, help="tempo hint (the prompt's BPM)")
    a.add_argument("--bar", type=int, default=4, help="beats per bar")
    a.add_argument("--min-loop", type=float, default=60.0, help="shortest loop in seconds")
    a.add_argument("--context", type=int, default=16, help="beats compared before the cut (half as many after)")
    a.add_argument("--top", type=int, default=12)
    r = sub.add_parser("render")
    r.add_argument("take")
    r.add_argument("out")
    r.add_argument("--bpm", type=float, required=True)
    r.add_argument("--bar", type=int, default=4)
    r.add_argument("--start-beat", type=int, required=True)
    r.add_argument("--end-beat", type=int, required=True)
    args = parser.parse_args()
    {"analyze": cmd_analyze, "render": cmd_render}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())

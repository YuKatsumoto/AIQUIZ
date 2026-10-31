"""Lasso effects for the elimination presentation (EliminationLassoDirector, docs/elimination_lasso.md).

Hatena twirls the lasso over her head (one swish per turn, played faster and higher as it speeds up),
throws it (a long swish and the rope running out through the glove), and cinches it around both souls
(a short zip, the rope creaking tight and a soft thump). All synthesized here: no external samples.

Run from any directory with Python/numpy and ffmpeg. Writes assets/audio/sfx/lasso/*.ogg and
artifacts/elimination_lasso/audio.json. After a rebuild, let the Godot editor rescan the files.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import wave
import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parents[2]
RNG = np.random.default_rng(4207)


def bandpass_sweep(n, centers, q):
    """White noise through a resonant band-pass whose centre moves per sample (state-variable filter)."""
    x = RNG.standard_normal(n)
    y = np.zeros(n)
    low = band = 0.0
    damp = 1.0 / q
    for i in range(n):
        f = 2.0 * np.sin(np.pi * min(centers[i], SR * 0.22) / SR)
        high = x[i] - low - damp * band
        band += f * high
        low += f * band
        y[i] = band
    return y / max(1e-9, np.sqrt(np.mean(y * y)))


def highpass(y, hz):
    spec = np.fft.rfft(y)
    f = np.fft.rfftfreq(len(y), 1 / SR)
    spec *= 1.0 / (1.0 + (hz / np.maximum(f, 1.0)) ** 4)
    return np.fft.irfft(spec, len(y))


def write(rel, y, peak=-3.0):
    y = y - np.mean(y)
    k = min(int(.002 * SR), len(y) // 4)
    y[:k] *= np.linspace(0, 1, k)
    k = min(int(.03 * SR), len(y) // 4)
    y[-k:] *= np.linspace(1, 0, k)
    y *= 10 ** (peak / 20) / np.max(np.abs(y))
    destination = ROOT / 'assets/audio/sfx' / rel
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / 'source.wav'
        with wave.open(str(wav), 'wb') as f:
            f.setparams((1, 2, SR, 0, 'NONE', 'not compressed'))
            f.writeframes((y * 32767).astype('<i2').tobytes())
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-c:a', 'libvorbis', '-q:a', '7', str(destination)], check=True)
    return {'path': str(destination.relative_to(ROOT)), 'seconds': round(len(y) / SR, 3), 'peak_dbfs': peak,
            'rms_dbfs': round(float(20 * np.log10(np.sqrt(np.mean(y * y)))), 2)}


def whirl():
    """One turn of the loop over the head: ヒュン. The swish rises as the rope comes round and falls away."""
    n = int(.44 * SR)
    t = np.arange(n) / SR
    p = t / t[-1]
    shape = np.sin(np.pi * np.clip(p * 1.08, 0, 1)) ** 2.4
    centers = 520 + 1500 * np.sin(np.pi * np.clip(p * 1.05, 0, 1)) ** 1.6
    air = bandpass_sweep(n, centers, 3.2)
    phase = 2 * np.pi * np.cumsum(centers * 1.02) / SR
    whistle = np.sin(phase) * 0.16 + np.sin(phase * 2.01) * 0.05
    return (air * 0.9 + whistle) * shape


def throw():
    """The throw: a long falling swish, then the rope running out through the glove (a dry rattle)."""
    n = int(.82 * SR)
    t = np.arange(n) / SR
    p = t / t[-1]
    centers = 1900 * np.exp(-p * 1.9) + 420
    swish = bandpass_sweep(n, centers, 2.6) * (1 - np.exp(-t / .03)) * np.exp(-t / .22)
    rattle_env = np.clip((t - .1) / .08, 0, 1) * np.exp(-np.maximum(t - .18, 0) / .26)
    rate = 58 - 26 * p
    grain = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * np.cumsum(rate) / SR))
    rattle = highpass(RNG.standard_normal(n), 1500) * grain * rattle_env
    rattle /= max(1e-9, np.sqrt(np.mean(rattle * rattle)))
    return swish * 1.0 + rattle * 0.32


def cinch():
    """The loop pulled tight: a short zip, the rope creaking (ギュッ) and a soft thump on the bodies."""
    n = int(.4 * SR)
    t = np.arange(n) / SR
    zip_env = np.clip(t / .006, 0, 1) * np.exp(-t / .03)
    zip_noise = bandpass_sweep(n, 3200 + 2600 * np.exp(-t / .04), 2.0) * zip_env
    creak_t = np.maximum(t - .028, 0)
    creak_env = np.clip(creak_t / .012, 0, 1) * np.exp(-creak_t / .085) * (t > .028)
    freq = 360 + 300 * (1 - np.exp(-creak_t / .05))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    # Stick-slip friction: a buzzy pulse train with a little jitter, softened by a resonance.
    saw = 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    creak = saw * (0.75 + 0.25 * RNG.standard_normal(n).clip(-1, 1))
    creak = bandpass_sweep(n, freq * 2.2, 5.0) * 0.35 + creak * 0.65
    creak *= creak_env
    thump_t = np.maximum(t - .02, 0)
    thump = np.sin(2 * np.pi * (140 * thump_t - 70 * thump_t * thump_t)) * np.exp(-thump_t / .05) * (t > .02)
    return zip_noise * 0.55 + creak * 0.9 + thump * 0.8


def main():
    report = [
        write('lasso/lasso_whirl.ogg', whirl(), -4.0),
        write('lasso/lasso_throw.ogg', throw(), -3.0),
        write('lasso/lasso_cinch.ogg', cinch(), -3.0),
    ]
    out = ROOT / 'artifacts/elimination_lasso/audio.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding='utf8')
    for row in report:
        print(row)


if __name__ == '__main__':
    main()

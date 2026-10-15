# Generates assets/audio/sfx/game/score_drum_roll.ogg (docs/sound_effects.md).
# python -I tools/audio/make_score_drum_roll.py <out.wav> 2.10, then encode with
# ffmpeg -i <out.wav> -c:a libvorbis -q:a 6 -ar 48000 assets/audio/sfx/game/score_drum_roll.ogg
import sys, struct, numpy as np
OUT = sys.argv[1]; LENGTH = float(sys.argv[2])
SR = 48000
rng = np.random.default_rng(7)
def bandpass_noise(n, lo, hi):
    spec = np.fft.rfft(rng.standard_normal(n)); f = np.fft.rfftfreq(n, 1 / SR)
    spec[(f < lo) | (f > hi)] = 0
    y = np.fft.irfft(spec, n); return y / (np.abs(y).max() + 1e-9)
n_total = int((LENGTH + 0.35) * SR)
out = np.zeros((n_total, 2))
wires = bandpass_noise(n_total, 2500, 11000)
t_stroke = 0.0; k = 0
while t_stroke < LENGTH:
    u = t_stroke / LENGTH                       # 0 -> 1 over the climb
    vel = (0.22 + 0.78 * u ** 1.6) * rng.uniform(0.82, 1.0) * (1.0 if k % 2 == 0 else 0.88)  # crescendo, L/R hands
    n = int(0.09 * SR); tt = np.arange(n) / SR
    head = np.sin(2 * np.pi * (195 + rng.uniform(-6, 6)) * tt) * np.exp(-tt / 0.018) * 0.55
    crack = bandpass_noise(n, 900, 7000) * np.exp(-tt / 0.012) * 0.8
    stroke = (head + crack) * vel
    s = int(t_stroke * SR); e = min(n_total, s + n)
    pan = 0.12 if k % 2 == 0 else -0.12
    out[s:e, 0] += stroke[:e - s] * (1 - pan); out[s:e, 1] += stroke[:e - s] * (1 + pan)
    # buzz: strokes get denser as the roll grows (16 -> 30 per second), with human jitter
    rate = 16 + 14 * u
    t_stroke += (1.0 / rate) * rng.uniform(0.9, 1.1); k += 1
# snare wires follow the stroke energy
env = np.convolve(np.abs(out).sum(1), np.ones(480) / 480, mode="same")
out += (wires * env * 0.35)[:, None]
# final accent stroke right at the end, then a quick choke into the hush
s = int(LENGTH * SR); n = int(0.06 * SR); tt = np.arange(n) / SR
acc = (np.sin(2 * np.pi * 190 * tt) * np.exp(-tt / 0.02) * 0.6 + bandpass_noise(n, 900, 8000) * np.exp(-tt / 0.015)) * 1.1
out[s:s + n] += acc[:, None]
cut = s + int(0.05 * SR); out[cut:] = 0
c = int(0.012 * SR); out[cut - c:cut] *= np.linspace(1, 0, c)[:, None]
out = out[:cut]
out /= np.abs(out).max() / 10 ** (-1.5 / 20)
d = out.astype(np.float32); nb = d.size * 4
with open(OUT, "wb") as f:
    f.write(b"RIFF" + struct.pack("<I", 36 + nb) + b"WAVE" + b"fmt " + struct.pack("<IHHIIHH", 16, 3, 2, SR, SR * 8, 8, 32) + b"data" + struct.pack("<I", nb)); f.write(d.tobytes())
print("roll", len(out) / SR, "s, strokes", k)

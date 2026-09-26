"""Crowd sound bed for the goal stand, rendered offline (numpy, deterministic).

Procedural layers (applause, cheer swell, boo, egg splat, throw whoosh) are mixed
with the Higgsfield seed_audio voice lines in source/generated/voice and written as
OGG to assets/audio/sfx/goal_stand/.  Run from the project root:

    python assets/goal_stand/source/synth_crowd_audio.py
"""
import subprocess
import wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
VOICE = HERE / "generated" / "voice"
OUT = HERE.parents[2] / "assets" / "audio" / "sfx" / "goal_stand"
RATE = 32000
rng = np.random.default_rng(0x60A1)


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def onepole_lowpass(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def bandpass(x, low, high):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / RATE)
    shape = np.clip((freqs - low * 0.7) / (low * 0.3 + 1e-6), 0, 1) * np.clip((high * 1.4 - freqs) / (high * 0.4), 0, 1)
    return np.fft.irfft(spec * shape, len(x))


def envelope(t, attack, hold, release):
    total = attack + hold + release
    env = np.clip(t / max(attack, 1e-4), 0, 1)
    env = np.where(t > attack + hold, np.clip(1.0 - (t - attack - hold) / max(release, 1e-4), 0, 1), env)
    return env * (t <= total)


def applause(seconds=2.6, rate_hz=70.0):
    t = t_axis(seconds)
    out = np.zeros_like(t)
    clap_len = int(RATE * 0.018)
    burst = rng.standard_normal(clap_len) * np.exp(-np.linspace(0, 7, clap_len))
    n = rng.poisson(rate_hz * seconds)
    for start in rng.integers(0, len(t) - clap_len, n):
        out[start:start + clap_len] += burst * rng.uniform(0.3, 1.0)
    out = bandpass(out, 700, 4200)
    return out * envelope(t, 0.12, seconds - 0.9, 0.78)


def voices(seconds, base, spread, count, vowel_low, vowel_high, vibrato, glide=0.0):
    """Many detuned sawtooth voices through a vowel band: a crowd shouting one vowel."""
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for _ in range(count):
        f0 = base * rng.uniform(1.0 - spread, 1.0 + spread)
        rate = rng.uniform(4.0, 6.5)
        depth = vibrato * rng.uniform(0.6, 1.4)
        onset = rng.uniform(0.0, 0.35)
        freq = f0 * (1.0 + depth * np.sin(2 * np.pi * rate * t + rng.uniform(0, 6.28))) * (1.0 + glide * t / seconds)
        phase = np.cumsum(freq) / RATE
        saw = 2.0 * (phase % 1.0) - 1.0
        amp = np.clip((t - onset) / 0.25, 0, 1) * rng.uniform(0.5, 1.0)
        out += saw * amp
    out = bandpass(out, vowel_low, vowel_high)
    return out


def cheer(seconds=2.8):
    """Distant "waaah": detuned voices through two vowel formants over applause."""
    t = t_axis(seconds)
    raw = voices(seconds, 300, 0.30, 24, 60, 7000, 0.035, glide=0.10)
    mix = bandpass(raw, 650, 1000) + bandpass(raw, 1100, 1500) * 0.7
    mix = normalize(mix, 1.0) * 0.55
    mix += normalize(bandpass(rng.standard_normal(len(t)), 800, 3000), 1.0) * 0.08
    mix += normalize(applause(seconds, 90), 1.0) * 0.35
    return mix * envelope(t, 0.18, seconds - 1.1, 0.92)


def boo(seconds=2.4):
    t = t_axis(seconds)
    mix = voices(seconds, 125, 0.28, 22, 180, 900, 0.02, glide=-0.08)
    mix += bandpass(rng.standard_normal(len(t)), 200, 700) * 0.15
    return mix * envelope(t, 0.35, seconds - 1.0, 0.65)


def splat():
    t = t_axis(0.42)
    crack = bandpass(rng.standard_normal(len(t)), 2500, 7000) * np.exp(-t * 90.0) * 0.8
    wet = bandpass(rng.standard_normal(len(t)), 250, 1800) * np.exp(-t * 14.0)
    wet *= 1.0 + 0.6 * np.sin(2 * np.pi * 38 * t)
    thump = np.sin(2 * np.pi * (140 - 90 * t) * t) * np.exp(-t * 22.0)
    return crack + wet * 0.9 + thump * 0.7


def whoosh():
    t = t_axis(0.35)
    noise = rng.standard_normal(len(t))
    sweep = np.concatenate([bandpass(chunk, 300 + 900 * k / 6, 900 + 2000 * k / 6)
                            for k, chunk in enumerate(np.array_split(noise, 7))])
    return sweep * np.sin(np.pi * np.clip(t / 0.35, 0, 1)) ** 2


def load_voice(name):
    path = VOICE / name
    if not path.exists():
        return None
    with wave.open(str(path)) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        channels, rate = w.getnchannels(), w.getframerate()
    data = data.reshape(-1, channels).mean(axis=1)
    idx = np.arange(0, len(data), rate / RATE)
    data = np.interp(idx, np.arange(len(data)), data)
    # Trim leading/trailing silence, then place it a little back in the stand.
    loud = np.nonzero(np.abs(data) > 0.02)[0]
    if len(loud):
        data = data[max(0, loud[0] - int(RATE * 0.03)):loud[-1] + int(RATE * 0.12)]
    data = onepole_lowpass(data, 5200.0)
    echo = np.zeros(len(data) + int(RATE * 0.16))
    echo[:len(data)] += data
    echo[int(RATE * 0.09):int(RATE * 0.09) + len(data)] += data * 0.22
    echo[int(RATE * 0.16):int(RATE * 0.16) + len(data)] += data * 0.10
    return echo


def place(bed, clip, at, gain):
    start = int(RATE * at)
    end = min(len(bed), start + len(clip))
    bed[start:end] += clip[:end - start] * gain
    return bed


def normalize(x, peak=0.85):
    return x / max(1e-6, np.max(np.abs(x))) * peak


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    wav = OUT / (name + ".wav")
    pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    ogg = OUT / (name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "4", str(ogg)], check=True)
    wav.unlink()
    return ogg, round(len(samples) / RATE, 2)


def with_voice(bed, clip, at, level):
    """Lay a Higgsfield voice line over a procedural bed; the voice leads."""
    if clip is None:
        return bed
    need = int(RATE * at) + len(clip)
    if need > len(bed):
        bed = np.pad(bed, (0, need - len(bed)))
    return place(bed, normalize(clip, 1.0), at, level)


def build():
    made = []
    made.append(write("crowd_applause", normalize(applause(3.0), 0.7)))
    bed = normalize(cheer(3.4), 0.45)
    bed = with_voice(bed, load_voice("cheer_male_raw.wav"), 0.30, 0.75)
    bed = with_voice(bed, load_voice("cheer_female_raw.wav"), 1.05, 0.6)
    made.append(write("crowd_cheer", normalize(bed, 0.85)))
    bed = normalize(boo(2.8), 0.45)
    bed = with_voice(bed, load_voice("boo_male_raw.wav"), 0.20, 0.8)
    made.append(write("crowd_boo", normalize(bed, 0.8)))
    for source, name in (("angry_male_raw.wav", "voice_angry"), ("draw_female_raw.wav", "voice_draw"),
                         ("hype_female_raw.wav", "voice_hype")):
        clip = load_voice(source)
        if clip is not None:
            made.append(write(name, normalize(clip, 0.8)))
    made.append(write("egg_splat", normalize(splat(), 0.8)))
    made.append(write("egg_throw", normalize(whoosh(), 0.5)))
    return made


if __name__ == "__main__":
    for item in build():
        print(item)

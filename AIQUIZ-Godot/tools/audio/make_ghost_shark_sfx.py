"""Ghost shark ride effects: soul rise, ocean ascent and breach, mount beam, charge loop,
perfect tick, dash, hit, vanish and the return portal (docs/sound_effects.md).

Run from any directory with Python/numpy and ffmpeg. No external samples; deterministic seeds.
Output: assets/audio/sfx/ghost_shark/*.ogg (48 kHz stereo, Ogg Vorbis q7).
"""
from pathlib import Path
import json
import subprocess
import tempfile
import wave
import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parents[2]
OUT = 'ghost_shark'
RNG = np.random.default_rng(51717)


def tt(seconds):
    return np.arange(int(seconds * SR)) / SR


def noise(n, low, high):
    """Band-limited noise, unit RMS. Periodic over n samples (built in the frequency domain)."""
    hz = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(RNG.standard_normal(n))
    spec *= np.minimum(1, hz / low) ** 4 / (1 + (hz / high) ** 6)
    y = np.fft.irfft(spec, n)
    return y / max(1e-9, np.sqrt(np.mean(y * y)))


def sweep_bandpass(x, center_hz, q=4.0):
    """Time-varying state-variable band-pass (center_hz is per sample)."""
    out = np.zeros_like(x)
    low = band = 0.0
    damp = 1.0 / q
    for i in range(len(x)):
        f = 2.0 * np.sin(np.pi * min(center_hz[i], SR * 0.22) / SR)
        high = x[i] - low - damp * band
        band += f * high
        low += f * band
        out[i] = band
    return out


def lowpass(x, hz):
    a = np.exp(-2 * np.pi * hz / SR)
    out = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        out[i] = acc
    return out


def phase(hz):
    """Oscillator phase for a per-sample frequency curve."""
    return 2 * np.pi * np.cumsum(hz) / SR


def env_ad(t, attack, decay):
    return np.minimum(1, t / max(attack, 1e-4)) * np.exp(-np.maximum(0, t - attack) / decay)


def ghost_voice(t, hz, vibrato_hz=5.2, vibrato_depth=0.018, voices=3, detune=0.006):
    """Theremin-like ghost wail: a few slightly detuned sines with vibrato."""
    y = np.zeros_like(t)
    for k in range(voices):
        spread = (k - (voices - 1) / 2) * detune
        vib = 1 + vibrato_depth * np.sin(2 * np.pi * (vibrato_hz + k * 0.37) * t + k * 1.7)
        ph = phase(hz * (1 + spread) * vib)
        y += np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    return y / voices


def reverb(y, seconds=1.2, mix=0.3, seed=0, predelay=0.012):
    """Decaying-noise convolution; returns len(y) + tail."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    ir_t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-ir_t / (seconds / 6.9))
    ir = lowpass(ir, 5200)
    ir[: int(predelay * SR)] = 0
    ir /= np.sqrt(np.sum(ir * ir))
    size = len(y) + n
    wet = np.fft.irfft(np.fft.rfft(y, size) * np.fft.rfft(ir, size), size)
    dry = np.concatenate([y, np.zeros(n)])
    return (1 - mix) * dry + mix * wet * 2.2


def stereo(y, seconds=1.2, mix=0.3, width_seed=7):
    """Spread a mono source with two decorrelated reverbs."""
    left = reverb(y, seconds, mix, seed=width_seed)
    right = reverb(y, seconds, mix, seed=width_seed + 101)
    return np.stack([left, right], axis=1)


def trim_tail(y, threshold_db=-62):
    level = np.max(np.abs(y), axis=1)
    peak = np.max(level)
    above = np.nonzero(level > peak * 10 ** (threshold_db / 20))[0]
    end = min(len(y), above[-1] + int(0.03 * SR)) if len(above) else len(y)
    return y[:end]


def write(name, y, peak=-3.0, fade_in=0.002, fade_out=0.06, loop=False):
    if y.ndim == 1:
        y = np.stack([y, y], axis=1)
    y = y - np.mean(y, axis=0)
    if not loop:
        y = trim_tail(y)
        k = min(int(fade_in * SR), len(y) // 4)
        y[:k] *= np.linspace(0, 1, k)[:, None]
        k = min(int(fade_out * SR), len(y) // 4)
        y[-k:] *= np.linspace(1, 0, k)[:, None]
    y = y * (10 ** (peak / 20) / np.max(np.abs(y)))
    destination = ROOT / 'assets/audio/sfx' / OUT / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / 'source.wav'
        with wave.open(str(wav), 'wb') as f:
            f.setparams((2, 2, SR, 0, 'NONE', 'not compressed'))
            f.writeframes((y * 32767).astype('<i2').tobytes())
        subprocess.run(
            ['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-c:a', 'libvorbis', '-q:a', '7', str(destination)],
            check=True,
        )
    mono = np.mean(y, axis=1)
    window = int(0.08 * SR)
    power = np.convolve(mono * mono, np.ones(window) / window, mode='valid') if len(mono) > window else mono * mono
    return {
        'path': str(destination.relative_to(ROOT)).replace('\\', '/'),
        'seconds': round(len(y) / SR, 3),
        'peak_dbfs': peak,
        'rms_dbfs': round(float(10 * np.log10(np.mean(mono * mono) + 1e-12)), 2),
        'max_80ms_rms_dbfs': round(float(10 * np.log10(np.max(power) + 1e-12)), 2),
    }


# ---------------------------------------------------------------------------------------------
# Cues

def soul_rise():
    """The dead player's soul leaves the body: a breathy, rising shimmer (~1.5 s)."""
    t = tt(1.5)
    u = np.clip(t / 1.5, 0, 1)
    hz = 520 * 2 ** (u * 1.15)
    wail = ghost_voice(t, hz, vibrato_hz=6.0, vibrato_depth=0.012, voices=4, detune=0.008)
    shimmer = np.zeros_like(t)
    for k, ratio in enumerate([2.0, 3.01, 4.02]):
        shimmer += np.sin(phase(hz * ratio) + k) * (0.18 / (k + 1))
    shimmer *= 0.5 + 0.5 * np.sin(2 * np.pi * 11 * t) ** 2
    breath = sweep_bandpass(noise(len(t), 300, 9000), 900 * 2 ** (u * 2.2), q=3.0)
    breath /= np.max(np.abs(breath))
    body = 0.32 * wail + 0.28 * shimmer + 0.32 * breath
    body *= np.minimum(1, t / 0.22) * (1 - u) ** 0.6
    return stereo(body, seconds=1.6, mix=0.42, width_seed=11)


def shark_rise():
    """The ghost shark surges up from the deep (2.45 s ascent): underwater swell + eerie wail."""
    length = 2.6
    t = tt(length)
    u = np.clip(t / 2.45, 0, 1)
    swell = u ** 1.6
    rumble = sweep_bandpass(noise(len(t), 25, 900), 70 + 160 * swell, q=1.6)
    rumble /= np.max(np.abs(rumble))
    sub = np.sin(phase(42 + 26 * swell)) * (0.4 + 0.6 * swell)
    wail_hz = 196 * 2 ** (swell * 0.75) * (1 + 0.04 * np.sin(2 * np.pi * 0.9 * t))
    wail = ghost_voice(t, wail_hz, vibrato_hz=4.6, vibrato_depth=0.022, voices=3, detune=0.011)
    wail *= np.clip((t - 0.35) / 1.4, 0, 1) ** 1.3
    bubbles = np.zeros_like(t)
    rng = np.random.default_rng(404)
    for at in np.sort(rng.uniform(0.15, 2.35, 26)):
        age = np.maximum(0, t - at)
        f0 = rng.uniform(380, 1100) * (1 + 1.6 * np.minimum(age, 0.05) / 0.05)
        bubbles += np.where(t >= at, np.sin(phase(np.full_like(t, f0)) * 1.0) * np.exp(-age / 0.025), 0)
    bubbles = lowpass(bubbles, 2600) * 0.5
    body = 0.42 * rumble * (0.3 + 0.7 * swell) + 0.3 * sub + 0.32 * wail + 0.16 * bubbles * swell
    body *= np.minimum(1, t / 0.4) * np.minimum(1, np.maximum(0, (length - t) / 0.25))
    return stereo(body, seconds=1.4, mix=0.3, width_seed=21)


def shark_breach():
    """The ghost shark breaks the ocean surface: splash, spray and a spectral howl (~1.6 s)."""
    t = tt(1.0)
    impact = noise(len(t), 90, 5200) * env_ad(t, 0.006, 0.09)
    thump = np.sin(phase(95 - 45 * np.minimum(t, 0.25) / 0.25)) * env_ad(t, 0.004, 0.11)
    spray = noise(len(t), 1800, 11000) * env_ad(t, 0.03, 0.32)
    drops = np.zeros_like(t)
    rng = np.random.default_rng(77)
    for at in np.sort(rng.uniform(0.12, 0.9, 22)):
        age = np.maximum(0, t - at)
        f0 = rng.uniform(900, 2600)
        drops += np.where(t >= at, np.sin(2 * np.pi * f0 * (1 + 2.5 * age) * age) * np.exp(-age / 0.018), 0) * rng.uniform(0.3, 1)
    howl_hz = 330 * 2 ** (-0.55 * np.clip(t / 0.9, 0, 1)) * (1 + 0.02 * np.sin(2 * np.pi * 5.8 * t))
    howl = ghost_voice(t, howl_hz, vibrato_hz=5.8, vibrato_depth=0.02, voices=4, detune=0.012) * env_ad(t, 0.05, 0.45)
    body = 0.5 * impact + 0.45 * thump + 0.22 * spray + 0.08 * drops + 0.3 * howl
    return stereo(body, seconds=1.3, mix=0.28, width_seed=31)


def mount_beam():
    """The rider is mounted and a spirit pillar fires (beam_fired = sound start).

    Timeline after the fire: opens 0-0.34 s, power hold to ~1.39 s, close 0.24 s, then the shark
    rises out of the pillar. Zap + boom, a sustained resonant hum, then a power-down sweep.
    """
    length = 2.4
    t = tt(length)
    hold_end = 1.39
    close_end = hold_end + 0.30
    open_w = np.clip(t / 0.34, 0, 1)
    close_w = 1 - np.clip((t - hold_end) / (close_end - hold_end), 0, 1)
    sustain = open_w * close_w
    pitch = 1 + 0.18 * open_w - 0.55 * (1 - close_w)
    base = 110 * pitch
    ph = phase(base)
    saw = np.zeros_like(t)
    for k in range(1, 14):
        saw += np.sin(k * ph) / k * (1 + 0.15 * np.sin(2 * np.pi * 7.3 * t + k))
    hum = lowpass(saw, 1800) * sustain
    choir = ghost_voice(t, base * 3, vibrato_hz=5.0, vibrato_depth=0.01, voices=5, detune=0.009) * sustain
    crackle = noise(len(t), 2500, 12000) * (0.35 + 0.65 * np.abs(np.sin(2 * np.pi * 23 * t)) ** 6) * sustain
    zap = sweep_bandpass(noise(len(t), 200, 12000), 6000 * np.exp(-t / 0.05) + 300, q=5.0) * env_ad(t, 0.002, 0.12)
    boom = np.sin(phase(70 * np.exp(-t / 0.4) + 30)) * env_ad(t, 0.004, 0.32)
    power_down = np.sin(phase(440 * np.exp(-np.maximum(0, t - hold_end) / 0.18) + 40))
    power_down *= np.where(t >= hold_end, np.exp(-np.maximum(0, t - hold_end) / 0.22), 0)
    whoosh = sweep_bandpass(noise(len(t), 150, 9000), 400 + 3000 * np.clip((t - close_end) / 0.6, 0, 1), q=2.0)
    whoosh *= np.clip((t - close_end + 0.15) / 0.25, 0, 1) * np.exp(-np.maximum(0, t - close_end - 0.2) / 0.22)
    whoosh /= max(1e-9, np.max(np.abs(whoosh)))
    zap /= np.max(np.abs(zap))
    body = (
        0.34 * hum / np.max(np.abs(hum))
        + 0.2 * choir
        + 0.05 * crackle
        + 0.4 * zap
        + 0.5 * boom
        + 0.2 * power_down
        + 0.26 * whoosh
    )
    return stereo(body, seconds=1.8, mix=0.3, width_seed=41)


def charge_loop():
    """Held while the charge meter cycles. Seamless 1.0 s loop; the game raises its pitch with the charge."""
    length = 1.0
    t = tt(length)
    # Every partial and LFO completes a whole number of cycles in the loop.
    hum = np.zeros_like(t)
    for f, amp in [(110, 0.5), (165, 0.3), (220, 0.32), (331, 0.12), (440, 0.1), (662, 0.05)]:
        hum += amp * np.sin(2 * np.pi * f * t)
    hum *= 0.75 + 0.25 * np.sin(2 * np.pi * 8 * t)
    whisper = noise(len(t), 600, 6000) * (0.55 + 0.45 * np.sin(2 * np.pi * 4 * t + 1.0) ** 2)
    shimmer = (np.sin(2 * np.pi * 1320 * t) + 0.6 * np.sin(2 * np.pi * 1985 * t)) * (0.5 + 0.5 * np.sin(2 * np.pi * 16 * t))
    body = 0.6 * hum + 0.14 * whisper + 0.07 * shimmer
    return np.stack([body, np.roll(body, int(0.011 * SR))], axis=1)


def charge_perfect():
    """Short bright tick when the charge enters the PERFECT band (~0.35 s)."""
    t = tt(0.35)
    bell = np.zeros_like(t)
    for ratio, amp, decay in [(1.0, 1.0, 0.09), (2.76, 0.45, 0.05), (5.4, 0.2, 0.03)]:
        bell += amp * np.sin(2 * np.pi * 1568 * ratio * t) * np.exp(-t / decay)
    click = noise(len(t), 3000, 12000) * np.exp(-t / 0.004)
    return stereo(0.7 * bell + 0.12 * click, seconds=0.5, mix=0.18, width_seed=51)


def dash():
    """Release: the shark launches in a straight dash. Whoosh + spectral roar (~1.0 s)."""
    t = tt(0.9)
    u = np.clip(t / 0.9, 0, 1)
    whoosh = sweep_bandpass(noise(len(t), 120, 12000), 500 + 4200 * np.sin(np.pi * np.minimum(u * 1.6, 1)) ** 1.5, q=1.8)
    whoosh /= np.max(np.abs(whoosh))
    whoosh *= env_ad(t, 0.05, 0.3)
    roar_hz = 150 * 2 ** (0.5 * np.exp(-t / 0.15)) * (1 + 0.03 * np.sin(2 * np.pi * 31 * t))
    roar = ghost_voice(t, roar_hz, vibrato_hz=7.5, vibrato_depth=0.03, voices=4, detune=0.02)
    roar += 0.4 * lowpass(noise(len(t), 60, 1500), 900) * np.sin(2 * np.pi * 31 * t) ** 2
    roar *= env_ad(t, 0.02, 0.28)
    kick = np.sin(phase(140 * np.exp(-t / 0.05) + 45)) * env_ad(t, 0.002, 0.07)
    body = 0.5 * whoosh + 0.32 * roar + 0.4 * kick
    return stereo(body, seconds=1.0, mix=0.24, width_seed=61)


def hit():
    """The charge connects with the survivor: heavy slam, spectral crack and spray (~0.9 s)."""
    t = tt(0.8)
    slam = np.sin(phase(120 * np.exp(-t / 0.06) + 48)) * env_ad(t, 0.002, 0.16)
    crunch = noise(len(t), 140, 6500) * env_ad(t, 0.001, 0.05)
    crack = sweep_bandpass(noise(len(t), 400, 12000), 5200 * np.exp(-t / 0.08) + 700, q=6.0)
    crack = crack / np.max(np.abs(crack)) * env_ad(t, 0.001, 0.09)
    ring = ghost_voice(t, 523 * 2 ** (-0.3 * np.clip(t / 0.6, 0, 1)), vibrato_hz=7.0, voices=4, detune=0.015) * env_ad(t, 0.01, 0.3)
    spray = noise(len(t), 1500, 10000) * env_ad(t, 0.02, 0.18)
    body = 0.62 * slam + 0.42 * crunch + 0.3 * crack + 0.16 * ring + 0.12 * spray
    return stereo(body, seconds=1.1, mix=0.22, width_seed=71)


def vanish():
    """After the dash the shark fades out of the world: reverse-swell 'poof' sinking away (~0.9 s)."""
    t = tt(0.8)
    u = np.clip(t / 0.8, 0, 1)
    swell = np.clip(t / 0.18, 0, 1) ** 2 * np.exp(-np.maximum(0, t - 0.18) / 0.14)
    air = sweep_bandpass(noise(len(t), 200, 10000), 2600 * 2 ** (-2.4 * u) + 250, q=2.2)
    air /= np.max(np.abs(air))
    sigh = ghost_voice(t, 440 * 2 ** (-1.1 * u), vibrato_hz=6.5, vibrato_depth=0.02, voices=3, detune=0.01)
    sigh *= np.clip(t / 0.1, 0, 1) * np.exp(-t / 0.3)
    body = 0.55 * air * swell + 0.22 * sigh
    return stereo(body, seconds=1.4, mix=0.45, width_seed=81)


def portal_open():
    """The return portal swirls open (~1.9 s): rising vortex with a pulsing spectral drone."""
    length = 1.9
    t = tt(length)
    u = np.clip(t / length, 0, 1)
    open_w = np.clip(t / 0.6, 0, 1) ** 1.5
    swirl_center = 700 + 900 * u + 500 * np.sin(2 * np.pi * (3.0 + 2.0 * u) * t)
    swirl = sweep_bandpass(noise(len(t), 150, 10000), swirl_center, q=3.5)
    swirl /= np.max(np.abs(swirl))
    drone = ghost_voice(t, 147 * 2 ** (0.25 * u), vibrato_hz=3.6, vibrato_depth=0.015, voices=5, detune=0.01)
    drone *= 0.6 + 0.4 * np.sin(2 * np.pi * 6 * t) ** 2
    sparkle = np.zeros_like(t)
    rng = np.random.default_rng(909)
    for at in np.sort(rng.uniform(0.1, 1.6, 18)):
        age = np.maximum(0, t - at)
        sparkle += np.where(t >= at, np.sin(2 * np.pi * rng.uniform(1800, 3600) * age) * np.exp(-age / 0.05), 0)
    body = (0.42 * swirl + 0.32 * drone + 0.05 * sparkle) * open_w
    body *= np.minimum(1, np.maximum(0, (length - t) / 0.5))
    return stereo(body, seconds=1.4, mix=0.34, width_seed=91)


def portal_cross():
    """The shark bursts back through the portal mouth: a close whoosh and flash (~0.8 s)."""
    t = tt(0.7)
    u = np.clip(t / 0.7, 0, 1)
    whoosh = sweep_bandpass(noise(len(t), 150, 12000), 300 + 5200 * np.sin(np.pi * u) ** 2, q=2.4)
    whoosh /= np.max(np.abs(whoosh))
    whoosh *= np.sin(np.pi * np.minimum(1, t / 0.55)) ** 1.2
    flash = ghost_voice(t, 392 * 2 ** (0.5 * u), vibrato_hz=6.8, voices=4, detune=0.012) * env_ad(t, 0.12, 0.2)
    thump = np.sin(phase(85 * np.exp(-np.maximum(0, t - 0.22) / 0.1) + 40)) * np.where(t >= 0.22, env_ad(np.maximum(0, t - 0.22), 0.003, 0.12), 0)
    body = 0.55 * whoosh + 0.22 * flash + 0.35 * thump
    return stereo(body, seconds=1.1, mix=0.28, width_seed=97)


def seeded_noise(n, low, high, seed):
    """Like noise(), but from its own seed, so a cue does not depend on the order cues are built."""
    rng = np.random.default_rng(seed)
    hz = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(rng.standard_normal(n))
    spec *= np.minimum(1, hz / low) ** 4 / (1 + (hz / high) ** 6)
    y = np.fft.irfft(spec, n)
    return y / max(1e-9, np.sqrt(np.mean(y * y)))


def awaken():
    """GOSTRIDER: the soul opens its arms and wakes as a ghost (~1.0 s). A short inhale swells into
    a bright spectral chord, a soft low 'whump' at the pose, then sparkles that drift upward."""
    length = 1.0
    t = tt(length)
    hit_at = 0.16
    after = np.maximum(0, t - hit_at)
    inhale = sweep_bandpass(seeded_noise(len(t), 400, 9000, 1201), 700 + 3800 * np.clip(t / hit_at, 0, 1) ** 2, q=2.6)
    inhale /= np.max(np.abs(inhale))
    inhale *= np.clip(t / hit_at, 0, 1) ** 2 * np.where(t < hit_at, 1.0, np.exp(-after / 0.05))
    chord = np.zeros_like(t)
    for k, hz in enumerate([523.25, 659.25, 783.99, 1046.5]):
        chord += ghost_voice(t, np.full_like(t, hz) * (1 + 0.02 * np.exp(-after / 0.2)), vibrato_hz=5.5 + k * 0.4, vibrato_depth=0.01, voices=3, detune=0.006) / (1 + 0.35 * k)
    chord *= np.where(t >= hit_at, env_ad(after, 0.015, 0.42), 0)
    whump = np.sin(phase(95 * np.exp(-after / 0.07) + 42)) * np.where(t >= hit_at, env_ad(after, 0.003, 0.14), 0)
    sparkle = np.zeros_like(t)
    rng = np.random.default_rng(1207)
    for at in np.sort(rng.uniform(hit_at + 0.02, 0.85, 22)):
        age = np.maximum(0, t - at)
        pitch = rng.uniform(2400, 5200) * (1 + 0.4 * (at - hit_at))
        sparkle += np.where(t >= at, np.sin(2 * np.pi * pitch * age) * np.exp(-age / 0.045), 0) * (1 - (at - hit_at) / 0.9)
    body = 0.32 * inhale + 0.3 * chord + 0.5 * whump + 0.07 * sparkle
    return stereo(body, seconds=1.5, mix=0.4, width_seed=1211)


def mount_land():
    """GOSTRIDER: the ghost drops into the saddle (~1.1 s). A heavy body thud, the slap of the saddle,
    a metallic clank from the handlebar grips, then a ghostly surge as the spirit flows into the shark."""
    length = 1.1
    t = tt(length)
    thud = np.sin(phase(70 * np.exp(-t / 0.09) + 38)) * env_ad(t, 0.002, 0.2)
    slap = sweep_bandpass(seeded_noise(len(t), 200, 8000, 1301), 1100 * np.exp(-t / 0.05) + 380, q=2.2)
    slap = slap / np.max(np.abs(slap)) * env_ad(t, 0.0015, 0.045)
    clank = np.zeros_like(t)
    clank_at = 0.012
    age = np.maximum(0, t - clank_at)
    for hz, decay, gain in [(1240, 0.09, 1.0), (2710, 0.06, 0.7), (4130, 0.04, 0.45), (5620, 0.03, 0.3)]:
        clank += np.where(t >= clank_at, np.sin(2 * np.pi * hz * age) * np.exp(-age / decay) * gain, 0)
    surge_start = 0.08
    surge_age = np.maximum(0, t - surge_start)
    surge_u = np.clip(surge_age / 0.75, 0, 1)
    surge = ghost_voice(t, 196 * 2 ** (1.4 * surge_u ** 0.7), vibrato_hz=6.2, vibrato_depth=0.02, voices=5, detune=0.012)
    surge *= np.where(t >= surge_start, np.clip(surge_age / 0.12, 0, 1) * np.exp(-surge_age / 0.5), 0)
    air = sweep_bandpass(seeded_noise(len(t), 300, 11000, 1307), 900 + 4200 * surge_u, q=2.8)
    air = air / np.max(np.abs(air)) * np.where(t >= surge_start, np.clip(surge_age / 0.2, 0, 1) * np.exp(-surge_age / 0.35), 0)
    body = 0.72 * thud + 0.34 * slap + 0.12 * clank + 0.24 * surge + 0.16 * air
    return stereo(body, seconds=1.3, mix=0.26, width_seed=1311)


def revive_gather():
    """Sudden death revival (docs/sudden_death_v2/ghost_revive.md): the floating ghost calls its body back.
    Starts 0.25 s into the revival and peaks at the burst 1.43 s later: a swirling wind that speeds up, swishes of the
    parts flying past, a rising ghost choir, and a short inhale that stops dead at the burst (~1.6 s)."""
    length = 1.6
    burst = 1.43
    t = tt(length)
    u = np.clip(t / burst, 0, 1)
    swirl_rate = 2.4 + 11.0 * u ** 1.6
    swirl = 0.55 + 0.45 * np.sin(np.cumsum(2 * np.pi * swirl_rate / SR))
    wind = sweep_bandpass(seeded_noise(len(t), 150, 9000, 1401), 380 + 2600 * u ** 1.4 + 500 * swirl, q=2.2)
    wind = wind / np.max(np.abs(wind)) * (0.25 + 0.75 * u ** 1.2) * swirl
    swishes = np.zeros_like(t)
    rng = np.random.default_rng(1409)
    # one swish per part arriving (the revival's arrival times, from the gather sound's start)
    for at in [0.31, 0.39, 0.47, 0.55, 0.63, 0.71, 0.79, 0.86, 0.93, 1.0, 1.08, 1.17]:
        width = 0.07
        shape = np.exp(-((t - at) / width) ** 2)
        center = 900 + 3800 * shape
        swish = sweep_bandpass(seeded_noise(len(t), 300, 12000, 1410 + int(at * 100)), center, q=3.5)
        swishes += swish / np.max(np.abs(swish)) * shape * rng.uniform(0.6, 1.0)
    choir = ghost_voice(t, 196 * 2 ** (1.0 * u ** 1.3), vibrato_hz=5.0 + 2.5 * u, vibrato_depth=0.016, voices=5, detune=0.01)
    choir += 0.6 * ghost_voice(t, 294 * 2 ** (1.0 * u ** 1.3), vibrato_hz=5.6 + 2.0 * u, vibrato_depth=0.014, voices=4, detune=0.009)
    choir *= np.clip(t / 0.25, 0, 1) * (0.3 + 0.7 * u ** 1.5)
    inhale_start = burst - 0.22
    inhale_u = np.clip((t - inhale_start) / (burst - inhale_start), 0, 1)
    inhale = sweep_bandpass(seeded_noise(len(t), 400, 11000, 1417), 800 + 6000 * inhale_u ** 2, q=2.4)
    inhale = inhale / np.max(np.abs(inhale)) * inhale_u ** 2
    body = 0.34 * wind + 0.22 * swishes + 0.2 * choir + 0.4 * inhale
    # everything stops dead at the burst (the burst sound takes over), with only a short room tail
    body *= np.where(t < burst, 1.0, np.exp(-(t - burst) / 0.018))
    return stereo(body, seconds=0.9, mix=0.22, width_seed=1421)


def revive_snap():
    """A body part locking into the ghost (~0.3 s). The game raises the pitch with every part (a rising scale).
    A soft magnetic thunk, a tight click, a glassy ping and a pinch of sparkle."""
    length = 0.3
    t = tt(length)
    thunk = np.sin(phase(150 * np.exp(-t / 0.03) + 95)) * env_ad(t, 0.0015, 0.05)
    click = sweep_bandpass(seeded_noise(len(t), 1500, 14000, 1501), np.full_like(t, 5200), q=1.6)
    click = click / np.max(np.abs(click)) * env_ad(t, 0.0005, 0.007)
    ping = np.zeros_like(t)
    for hz, decay, gain in [(880, 0.1, 1.0), (1764, 0.07, 0.55), (2659, 0.05, 0.35), (4420, 0.035, 0.22)]:
        ping += np.sin(2 * np.pi * hz * t) * np.exp(-t / decay) * gain
    ping *= np.minimum(1, t / 0.002)
    sparkle = np.zeros_like(t)
    rng = np.random.default_rng(1507)
    for at in np.sort(rng.uniform(0.01, 0.12, 6)):
        age = np.maximum(0, t - at)
        sparkle += np.where(t >= at, np.sin(2 * np.pi * rng.uniform(3600, 6400) * age) * np.exp(-age / 0.025), 0)
    body = 0.55 * thunk + 0.35 * click + 0.3 * ping + 0.06 * sparkle
    return stereo(body, seconds=0.35, mix=0.18, width_seed=1511)


def revive_burst():
    """The whole body is back and bursts with light (~1.6 s): a bright crack and a deep boom, a major chord that
    blooms and a shower of sparkles; 0.30 s later the body lands on its pad (a heavy thud and the slap of the floor)."""
    length = 1.6
    land_at = 0.3
    t = tt(length)
    crack = sweep_bandpass(seeded_noise(len(t), 600, 15000, 1601), 5200 * np.exp(-t / 0.06) + 1400, q=1.4)
    crack = crack / np.max(np.abs(crack)) * env_ad(t, 0.001, 0.05)
    boom = np.sin(phase(78 * np.exp(-t / 0.12) + 34)) * env_ad(t, 0.002, 0.32)
    chord = np.zeros_like(t)
    for k, hz in enumerate([261.63, 329.63, 392.0, 523.25, 659.25]):
        chord += ghost_voice(t, np.full_like(t, hz) * (1 + 0.03 * np.exp(-t / 0.08)), vibrato_hz=5.2 + k * 0.3, vibrato_depth=0.008, voices=3, detune=0.005) / (1 + 0.3 * k)
    chord *= env_ad(t, 0.015, 0.5)
    sparkle = np.zeros_like(t)
    rng = np.random.default_rng(1607)
    for at in np.sort(rng.uniform(0.02, 0.9, 36)):
        age = np.maximum(0, t - at)
        pitch = rng.uniform(2600, 7200)
        sparkle += np.where(t >= at, np.sin(2 * np.pi * pitch * age) * np.exp(-age / 0.045), 0) * (1 - at / 1.05)
    land_age = np.maximum(0, t - land_at)
    landed = np.where(t >= land_at, 1.0, 0.0)
    thud = np.sin(phase(64 * np.exp(-land_age / 0.08) + 36)) * env_ad(land_age, 0.002, 0.2) * landed
    slap = sweep_bandpass(seeded_noise(len(t), 200, 9000, 1611), 1300 * np.exp(-land_age / 0.04) + 420, q=2.0)
    slap = slap / np.max(np.abs(slap)) * env_ad(land_age, 0.0012, 0.05) * landed
    body = 0.4 * crack + 0.7 * boom + 0.22 * chord + 0.08 * sparkle + 0.75 * thud + 0.3 * slap
    return stereo(body, seconds=1.2, mix=0.3, width_seed=1621)


CUES = {
    'ghost_soul_rise.ogg': (soul_rise, {'fade_in': 0.02}),
    'ghost_shark_rise.ogg': (shark_rise, {'fade_in': 0.02}),
    'ghost_shark_breach.ogg': (shark_breach, {}),
    'ghost_mount_beam.ogg': (mount_beam, {}),
    'ghost_charge_loop.ogg': (charge_loop, {'peak': -6.0, 'loop': True}),
    'ghost_charge_perfect.ogg': (charge_perfect, {}),
    'ghost_dash.ogg': (dash, {}),
    'ghost_hit.ogg': (hit, {}),
    'ghost_vanish.ogg': (vanish, {'fade_in': 0.01}),
    'ghost_portal_open.ogg': (portal_open, {'fade_in': 0.02}),
    'ghost_portal_cross.ogg': (portal_cross, {'fade_in': 0.01}),
    # GOSTRIDER mount presentation (seeded per cue, independent of build order).
    'ghost_awaken.ogg': (awaken, {'fade_in': 0.01}),
    'ghost_mount_land.ogg': (mount_land, {}),
    # Sudden death: a ghost at the draw gets its body back (docs/sudden_death_v2/ghost_revive.md).
    'ghost_revive_gather.ogg': (revive_gather, {'fade_in': 0.05}),
    'ghost_revive_snap.ogg': (revive_snap, {'fade_out': 0.03}),
    'ghost_revive_burst.ogg': (revive_burst, {}),
}


def main():
    """python make_ghost_shark_sfx.py [--only name.ogg ...]  (default: every cue, in order)"""
    import sys
    only = [arg for arg in sys.argv[1:] if not arg.startswith('--')]
    names = only if '--only' in sys.argv[1:] else list(CUES)
    report = []
    for name in names:
        build, options = CUES[name]
        report.append(write(name, build(), **options))
    p = ROOT / 'artifacts/ghost_shark_audio/assets.json'
    p.parent.mkdir(parents=True, exist_ok=True)
    if '--only' in sys.argv[1:] and p.exists():
        previous = {entry['path']: entry for entry in json.loads(p.read_text(encoding='utf8'))}
        for entry in report:
            previous[entry['path']] = entry
        report = list(previous.values())
    p.write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

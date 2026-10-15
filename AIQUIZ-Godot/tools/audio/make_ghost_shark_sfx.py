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


def main():
    report = [
        write('ghost_soul_rise.ogg', soul_rise(), fade_in=0.02),
        write('ghost_shark_rise.ogg', shark_rise(), fade_in=0.02),
        write('ghost_shark_breach.ogg', shark_breach()),
        write('ghost_mount_beam.ogg', mount_beam()),
        write('ghost_charge_loop.ogg', charge_loop(), peak=-6.0, loop=True),
        write('ghost_charge_perfect.ogg', charge_perfect()),
        write('ghost_dash.ogg', dash()),
        write('ghost_hit.ogg', hit()),
        write('ghost_vanish.ogg', vanish(), fade_in=0.01),
        write('ghost_portal_open.ogg', portal_open(), fade_in=0.02),
        write('ghost_portal_cross.ogg', portal_cross(), fade_in=0.01),
    ]
    p = ROOT / 'artifacts/ghost_shark_audio/assets.json'
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

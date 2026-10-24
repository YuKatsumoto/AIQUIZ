"""Sudden death effects (つきやぶれ！スカイゲート and its floatplane staging) from 効果音ラボ files
(docs/sound_effects.md, assets/audio/sfx/CREDITS.md).

The originals (downloaded 2026-10-20) sit in assets/audio/sfx/source/se_lab/ and the results in
assets/audio/sfx/se_lab/; both folders are kept out of git (効果音ラボ forbids redistributing the files).
Each recipe cuts a part of one original, fades it, and normalises the peak; loops get an equal-power
crossfade (or a forward + reversed palindrome) so they repeat without a click.

Run from any directory with Python/numpy and ffmpeg. Writes artifacts/sudden_death_audio/assets.json.
After a rebuild, let the Godot editor rescan the files (focus it) so the game plays the new versions.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import wave
import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/audio/sfx/source/se_lab'
OUT = ROOT / 'assets/audio/sfx/se_lab'


def load(name):
    raw = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', str(SOURCE / name), '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
        capture_output=True, check=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def cut(y, start=0.0, end=None):
    a = int(start * SR)
    b = len(y) if end is None else min(len(y), int(end * SR))
    return y[a:b].copy()


def fade(y, fade_in=0.002, fade_out=0.05):
    k = min(int(fade_in * SR), len(y) // 2)
    if k > 0:
        y[:k] *= np.linspace(0.0, 1.0, k)[:, None]
    k = min(int(fade_out * SR), len(y) // 2)
    if k > 0:
        y[-k:] *= np.linspace(1.0, 0.0, k)[:, None] ** 1.5
    return y


def envelope(y, seconds=0.25):
    """Smoothed RMS envelope (per sample, mono)."""
    n = max(1, int(seconds * SR))
    power = np.mean(y * y, axis=1)
    kernel = np.hanning(n * 2 + 1)
    kernel /= kernel.sum()
    padded = np.pad(power, (n, n), mode='edge')
    return np.sqrt(np.convolve(padded, kernel, mode='valid') + 1e-12)


def flatten(y, amount=1.0, seconds=0.25):
    """Take out the slow level changes (a recording that grows or swells), keeping the texture."""
    env = envelope(y, seconds)
    gain = (np.median(env) / env) ** amount
    return y * gain[:, None]


def crossfade_loop(y, overlap):
    """A seamless loop of len(y) - overlap samples: the tail is blended into the head (equal power)."""
    n = int(overlap * SR)
    body = y[:-n].copy()
    t = np.linspace(0.0, 1.0, n)[:, None]
    body[:n] = y[:n] * np.sin(t * np.pi * 0.5) + y[-n:] * np.cos(t * np.pi * 0.5)
    return body


def palindrome_loop(y, overlap=0.04):
    """Forward then reversed (a steady texture sounds the same backwards), joined with short crossfades."""
    n = int(overlap * SR)
    back = y[::-1].copy()
    t = np.linspace(0.0, 1.0, n)[:, None]
    joined = np.concatenate([y[:-n], y[-n:] * np.cos(t * np.pi * 0.5) + back[:n] * np.sin(t * np.pi * 0.5), back[n:]])
    # The end of the reversed half is the head of the forward half: blend the seam there too.
    head = joined[:n].copy()
    tail = joined[-n:].copy()
    joined = joined[:-n]
    joined[:n] = head * np.sin(t * np.pi * 0.5) + tail * np.cos(t * np.pi * 0.5)
    return joined


def highpass(y, hz):
    spec = np.fft.rfft(y, axis=0)
    freq = np.fft.rfftfreq(len(y), 1 / SR)
    spec *= (np.minimum(1.0, freq / hz) ** 2)[:, None]
    return np.fft.irfft(spec, len(y), axis=0)


def write(name, y, peak=-3.0):
    y = y - np.mean(y, axis=0)
    y = y * (10 ** (peak / 20) / max(1e-9, np.max(np.abs(y))))
    destination = OUT / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / 'source.wav'
        with wave.open(str(wav), 'wb') as f:
            f.setparams((2, 2, SR, 0, 'NONE', 'not compressed'))
            f.writeframes((np.clip(y, -1.0, 1.0) * 32767).astype('<i2').tobytes())
        subprocess.run(
            # bitexact: the same input gives the same bytes (no random Ogg serial), so a rebuild does not touch unchanged files
            ['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-c:a', 'libvorbis', '-q:a', '6', '-fflags', '+bitexact',
             '-flags:a', '+bitexact', str(destination)],
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
        'loudest_at': round(float(np.argmax(power) + window / 2) / SR, 3),
    }


def one_shot(name, source, start=0.0, end=None, fade_in=0.002, fade_out=0.05, peak=-3.0):
    return write(name, fade(cut(load(source), start, end), fade_in, fade_out), peak)


def main():
    report = [
        # The branch: the referee's whistle (8.4 s), the alarm with "SUDDEN DEATH!" (8.6 s), the towers sinking (9.0-10.4 s).
        one_shot('sd_whistle.ogg', 'police-whistle2.mp3', 0.018, None, 0.002, 0.08),
        one_shot('sd_siren.ogg', 'emergency-alert1.mp3', 0.0, 3.2, 0.004, 0.7),
        one_shot('sd_tower_move.ogg', 'giant-motor1.mp3', 0.0, 2.0, 0.03, 0.55),
        # The stand beside the podium rising on its towers and going down again, the floor-edge lift and the hatch servos.
        one_shot('sd_stand_lift.ogg', 'giant-shutter1.mp3', 0.015, 3.0, 0.004, 0.8),
        one_shot('sd_stand_lower.ogg', 'giant-motor1.mp3', 0.0, 3.6, 0.03, 1.0),
        one_shot('sd_servo.ogg', 'arm-action1.mp3', 0.0, 0.95, 0.002, 0.08),
        # The floatplane: ramp hydraulics and its lock, the low pass overhead, the touchdown spray. (The green jump light plays
        # the start countdown's game/countdown_go.ogg: the buzzer sounded too much like the wrong-answer buzzer.)
        one_shot('fp_ramp.ogg', 'giant-arm-action3.mp3', 0.012, 2.0, 0.003, 0.3),
        one_shot('fp_ramp_latch.ogg', 'iron-door-close1.mp3', 0.015, None, 0.002, 0.08),
        one_shot('fp_flyby.ogg', 'propeller-aircraft-pass1.mp3', 2.1, None, 0.25, 0.5),
        one_shot('fp_touchdown.ogg', 'water-throw-stone2.mp3', 0.008, None, 0.002, 0.1),
        # The wind rushing in when the ramp opens in the air, and the jump off the ramp.
        one_shot('fp_ramp_wind.ogg', 'wind2.mp3', 40.0, 45.5, 2.0, 1.5),
        one_shot('fp_jump.ogg', 'jump1.mp3', 0.0, 0.9, 0.002, 0.1),
        # Through the cloud deck (the cover between the surface and the sky set): the gust starts part way up its swell,
        # so the loudest moment comes about 0.5 s in (while the cover is fully white or black).
        one_shot('sd_cloud_whoosh.ogg', 'gust-wind1.mp3', 0.42, 3.7, 0.12, 0.4),
        # The sky gate: the board rushing past, tearing through, bouncing off, the verdict, the revive, the rounds.
        one_shot('sg_gate_rush.ogg', 'highspeed-movement1.mp3', 0.0, 1.12),
        # The two tears are picked at random: the longer one is set 4 dB lower so both sound about as loud.
        one_shot('sg_tear_a.ogg', 'paper-tear2.mp3', 0.028, 0.45, 0.002, 0.04, -7.0),
        one_shot('sg_tear_b.ogg', 'paper-tear3.mp3', 0.008, 0.2, 0.002, 0.03),
        one_shot('sg_bounce.ogg', 'boyon1.mp3', 0.0, 0.66),
        one_shot('sg_safe.ogg', 'kira1.mp3', 0.008, 0.92),
        one_shot('sg_revive.ogg', 'magic-cure1.mp3', 0.01, 1.86, 0.002, 0.1),
        one_shot('sg_round_gong.ogg', 'gong-played1.mp3', 0.005, None, 0.002, 0.1),
        one_shot('sg_round_clear.ogg', 'trumpet1.mp3', 0.0, 1.66, 0.002, 0.12),
        one_shot('sg_overtime.ogg', 'trumpet2.mp3', 0.0, 3.3, 0.002, 0.5),
        one_shot('sg_notice.ogg', 'warning2.mp3', 0.0, 0.92),
        one_shot('sg_chute_open.ogg', 'umbrella-open1.mp3', 0.15, 0.6, 0.004, 0.06),
        one_shot('sg_float_splash.ogg', 'sprinkle-water1.mp3', 0.0, 0.82),
        one_shot('sg_winner.ogg', 'jajean1.mp3', 0.0, 1.55, 0.002, 0.15),
    ]
    # Loops (played by their own players, which set loop = true on the stream).
    # The falling wind: 24 s of the strong-wind recording, swells evened out by half, 2 s crossfade.
    wind = flatten(cut(load('wind2.mp3'), 10.0, 34.0), 0.5, 0.6)
    report.append(write('sd_freefall_loop.ogg', crossfade_loop(wind, 2.0), -6.0))
    # The floatplane's engine bed: the steady cabin noise of a flying aircraft (whine and roar), 1 s crossfade.
    engine = cut(load('fighter-cockpit1.mp3'), 4.0, 17.0)
    report.append(write('fp_engine_loop.ogg', crossfade_loop(engine, 1.0), -6.0))
    # The propeller buzz: the approach of the propeller pass, where the blade tone holds still (68 Hz), level evened out.
    prop = highpass(flatten(cut(load('propeller-aircraft-pass1.mp3'), 1.0, 2.2), 1.0, 0.2), 45.0)
    report.append(write('fp_prop_loop.ogg', palindrome_loop(prop, 0.04), -6.0))
    p = ROOT / 'artifacts/sudden_death_audio/assets.json'
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(report, indent=2), encoding='utf8')
    for row in report:
        print(f"{row['path']:52s} {row['seconds']:6.2f}s  rms {row['rms_dbfs']:6.1f}  max80 {row['max_80ms_rms_dbfs']:6.1f}  at {row['loudest_at']:.2f}s")


if __name__ == '__main__':
    main()

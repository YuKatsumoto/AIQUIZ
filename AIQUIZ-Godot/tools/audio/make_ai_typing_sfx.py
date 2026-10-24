"""最初の問題壁に AI が問題文を書く演出（docs/ai_question_typing.md）の効果音。外部の素材は使わず、ここで合成する。

    python tools/audio/make_ai_typing_sfx.py

書き出すもの（assets/audio/sfx/game/、48 kHz ステレオ、Ogg Vorbis q7、ピーク -3 dBFS）：
  ai_type_tick.ogg   文字のかたまり（トークン）が 1 つ出るたびの小さな電子音。ゲームが音程を少し揺らして鳴らす
  ai_type_done.ogg   問題文と選択肢を書き終えたときの、短い 2 音のきらめき
"""
from pathlib import Path
import json
import subprocess
import tempfile
import wave

import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio/sfx/game"
RNG = np.random.default_rng(20261022)


def times(n):
    return np.arange(n) / SR


def noise(n, low, high):
    hz = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(RNG.standard_normal(n))
    spec *= np.minimum(1, hz / max(low, 1)) ** 4 / (1 + (hz / high) ** 6)
    y = np.fft.irfft(spec, n)
    return y / max(1e-9, np.sqrt(np.mean(y * y)))


def env(t, attack, decay):
    return np.minimum(1, t / max(attack, 1e-6)) * np.exp(-np.maximum(0, t - attack) / decay)


def ping(seconds, hz, decay):
    """やわらかい鈴の音（基音と少しずらした倍音）。"""
    t = times(int(seconds * SR))
    y = np.sin(2 * np.pi * hz * t) + 0.35 * np.sin(2 * np.pi * hz * 2.01 * t) * np.exp(-t / (decay * 0.5))
    y += 0.12 * np.sin(2 * np.pi * hz * 3.98 * t) * np.exp(-t / (decay * 0.25))
    return y * env(t, 0.003, decay)


def stereo(mono, width=0.0, delay_ms=0.0):
    """左右に少しだけ時間差をつけて広げる。"""
    d = int(delay_ms * SR / 1000)
    left = mono
    right = np.concatenate([np.zeros(d), mono[:len(mono) - d]]) if d > 0 else mono
    return np.stack([left * (1 - width) + right * width, right * (1 - width) + left * width], axis=1)


def write(name, y, peak=-3.0, fade_out=0.02):
    y = y - np.mean(y, axis=0)
    k = int(0.001 * SR)
    y[:k] *= np.linspace(0, 1, k)[:, None]
    k = int(fade_out * SR)
    y[-k:] *= np.linspace(1, 0, k)[:, None]
    y *= 10 ** (peak / 20) / np.max(np.abs(y))
    OUT.mkdir(parents=True, exist_ok=True)
    destination = OUT / name
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "source.wav"
        with wave.open(str(wav), "wb") as f:
            f.setparams((2, 2, SR, 0, "NONE", "not compressed"))
            f.writeframes((y * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "7", str(destination)], check=True)
    rms = float(20 * np.log10(np.sqrt(np.mean(y * y))))
    return {"path": str(destination.relative_to(ROOT)).replace("\\", "/"), "seconds": round(len(y) / SR, 3),
            "peak_dbfs": peak, "rms_dbfs": round(rms, 2)}


def tick():
    # 乾いた「チッ」（高い帯域の雑音を 1 ms で立ち上げて 9 ms で消す）に、短い電子音の芯（3.1 kHz）を重ねる。
    n = int(0.07 * SR)
    t = times(n)
    click = noise(n, 2500, 9000) * env(t, 0.0008, 0.009)
    blip = np.sin(2 * np.pi * 3100 * t + 2.0 * np.sin(2 * np.pi * 60 * t)) * env(t, 0.001, 0.016)
    body = noise(n, 500, 2200) * env(t, 0.001, 0.006)
    return stereo(0.55 * click + 0.45 * blip + 0.18 * body, width=0.15, delay_ms=0.25)


def done():
    # E6 → B6 の 2 音（0.07 秒あけて）。小さな反射を 3 回重ねて、きらめきの尾を 0.6 秒ほど残す。
    seconds = 0.9
    n = int(seconds * SR)
    y = np.zeros(n)
    for at, hz, gain in ((0.0, 1318.5, 0.8), (0.07, 1975.5, 1.0)):
        s = ping(seconds - at, hz, 0.22)
        start = int(at * SR)
        y[start:start + len(s)] += gain * s[:n - start]
    t = times(n)
    y += 0.10 * noise(n, 5000, 14000) * env(t, 0.05, 0.12)
    tail = np.zeros(n)
    for delay, gain in ((0.045, 0.32), (0.093, 0.2), (0.151, 0.12)):
        d = int(delay * SR)
        tail[d:] += gain * y[:n - d]
    return stereo(y + tail, width=0.3, delay_ms=0.6)


def main():
    report = [write("ai_type_tick.ogg", tick(), fade_out=0.01), write("ai_type_done.ogg", done(), fade_out=0.08)]
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

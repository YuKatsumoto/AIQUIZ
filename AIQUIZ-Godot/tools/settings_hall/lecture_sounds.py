"""講義室の効果音を合成して WAV に書き出す（docs/lecture_hall_plan.md の第 4 段階: 音）。
外部の音源は使わない。どれも物理的な鳴り方（倍音・減衰・雑音の帯域）をまねて numpy で作る。

出力: assets/audio/sfx/lecture/*.wav（44.1 kHz、16 bit、モノラル）
  chime（ウェストミンスターの鐘 8 音、授業の始まり・終わり）、chalk_tap（「。」をカツッ）、chalk_squeak（キーッ）、
  chalk_scratch（書いている音、ループ）、step_plush（ぬいぐるみの足音 ぽふ）、whistle（ホイッスル ピーッ）、
  cleaner_hum（黒板消しクリーナー ブーン、ループ）、eraser_clap（黒板消しを打ち合わせる パフッ）、
  desk_bonk（机に突っ伏す ゴン）、chalk_hit（投げたチョークが頭に ぽこっ）、page_flip（ページをめくる）
使い方: python tools/settings_hall/lecture_sounds.py
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio" / "sfx" / "lecture"
SR = 44100
RNG = np.random.default_rng(1234)


def t_axis(secs: float) -> np.ndarray:
    return np.arange(int(SR * secs)) / SR


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def bandpass(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return lowpass(x, hi) - lowpass(x, lo)


def reverb(x: np.ndarray, room=0.35, decay=0.45) -> np.ndarray:
    """小さな部屋（地下の石の広間）: いくつかの遅れの重ね合わせ。"""
    out = np.concatenate([x, np.zeros(int(SR * 1.2))])
    for delay, gain in ((0.031, 0.5), (0.047, 0.42), (0.071, 0.35), (0.113, 0.28), (0.167, 0.2), (0.241, 0.14)):
        d = int(delay * SR / room * 0.35)
        out[d:d + len(x)] += x * gain * decay
    return out


def bell(freq: float, secs: float, strike=1.0) -> np.ndarray:
    """鐘: 倍音（ハム・プライム・ティアス・クイント・ノミナル）ごとに減衰が違う。"""
    t = t_axis(secs)
    partials = ((0.5, 0.55, 1.6), (1.0, 1.0, 1.25), (1.19, 0.45, 1.0), (1.5, 0.35, 0.8), (2.0, 0.6, 0.65),
                (2.52, 0.25, 0.45), (2.98, 0.18, 0.35), (4.07, 0.1, 0.25))
    y = np.zeros_like(t)
    for ratio, amp, tau in partials:
        detune = 1.0 + RNG.uniform(-0.0015, 0.0015)
        y += amp * np.sin(2 * np.pi * freq * ratio * detune * t) * np.exp(-t / tau)
    hit = np.exp(-t / 0.004) * RNG.normal(0, 0.3, len(t))
    return (y + hit * 0.2) * strike


def chime() -> np.ndarray:
    # E4 C4 D4 G3 / G3 D4 E4 C4（キーンコーンカーンコーン × 2）
    notes = (329.63, 261.63, 293.66, 196.0, 196.0, 293.66, 329.63, 261.63)
    step = 0.78
    total = step * len(notes) + 3.2
    y = np.zeros(int(SR * total))
    for k, f in enumerate(notes):
        start = int(SR * (k * step + (0.25 if k >= 4 else 0.0)))
        b = bell(f, 3.2, 1.0 if k % 4 != 3 else 1.15)
        y[start:start + len(b)] += b[: len(y) - start]
    return reverb(y, decay=0.55)


def chalk_tap() -> np.ndarray:
    t = t_axis(0.12)
    click = bandpass(RNG.normal(0, 1, len(t)), 1800, 5200) * np.exp(-t / 0.008)
    thump = np.sin(2 * np.pi * 180 * t) * np.exp(-t / 0.02) * 0.4
    return reverb(click * 1.6 + thump, decay=0.25)


def chalk_squeak() -> np.ndarray:
    t = t_axis(0.75)
    f = 2550 + 140 * np.sin(2 * np.pi * 7.0 * t) + 260 * t
    phase = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(phase) + 0.45 * np.sin(2 * phase + 0.4) + 0.2 * np.sin(3 * phase)
    stick = (RNG.random(len(t)) < 0.002).astype(float)
    grit = bandpass(RNG.normal(0, 1, len(t)), 2000, 7000) * 0.25
    env = np.clip(t / 0.04, 0, 1) * np.clip((0.75 - t) / 0.12, 0, 1) * (0.8 + 0.2 * np.sin(2 * np.pi * 23 * t))
    return reverb((tone * 0.55 + grit + stick * 0.4) * env, decay=0.3)


def chalk_scratch() -> np.ndarray:
    """書いている音（ループ 0.6 秒）: ザラザラした雑音が筆の動きで強弱する。"""
    t = t_axis(0.6)
    grit = bandpass(RNG.normal(0, 1, len(t)), 900, 6000)
    env = 0.35 + 0.65 * np.abs(np.sin(np.pi * t / 0.15)) ** 2
    y = grit * env * 0.35
    fade = int(0.01 * SR)
    y[:fade] *= np.linspace(0, 1, fade)
    y[-fade:] *= np.linspace(1, 0, fade)
    return y


def step_plush() -> np.ndarray:
    t = t_axis(0.16)
    thud = np.sin(2 * np.pi * (95 + 40 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.035)
    fluff = lowpass(RNG.normal(0, 1, len(t)), 900) * np.exp(-t / 0.03) * 0.8
    return reverb(thud * 0.7 + fluff, decay=0.2)


def whistle() -> np.ndarray:
    t = t_axis(1.0)
    trill = 1.0 + 0.6 * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 26 * t)))
    f = 2850 + 60 * np.sin(2 * np.pi * 26 * t)
    phase = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(phase) * trill + 0.15 * np.sin(2 * phase)
    breath = bandpass(RNG.normal(0, 1, len(t)), 1500, 6000) * 0.2
    env = np.clip(t / 0.03, 0, 1) * np.clip((1.0 - t) / 0.08, 0, 1)
    return reverb((tone * 0.35 + breath) * env, decay=0.5)


def cleaner_hum() -> np.ndarray:
    """黒板消しクリーナー（ループ 1 秒）: モーターのうなりと吸い込む風の音。"""
    t = t_axis(1.0)
    f = 118.0
    saw = sum(np.sin(2 * np.pi * f * k * t) / k for k in range(1, 12))
    air = bandpass(RNG.normal(0, 1, len(t)), 400, 3000) * 0.5
    y = (saw * 0.3 + air) * (0.9 + 0.1 * np.sin(2 * np.pi * 9 * t))
    return y * 0.6


def eraser_clap() -> np.ndarray:
    t = t_axis(0.35)
    slap = bandpass(RNG.normal(0, 1, len(t)), 300, 3500) * np.exp(-t / 0.018)
    puff = lowpass(RNG.normal(0, 1, len(t)), 1200) * np.exp(-t / 0.09) * 0.4
    return reverb(slap * 1.4 + puff, decay=0.3)


def desk_bonk() -> np.ndarray:
    t = t_axis(0.5)
    wood = (np.sin(2 * np.pi * 210 * t) + 0.6 * np.sin(2 * np.pi * 530 * t) + 0.3 * np.sin(2 * np.pi * 1180 * t)) \
        * np.exp(-t / 0.06)
    knock = bandpass(RNG.normal(0, 1, len(t)), 200, 2500) * np.exp(-t / 0.01)
    return reverb(wood * 0.6 + knock * 0.8, decay=0.35)


def chalk_hit() -> np.ndarray:
    t = t_axis(0.3)
    pok = np.sin(2 * np.pi * (520 - 240 * t) * t) * np.exp(-t / 0.04)
    soft = lowpass(RNG.normal(0, 1, len(t)), 1500) * np.exp(-t / 0.02) * 0.5
    return reverb(pok * 0.8 + soft, decay=0.25)


def page_flip() -> np.ndarray:
    t = t_axis(0.45)
    rustle = bandpass(RNG.normal(0, 1, len(t)), 1200, 8000)
    env = np.exp(-((t - 0.16) / 0.09) ** 2) + 0.4 * np.exp(-((t - 0.32) / 0.04) ** 2)
    return reverb(rustle * env * 0.5, decay=0.2)


def save(name: str, y: np.ndarray, peak=0.85) -> None:
    y = y / max(1e-6, float(np.max(np.abs(y)))) * peak
    data = (y * 32767).astype(np.int16)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / (name + ".wav")), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name}.wav {len(y) / SR:.2f}s")


def main() -> None:
    save("chime", chime(), 0.8)
    save("chalk_tap", chalk_tap(), 0.7)
    save("chalk_squeak", chalk_squeak(), 0.6)
    save("chalk_scratch", chalk_scratch(), 0.5)
    save("step_plush", step_plush(), 0.6)
    save("whistle", whistle(), 0.6)
    save("cleaner_hum", cleaner_hum(), 0.55)
    save("eraser_clap", eraser_clap(), 0.75)
    save("desk_bonk", desk_bonk(), 0.75)
    save("chalk_hit", chalk_hit(), 0.7)
    save("page_flip", page_flip(), 0.6)


if __name__ == "__main__":
    main()

"""練習（チュートリアル）の効果音を合成する（docs/new_tutorial/phase9_design.md 2章）。

外の素材は使わない（numpy と ffmpeg だけ）。48 kHz モノラル、ピーク −3 dBFS で assets/audio/sfx/practice/ に書き出す。
  practice_pop.ogg        吹き出しが出る「ぽこっ」（丸い泡がはじける。上へすべる短い音）
  practice_tick.ogg       課題の ✓「ピコン」（明るい 2 音。2 音目は長めに響く）
  practice_stamp.ogg      クリアカードのスタンプ「ポン」（ゴムの印を紙に押す：低いどすっ・紙のぱっ・丸い「ポン」）
  practice_rewind.ogg     まきもどし（0.6 秒。テープを巻き戻す「キュルルル」が速く高くなって、最後に「カチッ」）
  practice_fence.ogg      見えないさく（1-2）にはね返される「ぽよん」（ゴムのように上がってゆれる）
  practice_sign_fly.ogg   看板の壁が空へ戻る「ひゅーん」（かがむ「ぐっ」のあと、風を切る音が上へ抜ける。0.9 秒）
  practice_high_five.ogg  ハイタッチの「パチン」（手のひらの破裂音と、短い体のどん）
作り直したら、Godot のエディタでファイルを走査させる（取り込み直さないと前の音のまま鳴る）。
  python tools/audio/make_practice_sfx.py
"""
from pathlib import Path
import json
import subprocess
import tempfile
import wave

import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio/sfx/practice"


def rng(seed):
    return np.random.default_rng(seed)


def noise(n, low, high, seed):
    hz = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(rng(seed).standard_normal(n))
    spec *= np.minimum(1, hz / low) ** 4 / (1 + (hz / high) ** 6)
    y = np.fft.irfft(spec, n)
    return y / max(1e-9, np.sqrt(np.mean(y * y)))


def tone(t, hz, phase=0.0):
    """hz は定数か、t と同じ長さの配列（そのときは周波数をつないで位相を作る）。"""
    if np.isscalar(hz):
        return np.sin(2 * np.pi * hz * t + phase)
    return np.sin(2 * np.pi * np.cumsum(hz) / SR + phase)


def at(t, start):
    """start 秒からの経過（それより前は 0）と、鳴っているかの印。"""
    age = np.maximum(0.0, t - start)
    return age, (t >= start).astype(float)


def write(name, y, peak=-3.0, fade_in=0.002, fade_out=0.03):
    y = y - np.mean(y)
    k = max(1, min(int(fade_in * SR), len(y) // 4))
    y[:k] *= np.linspace(0, 1, k)
    k = max(1, min(int(fade_out * SR), len(y) // 4))
    y[-k:] *= np.linspace(1, 0, k)
    y *= 10 ** (peak / 20) / np.max(np.abs(y))
    OUT.mkdir(parents=True, exist_ok=True)
    destination = OUT / name
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / "source.wav"
        with wave.open(str(source), "wb") as f:
            f.setparams((1, 2, SR, 0, "NONE", "not compressed"))
            f.writeframes((y * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-c:a", "libvorbis", "-q:a", "7",
                        str(destination)], check=True)
    rms = float(np.sqrt(np.mean(y * y)))
    win = int(0.08 * SR)
    loud = max(float(np.sqrt(np.mean(y[i:i + win] ** 2))) for i in range(0, max(1, len(y) - win), win // 4))
    return {"path": str(destination.relative_to(ROOT)).replace("\\", "/"), "seconds": round(len(y) / SR, 3),
            "peak_dbfs": peak, "rms_dbfs": round(20 * np.log10(rms), 2), "max80ms_dbfs": round(20 * np.log10(loud), 2)}


def pop():
    # 丸い泡：380 Hz から 980 Hz へ 45 ms ですべり上がる正弦（倍音を少し）。はじけたあと、すぐ消える
    t = np.arange(int(0.13 * SR)) / SR
    sweep = 380 + 600 * (1 - np.exp(-t / 0.018))
    body = tone(t, sweep) + 0.18 * tone(t, sweep * 2.0)
    env = (1 - np.exp(-t / 0.003)) * np.exp(-t / 0.032)
    # はじける所の小さな「ぷ」（高めの短いノイズ）
    click = noise(len(t), 1500, 7000, 11) * np.exp(-t / 0.004) * 0.05
    return body * env * 0.5 + click


def tick():
    # ピ（1318 Hz、短い）→ コン（1976 Hz、少し響く）。鐘のように倍音を少し混ぜる
    t = np.arange(int(0.42 * SR)) / SR
    first = (tone(t, 1318.5) + 0.25 * tone(t, 2637.0)) * (1 - np.exp(-t / 0.002)) * np.exp(-t / 0.035)
    age, on = at(t, 0.075)
    second = (tone(age, 1975.5) + 0.22 * tone(age, 3951.0) + 0.08 * tone(age, 5926.5)) * on
    second *= (1 - np.exp(-age / 0.002)) * np.exp(-age / 0.12)
    return 0.55 * first + 0.6 * second


def stamp():
    # 低いどすっ（150→80 Hz）・紙のぱっ（短いノイズ）・丸い「ポン」（520 Hz から少し下がる）
    t = np.arange(int(0.36 * SR)) / SR
    thump = tone(t, 150 - 70 * (1 - np.exp(-t / 0.03))) * np.exp(-t / 0.05) * 0.55
    paper = noise(len(t), 350, 3200, 23) * np.exp(-t / 0.012) * 0.22
    age, on = at(t, 0.006)
    pon_hz = 560 - 80 * (1 - np.exp(-age / 0.05))
    pon = (tone(age, pon_hz) + 0.3 * tone(age, pon_hz * 2.0)) * on * (1 - np.exp(-age / 0.004)) * np.exp(-age / 0.09) * 0.35
    return thump + paper + pon


def rewind():
    # テープを巻き戻す音：速いさえずり（30 → 55 回/秒の粒）が、高さを上げながら続き、最後に「カチッ」
    seconds = 0.6
    t = np.arange(int(seconds * SR)) / SR
    u = t / seconds
    rate = 30 + 25 * u
    grain_phase = np.cumsum(rate) / SR
    grain = 0.5 - 0.5 * np.cos(2 * np.pi * grain_phase)
    # 粒ごとに少し高さが揺れる、上がっていくキュル音
    pitch = (900 + 900 * u ** 1.4) * (1 + 0.12 * np.sin(2 * np.pi * grain_phase))
    squeal = (tone(t, pitch) + 0.35 * tone(t, pitch * 1.5)) * grain ** 1.5
    whirr = noise(len(t), 600, 5000, 37) * (0.25 + 0.75 * grain) * 0.12
    env = np.minimum(1, t / 0.04) * (0.8 + 0.2 * u)
    y = (0.32 * squeal + whirr) * env
    # 終わりの「カチッ」（巻き戻しが止まる）
    age, on = at(t, seconds - 0.05)
    clack = (noise(len(t), 1200, 8000, 41) * 0.5 + tone(age, 2400)) * on * np.exp(-age / 0.006) * 0.35
    return y + clack


def fence():
    # ゴムにはね返される「ぽよん」：220 Hz から 470 Hz へ上がり、ゆれながら下がって消える（ゆれは 14 回/秒で弱まる）
    t = np.arange(int(0.38 * SR)) / SR
    base = 220 + 250 * (1 - np.exp(-t / 0.03)) - 120 * np.clip((t - 0.08) / 0.3, 0, 1)
    wobble = 1 + 0.09 * np.sin(2 * np.pi * 14 * t) * np.exp(-t / 0.12)
    hz = base * wobble
    body = tone(t, hz) + 0.3 * tone(t, hz * 2.0) + 0.08 * tone(t, hz * 3.0)
    env = (1 - np.exp(-t / 0.004)) * np.exp(-t / 0.11)
    thud = noise(len(t), 120, 900, 67) * np.exp(-t / 0.015) * 0.12
    return body * env * 0.5 + thud


def sign_fly():
    # 看板の壁が空へ戻る「ひゅーん」：はじめに軽くかがむ「ぐっ」、風を切るノイズの帯が上へすべり、細い音が上がって遠ざかる
    seconds = 0.9
    t = np.arange(int(seconds * SR)) / SR
    u = t / seconds
    windup = tone(t, 120 - 30 * u) * np.exp(-t / 0.05) * 0.25
    lift = np.clip((t - 0.12) / (seconds - 0.12), 0, 1)
    # 帯域を上げていく風：短い区間ごとに帯を変えたノイズをつなぐ
    wind = np.zeros_like(t)
    hop = int(0.03 * SR)
    for i, start in enumerate(range(0, len(t), hop)):
        end = min(len(t), start + hop * 2)
        k = start / len(t)
        center = 500 + 3500 * k ** 1.3
        part = noise(end - start, center * 0.6, center * 1.6, 70 + i) * np.hanning(end - start)
        wind[start:end] += part
    swell = np.sin(np.pi * np.clip((t - 0.08) / (seconds - 0.08), 0, 1)) ** 1.2
    whistle = tone(t, 600 + 1500 * lift ** 1.6) * swell * 0.12
    return windup + wind * swell * 0.18 + whistle


def high_five():
    # 手のひらの破裂音（広い帯域のノイズを 2 kHz あたりで強める）と、短い体のどん（210 Hz）
    t = np.arange(int(0.2 * SR)) / SR
    slap = noise(len(t), 700, 6500, 53) * np.exp(-t / 0.009)
    ring = tone(t, 1850) * np.exp(-t / 0.012) * 0.35
    body = tone(t, 210 - 60 * (1 - np.exp(-t / 0.02))) * np.exp(-t / 0.03) * 0.45
    # 手が離れるときの小さな 2 つ目の音
    age, on = at(t, 0.018)
    tail = noise(len(t), 1500, 7000, 59) * on * np.exp(-age / 0.006) * 0.25
    return slap * 0.7 + ring + body + tail


def main():
    report = [write("practice_pop.ogg", pop(), fade_out=0.02), write("practice_tick.ogg", tick()),
              write("practice_stamp.ogg", stamp()), write("practice_rewind.ogg", rewind(), fade_out=0.01),
              write("practice_fence.ogg", fence()), write("practice_sign_fly.ogg", sign_fly(), fade_in=0.004, fade_out=0.08),
              write("practice_high_five.ogg", high_five(), fade_out=0.02)]
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()

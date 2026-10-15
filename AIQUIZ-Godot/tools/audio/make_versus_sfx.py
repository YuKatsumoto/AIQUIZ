"""オンライン対戦の VS 演出（対峙）の効果音。外部の素材は使わず、ここで合成する。

    python tools/audio/make_versus_sfx.py

書き出すもの（assets/audio/sfx/online/、48 kHz ステレオ、Ogg Vorbis q7、ピーク -3 dBFS）：
  versus_cutin_in.ogg      カットインの入り（CUTIN_IN の始まりから。パネル・稲妻・白い光・VS の着地・名前の帯・札・ルール）
  versus_charge.ogg        SWAP（ゲーム画面を組み立てるあいだの溜め。開く演出が始まったら止める）
  versus_reveal.ogg        割れて開く（REVEAL 3.20 秒。稲妻が走る → 溜め → 割れる → こすれて開く → 抜ける）
  versus_reveal_short.ogg  同じ（「みじかい」演出の REVEAL 2.20 秒）

時刻はゲームと同じ数（OnlineStagingTimeline.CUTIN、SceneTransition.VERSUS_SPLIT_FX）から決める。
1 本の音で演出の全部の時刻に合わせるので、フレームが落ちても音と絵はずれない。
"""
from pathlib import Path
import json
import subprocess
import tempfile
import wave

import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio/sfx/online"
RNG = np.random.default_rng(31012)

# OnlineStagingTimeline.CUTIN（CUTIN_IN の始まりからの秒）
CUTIN = {
    "panels_end": 0.30, "bolt_start": 0.24, "bolt_end": 0.32, "vs_start": 0.42, "vs_end": 0.68,
    "names_start": 0.55, "rules_start": 0.70,
}
VS_LAND = CUTIN["vs_start"] + (CUTIN["vs_end"] - CUTIN["vs_start"]) * 0.7
# SceneTransition.VERSUS_SPLIT_FX（開く長さに対する割合）
SPLIT = {"strike_end": 0.156, "charge_start": 0.125, "burst": 0.234, "exit": 0.95, "grind_end": 0.80}


def silence(seconds):
    return np.zeros((int(seconds * SR), 2))


def times(n):
    return np.arange(n) / SR


def noise(n, low, high, seed=None):
    rng = RNG if seed is None else np.random.default_rng(seed)
    hz = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(rng.standard_normal(n))
    spec *= np.minimum(1, hz / max(low, 1)) ** 4 / (1 + (hz / high) ** 6)
    y = np.fft.irfft(spec, n)
    return y / max(1e-9, np.sqrt(np.mean(y * y)))


def sweep_noise(n, lows, highs):
    """帯域が時間で動く雑音（短い窓ごとに帯域を変えて重ね合わせる）。"""
    y = np.zeros(n)
    win = int(0.04 * SR)
    hop = win // 2
    raw = RNG.standard_normal(n + win)
    window = np.hanning(win)
    for start in range(0, n, hop):
        seg = raw[start:start + win] * window
        k = min(n - 1, start + hop)
        hz = np.fft.rfftfreq(win, 1 / SR)
        spec = np.fft.rfft(seg)
        spec *= np.minimum(1, hz / max(lows[k], 1)) ** 2 / (1 + (hz / highs[k]) ** 4)
        part = np.fft.irfft(spec, win)
        end = min(n, start + win)
        y[start:end] += part[:end - start]
    return y / max(1e-9, np.sqrt(np.mean(y * y)))


def place(buf, at, mono=None, stereo=None, pan=0.0, gain=1.0):
    """buf（ステレオ）の at 秒目に音を足す。pan は -1（左）〜 1（右）。"""
    start = int(at * SR)
    if stereo is None:
        left = np.cos((pan + 1) * np.pi / 4)
        right = np.sin((pan + 1) * np.pi / 4)
        stereo = np.stack([mono * left, mono * right], axis=1) * np.sqrt(2)
    stereo = stereo * gain
    end = min(len(buf), start + len(stereo))
    if end > start:
        buf[start:end] += stereo[:end - start]


def env(t, attack, decay):
    return np.minimum(1, t / max(attack, 1e-4)) * np.exp(-np.maximum(0, t - attack) / decay)


def whoosh(seconds, peak_at, low0, low1, high0, high1):
    n = int(seconds * SR)
    t = times(n)
    u = np.clip(t / seconds, 0, 1)
    lows = low0 + (low1 - low0) * u
    highs = high0 + (high1 - high0) * u
    y = sweep_noise(n, lows, highs)
    shape = np.where(t < peak_at, (t / peak_at) ** 2, np.exp(-(t - peak_at) / (0.25 * (seconds - peak_at) + 1e-3)))
    return y * shape


def crackle(seconds, density, seed, low=1800, high=12000):
    """電気のバチバチ：まばらなクリックを高域に通したもの。density は 1 秒あたりの数（配列なら時間で変わる）。"""
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    dens = np.broadcast_to(np.asarray(density, dtype=float), (n,))
    clicks = (rng.random(n) < dens / SR) * rng.uniform(0.3, 1.0, n) * rng.choice([-1, 1], n)
    hz = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(clicks)
    spec *= np.minimum(1, hz / low) ** 2 / (1 + (hz / high) ** 4)
    y = np.fft.irfft(spec, n)
    # クリックごとの短い響き
    kernel = np.exp(-times(int(0.004 * SR)) / 0.0012)
    y = np.convolve(y, kernel)[:n]
    return y / max(1e-9, np.max(np.abs(y)))


def buzz(seconds, hz, seed):
    """稲妻のうなり：揺れるのこぎり波＋雑音の FM。"""
    n = int(seconds * SR)
    t = times(n)
    rng = np.random.default_rng(seed)
    wobble = np.cumsum(rng.standard_normal(n)) / SR * 40
    phase = 2 * np.pi * np.cumsum(hz * (1 + 0.08 * np.sin(2 * np.pi * 31 * t)) + wobble) / SR
    saw = 2 * ((phase / (2 * np.pi)) % 1) - 1
    return 0.6 * saw + 0.4 * np.tanh(3 * np.sin(phase * 2.01))


def boom(seconds, f0, f1, decay):
    n = int(seconds * SR)
    t = times(n)
    hz = f1 + (f0 - f1) * np.exp(-t / 0.08)
    return np.sin(2 * np.pi * np.cumsum(hz) / SR) * env(t, 0.003, decay)


def clang(seconds, partials, decay):
    n = int(seconds * SR)
    t = times(n)
    y = np.zeros(n)
    for i, f in enumerate(partials):
        y += np.sin(2 * np.pi * f * t + i) * np.exp(-t / (decay / (1 + 0.35 * i))) / (1 + 0.5 * i)
    return y * np.minimum(1, t / 0.002)


def stereo_noise(n, low, high):
    return np.stack([noise(n, low, high), noise(n, low, high)], axis=1)


def write(name, y, peak=-3.0):
    y = y - np.mean(y, axis=0)
    k = int(0.002 * SR)
    y[:k] *= np.linspace(0, 1, k)[:, None]
    k = int(0.05 * SR)
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


def cutin_in():
    buf = silence(2.6)
    # パネル：左と右から入り、0.19 秒で行きすぎて止まる
    for pan, seed_gain in ((-0.75, 0.9), (0.75, 0.9)):
        place(buf, 0.0, whoosh(0.34, 0.17, 300, 1400, 1800, 7000), pan=pan, gain=0.32 * seed_gain)
    place(buf, 0.19, boom(0.25, 140, 70, 0.05) + 0.3 * noise(int(0.25 * SR), 200, 2500) * env(times(int(0.25 * SR)), 0.002, 0.02), gain=0.34)
    # 稲妻：0.24〜0.32 で上から描き、0.44 まで線がバチバチ揺れる
    n = int(0.45 * SR)
    t = times(n)
    zap_env = np.where(t < 0.08, 0.6 + 0.4 * t / 0.08, np.exp(-(t - 0.08) / 0.09))
    zap = (0.55 * crackle(0.45, 900, 7) + 0.35 * buzz(0.45, 140, 8) * np.exp(-t / 0.12) + 0.25 * noise(n, 2500, 11000) * np.exp(-t / 0.05)) * zap_env
    place(buf, CUTIN["bolt_start"], zap, gain=0.42)
    # 白い光（1 回だけ）：高いきらめき
    place(buf, CUTIN["bolt_end"], clang(0.35, [3150, 4720, 6080, 7930], 0.09), gain=0.07)
    # VS：上から落ちてくる（0.42〜）、着地（0.602）で大きな一打と金属の響き、星がはね返る
    drop_len = VS_LAND - CUTIN["vs_start"] + 0.02
    place(buf, CUTIN["vs_start"], whoosh(drop_len, drop_len * 0.95, 1800, 250, 9000, 2500), gain=0.24)
    n = int(1.6 * SR)
    t = times(n)
    slam = (1.0 * boom(1.6, 120, 46, 0.42) + 0.55 * noise(n, 60, 3500) * env(t, 0.002, 0.07)
            + 0.22 * clang(1.6, [262, 523, 1247, 1873, 2711, 3540], 0.55) + 0.12 * noise(n, 300, 2000) * env(t, 0.01, 0.35))
    place(buf, VS_LAND, np.tanh(1.4 * slam), gain=0.62)
    place(buf, VS_LAND + 0.05, clang(0.6, [1568, 2093, 3136], 0.12), pan=0.0, gain=0.06)
    # 名前の帯（左 0.55・右 0.58）と札（0.64・0.67）
    for at, pan in ((CUTIN["names_start"], -0.6), (CUTIN["names_start"] + 0.03, 0.6)):
        place(buf, at, whoosh(0.2, 0.12, 800, 2500, 4000, 9000), pan=pan, gain=0.1)
    for at, pan in ((0.64, -0.55), (0.67, 0.55)):
        m = int(0.07 * SR)
        tt = times(m)
        pop = np.sin(2 * np.pi * np.cumsum(1250 - 500 * tt / 0.07) / SR) * env(tt, 0.002, 0.018)
        place(buf, at, pop, pan=pan, gain=0.14)
    # ルールの帯が開く（0.70〜0.80）
    place(buf, CUTIN["rules_start"], whoosh(0.16, 0.09, 1500, 3000, 6000, 10000), gain=0.07)
    # 読み込みのあいだへつなぐ低いうなり（稲妻の光の粒）
    n = int(1.7 * SR)
    t = times(n)
    hum = (np.sin(2 * np.pi * 55 * t) + 0.5 * np.sin(2 * np.pi * 110 * t + 0.4)) * (1 + 0.25 * np.sin(2 * np.pi * 0.83 * t))
    hum = hum * np.minimum(1, t / 0.25) * np.exp(-t / 0.7) + 0.15 * crackle(1.7, 25, 11) * np.exp(-t / 0.6)
    place(buf, 0.85, hum, gain=0.05)
    return buf


def charge():
    """SWAP の溜め：ゲーム画面を組み立てる止まった絵のあいだ、電気が溜まっていく音を鳴らし続ける。"""
    seconds = 6.0
    n = int(seconds * SR)
    t = times(n)
    rise = np.clip(t / 3.2, 0, 1)
    rise = rise * rise * (3 - 2 * rise)
    fade = np.clip((seconds - t) / 2.0, 0, 1)
    shape = np.minimum(1, t / 0.12) * fade
    drone = (np.sin(2 * np.pi * np.cumsum(55 + 15 * rise) / SR) + 0.6 * np.sin(2 * np.pi * np.cumsum(110 + 30 * rise) / SR)
             + 0.25 * np.sin(2 * np.pi * np.cumsum(165 + 45 * rise) / SR))
    drone *= 1 + 0.3 * np.sin(2 * np.pi * (0.7 + 2.3 * rise) * t)
    energy = sweep_noise(n, 200 + 900 * rise, 900 + 4200 * rise) * (0.25 + 0.75 * rise)
    sparks = crackle(seconds, 8 + 70 * rise, 21)
    left = 0.5 * drone + 0.22 * energy + 0.3 * sparks
    right = 0.5 * drone + 0.22 * np.roll(energy, int(0.013 * SR)) + 0.3 * crackle(seconds, 8 + 70 * rise, 22)
    return np.stack([left, right], axis=1) * shape[:, None] * 0.5


def reveal(duration):
    """割れて開く（S10 v1.6）。時刻は duration に対する割合（SceneTransition.VERSUS_SPLIT_FX）。"""
    d = duration
    strike_end = SPLIT["strike_end"] * d
    charge_start = SPLIT["charge_start"] * d
    burst = SPLIT["burst"] * d
    exit_at = SPLIT["exit"] * d
    grind_end = burst + SPLIT["grind_end"] * (exit_at - burst)
    buf = silence(d + 1.2)
    # 稲妻が線を上から下へ走る：バチバチの連なりとうなり、走り終わりに小さな雷の割れ
    n = int((strike_end + 0.1) * SR)
    t = times(n)
    run = np.minimum(1, t / 0.03) * np.where(t < strike_end, 1.0, np.exp(-(t - strike_end) / 0.05))
    bolt = 0.6 * crackle(strike_end + 0.1, 1400, 31) + 0.45 * buzz(strike_end + 0.1, 180, 32) + 0.25 * noise(n, 3000, 12000)
    place(buf, 0.0, bolt * run, gain=0.36)
    place(buf, strike_end, noise(int(0.3 * SR), 150, 5000) * env(times(int(0.3 * SR)), 0.002, 0.04), gain=0.2)
    # 溜め：高くなっていく唸りと震え（charge_start〜burst）
    n = int((burst - charge_start) * SR)
    t = times(n)
    u = t / max(burst - charge_start, 1e-3)
    whine = np.sin(2 * np.pi * np.cumsum(380 + 1500 * u * u) / SR) * (1 + 0.5 * np.sin(2 * np.pi * 83 * t))
    hiss = noise(n, 2000, 9000) * u
    place(buf, charge_start, (0.5 * whine + 0.3 * hiss + 0.3 * crackle(burst - charge_start, 400 + 1500 * u, 33)) * u ** 1.5, gain=0.34)
    # 割れる：大きな破裂、低い衝撃、ガラスのような割れ、左右に広がる雑音
    n = int(2.2 * SR)
    t = times(n)
    low = boom(2.2, 150, 38, 0.55)
    crack = stereo_noise(n, 80, 9000) * env(t, 0.001, 0.09)[:, None]
    shards = clang(2.2, [2217, 3011, 3967, 5233, 6871], 0.18)
    body = np.stack([low, low], axis=1) * 0.9 + crack * 0.7 + np.stack([shards, np.roll(shards, 97)], axis=1) * 0.12
    place(buf, burst, stereo=np.tanh(1.3 * body), gain=0.6)
    # こすれながら開く：左右の半分の金属のこすれ（38 Hz で震える）と火花。開くにつれて外へ広がり、弱まる
    grind_len = grind_end - burst + 0.25
    n = int(grind_len * SR)
    t = times(n)
    fade_in = np.minimum(1, t / 0.12)
    fade_out = np.clip((grind_len - t) / (grind_len * 0.55), 0, 1)
    tremble = 0.65 + 0.35 * np.sin(2 * np.pi * 38 * t)
    for side, seed in ((-1, 41), (1, 42)):
        scrape = noise(n, 1300, 6500, seed) * tremble
        squeal = np.sin(2 * np.pi * (2900 + 180 * side) * t + 3 * np.sin(2 * np.pi * 5.3 * t)) * 0.18
        sparks = crackle(grind_len, 260 * fade_out + 30, seed + 10, 2500, 14000)
        mono = (0.5 * scrape + squeal + 0.5 * sparks) * fade_in * fade_out
        pan_track = side * (0.2 + 0.6 * np.clip(t / grind_len, 0, 1))
        stereo = np.stack([mono * np.cos((pan_track + 1) * np.pi / 4), mono * np.sin((pan_track + 1) * np.pi / 4)], axis=1) * np.sqrt(2)
        place(buf, burst + 0.03, stereo=stereo, gain=0.18)
    # 抜ける：左右の半分が速く外へ飛ぶ風切り（開ききる exit の少し前が山）
    swoosh_len = exit_at - grind_end + 0.45
    peak = exit_at - grind_end
    for pan in (-0.85, 0.85):
        place(buf, grind_end, whoosh(swoosh_len, peak, 350, 900, 2500, 6500), pan=pan, gain=0.15)
    # 余韻：低いうなりが消えていく
    n = int(1.2 * SR)
    t = times(n)
    tail = (np.sin(2 * np.pi * 48 * t) + 0.4 * np.sin(2 * np.pi * 96 * t)) * np.minimum(1, t / 0.2) * np.exp(-t / 0.5)
    place(buf, exit_at - 0.2, tail, gain=0.08)
    return buf


def main():
    report = [
        write("versus_cutin_in.ogg", cutin_in()),
        write("versus_charge.ogg", charge(), peak=-6.0),
        write("versus_reveal.ogg", reveal(3.2)),
        write("versus_reveal_short.ogg", reveal(2.2)),
    ]
    path = ROOT / "artifacts/versus_audio/assets.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2), encoding="utf8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

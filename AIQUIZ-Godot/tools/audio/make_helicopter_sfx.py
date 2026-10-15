"""Build the helicopter's mono, phase-continuous beds and short mechanical details.

Rotor source: qubodup, Freesound 187681 (CC0). All other layers are original.
Run from the project root with Python (numpy) and ffmpeg on PATH.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import wave
import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio/sfx/helicopter"
RNG = np.random.default_rng(12351)


def noise(n, low, high, periodic=False):
    spec = np.fft.rfft(RNG.standard_normal(n))
    hz = np.fft.rfftfreq(n, 1 / SR)
    spec *= np.minimum(1, hz / low) ** 4 / (1 + (hz / high) ** 6)
    y = np.fft.irfft(spec, n)
    return y / max(1e-9, np.sqrt(np.mean(y * y)))


def save(name, y, loop=False):
    y -= np.mean(y)
    if not loop:
        k = min(int(SR * .004), len(y) // 4)
        y[:k] *= np.linspace(0, 1, k)
        k = min(int(SR * .035), len(y) // 4)
        y[-k:] *= np.linspace(1, 0, k)
    # Conservative source peaks; the runtime mix has another 9-22 dB of headroom.
    y *= 10 ** (-3 / 20) / max(1e-9, np.max(np.abs(y)))
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "src.wav"
        with wave.open(str(wav), "wb") as f:
            f.setparams((1, 2, SR, 0, "NONE", "not compressed"))
            f.writeframes((y * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "7", str(OUT / (name + ".ogg"))], check=True)
    return {"seconds": len(y) / SR, "rms_dbfs": round(20 * np.log10(np.sqrt(np.mean(y*y))), 2), "loop": loop}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    report = {}
    source = ROOT / "assets/audio/sfx/source/helicopter/qubodup_187681_rotor.mp3"
    decoded = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(source), "-af", "highpass=f=65,lowpass=f=7500", "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"])
    rotor = np.frombuffer(decoded, dtype="<f4").astype(float)
    # Rotate a .30 s overlap into the head; preserve the source's blade transients.
    k = int(.30 * SR)
    u = np.linspace(0, 1, k)
    rotor[:k] = rotor[-k:] * (1-u) + rotor[:k] * u
    rotor = rotor[:-k]
    # Tame the isolated blade peaks so the sustained rotor remains readable in BGM.
    rotor = np.tanh(rotor * .9 / np.percentile(np.abs(rotor), 99.5))
    report["rotor_loop"] = save("rotor_loop", rotor, True)
    t = np.arange(4 * SR) / SR
    n = len(t)
    # All oscillators make integer cycles over four seconds, including modulation.
    turbine = .15*np.sin(2*np.pi*410*t + .35*np.sin(2*np.pi*2*t))
    turbine += .06*np.sin(2*np.pi*820*t) + .025*np.sin(2*np.pi*1230*t)
    report["turbine_loop"] = save("turbine_loop", turbine + .055*noise(n, 350, 4200, True), True)
    jet = .24*noise(n, 80, 1800, True) + .045*noise(n, 1800, 8500, True)
    jet *= .94 + .06*np.sin(2*np.pi*7*t)
    jet += .10*np.sin(2*np.pi*60*t) + .035*np.sin(2*np.pi*120*t)
    report["jet_loop"] = save("jet_loop", jet, True)
    t = np.arange(int(.68 * SR)) / SR
    blast = (.36*noise(len(t), 100, 6500)*np.exp(-t/.13)
             + .18*np.sin(2*np.pi*(83*t-32*t*t))*np.exp(-t/.12))
    report["jet_ignite"] = save("jet_ignite", blast)
    t = np.arange(int(.40*SR)) / SR
    env = np.sin(np.pi*np.clip(t/.40, 0, 1)) ** 1.2
    servo = (np.sin(2*np.pi*(190*t+90*t*t))*.12 + noise(len(t), 500, 3500)*.025)*env
    click = noise(len(t), 900, 6500)*np.exp(-t/.018)*.20
    report["hatch_open"] = save("hatch_open", servo + click)
    report["hatch_close"] = save("hatch_close", servo[::-1] + click*.60)
    t = np.arange(int(.20*SR)) / SR
    latch = (.15*np.sin(2*np.pi*175*t)+noise(len(t), 400, 6000)*.20)*np.exp(-t/.025)
    report["latch"] = save("latch", latch)
    t = np.arange(int(.16*SR)) / SR
    snap = noise(len(t), 1500, 8000)*np.exp(-t/.014)*.2
    snap += .07*np.sin(2*np.pi*950*t)*np.exp(-t/.018)
    report["belt_click"] = save("belt_click", snap)
    t = np.arange(int(.62*SR)) / SR
    rope = noise(len(t), 300, 4800)*.05*np.sin(np.pi*np.clip(t/.62, 0, 1))
    for at in [.04, .11, .22, .36, .48]:
        age = np.maximum(0, t-at)
        rope += np.where(t >= at, (.07*np.sin(2*np.pi*235*age)+.035*noise(len(t), 400, 3500))*np.exp(-age/.018), 0)
    report["rope_release"] = save("rope_release", rope)
    t = np.arange(2*SR) / SR
    winch = .10*np.sin(2*np.pi*145*t) + .04*np.sin(2*np.pi*435*t)
    winch += .045*noise(len(t), 400, 2800, True)
    report["winch_loop"] = save("winch_loop", winch, True)
    t = np.arange(int(.18*SR)) / SR
    grip = (noise(len(t), 250, 2800)*.10 + .11*np.sin(2*np.pi*165*t))*np.exp(-t/.023)
    report["grip"] = save("grip", grip)
    (ROOT / "artifacts/helicopter_audio/assets.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

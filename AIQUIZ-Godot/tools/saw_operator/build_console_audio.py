"""Deterministic console sounds for the v3 operator (no external samples).

console_horn.wav: one short two-tone toy-truck beep; the operator presses it twice.
console_switch.wav: key/START clunk (a pitched click with a low body thump).
"""
import math, random, struct, wave
from pathlib import Path

out = Path(__file__).resolve().parents[2] / 'assets/hazards/saw_operator'
rate = 44100


def write(name, samples):
    with wave.open(str(out / name), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in samples))


def horn(seconds=.19):
    data, low = [], 0.0
    for i in range(int(rate * seconds)):
        t = i / rate
        env = min(1, t / .012) * min(1, (seconds - t) / .035)
        # Two detuned saw-like voices a major third apart, softened by a one-pole low-pass.
        raw = sum(((f * t) % 1.0) * 2 - 1 for f in (466.2, 587.3, 470.0)) / 3
        low += .32 * (raw - low)
        data.append(.55 * env * low)
    return data


def switch(seconds=.16):
    rng = random.Random(20260928)
    data = []
    for i in range(int(rate * seconds)):
        t = i / rate
        click = math.exp(-t * 90) * (.6 * rng.uniform(-1, 1) + .4 * math.sin(t * math.tau * 2100))
        thump = math.exp(-t * 28) * math.sin(t * math.tau * (140 - 260 * t))
        data.append(.45 * click + .55 * thump)
    return data


write('console_horn.wav', horn())
write('console_switch.wav', switch())
print('ok')

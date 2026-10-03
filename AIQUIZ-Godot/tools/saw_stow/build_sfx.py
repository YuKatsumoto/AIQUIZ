"""Deterministic original stow warning horn: two buzzy pulses of an electric plant klaxon."""
import math, wave, struct, random
from pathlib import Path
out=Path(__file__).resolve().parents[2]/'assets/audio/sfx'
out.mkdir(parents=True,exist_ok=True)
rate=24000
duration=.78
pulses=((0.0,.30),(.40,.30)) # (start, length) seconds
rng=random.Random(311);values=[];filtered=0
for i in range(int(rate*duration)):
    t=i/rate;filtered=.86*filtered+.14*rng.uniform(-1,1)
    v=0.0
    for start,length in pulses:
        u=t-start
        if 0<=u<length:
            # Diaphragm spin-up: the pitch settles from a low growl onto the horn note.
            # Phase is the integral of f(u) = 415 * (1 - 0.1 * exp(-28 u)).
            phase=math.tau*415*(u-.10*(1-math.exp(-u*28))/28)
            # Odd harmonics of a clipped diaphragm plus a second horn a fourth above.
            v+=.30*math.sin(phase)+.13*math.sin(3*phase)+.07*math.sin(5*phase)+.035*math.sin(7*phase)
            v+=.16*math.sin(phase*4/3)+.05*math.sin(phase*4)
            v+=filtered*.10
            v*=min(1,u/.012)*min(1,(length-u)/.03)
    values.append(struct.pack('<h',round(max(-.95,min(.95,v))*32767)))
with wave.open(str(out/'stow_alarm.wav'),'wb') as f:
    f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate);f.writeframes(b''.join(values))

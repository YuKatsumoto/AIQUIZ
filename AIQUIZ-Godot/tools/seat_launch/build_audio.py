"""Deterministic locally authored latch and rocket sounds (no external samples)."""
import math, random, struct, wave
from pathlib import Path
out=Path(__file__).resolve().parents[2]/'assets/hazards/saw_operator'
rate=44100
def save(name,seconds,kind):
    rng=random.Random(260920);data=[];low=0.0
    for i in range(int(rate*seconds)):
        t=i/rate;n=rng.uniform(-1,1);low=.94*low+.06*n
        if kind=='click':
            a=math.exp(-t*65);b=math.exp(-max(0,t-.055)*95) if t>=.055 else 0
            v=.4*a*(.5*n+.5*math.sin(t*2*math.pi*1750))+.33*b*math.sin(t*2*math.pi*940)
        else:
            env=min(1,t/.07)*min(1,(seconds-t)/.15)
            v=env*(1.3*low+.1*n+.075*math.sin(t*2*math.pi*84))
        data.append(struct.pack('<h',int(max(-1,min(1,v))*32767)))
    with wave.open(str(out/name),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate);f.writeframes(b''.join(data))
save('chair_latch.wav',.20,'click')
save('chair_rocket.wav',2.0,'jet')

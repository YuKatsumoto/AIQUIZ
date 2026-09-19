"""Deterministic original mechanical layers, seamless two-second mono loops."""
import math, wave, struct, random
from pathlib import Path
out=Path(__file__).resolve().parents[2]/'assets/audio/sfx'
out.mkdir(parents=True,exist_ok=True)
rate=24000
for name,duration in [('servo',2),('spindle',2),('latch',.36)]:
    rng=random.Random(128);values=[];filtered=0
    for i in range(int(rate*duration)):
        t=i/rate;filtered=.90*filtered+.1*rng.uniform(-1,1)
        if name=='servo':
            # Loaded motor, gear mesh and restrained rolling/slat chatter.
            v=.22*math.sin(math.tau*96*t)+.10*math.sin(math.tau*192*t)+.035*math.sin(math.tau*768*t)
            v+=filtered*.24*(.6+.4*math.cos(math.tau*32*t))
        elif name=='spindle':
            v=.12*math.sin(math.tau*180*t)+.06*math.sin(math.tau*360*t)+.025*math.sin(math.tau*1080*t)+filtered*.15
        else:
            v=(.40*math.sin(math.tau*165*t)+.22*math.sin(math.tau*440*t)+filtered*.8)*math.exp(-t*23)
        # Quiet de-click edges; loop fundamental periods remain exact.
        v*=min(1,i/96,(int(rate*duration)-1-i)/96)
        values.append(struct.pack('<h',round(max(-.95,min(.95,v))*32767)))
    with wave.open(str(out/('dock_'+name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate);f.writeframes(b''.join(values))

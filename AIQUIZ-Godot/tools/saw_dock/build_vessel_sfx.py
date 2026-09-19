"""Original seamless diesel/propeller texture; no downloaded or generated media."""
import math, struct, wave
from pathlib import Path
rate=24000
duration=4
samples=[]
for i in range(rate*duration):
    t=i/rate
    pulse=.8+.2*math.cos(math.tau*12*t)
    tone=sum(a*math.sin(math.tau*f*t) for f,a in [(36,.22),(72,.13),(108,.06),(180,.025)])
    wash=.018*math.sin(math.tau*227*t+1.8*math.sin(math.tau*3*t))
    samples.append(struct.pack('<h',int(32767*(pulse*tone+wash))))
path=Path(__file__).resolve().parents[2]/'assets/audio/sfx/vessel_engine.wav'
with wave.open(str(path),'wb') as f:
    f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate);f.writeframes(b''.join(samples))

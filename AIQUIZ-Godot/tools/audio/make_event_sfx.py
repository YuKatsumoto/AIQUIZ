"""Original UI click, helicopter landing, shark bite, body burst and saw startup.

Run from any directory with Python/numpy and ffmpeg. No external samples.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import wave
import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parents[2]
RNG = np.random.default_rng(21012)


def noise(n, low, high):
    hz = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(RNG.standard_normal(n))
    spec *= np.minimum(1, hz / low) ** 4 / (1 + (hz / high) ** 6)
    y = np.fft.irfft(spec, n)
    return y / max(1e-9, np.sqrt(np.mean(y*y)))


def write(rel, y, peak=-3.0):
    y -= np.mean(y)
    k = min(int(.002*SR), len(y)//4)
    y[:k] *= np.linspace(0, 1, k)
    k = min(int(.035*SR), len(y)//4)
    y[-k:] *= np.linspace(1, 0, k)
    y *= 10**(peak/20) / np.max(np.abs(y))
    destination = ROOT / 'assets/audio/sfx' / rel
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp)/'source.wav'
        with wave.open(str(wav), 'wb') as f:
            f.setparams((1,2,SR,0,'NONE','not compressed'))
            f.writeframes((y*32767).astype('<i2').tobytes())
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','7',str(destination)], check=True)
    return {'path':str(destination.relative_to(ROOT)), 'seconds':len(y)/SR,
            'peak_dbfs':peak, 'rms_dbfs':round(float(20*np.log10(np.sqrt(np.mean(y*y)))),2)}


def main():
    report=[]
    t=np.arange(int(.095*SR))/SR
    click=(.24*np.sin(2*np.pi*720*t)*np.exp(-t/.008)
           +.09*np.sin(2*np.pi*1180*t)*np.exp(-t/.006)
           +.075*noise(len(t),800,5600)*np.exp(-t/.009))
    report.append(write('ui/click.ogg',click, -6))
    t=np.arange(int(.34*SR))/SR
    land=(.32*np.sin(2*np.pi*(100*t-28*t*t))*np.exp(-t/.045)
          +.12*noise(len(t),180,3200)*np.exp(-t/.035))
    # Second foot and clothing settle; dry floor impact instead of a metallic crash.
    age=np.maximum(0,t-.038)
    land+=np.where(t>=.038,(.20*np.sin(2*np.pi*125*age)+.065*noise(len(t),500,4000))*np.exp(-age/.022),0)
    report.append(write('game/heli_land.ogg',land))
    t=np.arange(int(.52*SR))/SR
    wet=.075*noise(len(t),280,6500)*(1-np.exp(-t/.015))*np.exp(-t/.095)
    chomp=(.22*np.sin(2*np.pi*(185*t-90*t*t))+.18*noise(len(t),650,4200))*np.exp(-t/.035)
    for at in [.055,.09,.13]:
        age=np.maximum(0,t-at)
        wet+=np.where(t>=at,.07*noise(len(t),1200,7200)*np.exp(-age/.016),0)
    report.append(write('game/shark_bite.ogg',chomp+wet))
    t=np.arange(int(.78*SR))/SR
    burst=.34*noise(len(t),80,5200)*np.exp(-t/.075)
    burst+=.28*np.sin(2*np.pi*(78*t-34*t*t))*np.exp(-t/.085)
    burst+=.05*noise(len(t),250,4500)*np.exp(-t/.16)
    for at,freq in [(.14,800),(.23,1150),(.35,620),(.47,1450)]:
        age=np.maximum(0,t-at)
        burst+=np.where(t>=at,.038*np.sin(2*np.pi*freq*age)*np.exp(-age/.014),0)
    report.append(write('game/body_burst.ogg',burst))
    duration=3.99
    t=np.arange(int((duration+.18)*SR))/SR
    u=np.clip(t/duration,0,1);ramp=u*u*(3-2*u)
    hz=100+620*ramp
    angle=2*np.pi*np.cumsum(hz)/SR
    motor=.08*np.sin(angle)+.025*np.sin(angle*2)+.012*np.sin(angle*3)
    teeth=noise(len(t),800,5500)*(.015+.06*ramp)*(.7+.3*np.sin(angle*.20)**2)
    motor=(motor+teeth)*(.15+.85*np.sqrt(ramp))
    # Electrical contactor at start, then an unbroken rise and a soft tail at full RPM.
    motor+=.055*noise(len(t),300,3000)*np.exp(-t/.018)
    motor*=np.minimum(1,np.maximum(0,(duration+.18-t)/.5))
    report.append(write('game/saw_start.ogg',motor))
    p=ROOT/'artifacts/event_audio/assets.json';p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(report,indent=2),encoding='utf8')
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main()

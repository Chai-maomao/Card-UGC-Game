"""Original CARDEX procedural audio. Python standard library, no samples.
Run from repository root; output deterministic mono PCM16 WAV at 22050 Hz.
"""
from pathlib import Path
import math, random, struct, wave
RATE = 22050
ROOT = Path(__file__).resolve().parents[1] / "res" / "audio"
SPECS = {"death": (.42,110,.8)}
def write(name, samples):
    scale = .50 / max(max(map(abs,samples)), 1e-9)
    pcm = [int(x*scale*32767) for x in samples]
    with wave.open(str(ROOT/(name+".wav")), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(struct.pack("<"+"h"*len(pcm), *pcm))
def main():
    ROOT.mkdir(exist_ok=True)
    for name, (duration,freq,noise) in SPECS.items():
        rng=random.Random(310+len(name))
        data=[]
        for i in range(int(RATE*duration)):
            t=i/RATE; u=t/duration
            envelope=min(1,t/.008)*(1-u)**2
            f=freq*(1-.35*u) if noise else freq
            tone=math.sin(2*math.pi*f*t)+.28*math.sin(2*math.pi*f*1.5*t)
            data.append(envelope*(tone*(1-.6*noise)+noise*(rng.random()*2-1)*.55))
        write(name,data)
if __name__ == "__main__": main()

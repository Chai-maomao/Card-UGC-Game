"""A short, quiet low resource-denial cue. No third-party samples."""
import math,struct,wave
from pathlib import Path
rate=44100
samples=[]
for i in range(int(rate*0.17)):
 t=i/rate
 envelope=min(1,t/0.012)*min(1,(0.17-t)/0.055)
 tone=math.sin(2*math.pi*155*t)+0.10*math.sin(2*math.pi*310*t)
 samples.append(struct.pack('<h',int(0.22*envelope*tone*32767)))
with wave.open(str(Path(__file__).resolve().parents[1]/'res/audio/denied.wav'),'wb') as output:
 output.setparams((1,2,rate,0,'NONE','not compressed'))
 output.writeframes(b''.join(samples))

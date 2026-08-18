#!/usr/bin/env python3
import math

def D(t): return t-math.sin(t)*math.cos(t)
def geom(area,deg):
    t=math.radians(deg); r=math.sqrt(area/D(t))
    yc=-r*math.cos(t)+(2*r*math.sin(t)**3)/(3*D(t))
    return r,2*r*math.sin(t),r*(1-math.cos(t)),yc
R0=.25; A90=R0*R0*D(math.pi/2)
ok=True
for deg in (60,90,120):
    r,w,h,y=geom(A90,deg)
    print(f"[0493x9p-mapcheck] from90 target={deg} R={r:.9g} footprint={w:.9g} height={h:.9g} yCM={y:.9g}")
    ok &= r>0 and w>0 and h>0 and y>0
print(f"[0493x9p-mapcheck] A90={A90:.12g} status={'PASS' if ok else 'FAIL'}")
raise SystemExit(0 if ok else 2)

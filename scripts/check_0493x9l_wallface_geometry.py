#!/usr/bin/env python3
import math

def rot(v, a):
    x,y=v; c=math.cos(a); s=math.sin(a)
    return (c*x-s*y, s*x+c*y)

def norm(v):
    g=math.hypot(*v); return (v[0]/g,v[1]/g)

def signed_delta(a,b):
    return math.atan2(a[0]*b[1]-a[1]*b[0], a[0]*b[0]+a[1]*b[1])

ok=True
for theta in (30,45,60,75,90,105,120,135,150):
    # bottom wall: nWall=(0,-1), tangent=(1,0); take right-hand branch.
    th=math.radians(theta)
    target=norm((math.sin(th), math.cos(th)))  # dot with wall = -cos(theta)
    # Synthetic interior normal rotated +12 deg from the exact wall-face normal.
    n2=rot(target, math.radians(12.0))
    d=signed_delta(target,n2)
    n0=rot(target,d/3.0)
    ng=rot(target,-d/3.0)
    face=norm((n0[0]+ng[0], n0[1]+ng[1]))
    wall=(0.0,-1.0)
    measured=math.degrees(math.acos(max(-1.0,min(1.0,-(face[0]*wall[0]+face[1]*wall[1])))))
    unit=max(abs(math.hypot(*n0)-1.0),abs(math.hypot(*ng)-1.0))
    passed=abs(measured-theta)<1e-12 and unit<1e-12
    ok &= passed
    print(f"[0493x9l-mapcheck] theta={theta} face={measured:.12g} deltaDeg={math.degrees(d):+.6f} unitErr={unit:.3e} pass={int(passed)}")
print(f"[0493x9l-mapcheck] status={'PASS' if ok else 'FAIL'}")
raise SystemExit(0 if ok else 2)

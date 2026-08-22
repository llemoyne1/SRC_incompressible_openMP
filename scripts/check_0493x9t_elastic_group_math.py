#!/usr/bin/env python3
"""Deterministic CPU check of the exact two-group x9t velocity transform."""
import math
import random

rng = random.Random(493910)
max_dp = 0.0
max_de = 0.0
cases = 0
for _ in range(20000):
    nc = rng.randint(1, 8)
    nr = rng.randint(1, 24)
    phi = rng.uniform(-math.pi, math.pi)
    nx, ny = math.cos(phi), math.sin(phi)
    cand = [(rng.gauss(0.8, 0.6), rng.gauss(0.0, 0.6), rng.uniform(0.5, 2.0)) for _ in range(nc)]
    recv = [(rng.gauss(-0.2, 0.6), rng.gauss(0.0, 0.6), rng.uniform(0.5, 2.0)) for _ in range(nr)]
    mc = sum(m for _,_,m in cand); mr = sum(m for _,_,m in recv)
    ucx = sum(m*x for x,y,m in cand)/mc; ucy = sum(m*y for x,y,m in cand)/mc
    urx = sum(m*x for x,y,m in recv)/mr; ury = sum(m*y for x,y,m in recv)/mr
    g = (ucx-urx)*nx + (ucy-ury)*ny
    if g <= 0: continue
    d_uc = -2.0*mr/(mc+mr)*g
    d_ur =  2.0*mc/(mc+mr)*g
    before = cand + recv
    after = []
    for x,y,m in cand:
        devn=(x-ucx)*nx+(y-ucy)*ny
        after.append((x+(-2*devn+d_uc)*nx, y+(-2*devn+d_uc)*ny, m))
    for x,y,m in recv:
        after.append((x+d_ur*nx, y+d_ur*ny, m))
    p0x=sum(m*x for x,y,m in before); p0y=sum(m*y for x,y,m in before)
    p1x=sum(m*x for x,y,m in after); p1y=sum(m*y for x,y,m in after)
    e0=.5*sum(m*(x*x+y*y) for x,y,m in before)
    e1=.5*sum(m*(x*x+y*y) for x,y,m in after)
    max_dp=max(max_dp, math.hypot(p1x-p0x,p1y-p0y))
    max_de=max(max_de, abs(e1-e0))
    cases += 1

ok = cases > 1000 and max_dp < 1e-11 and max_de < 1e-11
print(f"[0493x9t-math] cases={cases} maxDeltaP={max_dp:.3e} maxDeltaKE={max_de:.3e}")
print(f"[0493x9t-math] status={'PASS' if ok else 'FAIL'}")
raise SystemExit(0 if ok else 2)

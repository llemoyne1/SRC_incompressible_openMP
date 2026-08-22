#!/usr/bin/env python3
import math
import random

rng = random.Random(49310)
max_p = 0.0
max_e = 0.0

for _ in range(2000):
    nd = rng.randint(1, 40)
    nr = rng.randint(2, 80)
    donors = []
    A = Sx = Sy = H = 0.0
    for _ in range(nd):
        m = 0.2 + 2.0*rng.random()
        ang = 2.0*math.pi*rng.random()
        nx, ny = math.cos(ang), math.sin(ang)
        ubx = -0.4 + 0.8*rng.random()
        uby = -0.4 + 0.8*rng.random()
        g = 0.02 + 1.5*rng.random()
        tang = -1.0 + 2.0*rng.random()
        tx, ty = -ny, nx
        vx = ubx + g*nx + tang*tx
        vy = uby + g*ny + tang*ty
        donors.append((m,vx,vy,g,nx,ny))
        A += m*g*g
        Sx += m*g*nx
        Sy += m*g*ny
        H += m*g*(vx*nx + vy*ny)

    receivers = []
    mr = prx = pry = 0.0
    for _ in range(nr):
        m = 0.2 + 2.0*rng.random()
        vx = -0.8 + 1.6*rng.random()
        vy = -0.8 + 1.6*rng.random()
        receivers.append((m,vx,vy))
        mr += m
        prx += m*vx
        pry += m*vy

    urx, ury = prx/mr, pry/mr
    B = (Sx*Sx + Sy*Sy)/mr
    denom = A+B
    numer = 2.0*(H - (urx*Sx + ury*Sy))
    a = numer/denom if denom > 0.0 else 0.0
    if not (a > 0.0 and math.isfinite(a)):
        a = 0.0
    dux, duy = a*Sx/mr, a*Sy/mr

    p0x = p0y = e0 = 0.0
    p1x = p1y = e1 = 0.0
    for m,vx,vy,g,nx,ny in donors:
        nvx = vx-a*g*nx
        nvy = vy-a*g*ny
        p0x += m*vx; p0y += m*vy
        p1x += m*nvx; p1y += m*nvy
        e0 += 0.5*m*(vx*vx+vy*vy)
        e1 += 0.5*m*(nvx*nvx+nvy*nvy)
    for m,vx,vy in receivers:
        nvx = vx+dux
        nvy = vy+duy
        p0x += m*vx; p0y += m*vy
        p1x += m*nvx; p1y += m*nvy
        e0 += 0.5*m*(vx*vx+vy*vy)
        e1 += 0.5*m*(nvx*nvx+nvy*nvy)

    max_p = max(max_p, abs(p1x-p0x), abs(p1y-p0y))
    max_e = max(max_e, abs(e1-e0))

print(f'maxMomentumResidual={max_p:.3e}')
print(f'maxEnergyResidual={max_e:.3e}')
if max_p > 1e-10 or max_e > 1e-10:
    raise SystemExit('status=FAIL')
print('status=PASS')

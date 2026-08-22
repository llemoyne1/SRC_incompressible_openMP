#!/usr/bin/env python3
import math
import random

rng = random.Random(4931013)
max_rel_e = 0.0
max_final_side = 0.0
max_impulse = 0.0
released = 0
hits = 0
for _ in range(200000):
    ang = rng.uniform(-math.pi, math.pi)
    nx, ny = math.cos(ang), math.sin(ang)
    wall_vn = rng.uniform(-0.3, 0.3)
    # Particle starts on liquid side at signed distance d<0.
    s0 = -rng.uniform(0.0, 0.004)
    tang = rng.uniform(-0.002, 0.002)
    tx, ty = -ny, nx
    x0 = s0*nx + tang*tx
    y0 = s0*ny + tang*ty
    vn = wall_vn + rng.uniform(-0.2, 0.8)
    vt = rng.uniform(-0.5, 0.5)
    vx, vy = vn*nx + vt*tx, vn*ny + vt*ty
    dt = 0.002
    rel = vn-wall_vn
    if rel <= 0:
        continue
    thit = -s0/rel
    stationary_hit = vn > 0 and (-s0/vn) <= dt
    if not (0 <= thit <= dt):
        if stationary_hit:
            released += 1
        continue
    hits += 1
    nvx = vx - 2*rel*nx
    nvy = vy - 2*rel*ny
    wvx, wvy = wall_vn*nx, wall_vn*ny
    eb = (vx-wvx)**2 + (vy-wvy)**2
    ea = (nvx-wvx)**2 + (nvy-wvy)**2
    max_rel_e = max(max_rel_e, abs(ea-eb))
    xf = x0 + vx*thit + nvx*(dt-thit)
    yf = y0 + vy*thit + nvy*(dt-thit)
    qfx, qfy = wall_vn*nx*dt, wall_vn*ny*dt
    sf = (xf-qfx)*nx + (yf-qfy)*ny
    max_final_side = max(max_final_side, sf)
    m = rng.uniform(.5, 2.0)
    jx, jy = 2*m*rel*nx, 2*m*rel*ny
    # Particle momentum change + wall impulse must cancel identically.
    rx = m*(nvx-vx) + jx
    ry = m*(nvy-vy) + jy
    max_impulse = max(max_impulse, math.hypot(rx,ry))

print(f'hits={hits} stationaryOldCrossingsReleasedByMovingWall={released}')
print(f'maxRelativeSpeedSqError={max_rel_e:.12e}')
print(f'maxFinalRelativeOutside={max_final_side:.12e}')
print(f'maxParticlePlusWallImpulseResidual={max_impulse:.12e}')
if max_rel_e > 1e-12 or max_final_side > 1e-12 or max_impulse > 1e-12:
    raise SystemExit('status=FAIL')
print('status=PASS')

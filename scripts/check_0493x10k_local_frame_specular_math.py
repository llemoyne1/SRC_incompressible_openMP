#!/usr/bin/env python3
import math
import random
rng = random.Random(4931012)
max_rel_e = 0.0
max_g_res = 0.0
nonzero_lab_work = 0
for _ in range(200000):
    a = rng.uniform(-math.pi, math.pi)
    nx, ny = math.cos(a), math.sin(a)
    ubx, uby = rng.uniform(-1,1), rng.uniform(-1,1)
    # Build an outward relative velocity so the donor gate is satisfied.
    tx, ty = -ny, nx
    gn = rng.uniform(1.0e-6, 2.0)
    gt = rng.uniform(-2.0, 2.0)
    vx = ubx + gn*nx + gt*tx
    vy = uby + gn*ny + gt*ty
    wx = vx - 2.0*gn*nx
    wy = vy - 2.0*gn*ny
    rb = (vx-ubx)**2 + (vy-uby)**2
    ra = (wx-ubx)**2 + (wy-uby)**2
    ga = (wx-ubx)*nx + (wy-uby)*ny
    max_rel_e = max(max_rel_e, abs(ra-rb))
    max_g_res = max(max_g_res, abs(ga + gn))
    lab_before = vx*vx + vy*vy
    lab_after = wx*wx + wy*wy
    if abs(lab_after-lab_before) > 1.0e-12:
        nonzero_lab_work += 1
print(f"maxRelativeSpeedSqError={max_rel_e:.12e}")
print(f"maxRelativeNormalReflectionResidual={max_g_res:.12e}")
print(f"casesWithNonzeroLabSpeedSqChange={nonzero_lab_work}")
ok = max_rel_e < 1.0e-12 and max_g_res < 1.0e-12 and nonzero_lab_work > 0
print("status=" + ("PASS" if ok else "FAIL"))
if not ok:
    raise SystemExit(2)

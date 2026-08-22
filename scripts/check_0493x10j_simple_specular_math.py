#!/usr/bin/env python3
import math
import random
rng = random.Random(4931011)
mx = 0.0
for _ in range(200000):
    a = rng.uniform(-math.pi, math.pi)
    nx, ny = math.cos(a), math.sin(a)
    vx, vy = rng.uniform(-3,3), rng.uniform(-3,3)
    vn = vx*nx + vy*ny
    wx = vx - 2.0*vn*nx
    wy = vy - 2.0*vn*ny
    e = abs((wx*wx+wy*wy) - (vx*vx+vy*vy))
    mx = max(mx, e)
print(f"maxSpeedSqError={mx:.12e}")
print("status=" + ("PASS" if mx < 1.0e-12 else "FAIL"))
if mx >= 1.0e-12:
    raise SystemExit(2)

#!/usr/bin/env python3
import math, random

rng = random.Random(49390024)
max_err = 0.0
for _ in range(20000):
    x0 = rng.uniform(-3.0, 3.0)
    v0 = rng.uniform(-2.0, 2.0)
    v1 = rng.uniform(-2.0, 2.0)
    dt = 10.0 ** rng.uniform(-4.0, -1.0)
    s = rng.random()
    xpre = x0 + s * dt * (v0 - v1)
    got = xpre + v1 * dt
    expected = x0 + v0 * s * dt + v1 * (1.0 - s) * dt
    max_err = max(max_err, abs(got - expected))

print("===== 0493x9x CROSSING-TIME POSITION IDENTITY =====")
print(f"cases=20000 maxAbsError={max_err:.3e}")
if max_err > 5e-15:
    raise SystemExit("status=FAIL")
print("status=PASS")

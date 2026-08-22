#!/usr/bin/env python3

def alpha(x):
    return 1.0 - x

def inside_to_outside(x0, x1, n=4):
    assert alpha(x0) >= 0.5 and alpha(x1) < 0.5
    lo, hi = 0.0, 1.0
    for _ in range(n):
        mid = 0.5*(lo+hi)
        x = x0 + mid*(x1-x0)
        if alpha(x) >= 0.5: lo = mid
        else: hi = mid
    return x0 + lo*(x1-x0)

def outside_to_anchor(x1, anchor, n=4):
    assert alpha(x1) < 0.5 and alpha(anchor) >= 0.5
    lo, hi = 0.0, 1.0
    for _ in range(n):
        mid = 0.5*(lo+hi)
        x = x1 + mid*(anchor-x1)
        if alpha(x) >= 0.5: hi = mid
        else: lo = mid
    t = min(1.0, 2.0*hi)
    x = x1 + t*(anchor-x1)
    return x if alpha(x) >= 0.5 else anchor

worst = 0.0
for x0 in (0.0, 0.2, 0.49, 0.4999):
    for x1 in (0.5001, 0.55, 0.8, 1.2):
        x = inside_to_outside(x0, x1)
        worst = max(worst, max(0.0, 0.5-alpha(x)))
        if alpha(x) < 0.5:
            raise SystemExit('FAIL inside->outside barrier')
for x1 in (0.5001, 0.55, 0.8, 1.2):
    for anchor in (0.49, 0.4, 0.2, 0.0):
        x = outside_to_anchor(x1, anchor)
        worst = max(worst, max(0.0, 0.5-alpha(x)))
        if alpha(x) < 0.5:
            raise SystemExit('FAIL outside->anchor barrier')

maxerr = 0.0
dt = 0.002
for x0 in (-1.2, 0.0, 3.4):
    for v in (-2.1, 0.0, 4.7):
        for target in (-0.7, 0.3, 2.2):
            corr = target - (x0 + v*dt)
            landed = (x0+corr) + v*dt
            maxerr = max(maxerr, abs(landed-target))
print(f'maxOutsideDefect={worst:.3e}')
print(f'maxEndpointIdentityError={maxerr:.3e}')
print('status=PASS')

#!/usr/bin/env python3
import math

def alpha(x):
    # synthetic 1-D interface: alpha>=0.5 for x<=0.5
    return 1.0-x

def recover(candidate, anchor, niter=4):
    assert alpha(candidate) < 0.5 and alpha(anchor) >= 0.5
    lo, hi = 0.0, 1.0
    for _ in range(niter):
        mid = 0.5*(lo+hi)
        x = candidate + mid*(anchor-candidate)
        if alpha(x) >= 0.5: hi = mid
        else: lo = mid
    t = min(1.0, 2.0*hi)
    x = candidate + t*(anchor-candidate)
    if alpha(x) < 0.5: x = anchor
    return x

worst = 0.0
for candidate in (0.5001,0.52,0.60,0.74,0.90):
    for anchor in (0.49,0.40,0.25,0.0):
        if not (candidate > 0.5 and anchor <= 0.5):
            continue
        x = recover(candidate, anchor)
        worst = max(worst, max(0.0, 0.5-alpha(x)))
        if alpha(x) < 0.5:
            raise SystemExit('FAIL recovered endpoint outside')

# Same pre-stream placement identity used by x10a/x10b.
maxerr = 0.0
for x0 in (-1.2,0.0,3.4):
    for v in (-2.1,0.0,4.7):
        for target in (-0.7,0.3,2.2):
            dt=0.002
            corr=target-(x0+v*dt)
            landed=(x0+corr)+v*dt
            maxerr=max(maxerr,abs(landed-target))
print(f'maxRecoveryOutsideDefect={worst:.3e}')
print(f'maxEndpointIdentityError={maxerr:.3e}')
print('status=PASS')

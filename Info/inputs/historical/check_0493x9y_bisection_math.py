#!/usr/bin/env python3
import random
rng=random.Random(49399); worst=0.0
for _ in range(20000):
    true_s=rng.random(); lo=0.0; hi=1.0
    for _ in range(4):
        mid=0.5*(lo+hi)
        if mid<=true_s: lo=mid
        else: hi=mid
    if lo>true_s+1e-15: raise SystemExit('FAIL: last-inside crossed outside')
    worst=max(worst,true_s-lo)
print(f'max(true_s-last_inside)={worst:.12g}')
print('bound=0.0625')
print('status=' + ('PASS' if worst<=0.0625+1e-15 else 'FAIL'))

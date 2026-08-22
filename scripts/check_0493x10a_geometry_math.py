#!/usr/bin/env python3
# Pure geometry identity used by the pre-stream position correction.
# x_pre' = x_target - v_new*dt  => ordinary streaming lands at x_target.
import random, math
rng=random.Random(493100)
worst=0.0
for _ in range(20000):
    x0=rng.uniform(-2,2); y0=rng.uniform(-2,2)
    ovx=rng.uniform(-3,3); ovy=rng.uniform(-3,3)
    nvx=rng.uniform(-3,3); nvy=rng.uniform(-3,3)
    dt=10**rng.uniform(-4,-1); s=rng.random()
    xi=x0+s*ovx*dt; yi=y0+s*ovy*dt
    # emulate an arbitrary last-inside fraction t on reflected segment
    t=rng.random()
    xc=xi+(1-s)*nvx*dt; yc=yi+(1-s)*nvy*dt
    xt=xi+t*(xc-xi); yt=yi+t*(yc-yi)
    xpre=xt-nvx*dt; ypre=yt-nvy*dt
    xf=xpre+nvx*dt; yf=ypre+nvy*dt
    worst=max(worst,abs(xf-xt),abs(yf-yt))
print(f'maxEndpointIdentityError={worst:.3e}')
print('status=' + ('PASS' if worst < 1e-14 else 'FAIL'))

#!/usr/bin/env python3
"""Deterministic unit check of the x9k sheared-mirror mapping."""
import math

def ratio(theta_deg, gt):
    th=math.radians(theta_deg)
    if not (0.0 < theta_deg < 180.0):
        raise ValueError('open interval required')
    return (1.0 if gt>0 else -1.0)*math.cos(th)/math.sin(th)

def check(theta, sign):
    th=math.radians(theta)
    gt=sign*math.sin(th)
    gn=math.cos(th)
    r=ratio(theta,gt)
    # s is positive from fluid to solid.  A linear alpha = gt*t + gn*s
    # must be reproduced exactly by the shifted mirror for every ghost depth.
    for layer in (1,2,3,5):
        d=layer-0.5
        sep=2.0*d
        shift=sep*r
        ghost=gn*d
        mirror=gt*shift + gn*(-d)
        if abs(ghost-mirror)>2e-13:
            raise SystemExit(f'[0493x9k-mapcheck] FAIL theta={theta} sign={sign} layer={layer} err={ghost-mirror}')
    return r

for theta in (60.0,90.0,120.0):
    rp=check(theta,+1.0); rm=check(theta,-1.0)
    if abs(rp+rm)>1e-14:
        raise SystemExit('[0493x9k-mapcheck] FAIL tangent branch antisymmetry')
    if theta==90.0 and max(abs(rp),abs(rm))>1e-14:
        raise SystemExit('[0493x9k-mapcheck] FAIL theta=90 must be pure mirror')
    print(f'[0493x9k-mapcheck] theta={theta:g} ratio(+/-)=({rp:+.8g},{rm:+.8g}) pass=1')
print('[0493x9k-mapcheck] status=PASS')

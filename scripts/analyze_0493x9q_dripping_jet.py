#!/usr/bin/env python3
"""Exploratory 0493x9q jet/drop diagnostics.

This is deliberately not a physics PASS/FAIL checker.  It summarizes the
existing x9e/x9f diagnostics so visual LiveVis observations can be tied to
liquid inventory, COM motion, global moments and interface activity.
"""
from __future__ import annotations
import argparse
import csv
import math
from pathlib import Path


def read_rows(path: Path):
    if not path.exists():
        return []
    with path.open(newline='') as f:
        return list(csv.DictReader(f))


def fval(row, key, default=float('nan')):
    try:
        return float(row[key])
    except Exception:
        return default


def mean(vals):
    vals=[v for v in vals if math.isfinite(v)]
    return sum(vals)/len(vals) if vals else float('nan')


def slope(xs, ys):
    pts=[(x,y) for x,y in zip(xs,ys) if math.isfinite(x) and math.isfinite(y)]
    if len(pts)<2: return float('nan')
    xm=sum(x for x,_ in pts)/len(pts); ym=sum(y for _,y in pts)/len(pts)
    den=sum((x-xm)**2 for x,_ in pts)
    if den<=0: return 0.0
    return sum((x-xm)*(y-ym) for x,y in pts)/den


def summarize_case(root: Path, name: str):
    out=root/name/'output'
    shape=read_rows(out/'cuda_ellipse_shape_0493x9f.csv')
    pressure=read_rows(out/'cuda_static_drop_pressure_0493x9e.csv')
    velocity=read_rows(out/'cuda_static_drop_velocity_0493x9e.csv')
    if not shape:
        print(f'[0493x9q-check] case={name} missing x9f shape diagnostics: {out}')
        return None
    tailn=max(3, len(shape)//5)
    tail=shape[-tailn:]
    first=shape[0]; last=shape[-1]
    times=[fval(r,'time') for r in shape]
    masses=[fval(r,'liquidMass') for r in shape]
    particles=[fval(r,'liquidParticles') for r in shape]
    ycms=[fval(r,'yCM') for r in shape]
    xcms=[fval(r,'xCM') for r in shape]
    mass_slope=slope(times,masses)
    y_slope=slope(times[-tailn:],ycms[-tailn:])
    x0=xcms[0] if xcms else float('nan')
    axis=mean([fval(r,'axisRatio') for r in tail])
    ell=mean([fval(r,'ellipticity') for r in tail])
    rmaj=mean([fval(r,'momentRadiusMajor') for r in tail])
    rmin=mean([fval(r,'momentRadiusMinor') for r in tail])
    p_tail=pressure[-max(1,min(tailn,len(pressure))):] if pressure else []
    v_tail=velocity[-max(1,min(tailn,len(velocity))):] if velocity else []
    alpha=mean([fval(r,'alphaArea') for r in p_tail]) if p_tail else float('nan')
    kappa=mean([fval(r,'curvatureMean') for r in p_tail]) if p_tail else float('nan')
    kjump=mean([fval(r,'measuredPressureJump') for r in p_tail]) if p_tail else float('nan')
    uint=mean([fval(r,'interfaceSpeedRms') for r in v_tail]) if v_tail else float('nan')
    print(f'[0493x9q-check] case={name} rows={len(shape)} t=[{times[0]:.4g},{times[-1]:.4g}] liquidParticles={particles[0]:.0f}->{particles[-1]:.0f} liquidMass={masses[0]:.6g}->{masses[-1]:.6g} dM/dt={mass_slope:.6g}')
    print(f'[0493x9q-check]   xCM={xcms[-1]:.6g} drift={xcms[-1]-x0:+.4g} yCM={ycms[-1]:.6g} tailDy/dt={y_slope:+.4g} momentR=({rmaj:.5g},{rmin:.5g}) axisRatio={axis:.4g} ellipticity={ell:.4g}')
    print(f'[0493x9q-check]   alphaAreaTail={alpha:.6g} curvatureMeanTail={kappa:.6g} pressureJumpTail={kjump:.6g} interfaceSpeedRmsTail={uint:.6g}')
    return dict(name=name, mass=masses[-1], particles=particles[-1], ycm=ycms[-1], xdrift=xcms[-1]-x0,
                axis=axis, ell=ell, alpha=alpha, kappa=kappa, pjump=kjump, uint=uint)


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, required=True)
    ap.add_argument('--cases', nargs='+', required=True)
    args=ap.parse_args()
    metrics=[]
    for name in args.cases:
        m=summarize_case(args.root,name)
        if m: metrics.append(m)
    by={m['name']:m for m in metrics}
    if 'capillary' in by and 'sigma0' in by:
        a=by['capillary']; b=by['sigma0']
        print('[0493x9q-paired] exploratory comparison only; no hard physics gate')
        print(f"[0493x9q-paired]   capillaryMinusSigma0: yCM={a['ycm']-b['ycm']:+.5g} axisRatio={a['axis']-b['axis']:+.5g} ellipticity={a['ell']-b['ell']:+.5g} interfaceSpeed={a['uint']-b['uint']:+.5g}")
    print('[0493x9q-check] status=COMPLETE_VISUAL_REVIEW_REQUIRED')
    return 0

if __name__=='__main__':
    raise SystemExit(main())

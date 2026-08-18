#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import math
from collections import defaultdict
from pathlib import Path


def last_csv(path: Path):
    if not path.exists():
        raise SystemExit(f"[0493x9n-check] missing {path}")
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"[0493x9n-check] empty {path}")
    return rows[-1]


def fv(row, key):
    return float(row[key])


def iv(row, key):
    return int(float(row[key]))


def origin_fit(points):
    # y = slope*x, plus conventional R2 around mean(y) for information.
    sxx = sum(x*x for x,y in points)
    slope = sum(x*y for x,y in points)/sxx if sxx else float('nan')
    ybar = sum(y for x,y in points)/len(points)
    ssres = sum((y-slope*x)**2 for x,y in points)
    sst = sum((y-ybar)**2 for x,y in points)
    r2 = 1.0-ssres/sst if sst>0 else float('nan')
    return slope,r2


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',type=Path,required=True)
    args=ap.parse_args()
    metas=sorted(args.root.glob('**/init/geometry_0493x9n.smpcd.json'))
    if not metas:
        raise SystemExit(f"[0493x9n-check] no geometry metadata below {args.root}")

    overall=True
    rows_out=[]
    family_ok=defaultdict(lambda: True)
    circle_points=defaultdict(list)

    for mp in metas:
        meta=json.loads(mp.read_text())
        case_id=meta.get('caseId') or str(mp.parent.parent.relative_to(args.root))
        case_dir=mp.parent.parent
        out=last_csv(case_dir/'output'/'cuda_contact_angle_offsupport_0493x9m.csv')
        shape=meta['shape']
        theta=float(meta['contactAngleDegrees'])
        exact=float(meta['exactContactCurvature'])
        ideal=float(meta.get('exactSecantCurvatureAnchor4p5h',exact))
        raw=fv(out,'rawAngleMean'); measured=fv(out,'correctedAngleMean')
        angle_rms=fv(out,'correctedAngleErrorRms'); dot_rms=fv(out,'correctedDotErrorRms')
        cand=iv(out,'candidateCells'); corr=iv(out,'correctedCells')
        k=fv(out,'contactCurvatureMean'); ks=fv(out,'contactCurvatureStd')
        angle_pass=(cand>0 and corr==cand and abs(measured-theta)<=2.0 and angle_rms<=3.0)
        if shape=='plane-wedge':
            curvature_metric=abs(k)
            curvature_pass=curvature_metric<=0.5
            noise_pass=ks<=0.5
            rel=float('nan')
            print(f"[0493x9n-check] case={case_id} shape=plane theta={theta:g} rawMean={raw:.8g} contactMean={measured:.8g} angleRms={angle_rms:.3e} candidates={cand}/{corr} anglePass={int(angle_pass)}")
            print(f"[0493x9n-check]   kappa={k:.8g} exact=0 absError={abs(k):.6g} std={ks:.8g} zeroPass={int(curvature_pass)} noisePass={int(noise_pass)}")
        else:
            rel=(k-exact)/exact
            sec_rel=(k-ideal)/ideal if ideal else float('nan')
            curvature_pass=abs(rel)<=0.10
            noise_limit=max(0.5,0.15*abs(exact))
            noise_pass=ks<=noise_limit
            print(f"[0493x9n-check] case={case_id} shape={shape} theta={theta:g} rawMean={raw:.8g} contactMean={measured:.8g} angleRms={angle_rms:.3e} candidates={cand}/{corr} anglePass={int(angle_pass)}")
            print(f"[0493x9n-check]   kappa={k:.8g} exactLocal={exact:.8g} relBias={100*rel:+.3f}% std={ks:.8g} curvaturePass={int(curvature_pass)} noisePass={int(noise_pass)}")
            if shape=='ellipse':
                ideal_bias=(ideal-exact)/exact
                print(f"[0493x9n-check]   idealX9mSecant={ideal:.8g} idealVsLocal={100*ideal_bias:+.3f}% measuredVsIdeal={100*sec_rel:+.3f}%")
            if shape=='circle':
                circle_points[theta].append((exact,k))
        passed=angle_pass and curvature_pass and noise_pass
        family_ok[shape] &= passed
        overall &= passed
        print(f"[0493x9n-check]   pass={int(passed)}")
        rows_out.append({
            'caseId':case_id,'shape':shape,'thetaDegrees':theta,
            'candidateCells':cand,'correctedCells':corr,'rawAngleMean':raw,
            'contactAngleMean':measured,'angleErrorRms':angle_rms,'dotErrorRms':dot_rms,
            'exactLocalCurvature':exact,'idealX9mSecantCurvature':ideal,
            'measuredCurvature':k,'curvatureStd':ks,
            'relativeBiasLocal':rel,'anglePass':int(angle_pass),
            'curvaturePass':int(curvature_pass),'noisePass':int(noise_pass),'pass':int(passed),
        })

    for theta in sorted(circle_points):
        pts=sorted(circle_points[theta],reverse=True)
        slope,r2=origin_fit(pts)
        scaling_pass=(0.90<=slope<=1.10 and r2>=0.98)
        overall &= scaling_pass
        family_ok['circle'] &= scaling_pass
        print(f"[0493x9n-scaling] theta={theta:g} measuredKappa=slope*(1/R) slope={slope:.6g} R2={r2:.6g} pass={int(scaling_pass)}")

    summary=args.root/'x9n_geometry_summary.csv'
    with summary.open('w',newline='') as f:
        fields=list(rows_out[0].keys())
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows_out)
    for fam in ('plane-wedge','circle','ellipse'):
        print(f"[0493x9n-family] {fam}={'PASS' if family_ok[fam] else 'FAIL'}")
    print(f"[0493x9n-check] summary={summary}")
    print(f"[0493x9n-check] status={'PASS' if overall else 'FAIL'}")
    return 0 if overall else 2

if __name__=='__main__':
    raise SystemExit(main())

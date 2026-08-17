#!/usr/bin/env python3
"""Compare x9b one-pass with x9c two/three-pass passive curvature candidates."""
from __future__ import annotations
import argparse, csv, json, math
from pathlib import Path

BASE_REQ = {
    'step','crossingFaces','validCurvatureFaces','validFraction',
    'normalOutwardFraction','normalFaceAlignmentMean','curvatureMean',
    'curvatureRms','curvatureStd','curvatureAbsMean','curvatureAbsMax',
    'wallMarginCells','interiorCrossingFaces','interiorValidCurvatureFaces',
    'interiorCurvatureMean','interiorCurvatureRms','interiorCurvatureStd',
    'interiorCurvatureAbsMean','interiorCurvatureAbsMax',
    'nearWallCrossingFaces','nearWallValidCurvatureFaces',
    'nearWallCurvatureMean','nearWallCurvatureRms','nearWallCurvatureStd',
    'nearWallCurvatureAbsMean','nearWallCurvatureAbsMax','curvatureDefinition'
}

def load_rows(path: Path):
    if not path.exists(): raise SystemExit(f'missing audit: {path}')
    with path.open(newline='') as f: rows=list(csv.DictReader(f))
    if not rows: raise SystemExit(f'empty audit: {path}')
    return rows

def f(r,k): return float(r[k])
def i(r,k): return int(float(r[k]))

def region(r,p):
    return dict(crossingFaces=i(r,p+'CrossingFaces'), validCurvatureFaces=i(r,p+'ValidCurvatureFaces'),
                curvatureMean=f(r,p+'CurvatureMean'), curvatureRms=f(r,p+'CurvatureRms'),
                curvatureStd=f(r,p+'CurvatureStd'), curvatureAbsMean=f(r,p+'CurvatureAbsMean'),
                curvatureAbsMax=f(r,p+'CurvatureAbsMax'))

def metrics(r):
    missing=BASE_REQ.difference(r.keys())
    if missing: raise SystemExit(f'missing columns: {sorted(missing)}')
    return dict(step=i(r,'step'), crossingFaces=i(r,'crossingFaces'),
                validCurvatureFaces=i(r,'validCurvatureFaces'), validFraction=f(r,'validFraction'),
                normalOutwardFraction=f(r,'normalOutwardFraction'),
                normalFaceAlignmentMean=f(r,'normalFaceAlignmentMean'),
                curvatureMean=f(r,'curvatureMean'), curvatureRms=f(r,'curvatureRms'),
                curvatureStd=f(r,'curvatureStd'), curvatureAbsMean=f(r,'curvatureAbsMean'),
                curvatureAbsMax=f(r,'curvatureAbsMax'), wallMarginCells=i(r,'wallMarginCells'),
                interior=region(r,'interior'), nearWall=region(r,'nearWall'),
                curvatureDefinition=r['curvatureDefinition'])

def structural(m):
    return (m['crossingFaces']>0 and m['validFraction']>0.999 and
            m['normalOutwardFraction']>0.999 and
            all(math.isfinite(m[k]) for k in ('curvatureMean','curvatureRms','curvatureStd','curvatureAbsMax')) and
            m['interior']['crossingFaces']+m['nearWall']['crossingFaces']==m['crossingFaces'] and
            m['interior']['validCurvatureFaces']+m['nearWall']['validCurvatureFaces']==m['validCurvatureFaces'])

def circle_stats(m, exact):
    bias=(m['curvatureMean']-exact)/exact
    rel_std=m['curvatureStd']/exact
    rel_rms=math.sqrt(m['curvatureStd']**2+(m['curvatureMean']-exact)**2)/exact
    return dict(relativeMeanError=bias, relativeStd=rel_std, relativeRmsAboutExact=rel_rms)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--x9a',type=Path,required=True); ap.add_argument('--x9b',type=Path,required=True)
    ap.add_argument('--x9c',type=Path,required=True); ap.add_argument('--json',type=Path,required=True)
    ap.add_argument('--gamma',type=int,required=True); ap.add_argument('--radius-x',type=float,required=True)
    ap.add_argument('--radius-y',type=float,required=True); ap.add_argument('--Lx',type=float,required=True)
    ap.add_argument('--Ly',type=float,required=True); ap.add_argument('--nx',type=int,required=True); ap.add_argument('--ny',type=int,required=True)
    args=ap.parse_args()
    a=metrics(load_rows(args.x9a)[-1]); b=metrics(load_rows(args.x9b)[-1])
    crows=load_rows(args.x9c)
    if 'smoothingPasses' not in crows[0]: raise SystemExit('x9c audit missing smoothingPasses')
    bypass={i(r,'smoothingPasses'): metrics(r) for r in crows if i(r,'step')==b['step']}
    if 2 not in bypass or 3 not in bypass: raise SystemExit(f'x9c requires pass 2 and 3 rows at step {b["step"]}')
    c2,c3=bypass[2],bypass[3]
    if len({a['step'],b['step'],c2['step'],c3['step']})!=1: raise SystemExit('audit step mismatch')
    dx=args.Lx/args.nx; dy=args.Ly/args.ny
    circle=abs(args.radius_x-args.radius_y)<=1e-12*max(1.0,args.radius_x,args.radius_y)
    exact=1.0/args.radius_x if circle else None
    candidates={'p1_x9b':b,'p2_x9c':c2,'p3_x9c':c3}
    status='PASS-structural' if structural(a) and all(structural(x) for x in candidates.values()) else 'FAIL-structural'
    circle_errors={k:circle_stats(v,exact) for k,v in candidates.items()} if exact else None
    r_cells=args.radius_x/dx if circle else None
    report=dict(status=status,gamma=args.gamma,grid=[args.nx,args.ny],cellSize=[dx,dy],
                radiusX=args.radius_x,radiusY=args.radius_y,radiusCells=r_cells,circle=circle,
                circleExactCurvature=exact,x9a=a,candidates=candidates,circleErrors=circle_errors,
                accuracyStatus='DIAGNOSTIC-no-threshold-x9c')
    args.json.parent.mkdir(parents=True,exist_ok=True); args.json.write_text(json.dumps(report,indent=2)+'\n')
    def one(name,m):
        if exact:
            e=circle_errors[name]
            return (f"{name}[mean={m['curvatureMean']:.8g} std={m['curvatureStd']:.8g} "
                    f"relMean={100*e['relativeMeanError']:.3f}% relStd={100*e['relativeStd']:.3f}% "
                    f"relRms={100*e['relativeRmsAboutExact']:.3f}% max={m['curvatureAbsMax']:.8g}]")
        return f"{name}[mean={m['curvatureMean']:.8g} std={m['curvatureStd']:.8g} absMean={m['curvatureAbsMean']:.8g}]"
    print(f"[0493x9c-analysis] status={status} gamma={args.gamma} Rcells={r_cells if r_cells is not None else 'n/a'} " +
          ' '.join(one(k,v) for k,v in candidates.items()))
    print(f"[0493x9c-analysis] report={args.json}")
    return 0 if status.startswith('PASS') else 2

if __name__=='__main__': raise SystemExit(main())

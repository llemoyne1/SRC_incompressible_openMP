#!/usr/bin/env python3
"""Compare x18 penetration statistics across several existing runs (stdlib only)."""
import argparse,csv,glob,sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from analyze_0493x18_penetration import analyze


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--roots',nargs='*',default=[],help='explicit run roots')
    ap.add_argument('--glob',dest='patterns',action='append',default=[],
                    help='glob pattern; may be repeated, e.g. runs/0493x18b_hinged_fall_*')
    ap.add_argument('--out',default='runs/analysis_0493x18_penetration_sweep.csv')
    a=ap.parse_args()
    roots=list(a.roots)
    for p in a.patterns: roots.extend(sorted(glob.glob(p)))
    # deduplicate while retaining order
    seen=set(); roots=[r for r in roots if not (r in seen or seen.add(r))]
    if not roots: raise SystemExit('provide --roots and/or --glob')
    rows=[]
    for r in roots:
        try:
            _,res,_=analyze(r)
        except Exception as e:
            print(f'[0493x18-penetration-sweep] SKIP {r}: {e}',file=sys.stderr)
            continue
        rows.append(res)
    if not rows: raise SystemExit('no analyzable runs')

    def num(x):
        try:return float(x)
        except:return float('inf')
    rows.sort(key=lambda r:(num(r.get('fluidDensityFactor','')),str(r['run'])))
    fields=['run','fluidRegimeLabel','fluidDensityFactor','rho2D','flowUx','initialAngleDeg',
            'classification','samples','minSampledParticles','maxSampledParticles',
            'maxStrictInsideParticles','maxStrictInsideFraction','samplesWithStrictInside',
            'sumStrictParticleSamples','maxPenetrationCells','firstStrictStep','lastStrictStep',
            'totalSecondCollisionsAtAuditSamples','totalThirdCollisionsAtAuditSamples',
            'auditSamplesWithThirdCollisions','penetrationSamplesWithThirdCollisions']
    out=Path(a.out); out.parent.mkdir(parents=True,exist_ok=True)
    with out.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore'); w.writeheader(); w.writerows(rows)

    print('0493x18 penetration sweep')
    print('densityFactor classification maxStrict maxDepthCells affectedSamples thirdCollisions run')
    for r in rows:
        print(f"{r.get('fluidDensityFactor','-'):>12} {r['classification']:<22} "
              f"{r['maxStrictInsideParticles']:>9} {r['maxPenetrationCells']:>13.6g} "
              f"{r['samplesWithStrictInside']:>15} {r['totalThirdCollisionsAtAuditSamples']:>15} {r['run']}")
    print(f'[0493x18-penetration-sweep] csv={out}')

if __name__=='__main__':main()

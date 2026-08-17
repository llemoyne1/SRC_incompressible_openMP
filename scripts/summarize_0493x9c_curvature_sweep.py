#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,json,math
from pathlib import Path

ap=argparse.ArgumentParser(); ap.add_argument('--root',type=Path,required=True); ap.add_argument('--csv',type=Path,required=True)
args=ap.parse_args()
rows=[]
for p in sorted(args.root.rglob('curvature_compare_0493x9c.json')):
    d=json.loads(p.read_text())
    if not d.get('circle'): continue
    for name,passes in [('p1_x9b',1),('p2_x9c',2),('p3_x9c',3)]:
        m=d['candidates'][name]; e=d['circleErrors'][name]
        rows.append(dict(gamma=d['gamma'],radiusCells=d['radiusCells'],radius=d['radiusX'],
                         exactCurvature=d['circleExactCurvature'],smoothingPasses=passes,
                         curvatureMean=m['curvatureMean'],curvatureStd=m['curvatureStd'],
                         curvatureAbsMax=m['curvatureAbsMax'],relativeMeanError=e['relativeMeanError'],
                         relativeStd=e['relativeStd'],relativeRmsAboutExact=e['relativeRmsAboutExact'],
                         status=d['status'],report=str(p)))
if not rows: raise SystemExit(f'no x9c reports under {args.root}')
rows.sort(key=lambda r:(r['gamma'],r['radiusCells'],r['smoothingPasses']))
args.csv.parent.mkdir(parents=True,exist_ok=True)
with args.csv.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
print(f"[0493x9c-sweep] rows={len(rows)} csv={args.csv}")
# Compact winner-by-case table. Diagnostic only: minimize relative RMS, no acceptance threshold.
for g in sorted({r['gamma'] for r in rows}):
    for rc in sorted({r['radiusCells'] for r in rows if r['gamma']==g}):
        cand=[r for r in rows if r['gamma']==g and abs(r['radiusCells']-rc)<1e-9]
        best=min(cand,key=lambda r:r['relativeRmsAboutExact'])
        print(f"[0493x9c-sweep] gamma={g} Rcells={rc:g} bestPass={best['smoothingPasses']} "
              f"relMean={100*best['relativeMeanError']:.3f}% relStd={100*best['relativeStd']:.3f}% "
              f"relRms={100*best['relativeRmsAboutExact']:.3f}%")

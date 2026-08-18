#!/usr/bin/env python3
import argparse, csv, math
from pathlib import Path

def f(row,key,default=0.0):
    try: return float(row.get(key,default))
    except Exception: return default

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--csv', required=True)
    ap.add_argument('--tail', type=int, default=20)
    a=ap.parse_args()
    p=Path(a.csv)
    if not p.is_file():
        print(f'[0493x9r-check] missing {p}')
        return 2
    with p.open(newline='') as fh:
        rows=list(csv.DictReader(fh))
    if not rows:
        print(f'[0493x9r-check] empty {p}')
        return 2
    tail=rows[-max(1,a.tail):]
    limit=f(rows[-1],'kappaLimit')
    raw_max=max(f(r,'capillaryKappaRawAbsMax') for r in rows)
    eff_max=max(f(r,'capillaryKappaEffectiveAbsMax') for r in rows)
    clip_max=max(f(r,'clipFraction') for r in rows)
    clip_tail=sum(f(r,'clipFraction') for r in tail)/len(tail)
    clipped_total=sum(int(float(r.get('clippedFaces','0') or 0)) for r in rows)
    faces_total=sum(int(float(r.get('capillaryFaces','0') or 0)) for r in rows)
    sigma=f(rows[-1],'sigma'); rmin=f(rows[-1],'minRadiusCells')
    bounded = (limit <= 0.0) or (eff_max <= limit + max(1e-9,1e-8*abs(limit)))
    print(f'[0493x9r-check] rows={len(rows)} sigma={sigma:.8g} minRadiusCells={rmin:.8g} kappaLimit={limit:.8g}')
    print(f'[0493x9r-check]   rawAbsMax={raw_max:.8g} effectiveAbsMax={eff_max:.8g} bounded={int(bounded)}')
    print(f'[0493x9r-check]   clipFractionMax={clip_max:.6g} clipFractionTailMean={clip_tail:.6g} clippedFacesTotal={clipped_total} capillaryFacesTotal={faces_total}')
    if limit>0 and raw_max>limit:
        print(f'[0493x9r-check]   limiterActivated=1 raw/limit={raw_max/limit:.4g}')
    else:
        print('[0493x9r-check]   limiterActivated=0')
    print(f'[0493x9r-check] status={"PASS" if bounded else "FAIL"}')
    return 0 if bounded else 1
if __name__=='__main__':
    raise SystemExit(main())

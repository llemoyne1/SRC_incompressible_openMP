#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path
from statistics import mean, pstdev


def parse_meta(path):
    out = {}
    if path.exists():
        for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
            if '=' in line:
                k,v=line.split('=',1); out[k.strip()]=v.strip()
    return out


def f(row,key,default=0.0):
    try: return float(row.get(key,default))
    except (TypeError,ValueError): return float(default)


def one(case_dir, late_fraction):
    fresh=case_dir/'fresh'
    p=fresh/'output'/'chi_hinged_plate_0493x18a.csv'
    if not p.exists(): return None
    with p.open(newline='',encoding='utf-8') as fh: rows=list(csv.DictReader(fh))
    if len(rows)<2: return None
    meta=parse_meta(fresh/'run_meta_0493x18a_hinged_plate.txt')
    flow=float(meta.get('flowUx','nan'))
    n=max(2,int(math.ceil(late_fraction*len(rows))))
    late=rows[-n:]
    th=[f(r,'thetaDeg',f(r,'theta')*180/math.pi) for r in late]
    om=[f(r,'omegaAfter') for r in late]
    return {
      'flowUx':flow,
      'lateMeanThetaDeg':mean(th),
      'lateStdThetaDeg':pstdev(th) if len(th)>1 else 0.0,
      'lateOmegaRms':math.sqrt(mean([x*x for x in om])),
      'finalThetaDeg':f(rows[-1],'thetaDeg',f(rows[-1],'theta')*180/math.pi),
      'samples':len(rows),
      'case':case_dir.name,
    }


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',required=True)
    ap.add_argument('--late-fraction',type=float,default=0.25)
    a=ap.parse_args()
    root=Path(a.root).resolve()
    data=[]
    for d in root.iterdir() if root.exists() else []:
        if d.is_dir():
            r=one(d,a.late_fraction)
            if r is not None: data.append(r)
    data.sort(key=lambda r:r['flowUx'])
    if not data: raise SystemExit(f'no completed x18a cases below {root}')
    out=root/'angle_vs_speed_0493x18a.csv'
    with out.open('w',newline='',encoding='utf-8') as fh:
        w=csv.DictWriter(fh,fieldnames=['flowUx','lateMeanThetaDeg','lateStdThetaDeg','lateOmegaRms','finalThetaDeg','samples','case'])
        w.writeheader(); w.writerows(data)
    print('0493x18a angle versus crossflow')
    print('flowUx  lateMeanThetaDeg  lateStdThetaDeg  lateOmegaRms')
    for r in data:
        print(f"{r['flowUx']:7.4f}  {r['lateMeanThetaDeg']:16.8f}  {r['lateStdThetaDeg']:15.8f}  {r['lateOmegaRms']:.8g}")
    print(f'[0493x18a] sweepCsv={out}')

if __name__=='__main__': main()

#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path


def last_row(path):
    if not path.exists():
        raise SystemExit(f"[0493x9h-check] MISSING {path}")
    with path.open(newline="") as f:
        rows=list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"[0493x9h-check] EMPTY {path}")
    return rows[-1]


def iv(r,k): return int(float(r[k]))
def fv(r,k): return float(r[k])


def check_pair(case_dir, liquid_type):
    r=last_row(case_dir/'output/cuda_phase_pair_0493x9g.csv')
    ok=(r['phaseASelector']==f'type:{liquid_type}' and r['phaseBSelector']=='wall' and
        iv(r,'phaseBKind')==3 and iv(r,'phaseBSpeciesCount')==0 and
        iv(r,'phaseInterfaceEnabled')==0 and iv(r,'phaseBPressureEnabled')==0 and
        abs(fv(r,'surfaceTensionSigma'))<=1e-15)
    print(f"[0493x9h-check] pair {case_dir.name}: A={r['phaseASelector']} B={r['phaseBSelector']} "
          f"kindB={r['phaseBKind']} speciesB={r['phaseBSpeciesCount']} "
          f"interface={r['phaseInterfaceEnabled']} pressure={r['phaseBPressureEnabled']} pass={int(ok)}")
    return ok


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',required=True)
    ap.add_argument('--nx',type=int,required=True)
    ap.add_argument('--ny',type=int,required=True)
    ap.add_argument('--liquid-type',type=int,default=1)
    args=ap.parse_args()
    root=Path(args.root)
    ok=True

    # Domain walls: no interior solid cells are fabricated.  The provider sees
    # exact solid ghost samples on all four faces; the Scharr support therefore
    # occupies exactly the one-cell perimeter.
    ddir=root/'domain_wall'
    ok &= check_pair(ddir,args.liquid_type)
    d=last_row(ddir/'output/cuda_wall_geometry_0493x9h.csv')
    expected_band=2*args.nx + 2*max(0,args.ny-2)
    d_ok=(iv(d,'domainWallLeft')==1 and iv(d,'domainWallRight')==1 and
          iv(d,'domainWallBottom')==1 and iv(d,'domainWallTop')==1 and
          iv(d,'chiProviderEnabled')==0 and iv(d,'solidCells')==0 and
          iv(d,'mixedCells')==0 and iv(d,'wallBandCells')==expected_band and
          iv(d,'normalValidCells')==expected_band and
          abs(fv(d,'solidFractionMean'))<1e-14 and
          fv(d,'normalValidFraction')>0.999999 and
          fv(d,'normalUnitErrorRms')<1e-12)
    ok &= d_ok
    print(f"[0493x9h-check] domain: band={d['wallBandCells']} expected={expected_band} "
          f"normals={d['normalValidCells']} chi={d['chiProviderEnabled']} "
          f"unitErr={fv(d,'normalUnitErrorRms'):.3e} pass={int(d_ok)}")

    # Chi wall: periodic box has no domain-wall source, so B must come only from
    # the wallVP-declared chi provider.  The generated field is binary.
    cdir=root/'chi_wall'
    ok &= check_pair(cdir,args.liquid_type)
    c=last_row(cdir/'output/cuda_wall_geometry_0493x9h.csv')
    n=args.nx*args.ny
    solid=iv(c,'solidCells')
    band=iv(c,'wallBandCells')
    normals=iv(c,'normalValidCells')
    mean_s=fv(c,'solidFractionMean')
    expected_mean=solid/n
    c_ok=(iv(c,'domainWallLeft')==0 and iv(c,'domainWallRight')==0 and
          iv(c,'domainWallBottom')==0 and iv(c,'domainWallTop')==0 and
          iv(c,'chiProviderEnabled')==1 and iv(c,'chiCollisionWallVpEnabled')==1 and
          solid>0 and iv(c,'mixedCells')==0 and band>0 and normals>0 and
          normals <= band and fv(c,'normalValidFraction')>0.90 and
          abs(mean_s-expected_mean)<1e-12 and
          fv(c,'normalUnitErrorRms')<1e-12)
    ok &= c_ok
    print(f"[0493x9h-check] chi: solid={solid}/{n} meanS={mean_s:.6g} "
          f"band={band} normals={normals} validFrac={fv(c,'normalValidFraction'):.6f} "
          f"unitErr={fv(c,'normalUnitErrorRms'):.3e} pass={int(c_ok)}")

    print(f"[0493x9h-check] status={'PASS' if ok else 'FAIL'}")
    raise SystemExit(0 if ok else 1)

if __name__=='__main__':
    main()

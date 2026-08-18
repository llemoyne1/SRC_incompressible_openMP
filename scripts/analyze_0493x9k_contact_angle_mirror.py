#!/usr/bin/env python3
"""Analyze x9k sheared-mirror ghost-alpha contact-angle qualification."""
from __future__ import annotations
import argparse,csv,math
from pathlib import Path

def last_row(path: Path):
    if not path.exists():
        raise SystemExit(f"[0493x9k-check] missing {path}")
    with path.open(newline='') as f:
        rows=list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"[0493x9k-check] empty {path}")
    return rows[-1]

def f(row,key): return float(row[key])
def i(row,key): return int(float(row[key]))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',type=Path,required=True)
    ap.add_argument('--angles',nargs='+',required=True)
    ap.add_argument('--radius',type=float,required=True)
    ap.add_argument('--baseline-x9j-root',type=Path,default=None)
    ap.add_argument('--max-angle-mean-error-deg',type=float,default=3.0)
    ap.add_argument('--max-angle-rms-error-deg',type=float,default=5.0)
    ap.add_argument('--max-curvature-relative-bias',type=float,default=0.10)
    args=ap.parse_args()
    exact=1.0/args.radius
    ok=True
    for token in args.angles:
        theta=float(token); label=token.replace('.','p')
        row=last_row(args.root/f'theta{label}'/'output'/'cuda_contact_angle_mirror_0493x9k.csv')
        cand=i(row,'candidateCells'); corr=i(row,'correctedCells')
        raw=f(row,'rawAngleMean'); mirror=f(row,'correctedAngleMean')
        aerr=f(row,'correctedAngleErrorRms'); derr=f(row,'correctedDotErrorRms')
        k=f(row,'contactCurvatureMean'); ks=f(row,'contactCurvatureStd')
        rel=(k-exact)/exact
        angle_pass=(cand>0 and corr==cand and math.isfinite(mirror) and
                    abs(mirror-theta)<=args.max_angle_mean_error_deg and
                    aerr<=args.max_angle_rms_error_deg)
        curvature_pass=(math.isfinite(k) and k>0 and
                        abs(rel)<=args.max_curvature_relative_bias)
        baseline=None
        if args.baseline_x9j_root is not None:
            bp=args.baseline_x9j_root/f'theta{label}'/'output'/'cuda_contact_angle_ghost_0493x9j.csv'
            if bp.exists():
                br=last_row(bp)
                bk=f(br,'contactCurvatureMean'); bs=f(br,'contactCurvatureStd')
                brel=(bk-exact)/exact
                baseline=(bk,bs,brel)
        case_pass=angle_pass and curvature_pass
        ok=ok and case_pass
        print(f"[0493x9k-check] theta={theta:g} rawMean={raw:.8g} mirrorMean={mirror:.8g} angleErrRms={aerr:.3e} dotErrRms={derr:.3e} candidates={cand} measured={corr} anglePass={int(angle_pass)}")
        print(f"[0493x9k-check]   mirrorKappa={k:.8g} exactCircle={exact:.8g} relBias={100*rel:+.3f}% std={ks:.8g} curvaturePass={int(curvature_pass)}")
        if baseline is not None:
            bk,bs,brel=baseline
            factor=(abs(brel)/abs(rel)) if abs(rel)>1e-15 else float('inf')
            std_ratio=ks/bs if bs>0 else float('inf')
            print(f"[0493x9k-check]   baselineX9j kappa={bk:.8g} relBias={100*brel:+.3f}% std={bs:.8g} |bias|RatioOld/New={factor:.3g}x stdNew/Old={std_ratio:.3g}")
        print(f"[0493x9k-check]   pass={int(case_pass)}")
    print(f"[0493x9k-check] status={'PASS' if ok else 'FAIL'}")
    return 0 if ok else 2

if __name__=='__main__':
    raise SystemExit(main())

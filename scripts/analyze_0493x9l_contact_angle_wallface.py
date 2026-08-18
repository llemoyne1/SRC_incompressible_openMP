#!/usr/bin/env python3
import argparse,csv,math
from pathlib import Path

def last(path):
    if not path.exists(): raise SystemExit(f"[0493x9l-check] missing {path}")
    with path.open(newline='') as f: rows=list(csv.DictReader(f))
    if not rows: raise SystemExit(f"[0493x9l-check] empty {path}")
    return rows[-1]

def f(r,k): return float(r[k])
def i(r,k): return int(float(r[k]))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',type=Path,required=True)
    ap.add_argument('--angles',nargs='+',required=True)
    ap.add_argument('--radius',type=float,required=True)
    ap.add_argument('--baseline-x9k-root',type=Path)
    args=ap.parse_args()
    exact=1.0/args.radius
    overall=True
    for token in args.angles:
        theta=float(token); label=token.replace('.','p')
        row=last(args.root/f'theta{label}'/'output'/'cuda_contact_angle_wallface_0493x9l.csv')
        raw=f(row,'rawAngleMean'); measured=f(row,'correctedAngleMean')
        angle_rms=f(row,'correctedAngleErrorRms'); dot_rms=f(row,'correctedDotErrorRms')
        cand=i(row,'candidateCells'); corr=i(row,'correctedCells')
        k=f(row,'contactCurvatureMean'); ks=f(row,'contactCurvatureStd')
        rel=(k-exact)/exact
        angle_pass=(cand>0 and corr==cand and abs(measured-theta)<=2.0 and angle_rms<=3.0)
        curvature_pass=abs(rel)<=0.10
        passed=angle_pass and curvature_pass
        overall &= passed
        print(f"[0493x9l-check] theta={theta:g} rawMean={raw:.8g} wallFaceMean={measured:.8g} angleErrRms={angle_rms:.3e} dotErrRms={dot_rms:.3e} candidates={cand} measured={corr} anglePass={int(angle_pass)}")
        print(f"[0493x9l-check]   wallFaceKappa={k:.8g} exactCircle={exact:.8g} relBias={100*rel:+.3f}% std={ks:.8g} curvaturePass={int(curvature_pass)}")
        if args.baseline_x9k_root:
            bp=args.baseline_x9k_root/f'theta{label}'/'output'/'cuda_contact_angle_mirror_0493x9k.csv'
            if bp.exists():
                br=last(bp); bk=f(br,'contactCurvatureMean'); bstd=f(br,'contactCurvatureStd'); brel=(bk-exact)/exact
                ratio=abs(brel)/max(abs(rel),1e-15)
                print(f"[0493x9l-check]   baselineX9k kappa={bk:.8g} relBias={100*brel:+.3f}% std={bstd:.8g} |bias|Improvement={ratio:.3g}x")
        print(f"[0493x9l-check]   pass={int(passed)}")
    print(f"[0493x9l-check] status={'PASS' if overall else 'FAIL'}")
    return 0 if overall else 2
if __name__=='__main__': raise SystemExit(main())

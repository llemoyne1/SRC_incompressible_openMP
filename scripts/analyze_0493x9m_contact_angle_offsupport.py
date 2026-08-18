#!/usr/bin/env python3
import argparse,csv
from pathlib import Path

def last(path):
    if not path.exists(): raise SystemExit(f"[0493x9m-check] missing {path}")
    with path.open(newline='') as f: rows=list(csv.DictReader(f))
    if not rows: raise SystemExit(f"[0493x9m-check] empty {path}")
    return rows[-1]

def f(r,k): return float(r[k])
def i(r,k): return int(float(r[k]))

def baseline(path, exact):
    if not path.exists(): return None
    r=last(path); k=f(r,'contactCurvatureMean'); ks=f(r,'contactCurvatureStd')
    return k,ks,(k-exact)/exact

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',type=Path,required=True)
    ap.add_argument('--angles',nargs='+',required=True)
    ap.add_argument('--radius',type=float,required=True)
    ap.add_argument('--baseline-x9l-root',type=Path)
    ap.add_argument('--baseline-x9k-root',type=Path)
    args=ap.parse_args()
    exact=1.0/args.radius
    overall=True
    for token in args.angles:
        theta=float(token); label=token.replace('.','p')
        row=last(args.root/f'theta{label}'/'output'/'cuda_contact_angle_offsupport_0493x9m.csv')
        raw=f(row,'rawAngleMean'); measured=f(row,'correctedAngleMean')
        angle_rms=f(row,'correctedAngleErrorRms'); dot_rms=f(row,'correctedDotErrorRms')
        cand=i(row,'candidateCells'); corr=i(row,'correctedCells')
        k=f(row,'contactCurvatureMean'); ks=f(row,'contactCurvatureStd')
        rel=(k-exact)/exact
        angle_pass=(cand>0 and corr==cand and abs(measured-theta)<=2.0 and angle_rms<=3.0)
        curvature_pass=abs(rel)<=0.10
        passed=angle_pass and curvature_pass
        overall &= passed
        print(f"[0493x9m-check] theta={theta:g} rawMean={raw:.8g} offSupportMean={measured:.8g} angleErrRms={angle_rms:.3e} dotErrRms={dot_rms:.3e} candidates={cand} measured={corr} anglePass={int(angle_pass)}")
        print(f"[0493x9m-check]   offSupportKappa={k:.8g} exactCircle={exact:.8g} relBias={100*rel:+.3f}% std={ks:.8g} curvaturePass={int(curvature_pass)}")
        if args.baseline_x9l_root:
            b=baseline(args.baseline_x9l_root/f'theta{label}'/'output'/'cuda_contact_angle_wallface_0493x9l.csv',exact)
            if b:
                bk,bstd,brel=b; ratio=abs(brel)/max(abs(rel),1e-15)
                print(f"[0493x9m-check]   baselineX9l kappa={bk:.8g} relBias={100*brel:+.3f}% std={bstd:.8g} |bias|Improvement={ratio:.3g}x")
        if args.baseline_x9k_root:
            b=baseline(args.baseline_x9k_root/f'theta{label}'/'output'/'cuda_contact_angle_mirror_0493x9k.csv',exact)
            if b:
                bk,bstd,brel=b
                print(f"[0493x9m-check]   baselineX9k kappa={bk:.8g} relBias={100*brel:+.3f}% std={bstd:.8g}")
        print(f"[0493x9m-check]   pass={int(passed)}")
    print(f"[0493x9m-check] status={'PASS' if overall else 'FAIL'}")
    return 0 if overall else 2
if __name__=='__main__': raise SystemExit(main())

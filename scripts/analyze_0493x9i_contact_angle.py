#!/usr/bin/env python3
import argparse,csv,math
from pathlib import Path

def last(path):
    if not path.exists(): raise SystemExit(f'[0493x9i-check] MISSING {path}')
    with path.open(newline='') as f: rows=list(csv.DictReader(f))
    if not rows: raise SystemExit(f'[0493x9i-check] EMPTY {path}')
    return rows[-1]
def iv(r,k): return int(float(r[k]))
def fv(r,k): return float(r[k])

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',required=True); ap.add_argument('--angles',default='60 90 120'); ap.add_argument('--radius',type=float,required=True); ap.add_argument('--liquid-type',type=int,default=1); ap.add_argument('--gas-type',type=int,default=2)
    a=ap.parse_args(); root=Path(a.root); ok=True; exact_k=1.0/a.radius
    for tok in a.angles.split():
        theta=float(tok); label=f'theta{tok.replace(".","p")}'
        d=root/label
        ca=last(d/'output/cuda_contact_angle_0493x9i.csv')
        pp=last(d/'output/cuda_phase_pair_0493x9g.csv')
        wg=last(d/'output/cuda_wall_geometry_0493x9h.csv')
        pair_ok=(pp['phaseASelector']==f'type:{a.liquid_type}' and pp['phaseBSelector']==f'type:{a.gas_type}' and iv(pp,'phaseInterfaceEnabled')==1 and fv(pp,'surfaceTensionSigma')>0.0)
        corr=iv(ca,'correctedCells'); cand=iv(ca,'candidateCells'); curv=iv(ca,'curvatureCells')
        angle_err=fv(ca,'correctedAngleErrorRms'); dot_err=fv(ca,'correctedDotErrorRms'); measured=fv(ca,'correctedAngleMean'); raw=fv(ca,'rawAngleMean')
        closure_ok=(cand>0 and corr==cand and curv>0 and abs(measured-theta)<1e-8 and angle_err<1e-8 and dot_err<1e-12)
        wall_ok=(iv(wg,'domainWallBottom')==1 and iv(wg,'normalValidCells')>0 and fv(wg,'normalUnitErrorRms')<1e-12)
        case_ok=pair_ok and closure_ok and wall_ok; ok &= case_ok
        km=fv(ca,'contactCurvatureMean'); ks=fv(ca,'contactCurvatureStd')
        rel=(km-exact_k)/exact_k
        print(f'[0493x9i-check] theta={theta:g} rawMean={raw:.6f} correctedMean={measured:.12g} angleErrRms={angle_err:.3e} dotErrRms={dot_err:.3e} candidates={cand} corrected={corr} pass={int(case_ok)}')
        print(f'[0493x9i-check]   contactKappa={km:.8g} exactCircle={exact_k:.8g} relBias={rel:+.3%} std={ks:.8g} [INFO: curvature not a hard gate in x9i]')
    print(f'[0493x9i-check] status={"PASS" if ok else "FAIL"}')
    raise SystemExit(0 if ok else 1)
if __name__=='__main__': main()

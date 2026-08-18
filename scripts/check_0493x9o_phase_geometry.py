#!/usr/bin/env python3
import math


def main():
    h=1.6/320.0
    phases=(0.0,0.25,0.5,0.75)
    cx0=0.8
    ok=True
    for p in phases:
        cx=cx0+p*h
        recovered=(cx-cx0)/h
        passed=abs(recovered-p)<1e-12
        ok &= passed
        print(f"[0493x9o-mapcheck] phase={p:.2f} centerX={cx:.9f} recoveredCells={recovered:.9f} pass={int(passed)}")
    # Exact local curvatures of the two phase-sensitive x9n cases.
    kc=1.0/(80.0*h)
    a=40.0*h; b=56.0*h
    # At theta=90 deg the ellipse contact is at t=0 and kappa=a/b^2.
    ke=a/(b*b)
    pass_c=abs(kc-2.5)<1e-12
    pass_e=abs(ke-2.5510204081632653)<1e-12
    ok &= pass_c and pass_e
    print(f"[0493x9o-mapcheck] circleR80 exactKappa={kc:.12g} pass={int(pass_c)}")
    print(f"[0493x9o-mapcheck] ellipseTall90 exactKappa={ke:.12g} pass={int(pass_e)}")
    print(f"[0493x9o-mapcheck] status={'PASS' if ok else 'FAIL'}")
    return 0 if ok else 2

if __name__=='__main__':
    raise SystemExit(main())

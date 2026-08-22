#!/usr/bin/env python3
import math, random

rng = random.Random(493104)
max_dp = 0.0
max_de = 0.0
max_formula_res = 0.0
min_a = float('inf')
max_a = 0.0
non_inward = 0
positive = 0

for _ in range(20000):
    # Independent bath reference and receiver set: this is deliberately more
    # general than the same-cell partition special case.
    ub = (rng.uniform(-1,1), rng.uniform(-1,1))
    ur = (ub[0] + rng.uniform(-0.5,0.5), ub[1] + rng.uniform(-0.5,0.5))
    mr = rng.uniform(0.2, 50.0)

    donors = []
    A = 0.0
    Sx = Sy = 0.0
    for _j in range(rng.randint(1,8)):
        th = rng.uniform(-math.pi, math.pi)
        n = (math.cos(th), math.sin(th))
        g = rng.uniform(1e-4, 2.0)
        tang = rng.uniform(-2.0,2.0)
        t = (-n[1], n[0])
        v = (ub[0] + g*n[0] + tang*t[0],
             ub[1] + g*n[1] + tang*t[1])
        m = rng.uniform(0.1, 3.0)
        donors.append((m,v,n,g))
        A += m*g*g
        Sx += m*g*n[0]
        Sy += m*g*n[1]

    B = (Sx*Sx+Sy*Sy)/mr
    C = (ur[0]-ub[0])*Sx + (ur[1]-ub[1])*Sy
    a = 2.0*(A-C)/(A+B)
    if not (a > 0.0 and math.isfinite(a)):
        # production fallback is the exact trivial root a=0
        a = 0.0
    else:
        positive += 1
        min_a = min(min_a,a)
        max_a = max(max_a,a)
        if a <= 1.0:
            non_inward += 1

    du = (a*Sx/mr, a*Sy/mr)

    dp_x = dp_y = 0.0
    de = 0.0
    for m,v,n,g in donors:
        vp = (v[0]-a*g*n[0], v[1]-a*g*n[1])
        dp_x += m*(vp[0]-v[0])
        dp_y += m*(vp[1]-v[1])
        de += 0.5*m*((vp[0]*vp[0]+vp[1]*vp[1])-(v[0]*v[0]+v[1]*v[1]))

    # Represent receiver pool only through its COM change. Internal energy is
    # unchanged by the x10d uniform receiver translation.
    dp_x += mr*du[0]
    dp_y += mr*du[1]
    de += mr*(ur[0]*du[0] + ur[1]*du[1]) + 0.5*mr*(du[0]*du[0]+du[1]*du[1])

    formula_res = a*(C-A) + 0.5*a*a*(A+B)
    max_dp = max(max_dp, abs(dp_x), abs(dp_y))
    max_de = max(max_de, abs(de))
    max_formula_res = max(max_formula_res, abs(formula_res))

print(f'maxMomentumResidual={max_dp:.3e}')
print(f'maxEnergyResidual={max_de:.3e}')
print(f'maxFormulaResidual={max_formula_res:.3e}')
print(f'positiveRootCases={positive}')
print(f'nonInwardPositiveRootCases={non_inward}')
if positive:
    print(f'positiveScaleRange=[{min_a:.6g},{max_a:.6g}]')
if max_dp > 5e-12 or max_de > 5e-11 or max_formula_res > 5e-12:
    raise SystemExit('status=FAIL')
print('status=PASS')

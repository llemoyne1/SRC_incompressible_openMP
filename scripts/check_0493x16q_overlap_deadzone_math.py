#!/usr/bin/env python3
import math
h = 0.00390625
q2_level_excess = 3.0917901461258168e-08
depth_cells = 1.2339175084122454e-07
penetration = depth_cells * h
q2_level_tol = 1.0e-10
legacy_tol = 1.0e-8 * max(1.0, h)
chi_tol = 1.0e-10 * h
push_tol = 4.0 * chi_tol
assert q2_level_excess > q2_level_tol
assert penetration < legacy_tol
assert penetration > chi_tol
assert push_tol < penetration
print(f'PASS event85163 q2LevelExcess={q2_level_excess:.17g} > q2LevelTol={q2_level_tol:.17g}')
print(f'PASS event85163 penetration={penetration:.17g} oldX10pTol={legacy_tol:.17g} oldWouldMiss=1')
print(f'PASS event85163 chiX10pTol={chi_tol:.17g} newWouldResolve=1 penetrationOverTol={penetration/chi_tol:.9g}')
print(f'PASS historicalToleranceRetained={legacy_tol:.17g} chiToleranceScale=h*1e-10 deadBandShrink={legacy_tol/chi_tol:.9g}')
print('0493x16q overlap-deadzone math check: ALL PASS')

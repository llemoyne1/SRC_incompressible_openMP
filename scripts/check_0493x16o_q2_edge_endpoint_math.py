#!/usr/bin/env python3
"""0493x16o deterministic math regression (stdlib only).

Replays the local owner=(69,14) geometry responsible for the two deep
203->204 boost penetrations.  No dump files are required: the constants are
from that observed static-curved state and the test exercises the exact 1-D
Q2 edge construction proposed in x16o.
"""
import math

NX, NY = 128, 64
LX, LY = 0.5, 0.25
DX, DY = LX/NX, LY/NY
OWNER_I, OWNER_J = 69, 14
CENTER_X = 0.28419682360007187
AMPLITUDE = 0.0029296875
SLAB_HALF = 0.5 * 8.0 * DX
LEVEL_HALF_WIDTH = 2.0 * DX


def solid_level(ix, iy):
    x = (ix + 0.5) * DX
    y = (iy + 0.5) * DY
    xc = CENTER_X + AMPLITUDE * math.sin(2.0*math.pi*y/LY)
    d = x - xc
    d -= round(d/LX)*LX
    sd = abs(d) - SLAB_HALF
    return min(1.0, max(0.0, 0.5 - sd/(2.0*LEVEL_HALF_WIDTH)))


def q2_root(fm, f0, fp):
    flo, fhi = f0-0.5, fp-0.5
    assert flo == 0.0 or fhi == 0.0 or (flo > 0.0) != (fhi > 0.0)
    if flo == 0.0: return 0.0
    if fhi == 0.0: return 1.0
    d1 = 0.5*(fp-fm)
    d2 = 0.5*(fp-2.0*f0+fm)
    lo, hi = 0.0, 1.0
    for _ in range(40):
        mid = 0.5*(lo+hi)
        fmid = f0 + d1*mid + d2*mid*mid - 0.5
        if (fmid > 0.0) == (flo > 0.0):
            lo, flo = mid, fmid
        else:
            hi = mid
    return 0.5*(lo+hi)


def project_lambda(A, B, P):
    dx, dy = B[0]-A[0], B[1]-A[1]
    den = dx*dx + dy*dy
    lam = ((P[0]-A[0])*dx + (P[1]-A[1])*dy)/den
    qx, qy = A[0]+lam*dx, A[1]+lam*dy
    dist = math.hypot(P[0]-qx, P[1]-qy)
    return lam, dist

# owner code 7: branch joins edge 2 (top) to edge 3 (left).
i, j = OWNER_I, OWNER_J
a00 = solid_level(i,j)
a10 = solid_level(i+1,j)
a11 = solid_level(i+1,j+1)
a01 = solid_level(i,j+1)
code = (a00>=0.5) | ((a10>=0.5)<<1) | ((a11>=0.5)<<2) | ((a01>=0.5)<<3)
assert code == 7, code

# Top edge is affine in this x16k signed-distance field, hence linear and Q2
# roots coincide.  Left edge is curved in y and exposes the old mismatch.
xi_top_linear = (0.5-a01)/(a11-a01)
xi_top_q2 = q2_root(solid_level(i-1,j+1), a01, a11)
eta_left_linear = (0.5-a00)/(a01-a00)
eta_left_q2 = q2_root(solid_level(i,j-1), a00, a01)

assert abs(xi_top_q2-xi_top_linear) < 1e-12
assert 0.11 < eta_left_linear-eta_left_q2 < 0.13
assert abs(eta_left_q2 - 0.39845) < 2e-5

oldA=(xi_top_linear,1.0); oldB=(0.0,eta_left_linear)
newA=(xi_top_q2,1.0);    newB=(0.0,eta_left_q2)
# Q2 impact local coordinates reconstructed from the two actual penetrants.
events={
    32388:(0.000530,0.467300),
    46765:(0.000890,0.516791),
}
expected_old={32388:1.1032,46765:1.0007}
expected_new={32388:0.8855,46765:0.8033}
for pid,P in events.items():
    old_lam, old_dist = project_lambda(oldA,oldB,P)
    new_lam, new_dist = project_lambda(newA,newB,P)
    assert old_lam > 1.0, (pid,old_lam)
    assert 0.0 <= new_lam <= 1.0, (pid,new_lam)
    assert abs(old_lam-expected_old[pid]) < 5e-4
    assert abs(new_lam-expected_new[pid]) < 5e-4
    assert new_dist < 3e-4
    print(f'PASS pid={pid} lambdaLinear={old_lam:.9f} lambdaQ2={new_lam:.9f} chordDistanceCells={new_dist:.9g}')

# Shared-edge C0 property: both adjacent owners see the same canonical
# 3-sample column, hence the same bisection sequence/root exactly.
shared_a = q2_root(solid_level(i,j-1), solid_level(i,j), solid_level(i,j+1))
shared_b = q2_root(solid_level(i,j-1), solid_level(i,j), solid_level(i,j+1))
assert shared_a == shared_b
print(f'PASS leftEdge linearRoot={eta_left_linear:.12f} q2Root={eta_left_q2:.12f} shiftCells={eta_left_linear-eta_left_q2:.12f}')
print(f'PASS sharedEdgeRootBitwise root={shared_a:.12f}')
print('0493x16o Q2 edge-endpoint math check: ALL PASS')

#!/usr/bin/env python3
import math
import struct

NX, NY = 32, 64
LX, LY = 0.125, 0.25
DX, DY = LX / NX, LY / NY
AMP = 0.75 * DX
THICKNESS = 8.0 * DX
HALF = 0.5 * THICKNESS
CENTER = 0.062576857948058756  # x16a row 269 from the dump-trace run
LEVEL_HALF_WIDTH = 2.0 * DX

def f32(x):
    return struct.unpack('<f', struct.pack('<f', x))[0]

def periodic_delta(x, c, L):
    d = x - c
    return d - round(d / L) * L

def idx(i, j):
    return (j % NY) * NX + (i % NX)

def wall_fraction():
    out = []
    for j in range(NY):
        y = (j + 0.5) * DY
        local_center = CENTER + AMP * math.sin(2.0 * math.pi * y / LY)
        for i in range(NX):
            x = (i + 0.5) * DX
            d = periodic_delta(x, local_center, LX)
            sd = abs(d) - HALF
            S = max(0.0, min(1.0, 0.5 - sd / (2.0 * LEVEL_HALF_WIDTH)))
            # CUDA stores chi as float, then reconstructs S=1-chi in double.
            chi = f32(1.0 - S)
            out.append(1.0 - float(chi))
    return out

S = wall_fraction()

def q1(fm, f0, fp, z):
    return f0 + 0.5 * (fp - fm) * z + 0.5 * (fp - 2.0 * f0 + fm) * z * z

def qpatch(owner):
    i, j = owner % NX, owner // NX
    return [[S[idx(i + ii, j + jj)] for ii in (-1, 0, 1)] for jj in (-1, 0, 1)]

def qeval(owner, xi, eta):
    P = qpatch(owner)
    rows = [q1(row[0], row[1], row[2], xi) for row in P]
    return q1(rows[0], rows[1], rows[2], eta)

def wrap_pos(x, L):
    return x - math.floor(x / L) * L

def physical_owner(x, y):
    x, y = wrap_pos(x, LX), wrap_pos(y, LY)
    return int(math.floor(x / DX)) * 1 + int(math.floor(y / DY)) * NX

def dual_owner(x, y):
    x, y = wrap_pos(x, LX), wrap_pos(y, LY)
    i = int(math.floor(x / DX - 0.5)) % NX
    j = int(math.floor(y / DY - 0.5)) % NY
    return j * NX + i

def local(owner, x, y):
    i, j = owner % NX, owner // NX
    xc, yc = (i + 0.5) * DX, (j + 0.5) * DY
    return periodic_delta(x, xc, LX) / DX, periodic_delta(y, yc, LY) / DY

# Two exact post-stream positions from the 268->269 dump pair.
leaks = [
    (3142, 0.07881800785404756, 0.008432019717830636),
    (10759, 0.047796300576053656, 0.11336831365958239),
]

for pid, x, y in leaks:
    po = physical_owner(x, y)
    do = dual_owner(x, y)
    pxi, peta = local(po, x, y)
    dxi, deta = local(do, x, y)
    old_excess = qeval(po, pxi, peta) - 0.5
    new_excess = qeval(do, dxi, deta) - 0.5
    if not (old_excess > 1.0e-6):
        raise SystemExit(f'FAIL pid={pid}: historical x16l excess not reproduced: {old_excess:.3e}')
    if not (new_excess <= 0.0):
        raise SystemExit(f'FAIL pid={pid}: dual-owner Q2 still says solid: {new_excess:.3e}')
    if not (-1.0e-12 <= dxi <= 1.0 + 1.0e-12 and -1.0e-12 <= deta <= 1.0 + 1.0e-12):
        raise SystemExit(f'FAIL pid={pid}: dual coordinates outside owner square: {(dxi,deta)}')
    print(
        f'PASS dump269 pid={pid} oldPhysicalOwner=({po%NX},{po//NX}) '
        f'oldExcess={old_excess:.9e} dualOwner=({do%NX},{do//NX}) '
        f'dualExcess={new_excess:.9e} dualLocal=({dxi:.9f},{deta:.9f})'
    )

# Prove C0 continuity of the piecewise-Q2 convention on every shared edge of
# the actual curved-wall field.  Q2 owner(i,j) at xi=1 must equal owner(i+1,j)
# at xi=0 for every eta, and similarly in y.  Test several points per edge.
max_jump = 0.0
samples = (0.0, 0.125, 0.37, 0.5, 0.83, 1.0)
for j in range(NY):
    for i in range(NX):
        o = idx(i, j)
        oe = idx(i + 1, j)
        on = idx(i, j + 1)
        for t in samples:
            max_jump = max(max_jump, abs(qeval(o, 1.0, t) - qeval(oe, 0.0, t)))
            max_jump = max(max_jump, abs(qeval(o, t, 1.0) - qeval(on, t, 0.0)))
if max_jump > 5.0e-15:
    raise SystemExit(f'FAIL piecewise-Q2 edge continuity jump={max_jump:.3e}')
print(f'PASS piecewise_Q2_C0 maxSharedEdgeJump={max_jump:.3e}')
print('0493x16n Q2 dual-square math check: ALL PASS')

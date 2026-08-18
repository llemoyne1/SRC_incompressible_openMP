#!/usr/bin/env python3
"""Generate a homogeneous gas box plus inactive liquid slots for 0493x9q.

Stdlib-only and intentionally mirrors the proven 0431 state layout.
"""
from __future__ import annotations
import argparse
import math
import os
import random
import struct


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', required=True)
    ap.add_argument('--Lx', type=float, required=True)
    ap.add_argument('--Ly', type=float, required=True)
    ap.add_argument('--nx', type=int, required=True)
    ap.add_argument('--ny', type=int, required=True)
    ap.add_argument('--gamma', type=int, required=True)
    ap.add_argument('--kBT', type=float, required=True)
    ap.add_argument('--gas-mass', type=float, required=True)
    ap.add_argument('--gas-type', type=int, required=True)
    ap.add_argument('--liquid-mass', type=float, required=True)
    ap.add_argument('--liquid-type', type=int, required=True)
    ap.add_argument('--inactive-slots', type=int, required=True)
    ap.add_argument('--seed', type=int, required=True)
    args = ap.parse_args()

    if not (args.Lx > 0 and args.Ly > 0 and args.nx > 0 and args.ny > 0 and args.gamma > 0):
        raise SystemExit('[0493x9q-generate] positive domain/grid/gamma required')
    if not (args.gas_mass > 0 and args.liquid_mass > 0 and args.inactive_slots >= 0 and args.kBT >= 0):
        raise SystemExit('[0493x9q-generate] invalid mass/kBT/inactive slots')
    if args.gas_type == args.liquid_type:
        raise SystemExit('[0493x9q-generate] gas and liquid types must differ')

    rng = random.Random(args.seed)
    dx = args.Lx / args.nx
    dy = args.Ly / args.ny
    sigma = math.sqrt(args.kBT / args.gas_mass) if args.kBT > 0 else 0.0
    x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
    for j in range(args.ny):
        y0 = j * dy
        for i in range(args.nx):
            x0 = i * dx
            for _ in range(args.gamma):
                x.append(x0 + dx*rng.random())
                y.append(y0 + dy*rng.random())
                vx.append(sigma*rng.gauss(0.0, 1.0) if sigma else 0.0)
                vy.append(sigma*rng.gauss(0.0, 1.0) if sigma else 0.0)
                typ.append(args.gas_type); mass.append(args.gas_mass); role.append(1)

    # Remove the finite-box COM drift without changing the temperature field.
    active_mass = sum(mass)
    if active_mass > 0:
        mvx = sum(m*v for m,v in zip(mass, vx)) / active_mass
        mvy = sum(m*v for m,v in zip(mass, vy)) / active_mass
        vx = [v-mvx for v in vx]
        vy = [v-mvy for v in vy]

    for _ in range(args.inactive_slots):
        x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
        typ.append(args.liquid_type); mass.append(args.liquid_mass); role.append(0)

    n = len(x)
    magic = b'SRCMPCD_STATE' + b'\0'*(16-len('SRCMPCD_STATE'))
    reserved = [0]*8
    reserved[0] = 1
    reserved[1] = 1
    os.makedirs(os.path.dirname(args.output) or '.', exist_ok=True)
    with open(args.output, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<IIIIQIIII', 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        f.write(struct.pack('<8Q', *reserved))
        for arr, fmt in ((x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')):
            f.write(struct.pack('<%d%s' % (n, fmt), *arr))

    fluid = args.nx*args.ny*args.gamma
    print(f'[0493x9q-generate] state={args.output} grid={args.nx}x{args.ny} gamma={args.gamma} gas={fluid} inactiveLiquid={args.inactive_slots} total={n}')
    print(f'[0493x9q-generate] h=({dx:.9g},{dy:.9g}) gasMass={args.gas_mass:g} liquidMass={args.liquid_mass:g} massRatio={args.liquid_mass/args.gas_mass:g}')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())

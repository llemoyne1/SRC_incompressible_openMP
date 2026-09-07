#!/usr/bin/env python3
"""Generate a 2-D liquid bath + gas headspace for a normal planar gas-jet test.

Tooling only: no solver/source modification.
The liquid occupies y <= bath_height with nominal occupancy gamma.
The gas above it is initialized at isothermal barometric equilibrium under
bodyAccelerationY when gravity_y < 0, normalized so its mean headspace
occupancy is gamma.  For gravity_y == 0 the gas occupancy is uniform gamma.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import struct
import sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def pos_int(s: str) -> int:
    v = int(s)
    if v <= 0:
        raise argparse.ArgumentTypeError("expected positive integer")
    return v


def pos_float(s: str) -> float:
    v = float(s)
    if not math.isfinite(v) or v <= 0.0:
        raise argparse.ArgumentTypeError("expected finite positive number")
    return v


def nonneg_float(s: str) -> float:
    v = float(s)
    if not math.isfinite(v) or v < 0.0:
        raise argparse.ArgumentTypeError("expected finite non-negative number")
    return v


def coprime_multiplier(modulus: int, start: int, avoid: int = -1) -> int:
    if modulus <= 1:
        return 1
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1


def paired_velocities(rng: random.Random, count: int, mass: float, kbt: float):
    if count <= 0:
        return []
    if kbt == 0.0 or count == 1:
        return [(0.0, 0.0)] * count
    vals = []
    for _ in range(count // 2):
        gx, gy = rng.gauss(0.0, 1.0), rng.gauss(0.0, 1.0)
        vals.extend(((gx, gy), (-gx, -gy)))
    if count % 2:
        vals.append((0.0, 0.0))
    s2 = sum(x*x + y*y for x, y in vals)
    scale = math.sqrt((2.0 * count * kbt) / (mass * s2)) if s2 > 0.0 else 0.0
    return [(scale*x, scale*y) for x, y in vals]


def in_cell_positions(ix: int, iy: int, n: int, dx: float, dy: float):
    if n <= 0:
        return []
    ax = coprime_multiplier(n, 3)
    ay = coprime_multiplier(n, 7, avoid=ax)
    return [
        ((ix + (((ax*k) % n) + 0.5)/n) * dx,
         (iy + (((ay*k) % n) + 0.5)/n) * dy)
        for k in range(n)
    ]


def write_state(path: Path, x, y, vx, vy, typ, mass, role):
    n = len(x)
    if not (len(y) == len(vx) == len(vy) == len(typ) == len(mass) == len(role) == n):
        raise RuntimeError("inconsistent state arrays")
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    path.parent.mkdir(parents=True, exist_ok=True)
    if sys.byteorder == "big":
        for a in (x, y, vx, vy, typ, mass):
            a.byteswap()
    try:
        with path.open("wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
            f.write(struct.pack("<8Q", *reserved))
            for a in (x, y, vx, vy, typ, mass):
                a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder == "big":
            for a in (x, y, vx, vy, typ, mass):
                a.byteswap()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--Lx", type=pos_float, default=2.0)
    ap.add_argument("--Ly", type=pos_float, default=1.0)
    ap.add_argument("--nx", type=pos_int, default=512)
    ap.add_argument("--ny", type=pos_int, default=256)
    ap.add_argument("--gamma", type=pos_int, default=20)
    ap.add_argument("--bath-height", type=pos_float, default=0.5)
    ap.add_argument("--gravity-y", type=float, default=-0.5)
    ap.add_argument("--liquid-type", type=pos_int, default=1)
    ap.add_argument("--gas-type", type=pos_int, default=2)
    ap.add_argument("--liquid-mass", type=pos_float, default=1.0)
    ap.add_argument("--gas-mass", type=pos_float, default=0.1)
    ap.add_argument("--liquid-kBT", type=nonneg_float, default=0.02)
    ap.add_argument("--gas-kBT", type=pos_float, default=0.08)
    ap.add_argument("--seed", type=int, default=493205)
    a = ap.parse_args()

    if a.gamma < 2:
        ap.error("gamma must be >=2")
    if a.liquid_type == a.gas_type:
        ap.error("liquid and gas types must differ")
    if not (0.0 < a.bath_height < a.Ly):
        ap.error("bath-height must lie strictly inside the box")
    if not math.isfinite(a.gravity_y):
        ap.error("gravity-y must be finite")

    dx, dy = a.Lx/a.nx, a.Ly/a.ny
    if abs(dx-dy) > 1e-12*max(1.0, abs(dx), abs(dy)):
        ap.error("square cells required")
    bath_rows = a.bath_height/dy
    if abs(bath_rows-round(bath_rows)) > 1e-10:
        ap.error("bath-height must lie on a cell boundary for this first qualification")
    bath_row = int(round(bath_rows))
    if not (1 <= bath_row < a.ny):
        ap.error("invalid bath row")

    gas_height = a.Ly-a.bath_height
    gabs = max(0.0, -a.gravity_y)
    if gabs > 0.0:
        Hbar = a.gas_kBT/(a.gas_mass*gabs)
        mean_factor = (Hbar/gas_height)*(1.0-math.exp(-gas_height/Hbar))
        n0 = a.gamma/mean_factor
        top_bottom_ratio = math.exp(-gas_height/Hbar)
    else:
        Hbar = math.inf
        n0 = float(a.gamma)
        top_bottom_ratio = 1.0

    rng_l = random.Random(a.seed ^ 0x14B411)
    rng_g = random.Random(a.seed ^ 0x14B422)
    x = array("d"); y = array("d"); vx = array("d"); vy = array("d")
    typ = array("I"); mass = array("d"); role = bytearray()
    n_liquid = n_gas = 0
    gas_row_targets = []
    gas_row_means = []

    for iy in range(a.ny):
        yc = (iy+0.5)*dy
        if iy < bath_row:
            nrow_target = float(a.gamma)
            nbase = a.gamma
            extra_cells = 0
            is_liquid = True
        else:
            z = yc-a.bath_height
            nrow_target = n0*math.exp(-z/Hbar) if math.isfinite(Hbar) else float(a.gamma)
            nbase = int(math.floor(nrow_target))
            frac = nrow_target-nbase
            extra_cells = int(round(frac*a.nx))
            is_liquid = False
            gas_row_targets.append((yc, nrow_target))

        row_total = 0
        for ix in range(a.nx):
            if is_liquid:
                ncell = a.gamma
                cell_type = a.liquid_type
                cell_mass = a.liquid_mass
                cell_kbt = a.liquid_kBT
                rng = rng_l
            else:
                # Deterministic x-dithering gives the requested row-average occupancy.
                # The modular shift avoids stacking the +1 cells vertically.
                phase = (iy*37) % a.nx
                rank = (ix-phase) % a.nx
                ncell = nbase + (1 if rank < extra_cells else 0)
                ncell = max(2, ncell)
                cell_type = a.gas_type
                cell_mass = a.gas_mass
                cell_kbt = a.gas_kBT
                rng = rng_g
            pos = in_cell_positions(ix, iy, ncell, dx, dy)
            vel = paired_velocities(rng, ncell, cell_mass, cell_kbt)
            for (px,py),(ux,uy) in zip(pos,vel):
                x.append(px); y.append(py); vx.append(ux); vy.append(uy)
                typ.append(cell_type); mass.append(cell_mass); role.append(1)
            row_total += ncell
            if is_liquid: n_liquid += ncell
            else: n_gas += ncell
        if not is_liquid:
            gas_row_means.append((yc, row_total/a.nx))

    write_state(a.output, x, y, vx, vy, typ, mass, role)
    top_occ = gas_row_targets[-1][1] if gas_row_targets else float(a.gamma)
    bottom_occ = gas_row_targets[0][1] if gas_row_targets else float(a.gamma)
    meta = {
        "profile": "planar_gas_jet_liquid_bath_2d",
        "Lx":a.Lx,"Ly":a.Ly,"nx":a.nx,"ny":a.ny,"dx":dx,"dy":dy,
        "gamma":a.gamma,"bathHeight":a.bath_height,"bathRow":bath_row,
        "gravityY":a.gravity_y,"liquidType":a.liquid_type,"gasType":a.gas_type,
        "liquidMass":a.liquid_mass,"gasMass":a.gas_mass,
        "liquidKBT":a.liquid_kBT,"gasKBT":a.gas_kBT,"seed":a.seed,
        "particles":len(x),"liquidParticles":n_liquid,"gasParticles":n_gas,
        "barometricScaleHeight":None if not math.isfinite(Hbar) else Hbar,
        "barometricTopToBathDensityRatio":top_bottom_ratio,
        "gasBathOccupancyTarget":bottom_occ,
        "gasTopOccupancyTarget":top_occ,
        "gasTopOccupancyRounded":max(2,int(round(top_occ))),
        "gasRowTargets":gas_row_targets,
        "gasRowMeans":gas_row_means,
    }
    mp = a.output.with_suffix(a.output.suffix+".json")
    mp.write_text(json.dumps(meta, indent=2)+"\n")
    print(f"[gas-jet-bath-generate] grid={a.nx}x{a.ny} h={dx:.9g} gamma={a.gamma} N={len(x)} liquid={n_liquid} gas={n_gas}")
    print(f"[gas-jet-bath-generate] bathHeight={a.bath_height:.9g} gasHeight={gas_height:.9g} gravityY={a.gravity_y:.9g}")
    if math.isfinite(Hbar):
        print(f"[gas-jet-bath-generate] gas barometric H={Hbar:.9g} nTop/nBath={top_bottom_ratio:.9g} Nbath~{bottom_occ:.6g} Ntop~{top_occ:.6g}")
    else:
        print("[gas-jet-bath-generate] gas barometric H=inf uniform occupancy")
    print(f"[gas-jet-bath-generate] state={a.output}")
    print(f"[gas-jet-bath-generate] metadata={mp}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

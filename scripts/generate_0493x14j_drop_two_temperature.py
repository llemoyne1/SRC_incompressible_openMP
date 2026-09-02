#!/usr/bin/env python3
"""Generate the x14j two-species circular-drop state with per-type kBT.

This is intentionally a standalone derivative of generate_0493x9b_ellipse_state.py:
- same deterministic in-cell particle pattern;
- same exact geometric type assignment;
- separate liquid/gas masses;
- separate liquid/gas kinetic temperatures at initialization.

No runtime/source file is modified by this helper.
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
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1


def paired_velocities(rng: random.Random, count: int, mass: float, kbt: float):
    """Zero-barycentre per-cell velocities with exact kinetic kBT for count>1."""
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
    ap.add_argument("--Lx", type=pos_float, default=1.5625)
    ap.add_argument("--Ly", type=pos_float, default=1.5625)
    ap.add_argument("--nx", type=pos_int, default=400)
    ap.add_argument("--ny", type=pos_int, default=400)
    ap.add_argument("--gamma", type=pos_int, default=20)
    ap.add_argument("--center-x", type=float, default=None)
    ap.add_argument("--center-y", type=float, default=None)
    ap.add_argument("--radius", type=pos_float, default=0.15625)
    ap.add_argument("--liquid-type", type=pos_int, default=1)
    ap.add_argument("--gas-type", type=pos_int, default=2)
    ap.add_argument("--liquid-mass", type=pos_float, default=1.0)
    ap.add_argument("--gas-mass", type=pos_float, default=0.1)
    ap.add_argument("--liquid-kBT", type=nonneg_float, default=0.02)
    ap.add_argument("--gas-kBT", type=nonneg_float, default=0.08)
    ap.add_argument("--seed", type=int, default=493150)
    args = ap.parse_args()

    if args.gamma < 2:
        ap.error("gamma must be >=2")
    if args.liquid_type == args.gas_type:
        ap.error("liquid and gas types must differ")
    cx = args.Lx * 0.5 if args.center_x is None else args.center_x
    cy = args.Ly * 0.5 if args.center_y is None else args.center_y
    if not (math.isfinite(cx) and math.isfinite(cy)):
        ap.error("center must be finite")

    dx, dy = args.Lx / args.nx, args.Ly / args.ny
    if abs(dx-dy) > 1e-12 * max(1.0, abs(dx), abs(dy)):
        ap.error("x14j drop requires square cells")

    ax = coprime_multiplier(args.gamma, 3)
    ay = coprime_multiplier(args.gamma, 7, avoid=ax)
    rng_l = random.Random(args.seed ^ 0x14A11)
    rng_g = random.Random(args.seed ^ 0x14A22)

    x = array("d"); y = array("d"); vx = array("d"); vy = array("d")
    typ = array("I"); mass = array("d"); role = bytearray()
    liquid_particles = gas_particles = mixed_cells = liquid_cells = gas_cells = 0

    r2 = args.radius * args.radius
    for iy in range(args.ny):
        for ix in range(args.nx):
            positions = []
            types = []
            for k in range(args.gamma):
                fx = ((ax * k) % args.gamma + 0.5) / args.gamma
                fy = ((ay * k) % args.gamma + 0.5) / args.gamma
                px, py = (ix + fx) * dx, (iy + fy) * dy
                inside = (px-cx)*(px-cx) + (py-cy)*(py-cy) <= r2
                positions.append((px, py))
                types.append(args.liquid_type if inside else args.gas_type)

            nl = sum(t == args.liquid_type for t in types)
            ng = args.gamma - nl
            if nl == args.gamma:
                liquid_cells += 1
            elif ng == args.gamma:
                gas_cells += 1
            else:
                mixed_cells += 1
            liquid_particles += nl
            gas_particles += ng

            vl = paired_velocities(rng_l, nl, args.liquid_mass, args.liquid_kBT)
            vg = paired_velocities(rng_g, ng, args.gas_mass, args.gas_kBT)
            il = ig = 0
            for (px, py), t in zip(positions, types):
                if t == args.liquid_type:
                    ux, uy = vl[il]; il += 1; m = args.liquid_mass
                else:
                    ux, uy = vg[ig]; ig += 1; m = args.gas_mass
                x.append(px); y.append(py); vx.append(ux); vy.append(uy)
                typ.append(t); mass.append(m); role.append(1)

    write_state(args.output, x, y, vx, vy, typ, mass, role)
    meta = {
        "profile": "circular_drop_two_temperature_0493x14j",
        "Lx": args.Lx, "Ly": args.Ly, "nx": args.nx, "ny": args.ny,
        "dx": dx, "dy": dy, "gamma": args.gamma,
        "centerX": cx, "centerY": cy, "radius": args.radius,
        "liquidType": args.liquid_type, "gasType": args.gas_type,
        "liquidMass": args.liquid_mass, "gasMass": args.gas_mass,
        "liquidKBT": args.liquid_kBT, "gasKBT": args.gas_kBT,
        "seed": args.seed, "particles": len(x),
        "liquidParticles": liquid_particles, "gasParticles": gas_particles,
        "liquidCells": liquid_cells, "gasCells": gas_cells, "mixedCells": mixed_cells,
        "liquidFractionParticles": liquid_particles / max(1, len(x)),
        "radiusCells": args.radius / dx,
    }
    meta_path = args.output.with_suffix(args.output.suffix + ".json")
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    print(
        "[0493x14j-generate] "
        f"grid={args.nx}x{args.ny} gamma={args.gamma} N={len(x)} "
        f"R/h={args.radius/dx:.6g} liquid={liquid_particles} gas={gas_particles} mixedCells={mixed_cells}"
    )
    print(
        "[0493x14j-generate] "
        f"mL/mG={args.liquid_mass/args.gas_mass:.6g} "
        f"kBT_L={args.liquid_kBT:.6g} kBT_G={args.gas_kBT:.6g}"
    )
    print(f"[0493x14j-generate] state={args.output}")
    print(f"[0493x14j-generate] metadata={meta_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

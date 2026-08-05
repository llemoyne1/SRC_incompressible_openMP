#!/usr/bin/env python3
"""Generate deterministic closed-box dam-break or liquid-only states.

The normal dam-break profile contains a liquid column and ambient gas with the
same particle count per cell; their density ratio is encoded by particle mass.
The optional liquid-only profile fills every cell with the liquid species and is
used to isolate the ability of Q6 to sustain a closed liquid under gravity.
Cellwise thermal velocities are paired and rescaled so every initial cell has
exactly zero mean velocity while retaining the requested two-dimensional
kinetic temperature.
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


def positive_int(text: str) -> int:
    value = int(text)
    if value <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return value


def positive_float(text: str) -> float:
    value = float(text)
    if not math.isfinite(value) or value <= 0.0:
        raise argparse.ArgumentTypeError("expected a finite positive number")
    return value


def nonnegative_float(text: str) -> float:
    value = float(text)
    if not math.isfinite(value) or value < 0.0:
        raise argparse.ArgumentTypeError("expected a finite non-negative number")
    return value


def coprime_multiplier(modulus: int, start: int, avoid: int = -1) -> int:
    for offset in range(modulus):
        candidate = 1 + ((start + offset - 1) % modulus)
        if candidate != avoid and math.gcd(candidate, modulus) == 1:
            return candidate
    return 1


def paired_thermal_velocities(
    rng: random.Random, count: int, mass: float, kbt: float
) -> list[tuple[float, float]]:
    if kbt == 0.0:
        return [(0.0, 0.0)] * count

    values: list[tuple[float, float]] = []
    for _ in range(count // 2):
        gx = rng.gauss(0.0, 1.0)
        gy = rng.gauss(0.0, 1.0)
        values.append((gx, gy))
        values.append((-gx, -gy))
    if count % 2:
        values.append((0.0, 0.0))

    sum_v2 = sum(vx * vx + vy * vy for vx, vy in values)
    if not sum_v2 > 0.0:
        values[0] = (1.0, 0.0)
        if count > 1:
            values[1] = (-1.0, 0.0)
        sum_v2 = sum(vx * vx + vy * vy for vx, vy in values)

    # In 2D, equipartition gives a mean peculiar kinetic energy kBT per
    # particle: 0.5*m*sum_i(|c_i|^2) = count*kBT.
    scale = math.sqrt((2.0 * count * kbt) / (mass * sum_v2))
    return [(scale * vx, scale * vy) for vx, vy in values]


def write_state(
    path: Path,
    x: array,
    y: array,
    vx: array,
    vy: array,
    typ: array,
    mass: array,
    role: bytearray,
) -> None:
    n = len(x)
    if not (len(y) == len(vx) == len(vy) == len(typ) == len(mass) == len(role) == n):
        raise RuntimeError("state arrays have inconsistent lengths")
    if array("d").itemsize != 8 or array("I").itemsize != 4:
        raise RuntimeError("unsupported native array element size")

    path.parent.mkdir(parents=True, exist_ok=True)
    reserved = [0] * 8
    reserved[0] = 1  # mass array present
    reserved[1] = 1  # role array present

    if sys.byteorder == "big":
        for values in (x, y, vx, vy, typ, mass):
            values.byteswap()
    try:
        with path.open("wb") as stream:
            stream.write(MAGIC)
            stream.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
            stream.write(struct.pack("<8Q", *reserved))
            for values in (x, y, vx, vy, typ, mass):
                values.tofile(stream)
            stream.write(role)
    finally:
        if sys.byteorder == "big":
            for values in (x, y, vx, vy, typ, mass):
                values.byteswap()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--Lx", type=positive_float, default=3.0)
    parser.add_argument("--Ly", type=positive_float, default=1.0)
    parser.add_argument("--nx", type=positive_int, default=900)
    parser.add_argument("--ny", type=positive_int, default=300)
    parser.add_argument("--gamma", type=positive_int, default=10)
    parser.add_argument("--column-width", type=positive_float, default=0.6)
    parser.add_argument("--column-height", type=positive_float, default=0.8)
    parser.add_argument("--liquid-type", type=positive_int, default=1)
    parser.add_argument("--gas-type", type=positive_int, default=2)
    parser.add_argument("--liquid-mass", type=positive_float, default=100.0)
    parser.add_argument("--gas-mass", type=positive_float, default=1.0)
    parser.add_argument("--kBT", type=nonnegative_float, default=0.005)
    parser.add_argument("--seed", type=int, default=493900)
    parser.add_argument(
        "--liquid-only",
        action="store_true",
        help="fill the complete closed box with the liquid species",
    )
    args = parser.parse_args()

    if args.liquid_type == args.gas_type:
        parser.error("liquid and gas particle types must differ")
    if (not args.liquid_only) and (
        args.column_width >= args.Lx or args.column_height >= args.Ly
    ):
        parser.error("the initial liquid column must leave a non-empty gas region")
    if args.gamma < 2:
        parser.error("gamma must be at least 2")

    count = args.nx * args.ny * args.gamma
    x = array("d")
    y = array("d")
    vx = array("d")
    vy = array("d")
    typ = array("I")
    mass = array("d")
    role = bytearray()

    ax = coprime_multiplier(args.gamma, 3)
    ay = coprime_multiplier(args.gamma, 7, avoid=ax)
    rng = random.Random(args.seed)
    dx = args.Lx / args.nx
    dy = args.Ly / args.ny

    liquid_cells = 0
    gas_cells = 0
    liquid_particles = 0
    gas_particles = 0
    total_px = 0.0
    total_py = 0.0

    for iy in range(args.ny):
        yc = (iy + 0.5) * dy
        for ix in range(args.nx):
            xc = (ix + 0.5) * dx
            is_liquid = args.liquid_only or (
                xc < args.column_width and yc < args.column_height
            )
            particle_type = args.liquid_type if is_liquid else args.gas_type
            particle_mass = args.liquid_mass if is_liquid else args.gas_mass
            thermal = paired_thermal_velocities(rng, args.gamma, particle_mass, args.kBT)
            if is_liquid:
                liquid_cells += 1
                liquid_particles += args.gamma
            else:
                gas_cells += 1
                gas_particles += args.gamma

            for k, (ux, uy) in enumerate(thermal):
                fx = ((ax * k) % args.gamma + 0.5) / args.gamma
                fy = ((ay * k) % args.gamma + 0.5) / args.gamma
                x.append((ix + fx) * dx)
                y.append((iy + fy) * dy)
                vx.append(ux)
                vy.append(uy)
                typ.append(particle_type)
                mass.append(particle_mass)
                role.append(1)  # ParticleRole::Fluid
                total_px += particle_mass * ux
                total_py += particle_mass * uy

    if len(x) != count:
        raise RuntimeError(f"generated {len(x)} particles, expected {count}")

    write_state(args.output, x, y, vx, vy, typ, mass, role)
    metadata = {
        "profile": "liquid_only" if args.liquid_only else "dam_break",
        "liquid_only": args.liquid_only,
        "Lx": args.Lx,
        "Ly": args.Ly,
        "nx": args.nx,
        "ny": args.ny,
        "gamma": args.gamma,
        "column_width": args.column_width,
        "column_height": args.column_height,
        "liquid_type": args.liquid_type,
        "gas_type": args.gas_type,
        "liquid_mass": args.liquid_mass,
        "gas_mass": args.gas_mass,
        "density_ratio_proxy": args.liquid_mass / args.gas_mass,
        "kBT": args.kBT,
        "seed": args.seed,
        "fluid_particles": count,
        "liquid_cells": liquid_cells,
        "gas_cells": gas_cells,
        "liquid_particles": liquid_particles,
        "gas_particles": gas_particles,
        "total_mass": liquid_particles * args.liquid_mass + gas_particles * args.gas_mass,
        "total_momentum_x": total_px,
        "total_momentum_y": total_py,
        "position_multiplier_x": ax,
        "position_multiplier_y": ay,
    }
    metadata_path = args.output.with_suffix(args.output.suffix + ".json")
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    print(
        f"[0493x0-state] profile={metadata['profile']} state={args.output} "
        f"grid={args.nx}x{args.ny} "
        f"gamma={args.gamma} fluid={count} liquid={liquid_particles} gas={gas_particles} "
        f"massRatio={args.liquid_mass / args.gas_mass:.6g} "
        f"P=({total_px:.3e},{total_py:.3e})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

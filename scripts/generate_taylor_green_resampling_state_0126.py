#!/usr/bin/env python3
"""Generate a V2 .smpcd Taylor--Green initial state without MATLAB.

This script intentionally has no third-party dependency.  It mirrors the MATLAB
TG generator used by the 0126 OpenMP resampling validator and writes the compact
SRCMPCD_STATE V2 payload:

    x, y, vx, vy, type(uint32), mass(double), role(uint8)

Role convention: 0=Inactive, 1=Fluid, 2=Latent.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import struct
from typing import List

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
ENDIAN_MARKER = 0x01020304
VERSION_V2 = 2
ROLE_FLUID = 1


def positive_int(text: str) -> int:
    value = int(text)
    if value <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return value


def positive_float(text: str) -> float:
    value = float(text)
    if value <= 0.0:
        raise argparse.ArgumentTypeError("expected a positive float")
    return value


def nonnegative_float(text: str) -> float:
    value = float(text)
    if value < 0.0:
        raise argparse.ArgumentTypeError("expected a non-negative float")
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a periodic Taylor--Green .smpcd V2 state for OpenMP resampling validation."
    )
    parser.add_argument("--output", required=True, help="Output .smpcd path")
    parser.add_argument("--Lx", type=positive_float, default=1.0)
    parser.add_argument("--Ly", type=positive_float, default=1.0)
    parser.add_argument("--Nx", type=positive_int, default=32)
    parser.add_argument("--Ny", type=positive_int, default=32)
    parser.add_argument("--gamma", type=positive_int, default=20)
    parser.add_argument("--flow-amplitude", type=nonnegative_float, default=0.08)
    parser.add_argument("--kx-mode", type=positive_int, default=1)
    parser.add_argument("--ky-mode", type=positive_int, default=1)
    parser.add_argument("--kBT", type=nonnegative_float, default=0.001)
    parser.add_argument("--mass", type=positive_float, default=1.0)
    parser.add_argument("--type", type=int, default=0, dest="ptype")
    parser.add_argument("--seed", type=int, default=1260126)
    parser.add_argument(
        "--position-mode",
        choices=("uniform_per_cell",),
        default="uniform_per_cell",
        help="Only uniform_per_cell is implemented to keep exactly gamma particles per cell.",
    )
    parser.add_argument(
        "--no-remove-mean-momentum",
        action="store_true",
        help="Do not subtract the global mass-weighted mean velocity after generation.",
    )
    return parser.parse_args()


def write_smpcd_v2(
    filename: str,
    x: List[float],
    y: List[float],
    vx: List[float],
    vy: List[float],
    ptype: List[int],
    mass: List[float],
    role: List[int],
) -> None:
    n = len(x)
    if not (len(y) == len(vx) == len(vy) == len(ptype) == len(mass) == len(role) == n):
        raise ValueError("all arrays must have the same length")

    out_dir = os.path.dirname(filename)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    reserved = [0] * 8
    reserved[0] = 1  # has role payload
    reserved[1] = 1  # role scalar size, bytes

    with open(filename, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<IIIIQIIII", VERSION_V2, ENDIAN_MARKER, 2, 1, n, 1, 1, 8, 4))
        f.write(struct.pack("<8Q", *reserved))
        f.write(struct.pack(f"<{n}d", *x))
        f.write(struct.pack(f"<{n}d", *y))
        f.write(struct.pack(f"<{n}d", *vx))
        f.write(struct.pack(f"<{n}d", *vy))
        f.write(struct.pack(f"<{n}I", *ptype))
        f.write(struct.pack(f"<{n}d", *mass))
        f.write(struct.pack(f"<{n}B", *role))


def main() -> int:
    args = parse_args()
    rng = random.Random(args.seed)

    n_particles = args.Nx * args.Ny * args.gamma
    dx = args.Lx / args.Nx
    dy = args.Ly / args.Ny
    sigma = math.sqrt(args.kBT / args.mass) if args.kBT > 0.0 else 0.0

    x: List[float] = []
    y: List[float] = []
    vx: List[float] = []
    vy: List[float] = []
    ptype: List[int] = []
    mass: List[float] = []
    role: List[int] = []

    two_pi = 2.0 * math.pi
    for j in range(args.Ny):
        y0 = j * dy
        for i in range(args.Nx):
            x0 = i * dx
            for _ in range(args.gamma):
                xp = x0 + dx * rng.random()
                yp = y0 + dy * rng.random()
                ux = args.flow_amplitude * math.sin(two_pi * args.kx_mode * xp / args.Lx) * math.cos(
                    two_pi * args.ky_mode * yp / args.Ly
                )
                uy = -args.flow_amplitude * math.cos(two_pi * args.kx_mode * xp / args.Lx) * math.sin(
                    two_pi * args.ky_mode * yp / args.Ly
                )
                if sigma > 0.0:
                    ux += sigma * rng.gauss(0.0, 1.0)
                    uy += sigma * rng.gauss(0.0, 1.0)
                x.append(xp)
                y.append(yp)
                vx.append(ux)
                vy.append(uy)
                ptype.append(args.ptype)
                mass.append(args.mass)
                role.append(ROLE_FLUID)

    if not args.no_remove_mean_momentum and n_particles > 0:
        total_mass = sum(mass)
        mean_vx = sum(m * u for m, u in zip(mass, vx)) / total_mass
        mean_vy = sum(m * u for m, u in zip(mass, vy)) / total_mass
        vx = [u - mean_vx for u in vx]
        vy = [u - mean_vy for u in vy]
    else:
        mean_vx = 0.0
        mean_vy = 0.0

    write_smpcd_v2(args.output, x, y, vx, vy, ptype, mass, role)

    print("Generated Taylor--Green resampling V2 state:")
    print(f"  output     : {args.output}")
    print(f"  grid       : {args.Nx} x {args.Ny}")
    print(f"  gamma      : {args.gamma}")
    print(f"  particles  : {n_particles}")
    print(f"  U0/kBT     : {args.flow_amplitude:.12g} / {args.kBT:.12g}")
    print(f"  meanV sub. : {mean_vx:.12e} / {mean_vy:.12e}")
    print(f"  roles      : Fluid={n_particles} Latent=0 Inactive=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

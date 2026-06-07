#!/usr/bin/env python3
"""Generate compact SRC/MPCD V2 validation states without MATLAB.

The generator is intentionally small and deterministic.  It is used by the
0162 mono-configuration validation campaign so that origin and optimized source
trees can run exactly the same initial particle sets.

Payload format: x,y,vx,vy,type(uint32),mass(double),role(uint8).
Role convention: 0=Inactive, 1=Fluid, 2=Latent.
"""
from __future__ import annotations

import argparse
import math
import os
import random
import struct
from typing import Iterable, List, Sequence, Tuple

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
ENDIAN_MARKER = 0x01020304
VERSION_V2 = 2
ROLE_INACTIVE = 0
ROLE_FLUID = 1

Rect = Tuple[float, float, float, float]


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


def parse_rect(text: str) -> Rect:
    parts = [float(x) for x in text.replace(",", " ").split()]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("solid rect must be 'xmin,xmax,ymin,ymax'")
    xmin, xmax, ymin, ymax = parts
    if not (xmax > xmin and ymax > ymin):
        raise argparse.ArgumentTypeError("invalid solid rect bounds")
    return xmin, xmax, ymin, ymax


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate deterministic validation .smpcd V2 states.")
    p.add_argument("--output", required=True)
    p.add_argument("--Lx", type=positive_float, default=1.0)
    p.add_argument("--Ly", type=positive_float, default=1.0)
    p.add_argument("--Nx", type=positive_int, default=64)
    p.add_argument("--Ny", type=positive_int, default=64)
    p.add_argument("--gamma", type=positive_int, default=20)
    p.add_argument("--kBT", type=nonnegative_float, default=0.001)
    p.add_argument("--mass", type=positive_float, default=1.0)
    p.add_argument("--mass-factor", type=positive_float, default=1.0)
    p.add_argument("--type", type=int, default=0, dest="ptype")
    p.add_argument("--seed", type=int, default=1620162)
    p.add_argument("--mean-ux", type=float, default=0.0)
    p.add_argument("--mean-uy", type=float, default=0.0)
    p.add_argument(
        "--flow-mode",
        choices=("zero", "uniform", "taylor_green", "poiseuille_x"),
        default="uniform",
    )
    p.add_argument("--flow-amplitude", type=nonnegative_float, default=0.08)
    p.add_argument("--kx-mode", type=positive_int, default=1)
    p.add_argument("--ky-mode", type=positive_int, default=1)
    p.add_argument("--active-x-min", type=float, default=0.0)
    p.add_argument("--active-x-max", type=float, default=-1.0, help="negative means Lx")
    p.add_argument("--active-y-min", type=float, default=0.0)
    p.add_argument("--active-y-max", type=float, default=-1.0, help="negative means Ly")
    p.add_argument("--solid-rect", action="append", type=parse_rect, default=[])
    p.add_argument(
        "--inactive-slots",
        type=int,
        default=0,
        help="Append this many inactive V2 particle slots for resident GPU reservoir tests.",
    )
    p.add_argument(
        "--skip-cell-if-center-in-solid",
        action="store_true",
        default=True,
        help="Skip cells whose center is inside any solid rectangle.",
    )
    p.add_argument(
        "--no-remove-mean-momentum",
        action="store_true",
        help="Do not subtract the global mass-weighted mean thermal/mode residual velocity.",
    )
    return p.parse_args()


def write_smpcd_v2(filename: str,
                   x: Sequence[float], y: Sequence[float],
                   vx: Sequence[float], vy: Sequence[float],
                   ptype: Sequence[int], mass: Sequence[float], role: Sequence[int]) -> None:
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


def in_rect(x: float, y: float, rect: Rect) -> bool:
    xmin, xmax, ymin, ymax = rect
    return xmin <= x <= xmax and ymin <= y <= ymax


def in_any_rect(x: float, y: float, rects: Iterable[Rect]) -> bool:
    return any(in_rect(x, y, r) for r in rects)


def base_velocity(args: argparse.Namespace, xp: float, yp: float) -> Tuple[float, float]:
    if args.flow_mode == "zero":
        return 0.0, 0.0
    if args.flow_mode == "uniform":
        return args.mean_ux, args.mean_uy
    if args.flow_mode == "taylor_green":
        two_pi = 2.0 * math.pi
        ux = args.flow_amplitude * math.sin(two_pi * args.kx_mode * xp / args.Lx) * math.cos(
            two_pi * args.ky_mode * yp / args.Ly
        )
        uy = -args.flow_amplitude * math.cos(two_pi * args.kx_mode * xp / args.Lx) * math.sin(
            two_pi * args.ky_mode * yp / args.Ly
        )
        return ux + args.mean_ux, uy + args.mean_uy
    if args.flow_mode == "poiseuille_x":
        y0 = args.active_y_min
        y1 = args.active_y_max if args.active_y_max > 0.0 else args.Ly
        yc = 0.5 * (y0 + y1)
        half = max(1e-15, 0.5 * (y1 - y0))
        eta = (yp - yc) / half
        shape = max(0.0, 1.0 - eta * eta)
        return args.mean_ux * shape, args.mean_uy
    raise ValueError(f"unsupported flow mode {args.flow_mode}")


def main() -> int:
    args = parse_args()
    rng = random.Random(args.seed)
    ax0 = args.active_x_min
    ax1 = args.active_x_max if args.active_x_max > 0.0 else args.Lx
    ay0 = args.active_y_min
    ay1 = args.active_y_max if args.active_y_max > 0.0 else args.Ly
    if not (0.0 <= ax0 < ax1 <= args.Lx and 0.0 <= ay0 < ay1 <= args.Ly):
        raise SystemExit("invalid active-domain bounds")
    if args.inactive_slots < 0:
        raise SystemExit("--inactive-slots must be non-negative")

    dx = args.Lx / args.Nx
    dy = args.Ly / args.Ny
    particle_mass = args.mass * args.mass_factor
    sigma = math.sqrt(args.kBT / particle_mass) if args.kBT > 0.0 else 0.0

    x: List[float] = []
    y: List[float] = []
    vx: List[float] = []
    vy: List[float] = []
    ptype: List[int] = []
    mass: List[float] = []
    role: List[int] = []

    active_cells = 0
    skipped_cells = 0
    rejected_samples = 0
    for j in range(args.Ny):
        cy = (j + 0.5) * dy
        if cy < ay0 or cy > ay1:
            skipped_cells += 1
            continue
        for i in range(args.Nx):
            cx = (i + 0.5) * dx
            if cx < ax0 or cx > ax1:
                skipped_cells += 1
                continue
            if args.skip_cell_if_center_in_solid and in_any_rect(cx, cy, args.solid_rect):
                skipped_cells += 1
                continue
            x0 = i * dx
            y0 = j * dy
            active_cells += 1
            for _ in range(args.gamma):
                accepted = False
                for _attempt in range(1000):
                    xp = x0 + dx * rng.random()
                    yp = y0 + dy * rng.random()
                    if xp < ax0 or xp > ax1 or yp < ay0 or yp > ay1:
                        rejected_samples += 1
                        continue
                    if in_any_rect(xp, yp, args.solid_rect):
                        rejected_samples += 1
                        continue
                    accepted = True
                    break
                if not accepted:
                    # A cut cell almost fully occupied by the solid; leave it empty.
                    continue
                ux, uy = base_velocity(args, xp, yp)
                if sigma > 0.0:
                    ux += sigma * rng.gauss(0.0, 1.0)
                    uy += sigma * rng.gauss(0.0, 1.0)
                x.append(xp)
                y.append(yp)
                vx.append(ux)
                vy.append(uy)
                ptype.append(args.ptype)
                mass.append(particle_mass)
                role.append(ROLE_FLUID)

    n = len(x)
    if n == 0:
        raise SystemExit("generated zero particles")

    if not args.no_remove_mean_momentum:
        total_mass = sum(mass)
        mean_vx = sum(m * u for m, u in zip(mass, vx)) / total_mass
        mean_vy = sum(m * u for m, u in zip(mass, vy)) / total_mass
        # Preserve requested imposed mean flow for uniform/poiseuille inlet states.
        target_vx = args.mean_ux if args.flow_mode in ("uniform", "poiseuille_x") else 0.0
        target_vy = args.mean_uy if args.flow_mode in ("uniform", "poiseuille_x") else 0.0
        vx = [u - mean_vx + target_vx for u in vx]
        vy = [v - mean_vy + target_vy for v in vy]
    else:
        mean_vx = 0.0
        mean_vy = 0.0

    inactive_slots = int(args.inactive_slots)
    if inactive_slots > 0:
        # Inactive slots are ignored by the physics until a hard inlet reservoir
        # activates them.  Place them inside the numerical box with finite,
        # harmless values so the standard state validator accepts the payload.
        x.extend([ax0] * inactive_slots)
        y.extend([ay0] * inactive_slots)
        vx.extend([0.0] * inactive_slots)
        vy.extend([0.0] * inactive_slots)
        ptype.extend([args.ptype] * inactive_slots)
        mass.extend([particle_mass] * inactive_slots)
        role.extend([ROLE_INACTIVE] * inactive_slots)

    write_smpcd_v2(args.output, x, y, vx, vy, ptype, mass, role)
    print("Generated validation V2 state:")
    print(f"  output        : {args.output}")
    print(f"  grid          : {args.Nx} x {args.Ny}")
    print(f"  active cells  : {active_cells}")
    print(f"  skipped cells : {skipped_cells}")
    print(f"  fluid particles : {n}")
    print(f"  inactive slots  : {inactive_slots}")
    print(f"  particles       : {n + inactive_slots}")
    print(f"  gamma target  : {args.gamma}")
    print(f"  mass factor   : {args.mass_factor:.12g}")
    print(f"  flow/kBT      : {args.flow_mode} / {args.kBT:.12g}")
    print(f"  rejected      : {rejected_samples}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

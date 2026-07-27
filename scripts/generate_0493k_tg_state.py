#!/usr/bin/env python3
"""Generate deterministic periodic Taylor--Green states for qualification 0493k.

The mono state is shared by the legacy and resident-species mono runs.  The
binary state has a uniform total cell mass and a weak species-mass-fraction
mode aligned with the Taylor--Green stream function:

    c1 = 1/2 + eps sin(kx x) sin(ky y),  c2 = 1 - c1.

Each species has paired opposite peculiar velocities, so every cell and every
species starts with the requested barycentric Taylor--Green velocity and zero
peculiar momentum.
"""
from __future__ import annotations

import argparse
import math
import os
import struct
from pathlib import Path


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--scenario", choices=("mono", "binary"), required=True)
    ap.add_argument("--nx", type=int, default=32)
    ap.add_argument("--ny", type=int, default=32)
    ap.add_argument("--gamma", type=int, default=20)
    ap.add_argument("--tg-mode", type=int, default=1)
    ap.add_argument("--tg-amplitude", type=float, default=0.08)
    ap.add_argument("--composition-amplitude", type=float, default=0.15)
    ap.add_argument("--thermal-amplitude", type=float, default=0.04)
    ap.add_argument("--particle-mass", type=float, default=1.0)
    ap.add_argument("--inactive-per-cell", type=int, default=8)
    return ap.parse_args()


def validate(a: argparse.Namespace) -> None:
    if a.nx < 8 or a.ny < 8:
        raise SystemExit("[0493k-state] ERROR nx and ny must be >= 8")
    if a.gamma < 4 or a.gamma % 2:
        raise SystemExit("[0493k-state] ERROR gamma must be even and >= 4")
    if a.scenario == "binary" and a.gamma % 4:
        raise SystemExit("[0493k-state] ERROR binary gamma must be divisible by 4")
    if a.tg_mode < 1 or a.inactive_per_cell < 2:
        raise SystemExit("[0493k-state] ERROR tg-mode>=1 and inactive-per-cell>=2 required")
    vals = (
        a.tg_amplitude,
        a.composition_amplitude,
        a.thermal_amplitude,
        a.particle_mass,
    )
    if not all(math.isfinite(v) for v in vals):
        raise SystemExit("[0493k-state] ERROR non-finite physical parameter")
    if a.tg_amplitude <= 0.0 or a.thermal_amplitude < 0.0 or a.particle_mass <= 0.0:
        raise SystemExit("[0493k-state] ERROR require U0>0, thermal>=0 and mass>0")
    if not 0.0 < a.composition_amplitude < 0.45:
        raise SystemExit("[0493k-state] ERROR composition amplitude must be in (0,0.45)")


def slot_position(slot: int, count: int) -> tuple[float, float]:
    """Deterministic low-discrepancy offsets strictly inside one cell."""
    fx = ((slot + 0.5) * 0.6180339887498949) % 1.0
    fy = ((slot + 0.5) * 0.4142135623730950) % 1.0
    margin = 0.08
    return margin + (1.0 - 2.0 * margin) * fx, margin + (1.0 - 2.0 * margin) * fy


def append_pair(
    x: list[float], y: list[float], vx: list[float], vy: list[float],
    typ: list[int], mass: list[float], role: list[int],
    *, i: int, j: int, nx: int, ny: int, slot0: int, slot_count: int,
    type_id: int, particle_mass: float, bulk_x: float, bulk_y: float,
    thermal: float, theta: float,
) -> None:
    tx = thermal * math.cos(theta)
    ty = thermal * math.sin(theta)
    # Paired particles use distinct mirrored sub-cell positions but exactly
    # opposite peculiar velocities and equal masses.
    f0x, f0y = slot_position(slot0, slot_count)
    f1x, f1y = 1.0 - f0x, 1.0 - f0y
    for sign, fx, fy in ((1.0, f0x, f0y), (-1.0, f1x, f1y)):
        x.append((i + fx) / nx)
        y.append((j + fy) / ny)
        vx.append(bulk_x + sign * tx)
        vy.append(bulk_y + sign * ty)
        typ.append(type_id)
        mass.append(particle_mass)
        role.append(1)


def generate(a: argparse.Namespace) -> None:
    x: list[float] = []
    y: list[float] = []
    vx: list[float] = []
    vy: list[float] = []
    typ: list[int] = []
    mass: list[float] = []
    role: list[int] = []

    k = 2.0 * math.pi * a.tg_mode
    species_mass = {1: 0.0, 2: 0.0}
    species_px = {1: 0.0, 2: 0.0}
    species_py = {1: 0.0, 2: 0.0}
    composition_min = 1.0
    composition_max = 0.0

    for j in range(a.ny):
        yc = (j + 0.5) / a.ny
        sy = math.sin(k * yc)
        cy = math.cos(k * yc)
        for i in range(a.nx):
            xc = (i + 0.5) / a.nx
            sx = math.sin(k * xc)
            cx = math.cos(k * xc)
            bulk_x = a.tg_amplitude * sx * cy
            bulk_y = -a.tg_amplitude * cx * sy

            if a.scenario == "mono":
                pair_count = a.gamma // 2
                for p in range(pair_count):
                    theta = 2.0 * math.pi * (p + 0.5) / pair_count
                    before = len(x)
                    append_pair(
                        x, y, vx, vy, typ, mass, role,
                        i=i, j=j, nx=a.nx, ny=a.ny,
                        slot0=2 * p, slot_count=a.gamma,
                        type_id=1, particle_mass=a.particle_mass,
                        bulk_x=bulk_x, bulk_y=bulk_y,
                        thermal=a.thermal_amplitude, theta=theta,
                    )
                    for q in range(before, len(x)):
                        species_mass[1] += mass[q]
                        species_px[1] += mass[q] * vx[q]
                        species_py[1] += mass[q] * vy[q]
            else:
                c1 = 0.5 + a.composition_amplitude * sx * sy
                c2 = 1.0 - c1
                composition_min = min(composition_min, c1)
                composition_max = max(composition_max, c1)
                count_per_species = a.gamma // 2
                pair_count = count_per_species // 2
                particle_masses = {
                    1: 2.0 * a.particle_mass * c1,
                    2: 2.0 * a.particle_mass * c2,
                }
                for sidx, type_id in enumerate((1, 2)):
                    for p in range(pair_count):
                        theta = 2.0 * math.pi * (p + 0.5 + 0.25 * sidx) / pair_count
                        before = len(x)
                        append_pair(
                            x, y, vx, vy, typ, mass, role,
                            i=i, j=j, nx=a.nx, ny=a.ny,
                            slot0=sidx * count_per_species + 2 * p,
                            slot_count=a.gamma,
                            type_id=type_id, particle_mass=particle_masses[type_id],
                            bulk_x=bulk_x, bulk_y=bulk_y,
                            thermal=a.thermal_amplitude, theta=theta,
                        )
                        for q in range(before, len(x)):
                            species_mass[type_id] += mass[q]
                            species_px[type_id] += mass[q] * vx[q]
                            species_py[type_id] += mass[q] * vy[q]

    active = len(x)
    inactive = a.nx * a.ny * a.inactive_per_cell
    for _ in range(inactive):
        x.append(0.0)
        y.append(0.0)
        vx.append(0.0)
        vy.append(0.0)
        typ.append(0)
        mass.append(a.particle_mass)
        role.append(0)

    a.output.parent.mkdir(parents=True, exist_ok=True)
    magic = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    n = len(x)
    with a.output.open("wb") as stream:
        stream.write(magic)
        stream.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        stream.write(struct.pack("<8Q", *reserved))
        for values, fmt in (
            (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
            (typ, "I"), (mass, "d"), (role, "B"),
        ):
            stream.write(struct.pack(f"<{n}{fmt}", *values))

    total_mass = math.fsum(mass[:active])
    total_px = math.fsum(m * u for m, u in zip(mass[:active], vx[:active]))
    total_py = math.fsum(m * v for m, v in zip(mass[:active], vy[:active]))
    mass_min = min(mass[:active])
    mass_max = max(mass[:active])
    print(
        f"[0493k-state] path={a.output} scenario={a.scenario} "
        f"grid={a.nx}x{a.ny} gamma={a.gamma} fluid={active} inactive={inactive} "
        f"U0={a.tg_amplitude:.17g} thermal={a.thermal_amplitude:.17g} "
        f"mass={total_mass:.17g} px={total_px:.3e} py={total_py:.3e} "
        f"particleMassMinMax={mass_min:.9g}/{mass_max:.9g}"
    )
    if a.scenario == "binary":
        print(
            f"[0493k-state] compositionAmplitude={a.composition_amplitude:.17g} "
            f"c1MinMax={composition_min:.9g}/{composition_max:.9g} "
            f"M1={species_mass[1]:.17g} M2={species_mass[2]:.17g} "
            f"P1=({species_px[1]:.3e},{species_py[1]:.3e}) "
            f"P2=({species_px[2]:.3e},{species_py[2]:.3e})"
        )


def main() -> int:
    args = parse_args()
    validate(args)
    generate(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

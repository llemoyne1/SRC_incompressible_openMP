#!/usr/bin/env python3
"""Generate physically identical mono-type and dual-type Taylor--Green states.

The two state files contain exactly the same positions, velocities, masses and
roles.  Only the active-particle type array differs.  In the dual state, whole
opposite-peculiar-velocity pairs are assigned alternately to types 1 and 2, so
each type has exactly half the particles and exactly the requested cell
barycentric Taylor--Green velocity.
"""
from __future__ import annotations

import argparse
import hashlib
import math
import struct
from pathlib import Path


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mono-output", type=Path, required=True)
    ap.add_argument("--dual-output", type=Path, required=True)
    ap.add_argument("--nx", type=int, default=24)
    ap.add_argument("--ny", type=int, default=24)
    ap.add_argument("--gamma", type=int, default=32)
    ap.add_argument("--tg-mode", type=int, default=1)
    ap.add_argument("--tg-amplitude", type=float, default=0.08)
    ap.add_argument("--thermal-amplitude", type=float, default=0.04)
    ap.add_argument("--particle-mass", type=float, default=1.0)
    ap.add_argument("--inactive-per-cell", type=int, default=0)
    return ap.parse_args()


def validate(a: argparse.Namespace) -> None:
    if a.nx < 8 or a.ny < 8:
        raise SystemExit("[0493w8-state] ERROR nx and ny must be >= 8")
    if a.gamma < 8 or a.gamma % 4:
        raise SystemExit("[0493w8-state] ERROR gamma must be divisible by 4 and >= 8")
    if a.tg_mode < 1 or a.inactive_per_cell < 0:
        raise SystemExit("[0493w8-state] ERROR tg-mode>=1 and inactive-per-cell>=0 required")
    vals = (a.tg_amplitude, a.thermal_amplitude, a.particle_mass)
    if not all(math.isfinite(v) for v in vals):
        raise SystemExit("[0493w8-state] ERROR non-finite physical parameter")
    if a.tg_amplitude <= 0.0 or a.thermal_amplitude < 0.0 or a.particle_mass <= 0.0:
        raise SystemExit("[0493w8-state] ERROR require U0>0, thermal>=0 and mass>0")


def slot_position(slot: int, count: int) -> tuple[float, float]:
    fx = ((slot + 0.5) * 0.6180339887498949) % 1.0
    fy = ((slot + 0.5) * 0.4142135623730950) % 1.0
    margin = 0.08
    return margin + (1.0 - 2.0 * margin) * fx, margin + (1.0 - 2.0 * margin) * fy


def append_pair(
    x: list[float], y: list[float], vx: list[float], vy: list[float],
    mono_type: list[int], dual_type: list[int], mass: list[float], role: list[int],
    *, i: int, j: int, nx: int, ny: int, pair_index: int, pair_count: int,
    gamma: int, particle_mass: float, bulk_x: float, bulk_y: float,
    thermal: float,
) -> None:
    theta = 2.0 * math.pi * (pair_index + 0.5) / pair_count
    tx = thermal * math.cos(theta)
    ty = thermal * math.sin(theta)
    f0x, f0y = slot_position(2 * pair_index, gamma)
    f1x, f1y = 1.0 - f0x, 1.0 - f0y
    # Assign complete +/- peculiar-velocity pairs to one type.  Each pair has
    # zero peculiar momentum by itself; each type is therefore barycentrically
    # identical to the mono fluid in every cell.
    split_type = 1 if pair_index < pair_count // 2 else 2
    for sign, fx, fy in ((1.0, f0x, f0y), (-1.0, f1x, f1y)):
        x.append((i + fx) / nx)
        y.append((j + fy) / ny)
        vx.append(bulk_x + sign * tx)
        vy.append(bulk_y + sign * ty)
        mono_type.append(1)
        dual_type.append(split_type)
        mass.append(particle_mass)
        role.append(1)


def write_state(
    path: Path,
    x: list[float], y: list[float], vx: list[float], vy: list[float],
    typ: list[int], mass: list[float], role: list[int],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    magic = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    n = len(x)
    with path.open("wb") as stream:
        stream.write(magic)
        stream.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        stream.write(struct.pack("<8Q", *reserved))
        for values, fmt in (
            (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
            (typ, "I"), (mass, "d"), (role, "B"),
        ):
            stream.write(struct.pack(f"<{n}{fmt}", *values))


def physical_digest(
    x: list[float], y: list[float], vx: list[float], vy: list[float],
    mass: list[float], role: list[int],
) -> str:
    h = hashlib.sha256()
    for values, fmt in ((x, "d"), (y, "d"), (vx, "d"), (vy, "d"), (mass, "d"), (role, "B")):
        h.update(struct.pack(f"<{len(values)}{fmt}", *values))
    return h.hexdigest()


def main() -> int:
    a = parse_args()
    validate(a)
    x: list[float] = []
    y: list[float] = []
    vx: list[float] = []
    vy: list[float] = []
    mono_type: list[int] = []
    dual_type: list[int] = []
    mass: list[float] = []
    role: list[int] = []

    k = 2.0 * math.pi * a.tg_mode
    pair_count = a.gamma // 2
    for j in range(a.ny):
        yc = (j + 0.5) / a.ny
        sy, cy = math.sin(k * yc), math.cos(k * yc)
        for i in range(a.nx):
            xc = (i + 0.5) / a.nx
            sx, cx = math.sin(k * xc), math.cos(k * xc)
            bulk_x = a.tg_amplitude * sx * cy
            bulk_y = -a.tg_amplitude * cx * sy
            for p in range(pair_count):
                append_pair(
                    x, y, vx, vy, mono_type, dual_type, mass, role,
                    i=i, j=j, nx=a.nx, ny=a.ny, pair_index=p,
                    pair_count=pair_count, gamma=a.gamma,
                    particle_mass=a.particle_mass, bulk_x=bulk_x, bulk_y=bulk_y,
                    thermal=a.thermal_amplitude,
                )

    active = len(x)
    inactive = a.nx * a.ny * a.inactive_per_cell
    for _ in range(inactive):
        x.append(0.0)
        y.append(0.0)
        vx.append(0.0)
        vy.append(0.0)
        mono_type.append(0)
        dual_type.append(0)
        mass.append(a.particle_mass)
        role.append(0)

    write_state(a.mono_output, x, y, vx, vy, mono_type, mass, role)
    write_state(a.dual_output, x, y, vx, vy, dual_type, mass, role)

    digest = physical_digest(x, y, vx, vy, mass, role)
    dual1 = sum(1 for t, r in zip(dual_type, role) if r == 1 and t == 1)
    dual2 = sum(1 for t, r in zip(dual_type, role) if r == 1 and t == 2)
    total_mass = math.fsum(m for m, r in zip(mass, role) if r == 1)
    total_px = math.fsum(m * u for m, u, r in zip(mass, vx, role) if r == 1)
    total_py = math.fsum(m * v for m, v, r in zip(mass, vy, role) if r == 1)
    print(
        f"[0493w8-state] mono={a.mono_output} dual={a.dual_output} "
        f"grid={a.nx}x{a.ny} gamma={a.gamma} fluid={active} inactive={inactive} "
        f"dualTypes={dual1}/{dual2} mass={total_mass:.17g} "
        f"px={total_px:.3e} py={total_py:.3e} physicalSha256={digest}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

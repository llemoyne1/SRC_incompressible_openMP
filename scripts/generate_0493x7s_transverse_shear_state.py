#!/usr/bin/env python3
"""Generate an exactly cell-barycentric transverse shear-wave MPCD state.

The coherent field is
    u_x(y) = A sin(2*pi*m*y/Ly),  u_y = 0,
with the sine evaluated at collision-cell centres.  In every cell, the thermal
peculiar velocities have exactly zero barycentric momentum and are rescaled to
the requested 2-D peculiar kinetic energy N*kBT.  This makes the initial
coherent mode identical across SRC, legacy Q6 and Q6-g-f comparisons.
"""
from __future__ import annotations

import argparse
import math
import random
import struct
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--Lx", type=float, required=True)
    p.add_argument("--Ly", type=float, required=True)
    p.add_argument("--Nx", type=int, required=True)
    p.add_argument("--Ny", type=int, required=True)
    p.add_argument("--gamma", type=int, required=True)
    p.add_argument("--kBT", type=float, required=True)
    p.add_argument("--mass", type=float, default=1.0)
    p.add_argument("--seed", type=int, required=True)
    p.add_argument("--wave-mode", type=int, default=1)
    p.add_argument("--wave-amplitude", type=float, default=0.6)
    p.add_argument("--particle-type", type=int, default=0)
    return p.parse_args()


def validate(a: argparse.Namespace) -> None:
    vals = (a.Lx, a.Ly, a.kBT, a.mass, a.wave_amplitude)
    if not all(math.isfinite(v) for v in vals):
        raise SystemExit("[0493x7s-state] ERROR non-finite physical parameter")
    if a.Lx <= 0 or a.Ly <= 0 or a.kBT <= 0 or a.mass <= 0 or a.wave_amplitude <= 0:
        raise SystemExit("[0493x7s-state] ERROR require Lx,Ly,kBT,mass,amplitude > 0")
    if a.Nx < 8 or a.Ny < 8 or a.gamma < 4:
        raise SystemExit("[0493x7s-state] ERROR require Nx,Ny>=8 and gamma>=4")
    if a.wave_mode < 1 or 2 * a.wave_mode >= a.Ny:
        raise SystemExit("[0493x7s-state] ERROR wave-mode must satisfy 1 <= mode < Ny/2")
    if a.particle_type < 0:
        raise SystemExit("[0493x7s-state] ERROR particle type must be non-negative")


def offsets(slot: int) -> tuple[float, float]:
    fx = ((slot + 0.5) * 0.6180339887498949) % 1.0
    fy = ((slot + 0.5) * 0.4142135623730950) % 1.0
    margin = 0.04
    return margin + (1.0 - 2.0 * margin) * fx, margin + (1.0 - 2.0 * margin) * fy


def thermal_velocities(n: int, kbt: float, mass: float, seed: int) -> list[tuple[float, float]]:
    rng = random.Random(seed)
    q = [(rng.gauss(0.0, 1.0), rng.gauss(0.0, 1.0)) for _ in range(n)]
    mx = sum(u for u, _ in q) / n
    my = sum(v for _, v in q) / n
    q = [(u - mx, v - my) for u, v in q]
    energy = 0.5 * mass * sum(u * u + v * v for u, v in q)
    target = n * kbt  # d=2: peculiar KE = N*kBT.
    if not (energy > 0.0):
        raise RuntimeError("zero thermal peculiar energy")
    scale = math.sqrt(target / energy)
    return [(scale * u, scale * v) for u, v in q]


def generate(a: argparse.Namespace) -> None:
    x: list[float] = []
    y: list[float] = []
    vx: list[float] = []
    vy: list[float] = []
    typ: list[int] = []
    mass: list[float] = []
    role: list[int] = []

    for j in range(a.Ny):
        yc = (j + 0.5) * a.Ly / a.Ny
        bulk_x = a.wave_amplitude * math.sin(2.0 * math.pi * a.wave_mode * yc / a.Ly)
        for i in range(a.Nx):
            cell = i + a.Nx * j
            thermal = thermal_velocities(a.gamma, a.kBT, a.mass, a.seed + 104729 * cell)
            for slot, (tx, ty) in enumerate(thermal):
                fx, fy = offsets(slot)
                x.append((i + fx) * a.Lx / a.Nx)
                y.append((j + fy) * a.Ly / a.Ny)
                vx.append(bulk_x + tx)
                vy.append(ty)
                typ.append(a.particle_type)
                mass.append(a.mass)
                role.append(1)

    total_mass = math.fsum(mass)
    mean_ux = math.fsum(m * u for m, u in zip(mass, vx)) / total_mass
    mean_uy = math.fsum(m * v for m, v in zip(mass, vy)) / total_mass
    # Remove only roundoff-level global residual; the cellwise mode and peculiar
    # zero-momentum construction are otherwise unchanged.
    vx = [u - mean_ux for u in vx]
    vy = [v - mean_uy for v in vy]

    a.output.parent.mkdir(parents=True, exist_ok=True)
    n = len(x)
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    with a.output.open("wb") as stream:
        stream.write(MAGIC)
        stream.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        stream.write(struct.pack("<8Q", *reserved))
        for values, fmt in (
            (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
            (typ, "I"), (mass, "d"), (role, "B"),
        ):
            stream.write(struct.pack(f"<{n}{fmt}", *values))

    coherent_ke = 0.5 * total_mass * 0.5 * a.wave_amplitude * a.wave_amplitude
    total_ke = 0.5 * math.fsum(m * (u * u + v * v) for m, u, v in zip(mass, vx, vy))
    print(
        f"[0493x7s-state] path={a.output} grid={a.Nx}x{a.Ny} "
        f"cell=({a.Lx/a.Nx:.9g},{a.Ly/a.Ny:.9g}) N={n} gamma={a.gamma} "
        f"kBT={a.kBT:.9g} mode={a.wave_mode} amplitude={a.wave_amplitude:.9g} "
        f"meanU=({math.fsum(m*u for m,u in zip(mass,vx))/total_mass:.3e},"
        f"{math.fsum(m*v for m,v in zip(mass,vy))/total_mass:.3e}) "
        f"coherentKE={coherent_ke:.9g} totalKE={total_ke:.9g}"
    )


def main() -> int:
    a = parse_args()
    validate(a)
    generate(a)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

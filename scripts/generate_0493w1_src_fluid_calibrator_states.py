#!/usr/bin/env python3
"""Generate periodic SRC calibration states for 0493w1.

Cases:
  tg     : transverse Taylor--Green velocity mode for nu.
  sound  : weak standing longitudinal density mode for c_s and attenuation.
  msd    : homogeneous equilibrium state for self diffusion from MSD.

The sound state deliberately starts with zero coherent velocity. It therefore
requires no prior sound-speed assumption and is valid for raw or thermostatted
SRC configurations. All states are V2 .smpcd files with only Fluid slots.
"""
from __future__ import annotations

import argparse
import math
import random
import struct
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--case", choices=("tg", "sound", "msd"), required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--Lx", type=float, required=True)
    p.add_argument("--Ly", type=float, required=True)
    p.add_argument("--Nx", type=int, required=True)
    p.add_argument("--Ny", type=int, required=True)
    p.add_argument("--gamma", type=int, required=True)
    p.add_argument("--dt", type=float, required=True)
    p.add_argument("--kBT", type=float, required=True)
    p.add_argument("--mass", type=float, default=1.0)
    p.add_argument("--seed", type=int, default=493201)
    p.add_argument("--tg-mode-x", type=int, default=1)
    p.add_argument("--tg-mode-y", type=int, default=1)
    p.add_argument("--tg-amplitude", type=float, default=0.01)
    p.add_argument("--sound-mode-x", type=int, default=2)
    p.add_argument("--sound-density-amplitude", type=float, default=0.03)
    # Accepted only so old hand-written commands do not fail. It is ignored.
    p.add_argument("--sound-speed-proxy", type=float, default=-1.0)
    return p.parse_args()


def validate(a):
    if min(a.Lx, a.Ly, a.dt, a.kBT, a.mass) <= 0:
        raise SystemExit("[0493w1-state] positive Lx,Ly,dt,kBT,mass required")
    if min(a.Nx, a.Ny) < 8 or a.gamma < 4:
        raise SystemExit("[0493w1-state] Nx,Ny>=8 and gamma>=4 required")
    if a.tg_mode_x < 1 or a.tg_mode_y < 1 or a.sound_mode_x < 1:
        raise SystemExit("[0493w1-state] mode indices must be >=1")
    if not 0 < a.sound_density_amplitude < 0.20:
        raise SystemExit("[0493w1-state] sound density amplitude must be in (0,0.2)")
    if a.sound_mode_x * 8 > a.Nx:
        raise SystemExit(
            "[0493w1-state] sound wavelength must contain at least 8 cells"
        )


def offsets(slot):
    fx = ((slot + 0.5) * 0.6180339887498949) % 1.0
    fy = ((slot + 0.5) * 0.4142135623730950) % 1.0
    margin = 0.04
    return margin + (1 - 2 * margin) * fx, margin + (1 - 2 * margin) * fy


def thermal_velocities(n, kbt, mass, seed):
    rng = random.Random(seed)
    q = [(rng.gauss(0, 1), rng.gauss(0, 1)) for _ in range(n)]
    mx = sum(u for u, _ in q) / n
    my = sum(v for _, v in q) / n
    q = [(u - mx, v - my) for u, v in q]
    energy = 0.5 * mass * sum(u * u + v * v for u, v in q)
    target = n * kbt  # d=2: total peculiar KE = N*kBT.
    scale = math.sqrt(target / energy) if energy > 0 else 0.0
    return [(scale * u, scale * v) for u, v in q]


def sound_counts(nx, ny, gamma, amplitude, mode):
    desired = []
    for _j in range(ny):
        for i in range(nx):
            xc = (i + 0.5) / nx
            desired.append(gamma * (1 + amplitude * math.cos(2 * math.pi * mode * xc)))
    base = [int(math.floor(v)) for v in desired]
    remaining = nx * ny * gamma - sum(base)
    order = sorted(
        range(len(base)),
        key=lambda index: (desired[index] - base[index], -index),
        reverse=True,
    )
    for index in order[:remaining]:
        base[index] += 1
    if min(base) < 4 or sum(base) != nx * ny * gamma:
        raise RuntimeError("invalid sound population allocation")
    return base


def generate(a):
    x, y, vx, vy, typ, mass, role = [], [], [], [], [], [], []
    counts = (
        sound_counts(
            a.Nx,
            a.Ny,
            a.gamma,
            a.sound_density_amplitude,
            a.sound_mode_x,
        )
        if a.case == "sound"
        else [a.gamma] * (a.Nx * a.Ny)
    )

    for j in range(a.Ny):
        yc = (j + 0.5) * a.Ly / a.Ny
        for i in range(a.Nx):
            cell = i + a.Nx * j
            n = counts[cell]
            xc = (i + 0.5) * a.Lx / a.Nx
            if a.case == "tg":
                kx = 2 * math.pi * a.tg_mode_x / a.Lx
                ky = 2 * math.pi * a.tg_mode_y / a.Ly
                ubx = a.tg_amplitude * math.sin(kx * xc) * math.cos(ky * yc)
                uby = -a.tg_amplitude * math.cos(kx * xc) * math.sin(ky * yc)
            else:
                # Sound is initialized as a density standing wave with no
                # coherent velocity: no assumed equation of state or c_s.
                ubx = 0.0
                uby = 0.0

            thermal = thermal_velocities(n, a.kBT, a.mass, a.seed + 104729 * cell)
            for slot, (tx, ty) in enumerate(thermal):
                fx, fy = offsets(slot)
                x.append((i + fx) * a.Lx / a.Nx)
                y.append((j + fy) * a.Ly / a.Ny)
                vx.append(ubx + tx)
                vy.append(uby + ty)
                typ.append(0)
                mass.append(a.mass)
                role.append(1)

    total_mass = sum(mass)
    ux = sum(m * u for m, u in zip(mass, vx)) / total_mass
    uy = sum(m * v for m, v in zip(mass, vy)) / total_mass
    vx = [u - ux for u in vx]
    vy = [v - uy for v in vy]

    n = len(x)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    with a.output.open("wb") as stream:
        stream.write(MAGIC)
        stream.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        stream.write(struct.pack("<8Q", *reserved))
        for values, fmt in (
            (x, "d"),
            (y, "d"),
            (vx, "d"),
            (vy, "d"),
            (typ, "I"),
            (mass, "d"),
            (role, "B"),
        ):
            stream.write(struct.pack(f"<{n}{fmt}", *values))

    kinetic_energy = 0.5 * sum(
        m * (u * u + v * v) for m, u, v in zip(mass, vx, vy)
    )
    coherent = "standing_density_zero_velocity" if a.case == "sound" else a.case
    print(
        f"[0493w1-state] case={a.case} initialization={coherent} "
        f"path={a.output} grid={a.Nx}x{a.Ny} N={n} gamma={a.gamma} "
        f"kBT={a.kBT:.17g} mass={total_mass:.17g} "
        f"meanU=({sum(m*u for m,u in zip(mass,vx))/total_mass:.3e},"
        f"{sum(m*v for m,v in zip(mass,vy))/total_mass:.3e}) "
        f"KE={kinetic_energy:.17g}"
    )


def main():
    args = parse_args()
    validate(args)
    generate(args)


if __name__ == "__main__":
    main()

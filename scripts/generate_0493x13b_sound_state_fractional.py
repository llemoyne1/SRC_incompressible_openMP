#!/usr/bin/env python3
"""Generate x13b longitudinal standing-density states with sub-particle column resolution.

The legacy 0493w1 generator allocates integer cell occupancies by deterministic
largest-remainder rounding.  At low gamma this can quantize weak requested
sound amplitudes to exactly zero.  This x13b-only generator keeps the global
particle count exactly Nx*Ny*gamma while using unbiased systematic residual
rounding on *column totals*.  The resulting x-density Fourier amplitude is
therefore resolved at 1/(Ny*gamma), while y allocation is randomized.

No solver/source code is involved; this file only creates an initial .smpcd state.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import struct
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--metadata", type=Path, default=None)
    p.add_argument("--Lx", type=float, required=True)
    p.add_argument("--Ly", type=float, required=True)
    p.add_argument("--Nx", type=int, required=True)
    p.add_argument("--Ny", type=int, required=True)
    p.add_argument("--gamma", type=int, required=True)
    p.add_argument("--dt", type=float, required=True)
    p.add_argument("--kBT", type=float, required=True)
    p.add_argument("--mass", type=float, default=1.0)
    p.add_argument("--seed", type=int, default=4931321)
    p.add_argument("--sound-mode-x", type=int, default=1)
    p.add_argument("--sound-density-amplitude", type=float, required=True)
    return p.parse_args()


def validate(a):
    if min(a.Lx, a.Ly, a.dt, a.kBT, a.mass) <= 0:
        raise SystemExit("[0493x13b-sound-state] positive Lx,Ly,dt,kBT,mass required")
    if min(a.Nx, a.Ny) < 8 or a.gamma < 4:
        raise SystemExit("[0493x13b-sound-state] Nx,Ny>=8 and gamma>=4 required")
    if a.sound_mode_x < 1 or a.sound_mode_x * 8 > a.Nx:
        raise SystemExit("[0493x13b-sound-state] sound wavelength must contain at least 8 cells")
    if not 0 < a.sound_density_amplitude < 0.20:
        raise SystemExit("[0493x13b-sound-state] sound density amplitude must be in (0,0.2)")


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
    target = n * kbt
    scale = math.sqrt(target / energy) if energy > 0 else 0.0
    return [(scale * u, scale * v) for u, v in q]


def systematic_residual_round(values, total, rng):
    """Return integer values summing to total with E[result_i] = values_i.

    Each value is floor-rounded first.  The residual fractions are then selected
    by systematic sampling.  Here values are column populations and each
    fractional remainder is <1, so each column receives at most one extra item.
    """
    base = [int(math.floor(v)) for v in values]
    remaining = int(total - sum(base))
    if remaining < 0 or remaining > len(base):
        raise RuntimeError("invalid residual rounding population")
    frac = [v - b for v, b in zip(values, base)]
    frac_sum = sum(frac)
    if abs(frac_sum - remaining) > 1e-8 * max(1, remaining):
        raise RuntimeError(
            f"fractional population sum mismatch: frac={frac_sum:.17g} remaining={remaining}"
        )
    if remaining:
        u = rng.random()
        threshold = u
        cumulative = 0.0
        picked = 0
        for i, f in enumerate(frac):
            cumulative += f
            if picked < remaining and threshold < cumulative + 1e-14:
                base[i] += 1
                picked += 1
                threshold = u + picked
        if picked != remaining:
            raise RuntimeError(f"systematic residual rounding picked {picked}/{remaining}")
    if sum(base) != total:
        raise RuntimeError("systematic residual rounding lost global conservation")
    return base


def sound_counts(nx, ny, gamma, amplitude, mode, seed):
    rng = random.Random(seed ^ 0x5A17B3C9)
    desired_cols = [
        ny * gamma * (1 + amplitude * math.cos(2 * math.pi * mode * (i + 0.5) / nx))
        for i in range(nx)
    ]
    total = nx * ny * gamma
    column_totals = systematic_residual_round(desired_cols, total, rng)

    counts = [0] * (nx * ny)
    for i, col_n in enumerate(column_totals):
        q, r = divmod(col_n, ny)
        ys = list(range(ny))
        # Deterministic per-seed randomization avoids coherent y stripes while
        # preserving the exact x-column population used by the sound mode.
        rng.shuffle(ys)
        plus = set(ys[:r])
        for j in range(ny):
            counts[i + nx * j] = q + (1 if j in plus else 0)

    if min(counts) < 4 or sum(counts) != total:
        raise RuntimeError("invalid x13b sound population allocation")

    # Fourier amplitude of the actual column population, relative to mean gamma.
    norm = nx * ny * gamma
    cos_num = 0.0
    sin_num = 0.0
    for i, col_n in enumerate(column_totals):
        phase = 2 * math.pi * mode * (i + 0.5) / nx
        delta = col_n - ny * gamma
        cos_num += delta * math.cos(phase)
        sin_num += delta * math.sin(phase)
    cos_amp = 2 * cos_num / norm
    sin_amp = 2 * sin_num / norm
    mag_amp = math.hypot(cos_amp, sin_amp)
    return counts, column_totals, cos_amp, sin_amp, mag_amp


def generate(a):
    counts, column_totals, cos_amp, sin_amp, mag_amp = sound_counts(
        a.Nx, a.Ny, a.gamma, a.sound_density_amplitude, a.sound_mode_x, a.seed
    )
    x, y, vx, vy, typ, mass, role = [], [], [], [], [], [], []
    for j in range(a.Ny):
        for i in range(a.Nx):
            cell = i + a.Nx * j
            n = counts[cell]
            thermal = thermal_velocities(n, a.kBT, a.mass, a.seed + 104729 * cell)
            for slot, (tx, ty) in enumerate(thermal):
                fx, fy = offsets(slot)
                x.append((i + fx) * a.Lx / a.Nx)
                y.append((j + fy) * a.Ly / a.Ny)
                vx.append(tx)
                vy.append(ty)
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
            (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
            (typ, "I"), (mass, "d"), (role, "B"),
        ):
            stream.write(struct.pack(f"<{n}{fmt}", *values))

    meta = {
        "method": "x13b_column_systematic_residual_rounding",
        "seed": a.seed,
        "Nx": a.Nx,
        "Ny": a.Ny,
        "gamma": a.gamma,
        "modeX": a.sound_mode_x,
        "requestedDensityAmplitude": a.sound_density_amplitude,
        "realizedCosDensityAmplitude": cos_amp,
        "realizedSinDensityAmplitude": sin_amp,
        "realizedDensityAmplitudeMagnitude": mag_amp,
        "relativeCosAmplitudeError": (cos_amp - a.sound_density_amplitude) / a.sound_density_amplitude,
        "totalParticles": n,
        "expectedParticles": a.Nx * a.Ny * a.gamma,
        "minCellPopulation": min(counts),
        "maxCellPopulation": max(counts),
        "minColumnPopulation": min(column_totals),
        "maxColumnPopulation": max(column_totals),
    }
    if a.metadata is not None:
        a.metadata.parent.mkdir(parents=True, exist_ok=True)
        a.metadata.write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n")

    print(
        f"[0493x13b-sound-state] path={a.output} grid={a.Nx}x{a.Ny} "
        f"N={n} gamma={a.gamma} requested={a.sound_density_amplitude:.9g} "
        f"realizedCos={cos_amp:.9g} realizedSin={sin_amp:.3e} "
        f"cellN=[{min(counts)},{max(counts)}] conservation=exact"
    )


def main():
    a = parse_args()
    validate(a)
    generate(a)


if __name__ == "__main__":
    main()

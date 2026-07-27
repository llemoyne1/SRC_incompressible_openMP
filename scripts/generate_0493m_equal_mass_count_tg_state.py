#!/usr/bin/env python3
"""Generate an equal-mass, count-encoded binary Taylor--Green state (0493m).

Every active particle has the same inertial mass.  The composition field is
encoded only through the local numbers N1 and N2, with N1+N2=gamma in every
cell.  Counts are integer-quantized while enforcing exact global N1=N2.
"""
from __future__ import annotations

import argparse
import math
import struct
from pathlib import Path


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--nx", type=int, default=64)
    ap.add_argument("--ny", type=int, default=64)
    ap.add_argument("--gamma", type=int, default=20)
    ap.add_argument("--tg-mode", type=int, default=2)
    ap.add_argument("--tg-amplitude", type=float, default=0.08)
    ap.add_argument("--composition-amplitude", type=float, default=0.15)
    ap.add_argument("--thermal-amplitude", type=float, default=0.04)
    ap.add_argument("--particle-mass", type=float, default=1.0)
    ap.add_argument("--inactive-per-cell", type=int, default=8)
    ap.add_argument("--min-species-count", type=int, default=3)
    return ap.parse_args()


def validate(a: argparse.Namespace) -> None:
    if a.nx < 8 or a.ny < 8:
        raise SystemExit("[0493m-state] ERROR nx and ny must be >= 8")
    if a.gamma < 8 or a.gamma % 2:
        raise SystemExit("[0493m-state] ERROR gamma must be even and >= 8")
    if a.tg_mode < 1 or a.inactive_per_cell < 2:
        raise SystemExit("[0493m-state] ERROR tg-mode>=1 and inactive-per-cell>=2 required")
    if a.min_species_count < 3 or 2 * a.min_species_count > a.gamma:
        raise SystemExit("[0493m-state] ERROR invalid min-species-count")
    vals = (a.tg_amplitude, a.composition_amplitude, a.thermal_amplitude, a.particle_mass)
    if not all(math.isfinite(v) for v in vals):
        raise SystemExit("[0493m-state] ERROR non-finite physical parameter")
    if a.tg_amplitude <= 0.0 or a.thermal_amplitude < 0.0 or a.particle_mass <= 0.0:
        raise SystemExit("[0493m-state] ERROR require U0>0, thermal>=0 and mass>0")
    if not 0.0 < a.composition_amplitude < 0.45:
        raise SystemExit("[0493m-state] ERROR composition amplitude must be in (0,0.45)")


def slot_position(slot: int, count: int, phase: float) -> tuple[float, float]:
    fx = ((slot + 0.5 + phase) * 0.6180339887498949) % 1.0
    fy = ((slot + 0.5 + 0.37 * phase) * 0.4142135623730950) % 1.0
    margin = 0.08
    return margin + (1.0 - 2.0 * margin) * fx, margin + (1.0 - 2.0 * margin) * fy


def balanced_counts(a: argparse.Namespace) -> list[tuple[int, int, int, float, float, float, float, float]]:
    """Return cells with globally balanced integer counts.

    Tuple fields: i,j,n1,basis,c1_target,bulk_x,bulk_y,rounding_residual.
    """
    k = 2.0 * math.pi * a.tg_mode
    cells: list[list[float | int]] = []
    for j in range(a.ny):
        yc = (j + 0.5) / a.ny
        sy, cy = math.sin(k * yc), math.cos(k * yc)
        for i in range(a.nx):
            xc = (i + 0.5) / a.nx
            sx, cx = math.sin(k * xc), math.cos(k * xc)
            basis = sx * sy
            c1 = 0.5 + a.composition_amplitude * basis
            target = a.gamma * c1
            n1 = int(math.floor(target + 0.5))
            n1 = max(a.min_species_count, min(a.gamma - a.min_species_count, n1))
            bulk_x = a.tg_amplitude * sx * cy
            bulk_y = -a.tg_amplitude * cx * sy
            cells.append([i, j, n1, basis, c1, bulk_x, bulk_y, target - n1])

    desired = len(cells) * a.gamma // 2
    delta = desired - sum(int(c[2]) for c in cells)
    if delta > 0:
        candidates = sorted(
            (idx for idx, c in enumerate(cells) if int(c[2]) < a.gamma - a.min_species_count),
            key=lambda idx: float(cells[idx][7]), reverse=True,
        )
        if len(candidates) < delta:
            raise SystemExit("[0493m-state] ERROR unable to balance species counts upward")
        for idx in candidates[:delta]:
            cells[idx][2] = int(cells[idx][2]) + 1
    elif delta < 0:
        candidates = sorted(
            (idx for idx, c in enumerate(cells) if int(c[2]) > a.min_species_count),
            key=lambda idx: float(cells[idx][7]),
        )
        if len(candidates) < -delta:
            raise SystemExit("[0493m-state] ERROR unable to balance species counts downward")
        for idx in candidates[: -delta]:
            cells[idx][2] = int(cells[idx][2]) - 1

    if sum(int(c[2]) for c in cells) != desired:
        raise SystemExit("[0493m-state] ERROR global count balance failed")
    return [tuple(c) for c in cells]  # type: ignore[return-value]


def generate(a: argparse.Namespace) -> None:
    cells = balanced_counts(a)
    x: list[float] = []
    y: list[float] = []
    vx: list[float] = []
    vy: list[float] = []
    typ: list[int] = []
    mass: list[float] = []
    role: list[int] = []

    n_species = {1: 0, 2: 0}
    species_px = {1: 0.0, 2: 0.0}
    species_py = {1: 0.0, 2: 0.0}
    count_min = a.gamma
    count_max = 0
    projected_num = 0.0
    projected_den = 0.0
    quant_error_sq = 0.0

    golden = 0.6180339887498949
    for cell_index, (i, j, n1, basis, c1_target, bulk_x, bulk_y, _) in enumerate(cells):
        i, j, n1 = int(i), int(j), int(n1)
        n2 = a.gamma - n1
        count_min = min(count_min, n1, n2)
        count_max = max(count_max, n1, n2)
        c1_count = n1 / a.gamma
        projected_num += (c1_count - 0.5) * float(basis)
        projected_den += float(basis) * float(basis)
        quant_error_sq += (c1_count - float(c1_target)) ** 2

        phase = ((cell_index + 0.5) * golden) % 1.0
        slot_order = sorted(range(a.gamma), key=lambda s: ((s + 0.5) * golden + phase) % 1.0)
        type1_slots = set(slot_order[:n1])
        species_slots = {
            1: [s for s in range(a.gamma) if s in type1_slots],
            2: [s for s in range(a.gamma) if s not in type1_slots],
        }

        for sidx, type_id in enumerate((1, 2)):
            slots = species_slots[type_id]
            count = len(slots)
            # A regular velocity polygon gives exactly zero peculiar momentum
            # mathematically for any count >= 3, including odd counts.
            for local_index, slot in enumerate(slots):
                theta = 2.0 * math.pi * (local_index + 0.5 + 0.173 * sidx) / count
                tx = a.thermal_amplitude * math.cos(theta)
                ty = a.thermal_amplitude * math.sin(theta)
                fx, fy = slot_position(slot, a.gamma, phase)
                x.append((i + fx) / a.nx)
                y.append((j + fy) / a.ny)
                vx.append(float(bulk_x) + tx)
                vy.append(float(bulk_y) + ty)
                typ.append(type_id)
                mass.append(a.particle_mass)
                role.append(1)
                n_species[type_id] += 1
                species_px[type_id] += a.particle_mass * vx[-1]
                species_py[type_id] += a.particle_mass * vy[-1]

    active = len(x)
    inactive = a.nx * a.ny * a.inactive_per_cell
    for _ in range(inactive):
        x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
        typ.append(0); mass.append(a.particle_mass); role.append(0)

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
        for values, fmt in ((x, "d"), (y, "d"), (vx, "d"), (vy, "d"), (typ, "I"), (mass, "d"), (role, "B")):
            stream.write(struct.pack(f"<{n}{fmt}", *values))

    amp = projected_num / projected_den
    leakage = math.sqrt(quant_error_sq / len(cells))
    total_mass = math.fsum(mass[:active])
    total_px = math.fsum(m * u for m, u in zip(mass[:active], vx[:active]))
    total_py = math.fsum(m * v for m, v in zip(mass[:active], vy[:active]))
    print(
        f"[0493m-state] path={a.output} encoding=count_equal_mass grid={a.nx}x{a.ny} "
        f"gamma={a.gamma} fluid={active} inactive={inactive} U0={a.tg_amplitude:.17g} "
        f"thermal={a.thermal_amplitude:.17g} mass={total_mass:.17g} "
        f"px={total_px:.3e} py={total_py:.3e} particleMassMinMax={a.particle_mass:.9g}/{a.particle_mass:.9g}"
    )
    print(
        f"[0493m-state] requestedCompositionAmplitude={a.composition_amplitude:.17g} "
        f"projectedCountAmplitude={amp:.9g} quantizationRms={leakage:.9g} "
        f"countPerSpeciesMinMax={count_min}/{count_max} "
        f"N1={n_species[1]} N2={n_species[2]} "
        f"M1={n_species[1]*a.particle_mass:.17g} M2={n_species[2]*a.particle_mass:.17g} "
        f"P1=({species_px[1]:.3e},{species_py[1]:.3e}) "
        f"P2=({species_px[2]:.3e},{species_py[2]:.3e})"
    )


def main() -> int:
    a = parse_args()
    validate(a)
    generate(a)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

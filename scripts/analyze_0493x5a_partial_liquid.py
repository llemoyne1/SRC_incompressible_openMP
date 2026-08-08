#!/usr/bin/env python3
"""Offline geometry check for the 0493x5a partial-liquid free-surface run."""

from __future__ import annotations

import argparse
import json
import math
import struct
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def read_array(stream, code: str, count: int) -> array:
    values = array(code)
    values.fromfile(stream, count)
    if len(values) != count:
        raise RuntimeError("truncated state array")
    return values


def read_state(path: Path) -> dict[str, object]:
    with path.open("rb") as stream:
        if stream.read(16) != MAGIC:
            raise RuntimeError(f"{path}: invalid state magic")
        version, endian, dim, layout, n, has_type, _, real_bytes, type_bytes = struct.unpack(
            "<IIIIQIIII", stream.read(40)
        )
        reserved = struct.unpack("<8Q", stream.read(64))
        if endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"{path}: unsupported state layout")
        if real_bytes != 8 or type_bytes != 4 or not has_type:
            raise RuntimeError(f"{path}: unsupported scalar/type format")
        x = read_array(stream, "d", n)
        y = read_array(stream, "d", n)
        vx = read_array(stream, "d", n)
        vy = read_array(stream, "d", n)
        typ = read_array(stream, "I", n)
        mass = read_array(stream, "d", n) if reserved[0] else array("d", [1.0]) * n
        role = bytearray(stream.read(n)) if reserved[1] else bytearray([1]) * n
        if len(role) != n:
            raise RuntimeError(f"{path}: truncated role array")
    return {
        "version": version,
        "n": n,
        "x": x,
        "y": y,
        "vx": vx,
        "vy": vy,
        "type": typ,
        "mass": mass,
        "role": role,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--nx", type=int, required=True)
    parser.add_argument("--ny", type=int, required=True)
    parser.add_argument("--Lx", type=float, required=True)
    parser.add_argument("--Ly", type=float, required=True)
    parser.add_argument("--gamma", type=float, required=True)
    parser.add_argument("--liquid-type", type=int, required=True)
    parser.add_argument("--initial-fill-height", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    data = read_state(args.state)
    x = data["x"]
    y = data["y"]
    vx = data["vx"]
    vy = data["vy"]
    typ = data["type"]
    mass = data["mass"]
    role = data["role"]
    assert isinstance(role, bytearray)

    dx = args.Lx / args.nx
    dy = args.Ly / args.ny
    occupancy = [0] * (args.nx * args.ny)
    count = 0
    total_mass = 0.0
    sum_x = 0.0
    sum_y = 0.0
    sum_vx = 0.0
    sum_vy = 0.0
    sum_v2 = 0.0
    min_y = math.inf
    max_y = -math.inf

    for i in range(int(data["n"])):
        if role[i] != 1 or typ[i] != args.liquid_type:
            continue
        xi = min(max(float(x[i]), 0.0), math.nextafter(args.Lx, 0.0))
        yi = min(max(float(y[i]), 0.0), math.nextafter(args.Ly, 0.0))
        ix = min(args.nx - 1, max(0, int(xi / dx)))
        iy = min(args.ny - 1, max(0, int(yi / dy)))
        occupancy[iy * args.nx + ix] += 1
        mi = float(mass[i])
        total_mass += mi
        sum_x += mi * xi
        sum_y += mi * yi
        sum_vx += mi * float(vx[i])
        sum_vy += mi * float(vy[i])
        sum_v2 += mi * (float(vx[i]) ** 2 + float(vy[i]) ** 2)
        count += 1
        min_y = min(min_y, yi)
        max_y = max(max_y, yi)

    if count == 0 or total_mass <= 0.0:
        raise RuntimeError("no liquid particles found")

    occupied = [n for n in occupancy if n > 0]
    initial_rows = max(1, min(args.ny, int(round(args.initial_fill_height / dy))))
    initial_cells = args.nx * initial_rows
    initial_particles = int(round(initial_cells * args.gamma))
    row_counts = [sum(occupancy[iy * args.nx : (iy + 1) * args.nx]) for iy in range(args.ny)]
    occupied_rows = [iy for iy, n in enumerate(row_counts) if n > 0]
    interface_row = max(occupied_rows) if occupied_rows else -1
    expected_com_y = 0.5 * args.initial_fill_height
    com_y = sum_y / total_mass
    com_x = sum_x / total_mass
    mean_vx = sum_vx / total_mass
    mean_vy = sum_vy / total_mass
    velocity_rms = math.sqrt(sum_v2 / total_mass)

    bottom_band_rows = max(1, initial_rows // 10)
    bottom_band = sum(row_counts[:bottom_band_rows])
    upper_bulk_start = max(0, initial_rows - bottom_band_rows - 1)
    upper_bulk_end = max(upper_bulk_start + 1, initial_rows - 1)
    upper_bulk = sum(row_counts[upper_bulk_start:upper_bulk_end])

    com_tolerance = max(0.01 * args.Ly, 2.0 * dy)
    count_ok = count == initial_particles
    com_ok = abs(com_y - expected_com_y) <= com_tolerance
    max_population_ok = max(occupied) <= max(4.0 * args.gamma, args.gamma + 20.0)
    pass_like = count_ok and com_ok and max_population_ok

    report = {
        "state": str(args.state),
        "status": "PASS-like" if pass_like else "FAIL-like",
        "liquidParticles": count,
        "expectedLiquidParticles": initial_particles,
        "totalLiquidMass": total_mass,
        "centerOfMassX": com_x,
        "centerOfMassY": com_y,
        "expectedCenterOfMassY": expected_com_y,
        "centerOfMassYDrift": com_y - expected_com_y,
        "meanVx": mean_vx,
        "meanVy": mean_vy,
        "velocityRms": velocity_rms,
        "occupiedCells": len(occupied),
        "initialLiquidCells": initial_cells,
        "occupiedCellFractionOfInitial": len(occupied) / initial_cells,
        "populationMeanOccupied": sum(occupied) / len(occupied),
        "populationMinOccupied": min(occupied),
        "populationMaxOccupied": max(occupied),
        "occupiedInterfaceRow": interface_row,
        "occupiedInterfaceHeight": (interface_row + 1) * dy if interface_row >= 0 else 0.0,
        "minParticleY": min_y,
        "maxParticleY": max_y,
        "bottomBandParticles": bottom_band,
        "upperBulkBandParticles": upper_bulk,
        "checks": {
            "particleCountConserved": count_ok,
            "centerOfMassStable": com_ok,
            "noMacroscopicCellCollapse": max_population_ok,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(
        "[0493x5a-analysis] "
        f"status={report['status']} particles={count} occupiedCells={len(occupied)} "
        f"comY={com_y:.9g} driftY={com_y - expected_com_y:.6e} "
        f"popMin={min(occupied)} popMax={max(occupied)} "
        f"interfaceRow={interface_row} meanVy={mean_vy:.6e}"
    )
    return 0 if pass_like else 3


if __name__ == "__main__":
    raise SystemExit(main())

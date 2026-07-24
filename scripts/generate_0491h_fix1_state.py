#!/usr/bin/env python3
"""Generate deterministic multi-species SMPСD states for 0491h-fix1 qualification."""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def write_state(path: Path, x, y, vx, vy, typ, mass, role) -> None:
    n = len(x)
    arrays = (y, vx, vy, typ, mass, role)
    if any(len(a) != n for a in arrays):
        raise ValueError("state arrays have inconsistent lengths")
    path.parent.mkdir(parents=True, exist_ok=True)
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    with path.open("wb") as stream:
        stream.write(MAGIC)
        stream.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        stream.write(struct.pack("<8Q", *reserved))
        for array, fmt in (
            (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
            (typ, "I"), (mass, "d"), (role, "B"),
        ):
            stream.write(struct.pack(f"<{n}{fmt}", *array))


def particle_position(i: int, j: int, k: int, count: int, nx: int, ny: int):
    # Irrational-looking modular strides keep positions distinct without RNG.
    fx = ((k * 5 + 1) % max(count, 1) + 0.5) / max(count, 1)
    fy = ((k * 7 + 2) % max(count, 1) + 0.5) / max(count, 1)
    return (i + fx) / nx, (j + fy) / ny


def taylor_green(px: float, py: float, amplitude: float):
    twopi = 2.0 * math.pi
    return (
        amplitude * math.sin(twopi * px) * math.cos(twopi * py),
        -amplitude * math.cos(twopi * px) * math.sin(twopi * py),
    )


def build(args):
    nx, ny, gamma = args.nx, args.ny, args.gamma
    if nx < 2 or ny < 1 or gamma < 4:
        raise ValueError("qualification states require nx>=2, ny>=1 and gamma>=4")

    x, y, vx, vy, typ, mass, role = [], [], [], [], [], [], []
    trace_index = None
    trace_mass = None
    poor_count = max(2, gamma - 2)
    rich_count = 2 * gamma - poor_count

    for j in range(ny):
        for i in range(nx):
            if args.profile == "imbalanced":
                count = poor_count if (i + j) % 2 == 0 else rich_count
            else:
                count = gamma

            for k in range(count):
                px, py = particle_position(i, j, k, count, nx, ny)
                if args.profile == "interface":
                    ux = 0.0
                    uy = args.velocity_amplitude * math.sin(2.0 * math.pi * px)
                    ptype = 1 if i < nx // 2 else 2
                else:
                    ux, uy = taylor_green(px, py, args.velocity_amplitude)
                    ptype = 1 if k == 0 else 2

                if (
                    args.profile == "trace"
                    and i == nx // 2
                    and j == ny // 2
                    and k == 1
                ):
                    ptype = 3
                    trace_index = len(x)

                x.append(px)
                y.append(py)
                vx.append(ux)
                vy.append(uy)
                typ.append(ptype)
                mass.append(1.0)
                role.append(1)

    if args.profile == "trace":
        if trace_index is None:
            raise RuntimeError("failed to place the trace particle")
        other_mass = float(len(x) - 1)
        trace_mass = args.trace_mass_fraction * other_mass / (1.0 - args.trace_mass_fraction)
        mass[trace_index] = trace_mass

    inactive_slots = args.inactive_slots
    if inactive_slots < 0:
        inactive_slots = 2 * nx * ny * gamma if args.profile == "imbalanced" else 0
    for _ in range(inactive_slots):
        x.append(0.0)
        y.append(0.0)
        vx.append(0.0)
        vy.append(0.0)
        typ.append(0)
        mass.append(1.0)
        role.append(0)

    output = Path(args.output)
    write_state(output, x, y, vx, vy, typ, mass, role)

    fluid_indices = [idx for idx, value in enumerate(role) if value == 1]
    masses_by_type = {}
    counts_by_type = {}
    for idx in fluid_indices:
        key = int(typ[idx])
        masses_by_type[key] = masses_by_type.get(key, 0.0) + float(mass[idx])
        counts_by_type[key] = counts_by_type.get(key, 0) + 1
    total_mass = sum(masses_by_type.values())
    actual_trace_fraction = (
        masses_by_type.get(3, 0.0) / total_mass if total_mass > 0.0 else 0.0
    )

    metadata = {
        "profile": args.profile,
        "nx": nx,
        "ny": ny,
        "gamma": gamma,
        "seed": args.seed,
        "fluid_particles": len(fluid_indices),
        "inactive_particles": inactive_slots,
        "total_particles": len(x),
        "counts_by_type": counts_by_type,
        "masses_by_type": masses_by_type,
        "total_mass": total_mass,
        "trace_mass": trace_mass,
        "trace_mass_fraction_requested": args.trace_mass_fraction,
        "trace_mass_fraction_actual": actual_trace_fraction,
        "poor_count": poor_count if args.profile == "imbalanced" else None,
        "rich_count": rich_count if args.profile == "imbalanced" else None,
        "velocity_amplitude": args.velocity_amplitude,
    }
    metadata_path = output.with_suffix(output.suffix + ".json")
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    print(
        f"[0491h-fix1-state] profile={args.profile} state={output} "
        f"fluid={len(fluid_indices)} inactive={inactive_slots} "
        f"types={counts_by_type} trace_fraction={actual_trace_fraction:.17g}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--profile", choices=("uniform", "interface", "trace", "imbalanced"), required=True)
    parser.add_argument("--nx", type=int, default=8)
    parser.add_argument("--ny", type=int, default=4)
    parser.add_argument("--gamma", type=int, default=6)
    parser.add_argument("--seed", type=int, default=491201)
    parser.add_argument("--trace-mass-fraction", type=float, default=1.0e-7)
    parser.add_argument("--inactive-slots", type=int, default=-1)
    parser.add_argument("--velocity-amplitude", type=float, default=0.02)
    args = parser.parse_args()
    if not (0.0 < args.trace_mass_fraction < 1.0):
        parser.error("--trace-mass-fraction must lie in (0,1)")
    build(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

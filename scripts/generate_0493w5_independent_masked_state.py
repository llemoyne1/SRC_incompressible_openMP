#!/usr/bin/env python3
"""Deterministic periodic states for the 0493w5 independent-masked Q6 smoke."""

from __future__ import annotations

import argparse
import json
import math
import struct
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def particle_position(ix: int, iy: int, k: int, gamma: int, nx: int, ny: int):
    fx = ((5 * k + 1) % gamma + 0.5) / gamma
    fy = ((7 * k + 2) % gamma + 0.5) / gamma
    return (ix + fx) / nx, (iy + fy) / ny


def island_cell(ix: int, iy: int, nx: int, ny: int) -> bool:
    # Two disconnected liquid rectangles, each at least two cells thick.
    a = nx // 8 <= ix < 3 * nx // 8 and ny // 4 <= iy < 3 * ny // 4
    b = 5 * nx // 8 <= ix < 7 * nx // 8 and ny // 4 <= iy < 3 * ny // 4
    return a or b


def write_state(path: Path, x, y, vx, vy, typ, mass, role) -> None:
    n = len(x)
    path.parent.mkdir(parents=True, exist_ok=True)
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    with path.open("wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        f.write(struct.pack("<8Q", *reserved))
        for values, fmt in (
            (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
            (typ, "I"), (mass, "d"), (role, "B"),
        ):
            f.write(struct.pack(f"<{n}{fmt}", *values))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", required=True)
    ap.add_argument("--profile", choices=("full", "islands", "mixed60", "mixed40"), required=True)
    ap.add_argument("--nx", type=int, default=16)
    ap.add_argument("--ny", type=int, default=12)
    ap.add_argument("--gamma", type=int, default=10)
    ap.add_argument("--amplitude", type=float, default=0.05)
    args = ap.parse_args()
    if args.nx < 8 or args.ny < 8 or args.gamma < 4:
        ap.error("nx>=8, ny>=8 and gamma>=4 are required")

    x = []
    y = []
    vx = []
    vy = []
    typ = []
    mass = []
    role = []
    cells_by_type = {1: 0, 2: 0}
    particles_by_type = {1: 0, 2: 0}
    twopi = 2.0 * math.pi

    for iy in range(args.ny):
        for ix in range(args.nx):
            if args.profile == "full":
                liquid_count = args.gamma
            elif args.profile == "islands":
                liquid_count = args.gamma if island_cell(ix, iy, args.nx, args.ny) else 0
            elif args.profile == "mixed60":
                liquid_count = int(round(0.60 * args.gamma))
            else:
                liquid_count = int(round(0.40 * args.gamma))
            if liquid_count > 0:
                cells_by_type[1] += 1
            if liquid_count < args.gamma:
                cells_by_type[2] += 1
            for k in range(args.gamma):
                ptype = 1 if k < liquid_count else 2
                px, py = particle_position(ix, iy, k, args.gamma, args.nx, args.ny)
                if ptype == 1:
                    # Deliberately dilatational field for the projected species.
                    ux = args.amplitude * math.sin(twopi * px)
                    uy = args.amplitude * math.sin(twopi * py)
                else:
                    # Nonzero divergence-free control field.  Q6 must never
                    # apply a direct correction to this q6Strength=0 species.
                    ux = 0.5 * args.amplitude * math.sin(twopi * py)
                    uy = -0.5 * args.amplitude * math.sin(twopi * px)
                x.append(px)
                y.append(py)
                vx.append(ux)
                vy.append(uy)
                typ.append(ptype)
                mass.append(1.0)
                role.append(1)
                particles_by_type[ptype] += 1

    output = Path(args.output)
    write_state(output, x, y, vx, vy, typ, mass, role)
    metadata = {
        "profile": args.profile,
        "nx": args.nx,
        "ny": args.ny,
        "gamma": args.gamma,
        "amplitude": args.amplitude,
        "cells_by_type": cells_by_type,
        "particles_by_type": particles_by_type,
    }
    output.with_suffix(output.suffix + ".json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n"
    )
    print(
        f"[0493w5-state] profile={args.profile} state={output} "
        f"cells={cells_by_type} particles={particles_by_type}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Generate a liquid drop in vacuum, optionally above a flat liquid puddle.

0493x9s is intentionally liquid-only: no gas particles and no inactive slots.
The state uses the established SRCMPCD_STATE v2 layout.  Occupancy is sampled
with deterministic sub-cell points so the curved free surface can carry
fractional cell fill without a background phase.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import struct
import sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def pos_int(s: str) -> int:
    v = int(s)
    if v <= 0:
        raise argparse.ArgumentTypeError("expected positive integer")
    return v


def pos_float(s: str) -> float:
    v = float(s)
    if not math.isfinite(v) or v <= 0.0:
        raise argparse.ArgumentTypeError("expected finite positive number")
    return v


def nonneg_float(s: str) -> float:
    v = float(s)
    if not math.isfinite(v) or v < 0.0:
        raise argparse.ArgumentTypeError("expected finite non-negative number")
    return v


def finite_float(s: str) -> float:
    v = float(s)
    if not math.isfinite(v):
        raise argparse.ArgumentTypeError("expected finite number")
    return v


def coprime_multiplier(modulus: int, start: int, avoid: int = -1) -> int:
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1


def paired_fluctuations(rng: random.Random, count: int, mass: float, kbt: float):
    """Cell-relative thermal fluctuations with exactly zero cell COM."""
    if count <= 0:
        return []
    if kbt == 0.0 or count == 1:
        return [(0.0, 0.0)] * count
    vals = []
    for _ in range(count // 2):
        gx, gy = rng.gauss(0.0, 1.0), rng.gauss(0.0, 1.0)
        vals.extend(((gx, gy), (-gx, -gy)))
    if count % 2:
        vals.append((0.0, 0.0))
    s2 = sum(a * a + b * b for a, b in vals)
    scale = math.sqrt((2.0 * count * kbt) / (mass * s2)) if s2 > 0.0 else 0.0
    return [(scale * a, scale * b) for a, b in vals]


def write_state(path: Path, x, y, vx, vy, typ, mass, role: bytearray) -> None:
    n = len(x)
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    path.parent.mkdir(parents=True, exist_ok=True)
    arrays = (x, y, vx, vy, typ, mass)
    if sys.byteorder == "big":
        for a in arrays:
            a.byteswap()
    try:
        with path.open("wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
            f.write(struct.pack("<8Q", *reserved))
            for a in arrays:
                a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder == "big":
            for a in arrays:
                a.byteswap()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--target", choices=("wall", "puddle"), required=True)
    ap.add_argument("--Lx", type=pos_float, required=True)
    ap.add_argument("--Ly", type=pos_float, required=True)
    ap.add_argument("--nx", type=pos_int, required=True)
    ap.add_argument("--ny", type=pos_int, required=True)
    ap.add_argument("--gamma", type=pos_int, required=True)
    ap.add_argument("--drop-center-x", type=finite_float, required=True)
    ap.add_argument("--drop-center-y", type=finite_float, required=True)
    ap.add_argument("--drop-radius", type=pos_float, required=True)
    ap.add_argument("--drop-vx", type=finite_float, default=0.0)
    ap.add_argument("--drop-vy", type=finite_float, required=True)
    ap.add_argument("--puddle-depth", type=nonneg_float, default=0.0)
    ap.add_argument("--liquid-type", type=pos_int, default=1)
    ap.add_argument("--liquid-mass", type=pos_float, default=10.0)
    ap.add_argument("--kBT", type=nonneg_float, default=1.25e-6)
    ap.add_argument("--seed", type=int, default=493950)
    args = ap.parse_args()

    if args.gamma < 2:
        ap.error("gamma must be >=2")
    dx, dy = args.Lx / args.nx, args.Ly / args.ny
    if abs(dx - dy) > 1e-12 * max(1.0, abs(dx), abs(dy)):
        ap.error("square cells required")
    r = args.drop_radius
    cx, cy = args.drop_center_x, args.drop_center_y
    if cx - r <= 0.0 or cx + r >= args.Lx or cy - r <= 0.0 or cy + r >= args.Ly:
        ap.error("drop must start strictly inside the box")
    puddle_depth = args.puddle_depth if args.target == "puddle" else 0.0
    if args.target == "puddle" and not (puddle_depth > 0.0):
        ap.error("puddle target requires positive puddle depth")
    if puddle_depth >= cy - r - 2.0 * dy:
        ap.error("initial drop must be separated from puddle by at least two cells")

    ax = coprime_multiplier(args.gamma, 3)
    ay = coprime_multiplier(args.gamma, 7, avoid=ax)
    rng = random.Random(args.seed)

    # Visit only cells that can contain liquid: the drop bounding box plus the
    # shallow puddle.  This keeps vacuum cases fast even on an 800x400 grid.
    cells = set()
    ix0 = max(0, int(math.floor((cx - r) / dx)) - 1)
    ix1 = min(args.nx - 1, int(math.floor((cx + r) / dx)) + 1)
    iy0 = max(0, int(math.floor((cy - r) / dy)) - 1)
    iy1 = min(args.ny - 1, int(math.floor((cy + r) / dy)) + 1)
    for iy in range(iy0, iy1 + 1):
        for ix in range(ix0, ix1 + 1):
            cells.add((iy, ix))
    if puddle_depth > 0.0:
        py1 = min(args.ny - 1, int(math.floor(puddle_depth / dy)) + 1)
        for iy in range(0, py1 + 1):
            for ix in range(args.nx):
                cells.add((iy, ix))

    x = array("d")
    y = array("d")
    vx = array("d")
    vy = array("d")
    typ = array("I")
    mass = array("d")
    role = bytearray()
    n_drop = 0
    n_puddle = 0
    mixed_cells = 0
    occupied_cells = 0

    for iy, ix in sorted(cells):
        particles = []
        for k in range(args.gamma):
            fx = ((ax * k) % args.gamma + 0.5) / args.gamma
            fy = ((ay * k) % args.gamma + 0.5) / args.gamma
            px, py = (ix + fx) * dx, (iy + fy) * dy
            in_drop = (px - cx) ** 2 + (py - cy) ** 2 <= r * r
            in_puddle = puddle_depth > 0.0 and py <= puddle_depth
            if in_drop and in_puddle:
                ap.error("drop/puddle overlap encountered despite geometry preflight")
            if in_drop:
                particles.append((px, py, "drop"))
            elif in_puddle:
                particles.append((px, py, "puddle"))
        if not particles:
            continue
        occupied_cells += 1
        if len(particles) != args.gamma:
            mixed_cells += 1
        fluc = paired_fluctuations(rng, len(particles), args.liquid_mass, args.kBT)
        for (px, py, component), (du, dv) in zip(particles, fluc):
            if component == "drop":
                ux, uy = args.drop_vx + du, args.drop_vy + dv
                n_drop += 1
            else:
                ux, uy = du, dv
                n_puddle += 1
            x.append(px); y.append(py); vx.append(ux); vy.append(uy)
            typ.append(args.liquid_type); mass.append(args.liquid_mass); role.append(1)

    if n_drop == 0:
        ap.error("drop contains no particles")
    if args.target == "puddle" and n_puddle == 0:
        ap.error("puddle contains no particles")

    write_state(args.output, x, y, vx, vy, typ, mass, role)
    meta = {
        "profile": "liquid_vacuum_splash_0493x9s",
        "target": args.target,
        "Lx": args.Lx, "Ly": args.Ly,
        "nx": args.nx, "ny": args.ny,
        "dx": dx, "dy": dy, "gamma": args.gamma,
        "dropCenterX": cx, "dropCenterY": cy,
        "dropRadius": r, "dropRadiusCells": r / dx,
        "dropVx": args.drop_vx, "dropVy": args.drop_vy,
        "puddleDepth": puddle_depth, "puddleDepthCells": puddle_depth / dy,
        "liquidType": args.liquid_type, "liquidMass": args.liquid_mass,
        "kBT": args.kBT, "seed": args.seed,
        "particles": len(x), "dropParticles": n_drop, "puddleParticles": n_puddle,
        "occupiedCells": occupied_cells, "partialFillCells": mixed_cells,
    }
    meta_path = args.output.with_suffix(args.output.suffix + ".json")
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    print(
        f"[0493x9s-generate] target={args.target} grid={args.nx}x{args.ny} "
        f"h={dx:.10g} gamma={args.gamma} N={len(x)} drop={n_drop} puddle={n_puddle}"
    )
    print(
        f"[0493x9s-generate] drop R/h={r/dx:.6g} center=({cx:.8g},{cy:.8g}) "
        f"v=({args.drop_vx:.8g},{args.drop_vy:.8g}) puddle/h={puddle_depth/dy:.6g}"
    )
    print(f"[0493x9s-generate] state={args.output} metadata={meta_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

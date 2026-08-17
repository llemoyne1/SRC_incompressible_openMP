#!/usr/bin/env python3
"""Generate a deterministic two-species ellipse state for 0493x9a.

Every Eulerian cell contains exactly gamma particles.  Particle positions form a
low-discrepancy deterministic in-cell pattern; type is assigned from the exact
rotated ellipse indicator at each particle position.  Consequently
rawFill = liquid_count/gamma for equal liquid particle masses and naturally
contains fractional interface cells without a separate VOF field.
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


def coprime_multiplier(modulus: int, start: int, avoid: int = -1) -> int:
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1


def paired_velocities(rng: random.Random, count: int, mass: float, kbt: float):
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
    s2 = sum(x*x + y*y for x, y in vals)
    scale = math.sqrt((2.0 * count * kbt) / (mass * s2)) if s2 > 0.0 else 0.0
    return [(scale*x, scale*y) for x, y in vals]


def write_state(path: Path, x, y, vx, vy, typ, mass, role):
    n = len(x)
    if not (len(y) == len(vx) == len(vy) == len(typ) == len(mass) == len(role) == n):
        raise RuntimeError("inconsistent state arrays")
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    path.parent.mkdir(parents=True, exist_ok=True)
    if sys.byteorder == "big":
        for a in (x, y, vx, vy, typ, mass):
            a.byteswap()
    try:
        with path.open("wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
            f.write(struct.pack("<8Q", *reserved))
            for a in (x, y, vx, vy, typ, mass):
                a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder == "big":
            for a in (x, y, vx, vy, typ, mass):
                a.byteswap()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--Lx", type=pos_float, default=1.5625)
    ap.add_argument("--Ly", type=pos_float, default=1.5625)
    ap.add_argument("--nx", type=pos_int, default=400)
    ap.add_argument("--ny", type=pos_int, default=400)
    ap.add_argument("--gamma", type=pos_int, default=20)
    ap.add_argument("--center-x", type=float, default=None)
    ap.add_argument("--center-y", type=float, default=None)
    ap.add_argument("--radius-x", type=pos_float, default=0.3125)
    ap.add_argument("--radius-y", type=pos_float, default=0.3125)
    ap.add_argument("--angle-deg", type=float, default=0.0)
    ap.add_argument("--liquid-type", type=pos_int, default=1)
    ap.add_argument("--gas-type", type=pos_int, default=2)
    ap.add_argument("--liquid-mass", type=pos_float, default=1.0)
    ap.add_argument("--gas-mass", type=pos_float, default=1.0)
    ap.add_argument("--kBT", type=nonneg_float, default=0.125)
    ap.add_argument("--seed", type=int, default=493901)
    args = ap.parse_args()

    if args.gamma < 2:
        ap.error("gamma must be >=2")
    if args.liquid_type == args.gas_type:
        ap.error("liquid and gas types must differ")
    if not math.isfinite(args.angle_deg):
        ap.error("angle must be finite")
    cx = args.Lx * 0.5 if args.center_x is None else args.center_x
    cy = args.Ly * 0.5 if args.center_y is None else args.center_y
    if not (math.isfinite(cx) and math.isfinite(cy)):
        ap.error("center must be finite")

    dx, dy = args.Lx / args.nx, args.Ly / args.ny
    theta = math.radians(args.angle_deg)
    ct, st = math.cos(theta), math.sin(theta)
    ax = coprime_multiplier(args.gamma, 3)
    ay = coprime_multiplier(args.gamma, 7, avoid=ax)
    rng = random.Random(args.seed)

    x = array("d"); y = array("d"); vx = array("d"); vy = array("d")
    typ = array("I"); mass = array("d"); role = bytearray()
    liquid_particles = gas_particles = mixed_cells = liquid_cells = gas_cells = 0

    for iy in range(args.ny):
        for ix in range(args.nx):
            positions = []
            types = []
            for k in range(args.gamma):
                fx = ((ax * k) % args.gamma + 0.5) / args.gamma
                fy = ((ay * k) % args.gamma + 0.5) / args.gamma
                px, py = (ix + fx) * dx, (iy + fy) * dy
                qx, qy = px - cx, py - cy
                xr = ct * qx + st * qy
                yr = -st * qx + ct * qy
                inside = (xr / args.radius_x) ** 2 + (yr / args.radius_y) ** 2 <= 1.0
                positions.append((px, py))
                types.append(args.liquid_type if inside else args.gas_type)

            nl = sum(t == args.liquid_type for t in types)
            ng = args.gamma - nl
            if nl == args.gamma:
                liquid_cells += 1
            elif ng == args.gamma:
                gas_cells += 1
            else:
                mixed_cells += 1
            liquid_particles += nl
            gas_particles += ng

            vl = paired_velocities(rng, nl, args.liquid_mass, args.kBT)
            vg = paired_velocities(rng, ng, args.gas_mass, args.kBT)
            il = ig = 0
            for (px, py), t in zip(positions, types):
                if t == args.liquid_type:
                    ux, uy = vl[il]; il += 1; m = args.liquid_mass
                else:
                    ux, uy = vg[ig]; ig += 1; m = args.gas_mass
                x.append(px); y.append(py); vx.append(ux); vy.append(uy)
                typ.append(t); mass.append(m); role.append(1)

    write_state(args.output, x, y, vx, vy, typ, mass, role)
    meta = {
        "profile": "rotated_ellipse_two_species_0493x9a",
        "Lx": args.Lx, "Ly": args.Ly, "nx": args.nx, "ny": args.ny,
        "dx": dx, "dy": dy, "gamma": args.gamma,
        "centerX": cx, "centerY": cy,
        "radiusX": args.radius_x, "radiusY": args.radius_y,
        "angleDeg": args.angle_deg,
        "liquidType": args.liquid_type, "gasType": args.gas_type,
        "liquidMass": args.liquid_mass, "gasMass": args.gas_mass,
        "kBT": args.kBT, "seed": args.seed,
        "particles": len(x), "liquidParticles": liquid_particles,
        "gasParticles": gas_particles, "liquidCells": liquid_cells,
        "gasCells": gas_cells, "mixedCells": mixed_cells,
        "liquidFractionParticles": liquid_particles / max(1, len(x)),
        "semiAxisCellsX": args.radius_x / dx,
        "semiAxisCellsY": args.radius_y / dy,
    }
    meta_path = args.output.with_suffix(args.output.suffix + ".json")
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    print(
        "[0493x9a-generate] "
        f"grid={args.nx}x{args.ny} gamma={args.gamma} N={len(x)} "
        f"ellipse=({args.radius_x:g},{args.radius_y:g}) angle={args.angle_deg:g}deg "
        f"mixedCells={mixed_cells} liquidFraction={meta['liquidFractionParticles']:.6f}"
    )
    print(f"[0493x9a-generate] state={args.output}")
    print(f"[0493x9a-generate] metadata={meta_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

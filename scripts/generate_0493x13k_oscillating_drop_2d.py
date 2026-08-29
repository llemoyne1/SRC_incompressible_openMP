#!/usr/bin/env python3
"""0493x13k — generate a 2-D liquid/vacuum modal drop.

The initial interface is
    r(theta) = R * [c0 + eps*cos(n*theta)]
with c0 = sqrt(1 - eps^2/2), so the continuous area is exactly pi*R^2.

The smoke/qualification runner intentionally uses n=2 because the existing x9f
second-moment diagnostic gives a robust signed quadrupole observable without any
new CUDA/source diagnostic or heavy field recording.

State construction follows the deterministic sub-cell sampling pattern already
used by the x9 liquid/vacuum generators.  Thermal velocities are paired and
rescaled independently in each occupied cell so the initial cell mean velocity
is exactly zero (apart from one zero vector in odd-population cells).
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


def positive_int(s: str) -> int:
    v = int(s)
    if v <= 0:
        raise argparse.ArgumentTypeError("expected positive integer")
    return v


def positive_float(s: str) -> float:
    v = float(s)
    if not math.isfinite(v) or v <= 0.0:
        raise argparse.ArgumentTypeError("expected positive finite number")
    return v


def nonnegative_float(s: str) -> float:
    v = float(s)
    if not math.isfinite(v) or v < 0.0:
        raise argparse.ArgumentTypeError("expected non-negative finite number")
    return v


def coprime_multiplier(modulus: int, start: int, avoid: int = -1) -> int:
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1


def paired_fluctuations(rng: random.Random, count: int, mass: float, kbt: float):
    if count <= 0:
        return []
    if count == 1 or kbt == 0.0:
        return [(0.0, 0.0)] * count
    vals = []
    for _ in range(count // 2):
        gx, gy = rng.gauss(0.0, 1.0), rng.gauss(0.0, 1.0)
        vals.extend(((gx, gy), (-gx, -gy)))
    if count % 2:
        vals.append((0.0, 0.0))
    s2 = sum(u * u + v * v for u, v in vals)
    scale = math.sqrt(2.0 * count * kbt / (mass * s2)) if s2 > 0.0 else 0.0
    return [(scale * u, scale * v) for u, v in vals]


def write_state(path: Path, x, y, vx, vy, typ, mass, role) -> None:
    n = len(x)
    if not all(len(a) == n for a in (y, vx, vy, typ, mass, role)):
        raise RuntimeError("inconsistent state arrays")
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
    ap.add_argument("--Lx", type=positive_float, default=1.0)
    ap.add_argument("--Ly", type=positive_float, default=1.0)
    ap.add_argument("--nx", type=positive_int, default=256)
    ap.add_argument("--ny", type=positive_int, default=256)
    ap.add_argument("--gamma", type=positive_int, default=8)
    ap.add_argument("--center-x", type=float, default=0.5)
    ap.add_argument("--center-y", type=float, default=0.5)
    ap.add_argument("--radius-cells", type=positive_float, default=40.0)
    ap.add_argument("--mode", type=positive_int, default=2)
    ap.add_argument("--epsilon", type=positive_float, default=0.02)
    ap.add_argument("--phase", type=float, default=0.0)
    ap.add_argument("--liquid-type", type=positive_int, default=1)
    ap.add_argument("--liquid-mass", type=positive_float, default=1.0)
    ap.add_argument("--kBT", type=nonnegative_float, default=0.125)
    ap.add_argument("--seed", type=int, default=4931401)
    a = ap.parse_args()

    dx, dy = a.Lx / a.nx, a.Ly / a.ny
    if abs(dx - dy) > 1.0e-12 * max(1.0, abs(dx), abs(dy)):
        ap.error("square cells are required")
    if not all(math.isfinite(v) for v in (a.center_x, a.center_y, a.phase)):
        ap.error("center/phase must be finite")
    if not (0.0 < a.epsilon < 0.25):
        ap.error("epsilon must lie in (0,0.25) for this small-amplitude benchmark")

    h = dx
    R = a.radius_cells * h
    c0 = math.sqrt(1.0 - 0.5 * a.epsilon * a.epsilon)
    rmax = R * (c0 + abs(a.epsilon))
    clearance = min(a.center_x, a.Lx - a.center_x, a.center_y, a.Ly - a.center_y) - rmax
    if clearance <= 4.0 * h:
        ap.error(
            f"modal drop must remain >4h from every external wall: clearance/h={clearance/h:.6g}"
        )

    ax = coprime_multiplier(a.gamma, 3)
    ay = coprime_multiplier(a.gamma, 7, avoid=ax)
    rng = random.Random(a.seed)

    x = array("d")
    y = array("d")
    vx = array("d")
    vy = array("d")
    typ = array("I")
    mass = array("d")
    role = bytearray()

    occupied_cells = 0
    partial_cells = 0
    one_particle_cells = 0

    ix0 = max(0, int(math.floor((a.center_x - rmax) / dx)) - 1)
    ix1 = min(a.nx - 1, int(math.floor((a.center_x + rmax) / dx)) + 1)
    iy0 = max(0, int(math.floor((a.center_y - rmax) / dy)) - 1)
    iy1 = min(a.ny - 1, int(math.floor((a.center_y + rmax) / dy)) + 1)

    for iy in range(iy0, iy1 + 1):
        for ix in range(ix0, ix1 + 1):
            pts = []
            for q in range(a.gamma):
                fx = ((ax * q) % a.gamma + 0.5) / a.gamma
                fy = ((ay * q) % a.gamma + 0.5) / a.gamma
                px = (ix + fx) * dx
                py = (iy + fy) * dy
                rx = px - a.center_x
                ry = py - a.center_y
                rr = math.hypot(rx, ry)
                theta = math.atan2(ry, rx)
                rb = R * (c0 + a.epsilon * math.cos(a.mode * theta + a.phase))
                if rr <= rb:
                    pts.append((px, py))
            if not pts:
                continue
            occupied_cells += 1
            if len(pts) != a.gamma:
                partial_cells += 1
            if len(pts) == 1:
                one_particle_cells += 1
            fluc = paired_fluctuations(rng, len(pts), a.liquid_mass, a.kBT)
            for (px, py), (du, dv) in zip(pts, fluc):
                x.append(px)
                y.append(py)
                vx.append(du)
                vy.append(dv)
                typ.append(a.liquid_type)
                mass.append(a.liquid_mass)
                role.append(1)

    if not x:
        raise RuntimeError("generated modal drop is empty")

    # Remove any residual global mean drift (normally already roundoff-small).
    mvx = sum(vx) / len(vx)
    mvy = sum(vy) / len(vy)
    for i in range(len(vx)):
        vx[i] -= mvx
        vy[i] -= mvy

    write_state(a.output, x, y, vx, vy, typ, mass, role)

    target_area = math.pi * R * R
    discrete_area = len(x) * dx * dy / a.gamma
    reff_discrete = math.sqrt(discrete_area / math.pi)
    meta = {
        "profile": "liquid_vacuum_modal_drop_0493x13k",
        "Lx": a.Lx,
        "Ly": a.Ly,
        "nx": a.nx,
        "ny": a.ny,
        "dx": dx,
        "dy": dy,
        "gamma": a.gamma,
        "centerX": a.center_x,
        "centerY": a.center_y,
        "radius": R,
        "radiusCells": a.radius_cells,
        "mode": a.mode,
        "epsilon": a.epsilon,
        "phase": a.phase,
        "areaFactorC0": c0,
        "continuousTargetArea": target_area,
        "discreteParticleArea": discrete_area,
        "discreteAreaRelativeError": (discrete_area - target_area) / target_area,
        "discreteEffectiveRadius": reff_discrete,
        "maxRadius": rmax,
        "wallClearance": clearance,
        "wallClearanceCells": clearance / h,
        "liquidType": a.liquid_type,
        "liquidMass": a.liquid_mass,
        "kBT": a.kBT,
        "seed": a.seed,
        "particles": len(x),
        "occupiedCells": occupied_cells,
        "partialFillCells": partial_cells,
        "oneParticleCells": one_particle_cells,
        "initialGlobalMeanVxBeforeRemoval": mvx,
        "initialGlobalMeanVyBeforeRemoval": mvy,
    }
    mp = a.output.with_suffix(a.output.suffix + ".json")
    mp.write_text(json.dumps(meta, indent=2) + "\n")

    print(
        f"[0493x13k-generate] grid={a.nx}x{a.ny} h={h:.10g} gamma={a.gamma} "
        f"N={len(x)} R/h={a.radius_cells:g} mode={a.mode} eps={a.epsilon:g} c0={c0:.12g}"
    )
    print(
        f"[0493x13k-generate] targetArea={target_area:.12g} discreteArea={discrete_area:.12g} "
        f"relErr={(discrete_area/target_area-1):+.3e} Reff/h={reff_discrete/h:.8g} "
        f"clearance/h={clearance/h:.6g}"
    )
    print(f"[0493x13k-generate] state={a.output}")
    print(f"[0493x13k-generate] metadata={mp}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

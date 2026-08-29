#!/usr/bin/env python3
"""0493x13n — generate a finite 2-D liquid sheet with two free edges.

Geometry: rounded rectangle, centered at (cx,cy), with total tip-to-tip length Ls,
thickness H and corner radius rc.  The small corner rounding regularizes the cut
edge without pre-creating a semicircular Taylor-Culick rim of mass O(rho H^2).

State construction follows the deterministic sub-cell pattern used by x13k.
Thermal velocities are paired and exactly zero-mean in each occupied cell, then
a residual global mean is removed.  No source/physics change is involved.
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


def p_int(s: str) -> int:
    v = int(s)
    if v <= 0:
        raise argparse.ArgumentTypeError("expected positive integer")
    return v


def p_float(s: str) -> float:
    v = float(s)
    if not math.isfinite(v) or v <= 0.0:
        raise argparse.ArgumentTypeError("expected positive finite number")
    return v


def nn_float(s: str) -> float:
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
    s2 = sum(u*u + v*v for u, v in vals)
    scale = math.sqrt(2.0 * count * kbt / (mass * s2)) if s2 > 0.0 else 0.0
    return [(scale*u, scale*v) for u, v in vals]


def rounded_rectangle_inside(x: float, y: float, cx: float, cy: float,
                             half_length: float, half_thickness: float,
                             radius: float) -> bool:
    # Standard rounded-box signed-distance test.  radius <= both half-extents.
    qx = abs(x - cx) - (half_length - radius)
    qy = abs(y - cy) - (half_thickness - radius)
    ox = max(qx, 0.0)
    oy = max(qy, 0.0)
    outside = math.hypot(ox, oy)
    inside = min(max(qx, qy), 0.0)
    return outside + inside <= radius


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
    ap.add_argument("--Lx", type=p_float, default=2.5)
    ap.add_argument("--Ly", type=p_float, default=1.0)
    ap.add_argument("--nx", type=p_int, default=640)
    ap.add_argument("--ny", type=p_int, default=256)
    ap.add_argument("--gamma", type=p_int, default=8)
    ap.add_argument("--center-x", type=float, default=1.25)
    ap.add_argument("--center-y", type=float, default=0.5)
    ap.add_argument("--sheet-length-cells", type=p_float, default=512.0)
    ap.add_argument("--thickness-cells", type=p_float, default=64.0)
    ap.add_argument("--edge-round-cells", type=p_float, default=8.0)
    ap.add_argument("--liquid-type", type=p_int, default=1)
    ap.add_argument("--liquid-mass", type=p_float, default=1.0)
    ap.add_argument("--kBT", type=nn_float, default=0.125)
    ap.add_argument("--seed", type=int, default=4931501)
    a = ap.parse_args()

    dx, dy = a.Lx/a.nx, a.Ly/a.ny
    if abs(dx-dy) > 1e-12 * max(1.0, abs(dx), abs(dy)):
        ap.error("square cells are required")
    if not (math.isfinite(a.center_x) and math.isfinite(a.center_y)):
        ap.error("center must be finite")
    h = dx
    length = a.sheet_length_cells * h
    H = a.thickness_cells * h
    rc = a.edge_round_cells * h
    if not (0.0 < rc < 0.5*H and rc < 0.5*length):
        ap.error("edge rounding must be positive and smaller than both half-extents")

    halfL, halfH = 0.5*length, 0.5*H
    xclear = min(a.center_x-halfL, a.Lx-(a.center_x+halfL))
    yclear = min(a.center_y-halfH, a.Ly-(a.center_y+halfH))
    if min(xclear, yclear) <= 4.0*h:
        ap.error(f"sheet must remain >4h from external walls initially; xclear/h={xclear/h:.6g} yclear/h={yclear/h:.6g}")

    ax = coprime_multiplier(a.gamma, 3)
    ay = coprime_multiplier(a.gamma, 7, avoid=ax)
    rng = random.Random(a.seed)

    x = array("d"); y = array("d"); vx = array("d"); vy = array("d")
    typ = array("I"); mass = array("d"); role = bytearray()
    occupied_cells = partial_cells = one_particle_cells = 0

    ix0 = max(0, int(math.floor((a.center_x-halfL)/dx))-1)
    ix1 = min(a.nx-1, int(math.floor((a.center_x+halfL)/dx))+1)
    iy0 = max(0, int(math.floor((a.center_y-halfH)/dy))-1)
    iy1 = min(a.ny-1, int(math.floor((a.center_y+halfH)/dy))+1)

    for iy in range(iy0, iy1+1):
        for ix in range(ix0, ix1+1):
            pts = []
            for q in range(a.gamma):
                fx = ((ax*q) % a.gamma + 0.5)/a.gamma
                fy = ((ay*q) % a.gamma + 0.5)/a.gamma
                px = (ix+fx)*dx
                py = (iy+fy)*dy
                if rounded_rectangle_inside(px, py, a.center_x, a.center_y, halfL, halfH, rc):
                    pts.append((px, py))
            if not pts:
                continue
            occupied_cells += 1
            partial_cells += (len(pts) != a.gamma)
            one_particle_cells += (len(pts) == 1)
            fluc = paired_fluctuations(rng, len(pts), a.liquid_mass, a.kBT)
            for (px, py), (du, dv) in zip(pts, fluc):
                x.append(px); y.append(py); vx.append(du); vy.append(dv)
                typ.append(a.liquid_type); mass.append(a.liquid_mass); role.append(1)

    if not x:
        raise RuntimeError("generated sheet is empty")

    mvx = sum(vx)/len(vx); mvy = sum(vy)/len(vy)
    for i in range(len(vx)):
        vx[i] -= mvx; vy[i] -= mvy

    write_state(a.output, x, y, vx, vy, typ, mass, role)

    target_area = length*H - (4.0-math.pi)*rc*rc
    discrete_area = len(x)*dx*dy/a.gamma
    meta = {
        "profile": "taylor_culick_rounded_sheet_0493x13n",
        "Lx": a.Lx, "Ly": a.Ly, "nx": a.nx, "ny": a.ny,
        "dx": dx, "dy": dy, "gamma": a.gamma,
        "centerX": a.center_x, "centerY": a.center_y,
        "sheetLength": length, "sheetLengthCells": a.sheet_length_cells,
        "thickness": H, "thicknessCells": a.thickness_cells,
        "edgeRoundRadius": rc, "edgeRoundCells": a.edge_round_cells,
        "continuousTargetArea": target_area,
        "discreteParticleArea": discrete_area,
        "discreteAreaRelativeError": (discrete_area-target_area)/target_area,
        "xWallClearance": xclear, "xWallClearanceCells": xclear/h,
        "yWallClearance": yclear, "yWallClearanceCells": yclear/h,
        "liquidType": a.liquid_type, "liquidMass": a.liquid_mass,
        "kBT": a.kBT, "seed": a.seed, "particles": len(x),
        "occupiedCells": occupied_cells, "partialFillCells": partial_cells,
        "oneParticleCells": one_particle_cells,
        "initialGlobalMeanVxBeforeRemoval": mvx,
        "initialGlobalMeanVyBeforeRemoval": mvy,
    }
    mp = a.output.with_suffix(a.output.suffix + ".json")
    mp.write_text(json.dumps(meta, indent=2) + "\n")

    print(f"[0493x13n-generate] grid={a.nx}x{a.ny} h={h:.10g} gamma={a.gamma} N={len(x)}")
    print(f"[0493x13n-generate] sheet L/h={a.sheet_length_cells:g} H/h={a.thickness_cells:g} corner/h={a.edge_round_cells:g}")
    print(f"[0493x13n-generate] targetArea={target_area:.12g} discreteArea={discrete_area:.12g} relErr={(discrete_area/target_area-1):+.3e}")
    print(f"[0493x13n-generate] wall clearance x/h={xclear/h:.6g} y/h={yclear/h:.6g}")
    print(f"[0493x13n-generate] state={a.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

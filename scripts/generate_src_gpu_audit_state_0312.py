#!/usr/bin/env python3
"""Generate compact SRC/MPCD .smpcd states for independent CUDA audit scripts.

This generator is intentionally self-contained and does not source or call any
run_demo_* shell script.  It supports the two audit geometries used by 0312:
backward-step rectangle and Von Karman cylinder.
"""
from __future__ import annotations

import argparse
import math
import os
import random
import struct
from typing import List, Sequence, Tuple

Rect = Tuple[float, float, float, float]
Circle = Tuple[float, float, float]


def parse_rect(s: str | None) -> Rect | None:
    if not s or s.lower() == "none":
        return None
    vals = [float(v) for v in s.replace(",", " ").split()]
    if len(vals) != 4:
        raise SystemExit(f"invalid --rect specification: {s!r}")
    xmin, xmax, ymin, ymax = vals
    if xmax <= xmin or ymax <= ymin:
        raise SystemExit(f"invalid --rect bounds: {s!r}")
    return xmin, xmax, ymin, ymax


def parse_circle(s: str | None) -> Circle | None:
    if not s or s.lower() == "none":
        return None
    vals = [float(v) for v in s.replace(",", " ").split()]
    if len(vals) != 3:
        raise SystemExit(f"invalid --circle specification: {s!r}")
    cx, cy, r = vals
    if r <= 0.0:
        raise SystemExit(f"invalid --circle radius: {s!r}")
    return cx, cy, r


def in_solid(x: float, y: float, rects: Sequence[Rect], circles: Sequence[Circle]) -> bool:
    for xmin, xmax, ymin, ymax in rects:
        if xmin <= x <= xmax and ymin <= y <= ymax:
            return True
    for cx, cy, r in circles:
        if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
            return True
    return False


def base_velocity(mode: str, x: float, y: float, *, Lx: float, Ly: float, ux: float, uy: float, amp: float) -> Tuple[float, float]:
    if mode == "zero":
        return 0.0, 0.0
    if mode == "uniform":
        return ux, uy
    if mode == "taylor_green":
        vx = amp * math.sin(2.0 * math.pi * x / Lx) * math.cos(2.0 * math.pi * y / Ly)
        vy = -amp * math.cos(2.0 * math.pi * x / Lx) * math.sin(2.0 * math.pi * y / Ly)
        return vx + ux, vy + uy
    raise SystemExit(f"unsupported --velocity-mode: {mode}")


def write_smpcd(path: str, x: List[float], y: List[float], vx: List[float], vy: List[float], typ: List[int], mass: List[float], role: List[int]) -> None:
    n = len(x)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    magic = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    with open(path, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        f.write(struct.pack("<8Q", *reserved))
        for arr, fmt in ((x, "d"), (y, "d"), (vx, "d"), (vy, "d"), (typ, "I"), (mass, "d"), (role, "B")):
            f.write(struct.pack(f"<{n}{fmt}", *arr))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", required=True)
    ap.add_argument("--Lx", type=float, default=3.0)
    ap.add_argument("--Ly", type=float, default=1.0)
    ap.add_argument("--Nx", type=int, default=96)
    ap.add_argument("--Ny", type=int, default=48)
    ap.add_argument("--gamma", type=int, default=20)
    ap.add_argument("--kBT", type=float, default=0.001)
    ap.add_argument("--seed", type=int, default=1629312)
    ap.add_argument("--velocity-mode", default="uniform", choices=["zero", "uniform", "taylor_green"])
    ap.add_argument("--mean-ux", type=float, default=0.0)
    ap.add_argument("--mean-uy", type=float, default=0.0)
    ap.add_argument("--amp", type=float, default=0.0)
    ap.add_argument("--inactive-slots", type=int, default=0)
    ap.add_argument("--rect", default="none")
    ap.add_argument("--circle", default="none")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    rect = parse_rect(args.rect)
    circle = parse_circle(args.circle)
    rects = [rect] if rect else []
    circles = [circle] if circle else []
    dx = args.Lx / args.Nx
    dy = args.Ly / args.Ny
    sigma = math.sqrt(args.kBT) if args.kBT > 0.0 else 0.0

    x: List[float] = []
    y: List[float] = []
    vx: List[float] = []
    vy: List[float] = []
    typ: List[int] = []
    mass: List[float] = []
    role: List[int] = []
    fluid_cells = 0
    solid_cells = 0
    rejected = 0

    for j in range(args.Ny):
        cy = (j + 0.5) * dy
        for i in range(args.Nx):
            cx = (i + 0.5) * dx
            if in_solid(cx, cy, rects, circles):
                solid_cells += 1
                continue
            fluid_cells += 1
            x0 = i * dx
            y0 = j * dy
            for _ in range(args.gamma):
                ok = False
                xp = yp = 0.0
                for _attempt in range(2000):
                    xp = x0 + dx * rng.random()
                    yp = y0 + dy * rng.random()
                    if in_solid(xp, yp, rects, circles):
                        rejected += 1
                        continue
                    ok = True
                    break
                if not ok:
                    continue
                ux, uy = base_velocity(args.velocity_mode, xp, yp, Lx=args.Lx, Ly=args.Ly, ux=args.mean_ux, uy=args.mean_uy, amp=args.amp)
                if sigma > 0.0:
                    ux += sigma * rng.gauss(0.0, 1.0)
                    uy += sigma * rng.gauss(0.0, 1.0)
                x.append(xp)
                y.append(yp)
                vx.append(ux)
                vy.append(uy)
                typ.append(0)
                mass.append(1.0)
                role.append(1)

    if not x:
        raise SystemExit("generated zero fluid particles")

    # Remove stochastic mean drift while preserving the requested mean velocity.
    m_tot = sum(mass)
    mean_vx = sum(m * u for m, u in zip(mass, vx)) / m_tot
    mean_vy = sum(m * u for m, u in zip(mass, vy)) / m_tot
    target_vx = args.mean_ux if args.velocity_mode == "uniform" else 0.0
    target_vy = args.mean_uy if args.velocity_mode == "uniform" else 0.0
    vx = [u - mean_vx + target_vx for u in vx]
    vy = [v - mean_vy + target_vy for v in vy]

    # Inactive slots are capacity only.  Put them in a valid coordinate but keep
    # role=0 so physics kernels should ignore them.
    for _ in range(max(0, args.inactive_slots)):
        x.append(0.0)
        y.append(0.0)
        vx.append(0.0)
        vy.append(0.0)
        typ.append(0)
        mass.append(1.0)
        role.append(0)

    write_smpcd(args.output, x, y, vx, vy, typ, mass, role)
    print(
        f"[0312-state] output={args.output} grid={args.Nx}x{args.Ny} "
        f"fluidCells={fluid_cells} solidCells={solid_cells} fluid={len(x)-args.inactive_slots} "
        f"inactive={args.inactive_slots} total={len(x)} rejected={rejected}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""0345/topo: generate row-major float32 chi fields for Darcy/Brinkman runs.

Convention: chi=1 is free fluid, chi=0 is solid/porous penalized material.
Output layout: float32 chi[iy*Nx + ix], cell-centered over [0,Lx]x[0,Ly].
"""
from __future__ import annotations

import argparse
import array
import math
from pathlib import Path


def clamp01(x: float) -> float:
    return 0.0 if x < 0.0 else 1.0 if x > 1.0 else x


def smoothstep(t: float) -> float:
    t = clamp01(t)
    return t * t * (3.0 - 2.0 * t)


def chi_circle_obstacle(x: float, y: float, args: argparse.Namespace) -> float:
    d = math.hypot(x - args.cx, y - args.cy)
    if args.interface_width > 0.0:
        return smoothstep((d - args.radius) / args.interface_width)
    return 0.0 if d <= args.radius else 1.0


def dist_to_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    vv = vx * vx + vy * vy
    if vv <= 0.0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, (wx * vx + wy * vy) / vv))
    qx, qy = ax + t * vx, ay + t * vy
    return math.hypot(px - qx, py - qy)


def dist_to_arc(px: float, py: float, cx: float, cy: float, r: float, a0: float, a1: float) -> float:
    # Angles in radians, assuming a0 <= a1 and no wrap.  Used for a 90-degree bend.
    ang = math.atan2(py - cy, px - cx)
    if ang < a0:
        qx, qy = cx + r * math.cos(a0), cy + r * math.sin(a0)
        return math.hypot(px - qx, py - qy)
    if ang > a1:
        qx, qy = cx + r * math.cos(a1), cy + r * math.sin(a1)
        return math.hypot(px - qx, py - qy)
    return abs(math.hypot(px - cx, py - cy) - r)


def chi_bend_pipe(x: float, y: float, args: argparse.Namespace) -> float:
    # Simple analytic L-bend centerline: horizontal inlet -> quarter arc -> vertical outlet.
    # Default geometry is meant as a topo test field, not yet a calibrated benchmark.
    w2 = 0.5 * args.pipe_width
    r = args.bend_radius
    cx, cy = args.cx, args.cy
    # horizontal segment ends at arc start (cx+r, cy)
    d_h = dist_to_segment(x, y, 0.0, cy, cx + r, cy)
    # vertical segment starts at arc end (cx, cy+r)
    d_v = dist_to_segment(x, y, cx, cy + r, cx, args.Ly)
    # quarter arc from angle 0 to pi/2 around (cx,cy)
    d_a = dist_to_arc(x, y, cx, cy, r, 0.0, 0.5 * math.pi)
    d = min(d_h, d_v, d_a) - w2
    if args.interface_width > 0.0:
        return 1.0 - smoothstep(d / args.interface_width)
    return 1.0 if d <= 0.0 else 0.0


def chi_diagonal_channel(x: float, y: float, args: argparse.Namespace) -> float:
    # Straight descending channel from left boundary to bottom boundary.
    # Intended to mimic the RANS/topology reference sketch: inlet on x=0,
    # outlet on y=0, with a smoothed diagonal conduit through the design box.
    ax, ay = 0.0, args.inlet_y
    bx, by = args.outlet_x, 0.0
    d = dist_to_segment(x, y, ax, ay, bx, by) - 0.5 * args.pipe_width
    if args.interface_width > 0.0:
        return 1.0 - smoothstep(d / args.interface_width)
    return 1.0 if d <= 0.0 else 0.0


def generate(args: argparse.Namespace) -> list[float]:
    vals: list[float] = []
    for iy in range(args.Ny):
        y = (iy + 0.5) * args.Ly / args.Ny
        for ix in range(args.Nx):
            x = (ix + 0.5) * args.Lx / args.Nx
            if args.mode == "circle_obstacle":
                chi = chi_circle_obstacle(x, y, args)
            elif args.mode == "bend_pipe":
                chi = chi_bend_pipe(x, y, args)
            elif args.mode == "diagonal_channel":
                chi = chi_diagonal_channel(x, y, args)
            elif args.mode == "uniform":
                chi = args.uniform_chi
            else:
                raise ValueError(f"unsupported mode: {args.mode}")
            vals.append(clamp01(float(chi)))
    return vals


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["circle_obstacle", "bend_pipe", "diagonal_channel", "uniform"], default="circle_obstacle")
    ap.add_argument("--out", required=True)
    ap.add_argument("--Nx", type=int, required=True)
    ap.add_argument("--Ny", type=int, required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--format", choices=["float32"], default="float32")
    ap.add_argument("--cx", type=float, default=0.45)
    ap.add_argument("--cy", type=float, default=0.20)
    ap.add_argument("--radius", type=float, default=0.055)
    ap.add_argument("--interface-width", type=float, default=0.01)
    ap.add_argument("--uniform-chi", type=float, default=1.0)
    ap.add_argument("--pipe-width", type=float, default=0.10)
    ap.add_argument("--bend-radius", type=float, default=0.18)
    ap.add_argument("--inlet-y", type=float, default=0.78)
    ap.add_argument("--outlet-x", type=float, default=0.82)
    args = ap.parse_args()
    if args.Nx <= 0 or args.Ny <= 0 or args.Lx <= 0.0 or args.Ly <= 0.0:
        raise SystemExit("Nx, Ny, Lx and Ly must be positive")
    vals = generate(args)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    arr = array.array('f', vals)
    with out.open('wb') as f:
        arr.tofile(f)
    mean_chi = sum(vals) / len(vals)
    fluid_fraction = sum(1 for v in vals if v > 0.5) / len(vals)
    print(f"[0345-chi] wrote {out} mode={args.mode} format=float32 Nx={args.Nx} Ny={args.Ny} meanChi={mean_chi:.12g} fluidCellsGtHalf={fluid_fraction:.12g}")


if __name__ == "__main__":
    main()

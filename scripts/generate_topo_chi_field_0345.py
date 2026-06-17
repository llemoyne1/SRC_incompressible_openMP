#!/usr/bin/env python3
"""0345+/topo: generate row-major float32 chi fields for Darcy/Brinkman runs.

Convention: chi=1 is free fluid, chi=0 is solid/porous penalized material.
Output layout: float32 chi[iy*Nx + ix], cell-centered over [0,Lx]x[0,Ly].
"""
from __future__ import annotations

import argparse
import array
import math
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

Point = Tuple[float, float]


def clamp01(x: float) -> float:
    return 0.0 if x < 0.0 else 1.0 if x > 1.0 else x


def smoothstep(t: float) -> float:
    t = clamp01(t)
    return t * t * (3.0 - 2.0 * t)


def chi_from_signed_distance(sd: float, interface_width: float) -> float:
    # sd < 0 inside solid/penalized material, sd > 0 outside/free fluid.
    if interface_width > 0.0:
        return smoothstep(sd / interface_width)
    return 0.0 if sd <= 0.0 else 1.0


def chi_circle_obstacle(x: float, y: float, args: argparse.Namespace) -> float:
    d = math.hypot(x - args.cx, y - args.cy)
    return chi_from_signed_distance(d - args.radius, args.interface_width)


def chi_ellipse_obstacle(x: float, y: float, args: argparse.Namespace) -> float:
    a = max(args.ellipse_a, 1.0e-30)
    b = max(args.ellipse_b, 1.0e-30)
    th = math.radians(args.angle_deg)
    c, s = math.cos(th), math.sin(th)
    dx, dy = x - args.cx, y - args.cy
    xr = c * dx + s * dy
    yr = -s * dx + c * dy
    r = math.hypot(xr / a, yr / b)
    # Cheap signed-distance proxy adequate for smooth chi generation.
    sd = (r - 1.0) * min(a, b)
    return chi_from_signed_distance(sd, args.interface_width)


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
    d_h = dist_to_segment(x, y, 0.0, cy, cx + r, cy)
    d_v = dist_to_segment(x, y, cx, cy + r, cx, args.Ly)
    d_a = dist_to_arc(x, y, cx, cy, r, 0.0, 0.5 * math.pi)
    sd = min(d_h, d_v, d_a) - w2
    return 1.0 - smoothstep(sd / args.interface_width) if args.interface_width > 0.0 else (1.0 if sd <= 0.0 else 0.0)


def chi_diagonal_channel(x: float, y: float, args: argparse.Namespace) -> float:
    # Straight descending channel from left boundary to bottom boundary.
    ax, ay = 0.0, args.inlet_y
    bx, by = args.outlet_x, 0.0
    sd = dist_to_segment(x, y, ax, ay, bx, by) - 0.5 * args.pipe_width
    return 1.0 - smoothstep(sd / args.interface_width) if args.interface_width > 0.0 else (1.0 if sd <= 0.0 else 0.0)


def parse_naca4(code: str) -> Tuple[float, float, float]:
    digits = "".join(ch for ch in code if ch.isdigit())
    if len(digits) != 4:
        raise ValueError(f"NACA code must have four digits, got {code!r}")
    m = int(digits[0]) / 100.0
    p = int(digits[1]) / 10.0
    t = int(digits[2:]) / 100.0
    return m, p, t


def naca4_polygon(args: argparse.Namespace) -> List[Point]:
    m, p, t = parse_naca4(args.naca)
    c = args.chord
    n = max(24, args.naca_points)
    xs = [0.5 * c * (1.0 - math.cos(math.pi * i / (n - 1))) for i in range(n)]
    upper: List[Point] = []
    lower: List[Point] = []
    for x in xs:
        xc = x / c if c > 0.0 else 0.0
        yt = 5.0 * t * c * (
            0.2969 * math.sqrt(max(0.0, xc))
            - 0.1260 * xc
            - 0.3516 * xc * xc
            + 0.2843 * xc ** 3
            - 0.1015 * xc ** 4
        )
        if m > 0.0 and p > 0.0 and xc < p:
            yc = m * c / (p * p) * (2.0 * p * xc - xc * xc)
            dyc = 2.0 * m / (p * p) * (p - xc)
        elif m > 0.0 and p < 1.0:
            yc = m * c / ((1.0 - p) ** 2) * ((1.0 - 2.0 * p) + 2.0 * p * xc - xc * xc)
            dyc = 2.0 * m / ((1.0 - p) ** 2) * (p - xc)
        else:
            yc = 0.0
            dyc = 0.0
        th = math.atan(dyc)
        xu = x - yt * math.sin(th)
        yu = yc + yt * math.cos(th)
        xl = x + yt * math.sin(th)
        yl = yc - yt * math.cos(th)
        upper.append(transform_airfoil_point(xu, yu, args))
        lower.append(transform_airfoil_point(xl, yl, args))
    # Polygon orientation: upper leading->trailing, lower trailing->leading.
    return upper + list(reversed(lower))


def transform_airfoil_point(x: float, y: float, args: argparse.Namespace) -> Point:
    # Local chord midpoint is placed at (airfoil_cx, airfoil_cy), then rotated.
    x0 = x - 0.5 * args.chord
    y0 = y
    th = math.radians(args.aoa_deg)
    c, s = math.cos(th), math.sin(th)
    return args.airfoil_cx + c * x0 - s * y0, args.airfoil_cy + s * x0 + c * y0


def point_in_polygon(x: float, y: float, poly: Sequence[Point]) -> bool:
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)):
            xint = (xj - xi) * (y - yi) / ((yj - yi) if yj != yi else 1.0e-300) + xi
            if x < xint:
                inside = not inside
        j = i
    return inside


def distance_to_polygon(x: float, y: float, poly: Sequence[Point]) -> float:
    if not poly:
        return float("inf")
    dmin = float("inf")
    for (ax, ay), (bx, by) in zip(poly, list(poly[1:]) + [poly[0]]):
        dmin = min(dmin, dist_to_segment(x, y, ax, ay, bx, by))
    return dmin


def chi_polygon_obstacle(x: float, y: float, poly: Sequence[Point], interface_width: float) -> float:
    inside = point_in_polygon(x, y, poly)
    d = distance_to_polygon(x, y, poly)
    sd = -d if inside else d
    return chi_from_signed_distance(sd, interface_width)


def generate(args: argparse.Namespace) -> List[float]:
    poly: List[Point] = []
    if args.mode == "naca4_airfoil":
        poly = naca4_polygon(args)
    vals: List[float] = []
    for iy in range(args.Ny):
        y = (iy + 0.5) * args.Ly / args.Ny
        for ix in range(args.Nx):
            x = (ix + 0.5) * args.Lx / args.Nx
            if args.mode in ("circle_obstacle", "channel_cylinder"):
                chi = chi_circle_obstacle(x, y, args)
            elif args.mode == "channel_ellipse":
                chi = chi_ellipse_obstacle(x, y, args)
            elif args.mode == "bend_pipe":
                chi = chi_bend_pipe(x, y, args)
            elif args.mode == "diagonal_channel":
                chi = chi_diagonal_channel(x, y, args)
            elif args.mode == "naca4_airfoil":
                chi = chi_polygon_obstacle(x, y, poly, args.interface_width)
            elif args.mode == "uniform":
                chi = args.uniform_chi
            else:
                raise ValueError(f"unsupported mode: {args.mode}")
            vals.append(clamp01(float(chi)))
    return vals


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=[
        "circle_obstacle", "channel_cylinder", "channel_ellipse",
        "bend_pipe", "diagonal_channel", "naca4_airfoil", "uniform"
    ], default="circle_obstacle")
    ap.add_argument("--out", required=True)
    ap.add_argument("--Nx", type=int, required=True)
    ap.add_argument("--Ny", type=int, required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--format", choices=["float32"], default="float32")
    ap.add_argument("--cx", type=float, default=0.45)
    ap.add_argument("--cy", type=float, default=0.20)
    ap.add_argument("--radius", type=float, default=0.055)
    ap.add_argument("--ellipse-a", type=float, default=0.10)
    ap.add_argument("--ellipse-b", type=float, default=0.035)
    ap.add_argument("--angle-deg", type=float, default=0.0)
    ap.add_argument("--interface-width", type=float, default=0.01)
    ap.add_argument("--uniform-chi", type=float, default=1.0)
    ap.add_argument("--pipe-width", type=float, default=0.10)
    ap.add_argument("--bend-radius", type=float, default=0.18)
    ap.add_argument("--inlet-y", type=float, default=0.78)
    ap.add_argument("--outlet-x", type=float, default=0.82)
    ap.add_argument("--naca", default="0012")
    ap.add_argument("--chord", type=float, default=0.20)
    ap.add_argument("--airfoil-cx", type=float, default=0.55)
    ap.add_argument("--airfoil-cy", type=float, default=0.20)
    ap.add_argument("--aoa-deg", type=float, default=0.0)
    ap.add_argument("--naca-points", type=int, default=121)
    args = ap.parse_args()
    if args.Nx <= 0 or args.Ny <= 0 or args.Lx <= 0.0 or args.Ly <= 0.0:
        raise SystemExit("Nx, Ny, Lx and Ly must be positive")
    if args.chord <= 0.0:
        raise SystemExit("chord must be positive")
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

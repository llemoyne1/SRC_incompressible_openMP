#!/usr/bin/env python3
"""Autonomous initial-state and chi-field generator for SRC/MPCD 0434 run scripts.

State format follows the .smpcd binary layout used by the 0315/0425 scripts:
  magic[16], header <IIIIQIIII>, reserved <8Q>, arrays x,y,vx,vy,type,mass,role.
Roles: inactive=0, fluid=1.  The generated chi convention is chi=1 in fluid,
chi=0 in solid/penalized regions.
"""
from __future__ import annotations

import argparse
import math
import os
import random
import struct
from typing import Callable, Tuple


def fbool(s: str) -> bool:
    return str(s).lower() in {"1", "true", "yes", "on", "enable", "enabled"}


def naca4_thickness(x: float, t: float) -> float:
    # Closed trailing edge NACA 4-digit thickness law, x in [0,1].
    x = max(0.0, min(1.0, x))
    return 5.0 * t * (
        0.2969 * math.sqrt(max(x, 0.0))
        - 0.1260 * x
        - 0.3516 * x * x
        + 0.2843 * x ** 3
        - 0.1015 * x ** 4
    )


def make_solid_pred(args: argparse.Namespace) -> Callable[[float, float], bool]:
    kind = args.case
    Lx, Ly = args.Lx, args.Ly

    if kind in {"uniform", "poiseuille", "io_box", "injection"}:
        return lambda x, y: False

    if kind == "tg":
        # TG hole is represented by inactive particles, not by removing cells.
        # This matches the 0315/0337 portable TG-hole scripts and keeps the
        # periodic topology free of an implicit solid/chi geometry.
        return lambda x, y: False

    if kind == "step":
        return lambda x, y: (args.step_xmin <= x <= args.step_xmax and args.step_ymin <= y <= args.step_ymax)

    if kind == "vk":
        return lambda x, y: ((x - args.cylinder_cx) ** 2 + (y - args.cylinder_cy) ** 2) <= args.cylinder_r ** 2

    if kind == "bend_pipe":
        # L-shaped pipe: left/top segment -> vertical bend -> right/bottom segment.
        # Fluid region is a thickened centerline polyline; everything else is solid.
        w = max(args.bend_width, min(Lx, Ly) / max(args.Nx, args.Ny))
        r = 0.5 * w
        xmid = args.bend_xmid
        ytop = args.bend_y_top
        ybot = args.bend_y_bottom
        def dist_seg(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
            vx, vy = bx - ax, by - ay
            wx, wy = px - ax, py - ay
            vv = vx * vx + vy * vy
            if vv <= 0.0:
                return math.hypot(px - ax, py - ay)
            t = max(0.0, min(1.0, (wx * vx + wy * vy) / vv))
            qx, qy = ax + t * vx, ay + t * vy
            return math.hypot(px - qx, py - qy)
        def in_pipe(x: float, y: float) -> bool:
            return (
                dist_seg(x, y, 0.0, ytop, xmid, ytop) <= r or
                dist_seg(x, y, xmid, ytop, xmid, ybot) <= r or
                dist_seg(x, y, xmid, ybot, Lx, ybot) <= r
            )
        return lambda x, y: not in_pipe(x, y)

    if kind == "naca":
        alpha = math.radians(args.naca_alpha_deg)
        ca, sa = math.cos(alpha), math.sin(alpha)
        c = args.naca_chord
        xc, yc = args.naca_cx, args.naca_cy
        t = args.naca_thickness
        def inside(x: float, y: float) -> bool:
            # Rotate world point into airfoil coordinates.
            dx, dy = x - xc, y - yc
            xr = ( ca * dx + sa * dy) / c + 0.5
            yr = (-sa * dx + ca * dy) / c
            if xr < 0.0 or xr > 1.0:
                return False
            return abs(yr) <= naca4_thickness(xr, t)
        return inside

    raise ValueError(f"Unsupported case: {kind}")



def make_inactive_pred(args: argparse.Namespace) -> Callable[[float, float], bool]:
    if args.case == "tg" and args.tg_hole_enable:
        return lambda x, y: (args.hole_xmin <= x <= args.hole_xmax and args.hole_ymin <= y <= args.hole_ymax)
    return lambda x, y: False


def velocity(args: argparse.Namespace, rng: random.Random, x: float, y: float) -> Tuple[float, float]:
    sigma = math.sqrt(args.kBT / args.mass) if args.kBT > 0.0 and args.mass > 0.0 else 0.0
    noise_x = sigma * rng.gauss(0.0, 1.0) if sigma > 0.0 else 0.0
    noise_y = sigma * rng.gauss(0.0, 1.0) if sigma > 0.0 else 0.0
    if args.velocity_mode == "zero":
        ux, uy = 0.0, 0.0
    elif args.velocity_mode == "uniform_x":
        ux, uy = args.u0, 0.0
    elif args.velocity_mode == "uniform_y":
        ux, uy = 0.0, args.u0
    elif args.velocity_mode == "poiseuille_x":
        yy = y / args.Ly if args.Ly > 0 else 0.0
        ux, uy = args.u0 * 4.0 * yy * (1.0 - yy), 0.0
    elif args.velocity_mode == "taylor_green":
        ux = args.u0 * math.sin(2.0 * math.pi * x / args.Lx) * math.cos(2.0 * math.pi * y / args.Ly)
        uy = -args.u0 * math.cos(2.0 * math.pi * x / args.Lx) * math.sin(2.0 * math.pi * y / args.Ly)
    else:
        raise ValueError(f"Unsupported velocity mode: {args.velocity_mode}")
    return ux + noise_x, uy + noise_y


def generate(args: argparse.Namespace) -> None:
    rng = random.Random(args.seed)
    solid = make_solid_pred(args)
    inactive_pred = make_inactive_pred(args)
    dx, dy = args.Lx / args.Nx, args.Ly / args.Ny

    chi = []
    solid_cells = 0
    if args.chi:
        for j in range(args.Ny):
            yc = (j + 0.5) * dy
            for i in range(args.Nx):
                xc = (i + 0.5) * dx
                is_solid = solid(xc, yc)
                chi.append(0.0 if is_solid else 1.0)
                solid_cells += 1 if is_solid else 0
        os.makedirs(os.path.dirname(args.chi) or ".", exist_ok=True)
        with open(args.chi, "wb") as f:
            f.write(struct.pack(f"<{len(chi)}f", *chi))

    x = []
    y = []
    vx = []
    vy = []
    typ = []
    mass = []
    role = []
    active_cells = 0
    skipped_cells = 0
    rejected = 0

    for j in range(args.Ny):
        for i in range(args.Nx):
            x0, y0 = i * dx, j * dy
            xc, yc = (i + 0.5) * dx, (j + 0.5) * dy
            if args.skip_solid_cells and solid(xc, yc):
                skipped_cells += 1
                continue
            active_cells += 1
            for _ in range(args.gamma):
                xp = yp = None
                for _try in range(1000):
                    cand_x = x0 + dx * rng.random()
                    cand_y = y0 + dy * rng.random()
                    if args.skip_solid_particles and solid(cand_x, cand_y):
                        rejected += 1
                        continue
                    xp, yp = cand_x, cand_y
                    break
                if xp is None:
                    continue
                u, v = velocity(args, rng, xp, yp)
                particle_role = 0 if inactive_pred(xp, yp) else 1
                x.append(xp); y.append(yp); vx.append(u); vy.append(v)
                typ.append(args.background_type); mass.append(args.mass); role.append(particle_role)

    # Remove global thermal/drift noise bias while preserving requested mean for simple modes.
    fluid_mass = sum(m for m, r in zip(mass, role) if r == 1)
    if fluid_mass > 0 and args.remove_mean_drift:
        mvx = sum(m * u for m, u, r in zip(mass, vx, role) if r == 1) / fluid_mass
        mvy = sum(m * v for m, v, r in zip(mass, vy, role) if r == 1) / fluid_mass
        target_x = args.u0 if args.velocity_mode in {"uniform_x", "poiseuille_x"} else 0.0
        target_y = args.u0 if args.velocity_mode == "uniform_y" else 0.0
        for k, r in enumerate(role):
            if r == 1:
                vx[k] = vx[k] - mvx + target_x
                vy[k] = vy[k] - mvy + target_y

    for _ in range(max(0, args.inactive_slots)):
        x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
        typ.append(args.inactive_type); mass.append(args.mass); role.append(0)

    os.makedirs(os.path.dirname(args.state) or ".", exist_ok=True)
    magic = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    n = len(x)
    with open(args.state, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        f.write(struct.pack("<8Q", *reserved))
        for arr, fmt in [(x, "d"), (y, "d"), (vx, "d"), (vy, "d"), (typ, "I"), (mass, "d"), (role, "B")]:
            f.write(struct.pack(f"<{n}{fmt}", *arr))

    print(
        f"[0434-generate] case={args.case} state={args.state} chi={args.chi or 'none'} "
        f"grid={args.Nx}x{args.Ny} gamma={args.gamma} activeCells={active_cells} "
        f"skippedCells={skipped_cells} fluid={sum(1 for r in role if r == 1)} "
        f"inactive={sum(1 for r in role if r == 0)} holeInactive={sum(1 for xx, yy, rr in zip(x, y, role) if rr == 0 and inactive_pred(xx, yy))} rejected={rejected} solidCells={solid_cells}"
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", required=True, choices=["uniform", "tg", "poiseuille", "step", "io_box", "bend_pipe", "vk", "injection", "naca"])
    ap.add_argument("--state", required=True)
    ap.add_argument("--chi", default="")
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--Nx", type=int, required=True)
    ap.add_argument("--Ny", type=int, required=True)
    ap.add_argument("--gamma", type=int, required=True)
    ap.add_argument("--kBT", type=float, default=0.05)
    ap.add_argument("--mass", type=float, default=1.0)
    ap.add_argument("--seed", type=int, default=1628304)
    ap.add_argument("--u0", type=float, default=0.0)
    ap.add_argument("--velocity-mode", default="zero", choices=["zero", "uniform_x", "uniform_y", "poiseuille_x", "taylor_green"])
    ap.add_argument("--background-type", type=int, default=0)
    ap.add_argument("--inactive-type", type=int, default=0)
    ap.add_argument("--inactive-slots", type=int, default=0)
    ap.add_argument("--skip-solid-cells", default="true")
    ap.add_argument("--skip-solid-particles", default="true")
    ap.add_argument("--remove-mean-drift", default="true")

    ap.add_argument("--tg-hole-enable", default="true")
    ap.add_argument("--hole-xmin", type=float, default=0.45)
    ap.add_argument("--hole-xmax", type=float, default=0.55)
    ap.add_argument("--hole-ymin", type=float, default=0.45)
    ap.add_argument("--hole-ymax", type=float, default=0.55)

    ap.add_argument("--step-xmin", type=float, default=0.0)
    ap.add_argument("--step-xmax", type=float, default=1.0)
    ap.add_argument("--step-ymin", type=float, default=0.0)
    ap.add_argument("--step-ymax", type=float, default=0.52)

    ap.add_argument("--cylinder-cx", type=float, default=1.0)
    ap.add_argument("--cylinder-cy", type=float, default=0.5)
    ap.add_argument("--cylinder-r", type=float, default=0.08)

    ap.add_argument("--bend-width", type=float, default=0.25)
    ap.add_argument("--bend-xmid", type=float, default=0.5)
    ap.add_argument("--bend-y-top", type=float, default=0.875)
    ap.add_argument("--bend-y-bottom", type=float, default=0.125)

    ap.add_argument("--naca-chord", type=float, default=0.55)
    ap.add_argument("--naca-cx", type=float, default=0.5)
    ap.add_argument("--naca-cy", type=float, default=0.5)
    ap.add_argument("--naca-alpha-deg", type=float, default=5.0)
    ap.add_argument("--naca-thickness", type=float, default=0.12)

    args = ap.parse_args()
    args.skip_solid_cells = fbool(args.skip_solid_cells)
    args.skip_solid_particles = fbool(args.skip_solid_particles)
    args.remove_mean_drift = fbool(args.remove_mean_drift)
    args.tg_hole_enable = fbool(args.tg_hole_enable)
    generate(args)


if __name__ == "__main__":
    main()

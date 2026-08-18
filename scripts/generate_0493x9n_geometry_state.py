#!/usr/bin/env python3
"""Generate deterministic two-species geometries for 0493x9n qualification.

The physical wall is y=0 and the computational domain is y>=0.  Liquid A is
inside the requested shape.  The interface normal convention is A -> B, and
contact angle theta is measured through A, so at the bottom wall

    n_AB . n_wall = -cos(theta),   n_wall=(0,-1).

Shapes:
  plane-wedge : two locally straight contact branches, capped away from wall;
  circle      : sessile circular cap (same geometry as x9i/x9m);
  ellipse     : axis-aligned sessile ellipse with analytically prescribed
                contact angle and local contact curvature.
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
ANCHOR_LAYER = 4


def pos_int(s):
    v = int(s)
    if v <= 0:
        raise argparse.ArgumentTypeError("expected positive integer")
    return v


def pos_float(s):
    v = float(s)
    if not math.isfinite(v) or v <= 0.0:
        raise argparse.ArgumentTypeError("expected finite positive number")
    return v


def nonneg_float(s):
    v = float(s)
    if not math.isfinite(v) or v < 0.0:
        raise argparse.ArgumentTypeError("expected finite non-negative number")
    return v


def coprime_multiplier(modulus, start, avoid=-1):
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1


def paired_velocities(rng, count, mass, kbt):
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
    s2 = sum(x * x + y * y for x, y in vals)
    scale = math.sqrt((2.0 * count * kbt) / (mass * s2)) if s2 > 0.0 else 0.0
    return [(scale * x, scale * y) for x, y in vals]


def write_state(path, x, y, vx, vy, typ, mass, role):
    n = len(x)
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


def ellipse_geometry(a, b, theta):
    """Return cy, contact half-width, local kappa, parameter t0.

    For x=a cos(t), y=cy+b sin(t), the right contact outward normal is
    (sin(theta), cos(theta)).
    """
    st, ct = math.sin(theta), math.cos(theta)
    den = math.sqrt(a * a * st * st + b * b * ct * ct)
    cos_t = a * st / den
    sin_t = b * ct / den
    t0 = math.atan2(sin_t, cos_t)
    cy = -b * sin_t
    half_width = a * cos_t
    curvature = a * b / (a * a * sin_t * sin_t + b * b * cos_t * cos_t) ** 1.5
    return cy, half_width, curvature, t0


def ellipse_secant_curvature(a, b, cy, t0, anchor_y):
    """Ideal x9m finite-chord estimator on an exact ellipse at right contact."""
    s1 = (anchor_y - cy) / b
    if not (-1.0 <= s1 <= 1.0):
        return None
    t1 = math.asin(max(-1.0, min(1.0, s1)))
    # Contact branch used by all x9n cases has cos(t)>0.
    if math.cos(t1) < 0.0:
        t1 = math.pi - t1

    def unit_normal(t):
        vx = math.cos(t) / a
        vy = math.sin(t) / b
        g = math.hypot(vx, vy)
        return vx / g, vy / g

    n0 = unit_normal(t0)
    n1 = unit_normal(t1)
    dot = max(-1.0, min(1.0, n0[0] * n1[0] + n0[1] * n1[1]))
    cross = n0[0] * n1[1] - n0[1] * n1[0]
    delta = math.atan2(cross, dot)
    x0 = a * math.cos(t0)
    x1 = a * math.cos(t1)
    chord = math.hypot(x1 - x0, anchor_y)
    if chord <= 0.0:
        return None
    return abs(2.0 * math.sin(0.5 * delta) / chord)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--shape", choices=("plane-wedge", "circle", "ellipse"), required=True)
    ap.add_argument("--case-id", default="")
    ap.add_argument("--Lx", type=pos_float, default=1.6)
    ap.add_argument("--Ly", type=pos_float, default=1.0)
    ap.add_argument("--nx", type=pos_int, default=320)
    ap.add_argument("--ny", type=pos_int, default=200)
    ap.add_argument("--gamma", type=pos_int, default=20)
    ap.add_argument("--center-x", type=float, default=None)
    ap.add_argument("--contact-angle-deg", type=float, required=True)
    ap.add_argument("--radius", type=pos_float)
    ap.add_argument("--semi-axis-x", type=pos_float)
    ap.add_argument("--semi-axis-y", type=pos_float)
    ap.add_argument("--plane-half-width", type=pos_float)
    ap.add_argument("--plane-height", type=pos_float)
    ap.add_argument("--liquid-type", type=pos_int, default=1)
    ap.add_argument("--gas-type", type=pos_int, default=2)
    ap.add_argument("--liquid-mass", type=pos_float, default=1.0)
    ap.add_argument("--gas-mass", type=pos_float, default=1.0)
    ap.add_argument("--kBT", type=nonneg_float, default=0.125)
    ap.add_argument("--seed", type=int, default=493940)
    args = ap.parse_args()

    if args.gamma < 2:
        ap.error("gamma must be >=2")
    if args.liquid_type == args.gas_type:
        ap.error("liquid and gas types must differ")
    theta_deg = float(args.contact_angle_deg)
    if not math.isfinite(theta_deg) or not (0.0 < theta_deg < 180.0):
        ap.error("contact angle must satisfy 0 < theta < 180")
    theta = math.radians(theta_deg)
    cx = args.Lx * 0.5 if args.center_x is None else float(args.center_x)
    dx, dy = args.Lx / args.nx, args.Ly / args.ny
    if abs(dx - dy) > 1e-12 * max(1.0, abs(dx), abs(dy)):
        ap.error("square cells required")
    h = dx
    anchor_y = (ANCHOR_LAYER + 0.5) * h

    meta = {
        "profile": "geometry_qualification_0493x9n",
        "shape": args.shape,
        "caseId": args.case_id,
        "Lx": args.Lx,
        "Ly": args.Ly,
        "nx": args.nx,
        "ny": args.ny,
        "dx": dx,
        "dy": dy,
        "gamma": args.gamma,
        "centerX": cx,
        "contactAngleDegrees": theta_deg,
        "anchorLayer": ANCHOR_LAYER,
        "anchorCenterY": anchor_y,
    }

    if args.shape == "circle":
        if args.radius is None:
            ap.error("--radius is required for circle")
        r = args.radius
        cy = -r * math.cos(theta)
        half_width = r * math.sin(theta)
        top = cy + r
        if cx - half_width <= 0.0 or cx + half_width >= args.Lx:
            ap.error("circle contact points must remain away from side walls")
        if top >= args.Ly:
            ap.error("circle cap must remain below top wall")

        def inside(px, py):
            return (px - cx) ** 2 + (py - cy) ** 2 <= r * r

        exact_kappa = 1.0 / r
        exact_secant = exact_kappa
        meta.update({
            "centerY": cy,
            "radius": r,
            "contactHalfWidth": half_width,
            "capHeight": top,
            "exactContactCurvature": exact_kappa,
            "exactSecantCurvatureAnchor4p5h": exact_secant,
        })

    elif args.shape == "ellipse":
        if args.semi_axis_x is None or args.semi_axis_y is None:
            ap.error("--semi-axis-x and --semi-axis-y are required for ellipse")
        a, b = args.semi_axis_x, args.semi_axis_y
        cy, half_width, exact_kappa, t0 = ellipse_geometry(a, b, theta)
        top = cy + b
        if cx - half_width <= 0.0 or cx + half_width >= args.Lx:
            ap.error("ellipse contact points must remain away from side walls")
        if top >= args.Ly:
            ap.error("ellipse cap must remain below top wall")
        if top <= anchor_y + 5.0 * h:
            ap.error("ellipse is too shallow for the clean-anchor qualification")

        def inside(px, py):
            return ((px - cx) / a) ** 2 + ((py - cy) / b) ** 2 <= 1.0

        exact_secant = ellipse_secant_curvature(a, b, cy, t0, anchor_y)
        if exact_secant is None:
            ap.error("ellipse does not reach the x9m anchor layer")
        meta.update({
            "centerY": cy,
            "semiAxisX": a,
            "semiAxisY": b,
            "contactHalfWidth": half_width,
            "capHeight": top,
            "contactParameterT": t0,
            "exactContactCurvature": exact_kappa,
            "exactSecantCurvatureAnchor4p5h": exact_secant,
            "idealSecantRelativeBias": (exact_secant - exact_kappa) / exact_kappa,
        })

    else:
        if args.plane_half_width is None or args.plane_height is None:
            ap.error("--plane-half-width and --plane-height are required for plane-wedge")
        w0, height = args.plane_half_width, args.plane_height
        cot = math.cos(theta) / math.sin(theta)
        w_top = w0 - cot * height
        w_min = min(w0, w_top)
        w_max = max(w0, w_top)
        if w_min <= 6.0 * h:
            ap.error("plane wedge becomes too narrow before its remote cap")
        if cx - w_max <= 0.0 or cx + w_max >= args.Lx:
            ap.error("plane wedge must remain away from side walls")
        if height >= args.Ly:
            ap.error("plane wedge remote cap must remain below top wall")
        if height <= anchor_y + 5.0 * h:
            ap.error("plane wedge height is too small for anchor isolation")

        def inside(px, py):
            if py > height:
                return False
            width = w0 - cot * py
            return width > 0.0 and abs(px - cx) <= width

        exact_kappa = 0.0
        exact_secant = 0.0
        meta.update({
            "planeHalfWidthAtWall": w0,
            "planeHeight": height,
            "planeHalfWidthAtCap": w_top,
            "exactContactCurvature": exact_kappa,
            "exactSecantCurvatureAnchor4p5h": exact_secant,
        })

    ax = coprime_multiplier(args.gamma, 3)
    ay = coprime_multiplier(args.gamma, 7, avoid=ax)
    rng = random.Random(args.seed)
    x = array("d")
    y = array("d")
    vx = array("d")
    vy = array("d")
    typ = array("I")
    mass = array("d")
    role = bytearray()
    nl_tot = ng_tot = mixed = 0

    for iy in range(args.ny):
        for ix in range(args.nx):
            positions = []
            types = []
            for k in range(args.gamma):
                fx = ((ax * k) % args.gamma + 0.5) / args.gamma
                fy = ((ay * k) % args.gamma + 0.5) / args.gamma
                px, py = (ix + fx) * dx, (iy + fy) * dy
                is_liquid = inside(px, py)
                positions.append((px, py))
                types.append(args.liquid_type if is_liquid else args.gas_type)
            nl = sum(t == args.liquid_type for t in types)
            ng = args.gamma - nl
            mixed += int(nl > 0 and ng > 0)
            nl_tot += nl
            ng_tot += ng
            vl = paired_velocities(rng, nl, args.liquid_mass, args.kBT)
            vg = paired_velocities(rng, ng, args.gas_mass, args.kBT)
            il = ig = 0
            for (px, py), t in zip(positions, types):
                if t == args.liquid_type:
                    ux, uy = vl[il]
                    il += 1
                    m = args.liquid_mass
                else:
                    ux, uy = vg[ig]
                    ig += 1
                    m = args.gas_mass
                x.append(px)
                y.append(py)
                vx.append(ux)
                vy.append(uy)
                typ.append(t)
                mass.append(m)
                role.append(1)

    write_state(args.output, x, y, vx, vy, typ, mass, role)
    meta.update({
        "liquidType": args.liquid_type,
        "gasType": args.gas_type,
        "liquidMass": args.liquid_mass,
        "gasMass": args.gas_mass,
        "kBT": args.kBT,
        "seed": args.seed,
        "particles": len(x),
        "liquidParticles": nl_tot,
        "gasParticles": ng_tot,
        "mixedCells": mixed,
        "liquidFractionParticles": nl_tot / max(1, len(x)),
    })
    mp = args.output.with_suffix(args.output.suffix + ".json")
    mp.write_text(json.dumps(meta, indent=2) + "\n")
    print(
        f"[0493x9n-generate] shape={args.shape} grid={args.nx}x{args.ny} gamma={args.gamma} "
        f"N={len(x)} theta={theta_deg:g} exactKappa={meta['exactContactCurvature']:.12g} "
        f"idealSecant={meta['exactSecantCurvatureAnchor4p5h']:.12g} mixedCells={mixed}"
    )
    print(f"[0493x9n-generate] state={args.output}")
    print(f"[0493x9n-generate] metadata={mp}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

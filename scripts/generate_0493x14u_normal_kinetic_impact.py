#!/usr/bin/env python3
"""Generate mirror-paired planar G|L|G states for x14u.

Purpose
-------
Isolate the *normal kinetic momentum-flux* channel at a liquid/gas interface.

All native cells have the same occupancy, mass and thermodynamic kBT as the
qualified x14t balanced case.  Therefore x6g has zero initial thermodynamic
pressure jump.  A finite gas band adjacent to one interface receives a mean
normal drift toward the liquid.

Cases:
  static         : no gas drift
  bottom_impact  : bottom gas band gets +U_y
  top_impact     : top gas band gets -U_y (mirror of bottom_impact)

The bottom/top initial particle fields are mirror-paired in y.  Each cell has
exact zero peculiar barycentric velocity and exact requested 2-D kinetic kBT;
adding the band drift changes only the cell mean.

No solver source/runtime diagnostic is modified.
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
FLUID_ROLE = 1

def pos_int(s):
    v = int(s)
    if v <= 0:
        raise argparse.ArgumentTypeError("expected positive integer")
    return v

def pos_float(s):
    v = float(s)
    if not math.isfinite(v) or v <= 0:
        raise argparse.ArgumentTypeError("expected finite positive number")
    return v

def nonneg_float(s):
    v = float(s)
    if not math.isfinite(v) or v < 0:
        raise argparse.ArgumentTypeError("expected finite non-negative number")
    return v

def cell_seed(seed: int, ix: int, canonical_iy: int) -> int:
    # Stable integer mixer, independent of Python's randomized hash.
    z = (seed & 0xFFFFFFFFFFFFFFFF) ^ ((ix + 0x9E3779B9) * 0xBF58476D1CE4E5B9)
    z ^= ((canonical_iy + 0x94D049BB) * 0x94D049BB133111EB)
    z &= 0xFFFFFFFFFFFFFFFF
    z ^= z >> 30
    z = (z * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
    z ^= z >> 27
    z = (z * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
    z ^= z >> 31
    return z & 0xFFFFFFFFFFFFFFFF

def coprime_multiplier(modulus: int, start: int, avoid: int = -1) -> int:
    if modulus <= 1:
        return 1
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1

def peculiar_velocities(rng: random.Random, count: int, mass: float, kbt: float):
    """Zero cell mean, exact sum m|c|^2/(2N)=kBT."""
    if count == 1 or kbt == 0.0:
        return [(0.0, 0.0)] * count
    vals = []
    for _ in range(count // 2):
        gx, gy = rng.gauss(0.0, 1.0), rng.gauss(0.0, 1.0)
        vals.extend(((gx, gy), (-gx, -gy)))
    if count % 2:
        vals.append((0.0, 0.0))
    s2 = sum(u*u + v*v for u, v in vals)
    scale = math.sqrt((2.0 * count * kbt) / (mass * s2))
    return [(scale*u, scale*v) for u, v in vals]

def write_state(path: Path, x, y, vx, vy, typ, mass, role):
    n = len(x)
    if not (len(y) == len(vx) == len(vy) == len(typ) == len(mass) == len(role) == n):
        raise RuntimeError("inconsistent arrays")
    path.parent.mkdir(parents=True, exist_ok=True)
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
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
            for a in (x, y, vx, vy,typ, mass):
                a.byteswap()

def wall_pressure_from_samples(vn, number_density, mass, toward_positive=True):
    """Specular wall pressure 2 n m <v_n^2 1_incoming>."""
    if toward_positive:
        moment = sum(v*v for v in vn if v > 0.0) / len(vn)
    else:
        moment = sum(v*v for v in vn if v < 0.0) / len(vn)
    return 2.0 * number_density * mass * moment

def shifted_maxwell_wall_pressure(number_density, mass, kbt, drift):
    """Incoming pressure for N(U,sigma^2), wall ahead in +normal direction."""
    sigma = math.sqrt(kbt / mass)
    a = drift / sigma
    phi = math.exp(-0.5*a*a) / math.sqrt(2.0*math.pi)
    Phi = 0.5 * (1.0 + math.erf(a / math.sqrt(2.0)))
    return 2.0 * number_density * mass * (
        (drift*drift + sigma*sigma) * Phi + drift*sigma*phi
    )

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--case", choices=("static", "bottom_impact", "top_impact"), required=True)
    ap.add_argument("--Lx", type=pos_float, default=1.5625)
    ap.add_argument("--Ly", type=pos_float, default=1.0)
    ap.add_argument("--nx", type=pos_int, default=400)
    ap.add_argument("--ny", type=pos_int, default=256)
    ap.add_argument("--occupancy", type=pos_int, default=20)
    ap.add_argument("--slab-width-cells", type=pos_int, default=80)
    ap.add_argument("--slab-center-cell", type=float, default=128.0)
    ap.add_argument("--impact-band-cells", type=pos_int, default=24)
    ap.add_argument("--impact-speed", type=pos_float, default=0.1)
    ap.add_argument("--liquid-type", type=pos_int, default=1)
    ap.add_argument("--gas-type", type=pos_int, default=2)
    ap.add_argument("--liquid-mass", type=pos_float, default=1.0)
    ap.add_argument("--gas-mass", type=pos_float, default=0.1)
    ap.add_argument("--liquid-kBT", type=nonneg_float, default=0.02)
    ap.add_argument("--gas-kBT", type=nonneg_float, default=0.08)
    ap.add_argument("--seed", type=int, default=493150)
    args = ap.parse_args()

    if args.liquid_type == args.gas_type:
        ap.error("liquid and gas types must differ")
    dx, dy = args.Lx/args.nx, args.Ly/args.ny
    if abs(dx-dy) > 1e-12 * max(1.0, abs(dx), abs(dy)):
        ap.error("square cells required")

    s0 = args.slab_center_cell - args.slab_width_cells/2
    s1 = args.slab_center_cell + args.slab_width_cells/2
    if abs(s0-round(s0)) > 1e-12 or abs(s1-round(s1)) > 1e-12:
        ap.error("slab interfaces must be native-cell aligned")
    j0, j1 = int(round(s0)), int(round(s1))
    if not (0 < j0 < j1 < args.ny):
        ap.error("invalid slab")
    if j0 != args.ny-j1:
        ap.error("benchmark requires equal gas compartments")
    if args.impact_band_cells >= j0:
        ap.error("impact band must fit inside each gas compartment")

    b0, b1 = j0-args.impact_band_cells, j0
    t0, t1 = j1, j1+args.impact_band_cells

    x = array("d"); y = array("d"); vx = array("d"); vy = array("d")
    typ = array("I"); mass = array("d"); role = bytearray()

    # Samples from the impacted bottom-oriented band, before/after drift.
    band_pec_vy = []
    band_drift_vy = []
    n_liquid = n_gas = 0

    ax = coprime_multiplier(args.occupancy, 3)
    ay = coprime_multiplier(args.occupancy, 7, avoid=ax)

    for iy in range(args.ny):
        mirror = args.ny - 1 - iy
        canonical_iy = min(iy, mirror)
        mirrored = iy > mirror
        for ix in range(args.nx):
            rng = random.Random(cell_seed(args.seed, ix, canonical_iy))
            vv = peculiar_velocities(rng, args.occupancy,
                                     args.liquid_mass if j0 <= iy < j1 else args.gas_mass,
                                     args.liquid_kBT if j0 <= iy < j1 else args.gas_kBT)
            ptype = args.liquid_type if j0 <= iy < j1 else args.gas_type
            pmass = args.liquid_mass if ptype == args.liquid_type else args.gas_mass

            drift = 0.0
            if args.case == "bottom_impact" and b0 <= iy < b1:
                drift = +args.impact_speed
            elif args.case == "top_impact" and t0 <= iy < t1:
                drift = -args.impact_speed

            for k, (ux0, uy0) in enumerate(vv):
                fx = ((ax*k) % args.occupancy + 0.5) / args.occupancy
                fy0 = ((ay*k) % args.occupancy + 0.5) / args.occupancy
                if mirrored:
                    # Mirror the canonical-row microstate across the domain midplane.
                    ux, uy = ux0, -uy0
                    fy = 1.0 - fy0
                else:
                    ux, uy = ux0, uy0
                    fy = fy0
                uy_final = uy + drift

                x.append((ix + fx)*dx)
                y.append((iy + fy)*dy)
                vx.append(ux)
                vy.append(uy_final)
                typ.append(ptype)
                mass.append(pmass)
                role.append(FLUID_ROLE)

                if ptype == args.liquid_type:
                    n_liquid += 1
                else:
                    n_gas += 1

                # Canonical bottom impact-band samples for a direct kinetic-theory
                # target.  The top case is its exact mirror.
                if b0 <= iy < b1:
                    band_pec_vy.append(uy)
                    band_drift_vy.append(uy + args.impact_speed)

    write_state(args.output, x, y, vx, vy, typ, mass, role)

    A = dx*dy
    number_density = args.occupancy/A
    rho_liquid = args.occupancy*args.liquid_mass/A
    slab_width = args.slab_width_cells*dy
    p_thermo = args.occupancy*args.gas_kBT/A

    p0_emp = wall_pressure_from_samples(
        band_pec_vy, number_density, args.gas_mass, toward_positive=True)
    pU_emp = wall_pressure_from_samples(
        band_drift_vy, number_density, args.gas_mass, toward_positive=True)
    dp_emp = pU_emp-p0_emp
    a_emp = dp_emp/(rho_liquid*slab_width)

    pU_max = shifted_maxwell_wall_pressure(
        number_density, args.gas_mass, args.gas_kBT, args.impact_speed)
    dp_max = pU_max-p_thermo
    a_max = dp_max/(rho_liquid*slab_width)

    initial_px_liquid = initial_py_liquid = 0.0
    initial_px_gas = initial_py_gas = 0.0
    for ti, mi, uxi, uyi in zip(typ, mass, vx, vy):
        if ti == args.liquid_type:
            initial_px_liquid += mi*uxi
            initial_py_liquid += mi*uyi
        else:
            initial_px_gas += mi*uxi
            initial_py_gas += mi*uyi

    meta = {
        "profile": "0493x14u_normal_kinetic_impact",
        "case": args.case,
        "orientation": "horizontal_slab_motion_y",
        "Lx": args.Lx, "Ly": args.Ly, "nx": args.nx, "ny": args.ny,
        "h": dy, "cellArea": A,
        "occupancy": args.occupancy,
        "slabStartCellY": j0, "slabEndCellY": j1,
        "slabWidthCells": args.slab_width_cells, "slabWidth": slab_width,
        "impactBandBottomStartCellY": b0, "impactBandBottomEndCellY": b1,
        "impactBandTopStartCellY": t0, "impactBandTopEndCellY": t1,
        "impactBandCells": args.impact_band_cells,
        "impactSpeed": args.impact_speed,
        "liquidType": args.liquid_type, "gasType": args.gas_type,
        "liquidMass": args.liquid_mass, "gasMass": args.gas_mass,
        "liquidKBT": args.liquid_kBT, "gasKBT": args.gas_kBT,
        "thermodynamicGasPressure": p_thermo,
        "rhoLiquid": rho_liquid,
        "empiricalStaticSpecularPressure": p0_emp,
        "empiricalDriftSpecularPressure": pU_emp,
        "empiricalKineticPressureExcess": dp_emp,
        "empiricalInitialAccelerationTheory": a_emp,
        "maxwellDriftSpecularPressure": pU_max,
        "maxwellKineticPressureExcess": dp_max,
        "maxwellInitialAccelerationTheory": a_max,
        "initialLiquidPx": initial_px_liquid,
        "initialLiquidPy": initial_py_liquid,
        "initialGasPx": initial_px_gas,
        "initialGasPy": initial_py_gas,
        "liquidParticles": n_liquid,
        "gasParticles": n_gas,
        "particles": len(x),
        "seed": args.seed,
    }
    mp = args.output.with_suffix(args.output.suffix+".json")
    mp.write_text(json.dumps(meta, indent=2)+"\n")

    print(f"[0493x14u-generate] case={args.case} grid={args.nx}x{args.ny} h={dy:.12g}")
    print(f"[0493x14u-generate] slabY=[{j0},{j1}) impactBands=[{b0},{b1})/[{t0},{t1}) U={args.impact_speed}")
    print(f"[0493x14u-generate] pThermo={p_thermo:.12g} dPkinEmp={dp_emp:.12g} aKinEmp={a_emp:.12g}")
    print(f"[0493x14u-generate] dPkinMaxwell={dp_max:.12g} aKinMaxwell={a_max:.12g}")
    print(f"[0493x14u-generate] P0 liquid=({initial_px_liquid:.6g},{initial_py_liquid:.6g}) gas=({initial_px_gas:.6g},{initial_py_gas:.6g})")
    print(f"[0493x14u-generate] state={args.output}")
    print(f"[0493x14u-generate] metadata={mp}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

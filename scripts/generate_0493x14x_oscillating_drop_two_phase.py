#!/usr/bin/env python3
"""0493x14x — generate a two-species 2-D modal drop for liquid/gas oscillation.

Interface:
    r(theta) = R * [sqrt(1-eps^2/2) + eps*cos(n*theta + phase)]
so the continuous enclosed area is exactly pi*R^2.

The full box is populated at exactly gamma particles/cell.  Type 1 occupies the
modal drop, type 2 the exterior gas.  Liquid and gas use independent paired
thermal fluctuations with exactly zero species mean in each cell whenever the
species count is >1.  No runtime/source code is modified by this helper.
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
    ap.add_argument("--Lx", type=pos_float, default=1.5625)
    ap.add_argument("--Ly", type=pos_float, default=1.5625)
    ap.add_argument("--nx", type=pos_int, default=400)
    ap.add_argument("--ny", type=pos_int, default=400)
    ap.add_argument("--gamma", type=pos_int, default=20)
    ap.add_argument("--center-x", type=float, default=None)
    ap.add_argument("--center-y", type=float, default=None)
    ap.add_argument("--radius-cells", type=pos_float, default=40.0)
    ap.add_argument("--mode", type=pos_int, default=2)
    ap.add_argument("--epsilon", type=pos_float, default=0.04)
    ap.add_argument("--phase", type=float, default=0.0)
    ap.add_argument("--liquid-type", type=pos_int, default=1)
    ap.add_argument("--gas-type", type=pos_int, default=2)
    ap.add_argument("--liquid-mass", type=pos_float, default=1.0)
    ap.add_argument("--gas-mass", type=pos_float, default=0.1)
    ap.add_argument("--liquid-kBT", type=nonneg_float, default=0.02)
    ap.add_argument("--gas-kBT", type=nonneg_float, default=0.08)
    ap.add_argument("--seed", type=int, default=493180)
    a = ap.parse_args()

    if a.gamma < 2:
        ap.error("gamma must be >=2")
    if a.liquid_type == a.gas_type:
        ap.error("liquid and gas types must differ")
    if not (0.0 < a.epsilon <= 0.05):
        ap.error("small-amplitude qualification requires 0 < epsilon <= 0.05")
    if a.mode < 2:
        ap.error("mode must be >=2")
    if not math.isfinite(a.phase):
        ap.error("phase must be finite")

    dx, dy = a.Lx/a.nx, a.Ly/a.ny
    if abs(dx-dy) > 1e-12 * max(1.0, abs(dx), abs(dy)):
        ap.error("square cells required")
    h = dx
    cx = 0.5*a.Lx if a.center_x is None else a.center_x
    cy = 0.5*a.Ly if a.center_y is None else a.center_y
    if not all(math.isfinite(v) for v in (cx, cy)):
        ap.error("center must be finite")

    R = a.radius_cells*h
    c0 = math.sqrt(1.0 - 0.5*a.epsilon*a.epsilon)
    rmax = R*(c0 + abs(a.epsilon))
    clearance = min(cx, a.Lx-cx, cy, a.Ly-cy) - rmax
    if clearance <= 8.0*h:
        ap.error(f"drop clearance must exceed 8h, got {clearance/h:.6g}h")

    ax = coprime_multiplier(a.gamma, 3)
    ay = coprime_multiplier(a.gamma, 7, avoid=ax)
    rng_l = random.Random(a.seed ^ 0x14A31)
    rng_g = random.Random(a.seed ^ 0x14A42)

    x=array('d'); y=array('d'); vx=array('d'); vy=array('d')
    typ=array('I'); mass=array('d'); role=bytearray()
    nL=nG=mixed=liquid_cells=gas_cells=0

    for iy in range(a.ny):
        for ix in range(a.nx):
            pos=[]; kinds=[]
            for k in range(a.gamma):
                fx=((ax*k)%a.gamma+0.5)/a.gamma
                fy=((ay*k)%a.gamma+0.5)/a.gamma
                px=(ix+fx)*dx; py=(iy+fy)*dy
                rx=px-cx; ry=py-cy
                rr=math.hypot(rx,ry); th=math.atan2(ry,rx)
                rb=R*(c0 + a.epsilon*math.cos(a.mode*th + a.phase))
                t=a.liquid_type if rr <= rb else a.gas_type
                pos.append((px,py)); kinds.append(t)
            nl=sum(t==a.liquid_type for t in kinds); ng=a.gamma-nl
            nL += nl; nG += ng
            if nl==a.gamma: liquid_cells += 1
            elif ng==a.gamma: gas_cells += 1
            else: mixed += 1
            vl=paired_velocities(rng_l,nl,a.liquid_mass,a.liquid_kBT)
            vg=paired_velocities(rng_g,ng,a.gas_mass,a.gas_kBT)
            il=ig=0
            for (px,py),t in zip(pos,kinds):
                if t==a.liquid_type:
                    ux,uy=vl[il]; il+=1; m=a.liquid_mass
                else:
                    ux,uy=vg[ig]; ig+=1; m=a.gas_mass
                x.append(px); y.append(py); vx.append(ux); vy.append(uy)
                typ.append(t); mass.append(m); role.append(1)

    # Remove roundoff-level global momentum without changing the relative modal IC.
    Pmx=sum(m*u for m,u in zip(mass,vx)); Pmy=sum(m*v for m,v in zip(mass,vy)); M=sum(mass)
    dux=Pmx/M; duy=Pmy/M
    for i in range(len(vx)):
        vx[i] -= dux; vy[i] -= duy

    write_state(a.output,x,y,vx,vy,typ,mass,role)
    target_area=math.pi*R*R
    discrete_area=nL*dx*dy/a.gamma
    reff=math.sqrt(discrete_area/math.pi)
    rhoL=a.gamma*a.liquid_mass/(h*h)
    rhoG=a.gamma*a.gas_mass/(h*h)
    meta={
        "profile":"two_phase_modal_drop_0493x14x",
        "Lx":a.Lx,"Ly":a.Ly,"nx":a.nx,"ny":a.ny,"h":h,"gamma":a.gamma,
        "centerX":cx,"centerY":cy,"radius":R,"radiusCells":a.radius_cells,
        "mode":a.mode,"epsilon":a.epsilon,"phase":a.phase,"areaFactorC0":c0,
        "continuousTargetArea":target_area,"discreteLiquidArea":discrete_area,
        "discreteAreaRelativeError":discrete_area/target_area-1.0,"discreteEffectiveRadius":reff,
        "clearance":clearance,"clearanceCells":clearance/h,
        "liquidType":a.liquid_type,"gasType":a.gas_type,
        "liquidMass":a.liquid_mass,"gasMass":a.gas_mass,
        "liquidKBT":a.liquid_kBT,"gasKBT":a.gas_kBT,
        "rhoLiquidReference":rhoL,"rhoGasReference":rhoG,"rhoGasOverLiquid":rhoG/rhoL,
        "seed":a.seed,"particles":len(x),"liquidParticles":nL,"gasParticles":nG,
        "liquidCells":liquid_cells,"gasCells":gas_cells,"mixedCells":mixed,
        "removedGlobalDriftVx":dux,"removedGlobalDriftVy":duy,
    }
    mp=a.output.with_suffix(a.output.suffix+'.json')
    mp.write_text(json.dumps(meta,indent=2)+'\n')
    print(f"[0493x14x-generate] grid={a.nx}x{a.ny} h={h:.10g} gamma={a.gamma} N={len(x)} R/h={a.radius_cells:g} n={a.mode} eps={a.epsilon:g}")
    print(f"[0493x14x-generate] liquid={nL} gas={nG} mixedCells={mixed} rhoG/rhoL={rhoG/rhoL:.9g}")
    print(f"[0493x14x-generate] targetArea={target_area:.12g} discreteArea={discrete_area:.12g} relErr={discrete_area/target_area-1:+.3e} clearance/h={clearance/h:.6g}")
    print(f"[0493x14x-generate] state={a.output}")
    print(f"[0493x14x-generate] metadata={mp}")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())

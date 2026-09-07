#!/usr/bin/env python3
"""0493x14al — paired historical-x13h Taylor-Culick initial states.

CASE=liquid reproduces the historical x13n liquid state construction.
CASE=liquid_gas uses the *same liquid positions and velocities* and fills the
exterior with gas using an independent RNG stream.  The JSON metadata publishes
an SHA-256 digest of the canonical liquid substate so strict A/B pairing can be
verified before the solver is launched.

Tooling only: no solver/source modification; no pandas dependency.
"""
from __future__ import annotations
import argparse, hashlib, json, math, random, struct, sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def pos_int(s):
    v = int(s)
    if v <= 0:
        raise argparse.ArgumentTypeError("expected positive integer")
    return v


def pos_float(s):
    v = float(s)
    if not math.isfinite(v) or v <= 0:
        raise argparse.ArgumentTypeError("expected positive finite number")
    return v


def nonneg_float(s):
    v = float(s)
    if not math.isfinite(v) or v < 0:
        raise argparse.ArgumentTypeError("expected non-negative finite number")
    return v


def coprime_multiplier(modulus, start, avoid=-1):
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1


def paired_fluctuations(rng, count, mass, kbt):
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
    scale = math.sqrt(2.0 * count * kbt / (mass * s2)) if s2 > 0 else 0.0
    return [(scale*u, scale*v) for u, v in vals]


def inside(px, py, cx, cy, halfL, halfH, rr):
    qx = abs(px-cx) - (halfL-rr)
    qy = abs(py-cy) - (halfH-rr)
    ox, oy = max(qx, 0.0), max(qy, 0.0)
    return math.hypot(ox, oy) + min(max(qx, qy), 0.0) <= rr


def write_state(path, x, y, vx, vy, typ, mass, role):
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


def liquid_digest(records):
    h = hashlib.sha256()
    for iy, ix, q, px, py, ux, uy, typ, mass in records:
        h.update(struct.pack("<iii4dId", iy, ix, q, px, py, ux, uy, typ, mass))
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", choices=("liquid", "liquid_gas"), required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--Lx", type=pos_float, default=3.5)
    ap.add_argument("--Ly", type=pos_float, default=1.0)
    ap.add_argument("--nx", type=pos_int, default=896)
    ap.add_argument("--ny", type=pos_int, default=256)
    ap.add_argument("--gamma", type=pos_int, default=8)
    ap.add_argument("--center-x", type=float, default=1.75)
    ap.add_argument("--center-y", type=float, default=0.5)
    ap.add_argument("--sheet-length-cells", type=pos_float, default=768.0)
    ap.add_argument("--thickness-cells", type=pos_float, default=64.0)
    ap.add_argument("--edge-round-cells", type=pos_float, default=8.0)
    ap.add_argument("--liquid-type", type=pos_int, default=1)
    ap.add_argument("--gas-type", type=pos_int, default=2)
    ap.add_argument("--liquid-mass", type=pos_float, default=1.0)
    ap.add_argument("--gas-mass", type=pos_float, default=0.1)
    ap.add_argument("--liquid-kBT", type=nonneg_float, default=0.125)
    ap.add_argument("--gas-kBT", type=nonneg_float, default=0.08)
    ap.add_argument("--seed", type=int, default=4931501)
    a = ap.parse_args()
    if a.liquid_type == a.gas_type:
        ap.error("liquid and gas types must differ")
    dx, dy = a.Lx/a.nx, a.Ly/a.ny
    if abs(dx-dy) > 1e-12*max(1.0, abs(dx), abs(dy)):
        ap.error("square cells required")
    h = dx
    L = a.sheet_length_cells*h
    H = a.thickness_cells*h
    rr = a.edge_round_cells*h
    halfL, halfH = 0.5*L, 0.5*H
    if not (0 < rr < halfH and rr < halfL):
        ap.error("invalid rounded-sheet geometry")
    xclr = min(a.center_x-halfL, a.Lx-(a.center_x+halfL))
    yclr = min(a.center_y-halfH, a.Ly-(a.center_y+halfH))
    if min(xclr, yclr) <= 16*h:
        ap.error(f"require >16h wall clearance, got x={xclr/h:g}h y={yclr/h:g}h")

    ax = coprime_multiplier(a.gamma, 3)
    ay = coprime_multiplier(a.gamma, 7, avoid=ax)

    # Build the liquid exactly as x13n: same bounding-box traversal, same q
    # pattern, same RNG seed, same per-cell paired thermal fluctuations, same
    # final global mean removal.
    rngL = random.Random(a.seed)
    liquid = {}  # (iy,ix,q) -> [px,py,ux,uy]
    liquid_order = []
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
                px, py = (ix+fx)*dx, (iy+fy)*dy
                if inside(px, py, a.center_x, a.center_y, halfL, halfH, rr):
                    pts.append((q, px, py))
            if not pts:
                continue
            fluc = paired_fluctuations(rngL, len(pts), a.liquid_mass, a.liquid_kBT)
            for (q, px, py), (ux, uy) in zip(pts, fluc):
                key = (iy, ix, q)
                liquid[key] = [px, py, ux, uy]
                liquid_order.append(key)
    if not liquid_order:
        raise RuntimeError("generated liquid sheet is empty")
    mvx = sum(liquid[k][2] for k in liquid_order)/len(liquid_order)
    mvy = sum(liquid[k][3] for k in liquid_order)/len(liquid_order)
    for k in liquid_order:
        liquid[k][2] -= mvx
        liquid[k][3] -= mvy

    # Independent gas field.  No gas random draw can perturb the liquid stream.
    gas = {}
    if a.case == "liquid_gas":
        rngG = random.Random(a.seed ^ 0x14A14A1)
        gas_order = []
        for iy in range(a.ny):
            for ix in range(a.nx):
                pts = []
                for q in range(a.gamma):
                    key = (iy, ix, q)
                    if key in liquid:
                        continue
                    fx = ((ax*q) % a.gamma + 0.5)/a.gamma
                    fy = ((ay*q) % a.gamma + 0.5)/a.gamma
                    pts.append((q, (ix+fx)*dx, (iy+fy)*dy))
                fluc = paired_fluctuations(rngG, len(pts), a.gas_mass, a.gas_kBT)
                for (q, px, py), (ux, uy) in zip(pts, fluc):
                    key = (iy, ix, q)
                    gas[key] = [px, py, ux, uy]
                    gas_order.append(key)
        if gas_order:
            gvx = sum(gas[k][2] for k in gas_order)/len(gas_order)
            gvy = sum(gas[k][3] for k in gas_order)/len(gas_order)
            for k in gas_order:
                gas[k][2] -= gvx
                gas[k][3] -= gvy

    x = array("d"); y = array("d"); vx = array("d"); vy = array("d")
    typ = array("I"); mass = array("d"); role = bytearray()
    liquid_records = []
    nG = 0
    if a.case == "liquid":
        # Preserve historical x13n particle order exactly.
        keys = liquid_order
    else:
        keys = [(iy, ix, q) for iy in range(a.ny) for ix in range(a.nx) for q in range(a.gamma)]
    for key in keys:
        if key in liquid:
            px, py, ux, uy = liquid[key]
            t, m = a.liquid_type, a.liquid_mass
            iy, ix, q = key
            liquid_records.append((iy, ix, q, px, py, ux, uy, t, m))
        elif a.case == "liquid_gas":
            px, py, ux, uy = gas[key]
            t, m = a.gas_type, a.gas_mass
            nG += 1
        else:
            continue
        x.append(px); y.append(py); vx.append(ux); vy.append(uy)
        typ.append(t); mass.append(m); role.append(1)

    digest = liquid_digest(liquid_records)
    write_state(a.output, x, y, vx, vy, typ, mass, role)

    target_area = L*H - (4.0-math.pi)*rr*rr
    discrete_area = len(liquid_records)*dx*dy/a.gamma
    meta = {
        "profile": "0493x14al_historical_x13h_taylor_culick_paired",
        "case": a.case,
        "Lx": a.Lx, "Ly": a.Ly, "nx": a.nx, "ny": a.ny,
        "h": h, "gamma": a.gamma,
        "centerX": a.center_x, "centerY": a.center_y,
        "sheetLengthCells": a.sheet_length_cells,
        "thicknessCells": a.thickness_cells,
        "edgeRoundCells": a.edge_round_cells,
        "liquidType": a.liquid_type, "gasType": a.gas_type,
        "liquidMass": a.liquid_mass, "gasMass": a.gas_mass,
        "liquidKBT": a.liquid_kBT, "gasKBT": a.gas_kBT,
        "seed": a.seed,
        "particles": len(x), "liquidParticles": len(liquid_records), "gasParticles": nG,
        "liquidInitialCanonicalSHA256": digest,
        "liquidInitialMeanRemovedVx": mvx,
        "liquidInitialMeanRemovedVy": mvy,
        "continuousTargetArea": target_area,
        "discreteLiquidArea": discrete_area,
        "discreteAreaRelativeError": discrete_area/target_area - 1.0,
        "xWallClearanceCells": xclr/h,
        "yWallClearanceCells": yclr/h,
    }
    mp = a.output.with_suffix(a.output.suffix + ".json")
    mp.write_text(json.dumps(meta, indent=2) + "\n")
    print(f"[0493x14al-generate] case={a.case} grid={a.nx}x{a.ny} h={h:.10g} gamma={a.gamma}")
    print(f"[0493x14al-generate] liquid={len(liquid_records)} gas={nG} total={len(x)}")
    print(f"[0493x14al-generate] liquidSHA256={digest}")
    print(f"[0493x14al-generate] sheet L/h={a.sheet_length_cells:g} H/h={a.thickness_cells:g} edgeRound/h={a.edge_round_cells:g}")
    print(f"[0493x14al-generate] state={a.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

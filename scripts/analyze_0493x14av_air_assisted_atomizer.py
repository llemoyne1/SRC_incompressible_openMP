#!/usr/bin/env python3
"""Offline diagnostics for the 0493x14av air-assisted atomizer demo.

The analysis is deliberately descriptive rather than a PASS/FAIL qualification:
it tracks liquid penetration, downstream spray width and connected liquid
components on the MPCD cell grid.  No pandas is used.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
import struct
from collections import deque
from pathlib import Path

import numpy as np

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
STEP_RE = re.compile(r"state_step_(\d+)\.smpcd$")


def read_state(path: Path):
    with path.open("rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError(f"{path}: invalid state magic")
        version, endian, dim, layout, n, has_type, _, real_bytes, type_bytes = struct.unpack("<IIIIQIIII", f.read(40))
        reserved = struct.unpack("<8Q", f.read(64))
        if endian != 0x01020304 or dim != 2 or layout != 1 or real_bytes != 8 or type_bytes != 4 or not has_type:
            raise RuntimeError(f"{path}: unsupported state format")
        def arr(dtype, count):
            a = np.fromfile(f, dtype=dtype, count=count)
            if a.size != count:
                raise RuntimeError(f"{path}: truncated array")
            return a
        x = arr("<f8", n); y = arr("<f8", n); vx = arr("<f8", n); vy = arr("<f8", n)
        typ = arr("<u4", n)
        mass = arr("<f8", n) if reserved[0] else np.ones(n, dtype=np.float64)
        role = np.fromfile(f, dtype=np.uint8, count=n) if reserved[1] else np.ones(n, dtype=np.uint8)
        if role.size != n:
            raise RuntimeError(f"{path}: truncated role")
    return x, y, vx, vy, typ, mass, role


def components_from_occupancy(occ: np.ndarray, threshold: int):
    wet = occ >= threshold
    ny, nx = wet.shape
    seen = np.zeros_like(wet, dtype=np.uint8)
    comps = []
    for iy in range(ny):
        for ix in range(nx):
            if not wet[iy, ix] or seen[iy, ix]:
                continue
            q = deque([(iy, ix)]); seen[iy, ix] = 1
            cells = 0; particles = 0; touches_left = False
            minx = nx; maxx = -1; miny = ny; maxy = -1
            while q:
                cy, cx = q.popleft()
                cells += 1; particles += int(occ[cy, cx])
                touches_left = touches_left or cx == 0
                minx = min(minx, cx); maxx = max(maxx, cx); miny = min(miny, cy); maxy = max(maxy, cy)
                for dy, dx in ((-1,0),(1,0),(0,-1),(0,1)):
                    yy, xx = cy+dy, cx+dx
                    if 0 <= yy < ny and 0 <= xx < nx and wet[yy,xx] and not seen[yy,xx]:
                        seen[yy,xx] = 1; q.append((yy,xx))
            comps.append((cells, particles, touches_left, minx, maxx, miny, maxy))
    return comps


def q(values: np.ndarray, p: float) -> float:
    return float(np.quantile(values, p)) if values.size else math.nan


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-root", type=Path, required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--ny", type=int, required=True)
    ap.add_argument("--gamma", type=float, required=True)
    ap.add_argument("--liquid-type", type=int, required=True)
    ap.add_argument("--liquid-nozzle-exit-x", type=float, required=True)
    ap.add_argument("--air-center-x", type=float, required=True)
    ap.add_argument("--air-diameter", type=float, required=True)
    ap.add_argument("--component-threshold-fraction", type=float, default=0.25)
    ap.add_argument("--min-detached-cells", type=int, default=2)
    args = ap.parse_args()

    dumps = []
    for path in sorted((args.run_root / "output").glob("state_step_*.smpcd")):
        m = STEP_RE.search(path.name)
        if m:
            dumps.append((int(m.group(1)), path))
    if not dumps:
        raise RuntimeError(f"no state_step_*.smpcd in {args.run_root/'output'}")

    hx, hy = args.Lx/args.nx, args.Ly/args.ny
    if abs(hx-hy) > 1e-12*max(1.0, abs(hx), abs(hy)):
        raise RuntimeError("square cells required")
    threshold = max(1, int(round(args.component_threshold_fraction * args.gamma)))
    downstream_x = args.air_center_x + 2.0 * args.air_diameter

    rows = []
    for step, path in dumps:
        x,y,vx,vy,typ,mass,role = read_state(path)
        mask = (role == 1) & (typ == args.liquid_type)
        xl = x[mask]; yl = y[mask]; vxl = vx[mask]; vyl = vy[mask]; ml = mass[mask]
        if xl.size == 0:
            continue
        ix = np.clip((xl/hx).astype(np.int64), 0, args.nx-1)
        iy = np.clip((yl/hy).astype(np.int64), 0, args.ny-1)
        occ = np.zeros((args.ny,args.nx), dtype=np.int32)
        np.add.at(occ, (iy,ix), 1)
        comps = components_from_occupancy(occ, threshold)
        detached = [c for c in comps if not c[2] and c[0] >= args.min_detached_cells]
        core = [c for c in comps if c[2]]
        downstream = xl >= downstream_x
        ydown = yl[downstream]
        mass_total = float(ml.sum())
        px_total = float(np.dot(ml, vxl))
        py_total = float(np.dot(ml, vyl))
        row = {
            "step": step,
            "liquidParticles": int(xl.size),
            "liquidMass": mass_total,
            "liquidX50": q(xl,0.50), "liquidX90": q(xl,0.90), "liquidX99": q(xl,0.99), "liquidXMax": float(xl.max()),
            "liquidY10": q(yl,0.10), "liquidY50": q(yl,0.50), "liquidY90": q(yl,0.90),
            "downstreamParticles": int(downstream.sum()),
            "downstreamY10": q(ydown,0.10), "downstreamY90": q(ydown,0.90),
            "downstreamWidth80": (q(ydown,0.90)-q(ydown,0.10)) if ydown.size else math.nan,
            "wetComponents": len(comps), "coreComponents": len(core), "detachedComponents": len(detached),
            "largestDetachedCells": max((c[0] for c in detached), default=0),
            "largestDetachedParticles": max((c[1] for c in detached), default=0),
            "meanLiquidVx": px_total/mass_total if mass_total>0 else math.nan,
            "meanLiquidVy": py_total/mass_total if mass_total>0 else math.nan,
        }
        rows.append(row)
        print(
            f"[0493x14av-analysis] step={step} Nliq={row['liquidParticles']} "
            f"x99={row['liquidX99']:.6g} width80={row['downstreamWidth80']:.6g} "
            f"components={row['wetComponents']} detached={row['detachedComponents']}"
        )

    outdir = args.run_root / "analysis"
    outdir.mkdir(parents=True, exist_ok=True)
    csv_path = outdir / "atomizer_history.csv"
    fields = list(rows[0].keys())
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader(); w.writerows(rows)

    last = rows[-1]
    report = {
        "status": "DEMONSTRATION_DIAGNOSTIC_ONLY",
        "runRoot": str(args.run_root),
        "componentThresholdParticles": threshold,
        "downstreamProbeX": downstream_x,
        "latest": last,
        "interpretation": {
            "detachedComponents": "number of >=min-detached-cells liquid components not connected to the left boundary",
            "downstreamWidth80": "y90-y10 of liquid particles downstream of airCenterX+2*airDiameter",
        },
    }
    (outdir / "atomizer_report.json").write_text(json.dumps(report, indent=2, allow_nan=True)+"\n")
    (outdir / "atomizer_report.txt").write_text(
        "0493x14av air-assisted atomizer demo\n"
        "=====================================\n"
        "Status: DEMONSTRATION_DIAGNOSTIC_ONLY\n"
        f"latest step={last['step']} liquidX99={last['liquidX99']:.9g} "
        f"downstreamWidth80={last['downstreamWidth80']:.9g} detachedComponents={last['detachedComponents']}\n"
        "No physical atomization PASS/FAIL criterion is asserted by this analyzer.\n"
    )
    print(f"[0493x14av-analysis] history={csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

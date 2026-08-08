#!/usr/bin/env python3
"""Offline dynamic-support analysis for the 0493x5a2 liquid-vacuum dam break."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import struct
from array import array
from collections import deque
from pathlib import Path
from statistics import mean

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
STEP_RE = re.compile(r"state_step_(\d+)\.smpcd$")


def read_array(stream, code: str, count: int) -> array:
    values = array(code)
    values.fromfile(stream, count)
    if len(values) != count:
        raise RuntimeError("truncated state array")
    return values


def read_state(path: Path) -> dict[str, object]:
    with path.open("rb") as stream:
        if stream.read(16) != MAGIC:
            raise RuntimeError(f"{path}: invalid state magic")
        version, endian, dim, layout, n, has_type, _, real_bytes, type_bytes = struct.unpack(
            "<IIIIQIIII", stream.read(40)
        )
        reserved = struct.unpack("<8Q", stream.read(64))
        if endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"{path}: unsupported state layout")
        if real_bytes != 8 or type_bytes != 4 or not has_type:
            raise RuntimeError(f"{path}: unsupported scalar/type format")
        x = read_array(stream, "d", n)
        y = read_array(stream, "d", n)
        vx = read_array(stream, "d", n)
        vy = read_array(stream, "d", n)
        typ = read_array(stream, "I", n)
        mass = read_array(stream, "d", n) if reserved[0] else array("d", [1.0]) * n
        role = bytearray(stream.read(n)) if reserved[1] else bytearray([1]) * n
        if len(role) != n:
            raise RuntimeError(f"{path}: truncated role array")
    return {
        "version": version,
        "n": n,
        "x": x,
        "y": y,
        "vx": vx,
        "vy": vy,
        "type": typ,
        "mass": mass,
        "role": role,
    }


def quantile(values: list[float], q: float) -> float:
    if not values:
        return math.nan
    if len(values) == 1:
        return values[0]
    ordered = sorted(values)
    pos = min(1.0, max(0.0, q)) * (len(ordered) - 1)
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return ordered[lo]
    w = pos - lo
    return ordered[lo] * (1.0 - w) + ordered[hi] * w


def support_topology(mask: list[bool], nx: int, ny: int) -> dict[str, int | float]:
    nc = nx * ny
    visited = bytearray(nc)
    component_sizes: list[int] = []
    for start in range(nc):
        if not mask[start] or visited[start]:
            continue
        visited[start] = 1
        queue: deque[int] = deque([start])
        size = 0
        while queue:
            c = queue.popleft()
            size += 1
            ix = c % nx
            iy = c // nx
            if ix > 0:
                n = c - 1
                if mask[n] and not visited[n]:
                    visited[n] = 1
                    queue.append(n)
            if ix + 1 < nx:
                n = c + 1
                if mask[n] and not visited[n]:
                    visited[n] = 1
                    queue.append(n)
            if iy > 0:
                n = c - nx
                if mask[n] and not visited[n]:
                    visited[n] = 1
                    queue.append(n)
            if iy + 1 < ny:
                n = c + nx
                if mask[n] and not visited[n]:
                    visited[n] = 1
                    queue.append(n)
        component_sizes.append(size)

    exterior = bytearray(nc)
    queue: deque[int] = deque()
    boundary_cells = set()
    for ix in range(nx):
        boundary_cells.add(ix)
        boundary_cells.add((ny - 1) * nx + ix)
    for iy in range(ny):
        boundary_cells.add(iy * nx)
        boundary_cells.add(iy * nx + nx - 1)
    for c in boundary_cells:
        if not mask[c] and not exterior[c]:
            exterior[c] = 1
            queue.append(c)
    while queue:
        c = queue.popleft()
        ix = c % nx
        iy = c // nx
        for n in (
            c - 1 if ix > 0 else -1,
            c + 1 if ix + 1 < nx else -1,
            c - nx if iy > 0 else -1,
            c + nx if iy + 1 < ny else -1,
        ):
            if n >= 0 and not mask[n] and not exterior[n]:
                exterior[n] = 1
                queue.append(n)

    hole_cells = sum(1 for c in range(nc) if not mask[c] and not exterior[c])
    hole_components = 0
    hole_seen = bytearray(nc)
    for start in range(nc):
        if mask[start] or exterior[start] or hole_seen[start]:
            continue
        hole_components += 1
        hole_seen[start] = 1
        queue = deque([start])
        while queue:
            c = queue.popleft()
            ix = c % nx
            iy = c // nx
            for n in (
                c - 1 if ix > 0 else -1,
                c + 1 if ix + 1 < nx else -1,
                c - nx if iy > 0 else -1,
                c + nx if iy + 1 < ny else -1,
            ):
                if n >= 0 and not mask[n] and not exterior[n] and not hole_seen[n]:
                    hole_seen[n] = 1
                    queue.append(n)

    free_surface_faces = 0
    for c, active in enumerate(mask):
        if not active:
            continue
        ix = c % nx
        iy = c // nx
        if ix > 0 and not mask[c - 1]:
            free_surface_faces += 1
        if ix + 1 < nx and not mask[c + 1]:
            free_surface_faces += 1
        if iy > 0 and not mask[c - nx]:
            free_surface_faces += 1
        if iy + 1 < ny and not mask[c + nx]:
            free_surface_faces += 1

    active_cells = sum(mask)
    largest = max(component_sizes, default=0)
    return {
        "supportComponents": len(component_sizes),
        "largestSupportComponentCells": largest,
        "largestSupportComponentFraction": largest / active_cells if active_cells else 0.0,
        "enclosedVoidComponents": hole_components,
        "enclosedVoidCells": hole_cells,
        "freeSurfaceFaces": free_surface_faces,
    }


def analyze_state(
    path: Path,
    step: int,
    nx: int,
    ny: int,
    lx: float,
    ly: float,
    gamma: float,
    min_fill_fraction: float,
    liquid_type: int,
) -> dict[str, int | float | str]:
    data = read_state(path)
    x = data["x"]
    y = data["y"]
    vx = data["vx"]
    vy = data["vy"]
    typ = data["type"]
    mass = data["mass"]
    role = data["role"]
    assert isinstance(role, bytearray)

    dx = lx / nx
    dy = ly / ny
    occupancy = [0] * (nx * ny)
    xs: list[float] = []
    ys: list[float] = []
    count = 0
    total_mass = 0.0
    sx = sy = svx = svy = sv2 = 0.0

    for i in range(int(data["n"])):
        if role[i] != 1 or int(typ[i]) != liquid_type:
            continue
        xi = min(max(float(x[i]), 0.0), math.nextafter(lx, 0.0))
        yi = min(max(float(y[i]), 0.0), math.nextafter(ly, 0.0))
        ix = min(nx - 1, max(0, int(xi / dx)))
        iy = min(ny - 1, max(0, int(yi / dy)))
        occupancy[iy * nx + ix] += 1
        mi = float(mass[i])
        vxi = float(vx[i])
        vyi = float(vy[i])
        total_mass += mi
        sx += mi * xi
        sy += mi * yi
        svx += mi * vxi
        svy += mi * vyi
        sv2 += mi * (vxi * vxi + vyi * vyi)
        xs.append(xi)
        ys.append(yi)
        count += 1

    if count == 0 or total_mass <= 0.0:
        raise RuntimeError(f"{path}: no liquid particles found")

    occupied = [n for n in occupancy if n > 0]
    threshold_count = max(1, int(math.ceil(gamma * min_fill_fraction - 1.0e-12)))
    support_mask = [n >= threshold_count for n in occupancy]
    topology = support_topology(support_mask, nx, ny)
    row_counts = [sum(occupancy[iy * nx:(iy + 1) * nx]) for iy in range(ny)]
    col_counts = [sum(occupancy[iy * nx + ix] for iy in range(ny)) for ix in range(nx)]
    occupied_rows = [iy for iy, value in enumerate(row_counts) if value > 0]
    occupied_cols = [ix for ix, value in enumerate(col_counts) if value > 0]

    report: dict[str, int | float | str] = {
        "step": step,
        "state": str(path),
        "liquidParticles": count,
        "totalLiquidMass": total_mass,
        "centerOfMassX": sx / total_mass,
        "centerOfMassY": sy / total_mass,
        "meanVx": svx / total_mass,
        "meanVy": svy / total_mass,
        "velocityRms": math.sqrt(sv2 / total_mass),
        "occupiedCells": len(occupied),
        "supportCellsOffline": sum(support_mask),
        "supportThresholdParticles": threshold_count,
        "lowPopulationOccupiedCells": sum(1 for n in occupied if n < threshold_count),
        "populationMeanOccupied": sum(occupied) / len(occupied),
        "populationMinOccupied": min(occupied),
        "populationMaxOccupied": max(occupied),
        "frontXMax": max(xs),
        "frontX99": quantile(xs, 0.99),
        "frontX995": quantile(xs, 0.995),
        "topYMax": max(ys),
        "topY99": quantile(ys, 0.99),
        "occupiedColumnMax": max(occupied_cols) if occupied_cols else -1,
        "occupiedRowMax": max(occupied_rows) if occupied_rows else -1,
    }
    report.update(topology)
    return report


def percentile(values: list[float], q: float) -> float:
    return quantile(values, q)


def read_mask_audit(path: Path, liquid_type: int) -> dict[str, object]:
    if not path.exists():
        return {"present": False, "rows": 0}
    rows: list[dict[str, str]] = []
    with path.open(newline="") as stream:
        for row in csv.DictReader(stream):
            if int(row["type"]) == liquid_type and float(row["q6Strength"]) > 0.0:
                rows.append(row)
    if not rows:
        return {"present": True, "rows": 0}
    iterations = [int(row["iterations"]) for row in rows]
    residuals = [float(row["residualRel"]) for row in rows]
    active = [int(row["activeCells"]) for row in rows]
    return {
        "present": True,
        "rows": len(rows),
        "allConverged": all(int(row["converged"]) == 1 for row in rows),
        "iterationsMean": mean(iterations),
        "iterationsP95": percentile([float(v) for v in iterations], 0.95),
        "iterationsMax": max(iterations),
        "residualRelMax": max(residuals),
        "activeCellsMin": min(active),
        "activeCellsMax": max(active),
        "activeCellsFinal": active[-1],
        "correctedParticlesFinal": int(rows[-1]["correctedParticles"]),
    }


def read_resident_audit(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"present": False, "rows": 0}
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        return {"present": True, "rows": 0}
    solve = [float(row["solveSeconds"]) for row in rows]
    deposit = [float(row["depositSeconds"]) for row in rows]
    apply = [float(row["applySeconds"]) for row in rows]
    total = [float(row["totalSeconds"]) for row in rows]
    return {
        "present": True,
        "rows": len(rows),
        "solveSecondsSum": sum(solve),
        "solveSecondsMean": mean(solve),
        "solveSecondsP95": percentile(solve, 0.95),
        "solveSecondsMax": max(solve),
        "depositSecondsSum": sum(deposit),
        "applySecondsSum": sum(apply),
        "totalSecondsSum": sum(total),
        "totalSecondsMean": mean(total),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--initial-state", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--mask-audit", type=Path, required=True)
    parser.add_argument("--resident-audit", type=Path, required=True)
    parser.add_argument("--nx", type=int, required=True)
    parser.add_argument("--ny", type=int, required=True)
    parser.add_argument("--Lx", type=float, required=True)
    parser.add_argument("--Ly", type=float, required=True)
    parser.add_argument("--gamma", type=float, required=True)
    parser.add_argument("--min-fill-fraction", type=float, required=True)
    parser.add_argument("--liquid-type", type=int, required=True)
    parser.add_argument("--max-population-factor", type=float, default=12.0)
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--csv", type=Path, required=True)
    args = parser.parse_args()

    state_paths: list[tuple[int, Path]] = [(0, args.initial_state)]
    for path in sorted(args.output_dir.glob("state_step_*.smpcd")):
        match = STEP_RE.search(path.name)
        if match:
            step = int(match.group(1))
            if step != 0:
                state_paths.append((step, path))
    if len(state_paths) < 2:
        raise RuntimeError("no dynamic state dumps found")

    series = [
        analyze_state(
            path, step, args.nx, args.ny, args.Lx, args.Ly, args.gamma,
            args.min_fill_fraction, args.liquid_type,
        )
        for step, path in state_paths
    ]
    initial = series[0]
    final = series[-1]
    mask_audit = read_mask_audit(args.mask_audit, args.liquid_type)
    resident_audit = read_resident_audit(args.resident_audit)

    particle_count_ok = all(row["liquidParticles"] == initial["liquidParticles"] for row in series)
    population_limit = args.max_population_factor * args.gamma
    population_ok = max(float(row["populationMaxOccupied"]) for row in series) <= population_limit
    q6_present = bool(mask_audit.get("present")) and int(mask_audit.get("rows", 0)) > 0
    q6_converged = q6_present and bool(mask_audit.get("allConverged"))
    pass_like = particle_count_ok and population_ok and q6_converged

    front_advance_995 = float(final["frontX995"]) - float(initial["frontX995"])
    report = {
        "status": "PASS-like" if pass_like else "FAIL-like",
        "configuration": {
            "nx": args.nx,
            "ny": args.ny,
            "Lx": args.Lx,
            "Ly": args.Ly,
            "gamma": args.gamma,
            "minFillFraction": args.min_fill_fraction,
            "liquidType": args.liquid_type,
            "maxPopulationFactor": args.max_population_factor,
        },
        "checks": {
            "particleCountConserved": particle_count_ok,
            "q6AuditPresent": q6_present,
            "allQ6SolvesConverged": q6_converged,
            "noMacroscopicPopulationCollapse": population_ok,
        },
        "initial": initial,
        "final": final,
        "frontAdvanceX995": front_advance_995,
        "centerOfMassXShift": float(final["centerOfMassX"]) - float(initial["centerOfMassX"]),
        "centerOfMassYShift": float(final["centerOfMassY"]) - float(initial["centerOfMassY"]),
        "maskAudit": mask_audit,
        "residentAudit": resident_audit,
        "series": series,
    }

    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [key for key in series[0].keys() if key != "state"]
    with args.csv.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        for row in series:
            writer.writerow({key: row[key] for key in fieldnames})

    print(
        "[0493x5a2-analysis] "
        f"status={report['status']} dumps={len(series) - 1} "
        f"particles={final['liquidParticles']} supportFinal={final['supportCellsOffline']} "
        f"frontAdvanceX995={front_advance_995:.6e} "
        f"comShift=({report['centerOfMassXShift']:.6e},{report['centerOfMassYShift']:.6e}) "
        f"components={final['supportComponents']} largestFrac={final['largestSupportComponentFraction']:.6f} "
        f"holes={final['enclosedVoidComponents']}/{final['enclosedVoidCells']} "
        f"popMax={final['populationMaxOccupied']} "
        f"q6IterMax={mask_audit.get('iterationsMax', -1)} "
        f"q6ResidualMax={float(mask_audit.get('residualRelMax', math.nan)):.3e}"
    )
    return 0 if pass_like else 3


if __name__ == "__main__":
    raise SystemExit(main())

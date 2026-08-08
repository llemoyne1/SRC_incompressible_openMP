#!/usr/bin/env python3
"""Offline two-species diagnostics for the 0493x5b liquid-gas dam break."""

from __future__ import annotations

import argparse
import csv
import json
import math
from array import array
from pathlib import Path
from statistics import mean

from analyze_0493x5a2_dynamic_free_surface import (
    STEP_RE,
    quantile,
    read_mask_audit,
    read_resident_audit,
    read_state,
    support_topology,
)


def finite_or_raise(value: float, label: str, path: Path) -> float:
    if not math.isfinite(value):
        raise RuntimeError(f"{path}: non-finite {label}")
    return value


def population_stats(values: list[int], prefix: str) -> dict[str, int | float]:
    occupied = [n for n in values if n > 0]
    if not occupied:
        return {
            f"{prefix}OccupiedCells": 0,
            f"{prefix}PopulationMeanOccupied": 0.0,
            f"{prefix}PopulationMinOccupied": 0,
            f"{prefix}PopulationMaxOccupied": 0,
        }
    return {
        f"{prefix}OccupiedCells": len(occupied),
        f"{prefix}PopulationMeanOccupied": sum(occupied) / len(occupied),
        f"{prefix}PopulationMinOccupied": min(occupied),
        f"{prefix}PopulationMaxOccupied": max(occupied),
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
    gas_type: int,
) -> dict[str, int | float | str]:
    data = read_state(path)
    x = data["x"]
    y = data["y"]
    vx = data["vx"]
    vy = data["vy"]
    typ = data["type"]
    mass = data["mass"]
    role = data["role"]
    assert isinstance(x, array) and isinstance(y, array)
    assert isinstance(vx, array) and isinstance(vy, array)
    assert isinstance(typ, array) and isinstance(mass, array)
    assert isinstance(role, bytearray)

    nc = nx * ny
    dx = lx / nx
    dy = ly / ny
    liquid_occ = [0] * nc
    gas_occ = [0] * nc
    liquid_x: list[float] = []
    liquid_y: list[float] = []

    accum = {
        liquid_type: {"count": 0, "mass": 0.0, "sx": 0.0, "sy": 0.0,
                      "spx": 0.0, "spy": 0.0, "sv2": 0.0},
        gas_type: {"count": 0, "mass": 0.0, "sx": 0.0, "sy": 0.0,
                   "spx": 0.0, "spy": 0.0, "sv2": 0.0},
    }
    total_px = total_py = 0.0

    for i in range(int(data["n"])):
        if role[i] != 1:
            continue
        particle_type = int(typ[i])
        if particle_type not in accum:
            continue
        xi = min(max(finite_or_raise(float(x[i]), "x", path), 0.0), math.nextafter(lx, 0.0))
        yi = min(max(finite_or_raise(float(y[i]), "y", path), 0.0), math.nextafter(ly, 0.0))
        vxi = finite_or_raise(float(vx[i]), "vx", path)
        vyi = finite_or_raise(float(vy[i]), "vy", path)
        mi = finite_or_raise(float(mass[i]), "mass", path)
        ix = min(nx - 1, max(0, int(xi / dx)))
        iy = min(ny - 1, max(0, int(yi / dy)))
        cell = iy * nx + ix
        if particle_type == liquid_type:
            liquid_occ[cell] += 1
            liquid_x.append(xi)
            liquid_y.append(yi)
        else:
            gas_occ[cell] += 1
        a = accum[particle_type]
        a["count"] += 1
        a["mass"] += mi
        a["sx"] += mi * xi
        a["sy"] += mi * yi
        a["spx"] += mi * vxi
        a["spy"] += mi * vyi
        a["sv2"] += mi * (vxi * vxi + vyi * vyi)
        total_px += mi * vxi
        total_py += mi * vyi

    if not liquid_x or accum[gas_type]["count"] == 0:
        raise RuntimeError(f"{path}: expected both liquid and gas particles")

    threshold_count = max(1, int(math.ceil(gamma * min_fill_fraction - 1.0e-12)))
    support_mask = [n >= threshold_count for n in liquid_occ]
    topology = support_topology(support_mask, nx, ny)
    mixed_cells = sum(1 for l, g in zip(liquid_occ, gas_occ) if l > 0 and g > 0)
    liquid_only_cells = sum(1 for l, g in zip(liquid_occ, gas_occ) if l > 0 and g == 0)
    gas_only_cells = sum(1 for l, g in zip(liquid_occ, gas_occ) if l == 0 and g > 0)
    empty_cells = sum(1 for l, g in zip(liquid_occ, gas_occ) if l == 0 and g == 0)
    liquid_in_mixed = sum(l for l, g in zip(liquid_occ, gas_occ) if l > 0 and g > 0)
    gas_in_mixed = sum(g for l, g in zip(liquid_occ, gas_occ) if l > 0 and g > 0)

    report: dict[str, int | float | str] = {"step": step, "state": str(path)}
    for particle_type, prefix in ((liquid_type, "liquid"), (gas_type, "gas")):
        a = accum[particle_type]
        m = float(a["mass"])
        if m <= 0.0:
            raise RuntimeError(f"{path}: zero {prefix} mass")
        report.update({
            f"{prefix}Particles": int(a["count"]),
            f"{prefix}Mass": m,
            f"{prefix}CenterOfMassX": float(a["sx"]) / m,
            f"{prefix}CenterOfMassY": float(a["sy"]) / m,
            f"{prefix}MeanVx": float(a["spx"]) / m,
            f"{prefix}MeanVy": float(a["spy"]) / m,
            f"{prefix}VelocityRms": math.sqrt(float(a["sv2"]) / m),
        })
    report.update(population_stats(liquid_occ, "liquid"))
    report.update(population_stats(gas_occ, "gas"))
    report.update({
        "liquidSupportCellsOffline": sum(support_mask),
        "liquidSupportThresholdParticles": threshold_count,
        "lowPopulationLiquidOccupiedCells": sum(
            1 for n in liquid_occ if 0 < n < threshold_count
        ),
        "mixedCells": mixed_cells,
        "liquidOnlyCells": liquid_only_cells,
        "gasOnlyCells": gas_only_cells,
        "emptyCells": empty_cells,
        "liquidParticlesInMixedCells": liquid_in_mixed,
        "gasParticlesInMixedCells": gas_in_mixed,
        "frontXMax": max(liquid_x),
        "frontX99": quantile(liquid_x, 0.99),
        "frontX995": quantile(liquid_x, 0.995),
        "topYMax": max(liquid_y),
        "topY99": quantile(liquid_y, 0.99),
        "totalMomentumX": total_px,
        "totalMomentumY": total_py,
    })
    report.update({f"liquid{key[0].upper()}{key[1:]}": value for key, value in topology.items()})
    return report


def read_gas_q6_audit(path: Path, gas_type: int) -> dict[str, object]:
    if not path.exists():
        return {"present": False, "rows": 0}
    rows: list[dict[str, str]] = []
    with path.open(newline="") as stream:
        for row in csv.DictReader(stream):
            if int(row["type"]) == gas_type:
                rows.append(row)
    if not rows:
        return {"present": True, "rows": 0}
    return {
        "present": True,
        "rows": len(rows),
        "allStrengthZero": all(float(row["q6Strength"]) == 0.0 for row in rows),
        "allActiveCellsZero": all(int(row["activeCells"]) == 0 for row in rows),
        "allCorrectedParticlesZero": all(int(row["correctedParticles"]) == 0 for row in rows),
        "maxCorrectionRms": max(float(row["correctionRms"]) for row in rows),
        "maxCorrectionMaxAbs": max(float(row["correctionMaxAbs"]) for row in rows),
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
    parser.add_argument("--gas-type", type=int, required=True)
    parser.add_argument("--max-liquid-population-factor", type=float, default=12.0)
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
        raise RuntimeError("no liquid-gas dynamic state dumps found")

    series = [
        analyze_state(
            path, step, args.nx, args.ny, args.Lx, args.Ly, args.gamma,
            args.min_fill_fraction, args.liquid_type, args.gas_type,
        )
        for step, path in state_paths
    ]
    initial = series[0]
    final = series[-1]
    liquid_audit = read_mask_audit(args.mask_audit, args.liquid_type)
    gas_audit = read_gas_q6_audit(args.mask_audit, args.gas_type)
    resident_audit = read_resident_audit(args.resident_audit)

    liquid_count_ok = all(row["liquidParticles"] == initial["liquidParticles"] for row in series)
    gas_count_ok = all(row["gasParticles"] == initial["gasParticles"] for row in series)
    liquid_population_ok = max(float(row["liquidPopulationMaxOccupied"]) for row in series) <= (
        args.max_liquid_population_factor * args.gamma
    )
    liquid_q6_ok = (
        bool(liquid_audit.get("present")) and int(liquid_audit.get("rows", 0)) > 0
        and bool(liquid_audit.get("allConverged"))
    )
    gas_unprojected_ok = (
        bool(gas_audit.get("present")) and int(gas_audit.get("rows", 0)) > 0
        and bool(gas_audit.get("allStrengthZero"))
        and bool(gas_audit.get("allActiveCellsZero"))
        and bool(gas_audit.get("allCorrectedParticlesZero"))
    )
    pass_like = (
        liquid_count_ok and gas_count_ok and liquid_population_ok
        and liquid_q6_ok and gas_unprojected_ok
    )

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
            "gasType": args.gas_type,
            "maxLiquidPopulationFactor": args.max_liquid_population_factor,
        },
        "checks": {
            "liquidParticleCountConserved": liquid_count_ok,
            "gasParticleCountConserved": gas_count_ok,
            "allLiquidQ6SolvesConverged": liquid_q6_ok,
            "gasStrictlyUnprojected": gas_unprojected_ok,
            "noMacroscopicLiquidPopulationCollapse": liquid_population_ok,
        },
        "initial": initial,
        "final": final,
        "liquidFrontAdvanceX995": float(final["frontX995"]) - float(initial["frontX995"]),
        "liquidCenterOfMassXShift": (
            float(final["liquidCenterOfMassX"]) - float(initial["liquidCenterOfMassX"])
        ),
        "liquidCenterOfMassYShift": (
            float(final["liquidCenterOfMassY"]) - float(initial["liquidCenterOfMassY"])
        ),
        "liquidQ6Audit": liquid_audit,
        "gasQ6Audit": gas_audit,
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
        "[0493x5b-analysis] "
        f"status={report['status']} dumps={len(series) - 1} "
        f"liquid={final['liquidParticles']} gas={final['gasParticles']} "
        f"supportFinal={final['liquidSupportCellsOffline']} "
        f"frontAdvanceX995={report['liquidFrontAdvanceX995']:.6e} "
        f"comShift=({report['liquidCenterOfMassXShift']:.6e},"
        f"{report['liquidCenterOfMassYShift']:.6e}) "
        f"mixedCells={final['mixedCells']} "
        f"components={final['liquidSupportComponents']} "
        f"largestFrac={final['liquidLargestSupportComponentFraction']:.6f} "
        f"liquidPopMax={final['liquidPopulationMaxOccupied']} "
        f"gasPopMax={final['gasPopulationMaxOccupied']} "
        f"gasCorrected={0 if gas_audit.get('allCorrectedParticlesZero') else -1} "
        f"q6IterMax={liquid_audit.get('iterationsMax', -1)} "
        f"q6ResidualMax={float(liquid_audit.get('residualRelMax', math.nan)):.3e}"
    )
    return 0 if pass_like else 3


if __name__ == "__main__":
    raise SystemExit(main())

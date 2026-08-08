#!/usr/bin/env python3
"""Validate the 0493x6f prepared alpha=0.5 pressure-interface stencil."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def load_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise RuntimeError(f"missing audit CSV: {path}")
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise RuntimeError(f"empty audit CSV: {path}")
    return rows


def finite(row: dict[str, str], key: str) -> float:
    value = float(row[key])
    if not math.isfinite(value):
        raise RuntimeError(f"non-finite {key}: {row[key]}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stencil", type=Path, required=True)
    parser.add_argument("--geometry", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    args = parser.parse_args()

    stencil = load_csv(args.stencil)
    geometry = load_csv(args.geometry)
    geom_by_step = {int(r["step"]): r for r in geometry}

    required_stencil = {
        "step", "carrierActiveCells", "pressureActiveCells",
        "interiorPressureFaces", "representedInterfaceFaces",
        "smallThetaStabilizedFaces", "carrierTruncationFaces",
        "uncoveredInterfaceFaces", "thetaGuard", "thetaMin", "thetaMean",
        "thetaMax", "prepareSeconds", "residentBytes",
    }
    missing = required_stencil.difference(stencil[0])
    if missing:
        raise RuntimeError(f"stencil audit missing columns: {sorted(missing)}")

    required_geometry = {
        "step", "phaseInterfaceTopologyEnabled", "cutFaceGeometryEnabled",
        "alphaHalfCrossingFaces", "alphaHalfCrossingActiveActiveFaces",
        "alphaHalfCrossingAIActiveLiquidSideFaces",
        "alphaHalfCrossingAIActiveExteriorSideFaces",
        "alphaHalfCrossingInactiveInactiveFaces",
    }
    missing = required_geometry.difference(geometry[0])
    if missing:
        raise RuntimeError(f"geometry audit missing x6e columns: {sorted(missing)}")

    min_coverage = 1.0
    max_coverage = 0.0
    max_uncovered = 0
    max_truncation = 0
    max_small = 0
    min_pressure_ratio = 1.0
    max_pressure_ratio = 0.0
    theta_min_global = 1.0
    theta_max_global = 0.0
    prepare_sum = 0.0
    prepare_max = 0.0
    resident_bytes = 0
    per_step: list[dict[str, float | int]] = []

    for row in stencil:
        step = int(row["step"])
        if step not in geom_by_step:
            raise RuntimeError(f"step {step}: no matching x6e geometry row")
        g = geom_by_step[step]
        if int(g["phaseInterfaceTopologyEnabled"]) != 1:
            raise RuntimeError(f"step {step}: x6e topology audit is not enabled")
        if int(g["cutFaceGeometryEnabled"]) != 0:
            raise RuntimeError(f"step {step}: x6d must be disabled in the x6f runner")

        carrier = int(row["carrierActiveCells"])
        pressure = int(row["pressureActiveCells"])
        represented = int(row["representedInterfaceFaces"])
        small = int(row["smallThetaStabilizedFaces"])
        truncation = int(row["carrierTruncationFaces"])
        uncovered = int(row["uncoveredInterfaceFaces"])
        total = int(g["alphaHalfCrossingFaces"])
        aa = int(g["alphaHalfCrossingActiveActiveFaces"])
        ai_liquid = int(g["alphaHalfCrossingAIActiveLiquidSideFaces"])
        ai_exterior = int(g["alphaHalfCrossingAIActiveExteriorSideFaces"])
        ii = int(g["alphaHalfCrossingInactiveInactiveFaces"])

        if pressure <= 0 or pressure > carrier:
            raise RuntimeError(
                f"step {step}: invalid pressure/carrier cells {pressure}/{carrier}"
            )
        if represented + uncovered != total:
            raise RuntimeError(
                f"step {step}: physical interface partition mismatch: "
                f"represented={represented} uncovered={uncovered} total={total}"
            )
        # x6f turns all carrier-contained alpha crossings, including x6e AA,
        # into pressure-domain boundary faces.  Only a crossing whose liquid
        # side is outside the carrier remains uncovered.
        if represented != aa + ai_liquid:
            raise RuntimeError(
                f"step {step}: represented-interface topology mismatch: "
                f"x6f={represented} AA+AI-liquid={aa + ai_liquid}"
            )
        if uncovered != ai_exterior + ii:
            raise RuntimeError(
                f"step {step}: uncovered-interface topology mismatch: "
                f"x6f={uncovered} AI-exterior+II={ai_exterior + ii}"
            )
        if small > represented:
            raise RuntimeError(f"step {step}: small-theta count exceeds represented faces")

        theta_guard = finite(row, "thetaGuard")
        theta_min = finite(row, "thetaMin")
        theta_mean = finite(row, "thetaMean")
        theta_max = finite(row, "thetaMax")
        prep = finite(row, "prepareSeconds")
        if represented > 0 and not (
            0.0 <= theta_min <= theta_mean <= theta_max <= 1.0 + 2e-9
        ):
            raise RuntimeError(
                f"step {step}: invalid theta range {theta_min}, {theta_mean}, {theta_max}"
            )
        if theta_guard <= 0.0 or prep < 0.0:
            raise RuntimeError(f"step {step}: invalid guard/timing")

        coverage = represented / total if total else 0.0
        pressure_ratio = pressure / carrier
        min_coverage = min(min_coverage, coverage)
        max_coverage = max(max_coverage, coverage)
        max_uncovered = max(max_uncovered, uncovered)
        max_truncation = max(max_truncation, truncation)
        max_small = max(max_small, small)
        min_pressure_ratio = min(min_pressure_ratio, pressure_ratio)
        max_pressure_ratio = max(max_pressure_ratio, pressure_ratio)
        if represented > 0:
            theta_min_global = min(theta_min_global, theta_min)
            theta_max_global = max(theta_max_global, theta_max)
        prepare_sum += prep
        prepare_max = max(prepare_max, prep)
        resident_bytes = max(resident_bytes, int(row["residentBytes"]))
        per_step.append(
            {
                "step": step,
                "carrierActiveCells": carrier,
                "pressureActiveCells": pressure,
                "pressureToCarrierFraction": pressure_ratio,
                "physicalInterfaceFaces": total,
                "representedInterfaceFaces": represented,
                "uncoveredInterfaceFaces": uncovered,
                "representedCoverage": coverage,
                "carrierTruncationFaces": truncation,
                "smallThetaStabilizedFaces": small,
            }
        )

    first = per_step[0]
    last = per_step[-1]
    report = {
        "status": "PASS-like",
        "rows": len(stencil),
        "firstStep": first["step"],
        "lastStep": last["step"],
        "minPhysicalInterfaceCoverage": min_coverage,
        "maxPhysicalInterfaceCoverage": max_coverage,
        "maxUncoveredInterfaceFaces": max_uncovered,
        "maxCarrierTruncationFaces": max_truncation,
        "maxSmallThetaStabilizedFaces": max_small,
        "minPressureToCarrierFraction": min_pressure_ratio,
        "maxPressureToCarrierFraction": max_pressure_ratio,
        "globalThetaMin": theta_min_global,
        "globalThetaMax": theta_max_global,
        "prepareSecondsMean": prepare_sum / len(stencil),
        "prepareSecondsMax": prepare_max,
        "residentBytes": resident_bytes,
        "first": first,
        "last": last,
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")

    print(
        "[0493x6f-analysis] "
        f"status={report['status']} rows={report['rows']} "
        f"steps={report['firstStep']}..{report['lastStep']} "
        f"coverage={report['minPhysicalInterfaceCoverage']:.3f}.."
        f"{report['maxPhysicalInterfaceCoverage']:.3f} "
        f"uncoveredMax={report['maxUncoveredInterfaceFaces']} "
        f"carrierTruncMax={report['maxCarrierTruncationFaces']} "
        f"pressure/carrier={report['minPressureToCarrierFraction']:.3f}.."
        f"{report['maxPressureToCarrierFraction']:.3f} "
        f"theta={report['globalThetaMin']:.3f}..{report['globalThetaMax']:.3f} "
        f"smallThetaMax={report['maxSmallThetaStabilizedFaces']} "
        f"prepareMean={report['prepareSecondsMean']:.3e}s "
        f"resident={report['residentBytes']}B"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

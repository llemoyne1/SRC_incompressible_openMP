#!/usr/bin/env python3
"""Validate the 0493x6c resident phase-geometry infrastructure."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def finite(row: dict[str, str], key: str) -> float:
    value = float(row[key])
    if not math.isfinite(value):
        raise RuntimeError(f"non-finite {key}: {row[key]}")
    return value


def bounded_fraction(value: float, name: str, tol: float = 1.0e-12) -> None:
    if value < -tol or value > 1.0 + tol:
        raise RuntimeError(f"{name} outside [0,1]: {value}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--conservation-tolerance", type=float, default=1.0e-10)
    args = parser.parse_args()

    if not args.audit.exists():
        raise RuntimeError(f"missing 0493x6c audit: {args.audit}")
    with args.audit.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise RuntimeError("empty 0493x6c resident geometry audit")

    required = {
        "step", "time", "projectedSpeciesIndex", "projectedType",
        "liquidPhaseSpeciesCount", "liquidPhaseReferenceCellMass", "numCells",
        "filterLambda", "rawFillSum", "filteredFillSum",
        "conservationRelativeError", "filterDeltaRms",
        "maskFilteredMismatchCells", "interfaceFaces", "halfIsoBracketFraction",
        "halfIsoThetaMean", "halfIsoThetaStd", "normalValidFraction",
        "normalOutwardFraction", "normalFaceAlignmentMean", "rawBuildSeconds",
        "filterSeconds", "auditKernelSeconds", "residentBytes", "geometryDefinition",
    }
    missing = required.difference(rows[0])
    if missing:
        raise RuntimeError(f"audit missing columns: {sorted(missing)}")

    max_conservation_error = 0.0
    max_mismatch_fraction = 0.0
    min_half_bracket = 1.0
    min_normal_valid = 1.0
    max_filter_delta_rms = 0.0
    raw_build_total = 0.0
    filter_total = 0.0
    audit_total = 0.0
    definition_ok = True

    for row in rows:
        liquid_species = int(row["liquidPhaseSpeciesCount"])
        ref_mass = finite(row, "liquidPhaseReferenceCellMass")
        cells = int(row["numCells"])
        lam = finite(row, "filterLambda")
        raw_sum = finite(row, "rawFillSum")
        filtered_sum = finite(row, "filteredFillSum")
        conservation = finite(row, "conservationRelativeError")
        delta_rms = finite(row, "filterDeltaRms")
        mismatch = int(row["maskFilteredMismatchCells"])
        faces = int(row["interfaceFaces"])
        half_bracket = finite(row, "halfIsoBracketFraction")
        half_mean = finite(row, "halfIsoThetaMean")
        half_std = finite(row, "halfIsoThetaStd")
        normal_valid = finite(row, "normalValidFraction")
        normal_outward = finite(row, "normalOutwardFraction")
        normal_alignment = finite(row, "normalFaceAlignmentMean")
        raw_seconds = finite(row, "rawBuildSeconds")
        filter_seconds = finite(row, "filterSeconds")
        audit_seconds = finite(row, "auditKernelSeconds")
        resident_bytes = int(row["residentBytes"])

        if liquid_species <= 0 or not (ref_mass > 0.0):
            raise RuntimeError("invalid liquid phase definition")
        if cells <= 0 or resident_bytes < 2 * cells * 8:
            raise RuntimeError("invalid resident geometry storage")
        if not (0.0 <= lam <= 0.25):
            raise RuntimeError(f"filterLambda outside conservative stability range: {lam}")
        if raw_sum < 0.0 or filtered_sum < 0.0:
            raise RuntimeError("negative global phase fill")
        if min(conservation, delta_rms, half_std, raw_seconds, filter_seconds, audit_seconds) < 0.0:
            raise RuntimeError("negative resident geometry diagnostic")
        if faces <= 0:
            raise RuntimeError(f"step {row['step']}: no interface faces")
        for value, name in (
            (half_bracket, "halfIsoBracketFraction"),
            (normal_valid, "normalValidFraction"),
            (normal_outward, "normalOutwardFraction"),
        ):
            bounded_fraction(value, name)
        if half_bracket > 0.0 and not (-1.0e-12 <= half_mean <= 1.0 + 1.0e-12):
            raise RuntimeError(f"halfIsoThetaMean outside [0,1]: {half_mean}")
        if normal_valid > 0.0 and not (-1.0 - 1.0e-12 <= normal_alignment <= 1.0 + 1.0e-12):
            raise RuntimeError(f"normalFaceAlignmentMean outside [-1,1]: {normal_alignment}")

        max_conservation_error = max(max_conservation_error, conservation)
        max_mismatch_fraction = max(max_mismatch_fraction, mismatch / max(1, cells))
        min_half_bracket = min(min_half_bracket, half_bracket)
        min_normal_valid = min(min_normal_valid, normal_valid)
        max_filter_delta_rms = max(max_filter_delta_rms, delta_rms)
        raw_build_total += raw_seconds
        filter_total += filter_seconds
        audit_total += audit_seconds
        definition_ok = definition_ok and row["geometryDefinition"].startswith(
            "raw=sum_liquid_mass/sum_liquid_reference_mass"
        )

    pass_like = definition_ok and max_conservation_error <= args.conservation_tolerance
    first = rows[0]
    last = rows[-1]
    report = {
        "status": "PASS-like" if pass_like else "FAIL-like",
        "rows": len(rows),
        "firstStep": int(first["step"]),
        "lastStep": int(last["step"]),
        "filterLambda": float(first["filterLambda"]),
        "geometryDefinitionOK": definition_ok,
        "maxConservationRelativeError": max_conservation_error,
        "maxMaskFilteredMismatchFractionOfGrid": max_mismatch_fraction,
        "minHalfIsoBracketFraction": min_half_bracket,
        "minNormalValidFraction": min_normal_valid,
        "maxFilterDeltaRms": max_filter_delta_rms,
        "rawBuildSecondsTotalOnAuditSteps": raw_build_total,
        "filterSecondsTotalOnAuditSteps": filter_total,
        "auditKernelSecondsTotal": audit_total,
        "meanRawBuildSeconds": raw_build_total / len(rows),
        "meanFilterSeconds": filter_total / len(rows),
        "residentBytes": int(first["residentBytes"]),
        "firstRawFillSum": float(first["rawFillSum"]),
        "lastRawFillSum": float(last["rawFillSum"]),
        "firstFilteredFillSum": float(first["filteredFillSum"]),
        "lastFilteredFillSum": float(last["filteredFillSum"]),
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")

    print(
        "[0493x6c-analysis] "
        f"status={report['status']} rows={report['rows']} "
        f"steps={report['firstStep']}..{report['lastStep']} "
        f"conservationMax={report['maxConservationRelativeError']:.3e} "
        f"halfBracketMin={report['minHalfIsoBracketFraction']:.3f} "
        f"filterDeltaRmsMax={report['maxFilterDeltaRms']:.3e} "
        f"rawMean={report['meanRawBuildSeconds']:.3e}s "
        f"filterMean={report['meanFilterSeconds']:.3e}s "
        f"resident={report['residentBytes']}B"
    )
    return 0 if pass_like else 1


if __name__ == "__main__":
    raise SystemExit(main())

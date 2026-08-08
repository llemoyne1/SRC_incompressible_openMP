#!/usr/bin/env python3
"""Validate the diagnostic-only 0493x6b phase-interface geometry scaffold."""

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
    args = parser.parse_args()

    if not args.audit.exists():
        raise RuntimeError(f"missing 0493x6b audit: {args.audit}")
    with args.audit.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise RuntimeError("empty 0493x6b geometry audit")

    required = {
        "step", "time", "projectedSpeciesIndex", "projectedType",
        "liquidPhaseSpeciesCount", "liquidPhaseReferenceCellMass",
        "supportIsoFill", "maskActiveCells", "phaseFillActiveCells",
        "maskPhaseMismatchCells", "interfaceFaces", "insideFillMean",
        "outsideFillMean", "supportThetaValidFraction", "supportThetaMean",
        "supportThetaStd", "supportThetaMidpointRms",
        "supportThetaNearCellFraction", "supportThetaNearExteriorFraction",
        "halfIsoBracketFraction", "halfIsoThetaMean", "halfIsoThetaStd",
        "normalValidFraction", "normalOutwardFraction",
        "normalFaceAlignmentMean", "diagnosticSeconds", "geometryDefinition",
    }
    missing = required.difference(rows[0])
    if missing:
        raise RuntimeError(f"audit missing columns: {sorted(missing)}")

    max_mismatch_fraction = 0.0
    min_half_bracket_fraction = 1.0
    min_normal_valid_fraction = 1.0
    total_diagnostic_seconds = 0.0
    max_diagnostic_seconds = 0.0
    max_interface_faces = 0
    min_interface_faces: int | None = None
    all_definition_ok = True

    for row in rows:
        ref_mass = finite(row, "liquidPhaseReferenceCellMass")
        iso = finite(row, "supportIsoFill")
        mask_active = int(row["maskActiveCells"])
        phase_active = int(row["phaseFillActiveCells"])
        mismatch = int(row["maskPhaseMismatchCells"])
        faces = int(row["interfaceFaces"])
        liquid_species = int(row["liquidPhaseSpeciesCount"])
        inside_fill = finite(row, "insideFillMean")
        outside_fill = finite(row, "outsideFillMean")
        support_valid = finite(row, "supportThetaValidFraction")
        theta_mean = finite(row, "supportThetaMean")
        theta_std = finite(row, "supportThetaStd")
        theta_mid_rms = finite(row, "supportThetaMidpointRms")
        near_cell = finite(row, "supportThetaNearCellFraction")
        near_exterior = finite(row, "supportThetaNearExteriorFraction")
        half_bracket = finite(row, "halfIsoBracketFraction")
        half_mean = finite(row, "halfIsoThetaMean")
        half_std = finite(row, "halfIsoThetaStd")
        normal_valid = finite(row, "normalValidFraction")
        normal_outward = finite(row, "normalOutwardFraction")
        normal_alignment = finite(row, "normalFaceAlignmentMean")
        diagnostic_seconds = finite(row, "diagnosticSeconds")

        if not (ref_mass > 0.0 and liquid_species > 0):
            raise RuntimeError("invalid liquid phase reference in 0493x6b audit")
        if not (0.0 <= iso <= 1.0):
            raise RuntimeError(f"supportIsoFill outside [0,1]: {iso}")
        if min(mask_active, phase_active, mismatch, faces) < 0:
            raise RuntimeError("negative count in 0493x6b audit")
        if faces <= 0:
            raise RuntimeError(f"step {row['step']}: no liquid-exterior interface faces")
        if inside_fill < 0.0 or outside_fill < 0.0:
            raise RuntimeError("negative phase fill statistic")
        if min(theta_std, theta_mid_rms, half_std, diagnostic_seconds) < 0.0:
            raise RuntimeError("negative geometry dispersion/time statistic")

        for value, name in (
            (support_valid, "supportThetaValidFraction"),
            (near_cell, "supportThetaNearCellFraction"),
            (near_exterior, "supportThetaNearExteriorFraction"),
            (half_bracket, "halfIsoBracketFraction"),
            (normal_valid, "normalValidFraction"),
            (normal_outward, "normalOutwardFraction"),
        ):
            bounded_fraction(value, name)

        if support_valid > 0.0 and not (-1.0e-12 <= theta_mean <= 1.0 + 1.0e-12):
            raise RuntimeError(f"support theta mean outside [0,1]: {theta_mean}")
        if half_bracket > 0.0 and not (-1.0e-12 <= half_mean <= 1.0 + 1.0e-12):
            raise RuntimeError(f"half-iso theta mean outside [0,1]: {half_mean}")
        if normal_valid > 0.0 and not (-1.0 - 1.0e-12 <= normal_alignment <= 1.0 + 1.0e-12):
            raise RuntimeError(f"normal-face alignment outside [-1,1]: {normal_alignment}")

        active_scale = max(1, mask_active, phase_active)
        max_mismatch_fraction = max(max_mismatch_fraction, mismatch / active_scale)
        min_half_bracket_fraction = min(min_half_bracket_fraction, half_bracket)
        min_normal_valid_fraction = min(min_normal_valid_fraction, normal_valid)
        total_diagnostic_seconds += diagnostic_seconds
        max_diagnostic_seconds = max(max_diagnostic_seconds, diagnostic_seconds)
        max_interface_faces = max(max_interface_faces, faces)
        min_interface_faces = faces if min_interface_faces is None else min(min_interface_faces, faces)
        all_definition_ok = all_definition_ok and row["geometryDefinition"].startswith(
            "phaseFill=sum_liquid_mass/sum_liquid_reference_mass"
        )

    first = rows[0]
    last = rows[-1]
    pass_like = all_definition_ok
    report = {
        "status": "PASS-like" if pass_like else "FAIL-like",
        "rows": len(rows),
        "firstStep": int(first["step"]),
        "lastStep": int(last["step"]),
        "geometryDefinitionOK": all_definition_ok,
        "interfaceFacesMin": min_interface_faces,
        "interfaceFacesMax": max_interface_faces,
        "maxMaskPhaseMismatchFraction": max_mismatch_fraction,
        "minHalfIsoBracketFraction": min_half_bracket_fraction,
        "minNormalValidFraction": min_normal_valid_fraction,
        "firstSupportThetaMean": float(first["supportThetaMean"]),
        "lastSupportThetaMean": float(last["supportThetaMean"]),
        "firstHalfIsoThetaMean": float(first["halfIsoThetaMean"]),
        "lastHalfIsoThetaMean": float(last["halfIsoThetaMean"]),
        "totalGeometryDiagnosticSeconds": total_diagnostic_seconds,
        "meanGeometryDiagnosticSeconds": total_diagnostic_seconds / len(rows),
        "maxGeometryDiagnosticSeconds": max_diagnostic_seconds,
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")

    print(
        "[0493x6b-analysis] "
        f"status={report['status']} rows={report['rows']} "
        f"steps={report['firstStep']}..{report['lastStep']} "
        f"faces={report['interfaceFacesMin']}..{report['interfaceFacesMax']} "
        f"maskPhaseMismatchMax={report['maxMaskPhaseMismatchFraction']:.3e} "
        f"halfBracketMin={report['minHalfIsoBracketFraction']:.3f} "
        f"thetaHalf={report['firstHalfIsoThetaMean']:.4f}->{report['lastHalfIsoThetaMean']:.4f} "
        f"diagTotal={report['totalGeometryDiagnosticSeconds']:.4f}s "
        f"diagMean={report['meanGeometryDiagnosticSeconds']:.3e}s"
    )
    return 0 if pass_like else 1


if __name__ == "__main__":
    raise SystemExit(main())

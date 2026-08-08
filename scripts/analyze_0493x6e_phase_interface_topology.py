#!/usr/bin/env python3
"""Validate and summarize the 0493x6e alpha=0.5 interface topology audit."""

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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    args = parser.parse_args()

    if not args.audit.exists():
        raise RuntimeError(f"missing x6e/x6c geometry audit: {args.audit}")
    with args.audit.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise RuntimeError("empty x6e geometry audit")

    required = {
        "step",
        "phaseInterfaceTopologyEnabled",
        "alphaHalfCrossingFaces",
        "alphaHalfCrossingActiveActiveFaces",
        "alphaHalfCrossingActiveInactiveFaces",
        "alphaHalfCrossingInactiveInactiveFaces",
        "alphaHalfCrossingAIActiveLiquidSideFaces",
        "alphaHalfCrossingAIActiveExteriorSideFaces",
        "alphaHalfThetaMin",
        "alphaHalfThetaMean",
        "alphaHalfThetaStd",
        "alphaHalfThetaMax",
        "cutFaceGeometryEnabled",
        "cutFaceGeometricFaces",
        "cutFaceSmallThetaFallbackFaces",
        "auditKernelSeconds",
    }
    missing = required.difference(rows[0])
    if missing:
        raise RuntimeError(f"audit missing x6e columns: {sorted(missing)}")

    all_enabled = True
    all_cutface_enabled = True
    min_crossings = math.inf
    max_crossings = 0
    max_aa_fraction = 0.0
    max_ai_fraction = 0.0
    max_ii_fraction = 0.0
    max_reversed_ai_fraction = 0.0
    min_x6d_coverage = 1.0
    max_x6d_coverage = 0.0
    global_theta_min = 1.0
    global_theta_max = 0.0
    max_audit_seconds = 0.0
    mean_audit_seconds = 0.0

    per_step: list[dict[str, float | int]] = []

    for row in rows:
        step = int(row["step"])
        enabled = int(row["phaseInterfaceTopologyEnabled"])
        cut_enabled = int(row["cutFaceGeometryEnabled"])
        total = int(row["alphaHalfCrossingFaces"])
        aa = int(row["alphaHalfCrossingActiveActiveFaces"])
        ai = int(row["alphaHalfCrossingActiveInactiveFaces"])
        ii = int(row["alphaHalfCrossingInactiveInactiveFaces"])
        ai_liquid = int(row["alphaHalfCrossingAIActiveLiquidSideFaces"])
        ai_exterior = int(row["alphaHalfCrossingAIActiveExteriorSideFaces"])
        geometric = int(row["cutFaceGeometricFaces"])
        small = int(row["cutFaceSmallThetaFallbackFaces"])
        theta_min = finite(row, "alphaHalfThetaMin")
        theta_mean = finite(row, "alphaHalfThetaMean")
        theta_std = finite(row, "alphaHalfThetaStd")
        theta_max = finite(row, "alphaHalfThetaMax")
        audit_seconds = finite(row, "auditKernelSeconds")

        if total <= 0:
            raise RuntimeError(f"step {step}: no alpha=0.5 crossing faces")
        if aa + ai + ii != total:
            raise RuntimeError(
                f"step {step}: topology partition mismatch: "
                f"AA={aa} AI={ai} II={ii} total={total}"
            )
        if ai_liquid + ai_exterior != ai:
            raise RuntimeError(
                f"step {step}: active-inactive orientation partition mismatch: "
                f"liquid={ai_liquid} exterior={ai_exterior} AI={ai}"
            )
        # In the x6e runner x6d is active.  Every active-inactive crossing with
        # the active cell on the liquid side is either accepted by x6d or
        # rejected only by the theta guard.
        if cut_enabled == 1 and geometric + small != ai_liquid:
            raise RuntimeError(
                f"step {step}: x6d coverage accounting mismatch: "
                f"geometric={geometric} smallTheta={small} "
                f"AI-liquid={ai_liquid}"
            )
        if not (0.0 <= theta_min <= theta_mean <= theta_max <= 1.0 + 2e-9):
            raise RuntimeError(
                f"step {step}: invalid alpha-half theta range "
                f"min={theta_min} mean={theta_mean} max={theta_max}"
            )
        if theta_std < 0.0:
            raise RuntimeError(f"step {step}: negative theta std")

        aa_frac = aa / total
        ai_frac = ai / total
        ii_frac = ii / total
        reversed_frac = ai_exterior / total
        coverage = geometric / total

        min_crossings = min(min_crossings, total)
        max_crossings = max(max_crossings, total)
        max_aa_fraction = max(max_aa_fraction, aa_frac)
        max_ai_fraction = max(max_ai_fraction, ai_frac)
        max_ii_fraction = max(max_ii_fraction, ii_frac)
        max_reversed_ai_fraction = max(max_reversed_ai_fraction, reversed_frac)
        min_x6d_coverage = min(min_x6d_coverage, coverage)
        max_x6d_coverage = max(max_x6d_coverage, coverage)
        global_theta_min = min(global_theta_min, theta_min)
        global_theta_max = max(global_theta_max, theta_max)
        max_audit_seconds = max(max_audit_seconds, audit_seconds)
        mean_audit_seconds += audit_seconds
        all_enabled = all_enabled and enabled == 1
        all_cutface_enabled = all_cutface_enabled and cut_enabled == 1

        per_step.append(
            {
                "step": step,
                "crossingFaces": total,
                "activeActiveFraction": aa_frac,
                "activeInactiveFraction": ai_frac,
                "inactiveInactiveFraction": ii_frac,
                "reversedActiveInactiveFraction": reversed_frac,
                "x6dGeometricCoverageFraction": coverage,
            }
        )

    mean_audit_seconds /= len(rows)
    first = per_step[0]
    last = per_step[-1]
    pass_like = all_enabled and all_cutface_enabled and max_crossings > 0

    report = {
        "status": "PASS-like" if pass_like else "FAIL-like",
        "rows": len(rows),
        "firstStep": first["step"],
        "lastStep": last["step"],
        "minAlphaHalfCrossingFaces": int(min_crossings),
        "maxAlphaHalfCrossingFaces": max_crossings,
        "maxActiveActiveCrossingFraction": max_aa_fraction,
        "maxActiveInactiveCrossingFraction": max_ai_fraction,
        "maxInactiveInactiveCrossingFraction": max_ii_fraction,
        "maxReversedActiveInactiveFraction": max_reversed_ai_fraction,
        "minX6dGeometricCoverageOfPhysicalInterface": min_x6d_coverage,
        "maxX6dGeometricCoverageOfPhysicalInterface": max_x6d_coverage,
        "globalAlphaHalfThetaMin": global_theta_min,
        "globalAlphaHalfThetaMax": global_theta_max,
        "first": first,
        "last": last,
        "auditKernelSecondsMean": mean_audit_seconds,
        "auditKernelSecondsMax": max_audit_seconds,
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")

    print(
        "[0493x6e-analysis] "
        f"status={report['status']} rows={report['rows']} "
        f"steps={report['firstStep']}..{report['lastStep']} "
        f"crossings={report['minAlphaHalfCrossingFaces']}.."
        f"{report['maxAlphaHalfCrossingFaces']} "
        f"AAmax={report['maxActiveActiveCrossingFraction']:.3f} "
        f"AImax={report['maxActiveInactiveCrossingFraction']:.3f} "
        f"IImax={report['maxInactiveInactiveCrossingFraction']:.3f} "
        f"x6dCoverage={report['minX6dGeometricCoverageOfPhysicalInterface']:.3f}.."
        f"{report['maxX6dGeometricCoverageOfPhysicalInterface']:.3f} "
        f"reversedAImax={report['maxReversedActiveInactiveFraction']:.3e} "
        f"auditMean={report['auditKernelSecondsMean']:.3e}s"
    )
    return 0 if pass_like else 1


if __name__ == "__main__":
    raise SystemExit(main())

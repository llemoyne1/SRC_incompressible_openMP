#!/usr/bin/env python3
"""Compare origin and optimized 0162 mono-configuration validation runs.

The script compares final-row diagnostics written by
scripts/run_validation_mono_config_0162.sh.  It intentionally ignores timing
columns for pass/fail, but reports speedups separately.
"""
from __future__ import annotations

import argparse
import csv
import math
import os
from typing import Dict, Iterable, List, Tuple

TIMING_FIELDS = {"elapsed_s", "user_s", "sys_s", "wallTime"}
IDENTITY_FIELDS = {
    "Np", "nFluidParticles", "nInactiveParticles", "nLatentParticles", "minN", "maxN",
    "hitsImmersed", "inletReservoirDeleted", "inletBackflowDeleted", "outletParticlesDeleted",
    "inletParticlesInserted", "inletNetParticleDelta", "q6Applied", "q6Converged", "q6Iterations",
    "q6OpenBoundaryEnabled", "q6ImmersedSolidFluidCells", "q6ImmersedSolidSolidCells",
    "q6ImmersedSolidCutCells", "q6ImmersedSolidActiveCutCells", "resampComputed",
    "resampTransferPairs", "resampSelectedDonorParticles", "resampExtractionApplyRoleChanges",
    "resampInsertionApplyRoleChanges", "resampRemapApplied", "resampRemapCellsRemapped",
    "resampMassGuardApplied", "resampMassGuardCellsGuarded", "resampPopulationGuardApplied",
    "resampPopulationGuardCellsSplit", "resampPopulationGuardCellsExtracted",
    "resampPopulationGuardSplitParticlesCreated", "resampPopulationGuardExtractedParticles",
    "capacityResponseEnabled", "capacityResponseComputed", "capacityVirialKickApplied",
}
# These can differ by reduction order but should remain extremely close.
REL_TOL = 1.0e-6
ABS_TOL = 1.0e-10
# Some diagnostics are near solver tolerances or accumulated reductions; use a
# pragmatic validation threshold rather than bitwise equality.
FIELD_REL_TOL = {
    "q6ResidualRel": 1.0e-3,
    "q6DivBeforeRms": 1.0e-6,
    "q6DivAfterProjectedFluxRms": 1.0e-3,
    "q6DivAfterCellVelocityRms": 1.0e-3,
    "q6CorrectionVelocityRms": 1.0e-6,
    "q6OpenBoundaryFluxBalance": 1.0e-5,
    "q6OpenBoundaryMeanDivergence": 1.0e-5,
    "q6ImmersedSolidLeakProjectedFluxRms": 1.0e-3,
    "q6ImmersedSolidLeakCellClosedProjectedFluxRms": 1.0e-3,
    "q6ImmersedSolidLeakCutProjectedFluxRms": 1.0e-3,
    "capacityVirialMomentumResidualBeforeCorrection": 1.0e-5,
}
FIELD_ABS_TOL = {
    "q6ResidualRel": 1.0e-12,
    "q6DivAfterProjectedFluxRms": 1.0e-12,
    "q6DivAfterCellVelocityRms": 1.0e-12,
    "q6OpenBoundaryFluxBalance": 1.0e-12,
    "q6OpenBoundaryMeanDivergence": 1.0e-12,
    "capacityVirialMomentumResidualBeforeCorrection": 1.0e-12,
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Compare origin and optimized validation_summary_0162.csv files.")
    p.add_argument("--origin", required=True, help="Origin run root or validation_summary_0162.csv")
    p.add_argument("--optimized", required=True, help="Optimized run root or validation_summary_0162.csv")
    p.add_argument("--out", default="validation_compare_0162.csv")
    p.add_argument("--summary-out", default="validation_compare_summary_0162.csv")
    p.add_argument("--rel-tol", type=float, default=REL_TOL)
    p.add_argument("--abs-tol", type=float, default=ABS_TOL)
    return p.parse_args()


def summary_path(path: str) -> str:
    if os.path.isdir(path):
        return os.path.join(path, "validation_summary_0162.csv")
    return path


def read_summary(path: str) -> Dict[str, Dict[str, str]]:
    fn = summary_path(path)
    with open(fn, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"empty summary file: {fn}")
    out: Dict[str, Dict[str, str]] = {}
    for r in rows:
        case = r.get("case", "")
        if not case:
            raise SystemExit(f"row without case in {fn}")
        out[case] = r
    return out


def to_float(text: str) -> float | None:
    if text is None or text == "":
        return None
    try:
        return float(text)
    except ValueError:
        return None


def close_enough(metric: str, a: str, b: str, rel_default: float, abs_default: float) -> Tuple[str, float | str, float | str, float | str]:
    fa = to_float(a)
    fb = to_float(b)
    if metric in TIMING_FIELDS:
        if fa is not None and fb is not None:
            return "timing", fb - fa, (fb - fa) / max(abs(fa), 1e-300), ""
        return "timing", "", "", ""
    if metric in IDENTITY_FIELDS:
        status = "pass" if a == b else "fail"
        if fa is not None and fb is not None:
            return status, fb - fa, (fb - fa) / max(abs(fa), 1e-300), 0.0
        return status, "", "", 0.0
    if fa is None or fb is None:
        status = "pass" if a == b else "missing_or_non_numeric"
        return status, "", "", ""
    abs_diff = abs(fb - fa)
    rel_diff = abs_diff / max(abs(fa), abs(fb), 1e-300)
    rel_tol = FIELD_REL_TOL.get(metric, rel_default)
    abs_tol = FIELD_ABS_TOL.get(metric, abs_default)
    status = "pass" if (abs_diff <= abs_tol or rel_diff <= rel_tol) else "fail"
    return status, fb - fa, rel_diff, rel_tol


def main() -> int:
    args = parse_args()
    origin = read_summary(args.origin)
    optimized = read_summary(args.optimized)
    cases = sorted(set(origin) | set(optimized))
    rows: List[Dict[str, object]] = []
    case_fail_counts: Dict[str, int] = {c: 0 for c in cases}
    case_metric_counts: Dict[str, int] = {c: 0 for c in cases}
    speed_rows: List[Dict[str, object]] = []

    for case in cases:
        if case not in origin or case not in optimized:
            rows.append({
                "case": case, "metric": "__case_presence__", "origin": "present" if case in origin else "missing",
                "optimized": "present" if case in optimized else "missing", "status": "fail",
                "delta": "", "rel_diff_abs": "", "tolerance": "",
            })
            case_fail_counts[case] += 1
            continue
        ro = origin[case]
        rp = optimized[case]
        metrics = [m for m in ro.keys() if m not in {"runTag", "case"}]
        for m in metrics:
            status, delta, rel, tol = close_enough(m, ro.get(m, ""), rp.get(m, ""), args.rel_tol, args.abs_tol)
            rows.append({
                "case": case,
                "metric": m,
                "origin": ro.get(m, ""),
                "optimized": rp.get(m, ""),
                "delta": delta,
                "rel_diff_abs": rel,
                "tolerance": tol,
                "status": status,
            })
            if status not in {"pass", "timing"}:
                case_fail_counts[case] += 1
            if status != "timing":
                case_metric_counts[case] += 1
        o_wall = to_float(ro.get("wallTime", ""))
        p_wall = to_float(rp.get("wallTime", ""))
        o_elapsed = to_float(ro.get("elapsed_s", ""))
        p_elapsed = to_float(rp.get("elapsed_s", ""))
        speed_rows.append({
            "case": case,
            "origin_wallTime": o_wall if o_wall is not None else "",
            "optimized_wallTime": p_wall if p_wall is not None else "",
            "wall_speedup_origin_over_optimized": (o_wall / p_wall) if (o_wall and p_wall and p_wall > 0.0) else "",
            "origin_elapsed_s": o_elapsed if o_elapsed is not None else "",
            "optimized_elapsed_s": p_elapsed if p_elapsed is not None else "",
            "elapsed_speedup_origin_over_optimized": (o_elapsed / p_elapsed) if (o_elapsed and p_elapsed and p_elapsed > 0.0) else "",
            "failed_metrics": case_fail_counts[case],
            "compared_metrics": case_metric_counts[case],
            "verdict": "PASS" if case_fail_counts[case] == 0 else "FAIL",
        })

    with open(args.out, "w", newline="") as f:
        fieldnames = ["case", "metric", "origin", "optimized", "delta", "rel_diff_abs", "tolerance", "status"]
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(r)

    with open(args.summary_out, "w", newline="") as f:
        fieldnames = [
            "case", "origin_wallTime", "optimized_wallTime", "wall_speedup_origin_over_optimized",
            "origin_elapsed_s", "optimized_elapsed_s", "elapsed_speedup_origin_over_optimized",
            "failed_metrics", "compared_metrics", "verdict",
        ]
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in speed_rows:
            w.writerow(r)

    failures = sum(case_fail_counts.values())
    print(f"Wrote {args.out}")
    print(f"Wrote {args.summary_out}")
    if failures:
        print(f"Validation comparison: FAIL ({failures} failed metric comparisons)")
        return 1
    print("Validation comparison: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Compare existing runtime diagnostics between reference and 0315b runs.

Input: a run manifest produced by run_active_prefix_validation_0315b.sh.
The script compares only existing CSV diagnostics, principally
output/summary_runtime.csv. It does not require any development diagnostics to be
compiled or enabled in the solver.
"""
from __future__ import annotations

import argparse
import csv
import math
import re
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

# Columns selected to cover conservation, support, boundary events, thermostat,
# Q6, resampling and virial/capacity at a high level, without exploding into the
# full development diagnostic catalogue.
CORE_COLUMNS = [
    "step", "time", "Np", "nFluidParticles", "nInactiveParticles", "nLatentParticles",
    "totalMass", "Px", "Py", "meanVx", "meanVy", "meanKinetic", "kBTEstimate",
    "meanParticleSpeed", "maxParticleSpeed", "maxParticleAbsVx", "maxParticleAbsVy",
    "fluidXMin", "fluidXMax", "fluidYMin", "fluidYMax", "fluidArea",
    "meanPhysicalDensity", "meanN", "stdN", "minN", "maxN",
]
BOUNDARY_COLUMNS = [
    "hitsLeft", "hitsRight", "hitsBottom", "hitsTop", "hitsImmersed",
    "inletHardReservoirEnabled", "inletReservoirCells", "inletReservoirTargetParticles",
    "inletReservoirDeleted", "inletBackflowDeleted", "outletParticlesDeleted",
    "inletParticlesInserted", "inletNetParticleDelta", "inletReservoirMeanN",
    "inletReservoirStdN", "inletReservoirMinN", "inletReservoirMaxN",
    "inletReservoirEmptyFraction", "inletMeanUx", "inletMeanUy", "inletKBT",
    "virtualParticleCount", "virtualParticleEquivalent", "virtualMass",
    "virtualMomentumX", "virtualMomentumY",
]
THERMOSTAT_COLUMNS = [
    "thermostatApplied", "thermostatCells", "thermostatParticles",
    "thermostatKBTBefore", "thermostatKBTAfter", "thermostatScaleMean",
    "thermostatScaleMin", "thermostatScaleMax",
]
Q6_COLUMNS = [
    "q6Applied", "q6ProjectionStrength", "q6Converged", "q6Iterations", "q6EmptyCells",
    "q6ResidualRel", "q6DivBeforeRms", "q6DivBeforeMaxAbs",
    "q6DivAfterProjectedFluxRms", "q6DivAfterProjectedFluxMaxAbs",
    "q6DivAfterCellVelocityRms", "q6DivAfterCellVelocityMaxAbs",
    "q6CorrectionVelocityRms", "q6CorrectionVelocityMaxAbs",
    "q6OpenBoundaryEnabled", "q6OpenBoundaryFluxBalance",
    "q6MomentumCorrectionVx", "q6MomentumCorrectionVy", "q6MomentumResidualBeforeCorrection",
]
RESAMP_COLUMNS = [
    "resampComputed", "resampNFluid", "resampNLatent", "resampNInactive",
    "resampNonEmptyCells", "resampEmptyCells", "resampMeanN", "resampStdN",
    "resampMinN", "resampMaxN", "resampTotalMass", "resampMeanMass",
    "resampStdMass", "resampMinMass", "resampMaxMass", "resampTargetCellMass",
    "resampMRelRms", "resampMRelMaxAbs", "resampParticleMassMean",
    "resampParticleMassStd", "resampParticleMassRelStd", "resampParticleMassMin",
    "resampParticleMassMax", "resampMeanUx", "resampMeanUy", "resampCellUxRms",
    "resampCellUyRms", "resampActiveCells", "resampWetCells", "resampDryCells",
    "resampPoorCells", "resampRichCells", "resampEmptyWetCells",
    "resampOccupiedDryCells", "resampTransferPairs", "resampPlannedTransferMass",
    "resampExtractionApplied", "resampExtractionApplyRoleChanges",
    "resampInsertionApplied", "resampInsertionApplyRoleChanges",
    "resampRemapApplied", "resampRemapParticlesRemapped", "resampRemapMassDelta",
    "resampThermalRenormApplied", "resampThermalRenormParticlesRenormalized",
    "resampMassGuardApplied", "resampMassGuardParticlesAdjusted",
    "resampPopulationGuardApplied", "resampPopulationGuardWetCellsConsidered",
    "resampPopulationGuardUnderfullCells", "resampPopulationGuardOverfullCells",
    "resampPopulationGuardCellsSplit", "resampPopulationGuardCellsExtracted",
    "resampPopulationGuardSplitParticlesCreated", "resampPopulationGuardExtractedParticles",
    "resampPopulationGuardSkippedNoFreeSlots", "resampPopulationGuardFreeSlotsBefore",
    "resampPopulationGuardFreeSlotsAfter", "resampPopulationGuardActiveParticleDelta",
    "resampPoolBuilt", "resampPoolStorageSlots", "resampPoolFreeSlots",
    "resampPoolLatentSlots", "resampPoolFluidSlots", "resampPoolFreeSlotFraction",
]
CAPACITY_COLUMNS = [
    "capacityResponseEnabled", "capacityResponseComputed", "capacityVirialKickApplied",
    "capacityReferenceCells", "capacityReferenceMass", "capacityTotalMass",
    "capacityOverfillMass", "capacityOverfillRatio", "capacityQ6ProjectionStrengthEffective",
    "capacityMassRemapTargetCellMassEffective", "capacityVirialKEffective",
    "capacityVirialPressureMean", "capacityVirialPressureRms",
    "capacityVirialPressureMin", "capacityVirialPressureMax",
    "capacityVirialKickVelocityRms", "capacityVirialKickVelocityMaxAbs",
    "capacityVirialMomentumResidualBeforeCorrection",
    "capacityWallLoadComputed", "capacityWallPressureTotalMeanAll",
    "capacityWallForceTotalX", "capacityWallForceTotalY",
]
SELECTED_COLUMNS = CORE_COLUMNS + BOUNDARY_COLUMNS + THERMOSTAT_COLUMNS + Q6_COLUMNS + RESAMP_COLUMNS + CAPACITY_COLUMNS
EXACT_COLUMNS = {
    "step", "Np", "nFluidParticles", "nInactiveParticles", "nLatentParticles",
    "minN", "maxN", "hitsLeft", "hitsRight", "hitsBottom", "hitsTop", "hitsImmersed",
    "inletHardReservoirEnabled", "inletReservoirCells", "inletReservoirTargetParticles",
    "inletReservoirDeleted", "inletBackflowDeleted", "outletParticlesDeleted",
    "inletParticlesInserted", "inletNetParticleDelta", "thermostatApplied", "thermostatCells",
    "thermostatParticles", "q6Applied", "q6Converged", "q6Iterations", "resampComputed",
    "resampNFluid", "resampNLatent", "resampNInactive", "resampMinN", "resampMaxN",
    "resampPopulationGuardApplied", "resampPopulationGuardCellsSplit",
    "resampPopulationGuardCellsExtracted", "resampPopulationGuardSplitParticlesCreated",
    "resampPopulationGuardExtractedParticles", "resampPoolStorageSlots", "resampPoolFreeSlots",
    "resampPoolLatentSlots", "resampPoolFluidSlots", "capacityResponseEnabled",
    "capacityResponseComputed", "capacityVirialKickApplied", "capacityReferenceCells",
}


def read_csv(path: Path) -> List[Dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def parse_float(text: str) -> float:
    if text is None or text == "":
        return math.nan
    try:
        return float(text)
    except Exception:
        return math.nan


def rel_err(a: float, b: float) -> float:
    scale = max(1.0, abs(a), abs(b))
    return abs(b - a) / scale


def compare_rows(ref_rows: Sequence[Dict[str, str]], test_rows: Sequence[Dict[str, str]], columns: Iterable[str], abs_tol: float, rel_tol: float) -> Tuple[List[Dict[str, object]], int, int]:
    details: List[Dict[str, object]] = []
    if not ref_rows or not test_rows:
        return details, 0, 1

    ref_by_step = {r.get("step", str(i)): r for i, r in enumerate(ref_rows)}
    test_by_step = {r.get("step", str(i)): r for i, r in enumerate(test_rows)}
    common_steps = sorted(set(ref_by_step) & set(test_by_step), key=lambda x: parse_float(x))
    failed = 0
    compared = 0

    if len(ref_rows) != len(test_rows) or len(common_steps) != len(ref_rows):
        failed += 1
        details.append({
            "column": "__row_alignment__", "maxAbsDiff": "", "maxRelDiff": "",
            "worstStep": "", "refFinal": len(ref_rows), "testFinal": len(test_rows),
            "comparedSteps": len(common_steps), "verdict": "FAIL",
            "note": "row count or step alignment differs",
        })

    for col in columns:
        if col not in ref_rows[0] or col not in test_rows[0]:
            continue
        max_abs = 0.0
        max_rel = 0.0
        worst_step = ""
        local_failed = False
        local_compared = 0
        ref_final = ""
        test_final = ""
        for step in common_steps:
            rr = ref_by_step[step]
            tr = test_by_step[step]
            rv = parse_float(rr.get(col, ""))
            tv = parse_float(tr.get(col, ""))
            if math.isnan(rv) and math.isnan(tv):
                continue
            if math.isnan(rv) != math.isnan(tv):
                local_failed = True
                worst_step = step
                max_abs = math.inf
                max_rel = math.inf
                continue
            ad = abs(tv - rv)
            rd = rel_err(rv, tv)
            if ad > max_abs or rd > max_rel:
                max_abs = max(max_abs, ad)
                max_rel = max(max_rel, rd)
                worst_step = step
            tol_abs = 0.0 if col in EXACT_COLUMNS else abs_tol
            tol_rel = 0.0 if col in EXACT_COLUMNS else rel_tol
            if ad > tol_abs and rd > tol_rel:
                local_failed = True
            local_compared += 1
        if common_steps:
            ref_final = ref_by_step[common_steps[-1]].get(col, "")
            test_final = test_by_step[common_steps[-1]].get(col, "")
        if local_compared > 0:
            compared += 1
            if local_failed:
                failed += 1
            details.append({
                "column": col,
                "maxAbsDiff": max_abs,
                "maxRelDiff": max_rel,
                "worstStep": worst_step,
                "refFinal": ref_final,
                "testFinal": test_final,
                "comparedSteps": local_compared,
                "verdict": "FAIL" if local_failed else "PASS",
                "note": "exact" if col in EXACT_COLUMNS else "toleranced",
            })
    return details, compared, failed


def parse_time_file(run_root: Path) -> Tuple[float, float, float]:
    elapsed = user = sys_time = math.nan
    for p in sorted((run_root / "logs").glob("*.time")):
        text = p.read_text(errors="replace")
        m = re.search(r"elapsed=([0-9.+\-eE]+)\s+user=([0-9.+\-eE]+)\s+sys=([0-9.+\-eE]+)", text)
        if m:
            elapsed, user, sys_time = map(float, m.groups())
    return elapsed, user, sys_time


def read_manifest(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest", type=Path)
    ap.add_argument("art_dir", type=Path)
    ap.add_argument("--abs-tol", type=float, default=1e-8)
    ap.add_argument("--rel-tol", type=float, default=1e-8)
    ap.add_argument("--allow-runtime-ratio", type=float, default=0.0, help="Optional performance guard; 0 disables.")
    args = ap.parse_args()

    rows = read_manifest(args.manifest)
    grouped: Dict[Tuple[str, str], Dict[str, Dict[str, str]]] = defaultdict(dict)
    for r in rows:
        grouped[(r.get("caseName", ""), r.get("modeName", ""))][r.get("variant", "")] = r

    detail_path = args.art_dir / "active_prefix_0315b_compare_details.csv"
    summary_path = args.art_dir / "active_prefix_0315b_compare_summary.csv"
    args.art_dir.mkdir(parents=True, exist_ok=True)

    detail_fields = [
        "caseName", "modeName", "column", "maxAbsDiff", "maxRelDiff", "worstStep",
        "refFinal", "testFinal", "comparedSteps", "verdict", "note",
    ]
    summary_fields = [
        "caseName", "modeName", "refExitCode", "testExitCode", "refRows", "testRows",
        "comparedColumns", "failedColumns", "refElapsedSeconds", "testElapsedSeconds",
        "elapsedRatioTestOverRef", "refSummary", "testSummary", "verdict",
    ]

    summary_rows: List[Dict[str, object]] = []
    detail_rows: List[Dict[str, object]] = []
    any_fail = False

    for (case, mode), variants in sorted(grouped.items()):
        ref = variants.get("ref")
        test = variants.get("test")
        if not ref or not test:
            any_fail = True
            summary_rows.append({
                "caseName": case, "modeName": mode, "refExitCode": ref.get("exitCode") if ref else "missing",
                "testExitCode": test.get("exitCode") if test else "missing", "refRows": 0, "testRows": 0,
                "comparedColumns": 0, "failedColumns": 1, "refElapsedSeconds": "", "testElapsedSeconds": "",
                "elapsedRatioTestOverRef": "", "refSummary": "", "testSummary": "", "verdict": "FAIL",
            })
            continue
        ref_summary = Path(ref.get("summaryFile", ""))
        test_summary = Path(test.get("summaryFile", ""))
        ref_rows = read_csv(ref_summary)
        test_rows = read_csv(test_summary)
        ref_elapsed, _, _ = parse_time_file(Path(ref.get("runRoot", "")))
        test_elapsed, _, _ = parse_time_file(Path(test.get("runRoot", "")))
        elapsed_ratio = test_elapsed / ref_elapsed if ref_elapsed and not math.isnan(ref_elapsed) and not math.isnan(test_elapsed) else math.nan

        compared = 0
        failed = 0
        verdict = "PASS"
        if ref.get("exitCode") != "0" or test.get("exitCode") != "0" or not ref_rows or not test_rows:
            verdict = "FAIL"
            failed = 1
        else:
            details, compared, failed = compare_rows(ref_rows, test_rows, SELECTED_COLUMNS, args.abs_tol, args.rel_tol)
            for d in details:
                dd = {"caseName": case, "modeName": mode}
                dd.update(d)
                detail_rows.append(dd)
            if failed:
                verdict = "FAIL"
            if args.allow_runtime_ratio > 0 and not math.isnan(elapsed_ratio) and elapsed_ratio > args.allow_runtime_ratio:
                verdict = "FAIL"
                failed += 1
                detail_rows.append({
                    "caseName": case, "modeName": mode, "column": "__runtime_ratio__",
                    "maxAbsDiff": test_elapsed - ref_elapsed, "maxRelDiff": elapsed_ratio,
                    "worstStep": "", "refFinal": ref_elapsed, "testFinal": test_elapsed,
                    "comparedSteps": 1, "verdict": "FAIL",
                    "note": f"test/ref runtime ratio exceeds {args.allow_runtime_ratio}",
                })
        if verdict != "PASS":
            any_fail = True
        summary_rows.append({
            "caseName": case, "modeName": mode,
            "refExitCode": ref.get("exitCode", ""), "testExitCode": test.get("exitCode", ""),
            "refRows": len(ref_rows), "testRows": len(test_rows),
            "comparedColumns": compared, "failedColumns": failed,
            "refElapsedSeconds": ref_elapsed, "testElapsedSeconds": test_elapsed,
            "elapsedRatioTestOverRef": elapsed_ratio,
            "refSummary": str(ref_summary), "testSummary": str(test_summary),
            "verdict": verdict,
        })

    with detail_path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=detail_fields)
        w.writeheader(); w.writerows(detail_rows)
    with summary_path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=summary_fields)
        w.writeheader(); w.writerows(summary_rows)

    print(f"[0315b-compare] wrote {summary_path}")
    print(f"[0315b-compare] wrote {detail_path}")
    failed_cases = [r for r in summary_rows if r.get("verdict") != "PASS"]
    print(f"[0315b-compare] cases={len(summary_rows)} failed={len(failed_cases)} verdict={'FAIL' if any_fail else 'PASS'}")
    for r in failed_cases:
        print(f"[0315b-compare] FAIL case={r.get('caseName')} mode={r.get('modeName')} failedColumns={r.get('failedColumns')}")
    return 1 if any_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())

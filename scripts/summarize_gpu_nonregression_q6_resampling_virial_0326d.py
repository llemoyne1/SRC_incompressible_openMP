#!/usr/bin/env python3
"""0326d strict parser for Q6/resampling/virial non-regression outputs.

This script intentionally does not run or modify the solver.  It reads an
existing 0326d artifact directory and checks whether each advertised physics
module was actually exercised, not only whether the process exited with 0.
"""
from __future__ import annotations

import csv
import os
import sys
from pathlib import Path
from typing import Dict, List, Tuple

DEFAULT_ART_DIR = Path("dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326d")
DEFAULT_OUT_DIR = Path("dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326d")


def read_csv_rows(path: Path) -> List[Dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def as_float(row: Dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        value = row.get(key, "")
        if value is None or value == "":
            return default
        return float(value)
    except Exception:
        return default


def as_int(row: Dict[str, str], key: str, default: int = 0) -> int:
    return int(round(as_float(row, key, float(default))))


def find_validation_summary(art_dir: Path, target: str) -> Path | None:
    roots = list((art_dir / "runs" / target).glob("validation_summary_0162.csv"))
    if roots:
        return roots[0]
    nested = list((art_dir / "runs" / target).glob("*/validation_summary_0162.csv"))
    return nested[0] if nested else None


def find_cuda_persistent_csv(art_dir: Path, target: str) -> Path | None:
    files = list((art_dir / "runs" / target).glob("**/cuda_persistent_src_collision_thermostat_0215.csv"))
    return files[0] if files else None


def last_row(rows: List[Dict[str, str]]) -> Dict[str, str]:
    return rows[-1] if rows else {}


def verdict_for_target(target: str, exit_code: int, validation_last: Dict[str, str], cuda_rows: List[Dict[str, str]]) -> Tuple[str, str]:
    reasons: List[str] = []
    if exit_code != 0:
        reasons.append(f"exitCode={exit_code}")

    q6_applied = as_int(validation_last, "q6Applied")
    q6_converged = as_int(validation_last, "q6Converged")
    resamp_computed = as_int(validation_last, "resampComputed")
    cap_enabled = as_int(validation_last, "capacityResponseEnabled")
    cap_computed = as_int(validation_last, "capacityResponseComputed")
    virial_kick = as_int(validation_last, "capacityVirialKickApplied")

    cuda_rows_count = len(cuda_rows)
    thermostat_gpu_max = 0
    if cuda_rows:
        thermostat_gpu_max = max(as_int(r, "thermostatAppliedOnGpu") for r in cuda_rows)

    if target == "q6_only_tg":
        if q6_applied != 1:
            reasons.append("expected q6Applied=1")
        if q6_converged != 1:
            reasons.append("expected q6Converged=1")
        if resamp_computed != 0:
            reasons.append("expected resampComputed=0")
    elif target == "resampling_only_tg":
        if q6_applied != 0:
            reasons.append("expected q6Applied=0")
        if resamp_computed != 1:
            reasons.append("expected resampComputed=1")
    elif target == "hybrid_cuda_q6_resampling_tg":
        if cuda_rows_count <= 0:
            reasons.append("expected CUDA persistent collision rows")
        if thermostat_gpu_max != 0:
            reasons.append("expected CPU thermostat: thermostatAppliedOnGpu=0")
        if q6_applied != 1:
            reasons.append("expected q6Applied=1 in hybrid Q6/resampling")
        if q6_converged != 1:
            reasons.append("expected q6Converged=1 in hybrid Q6/resampling")
        if resamp_computed != 1:
            reasons.append("expected resampComputed=1 in hybrid Q6/resampling")
    elif target == "hybrid_cuda_piston_virial":
        if cuda_rows_count <= 0:
            reasons.append("expected CUDA persistent piston collision rows")
        if thermostat_gpu_max != 0:
            reasons.append("expected CPU thermostat: thermostatAppliedOnGpu=0")
        if q6_applied != 1:
            reasons.append("expected q6Applied=1 in piston/virial hybrid")
        if q6_converged != 1:
            reasons.append("expected q6Converged=1 in piston/virial hybrid")
        if resamp_computed != 1:
            reasons.append("expected resampComputed=1 in piston/virial hybrid")
        if cap_enabled != 1:
            reasons.append("expected capacityResponseEnabled=1")
        if cap_computed != 1:
            reasons.append("expected capacityResponseComputed=1")
        if virial_kick != 1:
            reasons.append("expected capacityVirialKickApplied=1")
    else:
        reasons.append(f"unknown target={target}")

    return ("PASS" if not reasons else "FAIL", "; ".join(reasons))


def main(argv: List[str]) -> int:
    art_dir = Path(argv[1]) if len(argv) > 1 else Path(os.environ.get("ART_DIR_0326B", DEFAULT_ART_DIR))
    out_dir = Path(argv[2]) if len(argv) > 2 else Path(os.environ.get("OUT_DIR_0326C", DEFAULT_OUT_DIR))
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest_path = art_dir / "gpu_nonregression_q6_resampling_virial_0326d_manifest.csv"
    manifest_rows = read_csv_rows(manifest_path)
    if not manifest_rows:
        print(f"[0326d-summary] ERROR: missing/empty manifest: {manifest_path}", file=sys.stderr)
        return 2

    out_csv = out_dir / "gpu_nonregression_q6_resampling_virial_0326d_summary.csv"
    fieldnames = [
        "target", "case", "exitCode", "strictVerdict", "strictReason",
        "q6Applied", "q6Converged", "q6Iterations", "q6ResidualRel",
        "resampComputed", "capacityResponseEnabled", "capacityResponseComputed",
        "capacityVirialKickApplied", "cudaPersistentRows", "thermostatAppliedOnGpuMax",
        "validationSummary", "cudaPersistentCsv",
    ]
    fail_count = 0
    with out_csv.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for m in manifest_rows:
            target = m.get("target", "")
            case = m.get("caseList", "")
            exit_code = as_int(m, "exitCode", 999)
            validation_path = find_validation_summary(art_dir, target)
            validation_rows = read_csv_rows(validation_path) if validation_path else []
            v_last = last_row(validation_rows)
            cuda_path = find_cuda_persistent_csv(art_dir, target)
            cuda_rows = read_csv_rows(cuda_path) if cuda_path else []
            verdict, reason = verdict_for_target(target, exit_code, v_last, cuda_rows)
            if verdict != "PASS":
                fail_count += 1
            thermostat_gpu_max = max([as_int(r, "thermostatAppliedOnGpu") for r in cuda_rows], default=0)
            writer.writerow({
                "target": target,
                "case": case,
                "exitCode": exit_code,
                "strictVerdict": verdict,
                "strictReason": reason,
                "q6Applied": as_int(v_last, "q6Applied"),
                "q6Converged": as_int(v_last, "q6Converged"),
                "q6Iterations": as_int(v_last, "q6Iterations"),
                "q6ResidualRel": v_last.get("q6ResidualRel", ""),
                "resampComputed": as_int(v_last, "resampComputed"),
                "capacityResponseEnabled": as_int(v_last, "capacityResponseEnabled"),
                "capacityResponseComputed": as_int(v_last, "capacityResponseComputed"),
                "capacityVirialKickApplied": as_int(v_last, "capacityVirialKickApplied"),
                "cudaPersistentRows": len(cuda_rows),
                "thermostatAppliedOnGpuMax": thermostat_gpu_max,
                "validationSummary": str(validation_path or ""),
                "cudaPersistentCsv": str(cuda_path or ""),
            })

    print(f"[0326d-summary] wrote {out_csv}")
    print(f"[0326d-summary] rows={len(manifest_rows)} strict_fail={fail_count}")
    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

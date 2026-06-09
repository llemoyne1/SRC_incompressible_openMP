#!/usr/bin/env python3
"""Analyze short inactive-slot scaling sweeps for CUDA SRC/MPCD.

The analyzer intentionally depends only on the Python standard library.  It reads
an audit manifest produced by run_cuda_inactive_slots_scaling_0310.sh and writes
compact per-run and summary CSVs.  Missing optional diagnostics are tolerated;
missing run roots are reported as FAIL-like rows rather than raising.
"""
from __future__ import annotations

import csv
import math
import re
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


def read_last_csv_row(path: Path) -> Dict[str, str]:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    last: Dict[str, str] = {}
    with path.open(newline="") as fh:
        for row in csv.DictReader(fh):
            last = row
    return last


def read_csv_rows(path: Path) -> List[Dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def f(row: Dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        v = row.get(key, "")
        if v is None or v == "":
            return default
        return float(v)
    except Exception:
        return default


def parse_time_file(run_root: Path) -> Tuple[float, float, float]:
    elapsed = user = sys_time = math.nan
    for p in sorted((run_root / "logs").glob("*.time")):
        text = p.read_text(errors="replace")
        m = re.search(r"elapsed=([0-9.+\-eE]+)\s+user=([0-9.+\-eE]+)\s+sys=([0-9.+\-eE]+)", text)
        if m:
            elapsed, user, sys_time = map(float, m.groups())
    return elapsed, user, sys_time


def parse_log_header(run_root: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for p in sorted((run_root / "logs").glob("*.log")):
        text = p.read_text(errors="replace")
        m = re.search(r"\[src_mpcd_base\]\s+Np=(\d+)\s+fluid=(\d+)\s+latent=(\d+)\s+inactive=(\d+)", text)
        if m:
            out.update({
                "NpLogged": m.group(1),
                "fluidLogged": m.group(2),
                "latentLogged": m.group(3),
                "inactiveLogged": m.group(4),
            })
            break
    return out


def sum_column(rows: Iterable[Dict[str, str]], *keys: str) -> float:
    total = 0.0
    for row in rows:
        for key in keys:
            if key in row:
                total += f(row, key)
                break
    return total


def max_column(rows: Iterable[Dict[str, str]], *keys: str) -> float:
    found = False
    mv = 0.0
    for row in rows:
        for key in keys:
            if key in row and row.get(key, "") != "":
                mv = max(mv, f(row, key))
                found = True
                break
    return mv if found else math.nan


def main(argv: List[str]) -> int:
    if len(argv) != 3:
        print("usage: analyze_cuda_inactive_slots_scaling_0310.py RUN_MANIFEST ART_DIR", file=sys.stderr)
        return 2

    manifest = Path(argv[1])
    art = Path(argv[2])
    if not manifest.exists():
        print(f"missing manifest: {manifest}", file=sys.stderr)
        return 2

    per_rows: List[Dict[str, object]] = []
    with manifest.open(newline="") as fh:
        for mr in csv.DictReader(fh):
            run_root = Path(mr.get("runRoot", ""))
            output = run_root / "output"
            summary = read_csv_rows(output / "summary_runtime.csv")
            final = summary[-1] if summary else {}
            guard_rows = read_csv_rows(output / "cuda_resampling_population_guard_0297.csv")
            flag_rows = read_csv_rows(output / "cuda_resampling_adaptive_flag_0304.csv")
            survey_rows = read_csv_rows(output / "cuda_resampling_support_survey_0295.csv")
            elapsed, user_time, sys_time = parse_time_file(run_root)
            header = parse_log_header(run_root)

            requested = int(float(mr.get("requestedSteps", "0") or 0))
            last_step = int(f(final, "step", 0)) if final else 0
            completed = int(requested > 0 and last_step >= requested)
            elapsed_per_step = elapsed / requested if requested > 0 and not math.isnan(elapsed) else math.nan

            row: Dict[str, object] = {
                "caseName": mr.get("caseName", ""),
                "modeName": mr.get("modeName", ""),
                "inactiveSlotsRequested": mr.get("inactiveSlots", ""),
                "guardEvery": mr.get("guardEvery", ""),
                "runRoot": str(run_root),
                "exitCode": mr.get("exitCode", ""),
                "requestedSteps": requested,
                "lastSummaryStep": last_step,
                "completed": completed,
                "elapsedSeconds": elapsed,
                "elapsedPerStep": elapsed_per_step,
                "userSeconds": user_time,
                "sysSeconds": sys_time,
                "summaryRows": len(summary),
                "guardRows": len(guard_rows),
                "flagRows": len(flag_rows),
                "surveyRows": len(survey_rows),
                "sumSplitApplied": sum_column(guard_rows, "splitApplied"),
                "sumMergeApplied": sum_column(guard_rows, "mergeApplied"),
                "sumSplitSkippedNoInactive": sum_column(guard_rows, "splitSkippedNoInactive", "splitSkippedNoInactive0297"),
                "maxGuardKernelSeconds": max_column(guard_rows, "kernelSeconds", "guardKernelSeconds"),
                "sumFlagDepositSeconds": sum_column(flag_rows, "depositKernelSeconds"),
                "sumFlagDownloadSeconds": sum_column(flag_rows, "downloadSeconds"),
                "finalFluidParticles": f(final, "nFluidParticles", math.nan),
                "finalInactiveParticles": f(final, "nInactiveParticles", math.nan),
                "finalTotalMass": f(final, "totalMass", math.nan),
                "finalKBT": f(final, "kBTEstimate", math.nan),
                "finalStdN": f(final, "stdN", math.nan),
                "maxParticleSpeed": f(final, "maxParticleSpeed", math.nan),
            }
            row.update(header)
            per_rows.append(row)

    per_path = art / "cuda_inactive_slots_scaling_0310_per_run.csv"
    fieldnames: List[str] = []
    for row in per_rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)
    with per_path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames)
        w.writeheader()
        for row in per_rows:
            w.writerow(row)

    # Compact ratio summary relative to the smallest completed slot count for
    # each (case, mode, guardEvery) group.
    groups: Dict[Tuple[str, str, str], List[Dict[str, object]]] = {}
    for row in per_rows:
        groups.setdefault((str(row.get("caseName", "")), str(row.get("modeName", "")), str(row.get("guardEvery", ""))), []).append(row)

    summary_rows: List[Dict[str, object]] = []
    for key, rows in groups.items():
        completed = [r for r in rows if int(float(r.get("completed", 0) or 0)) == 1 and not math.isnan(float(r.get("elapsedSeconds", math.nan)))]
        if not completed:
            continue
        completed.sort(key=lambda r: int(float(r.get("inactiveSlotsRequested", 0) or 0)))
        base = completed[0]
        base_elapsed = float(base.get("elapsedSeconds", math.nan))
        base_slots = int(float(base.get("inactiveSlotsRequested", 0) or 0))
        for r in completed:
            elapsed = float(r.get("elapsedSeconds", math.nan))
            slots = int(float(r.get("inactiveSlotsRequested", 0) or 0))
            summary_rows.append({
                "caseName": key[0],
                "modeName": key[1],
                "guardEvery": key[2],
                "baseInactiveSlots": base_slots,
                "inactiveSlots": slots,
                "elapsedSeconds": elapsed,
                "elapsedRatioVsBase": elapsed / base_elapsed if base_elapsed > 0 else math.nan,
                "elapsedPerStep": r.get("elapsedPerStep", math.nan),
                "NpLogged": r.get("NpLogged", ""),
                "fluidLogged": r.get("fluidLogged", ""),
                "inactiveLogged": r.get("inactiveLogged", ""),
                "sumSplitApplied": r.get("sumSplitApplied", ""),
                "sumFlagDepositSeconds": r.get("sumFlagDepositSeconds", ""),
            })

    ratio_path = art / "cuda_inactive_slots_scaling_0310_ratios.csv"
    if summary_rows:
        with ratio_path.open("w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(summary_rows[0].keys()))
            w.writeheader(); w.writerows(summary_rows)

    print(f"[0310-inactive] wrote {per_path}")
    print(f"[0310-inactive] wrote {ratio_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

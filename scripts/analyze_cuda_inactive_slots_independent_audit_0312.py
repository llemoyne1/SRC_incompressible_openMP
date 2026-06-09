#!/usr/bin/env python3
from __future__ import annotations

import csv
import math
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional

RE_INIT = re.compile(r"\[src_mpcd_base\]\s+Np=(\d+)\s+fluid=(\d+)\s+latent=(\d+)\s+inactive=(\d+)")
RE_ELAPSED = re.compile(r"elapsed=([0-9.eE+-]+)")


def fnum(v: str, default: float = math.nan) -> float:
    try:
        return float(v)
    except Exception:
        return default


def read_csv_rows(path: Path) -> List[Dict[str, str]]:
    if not path.is_file() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def parse_initial_counts(log_path: Path) -> Dict[str, float]:
    out = {"NpLogged": math.nan, "fluidLogged": math.nan, "latentLogged": math.nan, "inactiveLogged": math.nan}
    if not log_path.is_file():
        return out
    for line in log_path.read_text(errors="replace").splitlines():
        m = RE_INIT.search(line)
        if m:
            out["NpLogged"] = float(m.group(1))
            out["fluidLogged"] = float(m.group(2))
            out["latentLogged"] = float(m.group(3))
            out["inactiveLogged"] = float(m.group(4))
            break
    return out


def parse_elapsed(time_path: Path) -> float:
    if not time_path.is_file():
        return math.nan
    txt = time_path.read_text(errors="replace")
    matches = RE_ELAPSED.findall(txt)
    return float(matches[-1]) if matches else math.nan


def last_summary(path: Path) -> Dict[str, str]:
    rows = read_csv_rows(path)
    return rows[-1] if rows else {}


def sum_guard(run_root: Path, key: str) -> float:
    rows = read_csv_rows(run_root / "output" / "cuda_resampling_population_guard_0297.csv")
    total = 0.0
    for r in rows:
        total += fnum(r.get(key, "0"), 0.0)
    return total


def sum_time_csv(run_root: Path, rel: str, key: str) -> float:
    rows = read_csv_rows(run_root / "output" / rel)
    total = 0.0
    for r in rows:
        total += fnum(r.get(key, "0"), 0.0)
    return total


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: analyze_cuda_inactive_slots_independent_audit_0312.py RUN_MANIFEST OUT_DIR", file=sys.stderr)
        return 2
    manifest = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    rows = read_csv_rows(manifest)
    per_rows: List[Dict[str, object]] = []

    for r in rows:
        run_root = Path(r["runRoot"])
        summary_file = Path(r["summaryFile"])
        log_file = Path(r["logFile"])
        time_file = Path(r["timeFile"])
        requested_steps = int(float(r.get("requestedSteps", "0") or 0))
        slots_req = int(float(r.get("inactiveSlotsRequested", "0") or 0))
        exit_code = int(float(r.get("exitCode", "999") or 999))
        counts = parse_initial_counts(log_file)
        elapsed = parse_elapsed(time_file)
        last = last_summary(summary_file)
        last_step = int(float(last.get("step", "0") or 0)) if last else 0
        completed = 1 if exit_code == 0 and last_step >= requested_steps else 0
        inactive_logged = counts["inactiveLogged"]
        actual_matches = 1 if math.isfinite(inactive_logged) and abs(inactive_logged - slots_req) <= 1 else 0
        verdict = "PASS" if completed and actual_matches else ("INVALID" if completed and not actual_matches else "FAIL")
        per_rows.append({
            "caseName": r["caseName"],
            "modeName": r["modeName"],
            "inactiveSlotsRequested": slots_req,
            "runRoot": r["runRoot"],
            "exitCode": exit_code,
            "requestedSteps": requested_steps,
            "lastSummaryStep": last_step,
            "completed": completed,
            "verdict": verdict,
            "elapsedSeconds": elapsed,
            "NpLogged": counts["NpLogged"],
            "fluidLogged": counts["fluidLogged"],
            "latentLogged": counts["latentLogged"],
            "inactiveLogged": inactive_logged,
            "actualMatchesRequested": actual_matches,
            "nFluidFinal": fnum(last.get("nFluidParticles", "nan"), math.nan) if last else math.nan,
            "nInactiveFinal": fnum(last.get("nInactiveParticles", "nan"), math.nan) if last else math.nan,
            "stdNFinal": fnum(last.get("stdN", "nan"), math.nan) if last else math.nan,
            "kBTEstimateFinal": fnum(last.get("kBTEstimate", "nan"), math.nan) if last else math.nan,
            "sumSplitApplied": sum_guard(run_root, "splitApplied"),
            "sumMergeApplied": sum_guard(run_root, "mergeApplied"),
            "sumSplitSkippedNoInactive": sum_guard(run_root, "splitSkippedNoInactive"),
            "sumSplitSkippedDonorMass0307": sum_guard(run_root, "splitSkippedDonorMass0307"),
            "sumGuardKernelSeconds": sum_time_csv(run_root, "cuda_resampling_population_guard_0297.csv", "kernelSeconds"),
            "sumSurveyKernelSeconds": sum_time_csv(run_root, "cuda_resampling_support_survey_0295.csv", "kernelSeconds"),
        })

    per_path = out_dir / "cuda_inactive_slots_independent_0312_per_run.csv"
    per_path.parent.mkdir(parents=True, exist_ok=True)
    if per_rows:
        with per_path.open("w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(per_rows[0].keys()))
            writer.writeheader()
            writer.writerows(per_rows)

    # Ratios by case/mode against the smallest requested slot count that actually matched.
    groups: Dict[tuple, List[Dict[str, object]]] = {}
    for pr in per_rows:
        groups.setdefault((str(pr["caseName"]), str(pr["modeName"])), []).append(pr)
    ratio_rows: List[Dict[str, object]] = []
    for (case, mode), gr in groups.items():
        gr = sorted(gr, key=lambda x: int(x["inactiveSlotsRequested"]))
        valid = [x for x in gr if int(x["completed"]) == 1 and int(x["actualMatchesRequested"]) == 1 and math.isfinite(float(x["elapsedSeconds"]))]
        base = valid[0] if valid else None
        base_elapsed = float(base["elapsedSeconds"]) if base else math.nan
        base_slots = int(base["inactiveSlotsRequested"]) if base else 0
        for x in gr:
            elapsed = float(x["elapsedSeconds"]) if math.isfinite(float(x["elapsedSeconds"])) else math.nan
            ratio_rows.append({
                "caseName": case,
                "modeName": mode,
                "inactiveSlotsRequested": x["inactiveSlotsRequested"],
                "inactiveLogged": x["inactiveLogged"],
                "NpLogged": x["NpLogged"],
                "completed": x["completed"],
                "actualMatchesRequested": x["actualMatchesRequested"],
                "verdict": x["verdict"],
                "elapsedSeconds": elapsed,
                "baseSlots": base_slots,
                "elapsedRatioVsBase": elapsed / base_elapsed if base and base_elapsed > 0.0 and math.isfinite(elapsed) else math.nan,
                "sumSplitApplied": x["sumSplitApplied"],
                "sumSplitSkippedNoInactive": x["sumSplitSkippedNoInactive"],
            })
    ratio_path = out_dir / "cuda_inactive_slots_independent_0312_ratios.csv"
    if ratio_rows:
        with ratio_path.open("w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(ratio_rows[0].keys()))
            writer.writeheader()
            writer.writerows(ratio_rows)

    failures = [r for r in per_rows if r.get("verdict") != "PASS"]
    print(f"[0312-analyze] runs={len(per_rows)} failures_or_invalid={len(failures)} per_run={per_path} ratios={ratio_path}")
    if failures:
        for r in failures[:10]:
            print(f"[0312-analyze] {r['verdict']} case={r['caseName']} mode={r['modeName']} slots={r['inactiveSlotsRequested']} exit={r['exitCode']} last={r['lastSummaryStep']} inactiveLogged={r['inactiveLogged']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

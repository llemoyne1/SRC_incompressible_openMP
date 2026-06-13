#!/usr/bin/env python3
"""0331 safe_no0318 active CUDA resampling sweep analyzer.

Consumes the run manifest produced by run_cuda_safe_no0318_active_sweep_0331.sh
and writes compact CSVs with final summary metrics, guard/mass diagnostics and
classic-relative deltas.  Standard library only: no pandas dependency.
"""
from __future__ import annotations

import csv
import glob
import math
import os
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

SUMMARY_KEYS = [
    "step", "time", "nFluidParticles", "nInactiveParticles", "totalMass", "Px", "Py",
    "meanVx", "meanVy", "meanKinetic", "kBTEstimate", "meanParticleSpeed", "maxParticleSpeed",
    "meanN", "stdN", "minN", "maxN", "hitsLeft", "hitsRight", "hitsBottom", "hitsTop",
    "hitsImmersed", "outletParticlesDeleted", "inletParticlesInserted", "inletNetParticleDelta",
    "thermostatApplied", "thermostatKBTBefore", "thermostatKBTAfter", "resampMeanUx", "resampMeanUy",
]

GUARD_SUM_KEYS = [
    "splitApplied", "mergeApplied", "poorCells", "richCells", "emptyCells", "targetCells",
    "excludedBoundaryCells0299", "excludedOpenBoundaryCells0299", "excludedSolidHaloCells0299",
]
GUARD_MAX_KEYS = [
    "maxAbsCellMassError", "maxAbsCellMomentumError", "maxAbsCellKrelErrorPreRestore0298",
    "maxRelCellKrelErrorPreRestore0298", "maxAbsCellKrelError0298", "maxRelCellKrelError0298",
]
GUARD_LAST_KEYS = [
    "totalMassBefore", "totalMassAfter", "totalPxBefore", "totalPxAfter", "totalPyBefore", "totalPyAfter",
    "totalKrelBefore0298", "totalKrelAfterPreRestore0298", "totalKrelAfter0298",
]
MASS_SUM_KEYS = ["cellsProcessed", "particlesProcessed", "cellsSkipped", "cellsClipped"]
MASS_MAX_KEYS = ["maxAbsCellMassError", "maxAbsCellMomentumError", "maxRelMassChange", "maxMassBefore", "maxMassAfter"]


def as_float(value: object) -> Optional[float]:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def read_last_csv_row(path: Path) -> Dict[str, str]:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    with path.open(newline="") as fh:
        rows = list(csv.DictReader(fh))
    return rows[-1] if rows else {}


def read_manifest(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def aggregate_csv_files(root: Path, pattern: str, sum_keys: Iterable[str], max_keys: Iterable[str], last_keys: Iterable[str] = ()) -> Dict[str, object]:
    files = [Path(p) for p in glob.glob(str(root / "**" / pattern), recursive=True)]
    result: Dict[str, object] = {"files": len(files), "rows": 0}
    for key in sum_keys:
        result[f"sum_{key}"] = 0.0
    for key in max_keys:
        result[f"max_{key}"] = 0.0
    for key in last_keys:
        result[f"last_{key}"] = ""

    for p in files:
        try:
            with p.open(newline="") as fh:
                for row in csv.DictReader(fh):
                    result["rows"] = int(result["rows"]) + 1
                    for key in sum_keys:
                        v = as_float(row.get(key))
                        if v is not None:
                            result[f"sum_{key}"] = float(result[f"sum_{key}"]) + v
                    for key in max_keys:
                        v = as_float(row.get(key))
                        if v is not None:
                            result[f"max_{key}"] = max(float(result[f"max_{key}"]), abs(v))
                    for key in last_keys:
                        if key in row:
                            result[f"last_{key}"] = row.get(key, "")
        except FileNotFoundError:
            continue
    return result


def final_state_sha(root: Path) -> str:
    # Hashes are optional; the shell manifest may already contain them.  Avoid
    # recomputing huge dumps here.
    dumps = sorted((root / "output").glob("state_step_*.smpcd"))
    return dumps[-1].name if dumps else ""


def build_per_run_rows(manifest_rows: List[Dict[str, str]]) -> List[Dict[str, object]]:
    out: List[Dict[str, object]] = []
    for m in manifest_rows:
        root = Path(m.get("runRoot", ""))
        final = read_last_csv_row(root / "output" / "summary_runtime.csv")
        guard = aggregate_csv_files(root, "cuda_resampling_population_guard_0297.csv", GUARD_SUM_KEYS, GUARD_MAX_KEYS, GUARD_LAST_KEYS)
        mass = aggregate_csv_files(root, "cuda_resampling_mass_recondition_0296.csv", MASS_SUM_KEYS, MASS_MAX_KEYS)
        row: Dict[str, object] = {
            "caseName": m.get("caseName", ""),
            "modeName": m.get("modeName", ""),
            "nmin": m.get("nmin", ""),
            "ntarget": m.get("ntarget", ""),
            "nmax": m.get("nmax", ""),
            "exitCode": m.get("exitCode", ""),
            "runRoot": str(root),
            "finalDump": final_state_sha(root),
        }
        for key in SUMMARY_KEYS:
            row[f"summary_{key}"] = final.get(key, "")
        for key, value in guard.items():
            row[f"guard_{key}"] = value
        for key, value in mass.items():
            row[f"mass_{key}"] = value
        out.append(row)
    return out


def make_delta_rows(per_run: List[Dict[str, object]]) -> List[Dict[str, object]]:
    by_case: Dict[str, Dict[str, object]] = {}
    for r in per_run:
        if str(r.get("modeName")) == "classic" and str(r.get("nmin", "")) in ("", "0"):
            by_case[str(r.get("caseName"))] = r
    deltas: List[Dict[str, object]] = []
    for r in per_run:
        case = str(r.get("caseName"))
        base = by_case.get(case)
        if not base:
            continue
        d: Dict[str, object] = {
            "caseName": case,
            "modeName": r.get("modeName", ""),
            "nmin": r.get("nmin", ""),
            "ntarget": r.get("ntarget", ""),
            "nmax": r.get("nmax", ""),
        }
        for key in ["totalMass", "Px", "Py", "meanVx", "meanVy", "meanKinetic", "kBTEstimate", "meanN", "stdN", "minN", "maxN", "nFluidParticles", "nInactiveParticles"]:
            a = as_float(base.get(f"summary_{key}"))
            b = as_float(r.get(f"summary_{key}"))
            d[f"delta_{key}"] = "" if a is None or b is None else repr(b - a)
        d["guard_splitApplied"] = r.get("guard_sum_splitApplied", "")
        d["guard_mergeApplied"] = r.get("guard_sum_mergeApplied", "")
        d["guard_poorCells"] = r.get("guard_sum_poorCells", "")
        d["guard_richCells"] = r.get("guard_sum_richCells", "")
        d["guard_excludedOpen0299"] = r.get("guard_sum_excludedOpenBoundaryCells0299", "")
        d["guard_maxMassError"] = r.get("guard_max_maxAbsCellMassError", "")
        d["guard_maxMomentumError"] = r.get("guard_max_maxAbsCellMomentumError", "")
        d["guard_maxKrelError0298"] = r.get("guard_max_maxAbsCellKrelError0298", "")
        deltas.append(d)
    return deltas


def write_csv(path: Path, rows: List[Dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields: List[str] = []
    seen = set()
    for row in rows:
        for key in row.keys():
            if key not in seen:
                seen.add(key); fields.append(key)
    with path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main(argv: List[str]) -> int:
    if len(argv) < 3:
        print("usage: analyze_cuda_resampling_active_sweep_0300.py RUN_MANIFEST OUT_DIR", file=sys.stderr)
        return 2
    manifest = Path(argv[1])
    out_dir = Path(argv[2])
    rows = read_manifest(manifest)
    per_run = build_per_run_rows(rows)
    deltas = make_delta_rows(per_run)
    write_csv(out_dir / "cuda_safe_no0318_active_sweep_0331_per_run.csv", per_run)
    write_csv(out_dir / "cuda_safe_no0318_active_sweep_0331_vs_classic.csv", deltas)

    failed_runs = [r for r in rows if str(r.get("exitCode", "0")) != "0"]
    active_guard = [r for r in per_run if str(r.get("modeName", "")).startswith("guard")]
    total_split = sum(as_float(r.get("guard_sum_splitApplied")) or 0.0 for r in active_guard)
    total_merge = sum(as_float(r.get("guard_sum_mergeApplied")) or 0.0 for r in active_guard)
    max_mass_err = max([as_float(r.get("guard_max_maxAbsCellMassError")) or 0.0 for r in active_guard] or [0.0])
    max_mom_err = max([as_float(r.get("guard_max_maxAbsCellMomentumError")) or 0.0 for r in active_guard] or [0.0])
    max_krel_err = max([as_float(r.get("guard_max_maxAbsCellKrelError0298")) or 0.0 for r in active_guard] or [0.0])

    print(f"[0331-analyze] manifest={manifest}")
    print(f"[0331-analyze] runs={len(rows)} failedRuns={len(failed_runs)} totalSplit={total_split:g} totalMerge={total_merge:g} maxMassErr={max_mass_err:g} maxMomentumErr={max_mom_err:g} maxKrelErr0298={max_krel_err:g}")
    print(f"[0331-analyze] wrote={out_dir / 'cuda_safe_no0318_active_sweep_0331_per_run.csv'}")
    print(f"[0331-analyze] wrote={out_dir / 'cuda_safe_no0318_active_sweep_0331_vs_classic.csv'}")
    return 1 if failed_runs else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

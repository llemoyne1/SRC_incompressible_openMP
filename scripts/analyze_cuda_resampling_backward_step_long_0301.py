#!/usr/bin/env python3
"""0301 backward-step long-run analyzer.

Standard-library only.  Aggregates runtime summaries, passive 0295 survey CSVs,
and active 0297/0298/0299 guard diagnostics for the long/moderate backward-step
support-control campaign.
"""
from __future__ import annotations

import csv
import glob
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional

SUMMARY_KEYS = [
    "step", "time", "nFluidParticles", "nInactiveParticles", "totalMass", "Px", "Py",
    "meanVx", "meanVy", "meanKinetic", "kBTEstimate", "meanParticleSpeed", "maxParticleSpeed",
    "meanN", "stdN", "minN", "maxN", "hitsRight", "hitsImmersed", "outletParticlesDeleted",
    "inletParticlesInserted", "inletNetParticleDelta", "thermostatApplied", "thermostatKBTBefore",
    "thermostatKBTAfter", "resampMeanUx", "resampMeanUy",
]
SURVEY_KEYS = [
    "emptyCells", "poorCells", "richCells", "targetBandCells", "meanNActive", "stdNActive",
    "minNWet", "maxNWet", "massRelRmsWet", "relativeKineticEnergy", "kBTWeighted",
]
GUARD_SUM_KEYS = [
    "poorCells", "richCells", "mergeApplied", "splitApplied", "splitSkippedNoInactive",
    "splitSkippedNoDonor", "mergeSkippedNoPair", "excludedBoundaryCells0299",
    "excludedOpenBoundaryCells0299", "excludedSolidHaloCells0299",
]
GUARD_MAX_KEYS = [
    "maxAbsCellMassError", "maxAbsCellMomentumError", "maxAbsCellKrelErrorPreRestore0298",
    "maxRelCellKrelErrorPreRestore0298", "maxAbsCellKrelError0298", "maxRelCellKrelError0298",
]
GUARD_LAST_KEYS = [
    "fluidParticlesBefore", "fluidParticlesAfter", "inactiveParticlesBefore", "inactiveParticlesAfter",
    "totalMassBefore", "totalMassAfter", "totalPxBefore", "totalPxAfter", "totalPyBefore", "totalPyAfter",
    "totalKrelBefore0298", "totalKrelAfterPreRestore0298", "totalKrelAfter0298",
]


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


def read_csv_rows(path: Path) -> List[Dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def read_manifest(path: Path) -> List[Dict[str, str]]:
    return read_csv_rows(path)


def last_row(path: Path) -> Dict[str, str]:
    rows = read_csv_rows(path)
    return rows[-1] if rows else {}


def numeric_series(rows: List[Dict[str, str]], key: str) -> List[float]:
    out: List[float] = []
    for r in rows:
        v = as_float(r.get(key))
        if v is not None:
            out.append(v)
    return out


def aggregate_survey(root: Path) -> Dict[str, object]:
    rows: List[Dict[str, str]] = []
    for p in glob.glob(str(root / "**" / "cuda_resampling_support_survey_0295.csv"), recursive=True):
        rows.extend(read_csv_rows(Path(p)))
    out: Dict[str, object] = {"rows": len(rows)}
    if not rows:
        for k in SURVEY_KEYS:
            out[f"final_{k}"] = ""
            out[f"min_{k}"] = ""
            out[f"max_{k}"] = ""
            out[f"mean_{k}"] = ""
        return out
    final = rows[-1]
    for k in SURVEY_KEYS:
        vals = numeric_series(rows, k)
        out[f"final_{k}"] = final.get(k, "")
        out[f"min_{k}"] = "" if not vals else repr(min(vals))
        out[f"max_{k}"] = "" if not vals else repr(max(vals))
        out[f"mean_{k}"] = "" if not vals else repr(sum(vals) / len(vals))
    return out


def aggregate_guard(root: Path) -> Dict[str, object]:
    rows: List[Dict[str, str]] = []
    for p in glob.glob(str(root / "**" / "cuda_resampling_population_guard_0297.csv"), recursive=True):
        rows.extend(read_csv_rows(Path(p)))
    out: Dict[str, object] = {"rows": len(rows)}
    for k in GUARD_SUM_KEYS:
        vals = numeric_series(rows, k)
        out[f"sum_{k}"] = repr(sum(vals)) if vals else 0.0
        out[f"max_{k}"] = repr(max(vals)) if vals else 0.0
    for k in GUARD_MAX_KEYS:
        vals = [abs(v) for v in numeric_series(rows, k)]
        out[f"max_{k}"] = repr(max(vals)) if vals else 0.0
    final = rows[-1] if rows else {}
    for k in GUARD_LAST_KEYS:
        out[f"last_{k}"] = final.get(k, "")
    return out


def summary_extrema(rows: List[Dict[str, str]]) -> Dict[str, object]:
    out: Dict[str, object] = {"summaryRows": len(rows)}
    extrema = {
        "min_minN": ("minN", min),
        "max_stdN": ("stdN", max),
        "max_maxN": ("maxN", max),
        "min_totalMass": ("totalMass", min),
        "max_totalMass": ("totalMass", max),
        "max_kBTEstimate": ("kBTEstimate", max),
        "max_meanKinetic": ("meanKinetic", max),
    }
    for out_key, (src, fn) in extrema.items():
        vals = numeric_series(rows, src)
        out[out_key] = "" if not vals else repr(fn(vals))
    # First summary step at which global minN is zero.  This is not a recirculation-zone
    # measurement, but it is a useful coarse warning for catastrophic support loss.
    first_zero = ""
    for r in rows:
        v = as_float(r.get("minN"))
        if v is not None and v <= 0.0:
            first_zero = r.get("step", "")
            break
    out["firstStepMinNZero"] = first_zero
    return out


def build_rows(manifest_rows: List[Dict[str, str]]) -> List[Dict[str, object]]:
    out: List[Dict[str, object]] = []
    for m in manifest_rows:
        root = Path(m.get("runRoot", ""))
        summary_rows = read_csv_rows(root / "output" / "summary_runtime.csv")
        final = summary_rows[-1] if summary_rows else {}
        row: Dict[str, object] = {
            "caseName": m.get("caseName", ""),
            "modeName": m.get("modeName", ""),
            "uin": m.get("uin", ""),
            "nmin": m.get("nmin", ""),
            "ntarget": m.get("ntarget", ""),
            "nmax": m.get("nmax", ""),
            "exitCode": m.get("exitCode", ""),
            "runRoot": str(root),
        }
        for k in SUMMARY_KEYS:
            row[f"final_{k}"] = final.get(k, "")
        for k, v in summary_extrema(summary_rows).items():
            row[k] = v
        for k, v in aggregate_survey(root).items():
            row[f"survey_{k}"] = v
        for k, v in aggregate_guard(root).items():
            row[f"guard_{k}"] = v
        out.append(row)
    return out


def delta_rows(per: List[Dict[str, object]]) -> List[Dict[str, object]]:
    classic: Dict[str, Dict[str, object]] = {}
    for r in per:
        if str(r.get("modeName")) == "classic":
            classic[str(r.get("caseName"))] = r
    rows: List[Dict[str, object]] = []
    delta_keys = [
        "final_totalMass", "final_Px", "final_Py", "final_meanKinetic", "final_kBTEstimate",
        "final_meanN", "final_stdN", "final_minN", "final_maxN", "max_stdN",
        "survey_final_poorCells", "survey_max_poorCells", "survey_final_emptyCells", "survey_max_emptyCells",
        "survey_final_stdNActive", "survey_max_stdNActive", "survey_final_massRelRmsWet",
    ]
    for r in per:
        base = classic.get(str(r.get("caseName")))
        if not base:
            continue
        d: Dict[str, object] = {
            "caseName": r.get("caseName", ""),
            "modeName": r.get("modeName", ""),
            "uin": r.get("uin", ""),
            "nmin": r.get("nmin", ""),
            "ntarget": r.get("ntarget", ""),
            "nmax": r.get("nmax", ""),
        }
        for k in delta_keys:
            a = as_float(base.get(k)); b = as_float(r.get(k))
            d[f"delta_{k}"] = "" if a is None or b is None else repr(b - a)
        d["guard_sum_splitApplied"] = r.get("guard_sum_splitApplied", "")
        d["guard_sum_mergeApplied"] = r.get("guard_sum_mergeApplied", "")
        d["guard_sum_poorCells"] = r.get("guard_sum_poorCells", "")
        d["guard_sum_richCells"] = r.get("guard_sum_richCells", "")
        d["guard_maxMassError"] = r.get("guard_max_maxAbsCellMassError", "")
        d["guard_maxMomentumError"] = r.get("guard_max_maxAbsCellMomentumError", "")
        d["guard_maxKrelError0298"] = r.get("guard_max_maxAbsCellKrelError0298", "")
        d["guard_excludedOpen0299"] = r.get("guard_sum_excludedOpenBoundaryCells0299", "")
        rows.append(d)
    return rows


def timeseries_rows(manifest_rows: List[Dict[str, str]]) -> List[Dict[str, object]]:
    out: List[Dict[str, object]] = []
    for m in manifest_rows:
        root = Path(m.get("runRoot", ""))
        # Runtime summary.
        for r in read_csv_rows(root / "output" / "summary_runtime.csv"):
            out.append({
                "source": "summary", "caseName": m.get("caseName", ""), "modeName": m.get("modeName", ""),
                "uin": m.get("uin", ""), "step": r.get("step", ""), "time": r.get("time", ""),
                "minN": r.get("minN", ""), "stdN": r.get("stdN", ""), "maxN": r.get("maxN", ""),
                "totalMass": r.get("totalMass", ""), "Px": r.get("Px", ""), "Py": r.get("Py", ""),
                "kBTEstimate": r.get("kBTEstimate", ""), "nFluidParticles": r.get("nFluidParticles", ""),
                "nInactiveParticles": r.get("nInactiveParticles", ""),
            })
        # Passive support survey.
        for p in glob.glob(str(root / "**" / "cuda_resampling_support_survey_0295.csv"), recursive=True):
            for r in read_csv_rows(Path(p)):
                out.append({
                    "source": "survey0295", "caseName": m.get("caseName", ""), "modeName": m.get("modeName", ""),
                    "uin": m.get("uin", ""), "step": r.get("step", ""), "time": "",
                    "emptyCells": r.get("emptyCells", ""), "poorCells": r.get("poorCells", ""),
                    "richCells": r.get("richCells", ""), "stdNActive": r.get("stdNActive", ""),
                    "minNWet": r.get("minNWet", ""), "maxNWet": r.get("maxNWet", ""),
                    "massRelRmsWet": r.get("massRelRmsWet", ""), "kBTWeighted": r.get("kBTWeighted", ""),
                })
        # Active guard diagnostics.
        for p in glob.glob(str(root / "**" / "cuda_resampling_population_guard_0297.csv"), recursive=True):
            for r in read_csv_rows(Path(p)):
                out.append({
                    "source": "guard0297", "caseName": m.get("caseName", ""), "modeName": m.get("modeName", ""),
                    "uin": m.get("uin", ""), "step": r.get("step", ""), "time": "",
                    "poorCells": r.get("poorCells", ""), "richCells": r.get("richCells", ""),
                    "splitApplied": r.get("splitApplied", ""), "mergeApplied": r.get("mergeApplied", ""),
                    "maxAbsCellMassError": r.get("maxAbsCellMassError", ""),
                    "maxAbsCellMomentumError": r.get("maxAbsCellMomentumError", ""),
                    "maxAbsCellKrelError0298": r.get("maxAbsCellKrelError0298", ""),
                })
    return out


def write_csv(path: Path, rows: List[Dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields: List[str] = []
    seen = set()
    for r in rows:
        for k in r.keys():
            if k not in seen:
                seen.add(k); fields.append(k)
    with path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def main(argv: List[str]) -> int:
    if len(argv) < 3:
        print("usage: analyze_cuda_resampling_backward_step_long_0301.py RUN_MANIFEST OUT_DIR", file=sys.stderr)
        return 2
    manifest = Path(argv[1])
    out_dir = Path(argv[2])
    manifest_rows = read_manifest(manifest)
    per = build_rows(manifest_rows)
    deltas = delta_rows(per)
    ts = timeseries_rows(manifest_rows)
    write_csv(out_dir / "cuda_resampling_backward_step_long_0301_per_run.csv", per)
    write_csv(out_dir / "cuda_resampling_backward_step_long_0301_vs_classic.csv", deltas)
    write_csv(out_dir / "cuda_resampling_backward_step_long_0301_timeseries.csv", ts)

    failed = [r for r in manifest_rows if str(r.get("exitCode", "0")) != "0"]
    total_split = sum(as_float(r.get("guard_sum_splitApplied")) or 0.0 for r in per)
    max_mass_err = max([as_float(r.get("guard_max_maxAbsCellMassError")) or 0.0 for r in per] or [0.0])
    max_mom_err = max([as_float(r.get("guard_max_maxAbsCellMomentumError")) or 0.0 for r in per] or [0.0])
    max_krel_err = max([as_float(r.get("guard_max_maxAbsCellKrelError0298")) or 0.0 for r in per] or [0.0])
    print(f"[0301-analyze] runs={len(manifest_rows)} failedRuns={len(failed)} totalSplit={total_split:g} maxMassErr={max_mass_err:g} maxMomentumErr={max_mom_err:g} maxKrelErr0298={max_krel_err:g}")
    print(f"[0301-analyze] wrote={out_dir / 'cuda_resampling_backward_step_long_0301_per_run.csv'}")
    print(f"[0301-analyze] wrote={out_dir / 'cuda_resampling_backward_step_long_0301_vs_classic.csv'}")
    print(f"[0301-analyze] wrote={out_dir / 'cuda_resampling_backward_step_long_0301_timeseries.csv'}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

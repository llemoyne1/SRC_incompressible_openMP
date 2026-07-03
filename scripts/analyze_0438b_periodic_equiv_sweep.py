#!/usr/bin/env python3
"""Aggregate 0438 periodic path-equivalence replicate/sweep runs.

This script intentionally stays outside the solver.  It collects the per-run
0438 summary CSVs produced by:
  - run_0438_periodic_shear_wave_path_matrix.sh
  - run_0438_periodic_taylor_green_path_matrix.sh
and reports seed/gamma variability for the matching comparisons:
  src-resampling    vs src
  src-q6-resampling vs src-q6
"""
from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path
from statistics import mean, pstdev
from typing import Dict, Iterable, List

FIELDS = [
    "ampFinalRelDeltaVsRef",
    "ampRatioRelDeltaVsRef",
    "nuEffEstimateRelDeltaVsRef",
    "kBTEstimateRelDeltaVsRef",
    "totalMassRelDeltaVsRef",
    "meanNRelDeltaVsRef",
    "stdNRelDeltaVsRef",
    "elapsed_s",
    "ampFinal",
    "nuEffEstimate",
    "kBTEstimate",
    "meanN",
    "stdN",
    "resampComputed",
    "resampPoorCells",
    "resampRichCells",
    "resampTransferPairs",
    "nFluidParticles",
    "totalMass",
]


def f(value: object) -> float:
    try:
        x = float(value)  # type: ignore[arg-type]
        return x if math.isfinite(x) else float("nan")
    except Exception:
        return float("nan")


def read_rows(path: Path) -> List[Dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def clean_float(x: float) -> str:
    if not math.isfinite(x):
        return ""
    return f"{x:.17g}"


def stat(values: Iterable[float]) -> Dict[str, float]:
    vals = [v for v in values if math.isfinite(v)]
    if not vals:
        return {"n": 0, "mean": float("nan"), "std": float("nan"), "min": float("nan"), "max": float("nan"), "max_abs": float("nan")}
    return {
        "n": len(vals),
        "mean": mean(vals),
        "std": pstdev(vals) if len(vals) > 1 else 0.0,
        "min": min(vals),
        "max": max(vals),
        "max_abs": max(abs(v) for v in vals),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True, help="CSV written by run_0438b_periodic_equiv_sweep.sh")
    ap.add_argument("--csv", required=True)
    ap.add_argument("--markdown", required=True)
    args = ap.parse_args()

    manifest = Path(args.manifest)
    rows_out: List[Dict[str, str]] = []
    if not manifest.is_file():
        raise SystemExit(f"missing manifest: {manifest}")

    with manifest.open(newline="", encoding="utf-8") as stream:
        for item in csv.DictReader(stream):
            case = item.get("case", "")
            root = Path(item.get("root", ""))
            summary_name = "periodic_shear_wave_summary_0438.csv" if case == "shear" else "periodic_taylor_green_summary_0438.csv"
            summary_path = root / summary_name
            for row in read_rows(summary_path):
                out = dict(item)
                out["summary"] = str(summary_path)
                for k, v in row.items():
                    out[k] = v
                rows_out.append(out)

    out_csv = Path(args.csv)
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    keys = ["case", "gamma", "steps", "seed", "root", "mode", "exit_code", "passBasic"] + FIELDS + ["summary"]
    seen = []
    for k in keys:
        if k not in seen:
            seen.append(k)
    for r in rows_out:
        for k in r:
            if k not in seen:
                seen.append(k)
    with out_csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=seen)
        writer.writeheader()
        for r in rows_out:
            writer.writerow({k: r.get(k, "") for k in seen})

    groups: Dict[tuple, List[Dict[str, str]]] = defaultdict(list)
    for r in rows_out:
        groups[(r.get("case", ""), r.get("gamma", ""), r.get("steps", ""), r.get("mode", ""))].append(r)

    md = []
    md.append("# 0438b periodic path-equivalence sweep")
    md.append("")
    md.append("Scope: periodic, wall-free, no chi/Darcy, no inlet/outlet.")
    md.append("")
    md.append(f"Rows collected: **{len(rows_out)}**")
    md.append("")
    md.append("## Matching resampling comparisons")
    md.append("")
    md.append("Only these deltas are physically interpreted:")
    md.append("")
    md.append("- `src-resampling` vs `src`")
    md.append("- `src-q6-resampling` vs `src-q6`")
    md.append("")
    md.append("| case | gamma | steps | mode | n | mean Δnu | std Δnu | max |Δnu| | mean Δamp | max |Δamp| | mean elapsed_s | max resampPairs |")
    md.append("| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for key in sorted(groups):
        case, gamma, steps, mode = key
        rs = groups[key]
        if mode not in ("src-resampling", "src-q6-resampling"):
            continue
        nu = stat(f(r.get("nuEffEstimateRelDeltaVsRef", "")) for r in rs)
        amp = stat(f(r.get("ampFinalRelDeltaVsRef", "")) for r in rs)
        elapsed = stat(f(r.get("elapsed_s", "")) for r in rs)
        pairs = stat(f(r.get("resampTransferPairs", "")) for r in rs)
        md.append(
            f"| {case} | {gamma} | {steps} | {mode} | {nu['n']} | "
            f"{clean_float(nu['mean'])} | {clean_float(nu['std'])} | {clean_float(nu['max_abs'])} | "
            f"{clean_float(amp['mean'])} | {clean_float(amp['max_abs'])} | "
            f"{clean_float(elapsed['mean'])} | {clean_float(pairs['max'])} |"
        )
    md.append("")
    md.append(f"Flat CSV: `{out_csv}`")
    out_md = Path(args.markdown)
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text("\n".join(md) + "\n", encoding="utf-8")
    print(f"[0438b-aggregate] csv={out_csv}")
    print(f"[0438b-aggregate] markdown={out_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

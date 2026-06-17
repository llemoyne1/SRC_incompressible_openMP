#!/usr/bin/env python3
"""0350/topo: compact NACA polar-proxy postprocessing.

Reads the 0349 NACA sweep summary, then reads each 0348b window-statistics CSV
and writes one compact row per angle of attack.  This is a postprocessor only:
no solver changes and no CUDA dependency.
"""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from typing import Dict, List


def fget(row: Dict[str, str], key: str, default: float = float("nan")) -> float:
    try:
        return float(row.get(key, ""))
    except Exception:
        return default


def read_one_row_csv(path: Path) -> Dict[str, str]:
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise ValueError(f"empty CSV: {path}")
    return rows[0]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", required=True, help="naca_sweep_0349_summary.csv")
    ap.add_argument("--out", required=True, help="Output compact polar proxy CSV")
    ap.add_argument("--lift-sign", type=float, default=-1.0,
                    help="Multiplier applied to liftProxy_mean/std. Use -1 if positive AoA produced negative liftProxy in the current convention.")
    ap.add_argument("--drag-sign", type=float, default=1.0,
                    help="Multiplier applied to dragProxy_mean/std")
    args = ap.parse_args()

    summary = Path(args.summary)
    base_dir = summary.parent
    out = Path(args.out)
    rows_out: List[Dict[str, object]] = []

    with summary.open(newline="") as f:
        summary_rows = list(csv.DictReader(f))
    if not summary_rows:
        raise SystemExit(f"empty summary: {summary}")

    for r in summary_rows:
        naca = r.get("naca", "")
        aoa = float(r.get("aoaDeg", "nan"))
        stats_path = Path(r.get("windowStatsCsv", ""))
        if not stats_path.is_absolute():
            stats_path = Path(stats_path)
        stats = read_one_row_csv(stats_path)

        drag_mean_raw = fget(stats, "dragProxy_mean")
        drag_std_raw = fget(stats, "dragProxy_std")
        lift_mean_raw = fget(stats, "liftProxy_mean")
        lift_std_raw = fget(stats, "liftProxy_std")

        drag_mean = args.drag_sign * drag_mean_raw
        drag_std = abs(args.drag_sign) * drag_std_raw
        lift_mean = args.lift_sign * lift_mean_raw
        lift_std = abs(args.lift_sign) * lift_std_raw

        eps = 1.0e-30
        rows_out.append({
            "naca": naca,
            "aoaDeg": aoa,
            "dragProxy_mean_raw": drag_mean_raw,
            "liftProxy_mean_raw": lift_mean_raw,
            "dragProxy_mean": drag_mean,
            "dragProxy_std": drag_std,
            "liftProxy_mean": lift_mean,
            "liftProxy_std": lift_std,
            "liftOverDragProxy": lift_mean / max(abs(drag_mean), eps) if math.isfinite(lift_mean) and math.isfinite(drag_mean) else float("nan"),
            "absLiftOverAbsDrag": abs(lift_mean) / max(abs(drag_mean), eps) if math.isfinite(lift_mean) and math.isfinite(drag_mean) else float("nan"),
            "darcyPower_mean": fget(stats, "darcyPower_mean"),
            "darcyPower_std": fget(stats, "darcyPower_std"),
            "solidLeakOverSpeed_mean": fget(stats, "solidLeakOverSpeed_mean"),
            "meanSpeedRms_mean": fget(stats, "meanSpeedRms_mean"),
            "solidLeakRms_mean": fget(stats, "solidLeakRms_mean"),
            "meanChi_mean": fget(stats, "meanChi_mean"),
            "meanAlpha_mean": fget(stats, "meanAlpha_mean"),
            "windowRows": int(fget(stats, "windowRows", 0)),
            "stepFirst": fget(stats, "stepFirst"),
            "stepLast": fget(stats, "stepLast"),
            "timeFirst": fget(stats, "timeFirst"),
            "timeLast": fget(stats, "timeLast"),
            "liftSign": args.lift_sign,
            "dragSign": args.drag_sign,
            "windowStatsCsv": r.get("windowStatsCsv", ""),
            "benchmarkCsv": r.get("benchmarkCsv", ""),
            "chiFile": r.get("chiFile", ""),
        })

    rows_out.sort(key=lambda x: float(x["aoaDeg"]))

    out.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows_out[0].keys())
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for row in rows_out:
            w.writerow(row)

    print(f"[0350-naca-polar] summary={summary}")
    print(f"[0350-naca-polar] rows={len(rows_out)} out={out}")
    print("[0350-naca-polar] compact table:")
    for row in rows_out:
        print(f"  naca={row['naca']} aoa={row['aoaDeg']:+g} drag={row['dragProxy_mean']:.8g} lift={row['liftProxy_mean']:.8g} L/D={row['liftOverDragProxy']:.8g} power={row['darcyPower_mean']:.8g}")


if __name__ == "__main__":
    main()

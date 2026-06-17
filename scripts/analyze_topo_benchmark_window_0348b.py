#!/usr/bin/env python3
"""0348b/topo: window statistics for topo_benchmark_0348.csv.

The script is deliberately post-processing only: it does not modify solver
outputs and does not require CUDA.  It computes stable final-window averages for
the cell-based Darcy/Brinkman benchmark observables introduced in 0348a.
"""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from typing import Dict, List


DEFAULT_COLUMNS = [
    "darcyPower",
    "darcyPowerPerMass",
    "meanSpeedRms",
    "solidLeakRms",
    "darcyForceX",
    "darcyForceY",
    "dragProxy",
    "liftProxy",
    "meanChi",
    "meanAlpha",
]


def parse_float(x: str) -> float:
    try:
        return float(x)
    except Exception:
        return float("nan")


def mean(vals: List[float]) -> float:
    vals = [v for v in vals if math.isfinite(v)]
    return sum(vals) / len(vals) if vals else float("nan")


def std(vals: List[float], mu: float | None = None) -> float:
    vals = [v for v in vals if math.isfinite(v)]
    if not vals:
        return float("nan")
    if mu is None or not math.isfinite(mu):
        mu = sum(vals) / len(vals)
    return math.sqrt(sum((v - mu) ** 2 for v in vals) / len(vals))


def finite_min(vals: List[float]) -> float:
    vals = [v for v in vals if math.isfinite(v)]
    return min(vals) if vals else float("nan")


def finite_max(vals: List[float]) -> float:
    vals = [v for v in vals if math.isfinite(v)]
    return max(vals) if vals else float("nan")


def read_rows(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def select_window(rows: List[Dict[str, str]], tail_fraction: float, step_min: int | None, time_min: float | None) -> List[Dict[str, str]]:
    if not rows:
        return []
    selected = rows
    if step_min is not None:
        selected = [r for r in selected if parse_float(r.get("step", "nan")) >= step_min]
    if time_min is not None:
        selected = [r for r in selected if parse_float(r.get("time", "nan")) >= time_min]
    if step_min is None and time_min is None:
        tail_fraction = max(0.0, min(1.0, tail_fraction))
        n = max(1, int(math.ceil(len(rows) * tail_fraction)))
        selected = rows[-n:]
    return selected


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True, help="Path to topo_benchmark_0348.csv")
    ap.add_argument("--out", required=True, help="Output one-line CSV with window statistics")
    ap.add_argument("--tail-fraction", type=float, default=0.5, help="Final fraction of rows to average when no step/time lower bound is provided")
    ap.add_argument("--step-min", type=int, default=None, help="Optional lower step bound for the averaging window")
    ap.add_argument("--time-min", type=float, default=None, help="Optional lower time bound for the averaging window")
    ap.add_argument("--columns", default=",".join(DEFAULT_COLUMNS), help="Comma-separated numeric columns to summarize")
    args = ap.parse_args()

    src = Path(args.csv)
    out = Path(args.out)
    rows = read_rows(src)
    if not rows:
        raise SystemExit(f"empty CSV: {src}")

    win = select_window(rows, args.tail_fraction, args.step_min, args.time_min)
    if not win:
        raise SystemExit(f"empty selected window for {src}")

    cols = [c.strip() for c in args.columns.split(",") if c.strip()]
    result: Dict[str, str | float | int] = {
        "sourceCsv": str(src),
        "nRows": len(rows),
        "windowRows": len(win),
        "tailFraction": args.tail_fraction,
        "stepMinRequested": "" if args.step_min is None else args.step_min,
        "timeMinRequested": "" if args.time_min is None else args.time_min,
        "stepFirst": parse_float(win[0].get("step", "nan")),
        "stepLast": parse_float(win[-1].get("step", "nan")),
        "timeFirst": parse_float(win[0].get("time", "nan")),
        "timeLast": parse_float(win[-1].get("time", "nan")),
    }

    means: Dict[str, float] = {}
    for col in cols:
        vals = [parse_float(r.get(col, "nan")) for r in win]
        mu = mean(vals)
        means[col] = mu
        result[f"{col}_mean"] = mu
        result[f"{col}_std"] = std(vals, mu)
        result[f"{col}_min"] = finite_min(vals)
        result[f"{col}_max"] = finite_max(vals)
        result[f"{col}_last"] = parse_float(win[-1].get(col, "nan"))

    drag = means.get("dragProxy", float("nan"))
    lift = means.get("liftProxy", float("nan"))
    speed = means.get("meanSpeedRms", float("nan"))
    leak = means.get("solidLeakRms", float("nan"))
    power = means.get("darcyPower", float("nan"))
    eps = 1.0e-30
    result["absLiftOverAbsDrag_mean"] = abs(lift) / max(abs(drag), eps) if math.isfinite(lift) and math.isfinite(drag) else float("nan")
    result["solidLeakOverSpeed_mean"] = leak / max(speed, eps) if math.isfinite(leak) and math.isfinite(speed) else float("nan")
    result["powerOverDragAbs_mean"] = power / max(abs(drag), eps) if math.isfinite(power) and math.isfinite(drag) else float("nan")

    out.parent.mkdir(parents=True, exist_ok=True)
    fields = list(result.keys())
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerow(result)

    print(f"[0348b-window] source={src}")
    print(f"[0348b-window] rows={len(rows)} windowRows={len(win)} step={result['stepFirst']}..{result['stepLast']} time={result['timeFirst']}..{result['timeLast']}")
    print(f"[0348b-window] out={out}")
    print(f"[0348b-window] dragMean={result.get('dragProxy_mean')} liftMean={result.get('liftProxy_mean')} powerMean={result.get('darcyPower_mean')}")


if __name__ == "__main__":
    main()

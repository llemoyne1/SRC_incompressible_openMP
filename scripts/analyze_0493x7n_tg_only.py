#!/usr/bin/env python3
# 0493x7n TG-only adapter.
# This file does not reimplement Taylor--Green analysis. It imports the
# canonical 0493w1 analyzer, uses its argument parser, calls analyze_tg(a),
# and publishes only viscosity-related outputs for partial x7n campaigns.

from __future__ import annotations

import argparse
import csv
import importlib
import json
import sys
from pathlib import Path


def split_x7n_args(argv):
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--calibration-path", required=True)
    ap.add_argument("--experiments", required=True)
    ap.add_argument("--q6-density-relaxation-time", type=float, required=True)
    ap.add_argument("--projection-tolerance", type=float, required=True)
    ap.add_argument("--projection-max-iterations", type=int, required=True)
    ns, remaining = ap.parse_known_args(argv)
    q6_g_f = ns.calibration_path in {"src-q6-g-f", "q6-g-f", "src+q6-g-f"}
    meta = {
        "calibrationPath": ns.calibration_path,
        "experiments": ns.experiments.split(),
        "q6GFEnabled": q6_g_f,
        "q6DensityRelaxationTime": (
            ns.q6_density_relaxation_time if q6_g_f else None
        ),
        "projectionTolerance": ns.projection_tolerance,
        "projectionMaxIterations": ns.projection_max_iterations,
    }
    return remaining, meta


def write_single_csv(path, row):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(row))
        writer.writeheader()
        writer.writerow(row)


def main():
    remaining, meta = split_x7n_args(sys.argv[1:])

    scripts_dir = Path(__file__).resolve().parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    base = importlib.import_module("analyze_0493w1_src_fluid_calibrator")

    saved_argv = sys.argv[:]
    try:
        sys.argv = [saved_argv[0]] + remaining
        a = base.parse_args()
    finally:
        sys.argv = saved_argv

    result = base.analyze_tg(a)
    if not isinstance(result, tuple) or len(result) != 2:
        raise RuntimeError(
            "0493w1 analyze_tg API changed: expected (series, result)"
        )
    tg_series, tg_result = result

    required = (
        "nu",
        "fitR2",
        "fitPoints",
        "fitStartIndex",
        "fitEndIndex",
        "nuWindowStd",
        "nuWindowMin",
        "nuWindowMax",
    )
    missing = [k for k in required if k not in tg_result]
    if missing:
        raise RuntimeError(
            "0493w1 analyze_tg result API changed; missing keys: "
            + ", ".join(missing)
        )

    analysis = Path(a.root) / "analysis"
    analysis.mkdir(parents=True, exist_ok=True)

    base.write_csv(analysis / "tg_decay_0493w1.csv", tg_series)

    nu = float(tg_result["nu"])
    r2 = float(tg_result["fitR2"])
    viscosity_status = base._property_status(nu, r2, 0.98, 0.93)

    ax = float(a.Lx) / int(a.Nx)
    ay = float(a.Ly) / int(a.Ny)
    number_density = float(a.gamma) / (ax * ay)
    mass_density = number_density * float(a.mass)

    summary = {
        "schema": "0493x7n-tg-only-v1",
        **meta,
        "viscosityStatus": viscosity_status,
        "viscosityKinematic": nu,
        "viscosityDynamic2D": mass_density * nu,
        "fitR2": r2,
        "fitPoints": int(tg_result["fitPoints"]),
        "fitStartIndex": int(tg_result["fitStartIndex"]),
        "fitEndIndex": int(tg_result["fitEndIndex"]),
        "fitWindowCandidates": int(tg_result.get("fitWindowCandidates", 0)),
        "fitStableWindows": int(tg_result.get("fitStableWindows", 0)),
        "fitStableFallback": bool(tg_result.get("fitStableFallback", False)),
        "viscosityWindowStd": float(tg_result["nuWindowStd"]),
        "viscosityWindowMin": float(tg_result["nuWindowMin"]),
        "viscosityWindowMax": float(tg_result["nuWindowMax"]),
        "Lx": float(a.Lx),
        "Ly": float(a.Ly),
        "Nx": int(a.Nx),
        "Ny": int(a.Ny),
        "cellX": ax,
        "cellY": ay,
        "gamma": float(a.gamma),
        "dt": float(a.dt),
        "kBT": float(a.kBT),
        "particleMass": float(a.mass),
        "numberDensity2D": number_density,
        "massDensity2D": mass_density,
        "tgModeX": int(a.tg_mode_x),
        "tgModeY": int(a.tg_mode_y),
        "tgAmplitudeRequested": float(a.tg_amplitude),
    }

    summary["canonicalTGResultKeys"] = sorted(tg_result.keys())

    json_path = analysis / "tg_calibration_0493x7n.json"
    json_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    write_single_csv(analysis / "tg_calibration_0493x7n.csv", summary)

    print(
        "[0493x7n-tg] "
        f"path={meta['calibrationPath']} "
        f"status={viscosity_status} "
        f"nu={nu:.10g} "
        f"R2={r2:.8g} "
        f"windowStd={float(tg_result['nuWindowStd']):.6g} "
        f"fitPoints={int(tg_result['fitPoints'])} "
        f"fitIndex={int(tg_result['fitStartIndex'])}:{int(tg_result['fitEndIndex'])} "
        f"candidates={int(tg_result.get('fitWindowCandidates', 0))} "
        f"stable={int(tg_result.get('fitStableWindows', 0))} "
        f"stableFallback={str(bool(tg_result.get('fitStableFallback', False))).lower()}"
    )
    print(f"[0493x7n-tg] series={analysis / 'tg_decay_0493w1.csv'}")
    print(f"[0493x7n-tg] summary={json_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

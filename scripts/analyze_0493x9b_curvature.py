#!/usr/bin/env python3
"""Compare passive x9a and x9b curvature diagnostics without pandas."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

REQ = {
    "step", "crossingFaces", "validCurvatureFaces", "validFraction",
    "normalOutwardFraction", "normalFaceAlignmentMean", "curvatureMean",
    "curvatureRms", "curvatureStd", "curvatureAbsMean", "curvatureAbsMax",
    "normalBuildSeconds", "curvatureBuildSeconds", "faceAuditSeconds",
    "residentBytes", "curvatureDefinition",
}


def load_last(path: Path):
    if not path.exists():
        raise SystemExit(f"missing audit: {path}")
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"empty audit: {path}")
    missing = REQ.difference(rows[0].keys())
    if missing:
        raise SystemExit(f"{path}: missing columns: {sorted(missing)}")
    return rows[-1], len(rows)


def f(row, key):
    return float(row[key])


def i(row, key):
    return int(float(row[key]))


def metrics(row):
    return {
        "step": i(row, "step"),
        "crossingFaces": i(row, "crossingFaces"),
        "validCurvatureFaces": i(row, "validCurvatureFaces"),
        "validFraction": f(row, "validFraction"),
        "normalOutwardFraction": f(row, "normalOutwardFraction"),
        "normalFaceAlignmentMean": f(row, "normalFaceAlignmentMean"),
        "curvatureMean": f(row, "curvatureMean"),
        "curvatureRms": f(row, "curvatureRms"),
        "curvatureStd": f(row, "curvatureStd"),
        "curvatureAbsMean": f(row, "curvatureAbsMean"),
        "curvatureAbsMax": f(row, "curvatureAbsMax"),
        "normalBuildSeconds": f(row, "normalBuildSeconds"),
        "curvatureBuildSeconds": f(row, "curvatureBuildSeconds"),
        "faceAuditSeconds": f(row, "faceAuditSeconds"),
        "residentBytes": i(row, "residentBytes"),
        "curvatureDefinition": row["curvatureDefinition"],
    }


def ratio(a, b):
    return a / b if b != 0.0 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--x9a", type=Path, required=True)
    ap.add_argument("--x9b", type=Path, required=True)
    ap.add_argument("--json", type=Path, required=True)
    ap.add_argument("--radius-x", type=float, required=True)
    ap.add_argument("--radius-y", type=float, required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--ny", type=int, required=True)
    args = ap.parse_args()

    ra, rows_a = load_last(args.x9a)
    rb, rows_b = load_last(args.x9b)
    a, b = metrics(ra), metrics(rb)
    if a["step"] != b["step"]:
        raise SystemExit(f"audit step mismatch x9a={a['step']} x9b={b['step']}")

    dx = args.Lx / args.nx
    dy = args.Ly / args.ny
    circle = abs(args.radius_x - args.radius_y) <= 1e-12 * max(1.0, args.radius_x, args.radius_y)
    quasi_plane = max(args.radius_x, args.radius_y) > 10.0 * max(args.Lx, args.Ly)
    structural_a = (
        a["crossingFaces"] > 0 and a["validFraction"] > 0.999 and
        a["normalOutwardFraction"] > 0.999 and math.isfinite(a["curvatureMean"]) and
        math.isfinite(a["curvatureRms"]) and math.isfinite(a["curvatureAbsMax"])
    )
    structural_b = (
        b["crossingFaces"] > 0 and b["validFraction"] > 0.999 and
        b["normalOutwardFraction"] > 0.999 and math.isfinite(b["curvatureMean"]) and
        math.isfinite(b["curvatureRms"]) and math.isfinite(b["curvatureAbsMax"])
    )
    if circle and not quasi_plane:
        structural_b = structural_b and b["curvatureMean"] > 0.0
    status = "PASS-structural" if structural_a and structural_b else "FAIL-structural"

    exact_circle = 1.0 / args.radius_x if circle else None
    def circle_errors(m):
        if exact_circle is None:
            return None, None
        rel_mean = (m["curvatureMean"] - exact_circle) / exact_circle
        rms_about = math.sqrt(m["curvatureStd"]**2 + (m["curvatureMean"] - exact_circle)**2)
        return rel_mean, rms_about / exact_circle
    a_rel_mean, a_rel_rms = circle_errors(a)
    b_rel_mean, b_rel_rms = circle_errors(b)

    report = {
        "status": status,
        "rowsX9a": rows_a,
        "rowsX9b": rows_b,
        "grid": [args.nx, args.ny],
        "cellSize": [dx, dy],
        "radiusX": args.radius_x,
        "radiusY": args.radius_y,
        "circle": circle,
        "quasiPlaneProxy": quasi_plane,
        "circleExactCurvature": exact_circle,
        "quasiPlaneCurvatureAtMinorAxisProxy": (
            min(args.radius_x, args.radius_y) / max(args.radius_x, args.radius_y)**2
            if quasi_plane else None
        ),
        "x9a": a,
        "x9b": b,
        "comparison": {
            "stdRatioX9bOverX9a": ratio(b["curvatureStd"], a["curvatureStd"]),
            "rmsRatioX9bOverX9a": ratio(b["curvatureRms"], a["curvatureRms"]),
            "absMeanRatioX9bOverX9a": ratio(b["curvatureAbsMean"], a["curvatureAbsMean"]),
            "absMaxRatioX9bOverX9a": ratio(b["curvatureAbsMax"], a["curvatureAbsMax"]),
            "circleRelativeMeanErrorX9a": a_rel_mean,
            "circleRelativeMeanErrorX9b": b_rel_mean,
            "circleRelativeRmsAboutExactX9a": a_rel_rms,
            "circleRelativeRmsAboutExactX9b": b_rel_rms,
        },
        "accuracyStatus": "DIAGNOSTIC-no-threshold-x9b",
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")

    cmp = report["comparison"]
    def fmt(v):
        return "n/a" if v is None else f"{v:.6g}"
    print(
        f"[0493x9b-analysis] status={status} crossings={b['crossingFaces']} "
        f"x9a[kMean={a['curvatureMean']:.8g} kStd={a['curvatureStd']:.8g} "
        f"absMean={a['curvatureAbsMean']:.8g} max={a['curvatureAbsMax']:.8g}] "
        f"x9b[kMean={b['curvatureMean']:.8g} kStd={b['curvatureStd']:.8g} "
        f"absMean={b['curvatureAbsMean']:.8g} max={b['curvatureAbsMax']:.8g}] "
        f"stdRatio={fmt(cmp['stdRatioX9bOverX9a'])} "
        f"absMeanRatio={fmt(cmp['absMeanRatioX9bOverX9a'])}"
    )
    if exact_circle is not None:
        print(
            f"[0493x9b-analysis] circleExact={exact_circle:.10g} "
            f"x9aRelMean={100*a_rel_mean:.3f}% x9aRelRms={100*a_rel_rms:.3f}% "
            f"x9bRelMean={100*b_rel_mean:.3f}% x9bRelRms={100*b_rel_rms:.3f}%"
        )
    print(f"[0493x9b-analysis] report={args.json}")
    return 0 if status.startswith("PASS") else 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Analyze passive 0493x9a curvature diagnostics without pandas."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def f(row, key):
    v = float(row[key])
    if not math.isfinite(v):
        raise RuntimeError(f"non-finite {key}={row[key]}")
    return v


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", type=Path, required=True)
    ap.add_argument("--json", type=Path, required=True)
    ap.add_argument("--radius-x", type=float, required=True)
    ap.add_argument("--radius-y", type=float, required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--ny", type=int, required=True)
    ap.add_argument("--min-valid-fraction", type=float, default=0.95)
    ap.add_argument("--min-outward-fraction", type=float, default=0.95)
    args = ap.parse_args()

    if not args.audit.exists():
        raise RuntimeError(f"missing audit {args.audit}")
    with args.audit.open(newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise RuntimeError("empty x9a curvature audit")

    required = {
        "step", "crossingFaces", "validCurvatureFaces", "validFraction",
        "normalOutwardFraction", "normalFaceAlignmentMean", "curvatureMean",
        "curvatureRms", "curvatureStd", "curvatureAbsMean", "curvatureAbsMax",
        "normalBuildSeconds", "curvatureBuildSeconds", "faceAuditSeconds",
        "residentBytes", "curvatureDefinition",
    }
    miss = required.difference(rows[0])
    if miss:
        raise RuntimeError(f"missing columns {sorted(miss)}")

    # Geometry accuracy is reported primarily from the first row because later
    # rows may already reflect physical particle motion.  The runner defaults to
    # one step, so this distinction is mostly future-proofing.
    r = rows[0]
    crossings = int(r["crossingFaces"])
    valid = int(r["validCurvatureFaces"])
    valid_fraction = f(r, "validFraction")
    outward_fraction = f(r, "normalOutwardFraction")
    alignment = f(r, "normalFaceAlignmentMean")
    kmean = f(r, "curvatureMean")
    krms = f(r, "curvatureRms")
    kstd = f(r, "curvatureStd")
    kabs = f(r, "curvatureAbsMean")
    kmax = f(r, "curvatureAbsMax")

    rx, ry = args.radius_x, args.radius_y
    if not (rx > 0 and ry > 0):
        raise RuntimeError("radii must be positive")
    dx, dy = args.Lx / args.nx, args.Ly / args.ny
    circle = abs(rx - ry) <= 1.0e-12 * max(rx, ry)
    a, b = max(rx, ry), min(rx, ry)
    ellipse_kappa_min = b / (a * a)
    ellipse_kappa_max = a / (b * b)
    circle_exact = 1.0 / rx if circle else None
    circle_rel_mean_error = (
        abs(kmean - circle_exact) / circle_exact if circle else None
    )
    circle_rel_rms_about_exact = (
        math.sqrt(max(0.0, krms * krms - 2.0 * circle_exact * kmean + circle_exact**2))
        / circle_exact if circle else None
    )
    quasi_plane = a >= 20.0 * max(args.Lx, args.Ly)
    plane_proxy_exact = b / (a * a) if quasi_plane else None
    hk_rms = math.sqrt(dx * dy) * krms

    structural = (
        crossings > 0 and valid > 0 and
        valid_fraction >= args.min_valid_fraction and
        outward_fraction >= args.min_outward_fraction and
        alignment > 0.0 and
        r["curvatureDefinition"].startswith("n=-grad(alpha)/|grad(alpha)|")
    )
    # The first x9a patch is intentionally diagnostic: do not manufacture an
    # accuracy threshold before seeing the calibrated 400x400 data.  Sign is a
    # real invariant for a convex ellipse and is therefore checked.
    sign_ok = True if quasi_plane else kmean > 0.0
    status = "PASS-structural" if structural and sign_ok else "FAIL-structural"

    report = {
        "status": status,
        "rows": len(rows),
        "firstStep": int(r["step"]),
        "grid": [args.nx, args.ny],
        "cellSize": [dx, dy],
        "radiusX": rx,
        "radiusY": ry,
        "semiAxisCells": [rx / dx, ry / dy],
        "circle": circle,
        "quasiPlaneProxy": quasi_plane,
        "crossingFaces": crossings,
        "validCurvatureFaces": valid,
        "validFraction": valid_fraction,
        "normalOutwardFraction": outward_fraction,
        "normalFaceAlignmentMean": alignment,
        "curvatureMean": kmean,
        "curvatureRms": krms,
        "curvatureStd": kstd,
        "curvatureAbsMean": kabs,
        "curvatureAbsMax": kmax,
        "hCurvatureRms": hk_rms,
        "ellipseAnalyticCurvatureMin": ellipse_kappa_min,
        "ellipseAnalyticCurvatureMax": ellipse_kappa_max,
        "circleExactCurvature": circle_exact,
        "circleRelativeMeanError": circle_rel_mean_error,
        "circleRelativeRmsAboutExact": circle_rel_rms_about_exact,
        "quasiPlaneCurvatureAtMinorAxisProxy": plane_proxy_exact,
        "normalBuildSeconds": f(r, "normalBuildSeconds"),
        "curvatureBuildSeconds": f(r, "curvatureBuildSeconds"),
        "faceAuditSeconds": f(r, "faceAuditSeconds"),
        "residentBytes": int(r["residentBytes"]),
        "accuracyStatus": "DIAGNOSTIC-no-threshold-x9a",
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")

    msg = (
        f"[0493x9a-analysis] status={status} crossings={crossings} "
        f"valid={valid_fraction:.4f} outward={outward_fraction:.4f} "
        f"align={alignment:.4f} kMean={kmean:.8g} kRms={krms:.8g} "
        f"kStd={kstd:.8g} h*kRms={hk_rms:.5g}"
    )
    if circle:
        msg += (
            f" circleExact={circle_exact:.8g} "
            f"relMeanErr={circle_rel_mean_error:.3%} "
            f"relRmsErr={circle_rel_rms_about_exact:.3%}"
        )
    if quasi_plane:
        msg += f" planeProxyK={plane_proxy_exact:.8g}"
    print(msg)
    print(f"[0493x9a-analysis] report={args.json}")
    return 0 if structural and sign_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

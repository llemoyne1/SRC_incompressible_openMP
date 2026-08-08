#!/usr/bin/env python3
"""Validate the 0493x6d guarded alpha=0.5 cut-face Q6 boundary."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def finite(row: dict[str, str], key: str) -> float:
    value = float(row[key])
    if not math.isfinite(value):
        raise RuntimeError(f"non-finite {key}: {row[key]}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    args = parser.parse_args()

    if not args.audit.exists():
        raise RuntimeError(f"missing x6d/x6c geometry audit: {args.audit}")
    with args.audit.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise RuntimeError("empty x6d geometry audit")

    required = {
        "step", "interfaceFaces", "cutFaceGeometryEnabled",
        "cutFaceGeometricFaces", "cutFaceLegacyFallbackFaces",
        "cutFaceSmallThetaFallbackFaces", "cutFaceThetaGuard",
        "cutFaceThetaMin", "cutFaceThetaMean", "cutFaceThetaMax",
        "halfIsoBracketFraction", "conservationRelativeError",
    }
    missing = required.difference(rows[0])
    if missing:
        raise RuntimeError(f"audit missing x6d columns: {sorted(missing)}")

    min_geometric_fraction = 1.0
    max_geometric_fraction = 0.0
    max_fallback_fraction = 0.0
    max_small_theta_fallback = 0
    global_theta_min = 1.0
    global_theta_max = 0.0
    max_conservation = 0.0
    all_enabled = True
    guard = None

    for row in rows:
        enabled = int(row["cutFaceGeometryEnabled"])
        faces = int(row["interfaceFaces"])
        geometric = int(row["cutFaceGeometricFaces"])
        fallback = int(row["cutFaceLegacyFallbackFaces"])
        small = int(row["cutFaceSmallThetaFallbackFaces"])
        theta_guard = finite(row, "cutFaceThetaGuard")
        theta_min = finite(row, "cutFaceThetaMin")
        theta_mean = finite(row, "cutFaceThetaMean")
        theta_max = finite(row, "cutFaceThetaMax")
        conservation = finite(row, "conservationRelativeError")

        if faces <= 0:
            raise RuntimeError(f"step {row['step']}: no interface faces")
        if geometric < 0 or fallback < 0 or geometric + fallback != faces:
            raise RuntimeError(
                f"step {row['step']}: inconsistent cut-face accounting "
                f"geometric={geometric} fallback={fallback} faces={faces}"
            )
        if small < 0 or small > fallback:
            raise RuntimeError(f"step {row['step']}: invalid small-theta fallback count")
        if not (0.0 < theta_guard < 1.0):
            raise RuntimeError(f"invalid cut-face theta guard: {theta_guard}")
        if geometric > 0:
            if not (theta_guard - 2e-9 <= theta_min <= theta_mean <= theta_max <= 1.0 + 2e-9):
                raise RuntimeError(
                    f"step {row['step']}: invalid geometric theta range "
                    f"min={theta_min} mean={theta_mean} max={theta_max} guard={theta_guard}"
                )
            global_theta_min = min(global_theta_min, theta_min)
            global_theta_max = max(global_theta_max, theta_max)

        frac = geometric / faces
        fallback_frac = fallback / faces
        min_geometric_fraction = min(min_geometric_fraction, frac)
        max_geometric_fraction = max(max_geometric_fraction, frac)
        max_fallback_fraction = max(max_fallback_fraction, fallback_frac)
        max_small_theta_fallback = max(max_small_theta_fallback, small)
        max_conservation = max(max_conservation, conservation)
        all_enabled = all_enabled and enabled == 1
        if guard is None:
            guard = theta_guard
        elif abs(guard - theta_guard) > 1.0e-15:
            raise RuntimeError("cut-face theta guard changed within run")

    first = rows[0]
    last = rows[-1]
    pass_like = all_enabled and max_conservation <= 1.0e-10 and max_geometric_fraction > 0.0
    report = {
        "status": "PASS-like" if pass_like else "FAIL-like",
        "rows": len(rows),
        "firstStep": int(first["step"]),
        "lastStep": int(last["step"]),
        "cutFaceThetaGuard": guard,
        "minGeometricFaceFraction": min_geometric_fraction,
        "maxGeometricFaceFraction": max_geometric_fraction,
        "maxLegacyFallbackFraction": max_fallback_fraction,
        "maxSmallThetaFallbackFaces": max_small_theta_fallback,
        "globalGeometricThetaMin": global_theta_min if global_theta_max > 0.0 else 0.0,
        "globalGeometricThetaMax": global_theta_max,
        "firstGeometricFaces": int(first["cutFaceGeometricFaces"]),
        "lastGeometricFaces": int(last["cutFaceGeometricFaces"]),
        "firstFallbackFaces": int(first["cutFaceLegacyFallbackFaces"]),
        "lastFallbackFaces": int(last["cutFaceLegacyFallbackFaces"]),
        "firstThetaMean": float(first["cutFaceThetaMean"]),
        "lastThetaMean": float(last["cutFaceThetaMean"]),
        "maxGeometryConservationError": max_conservation,
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")

    print(
        "[0493x6d-analysis] "
        f"status={report['status']} rows={report['rows']} "
        f"steps={report['firstStep']}..{report['lastStep']} "
        f"geometricFrac={report['minGeometricFaceFraction']:.3f}.."
        f"{report['maxGeometricFaceFraction']:.3f} "
        f"theta={report['globalGeometricThetaMin']:.3f}.."
        f"{report['globalGeometricThetaMax']:.3f} "
        f"fallbackMax={report['maxLegacyFallbackFraction']:.3f} "
        f"smallThetaFallbackMax={report['maxSmallThetaFallbackFaces']}"
    )
    return 0 if pass_like else 1


if __name__ == "__main__":
    raise SystemExit(main())

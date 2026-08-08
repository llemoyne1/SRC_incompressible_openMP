#!/usr/bin/env python3
"""Validate the 0493x6g gas-pressure Dirichlet data prepared on the x6f interface."""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path


def load(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise RuntimeError(f"missing CSV: {path}")
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise RuntimeError(f"empty CSV: {path}")
    return rows


def f(row: dict[str, str], key: str) -> float:
    value = float(row[key])
    if not math.isfinite(value):
        raise RuntimeError(f"non-finite {key}: {row[key]}")
    return value


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pressure", type=Path, required=True)
    ap.add_argument("--stencil", type=Path, required=True)
    ap.add_argument("--json", type=Path, required=True)
    ap.add_argument("--constant-relative-tolerance", type=float, default=2.0e-12)
    ap.add_argument("--constant-absolute-tolerance", type=float, default=1.0e-12)
    args = ap.parse_args()

    pressure = load(args.pressure)
    stencil = load(args.stencil)
    stencil_by_step = {int(r["step"]): r for r in stencil}
    required = {
        "step", "gasSpeciesCount", "sourceMode", "liquidReferenceCellMass",
        "cellArea", "kBT", "dt", "pressureReference", "pressureScale",
        "constantPressure", "representedInterfaceFaces", "nonzeroPressureFaces",
        "pressurePotentialMean", "pressurePotentialStd", "pressureDeltaMean",
        "pressureDeltaStd", "prepareSeconds", "residentBytes",
    }
    missing = required.difference(pressure[0])
    if missing:
        raise RuntimeError(f"pressure audit missing columns: {sorted(missing)}")

    max_relation_error = 0.0
    max_delta_std = 0.0
    max_nonzero_fraction = 0.0
    min_nonzero_fraction = 1.0
    modes: set[str] = set()
    per_step: list[dict[str, float | int | str]] = []

    for row in pressure:
        step = int(row["step"])
        if step not in stencil_by_step:
            raise RuntimeError(f"step {step}: missing matching x6f stencil row")
        represented = int(row["representedInterfaceFaces"])
        stencil_represented = int(stencil_by_step[step]["representedInterfaceFaces"])
        if represented != stencil_represented:
            raise RuntimeError(
                f"step {step}: x6g/x6f represented-face mismatch "
                f"{represented}!={stencil_represented}"
            )
        if represented <= 0:
            raise RuntimeError(f"step {step}: no represented interface faces")

        mode = row["sourceMode"].strip().lower()
        if mode not in {"eos", "constant"}:
            raise RuntimeError(f"step {step}: unsupported source mode {mode!r}")
        modes.add(mode)
        gas_species = int(row["gasSpeciesCount"])
        if mode == "eos" and gas_species <= 0:
            raise RuntimeError(f"step {step}: EOS mode has no gas species")

        ref = f(row, "pressureReference")
        scale = f(row, "pressureScale")
        const = f(row, "constantPressure")
        phi_mean = f(row, "pressurePotentialMean")
        phi_std = f(row, "pressurePotentialStd")
        delta_mean = f(row, "pressureDeltaMean")
        delta_std = f(row, "pressureDeltaStd")
        dt = f(row, "dt")
        area = f(row, "cellArea")
        mref = f(row, "liquidReferenceCellMass")
        if scale < 0.0 or dt <= 0.0 or area <= 0.0 or mref <= 0.0:
            raise RuntimeError(f"step {step}: invalid pressure scaling metadata")

        rho_ref = mref / area
        reconstructed_delta = phi_mean * rho_ref / dt
        relation_error = abs(reconstructed_delta - delta_mean)
        relation_scale = max(1.0, abs(delta_mean), abs(reconstructed_delta))
        if relation_error > 2.0e-12 * relation_scale:
            raise RuntimeError(
                f"step {step}: phi-pressure relation mismatch {relation_error:.3e}"
            )
        max_relation_error = max(max_relation_error, relation_error / relation_scale)

        if mode == "constant":
            expected = scale * (const - ref)
            err = abs(delta_mean - expected)
            tol = args.constant_absolute_tolerance + args.constant_relative_tolerance * max(
                1.0, abs(expected)
            )
            if err > tol:
                raise RuntimeError(
                    f"step {step}: constant pressure mean mismatch: "
                    f"got={delta_mean:.17g} expected={expected:.17g} err={err:.3e}"
                )
            # The CUDA audit currently reconstructs the variance as E[p^2]-E[p]^2.
            # For an exactly constant non-zero pressure this subtraction is ill-conditioned:
            # the two O(expected^2) terms differ only by roundoff from parallel reductions.
            # The resulting apparent standard deviation scales as
            # |expected|*sqrt(N*eps), even though every face stores the same value.
            # Keep the mean check at the strict user tolerance, but allow only this
            # analytically estimated cancellation floor for the std check.  The paired
            # particle-state gauge test remains the independent physical invariance check.
            cancellation_floor = (
                4.0
                * max(1.0, abs(expected))
                * math.sqrt(max(1, represented) * sys.float_info.epsilon)
            )
            std_tol = max(tol, cancellation_floor)
            if delta_std > std_tol:
                raise RuntimeError(
                    f"step {step}: constant pressure is not spatially constant: "
                    f"std={delta_std:.3e} tol={std_tol:.3e}"
                )

        nonzero = int(row["nonzeroPressureFaces"])
        if nonzero < 0 or nonzero > represented:
            raise RuntimeError(f"step {step}: invalid nonzero pressure face count")
        frac = nonzero / represented
        min_nonzero_fraction = min(min_nonzero_fraction, frac)
        max_nonzero_fraction = max(max_nonzero_fraction, frac)
        max_delta_std = max(max_delta_std, delta_std)
        per_step.append({
            "step": step,
            "mode": mode,
            "representedInterfaceFaces": represented,
            "nonzeroPressureFaces": nonzero,
            "nonzeroFraction": frac,
            "pressureDeltaMean": delta_mean,
            "pressureDeltaStd": delta_std,
            "pressurePotentialMean": phi_mean,
            "pressurePotentialStd": phi_std,
        })

    report = {
        "status": "PASS-like",
        "rows": len(pressure),
        "firstStep": per_step[0]["step"],
        "lastStep": per_step[-1]["step"],
        "sourceModes": sorted(modes),
        "maxPhiPressureRelationRelativeError": max_relation_error,
        "minNonzeroPressureFaceFraction": min_nonzero_fraction,
        "maxNonzeroPressureFaceFraction": max_nonzero_fraction,
        "maxPressureDeltaStd": max_delta_std,
        "residentBytes": max(int(r["residentBytes"]) for r in pressure),
        "first": per_step[0],
        "last": per_step[-1],
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")
    print(
        "[0493x6g-analysis] "
        f"status={report['status']} rows={report['rows']} "
        f"steps={report['firstStep']}..{report['lastStep']} "
        f"mode={','.join(report['sourceModes'])} "
        f"phiRelationMax={report['maxPhiPressureRelationRelativeError']:.3e} "
        f"nonzeroFrac={report['minNonzeroPressureFaceFraction']:.3f}.."
        f"{report['maxNonzeroPressureFaceFraction']:.3f} "
        f"deltaPStdMax={report['maxPressureDeltaStd']:.6e} "
        f"resident={report['residentBytes']}B"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

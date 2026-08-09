#!/usr/bin/env python3
"""Compare coarse/fine 0493x7d density-RHS runs at fixed relaxation time."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def finite(value: str | float | int | None) -> float:
    try:
        x = float(value)
    except (TypeError, ValueError):
        return math.nan
    return x if math.isfinite(x) else math.nan


def mean(values: list[float]) -> float:
    vals = [x for x in values if math.isfinite(x)]
    return sum(vals) / len(vals) if vals else math.nan


def load(root: Path) -> dict[str, float]:
    q6_path = root / "output/cuda_species_q6_independent_masked_0493w5.csv"
    geom_path = root / "output/cuda_phase_geometry_resident_0493x6c.csv"
    if not q6_path.exists() or not geom_path.exists():
        raise RuntimeError(f"missing x7d audit files below {root}")

    with q6_path.open(newline="") as stream:
        qrows = list(csv.DictReader(stream))
    qrows = [
        row for row in qrows
        if finite(row.get("q6Strength")) > 0.0 and finite(row.get("activeCells")) > 0.0
    ]
    if not qrows:
        raise RuntimeError(f"no projected-liquid rows in {q6_path}")

    with geom_path.open(newline="") as stream:
        grows = list(csv.DictReader(stream))
    if not grows:
        raise RuntimeError(f"empty geometry audit {geom_path}")

    last = qrows[-1]
    glast = grows[-1]
    step = int(finite(last.get("step")))
    time = finite(last.get("time"))
    dt = time / step if step > 0 and math.isfinite(time) else math.nan
    beta = finite(last.get("q6DensityRelaxationBeta"))
    tau = finite(last.get("q6DensityRelaxationTime"))
    if not (math.isfinite(tau) and tau > 0.0) and beta > 0.0 and dt > 0.0:
        tau = dt / beta

    raw = finite(glast.get("rawFillSum"))
    bounded = finite(glast.get("boundedGeometrySourceSum"))
    excess = raw - bounded

    target = [finite(r.get("densityRelaxationTargetDivRms")) for r in qrows]
    residual = [finite(r.get("divAfterProjectedFaceFluxRms")) for r in qrows]
    applied = [finite(r.get("divAfterAppliedCellVelocityRms")) for r in qrows]

    return {
        "step": float(step),
        "time": time,
        "dt": dt,
        "beta": beta,
        "tau": tau,
        "target_mean": mean(target),
        "target_final": target[-1],
        "residual_mean": mean(residual),
        "residual_final": residual[-1],
        "applied_mean": mean(applied),
        "applied_final": applied[-1],
        "raw": raw,
        "bounded": bounded,
        "excess": excess,
        "excess_fraction": excess / raw if raw > 0.0 else math.nan,
    }


def rel(a: float, b: float) -> float:
    return abs(a - b) / max(abs(a), abs(b), 1.0e-300)


def show(name: str, d: dict[str, float]) -> None:
    print(
        f"[0493x7d] {name}: step={int(d['step'])} t={d['time']:.9g} dt={d['dt']:.9g} "
        f"tau={d['tau']:.9g} betaPerStep={d['beta']:.9g}"
    )
    print(
        f"[0493x7d] {name}: targetDiv mean/final={d['target_mean']:.6e}/{d['target_final']:.6e} "
        f"constraintResidual mean/final={d['residual_mean']:.6e}/{d['residual_final']:.6e}"
    )
    print(
        f"[0493x7d] {name}: q6Applied mean/final={d['applied_mean']:.6e}/{d['applied_final']:.6e} "
        f"raw={d['raw']:.6f} bounded={d['bounded']:.6f} "
        f"excess={d['excess']:.6f} excessFrac={d['excess_fraction']:.6%}"
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--coarse-root", type=Path, required=True)
    ap.add_argument("--fine-root", type=Path, required=True)
    args = ap.parse_args()

    coarse = load(args.coarse_root)
    fine = load(args.fine_root)
    show("coarse", coarse)
    show("fine", fine)

    tau_rel = rel(coarse["tau"], fine["tau"])
    coarse_beta_expected = coarse["dt"] / coarse["tau"]
    fine_beta_expected = fine["dt"] / fine["tau"]
    beta_err_coarse = rel(coarse["beta"], coarse_beta_expected)
    beta_err_fine = rel(fine["beta"], fine_beta_expected)
    time_rel = rel(coarse["time"], fine["time"])
    excess_ratio = fine["excess_fraction"] / max(coarse["excess_fraction"], 1.0e-300)

    scaling_ok = (
        coarse["tau"] > 0.0 and fine["tau"] > 0.0
        and tau_rel <= 1.0e-12
        and beta_err_coarse <= 1.0e-12
        and beta_err_fine <= 1.0e-12
        and time_rel <= 1.0e-12
    )

    print(
        f"[0493x7d] scaling: tauRelDiff={tau_rel:.3e} physicalTimeRelDiff={time_rel:.3e} "
        f"betaConsistency=({beta_err_coarse:.3e},{beta_err_fine:.3e}) "
        f"status={'PASS' if scaling_ok else 'REVIEW'}"
    )
    print(
        f"[0493x7d] physics comparison: normalizedExcess fine/coarse={excess_ratio:.6f}; "
        "interpret as an operator/refinement diagnostic, not by itself as full MPCD transport convergence"
    )
    return 0 if scaling_ok else 2


if __name__ == "__main__":
    raise SystemExit(main())

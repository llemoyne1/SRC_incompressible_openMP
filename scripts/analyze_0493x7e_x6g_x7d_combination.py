#!/usr/bin/env python3
"""Cross-check simultaneous x6g interface pressure and x7d density RHS."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def finite(value: object) -> float:
    try:
        x = float(value)
    except (TypeError, ValueError):
        return math.nan
    return x if math.isfinite(x) else math.nan


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise RuntimeError(f"missing audit: {path}")
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise RuntimeError(f"empty audit: {path}")
    return rows


def load(root: Path) -> dict[str, object]:
    q6_path = root / "output/cuda_species_q6_independent_masked_0493w5.csv"
    pg_path = root / "output/cuda_phase_interface_pressure_0493x6g.csv"
    qrows_all = read_csv(q6_path)
    prows = read_csv(pg_path)

    q_required = {
        "step", "time", "q6Strength", "activeCells",
        "q6DensityRelaxationBeta", "q6DensityRelaxationTime",
        "densityRelaxationTargetDivRms", "divAfterProjectedFaceFluxRms",
    }
    p_required = {
        "step", "gasSpeciesCount", "sourceMode", "pressureScale",
        "representedInterfaceFaces", "nonzeroPressureFaces",
        "pressureDeltaMean", "pressureDeltaStd",
    }
    missing_q = q_required.difference(qrows_all[0])
    missing_p = p_required.difference(prows[0])
    if missing_q:
        raise RuntimeError(f"Q6 audit missing x7d columns: {sorted(missing_q)}")
    if missing_p:
        raise RuntimeError(f"x6g audit missing columns: {sorted(missing_p)}")

    qrows = [
        r for r in qrows_all
        if finite(r.get("q6Strength")) > 0.0 and finite(r.get("activeCells")) > 0.0
    ]
    if not qrows:
        raise RuntimeError(f"no projected-liquid Q6 rows in {q6_path}")

    q_by_step = {int(finite(r["step"])): r for r in qrows}
    p_steps = [int(finite(r["step"])) for r in prows]
    common_steps = [s for s in p_steps if s in q_by_step]
    if not common_steps:
        raise RuntimeError("x6g and x7d audits have no common step")

    qlast = qrows[-1]
    beta = finite(qlast["q6DensityRelaxationBeta"])
    tau = finite(qlast["q6DensityRelaxationTime"])
    target_max = max(finite(r["densityRelaxationTargetDivRms"]) for r in qrows)
    residual_max = max(finite(r["divAfterProjectedFaceFluxRms"]) for r in qrows)

    modes = {r["sourceMode"].strip().lower() for r in prows}
    scales = [finite(r["pressureScale"]) for r in prows]
    gas_species_min = min(int(finite(r["gasSpeciesCount"])) for r in prows)
    represented_min = min(int(finite(r["representedInterfaceFaces"])) for r in prows)
    represented_max = max(int(finite(r["representedInterfaceFaces"])) for r in prows)
    nonzero_max = max(int(finite(r["nonzeroPressureFaces"])) for r in prows)
    delta_abs_max = max(
        max(abs(finite(r["pressureDeltaMean"])), abs(finite(r["pressureDeltaStd"])))
        for r in prows
    )

    ok = (
        beta > 0.0
        and tau > 0.0
        and target_max > 0.0
        and all(math.isfinite(x) and x > 0.0 for x in scales)
        and modes == {"eos"}
        and gas_species_min >= 1
        and represented_max > 0
        and math.isfinite(residual_max)
    )

    return {
        "ok": ok,
        "final_step": int(finite(qlast["step"])),
        "time": finite(qlast["time"]),
        "beta": beta,
        "tau": tau,
        "target_max": target_max,
        "residual_max": residual_max,
        "pressure_rows": len(prows),
        "common_steps": len(common_steps),
        "source_modes": ",".join(sorted(modes)),
        "pressure_scale_min": min(scales),
        "pressure_scale_max": max(scales),
        "gas_species_min": gas_species_min,
        "represented_min": represented_min,
        "represented_max": represented_max,
        "nonzero_max": nonzero_max,
        "pressure_delta_abs_max": delta_abs_max,
    }


def show(label: str, d: dict[str, object]) -> None:
    print(
        f"[0493x7e] {label}: step={d['final_step']} t={d['time']:.9g} "
        f"tau={d['tau']:.9g} betaPerStep={d['beta']:.9g} "
        f"targetDivMax={d['target_max']:.6e} q6ResidualMax={d['residual_max']:.6e}"
    )
    print(
        f"[0493x7e] {label}: x6g mode={d['source_modes']} "
        f"scale={d['pressure_scale_min']:.6g}..{d['pressure_scale_max']:.6g} "
        f"gasSpeciesMin={d['gas_species_min']} "
        f"representedFaces={d['represented_min']}..{d['represented_max']} "
        f"nonzeroFacesMax={d['nonzero_max']} "
        f"pressureDeltaAbsMax={d['pressure_delta_abs_max']:.6e} "
        f"matchedAuditSteps={d['common_steps']}/{d['pressure_rows']}"
    )
    print(f"[0493x7e] {label}: simultaneous-x6g+x7d status={'PASS' if d['ok'] else 'REVIEW'}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--coarse-root", type=Path, required=True)
    ap.add_argument("--fine-root", type=Path, required=True)
    args = ap.parse_args()

    coarse = load(args.coarse_root)
    fine = load(args.fine_root)
    show("coarse", coarse)
    show("fine", fine)
    ok = bool(coarse["ok"]) and bool(fine["ok"])
    print(f"[0493x7e] combined qualification status={'PASS' if ok else 'REVIEW'}")
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())

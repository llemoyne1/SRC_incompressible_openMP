#!/usr/bin/env python3
"""Compare weight-encoded 0493k and equal-mass count-encoded 0493m runs."""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def fval(row: dict[str, str], key: str) -> float:
    try:
        return float(row.get(key, "nan"))
    except (TypeError, ValueError):
        return float("nan")


def composition_amplitudes(cell_rows: list[dict[str, str]], mode: str, step: int) -> tuple[float, float, float, float]:
    selected = [r for r in cell_rows if r.get("mode") == mode and int(r.get("step", "-1")) == step]
    if not selected:
        return (float("nan"),) * 4

    basis = [fval(r, "composition_basis") for r in selected]
    mass_fraction = [fval(r, "species1_concentration_mass") for r in selected]
    count_fraction = [fval(r, "species1_count") / max(1.0, fval(r, "all_count")) for r in selected]

    def project(values: list[float]) -> tuple[float, float]:
        mean = math.fsum(values) / len(values)
        den = math.fsum(b * b for b in basis)
        amp = math.fsum((v - mean) * b for v, b in zip(values, basis)) / den if den > 0 else float("nan")
        residual = math.sqrt(math.fsum(((v - mean) - amp * b) ** 2 for v, b in zip(values, basis)) / len(values))
        return amp, residual

    ma, ml = project(mass_fraction)
    ca, cl = project(count_fraction)
    return ma, ml, ca, cl


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count-root", type=Path, required=True)
    ap.add_argument("--weight-root", type=Path, required=True)
    ap.add_argument("--seed", type=int, default=493101)
    ap.add_argument("--modes", nargs="+", default=["src", "src-resampling"])
    ap.add_argument("--final-step", type=int, required=True)
    args = ap.parse_args()

    roots = {"weight_encoded": args.weight_root, "count_encoded": args.count_root}
    data: dict[str, dict[str, dict[str, str]]] = {}
    cells: dict[str, list[dict[str, str]]] = {}
    weights: dict[str, list[dict[str, str]]] = {}
    for encoding, root in roots.items():
        tg_path = root / "tg_0493k_summary.csv"
        cell_path = root / "weight_transport_0493l_cells.csv"
        weight_path = root / "weight_transport_0493l_summary.csv"
        missing = [str(p) for p in (tg_path, cell_path, weight_path) if not p.is_file()]
        if missing:
            raise SystemExit(f"[0493m-compare] ERROR missing for {encoding}: {' '.join(missing)}")
        data[encoding] = {
            r["mode"]: r for r in rows(tg_path)
            if int(r["seed"]) == args.seed and r["scenario"] == "binary_species" and r["mode"] in args.modes
        }
        cells[encoding] = rows(cell_path)
        weights[encoding] = rows(weight_path)

    out_rows: list[dict[str, object]] = []
    for encoding in ("weight_encoded", "count_encoded"):
        for mode in args.modes:
            tg = data[encoding].get(mode)
            if tg is None:
                raise SystemExit(f"[0493m-compare] ERROR missing TG row encoding={encoding} mode={mode}")
            mass0, mass0_leak, count0, count0_leak = composition_amplitudes(cells[encoding], mode, 0)
            massf, massf_leak, countf, countf_leak = composition_amplitudes(cells[encoding], mode, args.final_step)
            wr = next((r for r in weights[encoding] if r.get("mode") == mode and int(r.get("step", "-1")) == args.final_step and int(r.get("species", "-1")) == 0), None)
            if wr is None:
                raise SystemExit(f"[0493m-compare] ERROR missing weight row encoding={encoding} mode={mode}")
            out_rows.append({
                "encoding": encoding,
                "mode": mode,
                "composition_mass_amp_initial": mass0,
                "composition_mass_amp_final": massf,
                "composition_mass_amp_ratio": massf / mass0 if mass0 else float("nan"),
                "composition_count_amp_initial": count0,
                "composition_count_amp_final": countf,
                "composition_count_amp_ratio": countf / count0 if count0 else float("nan"),
                "composition_mass_leak_final": massf_leak,
                "composition_count_leak_final": countf_leak,
                "diffusion_eff": fval(tg, "diffusion_eff"),
                "diffusion_fit_r2": fval(tg, "diffusion_fit_r2"),
                "nu_eff": fval(tg, "nu_eff"),
                "kinetic_drift_max_rel": fval(tg, "kinetic_drift_max_rel"),
                "closure_infeasible_cells": fval(tg, "closure_infeasible_cells"),
                "closure_kinetic_residual": fval(tg, "closure_kinetic_residual"),
                "resampling_activity": fval(tg, "resampling_activity"),
                "weight_min_final": fval(wr, "weight_min"),
                "weight_max_final": fval(wr, "weight_max"),
                "weight_cv2_final": fval(wr, "weight_cv2"),
                "effective_fraction_final": fval(wr, "effective_fraction"),
                "top1_mass_fraction_final": fval(wr, "top1_mass_fraction"),
                "outside_initial_range_mass_fraction_final": fval(wr, "outside_initial_range_mass_fraction"),
                "corr_weight_abs_radial_velocity_final": fval(wr, "corr_weight_abs_radial_velocity"),
            })

    csv_path = args.count_root / "encoding_comparison_0493m.csv"
    with csv_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(out_rows[0]))
        writer.writeheader(); writer.writerows(out_rows)

    md_path = args.count_root / "encoding_comparison_0493m.md"
    with md_path.open("w") as f:
        f.write("# 0493m — weight-encoded vs equal-mass count-encoded TG\n\n")
        f.write(f"Reference weight-encoded root: `{args.weight_root}`  \n")
        f.write(f"Count-encoded root: `{args.count_root}`  \n")
        f.write(f"Final step: {args.final_step}\n\n")
        f.write("| encoding | mode | mass amp 0→f | count amp 0→f | D | R²(D) | CV²(w) | ESS/N | w min/max | infeasible |\n")
        f.write("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|\n")
        for r in out_rows:
            f.write(
                f"| {r['encoding']} | {r['mode']} | "
                f"{float(r['composition_mass_amp_initial']):.6g}→{float(r['composition_mass_amp_final']):.6g} | "
                f"{float(r['composition_count_amp_initial']):.6g}→{float(r['composition_count_amp_final']):.6g} | "
                f"{float(r['diffusion_eff']):.6g} | {float(r['diffusion_fit_r2']):.4g} | "
                f"{float(r['weight_cv2_final']):.4g} | {float(r['effective_fraction_final']):.4g} | "
                f"{float(r['weight_min_final']):.4g}/{float(r['weight_max_final']):.4g} | "
                f"{float(r['closure_infeasible_cells']):.0f} |\n"
            )
        f.write("\nThe comparison is diagnostic. Conservation of moments does not by itself establish transport invariance.\n")

    print(f"[0493m-compare] csv={csv_path}")
    print(f"[0493m-compare] report={md_path}")
    for r in out_rows:
        print(
            f"[0493m-compare] encoding={r['encoding']} mode={r['mode']} "
            f"massAmp={float(r['composition_mass_amp_initial']):.6g}->{float(r['composition_mass_amp_final']):.6g} "
            f"countAmp={float(r['composition_count_amp_initial']):.6g}->{float(r['composition_count_amp_final']):.6g} "
            f"cv2={float(r['weight_cv2_final']):.6g} ess={float(r['effective_fraction_final']):.6g} "
            f"w={float(r['weight_min_final']):.6g}/{float(r['weight_max_final']):.6g}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

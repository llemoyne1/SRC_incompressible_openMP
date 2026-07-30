#!/usr/bin/env python3
"""Analyze 0493w8 mono/dual-identical Taylor--Green equivalence.

This qualification separates three questions:

* SRC neutrality of enabling the species registry and splitting identical
  particles into two type labels;
* full-support non-regression of independent_masked Q6 against legacy mono Q6;
* effective TG transport of two independently projected labels representing
  the same physical fluid.

The detailed Taylor--Green state metrics reuse the historical 0493k analyzer.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
from array import array
from dataclasses import asdict, fields
from pathlib import Path
from types import SimpleNamespace
from typing import Any

from analyze_0493k_tg_transport import (  # type: ignore
    Metric,
    finite,
    fit_decay,
    normalized_curve_rms,
    read_csv,
    read_state,
    rel_diff,
    state_series,
)

SCENARIOS = ("mono_legacy", "mono_independent", "dual_identical")
MODES = ("src", "src-q6")


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--ny", type=int, required=True)
    ap.add_argument("--dt", type=float, required=True)
    ap.add_argument("--steps", type=int, required=True)
    ap.add_argument("--dump-every", type=int, required=True)
    ap.add_argument("--tg-mode", type=int, required=True)
    ap.add_argument("--tg-amplitude", type=float, required=True)
    ap.add_argument("--thermal-amplitude", type=float, required=True)
    ap.add_argument("--seeds", nargs="+", type=int, required=True)
    ap.add_argument("--fit-r2-min", type=float, default=0.95)
    ap.add_argument("--mass-rel-tol", type=float, default=1.0e-11)
    ap.add_argument("--momentum-abs-tol", type=float, default=1.0e-9)
    ap.add_argument("--q6-mean-flow-u0-guard", type=float, default=1.0e-2)
    ap.add_argument("--mono-q6-mean-flow-diff-tol", type=float, default=1.0e-12)
    ap.add_argument("--src-state-abs-tol", type=float, default=1.0e-12)
    ap.add_argument("--mono-q6-nu-rel-tol", type=float, default=0.02)
    ap.add_argument("--mono-q6-curve-rms-tol", type=float, default=0.01)
    ap.add_argument("--mono-q6-state-rms-u0-tol", type=float, default=0.02)
    ap.add_argument("--dual-q6-nu-rel-tol", type=float, default=0.10)
    ap.add_argument("--dual-q6-curve-rms-tol", type=float, default=0.05)
    ap.add_argument("--dual-q6-slip-u0-max", type=float, default=0.35)
    ap.add_argument("--q6-vs-src-nu-rel-tol", type=float, default=0.15)
    ap.add_argument("--q6-vs-src-curve-rms-tol", type=float, default=0.08)
    ap.add_argument("--dual-active-coverage-min", type=float, default=0.99)
    return ap.parse_args()


def periodic_delta(a: float, b: float) -> float:
    d = abs(a - b)
    return min(d, abs(d - 1.0), abs(d + 1.0))


def array_rms_delta(a: array, b: array, periodic: bool = False) -> tuple[float, float]:
    if len(a) != len(b):
        return float("inf"), float("inf")
    if not a:
        return 0.0, 0.0
    s2 = 0.0
    mx = 0.0
    for x, y in zip(a, b):
        d = periodic_delta(float(x), float(y)) if periodic else abs(float(x) - float(y))
        s2 += d * d
        mx = max(mx, d)
    return math.sqrt(s2 / len(a)), mx


def compare_state_files(a_path: Path, b_path: Path, ignore_type: bool) -> dict[str, float | int]:
    a = read_state(a_path)
    b = read_state(b_path)
    if int(a["n"]) != int(b["n"]):
        return {"n_mismatch": 1, "n_a": int(a["n"]), "n_b": int(b["n"])}
    xr, xm = array_rms_delta(a["x"], b["x"], periodic=True)  # type: ignore[arg-type]
    yr, ym = array_rms_delta(a["y"], b["y"], periodic=True)  # type: ignore[arg-type]
    vxr, vxm = array_rms_delta(a["vx"], b["vx"])  # type: ignore[arg-type]
    vyr, vym = array_rms_delta(a["vy"], b["vy"])  # type: ignore[arg-type]
    mr, mm = array_rms_delta(a["mass"], b["mass"])  # type: ignore[arg-type]
    role_mismatch = sum(x != y for x, y in zip(a["role"], b["role"]))  # type: ignore[arg-type]
    type_mismatch = 0 if ignore_type else sum(x != y for x, y in zip(a["type"], b["type"]))  # type: ignore[arg-type]
    return {
        "n_mismatch": 0,
        "x_rms": xr,
        "x_max": xm,
        "y_rms": yr,
        "y_max": ym,
        "vx_rms": vxr,
        "vx_max": vxm,
        "vy_rms": vyr,
        "vy_max": vym,
        "mass_rms": mr,
        "mass_max": mm,
        "role_mismatch": role_mismatch,
        "type_mismatch": type_mismatch,
    }


def state_dump_map(case: Path) -> dict[int, Path]:
    pattern = re.compile(r"state_step_(\d+)\.smpcd$")
    result: dict[int, Path] = {}
    for path in (case / "output").glob("state_step_*.smpcd"):
        match = pattern.fullmatch(path.name)
        if not match:
            continue
        step = int(match.group(1))
        if step in result:
            raise ValueError(
                f"duplicate state dump for step {step} in {case}: "
                f"{result[step].name}, {path.name}"
            )
        result[step] = path
    return result


def compare_state_series(
    root: Path,
    seed: int,
    scenario_a: str,
    scenario_b: str,
    mode: str,
    steps: int,
    dump_every: int,
    ignore_type: bool,
) -> dict[str, float | int]:
    case_a = root / f"seed_{seed}" / scenario_a / mode
    case_b = root / f"seed_{seed}" / scenario_b / mode
    dumps_a = state_dump_map(case_a)
    dumps_b = state_dump_map(case_b)
    expected = set(range(0, steps + 1, dump_every))
    missing_a = sorted(expected - set(dumps_a))
    missing_b = sorted(expected - set(dumps_b))
    if missing_a or missing_b:
        raise ValueError(
            f"missing comparison dumps: {scenario_a}/{mode}={missing_a[:12]} "
            f"{scenario_b}/{mode}={missing_b[:12]}"
        )

    worst: dict[str, float | int] = {
        "n_mismatch": 0,
        "x_rms": 0.0,
        "x_max": 0.0,
        "y_rms": 0.0,
        "y_max": 0.0,
        "vx_rms": 0.0,
        "vx_max": 0.0,
        "vy_rms": 0.0,
        "vy_max": 0.0,
        "mass_rms": 0.0,
        "mass_max": 0.0,
        "role_mismatch": 0,
        "type_mismatch": 0,
        "worst_step": 0,
    }
    for step in range(0, steps + 1, dump_every):
        current = compare_state_files(dumps_a[step], dumps_b[step], ignore_type)
        score = max(float(current.get("vx_max", 0.0)), float(current.get("vy_max", 0.0)),
                    float(current.get("x_max", 0.0)), float(current.get("y_max", 0.0)))
        old_score = max(float(worst["vx_max"]), float(worst["vy_max"]),
                        float(worst["x_max"]), float(worst["y_max"]))
        if score >= old_score:
            worst["worst_step"] = step
        for key, value in current.items():
            if key in ("role_mismatch", "type_mismatch", "n_mismatch"):
                worst[key] = max(int(worst.get(key, 0)), int(value))
            elif key not in ("n_a", "n_b"):
                worst[key] = max(float(worst.get(key, 0.0)), float(value))
    return worst


def independent_q6_stats(path: Path, nc: int) -> dict[str, float | int]:
    rows = read_csv(path)
    active_rows = [r for r in rows if finite(r.get("q6Strength"), 0.0) > 0.0]
    if not active_rows:
        return {
            "rows": 0,
            "converged": 0,
            "coverage_min": 0.0,
            "corrected_min": 0,
            "applied_div_ratio_max": float("nan"),
        }
    coverage = [finite(r.get("activeCells"), 0.0) / nc for r in active_rows]
    corrected = [int(finite(r.get("correctedParticles"), 0.0)) for r in active_rows]
    ratios: list[float] = []
    for r in active_rows:
        before = finite(r.get("divBeforeRms"))
        after = finite(r.get("divAfterAppliedCellVelocityRms", r.get("divAfterRms")))
        if before > 0.0 and math.isfinite(after):
            ratios.append(after / before)
    return {
        "rows": len(active_rows),
        "converged": int(all(int(finite(r.get("converged"), 0.0)) == 1 for r in active_rows)),
        "coverage_min": min(coverage),
        "corrected_min": min(corrected),
        "applied_div_ratio_max": max(ratios, default=float("nan")),
    }


def main() -> int:
    a = parse_args()
    metric_args = SimpleNamespace(
        nx=a.nx,
        ny=a.ny,
        dt=a.dt,
        steps=a.steps,
        dump_every=a.dump_every,
        tg_mode=a.tg_mode,
        tg_amplitude=a.tg_amplitude,
        composition_amplitude=0.0,
    )
    k2 = 2.0 * (2.0 * math.pi * a.tg_mode) ** 2
    checks: list[dict[str, object]] = []
    summaries: list[dict[str, object]] = []
    comparisons: list[dict[str, object]] = []
    series: dict[tuple[int, str, str], list[Metric]] = {}
    summary: dict[tuple[int, str, str], dict[str, object]] = {}

    def emit(name: str, status: str, detail: str, category: str = "qualification") -> None:
        row = {"check": name, "status": status, "category": category, "detail": detail}
        checks.append(row)
        print(f"[0493w8-audit] {name}={status} {detail}")

    def check(name: str, ok: bool, detail: str, category: str = "qualification") -> None:
        emit(name, "PASS" if ok else "FAIL", detail, category)

    def info(name: str, detail: str, category: str = "observation") -> None:
        emit(name, "INFO", detail, category)

    for seed in a.seeds:
        for scenario in SCENARIOS:
            for mode in MODES:
                key = (seed, scenario, mode)
                case = a.root / f"seed_{seed}" / scenario / mode
                try:
                    rows = state_series(case, scenario, metric_args)
                except Exception as exc:
                    check(f"seed{seed}_{scenario}_{mode}_state_series", False, str(exc), "integrity")
                    continue
                series[key] = rows
                first, last = rows[0], rows[-1]
                fit = fit_decay(rows, "tg_amplitude", k2)
                nu = finite(fit.get("coefficient"))
                mass_drift = max(abs(r.total_mass - first.total_mass) / max(1.0, abs(first.total_mass)) for r in rows)
                px_drift = max(abs(r.px - first.px) for r in rows)
                py_drift = max(abs(r.py - first.py) for r in rows)
                q6_stats: dict[str, float | int] = {}
                if mode == "src-q6" and scenario != "mono_legacy":
                    q6_stats = independent_q6_stats(
                        case / "output" / "cuda_species_q6_independent_masked_0493w5.csv",
                        a.nx * a.ny,
                    )
                mean_flow_u0 = max(px_drift, py_drift) / max(
                    abs(first.total_mass) * a.tg_amplitude, 1.0e-14
                )
                row: dict[str, object] = {
                    "seed": seed,
                    "scenario": scenario,
                    "mode": mode,
                    "nu_eff": nu,
                    "nu_fit_r2": finite(fit.get("r2")),
                    "nu_fit_points": int(fit.get("points", 0)),
                    "tg_initial": first.tg_amplitude,
                    "tg_final": last.tg_amplitude,
                    "tg_final_ratio": last.tg_amplitude / first.tg_amplitude,
                    "mass_drift_max_rel": mass_drift,
                    "px_drift_max_abs": px_drift,
                    "py_drift_max_abs": py_drift,
                    "mean_flow_drift_over_u0": mean_flow_u0,
                    "final_divergence_rms": last.divergence_rms,
                    "final_species_slip_rms": last.species_slip_rms,
                    "final_species1_thermal_variance": last.species1_thermal_variance,
                    "final_species2_thermal_variance": last.species2_thermal_variance,
                    "q6_rows": int(q6_stats.get("rows", 0)),
                    "q6_converged": int(q6_stats.get("converged", 0)),
                    "q6_active_coverage_min": finite(q6_stats.get("coverage_min")),
                    "q6_corrected_particles_min": int(q6_stats.get("corrected_min", 0)),
                    "q6_applied_div_ratio_max": finite(q6_stats.get("applied_div_ratio_max")),
                }
                summaries.append(row)
                summary[key] = row

                check(f"seed{seed}_{scenario}_{mode}_mass", mass_drift <= a.mass_rel_tol,
                      f"maxRel={mass_drift:.3e}", "integrity")
                if mode == "src":
                    check(f"seed{seed}_{scenario}_{mode}_momentum",
                          max(px_drift, py_drift) <= a.momentum_abs_tol,
                          f"maxPx={px_drift:.3e} maxPy={py_drift:.3e}", "integrity")
                else:
                    # The comparison deliberately disables the legacy uniform
                    # momentum correction in both Q6 branches. The absolute
                    # drift is retained behind a broad pathology guard; mono
                    # non-regression is qualified below by directly comparing
                    # legacy and independent Q6 on the same seed.
                    check(f"seed{seed}_{scenario}_{mode}_mean_flow_guard",
                          mean_flow_u0 <= a.q6_mean_flow_u0_guard,
                          f"drift/U0={mean_flow_u0:.3e} maxPx={px_drift:.3e} "
                          f"maxPy={py_drift:.3e} guard={a.q6_mean_flow_u0_guard:.3e}",
                          "integrity")
                check(f"seed{seed}_{scenario}_{mode}_nu_positive", nu > 0.0, f"nu={nu:.8g}")
                check(f"seed{seed}_{scenario}_{mode}_nu_fit",
                      finite(fit.get("r2")) >= a.fit_r2_min,
                      f"r2={finite(fit.get('r2')):.6g} points={int(fit.get('points', 0))}")
                if q6_stats:
                    check(f"seed{seed}_{scenario}_{mode}_q6_rows",
                          int(q6_stats["rows"]) > 0, f"rows={int(q6_stats['rows'])}", "integrity")
                    check(f"seed{seed}_{scenario}_{mode}_q6_converged",
                          int(q6_stats["converged"]) == 1, "all species solves converged", "integrity")
                    check(f"seed{seed}_{scenario}_{mode}_q6_corrected",
                          int(q6_stats["corrected_min"]) > 0,
                          f"minCorrected={int(q6_stats['corrected_min'])}", "integrity")
                    if scenario == "dual_identical":
                        check(f"seed{seed}_{scenario}_{mode}_active_coverage",
                              finite(q6_stats["coverage_min"]) >= a.dual_active_coverage_min,
                              f"min={finite(q6_stats['coverage_min']):.6g} tol={a.dual_active_coverage_min:.6g}")

        # Strict SRC neutrality: registry on/off, then one label/two labels.
        for left, right, label, ignore_type in (
            ("mono_legacy", "mono_independent", "legacy_vs_independent", False),
            ("mono_independent", "dual_identical", "mono_vs_dual", True),
        ):
            cmp = compare_state_series(a.root, seed, left, right, "src", a.steps, a.dump_every, ignore_type)
            comparisons.append({"seed": seed, "mode": "src", "pair": label, **cmp})
            max_abs = max(float(cmp["x_max"]), float(cmp["y_max"]),
                          float(cmp["vx_max"]), float(cmp["vy_max"]), float(cmp["mass_max"]))
            discrete_ok = int(cmp["n_mismatch"]) == 0 and int(cmp["role_mismatch"]) == 0 and int(cmp["type_mismatch"]) == 0
            check(f"seed{seed}_src_{label}_state_exact",
                  discrete_ok and max_abs <= a.src_state_abs_tol,
                  f"maxAbs={max_abs:.3e} roleMismatch={cmp['role_mismatch']} typeMismatch={cmp['type_mismatch']} worstStep={cmp['worst_step']}")

        # Full-domain independent Q6 versus the legacy mono operator.
        kl = (seed, "mono_legacy", "src-q6")
        ki = (seed, "mono_independent", "src-q6")
        if kl in summary and ki in summary:
            nu_rel = rel_diff(finite(summary[kl]["nu_eff"]), finite(summary[ki]["nu_eff"]))
            curve = normalized_curve_rms(series[kl], series[ki], "tg_amplitude")
            mean_flow_legacy = finite(summary[kl]["mean_flow_drift_over_u0"])
            mean_flow_independent = finite(summary[ki]["mean_flow_drift_over_u0"])
            mean_flow_diff = abs(mean_flow_legacy - mean_flow_independent)
            cmp = compare_state_series(a.root, seed, "mono_legacy", "mono_independent", "src-q6",
                                       a.steps, a.dump_every, False)
            state_rms = math.hypot(float(cmp["vx_rms"]), float(cmp["vy_rms"])) / max(a.tg_amplitude, 1.0e-14)
            comparisons.append({"seed": seed, "mode": "src-q6", "pair": "legacy_vs_independent", **cmp,
                                "velocity_rms_over_u0": state_rms, "nu_rel": nu_rel,
                                "curve_rms_over_a0": curve,
                                "mean_flow_legacy_over_u0": mean_flow_legacy,
                                "mean_flow_independent_over_u0": mean_flow_independent,
                                "mean_flow_abs_diff_over_u0": mean_flow_diff})
            check(f"seed{seed}_mono_q6_nu_nonreg", nu_rel <= a.mono_q6_nu_rel_tol,
                  f"rel={nu_rel:.6g} legacy={finite(summary[kl]['nu_eff']):.8g} independent={finite(summary[ki]['nu_eff']):.8g}")
            check(f"seed{seed}_mono_q6_curve_nonreg", curve <= a.mono_q6_curve_rms_tol,
                  f"rms/A0={curve:.6g}")
            check(f"seed{seed}_mono_q6_state_nonreg", state_rms <= a.mono_q6_state_rms_u0_tol,
                  f"velocityRms/U0={state_rms:.6g} maxV=({cmp['vx_max']:.3e},{cmp['vy_max']:.3e})")
            check(f"seed{seed}_mono_q6_mean_flow_nonreg",
                  mean_flow_diff <= a.mono_q6_mean_flow_diff_tol,
                  f"absDiff/U0={mean_flow_diff:.3e} legacy={mean_flow_legacy:.3e} "
                  f"independent={mean_flow_independent:.3e} tol={a.mono_q6_mean_flow_diff_tol:.3e}")

        # Dual labels represent the same fluid, but independent Q6 is not
        # expected to be bitwise identical after each type develops its own
        # finite-population fluctuation.  Gate effective TG transport instead.
        kd = (seed, "dual_identical", "src-q6")
        if ki in summary and kd in summary:
            nu_rel = rel_diff(finite(summary[ki]["nu_eff"]), finite(summary[kd]["nu_eff"]))
            curve = normalized_curve_rms(series[ki], series[kd], "tg_amplitude")
            cmp = compare_state_series(a.root, seed, "mono_independent", "dual_identical", "src-q6",
                                       a.steps, a.dump_every, True)
            state_rms = math.hypot(float(cmp["vx_rms"]), float(cmp["vy_rms"])) / max(a.tg_amplitude, 1.0e-14)
            slip_ratio = finite(summary[kd]["final_species_slip_rms"]) / max(a.tg_amplitude, 1.0e-14)
            comparisons.append({"seed": seed, "mode": "src-q6", "pair": "mono_vs_dual", **cmp,
                                "velocity_rms_over_u0": state_rms, "nu_rel": nu_rel,
                                "curve_rms_over_a0": curve, "final_slip_over_u0": slip_ratio})
            check(f"seed{seed}_dual_q6_nu_agreement", nu_rel <= a.dual_q6_nu_rel_tol,
                  f"rel={nu_rel:.6g} mono={finite(summary[ki]['nu_eff']):.8g} dual={finite(summary[kd]['nu_eff']):.8g}")
            check(f"seed{seed}_dual_q6_curve_agreement", curve <= a.dual_q6_curve_rms_tol,
                  f"rms/A0={curve:.6g}")
            info(f"seed{seed}_dual_q6_particle_state_divergence",
                 f"velocityRms/U0={state_rms:.6g} diagnostic-only: independent species projections "
                 "need not preserve particle-index trajectories")
            check(f"seed{seed}_dual_q6_slip_bounded", slip_ratio <= a.dual_q6_slip_u0_max,
                  f"slip/U0={slip_ratio:.6g}")

        # TG is analytically divergence-free; Q6 should not grossly alter its
        # effective transport relative to SRC.  The dedicated calibrator will
        # later refine this broad qualification.
        for scenario in ("mono_independent", "dual_identical"):
            ks = (seed, scenario, "src")
            kq = (seed, scenario, "src-q6")
            if ks not in summary or kq not in summary:
                continue
            nu_rel = rel_diff(finite(summary[ks]["nu_eff"]), finite(summary[kq]["nu_eff"]))
            curve = normalized_curve_rms(series[ks], series[kq], "tg_amplitude")
            check(f"seed{seed}_{scenario}_q6_vs_src_nu", nu_rel <= a.q6_vs_src_nu_rel_tol,
                  f"rel={nu_rel:.6g} src={finite(summary[ks]['nu_eff']):.8g} q6={finite(summary[kq]['nu_eff']):.8g}")
            check(f"seed{seed}_{scenario}_q6_vs_src_curve", curve <= a.q6_vs_src_curve_rms_tol,
                  f"rms/A0={curve:.6g}")
            info(f"seed{seed}_{scenario}_q6_divergence_response",
                 f"src={finite(summary[ks]['final_divergence_rms']):.6g} q6={finite(summary[kq]['final_divergence_rms']):.6g}")

    a.root.mkdir(parents=True, exist_ok=True)
    metric_names = [f.name for f in fields(Metric)]
    with (a.root / "tg_0493w8_timeseries.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["seed", "scenario", "mode"] + metric_names)
        writer.writeheader()
        for key in sorted(series):
            seed, scenario, mode = key
            for row in series[key]:
                writer.writerow({"seed": seed, "scenario": scenario, "mode": mode, **asdict(row)})
    if summaries:
        with (a.root / "tg_0493w8_summary.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(summaries[0]))
            writer.writeheader()
            writer.writerows(summaries)
    if comparisons:
        fields_cmp: list[str] = []
        for row in comparisons:
            for key in row:
                if key not in fields_cmp:
                    fields_cmp.append(key)
        with (a.root / "tg_0493w8_comparisons.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields_cmp)
            writer.writeheader()
            writer.writerows(comparisons)
    with (a.root / "physics_0493w8_checks.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=("check", "status", "category", "detail"))
        writer.writeheader()
        writer.writerows(checks)

    failed = [r for r in checks if r["status"] == "FAIL"]
    status = "FAIL" if failed else "PASS"
    report = {
        "status": status,
        "parameters": {**vars(a), "root": str(a.root)},
        "summaries": summaries,
        "comparisons": comparisons,
        "failed_checks": failed,
    }
    (a.root / "physics_0493w8.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    md = [
        "# 0493w8 Taylor--Green mono/dual-identical equivalence",
        "",
        f"**Status: {status}**",
        "",
        "| seed | scenario | mode | nu | R2 | TG final/A0 | div(end) | slip(end) | Q6 coverage min |",
        "|---:|---|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in summaries:
        md.append(
            f"| {row['seed']} | {row['scenario']} | {row['mode']} | "
            f"{finite(row['nu_eff']):.6g} | {finite(row['nu_fit_r2']):.6g} | "
            f"{finite(row['tg_final_ratio']):.6g} | {finite(row['final_divergence_rms']):.6g} | "
            f"{finite(row['final_species_slip_rms']):.6g} | {finite(row['q6_active_coverage_min']):.6g} |"
        )
    if failed:
        md.extend(("", "## Failed checks", ""))
        md.extend(f"- `{r['check']}` — {r['detail']}" for r in failed)
    (a.root / "physics_0493w8.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    print(f"[0493w8] {status} checks={len(checks)} failed={len(failed)}")
    print(f"[0493w8] summary={a.root / 'tg_0493w8_summary.csv'}")
    print(f"[0493w8] comparisons={a.root / 'tg_0493w8_comparisons.csv'}")
    return 2 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

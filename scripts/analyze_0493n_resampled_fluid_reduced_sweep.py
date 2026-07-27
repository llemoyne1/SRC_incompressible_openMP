#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from statistics import fmean


def finite(x, default=float("nan")):
    try:
        v = float(x)
        return v if math.isfinite(v) else default
    except Exception:
        return default


def read_csv(path: Path):
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def rel_diff(a: float, b: float) -> float:
    return abs(a - b) / max(abs(a), abs(b), 1.0e-30)


def curve_rms(rows_a, rows_b, amplitude: float) -> float:
    aa = {int(float(r["step"])): finite(r.get("tg_amplitude")) for r in rows_a}
    bb = {int(float(r["step"])): finite(r.get("tg_amplitude")) for r in rows_b}
    vals = [(aa[s] - bb[s]) ** 2 for s in sorted(set(aa) & set(bb)) if math.isfinite(aa[s]) and math.isfinite(bb[s])]
    return math.sqrt(fmean(vals)) / max(abs(amplitude), 1.0e-30) if vals else float("nan")


def classify(value: float, go: float, watch: float, *, lower_is_better=True):
    if not math.isfinite(value):
        return "INCONCLUSIVE"
    if lower_is_better:
        return "GO" if value <= go else ("WATCH" if value <= watch else "NO_GO")
    return "GO" if value >= go else ("WATCH" if value >= watch else "NO_GO")


def worst_status(statuses):
    order = {"GO": 0, "INCONCLUSIVE": 1, "WATCH": 2, "NO_GO": 3}
    return max(statuses, key=lambda s: order.get(s, 3)) if statuses else "INCONCLUSIVE"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--steps", type=int, required=True)
    ap.add_argument("--tg-amplitude", type=float, required=True)
    a = ap.parse_args()
    root = a.root.resolve()
    manifest = read_csv(root / "case_manifest_0493n.csv")
    if not manifest:
        raise SystemExit(f"[0493n-audit] ERROR missing/empty manifest in {root}")

    case_meta = {r["case_id"]: r for r in manifest}
    summaries = {}
    series = {}
    weights = {}
    guard_stats = {}

    for meta in manifest:
        cid = meta["case_id"]
        croot = Path(meta["case_root"])
        if not croot.is_absolute():
            croot = (Path.cwd() / croot).resolve()
        for row in read_csv(croot / "tg_0493k_summary.csv"):
            key = (cid, row["mode"])
            summaries[key] = row
        ts = read_csv(croot / "tg_0493k_timeseries.csv")
        for mode in {r["mode"] for r in ts}:
            series[(cid, mode)] = [r for r in ts if r["mode"] == mode]
        for row in read_csv(croot / "weight_transport_0493l_summary.csv"):
            if str(row.get("species", "")) == "0" and int(float(row.get("step", -1))) == a.steps:
                weights[(cid, row["mode"])] = row
        guard = croot / f"seed_{meta.get('seed','493101')}" / "mono_species" / "src-resampling" / "output" / "cuda_resampling_population_guard_0297.csv"
        # Current manifest does not carry seed; runner default/current seed is visible in directory.
        if not guard.is_file():
            candidates = list(croot.glob("seed_*/mono_species/src-resampling/output/cuda_resampling_population_guard_0297.csv"))
            guard = candidates[0] if candidates else guard
        grows = read_csv(guard)
        edits = sum(int(finite(r.get("splitApplied"), 0)) + int(finite(r.get("mergeApplied"), 0)) for r in grows)
        guard_stats[cid] = {"guard_calls": len(grows), "population_edits": edits}

    per_run = []
    pair_rows = []
    checks = []

    def add_check(name, category, value, go, watch, detail="", lower_is_better=True, critical=True):
        status = classify(value, go, watch, lower_is_better=lower_is_better)
        checks.append({
            "check": name, "category": category, "status": status,
            "critical": int(critical), "value": value, "go_limit": go,
            "watch_limit": watch, "detail": detail,
        })
        return status

    for meta in manifest:
        cid = meta["case_id"]
        modes = meta["modes"].split()
        for mode in modes:
            key = (cid, mode)
            if key not in summaries:
                checks.append({"check": f"{cid}_{mode}_summary", "category": "integrity", "status": "NO_GO", "critical": 1,
                               "value": float("nan"), "go_limit": "", "watch_limit": "", "detail": "missing 0493k summary"})
                continue
            s = summaries[key]
            ts = series.get(key, [])
            first, last = (ts[0], ts[-1]) if ts else ({}, {})
            thermal0 = finite(first.get("species1_thermal_variance"))
            thermal1 = finite(last.get("species1_thermal_variance"))
            thermal_drift = rel_diff(thermal0, thermal1) if math.isfinite(thermal0) and math.isfinite(thermal1) else float("nan")
            max_empty = max((int(float(r.get("empty_cells", 0))) for r in ts), default=-1)
            min_occ = min((int(float(r.get("occupancy_min", 0))) for r in ts), default=-1)
            w = weights.get(key, {})
            g = guard_stats.get(cid, {}) if "resampling" in mode else {}
            particles0 = int(meta["nx"]) * int(meta["ny"]) * int(meta["gamma"])
            activity_norm = finite(g.get("population_edits"), 0.0) / max(particles0 * a.steps, 1)
            row = {
                **{k: meta[k] for k in ("case_id", "stage", "nx", "ny", "gamma", "guard_every", "nmin", "ntarget", "nmax", "reference_case")},
                "mode": mode,
                "nu_eff": finite(s.get("nu_eff")),
                "nu_fit_r2": finite(s.get("nu_fit_r2")),
                "tg_final_ratio": finite(s.get("tg_final_ratio")),
                "mass_drift_max_rel": finite(s.get("mass_drift_max_rel")),
                "momentum_drift_max_abs": max(finite(s.get("px_drift_max_abs"), 0.0), finite(s.get("py_drift_max_abs"), 0.0)),
                "kinetic_drift_max_rel": finite(s.get("kinetic_drift_max_rel")),
                "thermal_drift_rel": thermal_drift,
                "max_empty_cells": max_empty,
                "min_occupancy": min_occ,
                "resampling_activity": int(g.get("population_edits", 0)),
                "guard_calls": int(g.get("guard_calls", 0)),
                "activity_per_particle_step": activity_norm,
                "weight_cv2_final": finite(w.get("weight_cv2")),
                "weight_ess_fraction_final": finite(w.get("effective_fraction")),
                "weight_min_final": finite(w.get("weight_min")),
                "weight_max_final": finite(w.get("weight_max")),
            }
            per_run.append(row)
            if "resampling" in mode:
                add_check(f"{cid}_nu_fit", "hydrodynamics", row["nu_fit_r2"], 0.995, 0.98, f"R2={row['nu_fit_r2']:.6g}", lower_is_better=False)
                add_check(f"{cid}_mass", "integrity", row["mass_drift_max_rel"], 1e-9, 1e-7, f"maxRel={row['mass_drift_max_rel']:.3e}")
                add_check(f"{cid}_kinetic", "integrity", row["kinetic_drift_max_rel"], 1e-3, 5e-3, f"maxRel={row['kinetic_drift_max_rel']:.3e}")
                add_check(f"{cid}_thermal", "hydrodynamics", row["thermal_drift_rel"], 0.01, 0.03, f"rel={row['thermal_drift_rel']:.3e}")
                add_check(f"{cid}_empty_cells", "support", float(max_empty), 0.0, 0.0, f"maxEmpty={max_empty}")
                # Weight dispersion is deliberately diagnostic, not a standalone physical failure.
                add_check(f"{cid}_weight_ess", "weights", row["weight_ess_fraction_final"], 0.60, 0.40,
                          f"ESS/N={row['weight_ess_fraction_final']:.6g}", lower_is_better=False, critical=False)
                if int(g.get("population_edits", 0)) == 0:
                    checks.append({"check": f"{cid}_active_resampling", "category": "support", "status": "INCONCLUSIVE", "critical": 1,
                                   "value": 0, "go_limit": ">0", "watch_limit": "", "detail": "no split/merge: case does not test active resampling"})
                else:
                    checks.append({"check": f"{cid}_active_resampling", "category": "support", "status": "GO", "critical": 1,
                                   "value": int(g.get("population_edits", 0)), "go_limit": ">0", "watch_limit": "", "detail": "active split/merge"})

    per_map = {(r["case_id"], r["mode"]): r for r in per_run}
    for meta in manifest:
        cid = meta["case_id"]
        rk = (cid, "src-resampling")
        if rk not in per_map:
            continue
        ref_case = meta["reference_case"]
        sk = (ref_case, "src")
        if sk not in per_map:
            checks.append({"check": f"{cid}_paired_reference", "category": "pair", "status": "INCONCLUSIVE", "critical": 1,
                           "value": "", "go_limit": "", "watch_limit": "", "detail": f"missing src reference {ref_case}"})
            continue
        rr, sr = per_map[rk], per_map[sk]
        nu_delta = rel_diff(rr["nu_eff"], sr["nu_eff"])
        crms = curve_rms(series.get(rk, []), series.get(sk, []), a.tg_amplitude)
        pair = {
            "case_id": cid, "reference_case": ref_case,
            "nx": meta["nx"], "gamma": meta["gamma"], "guard_every": meta["guard_every"],
            "nu_src": sr["nu_eff"], "nu_resampling": rr["nu_eff"],
            "nu_ratio_resampling_to_src": rr["nu_eff"] / sr["nu_eff"] if sr["nu_eff"] else float("nan"),
            "nu_delta_rel_to_src": nu_delta,
            "tg_curve_rms_over_A0_vs_src": crms,
        }
        pair_rows.append(pair)
        add_check(f"{cid}_nu_shift_vs_src", "pair", nu_delta, 0.15, 0.25,
                  f"src={sr['nu_eff']:.8g} resamp={rr['nu_eff']:.8g} rel={nu_delta:.6g}")
        add_check(f"{cid}_tg_curve_vs_src", "pair", crms, 0.02, 0.05, f"rms/A0={crms:.6g}")

    pair_map = {r["case_id"]: r for r in pair_rows}
    # Gamma assessment uses the resampling-induced perturbation relative to the matching SRC fluid.
    if "g64_g20_e1" in pair_map and "g64_g40_e1" in pair_map:
        delta = abs(pair_map["g64_g20_e1"]["nu_delta_rel_to_src"] - pair_map["g64_g40_e1"]["nu_delta_rel_to_src"])
        add_check("gamma20_vs_gamma40_resampling_perturbation", "gamma", delta, 0.05, 0.10,
                  "comparison of |nu_resamp-nu_src|/nu at each gamma; raw nu is not compared across gamma")

    # Cadence sensitivity is compared to the nominal resampled case, not to raw SRC alone.
    nominal = per_map.get(("g64_g20_e1", "src-resampling"))
    for cid in ("g64_g20_e5", "g64_g20_e20"):
        row = per_map.get((cid, "src-resampling"))
        if nominal and row:
            dnu = rel_diff(row["nu_eff"], nominal["nu_eff"])
            dcurve = curve_rms(series.get((cid, "src-resampling"), []), series.get(("g64_g20_e1", "src-resampling"), []), a.tg_amplitude)
            add_check(f"{cid}_cadence_nu", "cadence", dnu, 0.05, 0.10,
                      f"nominalEvery1={nominal['nu_eff']:.8g} current={row['nu_eff']:.8g}")
            add_check(f"{cid}_cadence_curve", "cadence", dcurve, 0.02, 0.05, f"rms/A0={dcurve:.6g}")

    # Grid assessment also compares the relative perturbation, because raw MPCD viscosity changes with cell scale.
    if "g64_g20_e1" in pair_map and "g128_g20_e1" in pair_map:
        delta = abs(pair_map["g64_g20_e1"]["nu_delta_rel_to_src"] - pair_map["g128_g20_e1"]["nu_delta_rel_to_src"])
        add_check("grid64_vs_grid128_resampling_perturbation", "grid", delta, 0.05, 0.10,
                  "raw viscosity is not treated as grid-invariant; paired resampling perturbation is compared")

    root.mkdir(parents=True, exist_ok=True)
    def write(name, rows):
        path = root / name
        if rows:
            with path.open("w", newline="", encoding="utf-8") as f:
                w = csv.DictWriter(f, fieldnames=list(rows[0]))
                w.writeheader(); w.writerows(rows)
        else:
            path.write_text("", encoding="utf-8")
        return path

    per_path = write("resampled_fluid_0493n_per_run.csv", per_run)
    pair_path = write("resampled_fluid_0493n_pairwise.csv", pair_rows)
    checks_path = write("resampled_fluid_0493n_checks.csv", checks)

    critical = [r["status"] for r in checks if int(r.get("critical", 1))]
    base = worst_status(critical)
    stages = {r["stage"] for r in manifest}
    if base == "NO_GO": overall = "NO_GO"
    elif base == "WATCH": overall = "WATCH"
    elif base == "INCONCLUSIVE": overall = "INCONCLUSIVE"
    elif "core" in stages and "grid" in stages: overall = "GO"
    elif "core" in stages: overall = "GO_PROVISIONAL_CORE"
    else: overall = "INCOMPLETE_GRID_ONLY"

    md = [
        "# 0493n — Reduced resampled-fluid go/no-go sweep", "",
        f"**Overall status: {overall}**", "",
        "The sweep treats each gamma/grid SRC case as its own kinetic-fluid reference. Raw viscosities are not required to match across gamma or grid.", "",
        "| case | grid | gamma | guard every | mode | nu | R2 | max empty | kinetic drift | activity | CV2(w) | ESS/N |",
        "|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in per_run:
        md.append(f"| {r['case_id']} | {r['nx']} | {r['gamma']} | {r['guard_every']} | {r['mode']} | {r['nu_eff']:.7g} | {r['nu_fit_r2']:.6g} | {r['max_empty_cells']} | {r['kinetic_drift_max_rel']:.3e} | {r['resampling_activity']} | {r['weight_cv2_final']:.5g} | {r['weight_ess_fraction_final']:.5g} |")
    md.extend(["", "## Paired SRC/resampling comparisons", "",
               "| case | nu SRC | nu resampling | relative shift | TG curve RMS/A0 |",
               "|---|---:|---:|---:|---:|"])
    for r in pair_rows:
        md.append(f"| {r['case_id']} | {r['nu_src']:.7g} | {r['nu_resampling']:.7g} | {r['nu_delta_rel_to_src']:.4%} | {r['tg_curve_rms_over_A0_vs_src']:.4%} |")
    bad = [r for r in checks if r["status"] != "GO"]
    if bad:
        md.extend(["", "## Non-GO checks", ""])
        for r in bad:
            md.append(f"- **{r['status']}** `{r['check']}`: {r['detail']}")
    report_path = root / "resampled_fluid_0493n.md"
    report_path.write_text("\n".join(md) + "\n", encoding="utf-8")
    json_path = root / "resampled_fluid_0493n.json"
    json_path.write_text(json.dumps({"status": overall, "per_run": per_run, "pairwise": pair_rows, "checks": checks}, indent=2, allow_nan=True) + "\n", encoding="utf-8")

    for r in pair_rows:
        print(f"[0493n-audit] case={r['case_id']} nuSrc={r['nu_src']:.8g} nuResamp={r['nu_resampling']:.8g} delta={r['nu_delta_rel_to_src']:.4%} curve={r['tg_curve_rms_over_A0_vs_src']:.4%}")
    print(f"[0493n-audit] status={overall} checks={len(checks)} nonGo={len(bad)}")
    print(f"[0493n-audit] perRun={per_path}")
    print(f"[0493n-audit] pairwise={pair_path}")
    print(f"[0493n-audit] checks={checks_path}")
    print(f"[0493n-audit] report={report_path}")
    return 2 if overall == "NO_GO" else 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""0493x12yl — paired Young–Laplace surface-tension calibrator.

The calibrator measures the mechanical surface tension of the *current production
free-surface chain* from paired static drops at identical radius and seed:

    dp_cap = p(sigma) - p(sigma=0)
    dp_cap = G_sigma * sigma_declared * <kappa>
    sigma_eff = G_sigma * sigma_declared

The sigma=0 subtraction removes the solved-Q6 pressure gauge/background.  The
active-run measured curvature is used, so discrete geometry is not silently
replaced by 1/R.  No pandas/scipy dependency is required.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from pathlib import Path
from typing import Iterable


def read_rows(path: Path):
    if not path.is_file():
        raise SystemExit(f"[0493x12yl-analyze] missing {path}")
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"[0493x12yl-analyze] empty {path}")
    return rows


def finite_float(row, key, default=math.nan):
    try:
        x = float(row[key])
        return x if math.isfinite(x) else default
    except Exception:
        return default


def mean(xs: Iterable[float]):
    q = [x for x in xs if math.isfinite(x)]
    return statistics.fmean(q) if q else math.nan


def stdev(xs: Iterable[float]):
    q = [x for x in xs if math.isfinite(x)]
    return statistics.stdev(q) if len(q) > 1 else 0.0


def tail(rows, frac):
    if not rows:
        return []
    i = max(0, min(len(rows) - 1, int(math.floor(frac * len(rows)))))
    return rows[i:]


def slope_origin(pairs):
    q = [(x, y) for x, y in pairs if math.isfinite(x) and math.isfinite(y)]
    den = sum(x * x for x, _ in q)
    return sum(x * y for x, y in q) / den if den > 0 else math.nan


def slope_origin_se(pairs, slope):
    q = [(x, y) for x, y in pairs if math.isfinite(x) and math.isfinite(y)]
    if len(q) < 2 or not math.isfinite(slope):
        return math.nan
    den = sum(x * x for x, _ in q)
    if den <= 0:
        return math.nan
    rss = sum((y - slope * x) ** 2 for x, y in q)
    dof = max(1, len(q) - 1)
    return math.sqrt((rss / dof) / den)


def free_line(pairs):
    q = [(x, y) for x, y in pairs if math.isfinite(x) and math.isfinite(y)]
    if len(q) < 2:
        return math.nan, math.nan
    mx = mean(x for x, _ in q)
    my = mean(y for _, y in q)
    den = sum((x - mx) ** 2 for x, _ in q)
    if den <= 0:
        return math.nan, math.nan
    b = sum((x - mx) * (y - my) for x, y in q) / den
    return my - b * mx, b


def r2_centered(pairs, intercept, slope):
    q = [(x, y) for x, y in pairs if math.isfinite(x) and math.isfinite(y)]
    if len(q) < 2:
        return math.nan
    ym = mean(y for _, y in q)
    ss = sum((y - ym) ** 2 for _, y in q)
    er = sum((y - (intercept + slope * x)) ** 2 for x, y in q)
    return 1.0 - er / ss if ss > 0 else math.nan


def summarize_run(manifest_row, tail_start):
    run = Path(manifest_row["run_dir"])
    p = run / "output/cuda_static_drop_pressure_0493x9e.csv"
    rr = tail(read_rows(p), tail_start)

    lim = run / "output/cuda_surface_tension_limiter_0493x9r.csv"
    vel = run / "output/cuda_static_drop_velocity_0493x9e.csv"

    out = {
        "sigma": float(manifest_row["sigma"]),
        "r_cells": float(manifest_row["r_cells"]),
        "seed": int(manifest_row["seed"]),
        "run_dir": str(run),
        "tail_rows": len(rr),
        "pressure": mean(finite_float(r, "measuredPressureJump") for r in rr),
        "pressure_time_std": stdev(finite_float(r, "measuredPressureJump") for r in rr),
        "alpha_area": mean(finite_float(r, "alphaArea") for r in rr),
        "r_eff": mean(finite_float(r, "effectiveRadius") for r in rr),
        "kappa": mean(finite_float(r, "curvatureMean") for r in rr),
        "kappa_equiv": mean(finite_float(r, "equivalentCurvature") for r in rr),
        "max_tail_clip_fraction": 0.0,
        "liquid_mean_drift": math.nan,
        "interface_speed_rms": math.nan,
    }

    if lim.is_file():
        lr = tail(read_rows(lim), tail_start)
        out["max_tail_clip_fraction"] = max(
            [finite_float(r, "clipFraction", 0.0) for r in lr] or [0.0]
        )
    if vel.is_file():
        vr = tail(read_rows(vel), tail_start)
        vx = mean(finite_float(r, "liquidMeanVx") for r in vr)
        vy = mean(finite_float(r, "liquidMeanVy") for r in vr)
        out["liquid_mean_drift"] = math.hypot(vx, vy)
        out["interface_speed_rms"] = mean(
            finite_float(r, "interfaceSpeedRms") for r in vr
        )
    return out


def write_csv(path: Path, rows):
    if not rows:
        return
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def self_test():
    pairs = [(1.0, 0.97), (2.0, 1.94), (3.0, 2.91), (4.0, 3.88)]
    b = slope_origin(pairs)
    a, bf = free_line(pairs)
    assert abs(b - 0.97) < 1e-12
    assert abs(a) < 1e-12 and abs(bf - 0.97) < 1e-12
    assert abs(r2_centered(pairs, 0.0, b) - 1.0) < 1e-12
    assert slope_origin_se(pairs, b) < 1e-12
    print("[0493x12yl-analyze] self-test PASS")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path)
    ap.add_argument("--output-dir", type=Path)
    ap.add_argument("--tail-start", type=float, default=0.5)
    ap.add_argument("--characteristic-U", type=float, default=-1.0)
    ap.add_argument("--characteristic-D", type=float, default=-1.0)
    ap.add_argument("--kinematic-viscosity", type=float, default=-1.0)
    ap.add_argument("--gravity", type=float, default=0.0)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        self_test()
        return 0
    if args.manifest is None or args.output_dir is None:
        raise SystemExit("--manifest and --output-dir are required")
    if not (0.0 <= args.tail_start < 1.0):
        raise SystemExit("--tail-start must lie in [0,1)")

    manifest = read_rows(args.manifest)
    sigma_values = sorted({float(r["sigma_declared"]) for r in manifest})
    if len(sigma_values) != 1 or not (sigma_values[0] > 0):
        raise SystemExit("[0493x12yl-analyze] manifest must contain one positive sigma_declared")
    sigma_declared = sigma_values[0]

    active = [summarize_run(r, args.tail_start) for r in manifest if float(r["sigma"]) > 0]
    base = [summarize_run(r, args.tail_start) for r in manifest if abs(float(r["sigma"])) < 1e-15]
    bidx = {(r["r_cells"], r["seed"]): r for r in base}
    missing = sorted(
        {(r["r_cells"], r["seed"]) for r in active if (r["r_cells"], r["seed"]) not in bidx}
    )
    if missing:
        raise SystemExit("[0493x12yl-analyze] missing sigma=0 pairs: " + repr(missing))

    paired = []
    for r in active:
        b = bidx[(r["r_cells"], r["seed"])]
        dp = r["pressure"] - b["pressure"]
        target = sigma_declared * r["kappa"]
        gain = dp / target if target else math.nan
        k_eq = r["kappa_equiv"]
        paired.append({
            "r_cells": r["r_cells"],
            "seed": r["seed"],
            "sigma_declared": sigma_declared,
            "pressure_active": r["pressure"],
            "pressure_sigma0": b["pressure"],
            "pressure_capillary_increment": dp,
            "pressure_time_std_active": r["pressure_time_std"],
            "pressure_time_std_sigma0": b["pressure_time_std"],
            "kappa_active": r["kappa"],
            "kappa_equivalent_active": k_eq,
            "curvature_rel_error": (r["kappa"] - k_eq) / k_eq if k_eq else math.nan,
            "r_eff_active": r["r_eff"],
            "target_sigma_kappa": target,
            "gain_vs_kappa": gain,
            "sigma_effective_pair": sigma_declared * gain if math.isfinite(gain) else math.nan,
            "max_tail_clip_fraction": r["max_tail_clip_fraction"],
            "liquid_mean_drift": r["liquid_mean_drift"],
            "interface_speed_rms": r["interface_speed_rms"],
            "active_run_dir": r["run_dir"],
            "baseline_run_dir": b["run_dir"],
        })

    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(args.output_dir / "young_laplace_pairs_0493x12yl.csv", paired)

    groups = {}
    for r in paired:
        groups.setdefault(r["r_cells"], []).append(r)
    grouped = []
    for rc, rs in sorted(groups.items()):
        gains = [r["gain_vs_kappa"] for r in rs]
        dps = [r["pressure_capillary_increment"] for r in rs]
        kappas = [r["kappa_active"] for r in rs]
        grouped.append({
            "r_cells": rc,
            "replicates": len(rs),
            "gain_mean": mean(gains),
            "gain_seed_std": stdev(gains),
            "sigma_effective_mean": sigma_declared * mean(gains),
            "dp_cap_mean": mean(dps),
            "dp_cap_seed_std": stdev(dps),
            "kappa_mean": mean(kappas),
            "max_tail_clip_fraction": max(r["max_tail_clip_fraction"] for r in rs),
        })
    write_csv(args.output_dir / "young_laplace_radii_0493x12yl.csv", grouped)

    xy = [(r["target_sigma_kappa"], r["pressure_capillary_increment"]) for r in paired]
    gain = slope_origin(xy)
    gain_se = slope_origin_se(xy, gain)
    origin_r2 = r2_centered(xy, 0.0, gain)
    free_a, free_b = free_line(xy)
    free_r2 = r2_centered(xy, free_a, free_b)
    pair_gains = [r["gain_vs_kappa"] for r in paired]
    radius_gains = [r["gain_mean"] for r in grouped]
    pair_std = stdev(pair_gains)
    radius_std = stdev(radius_gains)
    radius_rel_std = radius_std / abs(gain) if gain else math.inf
    free_rel_diff = abs(free_b / gain - 1.0) if gain and math.isfinite(free_b) else math.inf
    max_clip = max([r["max_tail_clip_fraction"] for r in paired] or [0.0])

    notes = []
    if not math.isfinite(gain) or gain <= 0:
        notes.append("nonpositive_or_nonfinite_gain")
    if not math.isfinite(origin_r2) or origin_r2 < 0.90:
        notes.append("originR2_below_0p90")
    if radius_rel_std > 0.10:
        notes.append("radius_gain_relstd_above_10pct")
    if free_rel_diff > 0.15:
        notes.append("free_vs_origin_slope_diff_above_15pct")
    if max_clip > 0.02:
        notes.append("curvature_limiter_active_above_2pct")

    if not notes:
        status = "PASS"
    elif (
        math.isfinite(gain) and gain > 0 and math.isfinite(origin_r2) and origin_r2 >= 0.80
        and radius_rel_std <= 0.20 and free_rel_diff <= 0.30 and max_clip <= 0.10
    ):
        status = "REVIEW"
    else:
        status = "INVALID"

    sigma_raw = sigma_declared * gain if math.isfinite(gain) else math.nan
    sigma_qualified = sigma_raw if status == "PASS" else math.nan
    sigma_slope_se = sigma_declared * gain_se if math.isfinite(gain_se) else math.nan
    sigma_radius_spread = sigma_declared * radius_std if math.isfinite(radius_std) else math.nan

    first = manifest[0]
    h = float(first["h"])
    gamma = float(first["gamma"])
    mass = float(first["liquid_mass"])
    rho = gamma * mass / (h * h)
    U = args.characteristic_U
    D = args.characteristic_D
    nu = args.kinematic_viscosity
    sig_for_nd = sigma_qualified if math.isfinite(sigma_qualified) else sigma_raw
    we = rho * U * U * D / sig_for_nd if U > 0 and D > 0 and sig_for_nd > 0 else math.nan
    re = U * D / nu if U > 0 and D > 0 and nu > 0 else math.nan
    oh = nu * math.sqrt(rho / (sig_for_nd * D)) if nu > 0 and D > 0 and sig_for_nd > 0 else math.nan
    bo = rho * abs(args.gravity) * D * D / sig_for_nd if D > 0 and sig_for_nd > 0 else math.nan

    summary = {
        "status": status,
        "sigmaDeclared": sigma_declared,
        "surfaceTensionGainRaw": gain,
        "surfaceTensionGainSlopeStd": gain_se,
        "surfaceTensionGainPairStd": pair_std,
        "surfaceTensionGainRadiusStd": radius_std,
        "surfaceTensionGainRadiusRelStd": radius_rel_std,
        "surfaceTensionEffectiveRaw": sigma_raw,
        "surfaceTensionEffective": sigma_qualified,
        "surfaceTensionSlopeStd": sigma_slope_se,
        "surfaceTensionRadiusSpread": sigma_radius_spread,
        "originFitR2": origin_r2,
        "freeIntercept": free_a,
        "freeSlope": free_b,
        "freeFitR2": free_r2,
        "freeVsOriginSlopeRelDiff": free_rel_diff,
        "pairedRuns": len(paired),
        "radii": " ".join(f"{r['r_cells']:g}" for r in grouped),
        "replicatesMin": min((r["replicates"] for r in grouped), default=0),
        "tailStart": args.tail_start,
        "maxTailClipFraction": max_clip,
        "rhoReference": rho,
        "weber": we,
        "reynolds": re,
        "ohnesorge": oh,
        "bond": bo,
        "qualityNotes": ";".join(notes) if notes else "none",
        "definition": "paired Young-Laplace: dp_cap=[p(sigma)-p(0)]=sigma_eff*<kappa>_active",
    }
    write_csv(args.output_dir / "young_laplace_calibration_0493x12yl.csv", [summary])
    (args.output_dir / "young_laplace_calibration_0493x12yl.json").write_text(
        json.dumps(summary, indent=2, allow_nan=True) + "\n"
    )

    report = [
        "===== 0493x12yl YOUNG-LAPLACE SURFACE-TENSION CALIBRATION =====",
        f"status={status} sigmaDeclared={sigma_declared:.9g} sigmaEffRaw={sigma_raw:.9g} gain={gain:.9g}",
        f"qualifiedSigmaEff={sigma_qualified:.9g} slopeStd={sigma_slope_se:.6g} radiusSpread={sigma_radius_spread:.6g}",
        f"pairs={len(paired)} radii={summary['radii']} originR2={origin_r2:.6g} freeSlope={free_b:.6g} freeIntercept={free_a:.6g}",
        f"pairGainStd={pair_std:.6g} radiusGainRelStd={radius_rel_std:.6g} maxTailClipFraction={max_clip:.6g}",
        f"qualityNotes={summary['qualityNotes']}",
        "observable: dp_cap = measuredPressureJump(sigma) - measuredPressureJump(sigma=0), paired at fixed radius and seed",
        "primary law: dp_cap = sigma_eff * <kappa>_active",
        "scope: mechanical/static surface tension of the exact selected production chain; capillary-wave dispersion is a separate validation",
    ]
    if math.isfinite(we):
        report.append(f"dimensionless: rho={rho:.9g} We={we:.9g} Re={re:.9g} Oh={oh:.9g} Bo={bo:.9g}")
    text = "\n".join(report) + "\n"
    (args.output_dir / "young_laplace_calibration_report_0493x12yl.txt").write_text(text)
    print(text, end="")

    try:
        import matplotlib.pyplot as plt

        x = [r["target_sigma_kappa"] for r in paired]
        y = [r["pressure_capillary_increment"] for r in paired]
        hi = max(x) * 1.05 if x else 1.0
        fig = plt.figure()
        ax = fig.add_subplot(111)
        ax.scatter(x, y)
        ax.plot([0, hi], [0, hi], label="unit slope")
        ax.plot([0, hi], [0, gain * hi], label=f"fit gain={gain:.4f} ({status})")
        ax.set_xlabel("declared sigma * measured mean curvature")
        ax.set_ylabel("paired capillary pressure increment")
        ax.legend()
        fig.tight_layout()
        fig.savefig(args.output_dir / "young_laplace_pressure_0493x12yl.png", dpi=170)
        plt.close(fig)

        fig = plt.figure()
        ax = fig.add_subplot(111)
        ax.scatter([r["r_cells"] for r in paired], [r["gain_vs_kappa"] for r in paired])
        ax.axhline(gain, label=f"global gain={gain:.4f}")
        ax.axhline(1.0, linestyle="--", label="unit gain")
        ax.set_xlabel("R/h")
        ax.set_ylabel("paired Young-Laplace gain")
        ax.legend()
        fig.tight_layout()
        fig.savefig(args.output_dir / "young_laplace_gain_vs_radius_0493x12yl.png", dpi=170)
        plt.close(fig)
        print(f"[0493x12yl-analyze] plots={args.output_dir/'young_laplace_pressure_0493x12yl.png'} {args.output_dir/'young_laplace_gain_vs_radius_0493x12yl.png'}")
    except Exception as e:
        print(f"[0493x12yl-analyze] plotting skipped: {e}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Analyze the 0493x20f reduced longitudinal SRC / particle-field-closure map.

Campaign-only analysis.  No pandas and no solver modification.

The particle-state diagnostic resolves the coherent Fourier mode independently of
Q6.  For the closure path, the solver's resident Q6 audit is read separately so
we do not confuse a Fourier/post-processing metric with the projection operator's
own divergence diagnostic.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import math
import re
import sys
from pathlib import Path

import numpy as np

AUDIT = "cuda_species_q6_independent_masked_0493w5.csv"
REQUIRED_AUDIT = {
    "step", "time", "q6Strength", "converged", "residualRel",
    "divBeforeRms", "divAfterProjectedFaceFluxRms",
    "divAfterAppliedCellVelocityRms", "densityRelaxationTargetDivRms",
}


def ff(x, default=math.nan):
    try:
        return float(x)
    except Exception:
        return default


def ii(x, default=0):
    try:
        return int(float(x))
    except Exception:
        return default


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def clean_value(v):
    if isinstance(v, (float, np.floating)) and not math.isfinite(float(v)):
        return "NA"
    return v


def write_csv(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("")
        return
    fields = []
    for row in rows:
        for key in row:
            if key not in fields:
                fields.append(key)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        for row in rows:
            w.writerow({k: clean_value(row.get(k, "")) for k in fields})


def read_csv(path: Path):
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def stats(values):
    a = np.asarray([float(x) for x in values if math.isfinite(ff(x))], float)
    if len(a) == 0:
        return dict(n=0, mean=math.nan, std=math.nan, cv=math.nan)
    mean = float(np.mean(a))
    std = float(np.std(a, ddof=1)) if len(a) > 1 else 0.0
    return dict(n=len(a), mean=mean, std=std,
                cv=std / abs(mean) if mean != 0.0 else math.nan)


def elapsed_seconds(path: Path):
    try:
        m = re.search(r"elapsed=([0-9.eE+\-]+)", path.read_text(errors="ignore"))
        return float(m.group(1)) if m else math.nan
    except Exception:
        return math.nan


def mode_metrics(w1, state_path: Path, k: float):
    st = w1.read_state(state_path)
    role = st.get("role")
    mask = (role == 1) if role is not None else np.ones(len(st["x"]), dtype=bool)
    x = np.asarray(st["x"][mask], float)
    m = np.asarray(st["mass"][mask], float)
    vx = np.asarray(st["vx"][mask], float)
    vy = np.asarray(st["vy"][mask], float)
    M = float(np.sum(m))
    if not (M > 0.0):
        raise ValueError(f"no fluid mass in {state_path}")
    b = np.exp(-1j * k * x)
    rho = complex(2.0 * np.sum(m * b) / M)
    ux = complex(2.0 * np.sum(m * vx * b) / M)
    uy = complex(2.0 * np.sum(m * vy * b) / M)
    return rho, ux, uy


def state_series(w1, run_dir: Path, dt: float, k: float):
    init = sorted((run_dir / "init").glob("*.smpcd"))
    if not init:
        raise ValueError(f"missing initial state under {run_dir / 'init'}")
    rows = [(0, 0.0, *mode_metrics(w1, init[0], k))]
    for step, path in w1.list_dumps(run_dir):
        rows.append((int(step), float(step) * dt, *mode_metrics(w1, path, k)))
    # Solver may emit step 0; prefer the last occurrence for a unique sequence.
    uniq = {r[0]: r for r in rows}
    return [uniq[s] for s in sorted(uniq)]


def valid_zero_crossings(t, y, threshold_fraction=0.10):
    t = np.asarray(t, float)
    y = np.asarray(y, float)
    if len(y) < 3 or not math.isfinite(float(y[0])) or abs(y[0]) <= 0.0:
        return []
    amp0 = abs(float(y[0]))
    times = []
    for j in range(1, len(y)):
        a, b = float(y[j - 1]), float(y[j])
        if not (math.isfinite(a) and math.isfinite(b)):
            continue
        if a == 0.0:
            continue
        crossed = (a < 0.0 <= b) or (a > 0.0 >= b)
        if not crossed:
            continue
        lo = max(0, j - 2)
        hi = min(len(y), j + 3)
        local = float(np.max(np.abs(y[lo:hi])))
        if local < threshold_fraction * amp0:
            continue
        if b == a:
            z = float(t[j])
        else:
            z = float(t[j - 1] - a * (t[j] - t[j - 1]) / (b - a))
        if not times or z - times[-1] > 1.0e-12:
            times.append(z)
    return times


def crossing_fit(crossings, k):
    if len(crossings) < 4:
        return dict(c=math.nan, omega=math.nan, r2=math.nan,
                    windowRelDiff=math.nan, crossings=len(crossings))
    z = np.asarray(crossings, float)
    n = np.arange(len(z), dtype=float)
    p = np.polyfit(n, z, 1)
    pred = p[0] * n + p[1]
    ss_res = float(np.sum((z - pred) ** 2))
    ss_tot = float(np.sum((z - np.mean(z)) ** 2))
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 1.0
    omega = math.pi / p[0] if p[0] > 0 else math.nan
    c = omega / k if math.isfinite(omega) else math.nan
    wd = math.nan
    if len(z) >= 6:
        def c4(q):
            slope = np.polyfit(np.arange(4, dtype=float), np.asarray(q[:4], float), 1)[0]
            return math.pi / (slope * k) if slope > 0 else math.nan
        c_first = c4(z[:4])
        c_last = c4(z[-4:])
        if math.isfinite(c_first) and math.isfinite(c_last):
            wd = abs(c_last - c_first) / max(0.5 * (abs(c_last) + abs(c_first)), 1e-300)
    return dict(c=c, omega=omega, r2=r2, windowRelDiff=wd,
                crossings=len(crossings))


def audit_rows(run_dir: Path):
    path = run_dir / "output" / AUDIT
    rows = read_csv(path)
    if not rows:
        return path, []
    missing = REQUIRED_AUDIT.difference(rows[0].keys())
    if missing:
        raise ValueError(f"{path}: missing columns {sorted(missing)}")
    # Single projected liquid species: retain strictly positive-strength rows.
    rows = [r for r in rows if ff(r.get("q6Strength"), 0.0) > 0.0]
    return path, rows


def check_audit(run_dir: Path):
    path, rows = audit_rows(run_dir)
    if not rows:
        raise SystemExit(f"[x20f-audit] FAIL no projected-liquid audit rows in {path}")
    finite_keys = [
        "divBeforeRms", "divAfterProjectedFaceFluxRms",
        "divAfterAppliedCellVelocityRms", "densityRelaxationTargetDivRms",
        "residualRel",
    ]
    bad = []
    for r in rows:
        if r.get("converged") != "1":
            bad.append(f"step {r.get('step')}: converged={r.get('converged')}")
        for key in finite_keys:
            if not math.isfinite(ff(r.get(key))):
                bad.append(f"step {r.get('step')}: {key} nonfinite")
    if bad:
        raise SystemExit("[x20f-audit] FAIL " + "; ".join(bad[:8]))
    first, last = rows[0], rows[-1]
    print(f"[x20f-audit] PASS file={path} rows={len(rows)} "
          f"steps={first.get('step')}..{last.get('step')} "
          f"divBefore0={ff(first.get('divBeforeRms')):.6e} "
          f"constraintResidual0={ff(first.get('divAfterProjectedFaceFluxRms')):.6e} "
          f"postApplied0={ff(first.get('divAfterAppliedCellVelocityRms')):.6e} "
          f"target0={ff(first.get('densityRelaxationTargetDivRms')):.6e}")


def analyze_run(w1, campaign: Path, r):
    run_dir = campaign / r["runDir"]
    marker = run_dir / "RUN_COMPLETE_0493x20f"
    failed = run_dir / "RUN_FAILED_0493x20f"
    if not marker.exists():
        return ({**r, "runStatus": "FAILED" if failed.exists() else "MISSING"}, [])

    dt = ff(r["dt"]); lx = ff(r["Lx"]); mode = ii(r["modeX"], 1)
    k = 2.0 * math.pi * mode / lx
    period_ref = lx / (ff(r["csReference"]) * mode)
    ss = state_series(w1, run_dir, dt, k)
    ux0 = ss[0][3]
    phase = np.conj(ux0) / abs(ux0) if abs(ux0) > 0 else 1.0 + 0j
    al0 = float(np.real(ux0 * phase))
    if abs(al0) <= 0.0:
        raise ValueError(f"zero initial longitudinal mode in {run_dir}")

    audit_path, qarows = audit_rows(run_dir) if r["model"] == "src-q6-g-f" else (None, [])
    qa = {ii(q.get("step")): q for q in qarows}
    series = []
    signed = []
    times = []
    for step, time, rho, ux, uy in ss:
        al = float(np.real(ux * phase))
        at_signed = float(np.real(uy * phase))
        alr = al / al0
        signed.append(al)
        times.append(time)
        q = qa.get(step, {})
        db = ff(q.get("divBeforeRms"))
        dp = ff(q.get("divAfterProjectedFaceFluxRms"))
        da = ff(q.get("divAfterAppliedCellVelocityRms"))
        dtar = ff(q.get("densityRelaxationTargetDivRms"))
        series.append({
            "model": r["model"], "mach": r["mach"], "seed": r["seed"],
            "step": step, "time": time, "cycles_ref": time / period_ref,
            "AL": al, "AL_over_AL0": alr,
            "AT_signed_over_AL0": at_signed / al0,
            "AT_abs_over_AL0": abs(uy) / abs(al0),
            "density_mode_real_rotated": float(np.real(rho * phase)),
            "density_mode_abs": abs(rho),
            "div_mode_rms": k * abs(ux) / math.sqrt(2.0),
            "epsilon_div_mode": abs(ux) / abs(ux0),
            "q6_div_before_rms": db,
            "q6_constraint_residual_rms": dp,
            "q6_div_after_applied_rms": da,
            "q6_target_div_rms": dtar,
            "q6_abs_suppression_ratio": da / db if db > 0 and math.isfinite(da) else math.nan,
            "q6_constraint_residual_to_pre": dp / db if db > 0 and math.isfinite(dp) else math.nan,
            "q6_target_to_pre": dtar / db if db > 0 and math.isfinite(dtar) else math.nan,
        })

    crossings = valid_zero_crossings(times, signed)
    cf = crossing_fit(crossings, k)
    tail_start = max(1, int(math.floor(0.8 * len(series))))
    al_tail = [abs(ff(q["AL_over_AL0"])) for q in series[tail_start:]]
    at_peak = max(abs(ff(q["AT_abs_over_AL0"])) for q in series)
    rho_peak = max(abs(ff(q["density_mode_abs"])) for q in series)

    q_abs = []
    q_res = []
    q_target = []
    q_pre = []
    for q in qarows:
        db = ff(q.get("divBeforeRms")); da = ff(q.get("divAfterAppliedCellVelocityRms"))
        dp = ff(q.get("divAfterProjectedFaceFluxRms")); dtar = ff(q.get("densityRelaxationTargetDivRms"))
        if db > 0 and math.isfinite(da): q_abs.append(da / db)
        if db > 0 and math.isfinite(dp): q_res.append(dp / db)
        if db > 0 and math.isfinite(dtar): q_target.append(dtar / db)
        if math.isfinite(db): q_pre.append(db)

    # Individual candidate only; group/seed coherence is applied later.
    fit_window_ok = (not math.isfinite(cf["windowRelDiff"])) or cf["windowRelDiff"] <= 0.10
    prop_candidate = (cf["crossings"] >= 4 and math.isfinite(cf["c"]) and
                      cf["r2"] >= 0.98 and fit_window_ok)

    out = {
        **r, "runStatus": "COMPLETE", "samples": len(series),
        "AL_initial": al0,
        "AL_tail_abs_mean": float(np.mean(al_tail)) if al_tail else math.nan,
        "AL_tail_abs_max": float(np.max(al_tail)) if al_tail else math.nan,
        "transverse_peak_over_AL0": at_peak,
        "density_mode_peak": rho_peak,
        "validZeroCrossings": cf["crossings"],
        "c_candidate": cf["c"] if prop_candidate else math.nan,
        "omega_candidate": cf["omega"] if prop_candidate else math.nan,
        "crossingFitR2": cf["r2"],
        "crossingWindowRelativeDifference": cf["windowRelDiff"],
        "individualAcousticModeStatus": "PROPAGATIVE_CANDIDATE" if prop_candidate else "SUPPRESSED_OR_NONRESOLVABLE",
        "q6AuditRows": len(qarows),
        "q6DivBeforeInitial": q_pre[0] if q_pre else math.nan,
        "q6AbsSuppressionInitial": q_abs[0] if q_abs else math.nan,
        "q6AbsSuppressionMedian": float(np.median(q_abs)) if q_abs else math.nan,
        "q6AbsSuppressionLongTime": q_abs[-1] if q_abs else math.nan,
        "q6ConstraintResidualToPreInitial": q_res[0] if q_res else math.nan,
        "q6ConstraintResidualToPreMedian": float(np.median(q_res)) if q_res else math.nan,
        "q6TargetToPreInitial": q_target[0] if q_target else math.nan,
        "elapsedSeconds": elapsed_seconds(run_dir / "logs" / "time_0493x20f.txt"),
        "q6AuditFile": str(audit_path) if audit_path else "NA",
    }
    return out, series


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign-root", default="runs/0493x20f_longitudinal_reduced_map")
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--check-audit", type=Path, default=None)
    a = ap.parse_args()
    if a.check_audit is not None:
        check_audit(a.check_audit)
        return

    root = Path(a.repo_root).resolve()
    campaign = (root / a.campaign_root).resolve() if not Path(a.campaign_root).is_absolute() else Path(a.campaign_root)
    manifest = campaign / "manifest_0493x20f.csv"
    rows = read_csv(manifest)
    if not rows:
        raise SystemExit(f"[x20f-analysis] missing/empty manifest: {manifest}")
    w1 = load_module(root / "scripts" / "analyze_0493w1_src_fluid_calibrator.py", "w1_x20f")

    run_rows = []
    series_rows = []
    for r in rows:
        try:
            q, s = analyze_run(w1, campaign, r)
        except Exception as exc:
            q, s = ({**r, "runStatus": "ANALYSIS_ERROR", "error": repr(exc)}, [])
        run_rows.append(q)
        series_rows.extend(s)

    analysis = campaign / "analysis"
    write_csv(analysis / "longitudinal_map_realizations.csv", run_rows)
    write_csv(analysis / "longitudinal_map_timeseries.csv", series_rows)

    groups = []
    case_order = []
    for r in run_rows:
        cid = r.get("case_id", r.get("case", ""))
        if cid and cid not in case_order:
            case_order.append(cid)
    for cid in case_order:
        for model in ("src", "src-q6-g-f"):
            g = [r for r in run_rows if r.get("model") == model and r.get("runStatus") == "COMPLETE" and r.get("case_id", r.get("case", "")) == cid]
            if not g:
                continue
            mach = ff(g[0].get("mach"))
            cs = stats([ff(r.get("c_candidate")) for r in g])
            tail = stats([ff(r.get("AL_tail_abs_mean")) for r in g])
            trans = stats([ff(r.get("transverse_peak_over_AL0")) for r in g])
            sup0 = stats([ff(r.get("q6AbsSuppressionInitial")) for r in g])
            supmed = stats([ff(r.get("q6AbsSuppressionMedian")) for r in g])
            cres0 = stats([ff(r.get("q6ConstraintResidualToPreInitial")) for r in g])
            cres = stats([ff(r.get("q6ConstraintResidualToPreMedian")) for r in g])
            candidates = sum(r.get("individualAcousticModeStatus") == "PROPAGATIVE_CANDIDATE" for r in g)
            resolved = candidates >= 2 and cs["n"] >= 2 and math.isfinite(cs["cv"]) and cs["cv"] <= 0.10
            mode_status = "PROPAGATIVE_RESOLVED" if resolved else "SUPPRESSED_OR_NONRESOLVABLE"
            base = g[0]
            groups.append({
                "case_id": cid, "sweep": base.get("sweep", ""), "x": base.get("x", ""),
                "ell": base.get("ell", ""), "gamma": base.get("gamma", ""), "alpha_SRC_deg": base.get("alpha_SRC_deg", ""),
                "dt": base.get("dt", ""), "model": model, "mach": mach, "completedSeeds": len(g),
                "propagativeCandidateSeeds": candidates,
                "acousticModeStatus": mode_status,
                "c_resolved": cs["mean"] if resolved else math.nan,
                "c_std": cs["std"] if resolved else math.nan,
                "c_CV": cs["cv"] if resolved else math.nan,
                "AL_tail_abs_mean": tail["mean"], "AL_tail_abs_std": tail["std"],
                "transverse_peak_over_AL0_mean": trans["mean"],
                "q6AbsSuppressionInitial_mean": sup0["mean"],
                "q6AbsSuppressionMedian_mean": supmed["mean"],
                "q6ConstraintResidualToPreInitial_mean": cres0["mean"],
                "q6ConstraintResidualToPreMedian_mean": cres["mean"],
            })
    write_csv(analysis / "longitudinal_map_aggregated.csv", groups)

    # Compact factual decision note.  It deliberately does not decide the paper's conclusion.
    lines = [
        "0493x20f reduced longitudinal map — factual analysis\n",
        f"campaign={campaign}\n",
        "Criteria for a resolved propagative mode: >=2/3 seeds with >=4 valid signed zero crossings, crossing fit R2>=0.98, window frequency variation <=10% when measurable, and seed CV(c)<=10%.\n",
        "Q6 projected-face quantity is the residual to the active divergence constraint; post-applied-cell quantity is absolute reconstructed divergence.\n",
    ]
    for g in groups:
        lines.append(
            f"case={g.get('case_id','')} model={g['model']} Ma={g['mach']} seeds={g['completedSeeds']} acoustic={g['acousticModeStatus']} "
            f"c={clean_value(g['c_resolved'])} AL_tail={clean_value(g['AL_tail_abs_mean'])} "
            f"Sdiv_initial={clean_value(g['q6AbsSuppressionInitial_mean'])} "
            f"constraintResidual/pre={clean_value(g['q6ConstraintResidualToPreMedian_mean'])}\n"
        )
    (analysis / "longitudinal_map_decision.txt").write_text("".join(lines))
    print(f"[x20f-analysis] realizations={len(run_rows)} timeseries={len(series_rows)} groups={len(groups)}")
    for g in groups:
        print(f"[x20f-analysis] case={g.get('case_id',''):<18} model={g['model']:<12} Ma={g['mach']:.3g} seeds={g['completedSeeds']} mode={g['acousticModeStatus']} c={clean_value(g['c_resolved'])}")


def self_test():
    c = 0.35512
    lx = 0.25
    k = 2 * math.pi / lx
    t = np.linspace(0, 3.4 * lx / c, 150)
    y = np.cos(c * k * t) * np.exp(-0.05 * t)
    z = valid_zero_crossings(t, y)
    q = crossing_fit(z, k)
    rel = abs(q["c"] - c) / c
    print(f"[x20f-analysis-selftest] crossings={len(z)} c={q['c']:.9g} relErr={rel:.3e} r2={q['r2']:.9g}")
    if len(z) < 4 or rel > 5e-3 or q["r2"] < .999:
        raise SystemExit(2)


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
    else:
        main()

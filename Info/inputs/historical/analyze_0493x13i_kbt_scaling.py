#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import importlib.util
import math
from pathlib import Path
from types import SimpleNamespace

import numpy as np


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if not spec or not spec.loader:
        raise RuntimeError(f"cannot import {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_csv(path: Path):
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


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
        w.writerows(rows)


def ff(row, key, default=math.nan):
    try:
        return float(row[key])
    except Exception:
        return default


def stats(values):
    a = np.asarray([x for x in values if math.isfinite(x)], float)
    if len(a) == 0:
        return dict(n=0, mean=math.nan, std=math.nan, sem=math.nan, cv=math.nan)
    mean = float(a.mean())
    sd = float(a.std(ddof=1)) if len(a) > 1 else 0.0
    return dict(n=len(a), mean=mean, std=sd,
                sem=sd / math.sqrt(len(a)), cv=sd / abs(mean) if mean else math.nan)


def quantiles(values):
    a = np.asarray([x for x in values if math.isfinite(x)], float)
    if len(a) == 0:
        return dict(mean=math.nan, std=math.nan, p025=math.nan, p50=math.nan, p975=math.nan)
    return dict(mean=float(a.mean()), std=float(a.std(ddof=1)) if len(a) > 1 else 0.0,
                p025=float(np.quantile(a, .025)), p50=float(np.quantile(a, .5)),
                p975=float(np.quantile(a, .975)))


def relspread(values):
    a = np.asarray([x for x in values if math.isfinite(x) and x > 0], float)
    if len(a) < 2:
        return math.nan
    med = float(np.median(a))
    return float((a.max() - a.min()) / med) if med > 0 else math.nan


def grade_spread(spread, pass_limit, review_limit):
    if not math.isfinite(spread):
        return "UNRESOLVED"
    if spread <= pass_limit:
        return "PASS"
    if spread <= review_limit:
        return "REVIEW"
    return "UNRESOLVED"


def fit_power(kbt, values):
    x, y = [], []
    for t, q in zip(kbt, values):
        if t > 0 and q > 0 and math.isfinite(t) and math.isfinite(q):
            x.append(math.log(t)); y.append(math.log(q))
    if len(x) < 2:
        return dict(exponent=math.nan, prefactor=math.nan, r2=math.nan)
    coef = np.polyfit(np.asarray(x), np.asarray(y), 1)
    pred = coef[0] * np.asarray(x) + coef[1]
    yy = np.asarray(y)
    sse = float(np.sum((yy - pred) ** 2)); sst = float(np.sum((yy - yy.mean()) ** 2))
    return dict(exponent=float(coef[0]), prefactor=float(math.exp(coef[1])),
                r2=1.0 - sse / sst if sst > 0 else 1.0)


def fit_msd_series(w1, t, msd):
    t = np.asarray(t, float); msd = np.asarray(msd, float)
    candidates = []
    for fraction in (.20, .30, .40, .50):
        fit = w1.linear_fit(t[t >= fraction * t[-1]], msd[t >= fraction * t[-1]])
        if fit["slope"] > 0 and fit["points"] >= 6:
            candidates.append((fit["r2"], -fraction, fit, fraction))
    if candidates:
        _, _, fit, fraction = max(candidates, key=lambda z: (z[0], z[1]))
    else:
        fit = w1.linear_fit(t[1:], msd[1:]); fraction = 0.0
    d = fit["slope"] / 4.0
    status = "PASS" if d > 0 and fit["r2"] >= .995 else (
        "REVIEW" if d > 0 and fit["r2"] >= .98 else "INVALID")
    return dict(selfDiffusion=d, fitR2=fit["r2"], fitPoints=fit["points"],
                fitStartFraction=fraction, status=status)


def bootstrap_shear(rng, x13h_b, stacks, t, k, nboot):
    vals = []
    n = len(stacks)
    arr = np.asarray(stacks, float)
    for _ in range(nboot):
        idx = rng.integers(0, n, size=n)
        fit = x13h_b.fit_series(t, arr[idx].mean(axis=0), k)
        if fit["status"] in ("PASS", "REVIEW") and fit["nuT"] > 0:
            vals.append(float(fit["nuT"]))
    return quantiles(vals), len(vals)


def bootstrap_msd(rng, w1, stacks, t, nboot):
    vals = []
    n = len(stacks)
    arr = np.asarray(stacks, float)
    for _ in range(nboot):
        idx = rng.integers(0, n, size=n)
        fit = fit_msd_series(w1, t, arr[idx].mean(axis=0))
        if fit["status"] in ("PASS", "REVIEW") and fit["selfDiffusion"] > 0:
            vals.append(float(fit["selfDiffusion"]))
    return quantiles(vals), len(vals)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign-root", type=Path, required=True)
    ap.add_argument("--repo-root", type=Path, default=Path("."))
    ap.add_argument("--bootstrap", type=int, default=1000)
    ap.add_argument("--bootstrap-seed", type=int, default=4932139)
    ap.add_argument("--reference-kBT", type=float, default=.125)
    ap.add_argument("--target-lambda-over-h", type=float, default=.72)
    a = ap.parse_args()

    root = a.repo_root.resolve(); campaign = a.campaign_root
    analysis = campaign / "analysis"; analysis.mkdir(parents=True, exist_ok=True)
    x13b = load_module(root / "scripts/analyze_0493x13b_constitutive_transport.py", "x13b_i")
    x13h_b = load_module(root / "scripts/analyze_0493x13h_B_density_transport_L072.py", "x13hb_i")
    w1 = x13b.load_w1(root)
    rng = np.random.default_rng(a.bootstrap_seed)

    # ---- Shear ----
    sroot = campaign / "S_shear"
    sman = read_csv(sroot / "manifest_0493x13i_shear.csv")
    shear_runs, shear_series = [], {}
    for row in sman:
        run = sroot / row["runDir"]
        marker = run / "RUN_COMPLETE_0493x13i_shear"
        if not marker.exists():
            shear_runs.append({**row, "shearStatus": "MISSING"}); continue
        try:
            q = x13b.analyze_shear_run(w1, row, sroot)
            ser, k = x13h_b.shear_series(w1, row, sroot)
            key = (ff(row, "kBT"), int(ff(row, "wavelengthCells")), int(ff(row, "seed")))
            shear_series[key] = (ser, k)
            shear_runs.append(q)
        except Exception as e:
            shear_runs.append({**row, "shearStatus": "ERROR", "error": str(e)})
    write_csv(analysis / "shear_runs_0493x13i.csv", shear_runs)

    shear_summary = []
    groups = sorted({(ff(r, "kBT"), int(ff(r, "wavelengthCells"))) for r in shear_runs
                     if math.isfinite(ff(r, "kBT")) and math.isfinite(ff(r, "wavelengthCells"))})
    for kbt, ny in groups:
        allg = [r for r in shear_runs if abs(ff(r, "kBT") - kbt) < 1e-15 and int(ff(r, "wavelengthCells")) == ny]
        g = [r for r in allg if r.get("shearStatus") in ("PASS", "REVIEW") and ff(r, "nuT") > 0]
        st = stats([ff(r, "nuT") for r in g])
        stacks, tref, kref = [], None, math.nan
        for r in g:
            key = (kbt, ny, int(ff(r, "seed")))
            if key not in shear_series: continue
            ser, k = shear_series[key]
            t = np.asarray([z[1] for z in ser]); amp = np.asarray([z[2] for z in ser])
            if tref is None: tref = t; kref = k
            if len(t) == len(tref) and np.allclose(t, tref, rtol=0, atol=1e-12): stacks.append(amp)
        ens = x13h_b.fit_series(tref, np.mean(np.vstack(stacks), axis=0), kref) if stacks else dict(status="MISSING", nuT=math.nan, r2=math.nan, points=0, span=math.nan)
        bq, nb = bootstrap_shear(rng, x13h_b, stacks, tref, kref, a.bootstrap) if stacks else (quantiles([]), 0)
        passfrac = sum(r.get("shearStatus") == "PASS" for r in allg) / max(1, len(allg))
        grade = "PASS" if len(g) >= 5 and passfrac >= .75 and ens["status"] == "PASS" and st["cv"] <= .22 else (
            "REVIEW" if len(g) >= 4 and ens["status"] in ("PASS", "REVIEW") and st["cv"] <= .30 else "UNRESOLVED")
        base = allg[0] if allg else {}
        shear_summary.append({
            "kBT": kbt, "kBTScale": ff(base, "kBTScale"), "dt": ff(base, "dt"),
            "wavelengthCells": ny, "kLambda": ff(base, "kLambda"),
            "amplitude": ff(base, "amplitude"), "expectedSeeds": len(allg), "validSeeds": len(g),
            "passFraction": passfrac, "nuTIndividualMean": st["mean"], "nuTIndividualStd": st["std"],
            "nuTIndividualSem": st["sem"], "nuTIndividualCV": st["cv"],
            "nuTEnsembleFit": ens["nuT"], "ensembleFitR2": ens["r2"], "ensembleFitStatus": ens["status"],
            "bootstrapCompleted": nb, "nuTBootstrapMean": bq["mean"], "nuTBootstrapStd": bq["std"],
            "nuTBootstrapP025": bq["p025"], "nuTBootstrapMedian": bq["p50"], "nuTBootstrapP975": bq["p975"],
            "grade": grade,
        })
    write_csv(analysis / "shear_summary_0493x13i.csv", shear_summary)

    # locality 128 vs 256 per kBT
    locality = []
    for kbt in sorted({ff(r, "kBT") for r in shear_summary}):
        d = {int(ff(r, "wavelengthCells")): r for r in shear_summary if abs(ff(r, "kBT") - kbt) < 1e-15}
        r128, r256 = d.get(128), d.get(256)
        n128, n256 = ff(r128 or {}, "nuTEnsembleFit"), ff(r256 or {}, "nuTEnsembleFit")
        rel = abs(n256 - n128) / (0.5 * (n256 + n128)) if n128 > 0 and n256 > 0 else math.nan
        if r128 and r256 and r128.get("grade") == "PASS" and r256.get("grade") == "PASS" and rel <= .15:
            grade = "LOCAL_PASS"
        elif r128 and r256 and r128.get("grade") in ("PASS", "REVIEW") and r256.get("grade") in ("PASS", "REVIEW") and rel <= .25:
            grade = "LOCAL_REVIEW"
        else:
            grade = "UNRESOLVED"
        locality.append({"kBT": kbt, "nuT128Ensemble": n128, "nuT256Ensemble": n256,
                         "wavelengthRelativeDifference": rel, "localityGrade": grade})
    write_csv(analysis / "shear_locality_0493x13i.csv", locality)

    # ---- Sound: x13h analyzer output is reused directly ----
    sound_groups = read_csv(analysis / "A_Cdamp_group_statistics_0493x13h.csv")
    sound = []
    for r in sound_groups:
        kbt = ff(r, "kBT")
        if not math.isfinite(kbt): continue
        sound.append({
            "kBT": kbt, "kBTScale": ff(r, "kBTScale"), "dt": ff(r, "dt"),
            "replicatesCompleted": ff(r, "replicatesCompleted"), "dampStatus": r.get("dampStatus", ""),
            "cs": ff(r, "csDampedPooled"), "nuL": ff(r, "nuLDampedPooled"), "fitR2": ff(r, "fitR2Pooled"),
            "csBootstrapMean": ff(r, "csBootstrapMean"), "csBootstrapStd": ff(r, "csBootstrapStd"),
            "csBootstrapP025": ff(r, "csBootstrapP025"), "csBootstrapP975": ff(r, "csBootstrapP975"),
            "nuLBootstrapMean": ff(r, "nuLBootstrapMean"), "nuLBootstrapStd": ff(r, "nuLBootstrapStd"),
            "nuLBootstrapP025": ff(r, "nuLBootstrapP025"), "nuLBootstrapP975": ff(r, "nuLBootstrapP975"),
            "bootstrapUsableFraction": ff(r, "bootstrapUsableFraction"),
        })
    write_csv(analysis / "sound_summary_0493x13i.csv", sound)

    # ---- MSD ----
    mroot = campaign / "M_msd"; mman = read_csv(mroot / "manifest_0493x13i_msd.csv")
    msd_runs, msd_curves = [], {}
    for row in mman:
        case_root = mroot / row["runDir"]
        marker = case_root / "msd" / "RUN_COMPLETE_0493x13i_msd"
        if not marker.exists():
            msd_runs.append({**row, "diffusionStatus": "MISSING"}); continue
        try:
            ns = SimpleNamespace(root=case_root, dt=ff(row, "dt"), msd_sample_particles=int(ff(row, "sampleParticles")),
                                 msd_Lx=ff(row, "Lx"), msd_Ly=ff(row, "Ly"))
            series, result = w1.analyze_msd(ns)
            status = "PASS" if result["selfDiffusion"] > 0 and result["fitR2"] >= .995 else (
                "REVIEW" if result["selfDiffusion"] > 0 and result["fitR2"] >= .98 else "INVALID")
            q = {**row, "diffusionStatus": status, **result}
            msd_runs.append(q)
            msd_curves[(ff(row, "kBT"), int(ff(row, "seed")))] = series
        except Exception as e:
            msd_runs.append({**row, "diffusionStatus": "ERROR", "error": str(e)})
    write_csv(analysis / "msd_runs_0493x13i.csv", msd_runs)

    msd_summary = []
    for kbt in sorted({ff(r, "kBT") for r in msd_runs if math.isfinite(ff(r, "kBT"))}):
        allg = [r for r in msd_runs if abs(ff(r, "kBT") - kbt) < 1e-15]
        g = [r for r in allg if r.get("diffusionStatus") in ("PASS", "REVIEW") and ff(r, "selfDiffusion") > 0]
        st = stats([ff(r, "selfDiffusion") for r in g])
        curves, tref = [], None
        for r in g:
            key = (kbt, int(ff(r, "seed")))
            if key not in msd_curves: continue
            ser = msd_curves[key]
            t = np.asarray([ff(z, "time") for z in ser]); y = np.asarray([ff(z, "msd") for z in ser])
            if tref is None: tref = t
            if len(t) == len(tref) and np.allclose(t, tref, rtol=0, atol=1e-12): curves.append(y)
        ens = fit_msd_series(w1, tref, np.mean(np.vstack(curves), axis=0)) if curves else dict(status="MISSING", selfDiffusion=math.nan, fitR2=math.nan, fitPoints=0, fitStartFraction=math.nan)
        bq, nb = bootstrap_msd(rng, w1, curves, tref, a.bootstrap) if curves else (quantiles([]), 0)
        passfrac = sum(r.get("diffusionStatus") == "PASS" for r in allg) / max(1, len(allg))
        grade = "PASS" if len(g) >= 5 and passfrac >= .75 and ens["status"] == "PASS" and st["cv"] <= .15 else (
            "REVIEW" if len(g) >= 4 and ens["status"] in ("PASS", "REVIEW") and st["cv"] <= .25 else "UNRESOLVED")
        base = allg[0] if allg else {}
        msd_summary.append({
            "kBT": kbt, "kBTScale": ff(base, "kBTScale"), "dt": ff(base, "dt"),
            "expectedSeeds": len(allg), "validSeeds": len(g), "passFraction": passfrac,
            "DselfIndividualMean": st["mean"], "DselfIndividualStd": st["std"], "DselfIndividualSem": st["sem"], "DselfIndividualCV": st["cv"],
            "DselfEnsembleFit": ens["selfDiffusion"], "ensembleFitR2": ens["fitR2"], "ensembleFitStatus": ens["status"],
            "bootstrapCompleted": nb, "DselfBootstrapMean": bq["mean"], "DselfBootstrapStd": bq["std"],
            "DselfBootstrapP025": bq["p025"], "DselfBootstrapMedian": bq["p50"], "DselfBootstrapP975": bq["p975"],
            "grade": grade,
        })
    write_csv(analysis / "msd_summary_0493x13i.csv", msd_summary)

    # ---- Consolidated scaling table ----
    sb = {(ff(r, "kBT"), int(ff(r, "wavelengthCells"))): r for r in shear_summary}
    snd = {ff(r, "kBT"): r for r in sound}
    md = {ff(r, "kBT"): r for r in msd_summary}
    loc = {ff(r, "kBT"): r for r in locality}
    kbts = sorted(set([k for k, ny in sb if ny == 256]) | set(snd) | set(md))
    summary = []
    h = None
    if sman: h = ff(sman[0], "cellSize")
    for kbt in kbts:
        s = sb.get((kbt, 256), {}); c = snd.get(kbt, {}); d = md.get(kbt, {}); l = loc.get(kbt, {})
        nu, cs, nul, diff = ff(s, "nuTEnsembleFit"), ff(c, "cs"), ff(c, "nuL"), ff(d, "DselfEnsembleFit")
        scale = math.sqrt(kbt / a.reference_kBT) if kbt > 0 else math.nan
        dt = ff(s, "dt", ff(c, "dt", ff(d, "dt")))
        lambda_over_h = math.sqrt(math.pi * kbt / 2.0) * dt / h if h and kbt > 0 and dt > 0 else math.nan
        summary.append({
            "kBT": kbt, "sqrtScaleVsReference": scale, "dt": dt, "lambdaOverHMeasured": lambda_over_h,
            "lambdaOverHError": lambda_over_h - a.target_lambda_over_h if math.isfinite(lambda_over_h) else math.nan,
            "nuT": nu, "nuTNormBySqrtScale": nu / scale if scale > 0 else math.nan,
            "nuTBootstrapP025": ff(s, "nuTBootstrapP025"), "nuTBootstrapP975": ff(s, "nuTBootstrapP975"),
            "nuTGrade": s.get("grade", ""), "localityGrade": l.get("localityGrade", ""),
            "cs": cs, "csNormBySqrtScale": cs / scale if scale > 0 else math.nan,
            "csBootstrapP025": ff(c, "csBootstrapP025"), "csBootstrapP975": ff(c, "csBootstrapP975"),
            "soundStatus": c.get("dampStatus", ""),
            "nuL": nul, "nuLNormBySqrtScale": nul / scale if scale > 0 else math.nan,
            "Dself": diff, "DselfNormBySqrtScale": diff / scale if scale > 0 else math.nan,
            "DselfBootstrapP025": ff(d, "DselfBootstrapP025"), "DselfBootstrapP975": ff(d, "DselfBootstrapP975"),
            "diffusionGrade": d.get("grade", ""),
            "H_h": cs * h / nu if h and cs > 0 and nu > 0 else math.nan,
            "Sc": nu / diff if nu > 0 and diff > 0 else math.nan,
        })
    write_csv(analysis / "kbt_scaling_summary_0493x13i.csv", summary)

    kvec = [ff(r, "kBT") for r in summary]
    laws = []
    for name, field, normfield, pass_spread, review_spread, exp_tol_pass, exp_tol_review in (
        ("cs", "cs", "csNormBySqrtScale", .03, .06, .05, .10),
        ("nuT", "nuT", "nuTNormBySqrtScale", .15, .25, .10, .20),
        ("nuL_secondary", "nuL", "nuLNormBySqrtScale", .20, .35, .15, .30),
        ("Dself", "Dself", "DselfNormBySqrtScale", .15, .25, .10, .20),
    ):
        vals = [ff(r, field) for r in summary]; norm = [ff(r, normfield) for r in summary]
        p = fit_power(kvec, vals); spread = relspread(norm)
        sg = grade_spread(spread, pass_spread, review_spread)
        eg = "PASS" if math.isfinite(p["exponent"]) and abs(p["exponent"] - .5) <= exp_tol_pass else (
            "REVIEW" if math.isfinite(p["exponent"]) and abs(p["exponent"] - .5) <= exp_tol_review else "UNRESOLVED")
        grade = "PASS" if sg == "PASS" and eg == "PASS" else (
            "REVIEW" if sg in ("PASS", "REVIEW") and eg in ("PASS", "REVIEW") else "UNRESOLVED")
        laws.append({"quantity": name, "expectedExponent": .5, "fittedExponent": p["exponent"], "powerFitR2": p["r2"],
                     "normalizedRelativeSpread": spread, "spreadGrade": sg, "exponentGrade": eg, "grade": grade})
    hh_spread = relspread([ff(r, "H_h") for r in summary]); sc_spread = relspread([ff(r, "Sc") for r in summary])
    laws.append({"quantity": "H_h", "expectedExponent": 0.0, "fittedExponent": fit_power(kvec, [ff(r, "H_h") for r in summary])["exponent"],
                 "powerFitR2": fit_power(kvec, [ff(r, "H_h") for r in summary])["r2"], "normalizedRelativeSpread": hh_spread,
                 "spreadGrade": grade_spread(hh_spread, .15, .25), "exponentGrade": "N/A", "grade": grade_spread(hh_spread, .15, .25)})
    laws.append({"quantity": "Sc", "expectedExponent": 0.0, "fittedExponent": fit_power(kvec, [ff(r, "Sc") for r in summary])["exponent"],
                 "powerFitR2": fit_power(kvec, [ff(r, "Sc") for r in summary])["r2"], "normalizedRelativeSpread": sc_spread,
                 "spreadGrade": grade_spread(sc_spread, .20, .30), "exponentGrade": "N/A", "grade": grade_spread(sc_spread, .20, .30)})
    write_csv(analysis / "kbt_scaling_laws_0493x13i.csv", laws)

    primary = [r for r in laws if r["quantity"] in ("cs", "nuT", "Dself", "H_h", "Sc")]
    locality_ok = all(r.get("localityGrade") in ("LOCAL_PASS", "LOCAL_REVIEW") for r in locality) and len(locality) >= 3
    if primary and all(r["grade"] == "PASS" for r in primary) and locality_ok:
        overall = "PASS"
    elif primary and all(r["grade"] in ("PASS", "REVIEW") for r in primary) and locality_ok:
        overall = "REVIEW"
    else:
        overall = "UNRESOLVED"

    md_lines = [
        "# 0493x13i kBT scaling results", "",
        f"Overall status: **{overall}**", "",
        "The primary hypothesis is cs, nuT and Dself proportional to sqrt(kBT), with H_h and Sc invariant at fixed gamma, rotation angle and lambda/h.", "",
        "| kBT | dt | nuT | cs | nuL | Dself | H_h | Sc | locality |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|:---|",
    ]
    for r in summary:
        md_lines.append(f"| {ff(r,'kBT'):.6g} | {ff(r,'dt'):.9g} | {ff(r,'nuT'):.6g} | {ff(r,'cs'):.6g} | {ff(r,'nuL'):.6g} | {ff(r,'Dself'):.6g} | {ff(r,'H_h'):.6g} | {ff(r,'Sc'):.6g} | {r.get('localityGrade','')} |")
    md_lines += ["", "## Scaling laws", "", "| quantity | fitted exponent | normalized spread | grade |", "|:---|---:|---:|:---|"]
    for r in laws:
        md_lines.append(f"| {r['quantity']} | {ff(r,'fittedExponent'):.6g} | {ff(r,'normalizedRelativeSpread'):.4g} | {r['grade']} |")
    md_lines += ["", "Detailed per-run, bootstrap and locality CSV files are preserved in this directory.", ""]
    (analysis / "README_0493x13i_RESULTS.md").write_text("\n".join(md_lines))

    print("[0493x13i-analysis] kBT dt nuT cs Dself H_h Sc locality")
    for r in summary:
        print(f"  {ff(r,'kBT'):.6g} {ff(r,'dt'):.9g} {ff(r,'nuT'):.6g} {ff(r,'cs'):.6g} {ff(r,'Dself'):.6g} {ff(r,'H_h'):.5g} {ff(r,'Sc'):.5g} {r.get('localityGrade','')}")
    print("[0493x13i-analysis] scaling quantity exponent spread grade")
    for r in laws:
        print(f"  {r['quantity']:<14s} p={ff(r,'fittedExponent'):.5g} spread={ff(r,'normalizedRelativeSpread'):.4g} {r['grade']}")
    print(f"[0493x13i-analysis] OVERALL={overall} output={analysis}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,json,math,statistics
from pathlib import Path

def get_int(d, *names):
    for name in names:
        if name in d:
            return int(d[name])
    raise KeyError(f"none of {names} present; available keys={sorted(d)}")

ap=argparse.ArgumentParser()
ap.add_argument("--root",type=Path,required=True)
ap.add_argument("--seeds",type=int,nargs="+",required=True)
ap.add_argument("--poiseuille-solid-nu",type=float,required=True)
ap.add_argument("--poiseuille-chi-nu",type=float,required=True)
ap.add_argument("--old-src-reference-nu",type=float,required=True)
a=ap.parse_args()

rows=[]
for seed in a.seeds:
    p=a.root/f"seed_{seed}"/"analysis"/"tg_calibration_0493x7n.json"
    if not p.is_file():
        raise SystemExit(f"[0493x8e-cal] missing {p}")
    d=json.loads(p.read_text())
    if d.get("calibrationPath")!="src-q6-g-f":
        raise SystemExit(
            f"[0493x8e-cal] seed={seed}: calibrationPath={d.get('calibrationPath')}"
        )

    # Current x7n schema uses fitStartIndex/fitEndIndex.
    # Keep compatibility with earlier local x7n summaries that used *Step.
    fit_start=get_int(d,"fitStartIndex","fitStartStep")
    fit_end=get_int(d,"fitEndIndex","fitEndStep")

    rows.append({
        "seed":seed,
        "status":d["viscosityStatus"],
        "nu":float(d["viscosityKinematic"]),
        "R2":float(d["fitR2"]),
        "windowStd":float(d["viscosityWindowStd"]),
        "windowMin":float(d["viscosityWindowMin"]),
        "windowMax":float(d["viscosityWindowMax"]),
        "fitStartIndex":fit_start,
        "fitEndIndex":fit_end,
        "fitPoints":int(d.get("fitPoints",fit_end-fit_start+1)),
        "fitWindowCandidates":int(d.get("fitWindowCandidates",0)),
        "fitStableWindows":int(d.get("fitStableWindows",0)),
        "fitStableFallback":bool(d.get("fitStableFallback",False)),
    })

nus=[r["nu"] for r in rows]
r2s=[r["R2"] for r in rows]
mean=statistics.mean(nus)
std=statistics.stdev(nus) if len(nus)>1 else 0.0
sem=std/math.sqrt(len(nus)) if nus else math.nan
median=statistics.median(nus)
all_pass=all(r["status"]=="PASS" for r in rows)

summary={
    "schema":"0493x8e-q6gf-tg-ensemble-v1-fix1",
    "method":"mean/std of independent canonical x7n/0493w1 TG fits; no refit",
    "seeds":a.seeds,
    "n":len(rows),
    "allCanonicalFitsPass":all_pass,
    "nuMean":mean,
    "nuStdBetweenSeeds":std,
    "nuSem":sem,
    "nuMedian":median,
    "nuMin":min(nus),
    "nuMax":max(nus),
    "meanR2":statistics.mean(r2s),
    "poiseuilleSolidNu":a.poiseuille_solid_nu,
    "poiseuilleChiNu":a.poiseuille_chi_nu,
    "oldSrcReferenceNu":a.old_src_reference_nu,
    "tgMinusSolidRelative":(mean-a.poiseuille_solid_nu)/a.poiseuille_solid_nu,
    "tgMinusChiRelative":(mean-a.poiseuille_chi_nu)/a.poiseuille_chi_nu,
    "tgMinusOldSrcRelative":(mean-a.old_src_reference_nu)/a.old_src_reference_nu,
}

analysis=a.root/"analysis"
analysis.mkdir(parents=True,exist_ok=True)

with (analysis/"q6gf_tg_seed_fits_0493x8e.csv").open("w",newline="",encoding="utf-8") as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)

(analysis/"q6gf_tg_ensemble_0493x8e.json").write_text(
    json.dumps(summary,indent=2,sort_keys=True)+"\n",
    encoding="utf-8"
)

with (analysis/"q6gf_tg_ensemble_0493x8e.csv").open("w",newline="",encoding="utf-8") as f:
    w=csv.DictWriter(f,fieldnames=list(summary))
    w.writeheader()
    w.writerow(summary)

print("\n===== 0493x8e Q6-G-F TG VISCOSITY ENSEMBLE =====")
print("seed       status      nu              R2          windowStd      fitIndex  stable/candidates")
for r in rows:
    print(
        f"{r['seed']:<10d} {r['status']:<10s} {r['nu']:<15.9g} "
        f"{r['R2']:<11.7g} {r['windowStd']:<14.6g} "
        f"{r['fitStartIndex']}:{r['fitEndIndex']} "
        f"{r['fitStableWindows']}/{r['fitWindowCandidates']}"
    )

print("\nEnsemble of canonical fits:")
print(f"  nuMean              = {mean:.10g}")
print(f"  nuStdBetweenSeeds   = {std:.6g}")
print(f"  nuSEM               = {sem:.6g}")
print(f"  nuMedian            = {median:.10g}")
print(f"  range               = [{min(nus):.10g}, {max(nus):.10g}]")
print(f"  meanR2              = {statistics.mean(r2s):.8g}")
print(f"  allCanonicalPASS    = {int(all_pass)}")

print("\nCross-check against x8d:")
print(
    f"  solid Poiseuille nu = {a.poiseuille_solid_nu:.10g}; "
    f"TG-solid = {summary['tgMinusSolidRelative']:+.3%}"
)
print(
    f"  chi Brinkman nu     = {a.poiseuille_chi_nu:.10g}; "
    f"TG-chi   = {summary['tgMinusChiRelative']:+.3%}"
)
print(
    f"  old SRC reference   = {a.old_src_reference_nu:.10g}; "
    f"TG-oldSRC= {summary['tgMinusOldSrcRelative']:+.3%}"
)

print(f"\nNU_DESIGN={mean:.17g}")
print(f"summary={analysis/'q6gf_tg_ensemble_0493x8e.json'}")
print("status=COMPLETE")

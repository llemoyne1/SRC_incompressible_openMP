#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,json,math,statistics
from pathlib import Path

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
    if not p.is_file(): raise SystemExit(f"missing {p}")
    d=json.loads(p.read_text())
    if d.get("calibrationPath")!="src-q6-g-f":
        raise SystemExit(f"seed {seed}: wrong path {d.get('calibrationPath')}")
    rows.append(dict(seed=seed,status=d["viscosityStatus"],
        nu=float(d["viscosityKinematic"]),R2=float(d["fitR2"]),
        windowStd=float(d["viscosityWindowStd"]),
        fitStartStep=int(d.get("fitStartIndex", d.get("fitStartStep"))),fitEndStep=int(d.get("fitEndIndex", d.get("fitEndStep")))))

nus=[r["nu"] for r in rows]; r2=[r["R2"] for r in rows]
mean=statistics.mean(nus)
std=statistics.stdev(nus) if len(nus)>1 else 0.0
sem=std/math.sqrt(len(nus))
summary={
 "schema":"0493x8e-q6gf-tg-ensemble-v1",
 "method":"mean/std of independent canonical x7n/0493w1 TG fits; no refit",
 "seeds":a.seeds,"n":len(rows),
 "allCanonicalFitsPass":all(r["status"]=="PASS" for r in rows),
 "nuMean":mean,"nuStdBetweenSeeds":std,"nuSem":sem,
 "nuMedian":statistics.median(nus),"nuMin":min(nus),"nuMax":max(nus),
 "meanR2":statistics.mean(r2),
 "poiseuilleSolidNu":a.poiseuille_solid_nu,
 "poiseuilleChiNu":a.poiseuille_chi_nu,
 "oldSrcReferenceNu":a.old_src_reference_nu,
 "tgMinusSolidRelative":(mean-a.poiseuille_solid_nu)/a.poiseuille_solid_nu,
 "tgMinusChiRelative":(mean-a.poiseuille_chi_nu)/a.poiseuille_chi_nu,
 "tgMinusOldSrcRelative":(mean-a.old_src_reference_nu)/a.old_src_reference_nu,
}
out=a.root/"analysis"; out.mkdir(parents=True,exist_ok=True)
with (out/"q6gf_tg_seed_fits_0493x8e.csv").open("w",newline="") as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
(out/"q6gf_tg_ensemble_0493x8e.json").write_text(json.dumps(summary,indent=2,sort_keys=True)+"\n")

print("\n===== 0493x8e Q6-G-F TG VISCOSITY ENSEMBLE =====")
print("seed       status      nu              R2          windowStd      fitSteps")
for r in rows:
    print(f"{r['seed']:<10d} {r['status']:<10s} {r['nu']:<15.9g} {r['R2']:<11.7g} "
          f"{r['windowStd']:<14.6g} {r['fitStartStep']}:{r['fitEndStep']}")
print(f"\nnuMean            = {mean:.10g}")
print(f"nuStdBetweenSeeds = {std:.6g}")
print(f"nuSEM             = {sem:.6g}")
print(f"nuMedian          = {statistics.median(nus):.10g}")
print(f"range             = [{min(nus):.10g}, {max(nus):.10g}]")
print(f"meanR2            = {statistics.mean(r2):.8g}")
print(f"allCanonicalPASS  = {int(summary['allCanonicalFitsPass'])}")
print(f"\nsolid Poiseuille nu = {a.poiseuille_solid_nu:.10g}; TG-solid = {summary['tgMinusSolidRelative']:+.3%}")
print(f"chi Brinkman nu     = {a.poiseuille_chi_nu:.10g}; TG-chi   = {summary['tgMinusChiRelative']:+.3%}")
print(f"old SRC reference   = {a.old_src_reference_nu:.10g}; TG-SRC = {summary['tgMinusOldSrcRelative']:+.3%}")
print(f"\nNU_DESIGN={mean:.17g}")
print(f"summary={out/'q6gf_tg_ensemble_0493x8e.json'}")
print("status=COMPLETE")

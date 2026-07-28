#!/usr/bin/env python3
"""Collate and rank 0493w1 effective-fluid calibration candidates."""
from __future__ import annotations
import argparse, csv, json, math
from pathlib import Path


def f(row, key):
    try:
        return float(row.get(key, ""))
    except (TypeError, ValueError):
        return math.nan


def read_one(path):
    with path.open(newline="") as stream:
        return next(csv.DictReader(stream))


def write_csv(path, rows):
    keys=[]
    for row in rows:
        for key in row:
            if key not in keys: keys.append(key)
    with path.open("w", newline="") as stream:
        writer=csv.DictWriter(stream, fieldnames=keys)
        writer.writeheader(); writer.writerows(rows)


def classify(row):
    sound_ok=row.get("soundStatus")=="PASS"
    transport_ok=row.get("viscosityStatus") in ("PASS","REVIEW") and row.get("diffusionStatus") in ("PASS","REVIEW")
    re03=f(row,"reynoldsAtMach0p3")
    lam=f(row,"lambdaMeanOverCell")
    sc=f(row,"Schmidt")
    if sound_ok and transport_ok and 30 <= re03 <= 150 and 0.05 <= lam <= 0.55 and sc >= 10:
        return "TARGET"
    if sound_ok and transport_ok and re03 >= 10 and 0.03 <= lam <= 0.75:
        return "PROMISING"
    if transport_ok:
        return "REVIEW"
    return "REJECT"


def rank_score(row):
    cls={"TARGET":0,"PROMISING":1,"REVIEW":2,"REJECT":3}[row["physicalClass"]]
    re03=f(row,"reynoldsAtMach0p3")
    lam=f(row,"lambdaMeanOverCell")
    # Prefer Re@Ma=.3 near 70 and lambda/a near .2, after class.
    return (cls, abs(math.log(max(re03,1e-12)/70.0)) if math.isfinite(re03) else 99,
            abs(lam-.2) if math.isfinite(lam) else 99)


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--root", type=Path, required=True)
    a=p.parse_args()
    rows=[]
    for path in sorted(a.root.glob("*/analysis/fluid_calibration_0493w1.csv")):
        row=read_one(path)
        row={**row,"case":path.parents[1].name,"resultPath":str(path)}
        row["physicalClass"]=classify(row)
        rows.append(row)
    if not rows:
        raise SystemExit("[0493w1-presweep] no calibration results found")
    rows.sort(key=rank_score)
    for i,row in enumerate(rows,1): row["rank"]=i
    analysis=a.root/"analysis"; analysis.mkdir(exist_ok=True)
    write_csv(analysis/"fluid_presweep_0493w1.csv",rows)
    compact=[]
    for row in rows:
        compact.append({k:row.get(k) for k in (
            "rank","case","physicalClass","status","viscosityStatus","soundStatus","diffusionStatus",
            "cellSizeGeom","dt","kBT","viscosityKinematic","soundSpeed","selfDiffusion","Schmidt",
            "lambdaMeanOverCell","Reynolds","Mach","reynoldsAtMach0p3","machAtRe50",
            "soundMomentumRelativeRms","soundContinuityRelativeRms")})
    (analysis/"fluid_presweep_0493w1.json").write_text(json.dumps(compact,indent=2)+"\n")
    lines=["# 0493w1 effective-fluid physical presweep","",f"Candidates: `{len(rows)}`","", "|rank|case|class|nu|cs|Dself|Sc|lambda/a|Re@Ma=.3|Ma@Re50|", "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|"]
    for r in rows:
        def g(k):
            v=f(r,k); return f"{v:.5g}" if math.isfinite(v) else "—"
        lines.append(f"|{r['rank']}|{r['case']}|{r['physicalClass']}|{g('viscosityKinematic')}|{g('soundSpeed')}|{g('selfDiffusion')}|{g('Schmidt')}|{g('lambdaMeanOverCell')}|{g('reynoldsAtMach0p3')}|{g('machAtRe50')}|")
    lines += ["", "The ranking prefers a validated sound measurement, Re at Ma=0.3 near 70, and a thermal ballistic displacement near 0.2 collision cell.", ""]
    (analysis/"README_0493W1_PRESWEEP.md").write_text("\n".join(lines))
    best=rows[0]
    print("===== 0493w1 FLUID PRESWEEP =====")
    for r in rows:
        print(f"rank={r['rank']} case={r['case']} class={r['physicalClass']} nu={r.get('viscosityKinematic')} cs={r.get('soundSpeed')} ReAtMa0p3={r.get('reynoldsAtMach0p3')} lambda/a={r.get('lambdaMeanOverCell')}")
    print(f"recommended={best['case']} class={best['physicalClass']}")
    print(f"result={analysis/'fluid_presweep_0493w1.csv'}")

if __name__=="__main__": main()

#!/usr/bin/env python3
"""Analyze x14t fix2 using existing per-species runtime CSV.

Primary observable: slope of liquid meanVy in the early window.
"""
from __future__ import annotations
import argparse,csv,json,math
from pathlib import Path

def read_manifest(p):
    with p.open(newline="") as f: return list(csv.DictReader(f))

def liquid_rows(p,liquid_type):
    out=[]
    with p.open(newline="") as f:
        for r in csv.DictReader(f):
            try:
                if int(float(r["type"])) != liquid_type: continue
                out.append(dict(step=int(float(r["step"])),time=float(r["time"]),
                                vy=float(r["meanVy"]),vx=float(r["meanVx"]),
                                mass=float(r["totalMass"])))
            except Exception:
                pass
    out.sort(key=lambda q:q["step"])
    if not out: raise RuntimeError(f"no liquid rows in {p}")
    return out

def ols(points):
    n=len(points)
    if n<3: raise RuntimeError("need >=3 fit points")
    mt=sum(t for t,_ in points)/n; mv=sum(v for _,v in points)/n
    sxx=sum((t-mt)**2 for t,_ in points)
    slope=sum((t-mt)*(v-mv) for t,v in points)/sxx
    intercept=mv-slope*mt
    sse=sum((v-(intercept+slope*t))**2 for t,v in points)
    sst=sum((v-mv)**2 for _,v in points)
    return slope,intercept,(1-sse/sst if sst>0 else 1.0),math.sqrt(sse/n)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--campaign-root",type=Path,required=True)
    ap.add_argument("--manifest",type=Path,default=None)
    ap.add_argument("--liquid-type",type=int,default=1)
    ap.add_argument("--fit-step-min",type=int,default=50)
    ap.add_argument("--fit-step-max",type=int,default=150)
    args=ap.parse_args()
    manifest=args.manifest or args.campaign_root/"manifest_0493x14t.csv"
    cases=read_manifest(manifest); rows=[]
    for c in cases:
        p=Path(c["speciesCsv"])
        rr=liquid_rows(p,args.liquid_type)
        fit=[(r["time"],r["vy"]) for r in rr if args.fit_step_min<=r["step"]<=args.fit_step_max]
        slope,intercept,r2,rms=ols(fit)
        ath=float(c["aTheory"])
        end=max((r for r in rr if r["step"]<=args.fit_step_max),key=lambda q:q["step"])
        out=dict(c)
        out.update(fitStepMin=args.fit_step_min,fitStepMax=args.fit_step_max,
                   fitAccelerationY=slope,fitInterceptVy=intercept,fitR2=r2,fitRmsVy=rms,
                   gainAcceleration=(slope/ath if abs(ath)>0 else math.nan),
                   endpointStep=end["step"],endpointTime=end["time"],endpointMeanVy=end["vy"],
                   endpointTheoryVy=ath*end["time"],
                   endpointGain=(end["vy"]/(ath*end["time"]) if abs(ath*end["time"])>0 else math.nan),
                   endpointMeanVx=end["vx"])
        rows.append(out)
        print(f"[0493x14t-analysis] case={c['case']:11s} aFitY={slope:+.8g} aTheory={ath:+.8g} gain={out['gainAcceleration']:+.5f} R2={r2:.6f} Vy@{end['step']}={end['vy']:+.8g}")
    by={r["case"]:r for r in rows}; ens={}
    if "bottom_high" in by and "top_high" in by:
        ab=float(by["bottom_high"]["fitAccelerationY"]); at=float(by["top_high"]["fitAccelerationY"])
        amag=0.5*(abs(float(by["bottom_high"]["aTheory"]))+abs(float(by["top_high"]["aTheory"])))
        ens["antisymmetricAccelerationY"]=0.5*(ab-at)
        ens["theoryAccelerationMagnitude"]=amag
        ens["normalPressureTransferGain"]=ens["antisymmetricAccelerationY"]/amag
        ens["pairedBiasAccelerationY"]=0.5*(ab+at)
        ens["pairedSymmetryError"]=abs(ab+at)/abs(ab-at) if abs(ab-at)>0 else math.nan
    if "balanced" in by:
        ens["balancedAccelerationY"]=float(by["balanced"]["fitAccelerationY"])
        ens["balancedEndpointVy"]=float(by["balanced"]["endpointMeanVy"])
    print("\n===== 0493x14t NORMAL PRESSURE TRANSFER (FIX2) =====")
    if "normalPressureTransferGain" in ens:
        print(f"G_normal={ens['normalPressureTransferGain']:.6f}")
        print(f"pairedBiasY={ens['pairedBiasAccelerationY']:+.8g}")
        print(f"pairedSymmetryError={ens['pairedSymmetryError']:.6f}")
    if "balancedAccelerationY" in ens:
        print(f"balancedAccelerationY={ens['balancedAccelerationY']:+.8g}")
    print("Target: G_normal ~ 1; balanced acceleration ~ 0.")
    ad=args.campaign_root/"analysis"; ad.mkdir(parents=True,exist_ok=True)
    cp=ad/"normal_pressure_cases_0493x14t.csv"
    jp=ad/"normal_pressure_summary_0493x14t.json"
    with cp.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
    jp.write_text(json.dumps({"benchmark":"0493x14t_fix2_horizontal_normal_pressure_piston",
                              "fitStepMin":args.fit_step_min,"fitStepMax":args.fit_step_max,
                              "cases":rows,"ensemble":ens},indent=2,allow_nan=True)+"\n")
    print(f"cases={cp}"); print(f"summary={jp}")

if __name__=="__main__": main()

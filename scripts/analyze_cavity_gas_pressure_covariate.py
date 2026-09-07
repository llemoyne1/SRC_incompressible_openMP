#!/usr/bin/env python3
import argparse, csv, math
from pathlib import Path

def rows(path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))

def fv(r, k, default=float("nan")):
    try:
        x=float(r[k])
        return x if math.isfinite(x) else default
    except Exception:
        return default

def iv(r, k, default=-1):
    try:
        return int(float(r[k]))
    except Exception:
        return default

ap=argparse.ArgumentParser(
    description="Align liquid-cavity observables with measured gas pressure; no automatic correction is imposed."
)
ap.add_argument("--run-root", required=True)
ap.add_argument("--rho-liquid", type=float, required=True,
                help="liquid reference cell mass / area density used by the campaign")
ap.add_argument("--gravity-abs", type=float, required=True)
ap.add_argument("--sigma", type=float, required=True)
ap.add_argument("--jet-width", type=float, required=True)
ap.add_argument("--post-start-time", type=float, default=2.0)
args=ap.parse_args()

root=Path(args.run_root)
indent=root/"analysis"/"indentation_history.csv"
pressure=root/"output"/"cuda_phase_interface_pressure_0493x6g.csv"
for p in (indent, pressure):
    if not p.exists():
        raise SystemExit(f"[gas-pressure-covariate] missing {p}")

I=rows(indent)
P=rows(pressure)
if not I or not P:
    raise SystemExit("[gas-pressure-covariate] empty input")

# Match by step when available; otherwise by nearest time.
p_by_step={iv(r,"step"):r for r in P if iv(r,"step")>=0}

# Initial reference used only to describe the measured pressure offset.
p_ref0=fv(P[0],"pressureReference")
if not math.isfinite(p_ref0):
    p_ref0=fv(P[0],"pressureReferencePa")

hydro_scale=args.rho_liquid*args.gravity_abs*args.jet_width
cap_scale=args.sigma/args.jet_width

out=[]
for ir in I:
    st=iv(ir,"step")
    pr=p_by_step.get(st)
    if pr is None:
        # nearest-time fallback
        ti=fv(ir,"time")
        candidates=[r for r in P if math.isfinite(fv(r,"time"))]
        if candidates and math.isfinite(ti):
            pr=min(candidates,key=lambda r:abs(fv(r,"time")-ti))
    if pr is None:
        continue

    pref=fv(pr,"pressureReference")
    dp=fv(pr,"pressureDeltaMean")
    pg=pref+dp if math.isfinite(pref) and math.isfinite(dp) else float("nan")
    dpg_ref=pg-p_ref0 if math.isfinite(pg) and math.isfinite(p_ref0) else float("nan")
    head=(p_ref0-pg)/(args.rho_liquid*args.gravity_abs) \
        if args.rho_liquid>0 and args.gravity_abs>0 and math.isfinite(pg) and math.isfinite(p_ref0) else float("nan")

    depth=fv(ir,"depth")
    row={
        "step":st,
        "time":fv(ir,"time"),
        "depth":depth,
        "depthOverJetWidth":depth/args.jet_width if math.isfinite(depth) else float("nan"),
        "halfDepthWidth":fv(ir,"halfDepthWidth"),
        "etaFar":fv(ir,"etaFar"),
        "symmetryRmsRel":fv(ir,"symmetryRmsRel"),
        "gasPressureReference":pref,
        "gasPressureDeltaMean":dp,
        "gasPressureMean":pg,
        "gasPressureMeanOverInitialReference":pg/p_ref0 if math.isfinite(pg) and p_ref0!=0 else float("nan"),
        "gasPressureOffsetFromInitialReference":dpg_ref,
        "equivalentHydrostaticHeadForReferenceMinusGasPressure":head,
        "equivalentHydrostaticHeadOverJetWidth":head/args.jet_width if math.isfinite(head) else float("nan"),
        "gasPressureOffsetOverRhoGd":dpg_ref/hydro_scale if hydro_scale!=0 and math.isfinite(dpg_ref) else float("nan"),
        "gasPressureOffsetOverSigmaOverD":dpg_ref/cap_scale if cap_scale!=0 and math.isfinite(dpg_ref) else float("nan"),
    }
    out.append(row)

adir=root/"analysis"
hist=adir/"cavity_gas_pressure_covariate.csv"
with hist.open("w",newline="") as f:
    w=csv.DictWriter(f,fieldnames=list(out[0]))
    w.writeheader(); w.writerows(out)

post=[r for r in out if r["time"]>=args.post_start_time]
if not post: post=out

def mean(key):
    a=[r[key] for r in post if isinstance(r[key],(int,float)) and math.isfinite(r[key])]
    return sum(a)/len(a) if a else float("nan")

report=adir/"cavity_gas_pressure_covariate_report.txt"
with report.open("w") as f:
    f.write("Cavity / measured gas-pressure covariate\n")
    f.write("========================================\n")
    f.write("Gas pressure is treated as part of the generating condition, not as a pass/fail target.\n")
    f.write("No automatic correction is applied to cavity depth.\n")
    f.write("The equivalent hydrostatic head is reported only as a diagnostic scale.\n\n")
    f.write(f"postStartTime = {args.post_start_time:.12g}\n")
    f.write(f"meanDepthOverJetWidth = {mean('depthOverJetWidth'):.12g}\n")
    f.write(f"meanGasPressureMeanOverInitialReference = {mean('gasPressureMeanOverInitialReference'):.12g}\n")
    f.write(f"meanEquivalentHydrostaticHeadOverJetWidth = {mean('equivalentHydrostaticHeadOverJetWidth'):.12g}\n")
    f.write(f"meanGasPressureOffsetOverRhoGd = {mean('gasPressureOffsetOverRhoGd'):.12g}\n")
    f.write(f"meanGasPressureOffsetOverSigmaOverD = {mean('gasPressureOffsetOverSigmaOverD'):.12g}\n")

print(f"[gas-pressure-covariate] history={hist}")
print(f"[gas-pressure-covariate] report={report}")

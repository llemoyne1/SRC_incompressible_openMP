#!/usr/bin/env python3
"""0493x11c-a — paired Young–Laplace analysis.

Why this exists
---------------
The x9e quantity ``measuredPressureJump`` contains a large solved-Q6 gauge /
background level.  A regression of the *absolute* value through the origin is
therefore not a valid Young–Laplace test.  The physically discriminating
observable is the paired capillary increment at fixed (R/h, seed):

    dp_cap = p(sigma, R, seed) - p(sigma=0, R, seed).

The primary target uses the curvature measured in the active capillary run,

    dp_cap = sigma * <kappa>,

and a secondary geometric target uses sigma/R_eff.

No pandas/scipy dependency.
"""
from __future__ import annotations
import argparse, csv, math, statistics
from pathlib import Path

def read_rows(p: Path):
    if not p.exists():
        raise SystemExit(f"[0493x11c-a] missing {p}")
    with p.open(newline="") as f:
        rows=list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"[0493x11c-a] empty {p}")
    return rows

def F(r,k,default=math.nan):
    try:
        x=float(r[k])
        return x if math.isfinite(x) else default
    except Exception:
        return default

def mean(xs):
    q=[x for x in xs if math.isfinite(x)]
    return statistics.fmean(q) if q else math.nan

def stdev(xs):
    q=[x for x in xs if math.isfinite(x)]
    return statistics.stdev(q) if len(q)>1 else 0.0

def tail(rows, frac):
    i=max(0,min(len(rows)-1,int(math.floor(frac*len(rows)))))
    return rows[i:]

def slope0(pairs):
    q=[(x,y) for x,y in pairs if math.isfinite(x) and math.isfinite(y)]
    den=sum(x*x for x,y in q)
    return sum(x*y for x,y in q)/den if den>0 else math.nan

def free_line(pairs):
    q=[(x,y) for x,y in pairs if math.isfinite(x) and math.isfinite(y)]
    if len(q)<2:
        return math.nan,math.nan
    mx=mean([x for x,y in q]); my=mean([y for x,y in q])
    den=sum((x-mx)**2 for x,y in q)
    b=sum((x-mx)*(y-my) for x,y in q)/den if den>0 else math.nan
    return my-b*mx,b

def r2(pairs,a,b):
    q=[(x,y) for x,y in pairs if math.isfinite(x) and math.isfinite(y)]
    if len(q)<2:
        return math.nan
    ym=mean([y for x,y in q])
    ss=sum((y-ym)**2 for x,y in q)
    er=sum((y-(a+b*x))**2 for x,y in q)
    return 1-er/ss if ss>0 else math.nan

def r2_origin(pairs,b):
    q=[(x,y) for x,y in pairs if math.isfinite(x) and math.isfinite(y)]
    if len(q)<2:
        return math.nan
    # Centered R² is reported even for the origin-constrained fit so it is
    # directly comparable with the free-intercept diagnostic.
    ym=mean([y for x,y in q])
    ss=sum((y-ym)**2 for x,y in q)
    er=sum((y-b*x)**2 for x,y in q)
    return 1-er/ss if ss>0 else math.nan

def summarize_run(m, tail_start):
    run=Path(m["run_dir"])
    p=run/"output/cuda_static_drop_pressure_0493x9e.csv"
    rr=tail(read_rows(p),tail_start)
    v=run/"output/cuda_static_drop_velocity_0493x9e.csv"
    lim=run/"output/cuda_surface_tension_limiter_0493x9r.csv"

    sigma=float(m["sigma"]); rc=float(m["r_cells"]); seed=int(m["seed"])
    out={
        "sigma":sigma,"r_cells":rc,"seed":seed,"run_dir":str(run),
        "tail_rows":len(rr),
        "pressure":mean([F(r,"measuredPressureJump") for r in rr]),
        "pressure_time_std":stdev([F(r,"measuredPressureJump") for r in rr]),
        "alpha_area":mean([F(r,"alphaArea") for r in rr]),
        "r_eff":mean([F(r,"effectiveRadius") for r in rr]),
        "kappa":mean([F(r,"curvatureMean") for r in rr]),
        "kappa_equiv":mean([F(r,"equivalentCurvature") for r in rr]),
        "laplace_target_x9e":mean([F(r,"laplaceTargetCurrent") for r in rr]),
        "max_tail_clip_fraction":0.0,
        "liquid_mean_drift":math.nan,
        "interface_speed_rms":math.nan,
    }
    if lim.exists():
        lr=tail(read_rows(lim),tail_start)
        out["max_tail_clip_fraction"]=max([F(r,"clipFraction",0.0) for r in lr] or [0.0])
    if v.exists():
        vr=tail(read_rows(v),tail_start)
        mvx=mean([F(r,"liquidMeanVx") for r in vr])
        mvy=mean([F(r,"liquidMeanVy") for r in vr])
        out["liquid_mean_drift"]=math.hypot(mvx,mvy)
        out["interface_speed_rms"]=mean([F(r,"interfaceSpeedRms") for r in vr])
    return out

def write_csv(p,rows):
    if not rows:
        return
    with p.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--active-manifest",type=Path,required=True)
    ap.add_argument("--baseline-manifest",type=Path,required=True)
    ap.add_argument("--output-dir",type=Path,default=None)
    ap.add_argument("--tail-start",type=float,default=0.5)
    a=ap.parse_args()
    if not (0<=a.tail_start<1):
        raise SystemExit("--tail-start must be in [0,1)")

    active_manifest=read_rows(a.active_manifest)
    base_manifest=read_rows(a.baseline_manifest)
    active=[summarize_run(m,a.tail_start) for m in active_manifest if float(m["sigma"])>0]
    baselines=[summarize_run(m,a.tail_start) for m in base_manifest if abs(float(m["sigma"]))<1e-15]

    bidx={(r["r_cells"],r["seed"]):r for r in baselines}
    missing=sorted({(r["r_cells"],r["seed"]) for r in active if (r["r_cells"],r["seed"]) not in bidx})
    if missing:
        msg=", ".join(f"R/h={rc:g},seed={seed}" for rc,seed in missing)
        raise SystemExit("[0493x11c-a] missing sigma=0 paired baselines: "+msg)

    paired=[]
    for r in active:
        b=bidx[(r["r_cells"],r["seed"])]
        dp=r["pressure"]-b["pressure"]
        target_kappa=r["sigma"]*r["kappa"]
        target_radius=r["sigma"]/r["r_eff"] if r["r_eff"]>0 else math.nan
        paired.append({
            "sigma":r["sigma"],"r_cells":r["r_cells"],"seed":r["seed"],
            "active_run_dir":r["run_dir"],"baseline_run_dir":b["run_dir"],
            "pressure_active":r["pressure"],"pressure_sigma0":b["pressure"],
            "pressure_capillary_increment":dp,
            "pressure_time_std_active":r["pressure_time_std"],
            "pressure_time_std_sigma0":b["pressure_time_std"],
            "r_eff_active":r["r_eff"],"r_eff_sigma0":b["r_eff"],
            "kappa_active":r["kappa"],"kappa_equiv_active":r["kappa_equiv"],
            "curvature_rel_error":(r["kappa"]-r["kappa_equiv"])/r["kappa_equiv"] if r["kappa_equiv"] else math.nan,
            "target_sigma_kappa":target_kappa,
            "target_sigma_over_reff":target_radius,
            "gain_vs_kappa":dp/target_kappa if target_kappa else math.nan,
            "gain_vs_reff":dp/target_radius if target_radius else math.nan,
            "max_tail_clip_fraction":r["max_tail_clip_fraction"],
            "liquid_mean_drift":r["liquid_mean_drift"],
            "interface_speed_rms":r["interface_speed_rms"],
        })

    outdir=a.output_dir or a.active_manifest.parent/"analysis_refined"
    outdir.mkdir(parents=True,exist_ok=True)
    write_csv(outdir/"young_laplace_paired_runs.csv",paired)

    groups={}
    for r in paired:
        groups.setdefault((r["sigma"],r["r_cells"]),[]).append(r)
    grouped=[]
    for (sig,rc),rs in sorted(groups.items()):
        def vals(k): return [float(x[k]) for x in rs if math.isfinite(float(x[k]))]
        grouped.append({
            "sigma":sig,"r_cells":rc,"seeds":len(rs),
            "dp_cap_mean":mean(vals("pressure_capillary_increment")),
            "dp_cap_seed_std":stdev(vals("pressure_capillary_increment")),
            "target_sigma_kappa_mean":mean(vals("target_sigma_kappa")),
            "gain_vs_kappa_mean":mean(vals("gain_vs_kappa")),
            "gain_vs_kappa_seed_std":stdev(vals("gain_vs_kappa")),
            "gain_vs_reff_mean":mean(vals("gain_vs_reff")),
            "gain_vs_reff_seed_std":stdev(vals("gain_vs_reff")),
            "curvature_rel_error_mean":mean(vals("curvature_rel_error")),
            "curvature_rel_error_seed_std":stdev(vals("curvature_rel_error")),
            "max_tail_clip_fraction":max(vals("max_tail_clip_fraction") or [0.0]),
        })
    write_csv(outdir/"young_laplace_paired_grouped.csv",grouped)

    def select(pred,target):
        return [(r[target],r["pressure_capillary_increment"]) for r in paired if pred(r)]

    suites=[
        ("all",lambda r:True),
        ("radiusSweep_sigma1500",lambda r:abs(r["sigma"]-1500)<1e-12),
        ("sigmaSweep_R20",lambda r:abs(r["r_cells"]-20)<1e-12),
    ]
    lines=[
        "===== 0493x11c-a PAIRED YOUNG-LAPLACE VALIDATION =====",
        f"activeRuns={len(active)} baselines={len(baselines)} pairedRuns={len(paired)} tailStart={a.tail_start:g}",
        "observable: dp_cap = measuredPressureJump(sigma) - measuredPressureJump(sigma=0), paired at fixed R/h and seed",
        "primaryTarget: dp_cap = sigma * <kappa>_active",
        "secondaryTarget: dp_cap = sigma / R_eff_active",
    ]
    for name,pred in suites:
        for target,label in (("target_sigma_kappa","sigmaKappa"),("target_sigma_over_reff","sigmaOverReff")):
            pp=select(pred,target)
            b=slope0(pp)
            ai,bi=free_line(pp)
            lines.append(
                f"{name}.{label}: n={len(pp)} constrainedSlope={b:.8g} "
                f"originFitR2={r2_origin(pp,b):.8g} freeIntercept={ai:.8g} "
                f"freeSlope={bi:.8g} freeR2={r2(pp,ai,bi):.8g}"
            )

    # Secondary no-baseline check at fixed R/h: absolute pressure vs sigma*kappa
    abs20=[(r["target_sigma_kappa"],r["pressure_active"]) for r in paired if abs(r["r_cells"]-20)<1e-12]
    ai,bi=free_line(abs20)
    lines.append(
        f"absoluteSigmaSweep_R20.sigmaKappa: freeIntercept={ai:.8g} "
        f"freeSlope={bi:.8g} R2={r2(abs20,ai,bi):.8g}"
    )
    gains=[r["gain_vs_kappa"] for r in paired]
    lines.append(
        f"pairedGainVsKappa: mean={mean(gains):.8g} seedAndCaseStd={stdev(gains):.8g} "
        f"min={min(gains):.8g} max={max(gains):.8g}"
    )
    lines.append(
        "interpretation: the paired sigma=0 subtraction removes the solved-Q6 gauge/background; "
        "no empirical renormalization of sigma is applied."
    )
    report="\n".join(lines)+"\n"
    (outdir/"young_laplace_paired_report.txt").write_text(report)
    print(report,end="")

    try:
        import matplotlib.pyplot as plt

        fig=plt.figure()
        ax=fig.add_subplot(111)
        x=[r["target_sigma_kappa"] for r in paired]
        y=[r["pressure_capillary_increment"] for r in paired]
        hi=max(x)*1.05
        b=slope0(list(zip(x,y)))
        ax.scatter(x,y)
        ax.plot([0,hi],[0,hi],label="unit slope")
        ax.plot([0,hi],[0,b*hi],label=f"paired fit slope={b:.4f}")
        ax.set_xlabel(r"$\sigma\langle\kappa\rangle$")
        ax.set_ylabel(r"$p(\sigma)-p(0)$")
        ax.legend()
        fig.tight_layout()
        fig.savefig(outdir/"young_laplace_paired_pressure.png",dpi=170)
        plt.close(fig)

        fig=plt.figure()
        ax=fig.add_subplot(111)
        for sig in sorted({r["sigma"] for r in paired}):
            q=[r for r in paired if r["sigma"]==sig]
            ax.scatter([r["r_cells"] for r in q],[r["gain_vs_kappa"] for r in q],label=f"sigma={sig:g}")
        ax.axhline(1.0)
        ax.set_xlabel("R/h")
        ax.set_ylabel(r"$[p(\sigma)-p(0)]/[\sigma\langle\kappa\rangle]$")
        ax.legend(fontsize=8)
        fig.tight_layout()
        fig.savefig(outdir/"young_laplace_paired_gain.png",dpi=170)
        plt.close(fig)
        print(f"[0493x11c-a] plots={outdir/'young_laplace_paired_pressure.png'} {outdir/'young_laplace_paired_gain.png'}")
    except Exception as e:
        print(f"[0493x11c-a] plotting skipped: {e}")

if __name__=="__main__":
    main()

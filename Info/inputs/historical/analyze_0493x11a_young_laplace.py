#!/usr/bin/env python3
"""0493x11a Young--Laplace quantitative analysis.

Uses the *resolved* Q6 pressure potential diagnostic x9e:
  cuda_static_drop_pressure_0493x9e.csv
rather than the imposed capillary boundary value x9d.
No pandas dependency.
"""
from __future__ import annotations
import argparse, csv, math, statistics
from pathlib import Path

def read_rows(p):
    if not p.exists(): raise SystemExit(f"missing {p}")
    with p.open(newline="") as f: r=list(csv.DictReader(f))
    if not r: raise SystemExit(f"empty {p}")
    return r

def fmean(xs):
    xs=[x for x in xs if math.isfinite(x)]
    return statistics.fmean(xs) if xs else math.nan

def sample_std(xs):
    xs=[x for x in xs if math.isfinite(x)]
    return statistics.stdev(xs) if len(xs)>1 else 0.0

def tail(rows, frac):
    n=len(rows)
    i=max(0,min(n-1,int(math.floor(frac*n))))
    return rows[i:]

def F(r,k,default=math.nan):
    try: return float(r[k])
    except Exception: return default

def constrained_slope(pairs):
    sxx=sum(x*x for x,y in pairs if math.isfinite(x) and math.isfinite(y))
    sxy=sum(x*y for x,y in pairs if math.isfinite(x) and math.isfinite(y))
    return sxy/sxx if sxx>0 else math.nan

def free_line(pairs):
    pts=[(x,y) for x,y in pairs if math.isfinite(x) and math.isfinite(y)]
    if len(pts)<2: return math.nan,math.nan
    mx=fmean([x for x,_ in pts]); my=fmean([y for _,y in pts])
    den=sum((x-mx)**2 for x,_ in pts)
    b=sum((x-mx)*(y-my) for x,y in pts)/den if den>0 else math.nan
    a=my-b*mx if math.isfinite(b) else math.nan
    return a,b

def r2_for_line(pairs,a,b):
    pts=[(x,y) for x,y in pairs if math.isfinite(x) and math.isfinite(y)]
    if len(pts)<2:return math.nan
    ym=fmean([y for _,y in pts])
    ss=sum((y-ym)**2 for _,y in pts)
    er=sum((y-(a+b*x))**2 for x,y in pts)
    return 1-er/ss if ss>0 else math.nan

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--manifest",type=Path,required=True)
    ap.add_argument("--output-dir",type=Path,default=None)
    ap.add_argument("--tail-start",type=float,default=0.5,
                    help="fraction of each time series discarded as transient")
    a=ap.parse_args()
    if not (0<=a.tail_start<1): raise SystemExit("--tail-start must be in [0,1)")
    manifest=read_rows(a.manifest)
    outdir=a.output_dir or a.manifest.parent/"analysis"
    outdir.mkdir(parents=True,exist_ok=True)
    run_rows=[]

    for m in manifest:
        run=Path(m["run_dir"])
        p=run/"output/cuda_static_drop_pressure_0493x9e.csv"
        v=run/"output/cuda_static_drop_velocity_0493x9e.csv"
        lim=run/"output/cuda_surface_tension_limiter_0493x9r.csv"
        rr=tail(read_rows(p),a.tail_start)
        sigma=float(m["sigma"]); rc=float(m["r_cells"]); seed=int(m["seed"])
        reff=fmean([F(r,"effectiveRadius") for r in rr])
        target=fmean([F(r,"laplaceTargetCurrent") for r in rr])
        dp=fmean([F(r,"measuredPressureJump") for r in rr])
        kappa=fmean([F(r,"curvatureMean") for r in rr])
        keq=fmean([F(r,"equivalentCurvature") for r in rr])
        alpha_area=fmean([F(r,"alphaArea") for r in rr])
        dp_std=sample_std([F(r,"measuredPressureJump") for r in rr])
        sigma_eff=dp*reff if math.isfinite(dp*reff) else math.nan
        perr=(dp-target)/target if target else math.nan
        kerr=(kappa-keq)/keq if keq else math.nan

        drift=math.nan; cell_rms=math.nan; interface_rms=math.nan
        if v.exists():
            vv=tail(read_rows(v),a.tail_start)
            mvx=fmean([F(r,"liquidMeanVx") for r in vv])
            mvy=fmean([F(r,"liquidMeanVy") for r in vv])
            drift=math.hypot(mvx,mvy)
            cell_rms=fmean([F(r,"liquidSpeedRms") for r in vv])
            interface_rms=fmean([F(r,"interfaceSpeedRms") for r in vv])
        max_clip=0.0
        if lim.exists():
            lr=tail(read_rows(lim),a.tail_start)
            max_clip=max([F(r,"clipFraction",0.0) for r in lr] or [0.0])

        run_rows.append({
            "sigma":sigma,"r_cells":rc,"seed":seed,"run_dir":str(run),
            "tail_rows":len(rr),"alpha_area":alpha_area,"r_eff":reff,
            "equiv_kappa":keq,"curvature_mean":kappa,"curvature_rel_error":kerr,
            "pressure_jump":dp,"pressure_jump_time_std":dp_std,
            "laplace_target":target,"pressure_rel_error":perr,
            "sigma_eff":sigma_eff,"sigma_eff_over_sigma":sigma_eff/sigma if sigma else math.nan,
            "liquid_mean_drift":drift,"liquid_cell_speed_rms":cell_rms,
            "interface_cell_speed_rms":interface_rms,"max_tail_clip_fraction":max_clip
        })

    fields=list(run_rows[0].keys())
    with (outdir/"young_laplace_runs.csv").open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(run_rows)

    groups={}
    for r in run_rows:
        key=(r["sigma"],r["r_cells"])
        groups.setdefault(key,[]).append(r)
    grouped=[]
    for (sig,rc),rs in sorted(groups.items()):
        def g(k): return [float(r[k]) for r in rs if math.isfinite(float(r[k]))]
        grouped.append({
            "sigma":sig,"r_cells":rc,"seeds":len(rs),
            "r_eff_mean":fmean(g("r_eff")),"r_eff_seed_std":sample_std(g("r_eff")),
            "pressure_jump_mean":fmean(g("pressure_jump")),
            "pressure_jump_seed_std":sample_std(g("pressure_jump")),
            "laplace_target_mean":fmean(g("laplace_target")),
            "pressure_rel_error_mean":fmean(g("pressure_rel_error")),
            "pressure_rel_error_seed_std":sample_std(g("pressure_rel_error")),
            "sigma_eff_over_sigma_mean":fmean(g("sigma_eff_over_sigma")),
            "sigma_eff_over_sigma_seed_std":sample_std(g("sigma_eff_over_sigma")),
            "curvature_rel_error_mean":fmean(g("curvature_rel_error")),
            "max_tail_clip_fraction":max(g("max_tail_clip_fraction") or [0.0])
        })
    gf=list(grouped[0].keys())
    with (outdir/"young_laplace_grouped.csv").open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=gf); w.writeheader(); w.writerows(grouped)

    allpairs=[(r["laplace_target"],r["pressure_jump"]) for r in run_rows]
    rpairs=[(r["laplace_target"],r["pressure_jump"]) for r in run_rows if abs(r["sigma"]-1500)<1e-12]
    spairs=[(r["laplace_target"],r["pressure_jump"]) for r in run_rows if abs(r["r_cells"]-20)<1e-12]
    lines=[]
    lines.append("===== 0493x11a YOUNG-LAPLACE QUANTITATIVE VALIDATION =====")
    lines.append(f"runs={len(run_rows)} groupedCases={len(grouped)} tailStart={a.tail_start:g}")
    for name,pairs in (("all",allpairs),("radiusSweep_sigma1500",rpairs),("sigmaSweep_R20",spairs)):
        b0=constrained_slope(pairs)
        ai,bi=free_line(pairs)
        r2=r2_for_line(pairs,ai,bi)
        lines.append(
            f"{name}: constrainedSlope={b0:.8g} freeIntercept={ai:.8g} "
            f"freeSlope={bi:.8g} R2={r2:.8g}"
        )
    errs=[abs(r["pressure_rel_error"]) for r in run_rows if math.isfinite(r["pressure_rel_error"])]
    lines.append(f"meanAbsPressureRelError={fmean(errs):.6g} maxAbsPressureRelError={max(errs):.6g}")
    lines.append(
        "target2D: measuredPressureJump = sigma/R_eff; "
        "R_eff=sqrt(alphaArea/pi); pressure is solved Q6 bulk gauge (x9e), not imposed boundary value."
    )
    lines.append(
        "historicalContext: pre-x10 x9d/x9e campaign reported constrained slope about 0.9575; "
        "the present target remains unit slope without empirical sigma renormalization."
    )
    report="\n".join(lines)+"\n"
    (outdir/"young_laplace_report.txt").write_text(report)
    print(report,end="")

    try:
        import matplotlib.pyplot as plt
        xs=[r["laplace_target"] for r in run_rows]; ys=[r["pressure_jump"] for r in run_rows]
        lo=min(xs+[0.0]); hi=max(xs)*1.05
        fig=plt.figure()
        ax=fig.add_subplot(111)
        ax.scatter(xs,ys)
        ax.plot([lo,hi],[lo,hi],label="unit slope")
        b=constrained_slope(allpairs)
        ax.plot([lo,hi],[b*lo,b*hi],label=f"fit slope={b:.4f}")
        ax.set_xlabel(r"$\sigma/R_{\rm eff}$")
        ax.set_ylabel(r"$\Delta p_{\rm Q6}$")
        ax.legend()
        fig.tight_layout()
        fig.savefig(outdir/"young_laplace_pressure.png",dpi=160)
        plt.close(fig)

        fig=plt.figure()
        ax=fig.add_subplot(111)
        ax.scatter([r["r_cells"] for r in run_rows],
                   [r["sigma_eff_over_sigma"] for r in run_rows])
        ax.axhline(1.0)
        ax.set_xlabel("R/h")
        ax.set_ylabel(r"$\sigma_{\rm eff}/\sigma$")
        fig.tight_layout()
        fig.savefig(outdir/"young_laplace_sigma_eff.png",dpi=160)
        plt.close(fig)
        print(f"[0493x11a] plots={outdir/'young_laplace_pressure.png'} {outdir/'young_laplace_sigma_eff.png'}")
    except Exception as e:
        print(f"[0493x11a] plotting skipped: {e}")

if __name__=="__main__":
    main()

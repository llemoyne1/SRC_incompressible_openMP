#!/usr/bin/env python3
"""0493x11c-b — early/high-SNR capillary-wave refit.

The original x11b fit used almost the entire recorded trace.  After the
capillary mode is damped to the thermal noise floor, that procedure can fit
noise rather than the intended oscillation.  This refinement uses a fixed,
pre-declared physics window of one theoretical period by default and reports
sensitivity to 0.75, 1.00 and 1.25 periods.

Input is the existing x11b ``capillary_wave_cases.csv`` plus its trace CSVs;
no simulation rerun is required.
"""
from __future__ import annotations
import argparse, csv, math, statistics
from pathlib import Path

def read_csv(p):
    if not p.exists():
        raise SystemExit(f"[0493x11c-b] missing {p}")
    with p.open(newline="") as f:
        rows=list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"[0493x11c-b] empty {p}")
    return rows

def mean(x): return statistics.fmean(x) if x else math.nan
def stdev(x): return statistics.stdev(x) if len(x)>1 else 0.0

def solve3(M,b):
    A=[list(map(float,row))+[float(rhs)] for row,rhs in zip(M,b)]
    for i in range(3):
        piv=max(range(i,3),key=lambda r:abs(A[r][i]))
        if abs(A[piv][i])<1e-18:return None
        A[i],A[piv]=A[piv],A[i]
        q=A[i][i]
        for j in range(i,4):A[i][j]/=q
        for r in range(3):
            if r==i:continue
            q=A[r][i]
            for j in range(i,4):A[r][j]-=q*A[i][j]
    return [A[i][3] for i in range(3)]

def linear_fit(t,y,omega,beta):
    cols=[]
    for tt in t:
        e=math.exp(-beta*tt)
        cols.append((e*math.cos(omega*tt),e*math.sin(omega*tt),1.0))
    M=[[sum(c[i]*c[j] for c in cols) for j in range(3)] for i in range(3)]
    b=[sum(c[i]*yy for c,yy in zip(cols,y)) for i in range(3)]
    q=solve3(M,b)
    if q is None:return None
    pred=[q[0]*c[0]+q[1]*c[1]+q[2] for c in cols]
    sse=sum((yy-pp)**2 for yy,pp in zip(y,pred))
    ym=mean(y); sst=sum((yy-ym)**2 for yy in y)
    r2=1-sse/sst if sst>0 else 0.0
    return sse,r2,q,pred

def fit_damped(t_abs,y,omega0):
    t0=t_abs[0]
    t=[q-t0 for q in t_abs]
    wlo,whi=0.60*omega0,1.40*omega0
    blo,bhi=0.0,min(2.5*omega0,10.0)
    best=None
    for refine in range(3):
        nw=121 if refine==0 else 81
        nb=61 if refine==0 else 41
        for iw in range(nw):
            w=wlo+(whi-wlo)*iw/max(1,nw-1)
            for ib in range(nb):
                b=blo+(bhi-blo)*ib/max(1,nb-1)
                r=linear_fit(t,y,w,b)
                if r and (best is None or r[0]<best[0]):
                    best=(r[0],w,b,r[1],r[2],r[3])
        if best is None:
            return None
        _,w,b,_,_,_=best
        dw=(whi-wlo)/max(1,nw-1)*3
        db=(bhi-blo)/max(1,nb-1)*3
        wlo=max(0.10*omega0,w-dw); whi=w+dw
        blo=max(0.0,b-db); bhi=b+db
    return best

def locate_trace(case,cases_csv):
    p=Path(case.get("trace",""))
    candidates=[]
    if p:
        candidates.append(p)
        candidates.append(cases_csv.parent/p.name)
    candidates.append(cases_csv.parent/(case["case"]+"_trace.csv"))
    for q in candidates:
        if q.exists():return q
    raise SystemExit(f"[0493x11c-b] trace not found for {case['case']}; tried: "+", ".join(map(str,candidates)))

def slope0(pairs):
    den=sum(x*x for x,y in pairs)
    return sum(x*y for x,y in pairs)/den if den else math.nan

def fit_window(trace,omega0,periods):
    T=2*math.pi/omega0
    t_start=float(trace[0]["time"])
    t_end=t_start+periods*T
    q=[r for r in trace if float(r["time"])<=t_end+1e-14]
    if len(q)<12:
        raise RuntimeError(f"only {len(q)} frames in {periods:g} theoretical periods")
    tt=[float(r["time"]) for r in q]
    yy=[float(r["modePrimary"]) for r in q]
    best=fit_damped(tt,yy,omega0)
    if best is None: raise RuntimeError("fit failed")
    sse,w,beta,r2,coef,pred=best
    amp=math.hypot(coef[0],coef[1])
    return {"omega":w,"beta":beta,"r2":r2,"coef":coef,"frames":len(q),
            "t_start":tt[0],"t_end":tt[-1],"amp":amp}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--cases-csv",type=Path,required=True)
    ap.add_argument("--output-dir",type=Path,default=None)
    ap.add_argument("--fit-periods",type=float,default=1.0)
    ap.add_argument("--sensitivity-periods",default="0.75,1.0,1.25")
    ap.add_argument("--late-noise-fraction",type=float,default=0.25)
    a=ap.parse_args()
    if a.fit_periods<=0: raise SystemExit("--fit-periods must be positive")
    sens=[float(x) for x in a.sensitivity_periods.split(",") if x.strip()]
    if not sens or any(x<=0 for x in sens): raise SystemExit("invalid --sensitivity-periods")
    if not (0<a.late_noise_fraction<0.5): raise SystemExit("--late-noise-fraction must be in (0,0.5)")

    cases=read_csv(a.cases_csv)
    outdir=a.output_dir or a.cases_csv.parent/"refined"
    outdir.mkdir(parents=True,exist_ok=True)
    rows=[]

    for c in cases:
        omega0=float(c["omega_inviscid_theory"])
        trace_path=locate_trace(c,a.cases_csv)
        tr=read_csv(trace_path)
        primary=[float(r["modePrimary"]) for r in tr]
        nlate=max(8,int(math.ceil(a.late_noise_fraction*len(primary))))
        noise=math.sqrt(mean([x*x for x in primary[-nlate:]]))

        primary_fit=fit_window(tr,omega0,a.fit_periods)
        sensfits=[]
        for p in sens:
            try:
                sf=fit_window(tr,omega0,p)
                sensfits.append((p,sf))
            except Exception:
                pass
        wratios=[sf["omega"]/omega0 for p,sf in sensfits]
        amp_end=primary_fit["amp"]*math.exp(-primary_fit["beta"]*(primary_fit["t_end"]-primary_fit["t_start"]))
        snr0=primary_fit["amp"]/noise if noise>0 else math.inf
        snrend=amp_end/noise if noise>0 else math.inf

        row={
            "case":c["case"],"sigma":float(c["sigma"]),"mode":int(c["mode"]),"seed":int(c["seed"]),
            "omega_theory":omega0,
            "omega_fit_early":primary_fit["omega"],
            "omega_fit_over_theory":primary_fit["omega"]/omega0,
            "omega_rel_error":primary_fit["omega"]/omega0-1.0,
            "beta_fit_early":primary_fit["beta"],
            "fit_R2_early":primary_fit["r2"],
            "fit_periods":a.fit_periods,
            "fit_frames":primary_fit["frames"],
            "fit_t_start":primary_fit["t_start"],"fit_t_end":primary_fit["t_end"],
            "late_noise_rms":noise,
            "fit_amplitude_start":primary_fit["amp"],
            "fit_amplitude_end":amp_end,
            "snr_start":snr0,"snr_end":snrend,
            "window_ratio_mean":mean(wratios),"window_ratio_std":stdev(wratios),
            "window_ratio_min":min(wratios) if wratios else math.nan,
            "window_ratio_max":max(wratios) if wratios else math.nan,
            "sensitivity_windows":len(wratios),
            "trace":str(trace_path),
        }
        if "omega_weak_damped" in c and c["omega_weak_damped"]:
            try:
                ow=float(c["omega_weak_damped"])
                row["omega_weak_damped"]=ow
                row["omega_fit_over_weak_damped"]=primary_fit["omega"]/ow if ow>0 else math.nan
            except Exception:
                row["omega_weak_damped"]=math.nan
                row["omega_fit_over_weak_damped"]=math.nan
        else:
            row["omega_weak_damped"]=math.nan
            row["omega_fit_over_weak_damped"]=math.nan
        rows.append(row)
        print(
            f"[0493x11c-b] {row['case']} omega={row['omega_fit_early']:.8g} "
            f"theory={omega0:.8g} err={100*row['omega_rel_error']:+.3f}% "
            f"R2={row['fit_R2_early']:.5f} fit={a.fit_periods:g}T "
            f"windowStd={100*row['window_ratio_std']:.3f}%"
        )

    with (outdir/"capillary_wave_refined_cases.csv").open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys()));w.writeheader();w.writerows(rows)

    groups={}
    for r in rows:
        groups.setdefault((r["sigma"],r["mode"]),[]).append(r)
    grouped=[]
    for (sig,mode),rs in sorted(groups.items()):
        vals=[r["omega_fit_over_theory"] for r in rs]
        grouped.append({
            "sigma":sig,"mode":mode,"seeds":len(rs),
            "omega_ratio_mean":mean(vals),"omega_ratio_seed_std":stdev(vals),
            "fit_R2_mean":mean([r["fit_R2_early"] for r in rs]),
            "window_ratio_std_mean":mean([r["window_ratio_std"] for r in rs]),
        })
    with (outdir/"capillary_wave_refined_grouped.csv").open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(grouped[0].keys()));w.writeheader();w.writerows(grouped)

    pairs=[(r["omega_theory"]**2,r["omega_fit_early"]**2) for r in rows]
    disp=slope0(pairs)
    ratios=[r["omega_fit_over_theory"] for r in rows]
    lines=[
        "===== 0493x11c-b EARLY/HIGH-SNR CAPILLARY-WAVE VALIDATION =====",
        f"cases={len(rows)} primaryFitWindow={a.fit_periods:g} theoreticalPeriods sensitivity={','.join(map(str,sens))}",
        f"dispersionSlopeOmega2={disp:.8g}",
        f"meanOmegaRatio={mean(ratios):.8g} stdAcrossCases={stdev(ratios):.8g}",
        f"meanFitR2={mean([r['fit_R2_early'] for r in rows]):.8g}",
        f"meanWindowSensitivityStd={mean([r['window_ratio_std'] for r in rows]):.8g}",
        "theory is inherited from x11b: omega^2=(sigma/rho) k^3 tanh(kH).",
        "The fixed early window prevents the long thermal-noise tail from dominating the frequency fit.",
    ]

    idx={(r["mode"],r["seed"],r["sigma"]):r for r in rows}
    scales=[]
    for mode in sorted({r["mode"] for r in rows}):
        for seed in sorted({r["seed"] for r in rows}):
            lo=idx.get((mode,seed,1500.0)); hi=idx.get((mode,seed,4500.0))
            if lo and hi:
                q=hi["omega_fit_early"]/lo["omega_fit_early"]
                scales.append(q)
                lines.append(
                    f"mode={mode} seed={seed} omega4500/omega1500={q:.8g} "
                    f"targetSqrt3={math.sqrt(3):.8g} relErr={(q/math.sqrt(3)-1)*100:+.3f}%"
                )
    if scales:
        lines.append(f"meanSigmaScalingRatio={mean(scales):.8g}")

    report="\n".join(lines)+"\n"
    (outdir/"capillary_wave_refined_report.txt").write_text(report)
    print(report,end="")

    try:
        import matplotlib.pyplot as plt

        fig=plt.figure()
        ax=fig.add_subplot(111)
        x=[r["omega_theory"]**2 for r in rows]
        y=[r["omega_fit_early"]**2 for r in rows]
        hi=max(x)*1.05
        ax.scatter(x,y)
        ax.plot([0,hi],[0,hi],label="unit slope")
        ax.plot([0,hi],[0,disp*hi],label=f"early-fit slope={disp:.4f}")
        ax.set_xlabel(r"$\omega_{\rm theory}^2$")
        ax.set_ylabel(r"$\omega_{\rm early-fit}^2$")
        ax.legend()
        fig.tight_layout()
        fig.savefig(outdir/"capillary_wave_refined_dispersion.png",dpi=170)
        plt.close(fig)

        fig=plt.figure()
        ax=fig.add_subplot(111)
        for r in rows:
            tr=read_csv(Path(r["trace"]))
            T=2*math.pi/r["omega_theory"]
            tt=[float(q["time"])/T for q in tr if float(q["time"])<=1.5*T]
            yy=[float(q["modePrimary"]) for q in tr if float(q["time"])<=1.5*T]
            ax.plot(tt,yy,label=f"s={r['sigma']:g}, n={r['mode']}, seed={r['seed']}")
        ax.axvline(a.fit_periods,linestyle="--")
        ax.set_xlabel(r"$t/T_{\rm theory}$")
        ax.set_ylabel("signed interface Fourier amplitude")
        ax.legend(fontsize=7)
        fig.tight_layout()
        fig.savefig(outdir/"capillary_wave_refined_early_traces.png",dpi=170)
        plt.close(fig)
        print(f"[0493x11c-b] plots={outdir/'capillary_wave_refined_dispersion.png'} {outdir/'capillary_wave_refined_early_traces.png'}")
    except Exception as e:
        print(f"[0493x11c-b] plotting skipped: {e}")

if __name__=="__main__":
    main()

#!/usr/bin/env python3
"""0493x11b capillary-wave dispersion analysis from filtered mass recordings.

No pandas/scipy dependency.  The measured interface-height Fourier coefficient
is reconstructed from alpha ~= clamp(recorded_cell_mass/(gamma*m),0,1).
A damped sinusoid is fitted by a small (omega,beta) grid search; for each pair
the coefficients A*cos + B*sin + C are solved linearly.
"""
from __future__ import annotations
import argparse, csv, json, math, statistics, sys
from array import array
from pathlib import Path

def read_csv(p):
    with p.open(newline="") as f: return list(csv.DictReader(f))

def mean(x): return statistics.fmean(x) if x else math.nan
def std(x): return statistics.stdev(x) if len(x)>1 else 0.0

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

def linear_fit_for(t,y,omega,beta):
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
    # Shift t to improve conditioning; discard no information.
    t0=t_abs[0]; t=[q-t0 for q in t_abs]
    wlo,whi=0.55*omega0,1.45*omega0
    blo,bhi=0.0,min(2.0*omega0,8.0)
    best=None
    for refine in range(3):
        nw=121 if refine==0 else 81
        nb=51 if refine==0 else 41
        for iw in range(nw):
            w=wlo+(whi-wlo)*iw/max(1,nw-1)
            for ib in range(nb):
                b=blo+(bhi-blo)*ib/max(1,nb-1)
                r=linear_fit_for(t,y,w,b)
                if r and (best is None or r[0]<best[0]):
                    best=(r[0],w,b,r[1],r[2],r[3])
        _,w,b,_,_,_=best
        dw=(whi-wlo)/max(1,nw-1)*3
        db=(bhi-blo)/max(1,nb-1)*3
        wlo=max(0.05*omega0,w-dw); whi=w+dw
        blo=max(0.0,b-db); bhi=b+db
    return best

def f32(path,n):
    a=array("f")
    with path.open("rb") as f:a.fromfile(f,n)
    if len(a)!=n: raise RuntimeError(f"{path}: expected {n} floats, got {len(a)}")
    if sys.byteorder=="big":a.byteswap()
    return a

def locate_frames(case_dir):
    timelines=sorted((case_dir/"output/recordings").glob("*/timeline.csv"))
    if not timelines: raise RuntimeError(f"{case_dir}: no recording timeline")
    bystep={}
    for tl in timelines:
        for r in read_csv(tl):
            if r.get("field")!="rho":continue
            step=int(r["step"])
            bystep[step]=(float(r["time"]),int(r["nx"]),int(r["ny"]),tl.parent/r["file"])
    return [(s,)+bystep[s] for s in sorted(bystep)]

def mode_series(case):
    case_dir=Path(case["run_dir"])
    nx=int(case["nx"]); ny=int(case["ny"])
    lx=float(case["Lx"]); ly=float(case["Ly"])
    gamma=float(case["gamma"]); mass=float(case["liquid_mass"])
    mode=int(case["mode"]); k=2*math.pi*mode/lx
    dy=ly/ny; ref=gamma*mass
    frames=locate_frames(case_dir)
    out=[]
    for step,time,fx,fy,path in frames:
        if (fx,fy)!=(nx,ny):
            raise RuntimeError(f"{path}: recorder grid {(fx,fy)} != simulation {(nx,ny)}")
        d=f32(path,nx*ny)
        heights=[0.0]*nx
        for iy in range(ny):
            off=iy*nx
            for ix in range(nx):
                alpha=max(0.0,min(1.0,float(d[off+ix])/ref))
                heights[ix]+=alpha*dy
        c=s=0.0
        for ix,h in enumerate(heights):
            x=(ix+0.5)*lx/nx
            c+=h*math.cos(k*x)
            s+=h*math.sin(k*x)
        c*=2.0/nx; s*=2.0/nx
        out.append((step,time,c,s,mean(heights)))
    return out

def constrained_slope(pairs):
    den=sum(x*x for x,y in pairs); return sum(x*y for x,y in pairs)/den if den else math.nan

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--manifest",type=Path,required=True)
    ap.add_argument("--output-dir",type=Path,default=None)
    ap.add_argument("--skip-time",type=float,default=0.20)
    a=ap.parse_args()
    rows=read_csv(a.manifest)
    if not rows: raise SystemExit("empty manifest")
    outdir=a.output_dir or a.manifest.parent/"analysis"
    outdir.mkdir(parents=True,exist_ok=True)
    summaries=[]

    for case in rows:
        sig=float(case["sigma"]); mode=int(case["mode"])
        lx=float(case["Lx"]); h=float(case["h"]); H=float(case["mean_height"])
        gamma=float(case["gamma"]); m=float(case["liquid_mass"])
        nu=float(case.get("nu_ref") or 0.0)
        rho=gamma*m/(h*h)
        k=2*math.pi*mode/lx
        omega0=math.sqrt((sig/rho)*k**3*math.tanh(k*H))
        beta_weak=2*nu*k*k if nu>0 else math.nan
        omega_weak=math.sqrt(max(0.0,omega0*omega0-beta_weak*beta_weak)) if nu>0 else math.nan

        series=mode_series(case)
        if len(series)<20: raise RuntimeError(f"{case['case']}: too few frames ({len(series)})")
        # Rotate the complex Fourier coefficient onto the initial mode phase.
        c0,s0=series[0][2],series[0][3]
        z0=math.hypot(c0,s0)
        if z0<=0: raise RuntimeError(f"{case['case']}: zero initial Fourier amplitude")
        samples=[]
        for step,t,c,s,Hm in series:
            primary=(c*c0+s*s0)/z0
            quadrature=(-c*s0+s*c0)/z0
            samples.append((step,t,primary,quadrature,Hm,c,s))
        fit=[q for q in samples if q[1]>=a.skip_time]
        if len(fit)<20: fit=samples
        tt=[q[1] for q in fit]; yy=[q[2] for q in fit]
        best=fit_damped(tt,yy,omega0)
        if best is None: raise RuntimeError(f"{case['case']}: fit failed")
        sse,omega,beta,r2,coef,pred=best
        qrms=math.sqrt(mean([q[3]**2 for q in fit]))
        prms=math.sqrt(mean([q[2]**2 for q in fit]))
        depth=mean([q[4] for q in fit])

        # Save the extracted trace to make every fit auditable.
        trace=outdir/f"{case['case']}_trace.csv"
        with trace.open("w",newline="") as f:
            w=csv.writer(f);w.writerow(["step","time","modePrimary","modeQuadrature","meanDepth","cosCoeff","sinCoeff"])
            w.writerows(samples)

        summaries.append({
            "case":case["case"],"sigma":sig,"mode":mode,"seed":int(case["seed"]),
            "k":k,"H":H,"mean_depth_measured":depth,"rho_ref":rho,
            "initial_amplitude_measured":z0,
            "amplitude_over_wavelength":z0/(lx/mode),
            "omega_inviscid_theory":omega0,
            "beta_weak_2nu_k2":beta_weak,
            "omega_weak_damped":omega_weak,
            "omega_fit":omega,"omega_fit_over_theory":omega/omega0,
            "omega_rel_error":(omega-omega0)/omega0,
            "beta_fit":beta,"fit_R2":r2,
            "quadrature_over_primary_rms":qrms/prms if prms>0 else math.nan,
            "frames":len(series),"trace":str(trace)
        })
        print(
            f"[0493x11b] {case['case']} omegaFit={omega:.8g} "
            f"omegaTheory={omega0:.8g} err={100*(omega/omega0-1):+.3f}% "
            f"beta={beta:.6g} R2={r2:.5f} frames={len(series)}"
        )

    fields=list(summaries[0].keys())
    with (outdir/"capillary_wave_cases.csv").open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(summaries)

    # Dispersion regression: omega_fit^2 = slope * [(sigma/rho) k^3 tanh(kH)].
    pairs=[(r["omega_inviscid_theory"]**2,r["omega_fit"]**2) for r in summaries]
    slope=constrained_slope(pairs)
    ratios=[r["omega_fit_over_theory"] for r in summaries]
    report=[
        "===== 0493x11b CAPILLARY-WAVE DISPERSION VALIDATION =====",
        f"cases={len(summaries)} dispersionSlopeOmega2={slope:.8g}",
        f"meanOmegaRatio={mean(ratios):.8g} stdOmegaRatio={std(ratios):.8g}",
        "theory: omega^2=(sigma/rho) k^3 tanh(kH), rho=gamma*m/h^2",
    ]
    # Sigma scaling for matched mode/seed.
    index={(r["mode"],r["seed"],r["sigma"]):r for r in summaries}
    ratio_lines=[]
    for mode in sorted({r["mode"] for r in summaries}):
        for seed in sorted({r["seed"] for r in summaries}):
            lo=index.get((mode,seed,1500.0)); hi=index.get((mode,seed,4500.0))
            if lo and hi:
                rr=hi["omega_fit"]/lo["omega_fit"]
                ratio_lines.append(rr)
                report.append(
                    f"mode={mode} seed={seed} omega4500/omega1500={rr:.8g} "
                    f"targetSqrt3={math.sqrt(3):.8g} relErr={(rr/math.sqrt(3)-1)*100:+.3f}%"
                )
    if ratio_lines:
        report.append(f"meanSigmaScalingRatio={mean(ratio_lines):.8g}")
    txt="\n".join(report)+"\n"
    (outdir/"capillary_wave_report.txt").write_text(txt)
    print(txt,end="")

    try:
        import matplotlib.pyplot as plt
        fig=plt.figure()
        ax=fig.add_subplot(111)
        x=[r["omega_inviscid_theory"]**2 for r in summaries]
        y=[r["omega_fit"]**2 for r in summaries]
        hi=max(x)*1.05
        ax.scatter(x,y)
        ax.plot([0,hi],[0,hi],label="unit slope")
        ax.plot([0,hi],[0,slope*hi],label=f"fit slope={slope:.4f}")
        ax.set_xlabel(r"$(\sigma/\rho)k^3\tanh(kH)$")
        ax.set_ylabel(r"$\omega_{\rm fit}^2$")
        ax.legend()
        fig.tight_layout()
        fig.savefig(outdir/"capillary_wave_dispersion.png",dpi=160)
        plt.close(fig)

        fig=plt.figure()
        ax=fig.add_subplot(111)
        for r in summaries:
            tr=read_csv(Path(r["trace"]))
            ax.plot([float(q["time"]) for q in tr],
                    [float(q["modePrimary"]) for q in tr],
                    label=f"s={r['sigma']:g}, n={r['mode']}, seed={r['seed']}")
        ax.set_xlabel("time"); ax.set_ylabel("signed interface Fourier amplitude")
        ax.legend(fontsize=7)
        fig.tight_layout()
        fig.savefig(outdir/"capillary_wave_traces.png",dpi=160)
        plt.close(fig)
        print(f"[0493x11b] plots={outdir/'capillary_wave_dispersion.png'} {outdir/'capillary_wave_traces.png'}")
    except Exception as e:
        print(f"[0493x11b] plotting skipped: {e}")

if __name__=="__main__":
    main()

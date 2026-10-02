#!/usr/bin/env python3
"""
0493x24y-v3 — Sato h/D vs Fr with explicit forced-time offsets.

Main correction vs v2
---------------------
The first forced x24u segment starts at forced time t=0 even though it restarts
from a relaxed checkpoint whose RESTART_FROM_STEP is nonzero.  Therefore the
hydrodynamic "forced-time" origin must NOT be inferred from RESTART_FROM_STEP.

This v3 requires each segment to be passed as:

    TARGET_FR:FORCED_TIME_OFFSET:RUN_ROOT

Examples for the current chained history:
    x24u  : 0.660364520158346:0.0:<runroot>   -> forced t in [0,2]
    x24v  : 0.660364520158346:2.0:<runroot>   -> forced t in [2,4]
    x24w  : 0.660364520158346:4.0:<runroot>   -> forced t in [4,6]

The same applies to Fr=0.25 for x24u/x24v.

Primary Sato observable
-----------------------
    h/D = (initial bath height - eta_min) / D

Secondary diagnostic
--------------------
    h_far/D = (instantaneous far-field level - eta_min) / D

No pandas.
"""

from __future__ import annotations
import argparse, csv, math, re
from pathlib import Path
from collections import defaultdict

import numpy as np
import matplotlib.pyplot as plt

SATO_SLOPE = 1.30

def fv(x, default=math.nan):
    try:
        y=float(x)
        return y if math.isfinite(y) else default
    except Exception:
        return default

def read_kv(path: Path):
    out={}
    if not path.exists():
        return out
    for line in path.read_text(errors="replace").splitlines():
        s=line.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        k,v=s.split("=",1)
        out[k.strip()]=v.strip()
    return out

def parse_env(root: Path):
    env={}
    for p in sorted((root/"logs").glob("environment_*.env")):
        env.update(read_kv(p))
    return env

def find_manifest(root: Path):
    cands=list((root/"output"/"recordings").glob("**/manifest.kv"))
    return cands[0] if cands else None

def detect_grid(root: Path, nx_default, ny_default):
    man=find_manifest(root)
    if man:
        kv=read_kv(man)
        for kx,ky in [("liveGridNx","liveGridNy"),("Nx","Ny"),("nx","ny")]:
            if kx in kv and ky in kv:
                try:
                    return int(float(kv[kx])), int(float(kv[ky])), kv
                except Exception:
                    pass
    return nx_default, ny_default, {}

def read_summary(root: Path):
    p=root/"analysis"/"sato_stageA_recording_summary.csv"
    if not p.exists():
        return {}
    with p.open(newline="") as h:
        rows=list(csv.DictReader(h))
    return rows[0] if rows else {}

def step_from_name(p: Path):
    m=re.search(r"step_(\d+)_field_rho1\.f32$",p.name)
    return int(m.group(1)) if m else None

def load_f32(path: Path, nx: int, ny: int):
    a=np.fromfile(path,dtype="<f4")
    if a.size != nx*ny:
        raise ValueError(f"{path}: expected {nx*ny} floats, got {a.size}")
    return a.reshape((ny,nx))

def interface_profile_from_rho1(arr, Lx, Ly, threshold):
    ny,nx=arr.shape
    dy=Ly/ny
    eta=np.full(nx,np.nan,float)
    mask=arr>=threshold
    for i in range(nx):
        js=np.flatnonzero(mask[:,i])
        if len(js):
            eta[i]=(js[-1]+0.5)*dy
    return eta

def profile_metrics(eta,Lx,jet_center,jet_width,bath_height):
    nx=len(eta)
    dx=Lx/nx
    xs=(np.arange(nx)+0.5)*dx
    valid=np.isfinite(eta)

    far=eta[
        valid
        & (xs>0.08*Lx) & (xs<0.92*Lx)
        & (np.abs(xs-jet_center)>=3.0*jet_width)
    ]
    eta_far=float(np.median(far)) if len(far) else math.nan

    center=(np.abs(xs-jet_center)<=1.5*jet_width) & valid
    eta_min=float(np.min(eta[center])) if np.any(center) else math.nan

    h_initial=(bath_height-eta_min)/jet_width if math.isfinite(eta_min) else math.nan
    h_far=(eta_far-eta_min)/jet_width if math.isfinite(eta_far) and math.isfinite(eta_min) else math.nan

    half_width=math.nan
    if math.isfinite(eta_far) and math.isfinite(eta_min) and eta_far>eta_min:
        level=eta_far-0.5*(eta_far-eta_min)
        below=valid & (eta<=level)
        ic=int(np.argmin(np.abs(xs-jet_center)))
        if below[ic]:
            il=ic; ir=ic
            while il>0 and below[il-1]: il-=1
            while ir+1<nx and below[ir+1]: ir+=1
            half_width=((ir-il+1)*dx)/jet_width

    return {
        "etaFar":eta_far,
        "etaMin":eta_min,
        "hOverD_initialRef":h_initial,
        "hOverD_farRef":h_far,
        "halfDepthWidthOverD":half_width,
    }

def dedupe_time_series(t,y,prefer="last"):
    """
    Deduplicate identical forced times. Restarts may contain frame 0 / boundary
    frames that coincide exactly with the previous segment endpoint.
    """
    pairs=sorted(zip(t,y),key=lambda z:z[0])
    d={}
    for ti,yi in pairs:
        if prefer=="first" and ti in d:
            continue
        d[ti]=yi
    tt=np.array(sorted(d),float)
    yy=np.array([d[x] for x in tt],float)
    return tt,yy

def dominant_period(t,y):
    t=np.asarray(t,float); y=np.asarray(y,float)
    m=np.isfinite(t)&np.isfinite(y)
    t=t[m]; y=y[m]
    if len(t)<12:
        return math.nan

    t,y=dedupe_time_series(t,y)
    if len(t)<12:
        return math.nan

    dt=np.median(np.diff(t))
    if not (dt>0):
        return math.nan

    tu=np.arange(t[0],t[-1]+0.5*dt,dt)
    yu=np.interp(tu,t,y)

    # detrend linearly before FFT
    a,b=np.polyfit(tu,yu,1)
    yd=yu-(a*tu+b)

    amp=np.abs(np.fft.rfft(yd))
    freq=np.fft.rfftfreq(len(yd),dt)
    if len(amp)<2:
        return math.nan
    amp[0]=0.0

    # ignore periods longer than the available record itself
    k=int(np.argmax(amp))
    return 1/freq[k] if freq[k]>0 else math.nan

def stats_block(t,y):
    t=np.asarray(t,float); y=np.asarray(y,float)
    m=np.isfinite(t)&np.isfinite(y)
    t=t[m]; y=y[m]
    if len(y)==0:
        return {}
    t,y=dedupe_time_series(t,y)
    slope=math.nan
    if len(y)>=2:
        slope=float(np.polyfit(t,y,1)[0])
    return {
        "n":int(len(y)),
        "timeStart":float(np.min(t)),
        "timeEnd":float(np.max(t)),
        "mean":float(np.mean(y)),
        "std":float(np.std(y,ddof=1)) if len(y)>1 else 0.0,
        "min":float(np.min(y)),
        "max":float(np.max(y)),
        "peakToPeak":float(np.ptp(y)),
        "linearSlopePerTime":slope,
        "dominantPeriod":dominant_period(t,y),
    }

def linfit(x,y,through_origin=False):
    x=np.asarray(x,float); y=np.asarray(y,float)
    m=np.isfinite(x)&np.isfinite(y)
    x=x[m]; y=y[m]
    if len(x)<2:
        return math.nan,math.nan,math.nan
    if through_origin:
        a=float(np.dot(x,y)/np.dot(x,x)); b=0.0
    else:
        a,b=np.polyfit(x,y,1); a=float(a); b=float(b)
    yp=a*x+b
    ssr=float(np.sum((y-yp)**2))
    sst=float(np.sum((y-np.mean(y))**2))
    r2=1-ssr/sst if sst>0 else math.nan
    return a,b,r2

ap=argparse.ArgumentParser()
ap.add_argument("--case", action="append", required=True,
                help="TARGET_FR:FORCED_TIME_OFFSET:RUN_ROOT, repeat for each segment")
ap.add_argument("--out", default="analysis/0493x24y_v3")
ap.add_argument("--nx", type=int, default=400)
ap.add_argument("--ny", type=int, default=256)
ap.add_argument("--Lx", type=float, default=1.5625)
ap.add_argument("--Ly", type=float, default=1.0)
ap.add_argument("--jet-center-x", type=float, default=0.78125)
ap.add_argument("--jet-width", type=float, default=0.078125)
ap.add_argument("--bath-height", type=float, default=0.81640625)
ap.add_argument("--rho-threshold", type=float, default=10.0)
ap.add_argument("--transient-cutoff", type=float, default=1.0,
                help="forced-time cutoff applied after explicit segment offsets")
ap.add_argument("--sato-band", type=float, default=0.20)
args=ap.parse_args()

out=Path(args.out)
out.mkdir(parents=True,exist_ok=True)

segments=[]
for spec in args.case:
    parts=spec.split(":",2)
    if len(parts)!=3:
        raise SystemExit(
            f"bad --case '{spec}', expected TARGET_FR:FORCED_TIME_OFFSET:RUN_ROOT"
        )
    frs,offs,rootstr=parts
    fr=float(frs)
    offset=float(offs)
    root=Path(rootstr)
    if not root.exists():
        raise SystemExit(f"missing run root: {root}")

    summary=read_summary(root)
    env=parse_env(root)
    dt=fv(env.get("DT"), fv(summary.get("dt"), 0.0004))
    nx,ny,mankv=detect_grid(root,args.nx,args.ny)

    segments.append({
        "fr":fr,
        "forcedOffset":offset,
        "root":root,
        "summary":summary,
        "env":env,
        "dt":dt,
        "nx":nx,
        "ny":ny,
        "manifest":mankv,
    })

frame_rows=[]
for seg in segments:
    root=seg["root"]
    files=sorted((root/"output"/"recordings").glob("**/step_*_field_rho1.f32"))
    if not files:
        print(f"[0493x24y-v3] WARNING no rho1 recordings under {root}")
        continue

    for p in files:
        st=step_from_name(p)
        if st is None:
            continue

        arr=load_f32(p,seg["nx"],seg["ny"])
        eta=interface_profile_from_rho1(
            arr,args.Lx,args.Ly,args.rho_threshold
        )
        mm=profile_metrics(
            eta,args.Lx,args.jet_center_x,args.jet_width,args.bath_height
        )

        local_t=st*seg["dt"]
        forced_t=seg["forcedOffset"]+local_t

        frame_rows.append({
            "targetFr":seg["fr"],
            "forcedTimeOffset":seg["forcedOffset"],
            "runRoot":str(root),
            "file":str(p),
            "localStep":st,
            "localTime":local_t,
            "forcedTime":forced_t,
            **mm,
        })

if not frame_rows:
    raise SystemExit("no rho1 frames found")

frame_rows.sort(key=lambda r:(r["targetFr"],r["forcedTime"],r["forcedTimeOffset"]))

with (out/"frame_history.csv").open("w",newline="") as h:
    fields=list(frame_rows[0].keys())
    w=csv.DictWriter(h,fieldnames=fields)
    w.writeheader()
    w.writerows(frame_rows)

# Per segment metrics
run_groups=defaultdict(list)
for r in frame_rows:
    run_groups[(r["targetFr"],r["forcedTimeOffset"],r["runRoot"])].append(r)

run_metrics=[]
for (fr,offset,root),rr in sorted(run_groups.items()):
    keep=[r for r in rr if r["forcedTime"]>=args.transient_cutoff]
    if not keep:
        keep=rr

    t=[r["forcedTime"] for r in keep]
    yi=[r["hOverD_initialRef"] for r in keep]
    yf=[r["hOverD_farRef"] for r in keep]

    si=stats_block(t,yi)
    sf=stats_block(t,yf)
    summary=read_summary(Path(root))

    run_metrics.append({
        "targetFr":fr,
        "forcedTimeOffset":offset,
        "runRoot":root,
        "frames":si.get("n",0),
        "timeStart":si.get("timeStart",math.nan),
        "timeEnd":si.get("timeEnd",math.nan),
        "meanHOverD":si.get("mean",math.nan),
        "stdHOverD":si.get("std",math.nan),
        "minHOverD":si.get("min",math.nan),
        "maxHOverD":si.get("max",math.nan),
        "peakToPeakHOverD":si.get("peakToPeak",math.nan),
        "slopeHOverDPerTime":si.get("linearSlopePerTime",math.nan),
        "dominantPeriod":si.get("dominantPeriod",math.nan),
        "meanFarReferencedHOverD":sf.get("mean",math.nan),
        "summaryMeasuredFr":fv(summary.get("meanMeasuredModifiedFroude")),
        "summaryMeasuredFrStd":fv(summary.get("stdMeasuredModifiedFroude")),
    })

with (out/"run_oscillation_metrics.csv").open("w",newline="") as h:
    fields=list(run_metrics[0].keys())
    w=csv.DictWriter(h,fieldnames=fields)
    w.writeheader()
    w.writerows(run_metrics)

# Aggregate by Fr using deduplicated forced-time histories
fr_groups=defaultdict(list)
for r in frame_rows:
    if r["forcedTime"]>=args.transient_cutoff:
        fr_groups[r["targetFr"]].append(r)

agg=[]
for fr in sorted(fr_groups):
    rr=fr_groups[fr]

    # dedupe overlapping boundary frames in forced-time space
    tt=[r["forcedTime"] for r in rr]
    yy=[r["hOverD_initialRef"] for r in rr]
    t,y=dedupe_time_series(tt,yy,prefer="last")

    pred=SATO_SLOPE*fr

    mfr=[]
    mfr_std=[]
    for seg in segments:
        if abs(seg["fr"]-fr)>1e-12:
            continue
        s=seg["summary"]
        a=fv(s.get("meanMeasuredModifiedFroude"))
        b=fv(s.get("stdMeasuredModifiedFroude"))
        if math.isfinite(a): mfr.append(a)
        if math.isfinite(b): mfr_std.append(b)

    agg.append({
        "targetFr":fr,
        "frames":len(y),
        "timeMin":float(np.min(t)),
        "timeMax":float(np.max(t)),
        "meanHOverD":float(np.mean(y)),
        "stdHOverD":float(np.std(y,ddof=1)) if len(y)>1 else 0.0,
        "minHOverD":float(np.min(y)),
        "maxHOverD":float(np.max(y)),
        "peakToPeakHOverD":float(np.ptp(y)),
        "dominantPeriod":dominant_period(t,y),
        "linearSlopePerTime":float(np.polyfit(t,y,1)[0]) if len(y)>=2 else math.nan,
        "satoHOverD":pred,
        "relativeErrorToSato":(float(np.mean(y))-pred)/pred if pred else math.nan,
        "meanMeasuredFr":float(np.mean(mfr)) if mfr else math.nan,
        "stdMeasuredFrAcrossSegments":(
            float(np.std(mfr,ddof=1))
            if len(mfr)>1
            else (mfr_std[0] if len(mfr_std)==1 else math.nan)
        ),
    })

with (out/"fr_relation_aggregate.csv").open("w",newline="") as h:
    fields=list(agg[0].keys())
    w=csv.DictWriter(h,fieldnames=fields)
    w.writeheader()
    w.writerows(agg)

xt=[r["targetFr"] for r in agg]
yy=[r["meanHOverD"] for r in agg]
xm=[r["meanMeasuredFr"] for r in agg]

fit_free=linfit(xt,yy,False)
fit_zero=linfit(xt,yy,True)
fit_mfree=linfit(xm,yy,False)
fit_mzero=linfit(xm,yy,True)

with (out/"report.txt").open("w") as h:
    h.write("0493x24y-v3 — forced-time-corrected Sato h/D vs Fr analysis\n")
    h.write("============================================================\n\n")
    h.write(f"rho1 threshold = {args.rho_threshold:g}\n")
    h.write(f"forced-time transient cutoff = {args.transient_cutoff:g}\n")
    h.write("Primary depth = (initial bath height - minimum cavity height)/D\n")
    h.write("Time origin = explicit FORCED_TIME_OFFSET supplied per segment.\n\n")

    h.write("Aggregate dense-frame results\n")
    h.write("-----------------------------\n")
    for r in agg:
        h.write(
            f"Fr={r['targetFr']:.9g}  "
            f"h/D={r['meanHOverD']:.6g} +/- {r['stdHOverD']:.4g}  "
            f"range=[{r['minHOverD']:.6g},{r['maxHOverD']:.6g}]  "
            f"period~{r['dominantPeriod']:.6g}  "
            f"slope/time={r['linearSlopePerTime']:.6g}  "
            f"Sato={r['satoHOverD']:.6g}  "
            f"err={100*r['relativeErrorToSato']:+.2f}%\n"
        )

    h.write("\nFits versus TARGET Fr\n")
    h.write(
        f"free:   h/D = {fit_free[0]:.8g} Fr + "
        f"{fit_free[1]:+.8g}; R2={fit_free[2]:.8g}\n"
    )
    h.write(
        f"origin: h/D = {fit_zero[0]:.8g} Fr; "
        f"R2={fit_zero[2]:.8g}\n"
    )
    h.write(f"Sato:   h/D = {SATO_SLOPE:.8g} Fr\n")

    h.write("\nFits versus measured Fr proxy\n")
    h.write(
        f"free:   h/D = {fit_mfree[0]:.8g} Fr_meas + "
        f"{fit_mfree[1]:+.8g}; R2={fit_mfree[2]:.8g}\n"
    )
    h.write(
        f"origin: h/D = {fit_mzero[0]:.8g} Fr_meas; "
        f"R2={fit_mzero[2]:.8g}\n"
    )

# Plot 1: time histories with explicit forced time
fig,ax=plt.subplots(figsize=(9.2,5.6))
for fr in sorted(set(r["targetFr"] for r in frame_rows)):
    rr=[r for r in frame_rows if r["targetFr"]==fr]
    tt=[r["forcedTime"] for r in rr]
    yyf=[r["hOverD_initialRef"] for r in rr]
    t,y=dedupe_time_series(tt,yyf,prefer="last")
    order=np.argsort(t)
    ax.plot(t[order],y[order],label=f"Fr'={fr:g}")
ax.axvline(
    args.transient_cutoff,
    linestyle="--",
    alpha=0.6,
    label="transient cutoff",
)
ax.set_xlabel("Forced physical time")
ax.set_ylabel("Cavity depth h/D")
ax.grid(True,alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out/"h_over_D_time_series.png",dpi=180)
plt.close(fig)

# Plot 2: target Fr
fig,ax=plt.subplots(figsize=(7.6,5.4))
xx=np.linspace(0,max(xt)*1.08,300)
ax.fill_between(
    xx,
    SATO_SLOPE*xx*(1-args.sato_band),
    SATO_SLOPE*xx*(1+args.sato_band),
    alpha=0.18,
    label=f"Sato ±{int(args.sato_band*100)}%",
)
ax.plot(xx,SATO_SLOPE*xx,label="Sato: h/D = 1.30 Fr'")
ax.errorbar(
    xt,yy,
    yerr=[r["stdHOverD"] for r in agg],
    fmt="o",
    capsize=4,
    label="SRC/MPCD dense-time mean",
)
ax.plot(
    xx,
    fit_zero[0]*xx,
    "--",
    label=f"SRC fit through 0: {fit_zero[0]:.3f} Fr'",
)
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel("Cavity depth h/D")
ax.grid(True,alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out/"h_over_D_vs_target_Fr.png",dpi=180)
plt.close(fig)

# Plot 3: measured Fr
valid=[r for r in agg if math.isfinite(r["meanMeasuredFr"])]
if len(valid)>=2:
    fig,ax=plt.subplots(figsize=(7.6,5.4))
    xv=[r["meanMeasuredFr"] for r in valid]
    yv=[r["meanHOverD"] for r in valid]
    xe=[
        r["stdMeasuredFrAcrossSegments"]
        if math.isfinite(r["stdMeasuredFrAcrossSegments"])
        else 0.0
        for r in valid
    ]
    ye=[r["stdHOverD"] for r in valid]

    ax.errorbar(xv,yv,xerr=xe,yerr=ye,fmt="o",capsize=4)
    xxm=np.linspace(0,max(xv)*1.1,300)
    ax.plot(
        xxm,
        fit_mzero[0]*xxm,
        "--",
        label=f"fit through 0: {fit_mzero[0]:.3f} Fr_meas",
    )
    ax.set_xlabel("Measured incident modified Froude proxy")
    ax.set_ylabel("Cavity depth h/D")
    ax.grid(True,alpha=0.25)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out/"h_over_D_vs_measured_Fr.png",dpi=180)
    plt.close(fig)

print(f"[0493x24y-v3] wrote {out/'frame_history.csv'}")
print(f"[0493x24y-v3] wrote {out/'run_oscillation_metrics.csv'}")
print(f"[0493x24y-v3] wrote {out/'fr_relation_aggregate.csv'}")
print(f"[0493x24y-v3] wrote {out/'report.txt'}")
print(f"[0493x24y-v3] wrote {out/'h_over_D_time_series.png'}")
print(f"[0493x24y-v3] wrote {out/'h_over_D_vs_target_Fr.png'}")

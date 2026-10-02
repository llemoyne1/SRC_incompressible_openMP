#!/usr/bin/env python3
"""
0493x24y-v2 — Sato h/D vs Fr analysis with dense rho1-recording reconstruction.

Purpose
-------
Build the article-grade h/D vs Fr relation using:
  1) sato_stageA_recording_summary.csv files for run metadata / Fr values;
  2) dense recorded rho1 .f32 fields to reconstruct h/D(t) frame by frame;
  3) oscillation-aware statistics after a user-chosen transient cutoff.

Key principle
-------------
For comparison with Sato, h is measured from the INITIAL bath level:
    h(t) = bath_height - eta_min(t)
not from the instantaneous far-field level.

The analyzer also reports the instantaneous far-field-referenced depth as a
secondary diagnostic, but it is NOT used for the primary Sato fit.

No pandas.

Outputs
-------
  frame_history.csv
  run_oscillation_metrics.csv
  fr_relation_aggregate.csv
  report.txt
  h_over_D_vs_target_Fr.png
  h_over_D_vs_measured_Fr.png
  h_over_D_time_series.png

Typical current use
-------------------
python3 scripts/analyze_0493x24y_v2_sato_relation_dense_recordings.py \
  --case 0.25:runs/0493x24u_sato_stageA_short_M033_seed493205/Fr0p25/restart_short_stageA_screen \
  --case 0.40:runs/0493x24u_sato_stageA_short_M033_seed493205/Fr0p40/restart_short_stageA_screen \
  --case 0.55:runs/0493x24u_sato_stageA_short_M033_seed493205/Fr0p55/restart_short_stageA_screen \
  --case 0.660364520158346:runs/0493x24u_sato_stageA_short_M033_seed493205/Fr0p660364520158346/restart_short_stageA_screen \
  --case 0.25:runs/0493x24v_sato_stageA_two_endpoints_extend_seed493205/Fr0p25/restart_extend_t2_to_t4 \
  --case 0.660364520158346:runs/0493x24v_sato_stageA_two_endpoints_extend_seed493205/Fr0p660364520158346/restart_extend_t2_to_t4 \
  --case 0.660364520158346:runs/0493x24w_sato_stageA_Fr0p660_extend_t4_to_t6_seed493205/restart_extend_t4_to_t6 \
  --out analysis/0493x24y_v2

Notes
-----
- Each --case is TARGET_FR:RUN_ROOT.
- The script auto-detects recordings under:
      RUN_ROOT/output/recordings/record_step_*/step_*_field_rho1.f32
  and recursively below output/recordings.
- It also reads manifest.kv when present.
- Global time across restart segments is reconstructed from environment_*.env
  RESTART_FROM_STEP when available. If not available, local step is used.
"""

from __future__ import annotations
import argparse, csv, math, re, statistics
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
    # liquid is below free surface; take highest y-cell with rho1 >= threshold
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

def dominant_period(t,y):
    t=np.asarray(t,float); y=np.asarray(y,float)
    m=np.isfinite(t)&np.isfinite(y)
    t=t[m]; y=y[m]
    if len(t)<12:
        return math.nan
    order=np.argsort(t); t=t[order]; y=y[order]
    keep=np.r_[True,np.diff(t)>1e-14]
    t=t[keep]; y=y[keep]
    if len(t)<12:
        return math.nan
    # resample to uniform grid if needed
    dt=np.median(np.diff(t))
    if not (dt>0):
        return math.nan
    tu=np.arange(t[0],t[-1]+0.5*dt,dt)
    yu=np.interp(tu,t,y)
    a,b=np.polyfit(tu,yu,1)
    yd=yu-(a*tu+b)
    amp=np.abs(np.fft.rfft(yd))
    freq=np.fft.rfftfreq(len(yd),dt)
    if len(amp)<2:
        return math.nan
    amp[0]=0
    k=int(np.argmax(amp))
    return 1/freq[k] if freq[k]>0 else math.nan

def stats_block(t,y):
    t=np.asarray(t,float); y=np.asarray(y,float)
    m=np.isfinite(t)&np.isfinite(y)
    t=t[m]; y=y[m]
    if len(y)==0:
        return {}
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
                help="TARGET_FR:RUN_ROOT, repeat for each segment")
ap.add_argument("--out", default="analysis/0493x24y_v2")
ap.add_argument("--nx", type=int, default=400)
ap.add_argument("--ny", type=int, default=256)
ap.add_argument("--Lx", type=float, default=1.5625)
ap.add_argument("--Ly", type=float, default=1.0)
ap.add_argument("--jet-center-x", type=float, default=0.78125)
ap.add_argument("--jet-width", type=float, default=0.078125)
ap.add_argument("--bath-height", type=float, default=0.81640625)
ap.add_argument("--rho-threshold", type=float, default=10.0)
ap.add_argument("--transient-cutoff", type=float, default=1.0,
                help="global physical time before which frames are excluded")
ap.add_argument("--sato-band", type=float, default=0.20)
args=ap.parse_args()

out=Path(args.out); out.mkdir(parents=True,exist_ok=True)

segments=[]
for spec in args.case:
    if ":" not in spec:
        raise SystemExit(f"bad --case '{spec}', expected TARGET_FR:RUN_ROOT")
    frs,rootstr=spec.split(":",1)
    fr=float(frs); root=Path(rootstr)
    if not root.exists():
        raise SystemExit(f"missing run root: {root}")
    summary=read_summary(root)
    env=parse_env(root)
    restart_from=int(float(env.get("RESTART_FROM_STEP",0))) if env.get("RESTART_FROM_STEP","") else 0
    dt=fv(env.get("DT"), fv(summary.get("dt"), 0.0004))
    nx,ny,mankv=detect_grid(root,args.nx,args.ny)
    segments.append({
        "fr":fr,"root":root,"summary":summary,"env":env,
        "restartFrom":restart_from,"dt":dt,"nx":nx,"ny":ny,"manifest":mankv
    })

frame_rows=[]
for seg in segments:
    root=seg["root"]; fr=seg["fr"]; nx=seg["nx"]; ny=seg["ny"]
    files=sorted((root/"output"/"recordings").glob("**/step_*_field_rho1.f32"))
    if not files:
        print(f"[0493x24y-v2] WARNING no rho1 recordings under {root}")
        continue
    for p in files:
        st=step_from_name(p)
        if st is None:
            continue
        arr=load_f32(p,nx,ny)
        eta=interface_profile_from_rho1(arr,args.Lx,args.Ly,args.rho_threshold)
        mm=profile_metrics(eta,args.Lx,args.jet_center_x,args.jet_width,args.bath_height)
        local_t=st*seg["dt"]
        global_step=seg["restartFrom"]+st
        global_t=global_step*seg["dt"]
        frame_rows.append({
            "targetFr":fr,
            "runRoot":str(root),
            "file":str(p),
            "localStep":st,
            "globalStep":global_step,
            "localTime":local_t,
            "globalTime":global_t,
            **mm
        })

if not frame_rows:
    raise SystemExit("no rho1 frames found")

frame_rows.sort(key=lambda r:(r["targetFr"],r["globalTime"],r["runRoot"]))

with (out/"frame_history.csv").open("w",newline="") as h:
    fields=list(frame_rows[0].keys())
    w=csv.DictWriter(h,fieldnames=fields); w.writeheader(); w.writerows(frame_rows)

# Per-run/segment metrics
run_groups=defaultdict(list)
for r in frame_rows:
    run_groups[(r["targetFr"],r["runRoot"])].append(r)

run_metrics=[]
for (fr,root),rr in sorted(run_groups.items()):
    keep=[r for r in rr if r["globalTime"]>=args.transient_cutoff]
    if not keep: keep=rr
    t=[r["globalTime"] for r in keep]
    yi=[r["hOverD_initialRef"] for r in keep]
    yf=[r["hOverD_farRef"] for r in keep]
    si=stats_block(t,yi); sf=stats_block(t,yf)
    summary=read_summary(Path(root))
    run_metrics.append({
        "targetFr":fr,
        "runRoot":root,
        "frames":len(keep),
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
    w=csv.DictWriter(h,fieldnames=fields); w.writeheader(); w.writerows(run_metrics)

# Aggregate by target Fr using all retained dense frames
fr_groups=defaultdict(list)
for r in frame_rows:
    if r["globalTime"]>=args.transient_cutoff:
        fr_groups[r["targetFr"]].append(r)

agg=[]
for fr in sorted(fr_groups):
    rr=fr_groups[fr]
    y=np.array([r["hOverD_initialRef"] for r in rr],float)
    t=np.array([r["globalTime"] for r in rr],float)
    mean=float(np.mean(y)); sd=float(np.std(y,ddof=1)) if len(y)>1 else 0.0
    pred=SATO_SLOPE*fr

    # summary-measured Fr pooled across segments for this target
    mfr=[]; mfrs=[]
    for seg in segments:
        if abs(seg["fr"]-fr)>1e-12: continue
        s=seg["summary"]
        a=fv(s.get("meanMeasuredModifiedFroude"))
        b=fv(s.get("stdMeasuredModifiedFroude"))
        if math.isfinite(a): mfr.append(a)
        if math.isfinite(b): mfrs.append(b)

    agg.append({
        "targetFr":fr,
        "frames":len(y),
        "timeMin":float(np.min(t)),
        "timeMax":float(np.max(t)),
        "meanHOverD":mean,
        "stdHOverD":sd,
        "minHOverD":float(np.min(y)),
        "maxHOverD":float(np.max(y)),
        "peakToPeakHOverD":float(np.ptp(y)),
        "dominantPeriod":dominant_period(t,y),
        "satoHOverD":pred,
        "relativeErrorToSato":(mean-pred)/pred if pred else math.nan,
        "meanMeasuredFr":float(np.mean(mfr)) if mfr else math.nan,
        "stdMeasuredFrAcrossSegments":float(np.std(mfr,ddof=1)) if len(mfr)>1 else (mfrs[0] if len(mfrs)==1 else math.nan),
    })

with (out/"fr_relation_aggregate.csv").open("w",newline="") as h:
    fields=list(agg[0].keys())
    w=csv.DictWriter(h,fieldnames=fields); w.writeheader(); w.writerows(agg)

xt=[r["targetFr"] for r in agg]; yy=[r["meanHOverD"] for r in agg]
xm=[r["meanMeasuredFr"] for r in agg]
fit_free=linfit(xt,yy,False)
fit_zero=linfit(xt,yy,True)
fit_mfree=linfit(xm,yy,False)
fit_mzero=linfit(xm,yy,True)

with (out/"report.txt").open("w") as h:
    h.write("0493x24y-v2 — dense-recording Sato h/D vs Fr analysis\n")
    h.write("======================================================\n\n")
    h.write(f"rho1 threshold = {args.rho_threshold:g}\n")
    h.write(f"transient cutoff global time = {args.transient_cutoff:g}\n")
    h.write("Primary depth = (initial bath height - minimum cavity height)/D\n\n")
    h.write("Aggregate dense-frame results\n")
    h.write("-----------------------------\n")
    for r in agg:
        h.write(
            f"Fr={r['targetFr']:.9g}  h/D={r['meanHOverD']:.6g} +/- {r['stdHOverD']:.4g}  "
            f"range=[{r['minHOverD']:.6g},{r['maxHOverD']:.6g}]  "
            f"period~{r['dominantPeriod']:.6g}  "
            f"Sato={r['satoHOverD']:.6g}  err={100*r['relativeErrorToSato']:+.2f}%\n"
        )
    h.write("\nFits versus TARGET Fr\n")
    h.write(f"free:   h/D = {fit_free[0]:.8g} Fr + {fit_free[1]:+.8g}; R2={fit_free[2]:.8g}\n")
    h.write(f"origin: h/D = {fit_zero[0]:.8g} Fr; R2={fit_zero[2]:.8g}\n")
    h.write(f"Sato:   h/D = {SATO_SLOPE:.8g} Fr\n")
    h.write("\nFits versus measured Fr proxy\n")
    h.write(f"free:   h/D = {fit_mfree[0]:.8g} Fr_meas + {fit_mfree[1]:+.8g}; R2={fit_mfree[2]:.8g}\n")
    h.write(f"origin: h/D = {fit_mzero[0]:.8g} Fr_meas; R2={fit_mzero[2]:.8g}\n")

# Figure: relation vs target Fr
fig,ax=plt.subplots(figsize=(7.6,5.4))
xx=np.linspace(0,max(xt)*1.08,300)
ax.fill_between(xx,SATO_SLOPE*xx*(1-args.sato_band),SATO_SLOPE*xx*(1+args.sato_band),
                alpha=0.18,label=f"Sato ±{int(args.sato_band*100)}%")
ax.plot(xx,SATO_SLOPE*xx,label="Sato: h/D = 1.30 Fr'")
ax.errorbar(xt,yy,yerr=[r["stdHOverD"] for r in agg],fmt="o",capsize=4,label="SRC/MPCD dense-time mean")
ax.plot(xx,fit_zero[0]*xx,"--",label=f"SRC fit through 0: {fit_zero[0]:.3f} Fr'")
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel("Cavity depth h/D")
ax.grid(True,alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out/"h_over_D_vs_target_Fr.png",dpi=180)
plt.close(fig)

# Figure: relation vs measured Fr
valid=[r for r in agg if math.isfinite(r["meanMeasuredFr"])]
if len(valid)>=2:
    fig,ax=plt.subplots(figsize=(7.6,5.4))
    xv=[r["meanMeasuredFr"] for r in valid]
    yv=[r["meanHOverD"] for r in valid]
    xe=[r["stdMeasuredFrAcrossSegments"] if math.isfinite(r["stdMeasuredFrAcrossSegments"]) else 0 for r in valid]
    ye=[r["stdHOverD"] for r in valid]
    ax.errorbar(xv,yv,xerr=xe,yerr=ye,fmt="o",capsize=4)
    xxm=np.linspace(0,max(xv)*1.1,300)
    ax.plot(xxm,fit_mzero[0]*xxm,"--",label=f"fit through 0: {fit_mzero[0]:.3f} Fr_meas")
    ax.set_xlabel("Measured incident modified Froude proxy")
    ax.set_ylabel("Cavity depth h/D")
    ax.grid(True,alpha=0.25)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out/"h_over_D_vs_measured_Fr.png",dpi=180)
    plt.close(fig)

# Figure: time histories
fig,ax=plt.subplots(figsize=(9.2,5.6))
for fr in sorted(set(r["targetFr"] for r in frame_rows)):
    rr=[r for r in frame_rows if r["targetFr"]==fr]
    rr.sort(key=lambda r:r["globalTime"])
    ax.plot([r["globalTime"] for r in rr],[r["hOverD_initialRef"] for r in rr],label=f"Fr'={fr:g}")
ax.axvline(args.transient_cutoff,linestyle="--",alpha=0.6,label="transient cutoff")
ax.set_xlabel("Global physical time")
ax.set_ylabel("Cavity depth h/D")
ax.grid(True,alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out/"h_over_D_time_series.png",dpi=180)
plt.close(fig)

print(f"[0493x24y-v2] wrote {out/'frame_history.csv'}")
print(f"[0493x24y-v2] wrote {out/'run_oscillation_metrics.csv'}")
print(f"[0493x24y-v2] wrote {out/'fr_relation_aggregate.csv'}")
print(f"[0493x24y-v2] wrote {out/'report.txt'}")
print(f"[0493x24y-v2] wrote {out/'h_over_D_time_series.png'}")
print(f"[0493x24y-v2] wrote {out/'h_over_D_vs_target_Fr.png'}")

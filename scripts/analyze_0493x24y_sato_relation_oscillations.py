#!/usr/bin/env python3
"""
0493x24y — Sato h/D vs Fr analysis with oscillation-aware aggregation.

No pandas. Uses only csv/numpy/matplotlib from the standard project Python stack.

What it does
------------
1. Collects one or more sato_stageA_recording_summary.csv files.
2. Groups repeated windows/segments belonging to the same target Fr.
3. Computes:
   - sample-weighted mean h/D and pooled scatter,
   - Sato Stage-A prediction 1.30 Fr,
   - residuals to Sato,
   - free-intercept and through-origin fits versus TARGET Fr,
   - equivalent fits versus measured Fr.
4. If a run root contains a dense time-history CSV in analysis/, it automatically
   looks for a CSV with columns step/time plus depthOverJetWidth (or depth + jet width
   supplied through --jet-width) and estimates:
   - oscillation mean/std/peak-to-peak,
   - dominant period from FFT,
   - linear secular slope after removing the mean.
5. Writes CSV/TXT and two PNG figures.

Typical use for the current campaign
------------------------------------
python3 scripts/analyze_0493x24y_sato_relation_oscillations.py \
  --summary runs/0493x24u_sato_stageA_short_M033_seed493205/Fr0p25/restart_short_stageA_screen/analysis/sato_stageA_recording_summary.csv \
  --summary runs/0493x24u_sato_stageA_short_M033_seed493205/Fr0p40/restart_short_stageA_screen/analysis/sato_stageA_recording_summary.csv \
  --summary runs/0493x24u_sato_stageA_short_M033_seed493205/Fr0p55/restart_short_stageA_screen/analysis/sato_stageA_recording_summary.csv \
  --summary runs/0493x24u_sato_stageA_short_M033_seed493205/Fr0p660364520158346/restart_short_stageA_screen/analysis/sato_stageA_recording_summary.csv \
  --summary runs/0493x24v_sato_stageA_two_endpoints_extend_seed493205/Fr0p25/restart_extend_t2_to_t4/analysis/sato_stageA_recording_summary.csv \
  --summary runs/0493x24v_sato_stageA_two_endpoints_extend_seed493205/Fr0p660364520158346/restart_extend_t2_to_t4/analysis/sato_stageA_recording_summary.csv \
  --summary runs/0493x24w_sato_stageA_Fr0p660_extend_t4_to_t6_seed493205/restart_extend_t4_to_t6/analysis/sato_stageA_recording_summary.csv \
  --out analysis/0493x24y_sato_relation

Add the x24x Fr=0.75 summary with one more --summary when available.
"""

import argparse, csv, math
from pathlib import Path
from collections import defaultdict

import numpy as np
import matplotlib.pyplot as plt

SATO_SLOPE = 1.30

def f(x, default=math.nan):
    try:
        y=float(x)
        return y if math.isfinite(y) else default
    except Exception:
        return default

def read_one_summary(path):
    p=Path(path)
    with p.open(newline="") as h:
        rows=list(csv.DictReader(h))
    if not rows:
        raise ValueError(f"empty summary: {p}")
    r=rows[0]
    return {
        "path": str(p),
        "runRoot": r.get("runRoot",""),
        "targetFr": f(r.get("targetModifiedFroude")),
        "measuredFr": f(r.get("meanMeasuredModifiedFroude")),
        "measuredFrStd": f(r.get("stdMeasuredModifiedFroude")),
        "h": f(r.get("meanDepthOverJetWidth")),
        "hStd": f(r.get("stdDepthOverJetWidth")),
        "relativeFarH": f(r.get("meanRelativeFarDepthOverJetWidth")),
        "farShift": f(r.get("meanFarFieldLevelShiftOverJetWidth")),
        "samples": int(f(r.get("analysisSamples"),1)),
        "slopePerStep": f(r.get("depthSlopePerStep")),
        "relDrift": f(r.get("relativeDepthDriftAcrossWindow")),
        "lateMinusEarly": f(r.get("relativeLateMinusEarlyHalfMean")),
        "status": r.get("stabilityStatus",""),
        "incidentRho": f(r.get("meanIncidentGasMassDensity")),
        "incidentVy": f(r.get("meanIncidentGasMeanVy")),
        "incidentStress": f(r.get("meanIncidentAdvectiveStress")),
        "symmetry": f(r.get("meanSymmetryRmsRel")),
    }

def weighted_mean(vals, weights):
    a=[(v,w) for v,w in zip(vals,weights) if math.isfinite(v) and w>0]
    if not a: return math.nan
    sw=sum(w for _,w in a)
    return sum(v*w for v,w in a)/sw

def pooled_stats(rows, key, stdkey=None):
    vals=[]; weights=[]
    for r in rows:
        v=r[key]; n=max(1,r["samples"])
        if math.isfinite(v):
            vals.append(v); weights.append(n)
    if not vals: return math.nan,math.nan,0
    mu=weighted_mean(vals,weights)
    N=sum(weights)
    if stdkey:
        # pooled second moment across windows
        num=0.0
        for r in rows:
            v=r[key]; s=r.get(stdkey,math.nan); n=max(1,r["samples"])
            if not math.isfinite(v): continue
            within=(n-1)*s*s if math.isfinite(s) and n>1 else 0.0
            num += within + n*(v-mu)**2
        sd=math.sqrt(num/max(1,N-1))
    else:
        sd=math.sqrt(sum(w*(v-mu)**2 for v,w in zip(vals,weights))/max(1,N-1))
    return mu,sd,N

def linfit(x,y,through_origin=False):
    x=np.asarray(x,float); y=np.asarray(y,float)
    m=np.isfinite(x)&np.isfinite(y)
    x=x[m]; y=y[m]
    if len(x)<2: return (math.nan,math.nan,math.nan)
    if through_origin:
        a=float(np.dot(x,y)/np.dot(x,x)); b=0.0
    else:
        a,b=np.polyfit(x,y,1)
        a=float(a); b=float(b)
    yp=a*x+b
    ssr=float(np.sum((y-yp)**2))
    sst=float(np.sum((y-np.mean(y))**2))
    r2=1-ssr/sst if sst>0 else math.nan
    return a,b,r2

def detect_history(run_root, jet_width=None):
    root=Path(run_root)
    adir=root/"analysis"
    if not adir.is_dir():
        return None
    candidates=[]
    for p in sorted(adir.glob("*.csv")):
        try:
            with p.open(newline="") as h:
                rd=csv.DictReader(h)
                fields=rd.fieldnames or []
                if "step" not in fields and "time" not in fields:
                    continue
                score=0
                if "depthOverJetWidth" in fields: score+=100
                if "depth" in fields: score+=30
                if "etaFar" in fields: score+=10
                if "incidentGasMeanVy" in fields: score+=5
                if score:
                    candidates.append((score,p,fields))
        except Exception:
            pass
    if not candidates:
        return None
    _,p,fields=max(candidates,key=lambda z:z[0])
    rows=[]
    with p.open(newline="") as h:
        for r in csv.DictReader(h):
            t=f(r.get("time"))
            step=f(r.get("step"))
            if not math.isfinite(t) and math.isfinite(step):
                t=step
            if "depthOverJetWidth" in r:
                hd=f(r.get("depthOverJetWidth"))
            elif "depth" in r and jet_width and jet_width>0:
                hd=f(r.get("depth"))/jet_width
            else:
                hd=math.nan
            if math.isfinite(t) and math.isfinite(hd):
                rows.append((t,hd))
    if len(rows)<5:
        return None
    rows.sort()
    return p, np.array([x[0] for x in rows]), np.array([x[1] for x in rows])

def oscillation_metrics(t,y):
    if len(t)<8: return {}
    # remove duplicate times and sort
    order=np.argsort(t); t=t[order]; y=y[order]
    keep=np.r_[True,np.diff(t)>0]
    t=t[keep]; y=y[keep]
    if len(t)<8: return {}
    # linear trend
    a,b=np.polyfit(t,y,1)
    detr=y-(a*t+b)
    dt=np.median(np.diff(t))
    if not (dt>0): return {}
    freq=np.fft.rfftfreq(len(detr),dt)
    amp=np.abs(np.fft.rfft(detr))
    if len(amp)>1:
        amp[0]=0.0
        k=int(np.argmax(amp))
        period=1/freq[k] if freq[k]>0 else math.nan
    else:
        period=math.nan
    return {
        "timeStart":float(t[0]), "timeEnd":float(t[-1]),
        "mean":float(np.mean(y)), "std":float(np.std(y,ddof=1)),
        "min":float(np.min(y)), "max":float(np.max(y)),
        "peakToPeak":float(np.ptp(y)),
        "linearSlopePerTime":float(a),
        "dominantPeriod":float(period),
        "n":len(y),
    }

ap=argparse.ArgumentParser()
ap.add_argument("--summary", action="append", required=True,
                help="path to sato_stageA_recording_summary.csv; repeat")
ap.add_argument("--out", default="analysis/0493x24y_sato_relation")
ap.add_argument("--jet-width", type=float, default=0.078125,
                help="needed only when a history has depth but not depthOverJetWidth")
ap.add_argument("--sato-band", type=float, default=0.20)
args=ap.parse_args()

out=Path(args.out); out.mkdir(parents=True,exist_ok=True)
rows=[read_one_summary(p) for p in args.summary]

# --- per-window CSV
with (out/"window_metrics.csv").open("w",newline="") as h:
    fields=list(rows[0].keys())
    w=csv.DictWriter(h,fieldnames=fields); w.writeheader(); w.writerows(rows)

# --- aggregate by target Fr
groups=defaultdict(list)
for r in rows:
    groups[r["targetFr"]].append(r)

agg=[]
for fr in sorted(groups):
    g=groups[fr]
    hmu,hsd,N=pooled_stats(g,"h","hStd")
    fmu,fsd,_=pooled_stats(g,"measuredFr","measuredFrStd")
    rfar,rfarsd,_=pooled_stats(g,"relativeFarH",None)
    stress,stresssd,_=pooled_stats(g,"incidentStress",None)
    vy,vysd,_=pooled_stats(g,"incidentVy",None)
    pred=SATO_SLOPE*fr
    agg.append({
        "targetFr":fr,
        "windows":len(g),
        "samples":N,
        "meanHOverD":hmu,
        "stdHOverD":hsd,
        "satoHOverD":pred,
        "relativeErrorToSato":(hmu-pred)/pred if pred else math.nan,
        "meanMeasuredFr":fmu,
        "stdMeasuredFr":fsd,
        "meanMeasuredFrOverTarget":fmu/fr if fr else math.nan,
        "meanRelativeFarHOverD":rfar,
        "meanIncidentAdvectiveStress":stress,
        "meanIncidentVy":vy,
    })

with (out/"fr_relation_aggregate.csv").open("w",newline="") as h:
    fields=list(agg[0].keys())
    w=csv.DictWriter(h,fieldnames=fields); w.writeheader(); w.writerows(agg)

xt=[r["targetFr"] for r in agg]; yy=[r["meanHOverD"] for r in agg]
xm=[r["meanMeasuredFr"] for r in agg]
fit_free=linfit(xt,yy,False)
fit_zero=linfit(xt,yy,True)
fit_meas_free=linfit(xm,yy,False)
fit_meas_zero=linfit(xm,yy,True)

# --- optional history/oscillation discovery
osc=[]
seen=set()
for r in rows:
    rr=r["runRoot"]
    if not rr or rr in seen: continue
    seen.add(rr)
    got=detect_history(rr,args.jet_width)
    if got is None: continue
    p,t,y=got
    m=oscillation_metrics(t,y)
    if not m: continue
    m.update({"runRoot":rr,"historyFile":str(p),"targetFr":r["targetFr"]})
    osc.append(m)

if osc:
    fields=["runRoot","historyFile","targetFr","timeStart","timeEnd","n","mean","std","min","max",
            "peakToPeak","linearSlopePerTime","dominantPeriod"]
    with (out/"oscillation_metrics.csv").open("w",newline="") as h:
        w=csv.DictWriter(h,fieldnames=fields); w.writeheader(); w.writerows(osc)

# --- report
with (out/"report.txt").open("w") as h:
    h.write("0493x24y — Sato h/D vs Fr, oscillation-aware analysis\n")
    h.write("=====================================================\n\n")
    h.write("Observable used for Sato comparison: meanDepthOverJetWidth,\n")
    h.write("i.e. depth from the initial bath-height reference, not the instantaneous far-field level.\n\n")
    h.write("Aggregate points\n")
    h.write("----------------\n")
    for r in agg:
        h.write(f"Fr_target={r['targetFr']:.9g}  h/D={r['meanHOverD']:.6g} +/- {r['stdHOverD']:.3g}  "
                f"Sato={r['satoHOverD']:.6g}  err={100*r['relativeErrorToSato']:+.2f}%  "
                f"Fr_measured={r['meanMeasuredFr']:.6g}\n")
    h.write("\nFits versus TARGET Fr\n")
    h.write(f"free:   h/D = {fit_free[0]:.8g} Fr + {fit_free[1]:+.8g}; R2={fit_free[2]:.8g}\n")
    h.write(f"origin: h/D = {fit_zero[0]:.8g} Fr; R2={fit_zero[2]:.8g}\n")
    h.write(f"Sato:   h/D = {SATO_SLOPE:.8g} Fr\n")
    h.write("\nFits versus MEASURED Fr\n")
    h.write(f"free:   h/D = {fit_meas_free[0]:.8g} Fr_meas + {fit_meas_free[1]:+.8g}; R2={fit_meas_free[2]:.8g}\n")
    h.write(f"origin: h/D = {fit_meas_zero[0]:.8g} Fr_meas; R2={fit_meas_zero[2]:.8g}\n")
    if osc:
        h.write("\nDetected time histories\n")
        h.write("-----------------------\n")
        for m in osc:
            h.write(f"Fr={m['targetFr']:.6g} {m['runRoot']}: "
                    f"mean={m['mean']:.6g} std={m['std']:.6g} p2p={m['peakToPeak']:.6g} "
                    f"slope/time={m['linearSlopePerTime']:.6g} period~{m['dominantPeriod']:.6g}\n")
    else:
        h.write("\nNo dense h/D time-history CSV was auto-detected; summary-window aggregation only.\n")

# --- figure 1 relation
fig,ax=plt.subplots(figsize=(7.4,5.2))
x=np.linspace(0,max(xt)*1.08,300)
ax.fill_between(x,SATO_SLOPE*x*(1-args.sato_band),SATO_SLOPE*x*(1+args.sato_band),
                alpha=0.18,label=f"Sato ±{int(100*args.sato_band)}%")
ax.plot(x,SATO_SLOPE*x,label="Sato: h/D = 1.30 Fr'")
ax.errorbar(xt,yy,yerr=[r["stdHOverD"] for r in agg],fmt="o",capsize=4,label="SRC/MPCD aggregate")
ax.plot(x,fit_zero[0]*x,"--",label=f"SRC fit through 0: {fit_zero[0]:.3f} Fr'")
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel("Cavity depth h/D")
ax.grid(True,alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out/"h_over_D_vs_target_Fr.png",dpi=180)
plt.close(fig)

# --- figure 2 measured Fr
fig,ax=plt.subplots(figsize=(7.4,5.2))
ax.errorbar(xm,yy,xerr=[r["stdMeasuredFr"] for r in agg],
            yerr=[r["stdHOverD"] for r in agg],fmt="o",capsize=4)
xx=np.linspace(0,max(xm)*1.1,300)
ax.plot(xx,fit_meas_zero[0]*xx,"--",label=f"fit through 0: {fit_meas_zero[0]:.3f} Fr_meas")
ax.set_xlabel("Measured incident modified Froude proxy")
ax.set_ylabel("Cavity depth h/D")
ax.grid(True,alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out/"h_over_D_vs_measured_Fr.png",dpi=180)
plt.close(fig)

print(f"[0493x24y] wrote {out/'report.txt'}")
print(f"[0493x24y] wrote {out/'fr_relation_aggregate.csv'}")
print(f"[0493x24y] wrote {out/'h_over_D_vs_target_Fr.png'}")
print(f"[0493x24y] wrote {out/'h_over_D_vs_measured_Fr.png'}")
if osc:
    print(f"[0493x24y] wrote {out/'oscillation_metrics.csv'}")
